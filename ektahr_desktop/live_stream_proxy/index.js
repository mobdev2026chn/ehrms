require('dotenv').config();
const http = require('http');
const express = require('express');
const cors = require('cors');
const WebSocket = require('ws');
const url = require('url');

const PORT = process.env.PORT || 9003;
const BACKEND_URL = process.env.MONITORING_BACKEND_URL || 'http://localhost:9002';

const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
    res.json({ ok: true, activeDevices: agentSockets.size, activeSessions: viewerSockets.size });
});

const server = http.createServer(app);
const wss = new WebSocket.Server({ noServer: true });

// Data structures for routing streams
// deviceId -> WebSocket (Agent socket)
const agentSockets = new Map();

// deviceId -> Set<WebSocket> (Viewer sockets)
const deviceViewers = new Map();

// liveSessionId -> metadata { deviceId, quality, fps, frameCount, lastFpsCalc, resolution }
const activeSessions = new Map();

// Handle HTTP upgrade to WebSocket
server.on('upgrade', (request, socket, head) => {
    const parsedUrl = url.parse(request.url, true);
    const pathname = parsedUrl.pathname;
    const query = parsedUrl.query;

    if (pathname === '/agent' || pathname === '/ws/agent') {
        const deviceId = query.deviceId;
        if (!deviceId) {
            socket.destroy();
            return;
        }
        wss.handleUpgrade(request, socket, head, (ws) => {
            ws.clientType = 'agent';
            ws.deviceId = deviceId;
            wss.emit('connection', ws, request);
        });
    } else if (pathname === '/viewer' || pathname === '/ws/viewer') {
        const deviceId = query.deviceId;
        const liveSessionId = query.liveSessionId;
        if (!deviceId || !liveSessionId) {
            socket.destroy();
            return;
        }
        wss.handleUpgrade(request, socket, head, (ws) => {
            ws.clientType = 'viewer';
            ws.deviceId = deviceId;
            ws.liveSessionId = liveSessionId;
            ws.quality = query.quality || 'high';
            wss.emit('connection', ws, request);
        });
    } else {
        socket.destroy();
    }
});

wss.on('connection', (ws) => {
    if (ws.clientType === 'agent') {
        handleAgentConnection(ws);
    } else if (ws.clientType === 'viewer') {
        handleViewerConnection(ws);
    }
});

function handleAgentConnection(ws) {
    const deviceId = ws.deviceId;
    console.log(`[Proxy] Agent connected: ${deviceId}`);

    // Store agent socket
    agentSockets.set(deviceId, ws);

    // If viewers were already waiting for this device, request stream start
    const viewers = deviceViewers.get(deviceId);
    if (viewers && viewers.size > 0) {
        notifyAgentStartStream(deviceId, 'high');
        notifyViewersStatus(deviceId, 'Connected', 'Connected to device');
    }

    ws.on('message', (message, isBinary) => {
        if (isBinary) {
            // Forward binary screen frame directly to all connected viewers for this device
            const viewers = deviceViewers.get(deviceId);
            if (viewers && viewers.size > 0) {
                // Calculate FPS for tracking
                updateDeviceFps(deviceId);

                for (const viewerWs of viewers) {
                    if (viewerWs.readyState === WebSocket.OPEN) {
                        viewerWs.send(message, { binary: true });
                    }
                }
            }
        } else {
            // Parse JSON control messages from Agent
            try {
                const text = message.toString();
                const payload = JSON.parse(text);
                if (payload.type === 'RESOLUTION_INFO') {
                    notifyViewersResolution(deviceId, payload.resolution);
                } else if (payload.type === 'AGENT_ERROR') {
                    notifyViewersStatus(deviceId, 'Connection Failed', payload.message || 'Stream error');
                }
            } catch (err) {
                // ignore
            }
        }
    });

    ws.on('close', () => {
        console.log(`[Proxy] Agent disconnected: ${deviceId}`);
        agentSockets.delete(deviceId);
        notifyViewersStatus(deviceId, 'Disconnected', 'Employee device disconnected');
    });

    ws.on('error', (err) => {
        console.error(`[Proxy] Agent socket error (${deviceId}):`, err.message);
    });
}

