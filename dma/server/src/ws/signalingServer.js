const WebSocket = require('ws');
const url = require('url');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const { registerOrUpdateDevice, markDeviceOffline, getDevicesList, storeScreenshot } = require('../db/mongo');

const agentSockets = new Map();
const viewerSockets = new Map();

async function findAgentSocketAsync(targetId) {
  if (!targetId) return null;
  if (agentSockets.has(targetId)) return agentSockets.get(targetId);

  const cleanTarget = targetId.toLowerCase();

  // 1. Direct match by deviceId, hostname, or substring
  for (const [id, socket] of agentSockets.entries()) {
    const cleanId = id.toLowerCase();
    const host = (socket.hostname || '').toLowerCase();

    if (
      cleanId === cleanTarget ||
      cleanId.includes(cleanTarget) ||
      cleanTarget.includes(cleanId) ||
      (host && (cleanTarget.includes(host) || host.includes(cleanTarget)))
    ) {
      return socket;
    }
  }

  // 2. Resolve targetId (hex MongoDB ID) -> hostname via getDevicesList()
  try {
    const devices = await getDevicesList();
    const targetDev = devices.find(d => 
      (d.deviceId && d.deviceId.toLowerCase() === cleanTarget) || 
      (d.hostname && d.hostname.toLowerCase() === cleanTarget)
    );

    if (targetDev && targetDev.hostname) {
      const devHost = targetDev.hostname.toLowerCase();
      for (const [id, socket] of agentSockets.entries()) {
        const cleanId = id.toLowerCase();
        const host = (socket.hostname || '').toLowerCase();
        if (host === devHost || cleanId.includes(devHost)) {
          return socket;
        }
      }
    }
  } catch (e) {}

  // 3. Fallback: if only 1 agent socket exists, return it
  if (agentSockets.size === 1) {
    return agentSockets.values().next().value;
  }

  return null;
}

async function getViewerSocketsForAgentAsync(agentWs) {
  const matchingViewers = new Set();
  if (!agentWs) return matchingViewers;

  const agentId = (agentWs.deviceId || '').toLowerCase();
  const agentHost = (agentWs.hostname || '').toLowerCase();

  for (const [targetId, vSet] of viewerSockets.entries()) {
    const cleanTarget = targetId.toLowerCase();

    if (
      cleanTarget === agentId ||
      cleanTarget === agentHost ||
      (agentId && agentId.includes(cleanTarget)) ||
      (agentHost && (cleanTarget.includes(agentHost) || agentHost.includes(cleanTarget)))
    ) {
      for (const vWs of vSet) matchingViewers.add(vWs);
    } else {
      // Resolve hex targetId via database
      try {
        const devices = await getDevicesList();
        const targetDev = devices.find(d => 
          (d.deviceId && d.deviceId.toLowerCase() === cleanTarget) || 
          (d.hostname && d.hostname.toLowerCase() === cleanTarget)
        );

        if (targetDev && targetDev.hostname) {
          const devHost = targetDev.hostname.toLowerCase();
          if (devHost === agentHost || agentId.includes(devHost)) {
            for (const vWs of vSet) matchingViewers.add(vWs);
          }
        }
      } catch (e) {}
    }
  }

  // Fallback: If only 1 viewer group is active, route to it
  if (matchingViewers.size === 0 && viewerSockets.size === 1) {
    for (const vSet of viewerSockets.values()) {
      for (const vWs of vSet) matchingViewers.add(vWs);
    }
  }

  return matchingViewers;
}

function initWebSocketServer(server) {
  const wss = new WebSocket.Server({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    const parsedUrl = url.parse(request.url, true);
    const pathname = parsedUrl.pathname;

    if (
      pathname === '/agent' ||
      pathname === '/ws/agent' ||
      pathname === '/viewer' ||
      pathname === '/ws/viewer'
    ) {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    } else {
      socket.destroy();
    }
  });

  wss.on('connection', (ws, request) => {
    const parsedUrl = url.parse(request.url, true);
    const pathname = parsedUrl.pathname;
    const query = parsedUrl.query;

    if (pathname === '/agent' || pathname === '/ws/agent') {
      handleAgentConnection(ws, query, request);
    } else if (pathname === '/viewer' || pathname === '/ws/viewer') {
      handleViewerConnection(ws, query, request);
    }
  });

  console.log('[WebSocket] EktaDMA Signaling Server active on /agent and /viewer');
}

function disconnectOldDeviceIfLoggedElsewhere(updatedInfo) {
  if (updatedInfo && updatedInfo.previousDeviceIdToDisconnect) {
    const oldId = updatedInfo.previousDeviceIdToDisconnect;
    const oldSocket = agentSockets.get(oldId);
    if (oldSocket && oldSocket.readyState === WebSocket.OPEN) {
      try {
        console.log(`[SingleLogin] Terminating active WebSocket session for old device: ${oldId}`);
        oldSocket.send(JSON.stringify({
          type: 'FORCE_LOGOUT',
          reason: 'LOGGED_IN_ON_ANOTHER_DEVICE'
        }));
        oldSocket.close();
      } catch (e) {}
      agentSockets.delete(oldId);
      markDeviceOffline(oldId);
    }
  }
}

