const WebSocket = require('ws');
const url = require('url');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const { registerOrUpdateDevice, markDeviceOffline, getDevicesList } = require('../db/mongo');
const idleTracker = require('../db/idleTracker');
const { allowLanUpgrade } = require('../lanGuard');
const { IDLE_THRESHOLD_SECONDS, IS_ONLINE } = require('../config');
const { verifyToken, isAdminUser } = require('../controllers/authController');
const { updateOfferFor } = require('../agentUpdate');
const { getPrivacySites } = require('../privacySites');
const { isSuperScope } = require('../storage/fileStore');

const agentSockets = new Map();
const UPDATE_RECHECK_MS = 10 * 60 * 1000;

// Central settings, so agents follow them without being rebuilt: the idle time (.env) and the company's
// personal websites (hidden in screenshots / live view). privacySites goes last and '|'-separated: the
// agent's JSON reader takes one plain string value per key.
function sendConfig(ws) {
  ws.configBusinessId = ws.businessId || '';
  if (ws.readyState !== WebSocket.OPEN) return;
  try {
    ws.send(JSON.stringify({
      type: 'CONFIG',
      idleThresholdSeconds: IDLE_THRESHOLD_SECONDS,
      privacySites: getPrivacySites(ws.businessId).sites.join('|')
    }));
  } catch (e) {}
}

// A company's personal-website list changed: send it to its connected agents now (the default list
// can apply to any company, so a super admin's change goes to every agent)
function pushAgentConfig(businessId) {
  for (const socket of agentSockets.values()) {
    if (isSuperScope(businessId) || String(socket.businessId || '') === String(businessId)) sendConfig(socket);
  }
}

// Offer a newer agent (once per version per connection); re-checked every 10 minutes, so a newly
// published agent reaches PCs that are already connected
function offerAgentUpdate(ws) {
  ws.updateCheckedAt = Date.now();
  const offer = updateOfferFor(ws.agentVersion);
  if (!offer || ws.offeredVersion === offer.version || ws.readyState !== WebSocket.OPEN) return;
  ws.offeredVersion = offer.version;
  try {
    ws.send(JSON.stringify(offer));
    console.log(`[Update] Offered agent ${offer.version} to ${ws.deviceId} (has ${ws.agentVersion})`);
  } catch (e) {}
}
const viewerSockets = new Map();

// A viewer reaches only the agents of its own company (super admins reach all)
function sameBusiness(viewerWs, agentWs) {
  if (!viewerWs || !agentWs) return false;
  if (viewerWs.isSuper) return true;
  return !!viewerWs.businessId && String(agentWs.businessId || '') === viewerWs.businessId;
}

async function findAgentSocketAsync(targetId, viewerWs) {
  if (!targetId) return null;
  const candidates = [...agentSockets.entries()].filter(([, socket]) => sameBusiness(viewerWs, socket));
  const exact = candidates.find(([id]) => id === targetId);
  if (exact) return exact[1];

  const cleanTarget = targetId.toLowerCase();

  // 1. Direct match by deviceId, hostname, or substring
  for (const [id, socket] of candidates) {
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
      for (const [id, socket] of candidates) {
        const cleanId = id.toLowerCase();
        const host = (socket.hostname || '').toLowerCase();
        if (host === devHost || cleanId.includes(devHost)) {
          return socket;
        }
      }
    }
  } catch (e) {}

  // 3. Fallback: if only 1 agent socket of this company exists, return it
  if (candidates.length === 1) {
    return candidates[0][1];
  }

  return null;
}