function handleViewerConnection(ws) {
    const { deviceId, liveSessionId, quality } = ws;
    console.log(`[Proxy] Viewer connected for device ${deviceId} (session: ${liveSessionId})`);

    if (!deviceViewers.has(deviceId)) {
        deviceViewers.set(deviceId, new Set());
    }
    const viewers = deviceViewers.get(deviceId);
    viewers.add(ws);

    // Initialize session stats
    if (!activeSessions.has(liveSessionId)) {
        activeSessions.set(liveSessionId, {
            deviceId,
            quality,
            frameCount: 0,
            lastFpsCalc: Date.now(),
            currentFps: 0,
            resolution: '1920x1080'
        });
    }

    const agentWs = agentSockets.get(deviceId);
    if (agentWs && agentWs.readyState === WebSocket.OPEN) {
        // Send start stream to agent if this is the first viewer
        if (viewers.size === 1) {
            notifyAgentStartStream(deviceId, quality);
        }
        ws.send(JSON.stringify({ type: 'STATUS', status: 'Live', message: 'Connected to live stream' }));
    } else {
        ws.send(JSON.stringify({ type: 'STATUS', status: 'Connecting...', message: 'Waiting for employee device to respond...' }));
    }

    ws.on('message', (message) => {
        try {
            const payload = JSON.parse(message.toString());
            if (payload.type === 'CHANGE_QUALITY') {
                const newQuality = payload.quality || 'high';
                ws.quality = newQuality;
                const sessionMeta = activeSessions.get(liveSessionId);
                if (sessionMeta) sessionMeta.quality = newQuality;
                notifyAgentQualityChange(deviceId, newQuality);
            }
        } catch (err) {
            // ignore
        }
    });

    ws.on('close', () => {
        console.log(`[Proxy] Viewer disconnected from device ${deviceId} (session: ${liveSessionId})`);
        viewers.delete(ws);

        if (viewers.size === 0) {
            deviceViewers.delete(deviceId);
            // Notify agent to stop streaming as no active viewers remain
            notifyAgentStopStream(deviceId);
        }

        activeSessions.delete(liveSessionId);
    });

    ws.on('error', (err) => {
        console.error(`[Proxy] Viewer socket error (${deviceId}):`, err.message);
    });
}

function notifyAgentStartStream(deviceId, quality) {
    const agentWs = agentSockets.get(deviceId);
    if (agentWs && agentWs.readyState === WebSocket.OPEN) {
        console.log(`[Proxy] Requesting Agent ${deviceId} START_STREAM (quality: ${quality})`);
        agentWs.send(JSON.stringify({
            type: 'START_STREAM',
            quality,
            timestamp: Date.now()
        }));
    }
}

function notifyAgentStopStream(deviceId) {
    const agentWs = agentSockets.get(deviceId);
    if (agentWs && agentWs.readyState === WebSocket.OPEN) {
        console.log(`[Proxy] Requesting Agent ${deviceId} STOP_STREAM`);
        agentWs.send(JSON.stringify({
            type: 'STOP_STREAM',
            timestamp: Date.now()
        }));
    }
}

function notifyAgentQualityChange(deviceId, quality) {
    const agentWs = agentSockets.get(deviceId);
    if (agentWs && agentWs.readyState === WebSocket.OPEN) {
        agentWs.send(JSON.stringify({
            type: 'CHANGE_QUALITY',
            quality
        }));
    }
}

function notifyViewersStatus(deviceId, status, message) {
    const viewers = deviceViewers.get(deviceId);
    if (viewers) {
        const payload = JSON.stringify({ type: 'STATUS', status, message });
        for (const viewerWs of viewers) {
            if (viewerWs.readyState === WebSocket.OPEN) {
                viewerWs.send(payload);
            }
        }
    }
}

function notifyViewersResolution(deviceId, resolution) {
    const viewers = deviceViewers.get(deviceId);
    if (viewers) {
        const payload = JSON.stringify({ type: 'RESOLUTION_INFO', resolution });
        for (const viewerWs of viewers) {
            if (viewerWs.readyState === WebSocket.OPEN) {
                viewerWs.send(payload);
            }
        }
    }
}

function updateDeviceFps(deviceId) {
    const viewers = deviceViewers.get(deviceId);
    if (!viewers) return;

    for (const viewerWs of viewers) {
        const sessionMeta = activeSessions.get(viewerWs.liveSessionId);
        if (sessionMeta) {
            sessionMeta.frameCount++;
            const now = Date.now();
            const elapsed = (now - sessionMeta.lastFpsCalc) / 1000;
            if (elapsed >= 1.0) {
                sessionMeta.currentFps = Math.round(sessionMeta.frameCount / elapsed);
                sessionMeta.frameCount = 0;
                sessionMeta.lastFpsCalc = now;

                // Send FPS update to viewer
                if (viewerWs.readyState === WebSocket.OPEN) {
                    viewerWs.send(JSON.stringify({
                        type: 'FPS_INFO',
                        fps: sessionMeta.currentFps
                    }));
                }
            }
        }
    }
}

server.listen(PORT, () => {
    console.log(`[LiveStreamProxy] Service listening on port ${PORT}`);
});