function handleAgentConnection(ws, query, request) {
  const deviceId = query.deviceId || query.hostname || `AGENT-${Date.now()}`;
  const clientIp = request.headers['x-forwarded-for'] || request.socket.remoteAddress || '127.0.0.1';

  ws.deviceId = deviceId;
  ws.hostname = query.hostname || query.machineName || deviceId;
  console.log(`[WebSocket] Agent connected: ${deviceId} (${ws.hostname} @ ${clientIp})`);

  if (agentSockets.has(deviceId)) {
    try {
      const oldSocket = agentSockets.get(deviceId);
      if (oldSocket && oldSocket !== ws && oldSocket.readyState === WebSocket.OPEN) {
        oldSocket.close();
      }
    } catch (e) {}
  }

  agentSockets.set(deviceId, ws);

  const updatedDev = registerOrUpdateDevice(deviceId, {
    hostname: ws.hostname,
    ipAddress: clientIp,
    currentUser: query.user || query.employeeName,
    businessId: query.businessId || query.orgId || query.companyId
  });
  disconnectOldDeviceIfLoggedElsewhere(updatedDev);

  ws.on('message', async (message) => {
    const isBuffer = Buffer.isBuffer(message);
    const isJpegFrame = isBuffer && (message.length > 200 || (message[0] === 0xFF && message[1] === 0xD8));

    if (isJpegFrame) {
      const now = Date.now();
      if (!ws.lastSnapTs || (now - ws.lastSnapTs > 10000)) {
        ws.lastSnapTs = now;
        try {
          const base64Str = 'data:image/jpeg;base64,' + message.toString('base64');
          storeScreenshot({
            deviceId: ws.deviceId,
            hostname: ws.hostname,
            currentUser: ws.currentUser || 'EktaHR Employee',
            businessId: ws.businessId || 'default',
            timestamp: new Date().toISOString(),
            imageBase64: base64Str
          });
        } catch (e) {}
      }

      const targetViewers = await getViewerSocketsForAgentAsync(ws);
      for (const viewerWs of targetViewers) {
        if (viewerWs.readyState === WebSocket.OPEN) {
          viewerWs.send(message, { binary: true });
        }
      }
    } else {
      try {
        const text = message.toString();
        const data = JSON.parse(text);

        if (data.type === 'HEARTBEAT') {
          const hbDev = registerOrUpdateDevice(deviceId, {
            hostname: data.hostname || data.machineName,
            currentUser: data.currentUser,
            businessId: data.businessId || query.businessId || query.orgId || query.companyId,
            status: data.status || (data.isPaused ? 'PAUSED' : 'ONLINE'),
            ipAddress: clientIp
          });
          disconnectOldDeviceIfLoggedElsewhere(hbDev);
        } else if (data.type === 'RESOLUTION_INFO') {
          const targetViewers = await getViewerSocketsForAgentAsync(ws);
          for (const vWs of targetViewers) {
            if (vWs.readyState === WebSocket.OPEN) {
              vWs.send(text);
            }
          }
        }
      } catch (err) {
        console.error('[WebSocket] Error processing agent text message:', err.message);
      }
    }
  });

  ws.on('close', () => {
    console.log(`[WebSocket] Agent disconnected: ${deviceId}`);
    if (agentSockets.get(deviceId) === ws) {
      agentSockets.delete(deviceId);
      markDeviceOffline(deviceId);

      for (const [vId, vSet] of viewerSockets.entries()) {
        for (const vWs of vSet) {
          if (vWs.readyState === WebSocket.OPEN) {
            vWs.send(JSON.stringify({ type: 'AGENT_OFFLINE', deviceId }));
          }
        }
      }
    }
  });
}

async function handleViewerConnection(ws, query, request) {
  const targetDeviceId = query.targetDeviceId || query.deviceId;
  if (!targetDeviceId) {
    ws.close(1008, 'Missing deviceId parameter');
    return;
  }

  console.log(`[WebSocket] Admin Viewer connected to device: ${targetDeviceId}`);

  if (!viewerSockets.has(targetDeviceId)) {
    viewerSockets.set(targetDeviceId, new Set());
  }
  viewerSockets.get(targetDeviceId).add(ws);

  const agentWs = await findAgentSocketAsync(targetDeviceId);

  if (agentWs && agentWs.readyState === WebSocket.OPEN) {
    console.log(`[WebSocket] Sending START_STREAM to agent ${agentWs.hostname || targetDeviceId}`);
    agentWs.send(JSON.stringify({ type: 'START_STREAM', quality: 'high' }));
  } else {
    console.log(`[WebSocket] Agent socket not found for target ${targetDeviceId}`);
  }

  ws.on('message', async (message) => {
    try {
      const text = message.toString();
      const liveAgentWs = await findAgentSocketAsync(targetDeviceId);
      if (liveAgentWs && liveAgentWs.readyState === WebSocket.OPEN) {
        liveAgentWs.send(text);
      }
    } catch (err) {
      console.error('[WebSocket] Error relaying control input to agent:', err);
    }
  });

  ws.on('close', async () => {
    console.log(`[WebSocket] Admin Viewer disconnected from device: ${targetDeviceId}`);
    const viewers = viewerSockets.get(targetDeviceId);
    if (viewers) {
      viewers.delete(ws);
      if (viewers.size === 0) {
        viewerSockets.delete(targetDeviceId);
        const liveAgentWs = await findAgentSocketAsync(targetDeviceId);
        if (liveAgentWs && liveAgentWs.readyState === WebSocket.OPEN) {
          liveAgentWs.send(JSON.stringify({ type: 'STOP_STREAM' }));
        }
      }
    }
  });
}

module.exports = { initWebSocketServer };