async function getViewerSocketsForAgentAsync(agentWs) {
  const matchingViewers = new Set();
  if (!agentWs) return matchingViewers;

  const agentId = (agentWs.deviceId || '').toLowerCase();
  const agentHost = (agentWs.hostname || '').toLowerCase();
  const unresolvedGroups = [];

  for (const [targetId, group] of viewerSockets.entries()) {
    const vSet = new Set();
    for (const vWs of group) {
      if (!sameBusiness(vWs, agentWs)) continue;
      // A viewer that already found its agent matches on the agent's deviceId (no lookup per frame)
      if (vWs.agentDeviceId) {
        if (vWs.agentDeviceId === agentWs.deviceId) matchingViewers.add(vWs);
      } else {
        vSet.add(vWs);
      }
    }
    if (vSet.size === 0) continue;
    unresolvedGroups.push(vSet);
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

  // Fallback: If only 1 viewer group of this company is waiting for its agent, route to it
  if (matchingViewers.size === 0 && unresolvedGroups.length === 1) {
    for (const vWs of unresolvedGroups[0]) matchingViewers.add(vWs);
  }

  return matchingViewers;
}

function initWebSocketServer(server) {
  const wss = new WebSocket.Server({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    if (!allowLanUpgrade(request, socket)) return;
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
      idleTracker.closeForDevice(oldId, 'logged_in_elsewhere');
    }
  }
}

// Behind the online server's reverse proxy the socket address is the proxy's; show the PC's public IP (display only)
function agentIp(request) {
  const forwarded = IS_ONLINE ? String(request.headers['x-forwarded-for'] || '').split(',')[0].trim() : '';
  return (forwarded || request.socket.remoteAddress || '127.0.0.1').replace(/^::ffff:/, '');
}

function handleAgentConnection(ws, query, request) {
  const deviceId = query.deviceId || query.hostname || `AGENT-${Date.now()}`;
  const clientIp = agentIp(request);

  // The agent's DMA token (from /api/device/register). Required on the online server, where the
  // employee and company come from the token, never from the query string or heartbeats.
  const auth = verifyToken(query.token);
  if (IS_ONLINE && !auth) {
    console.warn(`[WebSocket] Rejected agent ${deviceId} @ ${clientIp}: missing or invalid token`);
    ws.close(4401, 'Unauthorized');
    return;
  }

  ws.deviceId = deviceId;
  ws.hostname = query.hostname || query.machineName || deviceId;
  ws.clientIp = clientIp;
  ws.connectedAt = new Date();
  ws.authUser = auth;
  ws.currentUser = auth ? auth.username : (query.user || query.employeeName);
  ws.businessId = auth ? String(auth.businessId) : (query.businessId || query.orgId || query.companyId);
  // A LAN server only sees office PCs; on the online server the agent says whether it also reached an office LAN server
  ws.network = !IS_ONLINE || query.network === 'LAN' ? 'LAN' : 'ONLINE';
  // Agents from before auto-update report no version
  ws.agentVersion = query.version || '';
  console.log(`[WebSocket] Agent connected: ${deviceId} (${ws.hostname} @ ${clientIp}, ${ws.network}, agent ${ws.agentVersion || 'old'})`);

  if (agentSockets.has(deviceId)) {
    try {
      const oldSocket = agentSockets.get(deviceId);
      if (oldSocket && oldSocket !== ws && oldSocket.readyState === WebSocket.OPEN) {
        oldSocket.close();
      }
    } catch (e) {}
  }

  agentSockets.set(deviceId, ws);

  sendConfig(ws);
  offerAgentUpdate(ws);

  const updatedDev = registerOrUpdateDevice(deviceId, {
    hostname: ws.hostname,
    ipAddress: clientIp,
    currentUser: ws.currentUser,
    businessId: ws.businessId,
    network: ws.network,
    // A (re)connected agent is online; don't inherit OFFLINE from its last disconnect
    status: 'ONLINE'
  });
  disconnectOldDeviceIfLoggedElsewhere(updatedDev);

  ws.on('message', async (message, isBinary) => {
    // ws delivers text frames as Buffers too, so use the frame type — a long heartbeat
    // (long active-window title) must not be mistaken for a screen frame
    const isJpegFrame = isBinary && Buffer.isBuffer(message) && message.length > 2 && message[0] === 0xFF && message[1] === 0xD8;

    if (isJpegFrame) {
      // Live frames are relayed only; saved screenshots come from the agent (every 5 min + when idle > 5 min)
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
          if (!ws.authUser) {
            if (data.currentUser) ws.currentUser = data.currentUser;
            if (data.businessId || query.businessId) ws.businessId = data.businessId || query.businessId;
          }
          if (IS_ONLINE) ws.network = data.network === 'LAN' ? 'LAN' : 'ONLINE';
          if (data.version) ws.agentVersion = data.version;
          // Company first known from a heartbeat (older office agents): resend its personal-website list
          if ((ws.businessId || '') !== ws.configBusinessId) sendConfig(ws);
          if (Date.now() - (ws.updateCheckedAt || 0) > UPDATE_RECHECK_MS) offerAgentUpdate(ws);

          const hbDev = registerOrUpdateDevice(deviceId, {
            hostname: data.hostname || data.machineName,
            currentUser: ws.currentUser,
            businessId: ws.businessId || query.orgId || query.companyId,
            network: ws.network,
            status: data.status || (data.isPaused ? 'PAUSED' : 'ONLINE'),
            ipAddress: clientIp
          });
          disconnectOldDeviceIfLoggedElsewhere(hbDev);

          idleTracker.trackStatus(deviceId, {
            status: data.status || (data.isPaused ? 'PAUSED' : 'ONLINE'),
            idleSeconds: data.idleSeconds,
            currentUser: ws.currentUser || query.user,
            businessId: ws.businessId || query.orgId || query.companyId,
            hostname: data.hostname || data.machineName || ws.hostname
          });
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
      idleTracker.closeForDevice(deviceId, 'agent_disconnected');

      // Tell only the viewers watching this PC (not every company's viewers)
      for (const [vId, vSet] of viewerSockets.entries()) {
        for (const vWs of vSet) {
          const watching = vWs.agentDeviceId ? vWs.agentDeviceId === deviceId : vId === deviceId;
          if (watching && sameBusiness(vWs, ws) && vWs.readyState === WebSocket.OPEN) {
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

  // Admin Console token (?token=): company admins only, and only their own company's PCs
  const viewer = verifyToken(query.token);
  if (!isAdminUser(viewer)) {
    console.warn(`[WebSocket] Rejected viewer for ${targetDeviceId}: missing or invalid admin token`);
    ws.close(4401, 'Unauthorized');
    return;
  }
  ws.businessId = String(viewer.businessId);
  ws.isSuper = viewer.role === 'SUPER_ADMIN';

  console.log(`[WebSocket] Admin Viewer ${viewer.username} connected to device: ${targetDeviceId}`);

  if (!viewerSockets.has(targetDeviceId)) {
    viewerSockets.set(targetDeviceId, new Set());
  }
  viewerSockets.get(targetDeviceId).add(ws);

  const agentWs = await findAgentSocketAsync(targetDeviceId, ws);

  if (agentWs && agentWs.readyState === WebSocket.OPEN) {
    ws.agentDeviceId = agentWs.deviceId;
    console.log(`[WebSocket] Sending START_STREAM to agent ${agentWs.hostname || targetDeviceId}`);
    agentWs.send(JSON.stringify({ type: 'START_STREAM', quality: 'high' }));
  } else {
    console.log(`[WebSocket] Agent socket not found for target ${targetDeviceId}`);
  }

  ws.on('message', async (message) => {
    try {
      const text = message.toString();
      const resolved = ws.agentDeviceId && agentSockets.get(ws.agentDeviceId);
      const liveAgentWs = resolved && sameBusiness(ws, resolved) ? resolved : await findAgentSocketAsync(targetDeviceId, ws);
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
        const liveAgentWs = await findAgentSocketAsync(targetDeviceId, ws);
        if (liveAgentWs && liveAgentWs.readyState === WebSocket.OPEN) {
          liveAgentWs.send(JSON.stringify({ type: 'STOP_STREAM' }));
        }
      }
    }
  });
}

// Agents with an open WebSocket right now: deviceId -> { hostname, ipAddress, connectedAt, network, agentVersion }
function getConnectedAgents() {
  const connected = new Map();
  for (const [id, socket] of agentSockets.entries()) {
    if (socket.readyState === WebSocket.OPEN) {
      connected.set(id, { hostname: socket.hostname, ipAddress: socket.clientIp, connectedAt: socket.connectedAt, network: socket.network, agentVersion: socket.agentVersion });
    }
  }
  return connected;
}

// An admin is watching / controlling a screen right now (updates wait until they are done)
function hasActiveViewers() {
  for (const group of viewerSockets.values()) {
    for (const vWs of group) if (vWs.readyState === WebSocket.OPEN) return true;
  }
  return false;
}

module.exports = { initWebSocketServer, getConnectedAgents, hasActiveViewers, pushAgentConfig };
