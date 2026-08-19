const http = require('http');
const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const { connectMongo } = require('./db/mongo');
const { login, logout, verifyTokenMiddleware } = require('./controllers/authController');
const { getAllDevices, postScreenshot, getScreenshots } = require('./controllers/deviceController');
const { initWebSocketServer } = require('./ws/signalingServer');

// Connect to EktaHR MongoDB
connectMongo();

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Auth & Public API
app.post('/api/v1/auth/login', login);
app.post('/api/device/register', login);
app.post('/api/v1/auth/logout', verifyTokenMiddleware, logout);
app.get('/api/v1/health', (req, res) => res.json({ status: 'OK', ok: true, message: 'EktaDMA Server Active' }));
app.get('/health', (req, res) => res.json({ status: 'OK', ok: true, message: 'EktaDMA Server Active' }));
app.get('/api/health', (req, res) => res.json({ status: 'OK', ok: true, message: 'EktaDMA Server Active' }));

// Devices API
app.get('/api/v1/devices', verifyTokenMiddleware, getAllDevices);
app.get('/api/v1/devices/list', verifyTokenMiddleware, getAllDevices);
app.get('/api/devices/list', getAllDevices);

const fs = require('fs');
const path = require('path');

// Screenshot API
app.post('/api/v1/device/screenshot', postScreenshot);
app.post('/api/device/screenshot', postScreenshot);
app.get('/api/v1/devices/:deviceId/screenshots', getScreenshots);
app.get('/api/devices/:deviceId/screenshots', getScreenshots);

// Serve Agents (.exe download endpoint)
const agentsPath = path.join(__dirname, '../../agent/publish');
if (fs.existsSync(agentsPath)) {
  app.use('/agents', express.static(agentsPath));
}

// Serve Admin Console Dist UI
const adminDistPath = path.join(__dirname, '../../admin_console/dist');
if (fs.existsSync(adminDistPath)) {
  app.use(express.static(adminDistPath));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/ws') || req.path.startsWith('/agents')) return next();
    res.sendFile(path.join(adminDistPath, 'index.html'));
  });
}

const PORT = process.env.PORT || 2005;
const server = http.createServer(app);

// Initialize WebSocket Signaling
initWebSocketServer(server);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`=======================================================`);
  console.log(`[EktaDMA Server] Running on http://0.0.0.0:${PORT}`);
  console.log(`[WebSocket] Listening on ws://0.0.0.0:${PORT}/agent & /viewer`);
  console.log(`=======================================================`);
});

// Multi-Port Listeners to ensure Nginx proxy (2005, 9000, 3000, 2000) never hits 502 Bad Gateway
const fallbackPorts = [2005, 9000, 3000, 2000];
for (const p of fallbackPorts) {
  if (p != PORT) {
    try {
      const extraServer = http.createServer(app);
      extraServer.on('error', (err) => {
        // Silently swallow EADDRINUSE if another process uses port p
      });
      initWebSocketServer(extraServer);
      extraServer.listen(p, '0.0.0.0', () => {
        console.log(`[EktaDMA Multi-Port] Active on http://0.0.0.0:${p}`);
      });
    } catch (e) {}
  }
}

// Zero-Conf UDP LAN Server Beacon for Instant Auto-Discovery
try {
  const dgram = require('dgram');
  const udpServer = dgram.createSocket('udp4');

  udpServer.on('message', (msg, rinfo) => {
    const messageStr = msg.toString().trim();
    if (messageStr.includes('EKTA_DISCOVER')) {
      const responseMsg = Buffer.from(`EKTA_SERVER:${PORT}`);
      udpServer.send(responseMsg, 0, responseMsg.length, rinfo.port, rinfo.address, (err) => {
        if (!err) console.log(`[UDP Discovery] Sent LAN auto-discovery response to ${rinfo.address}:${rinfo.port}`);
      });
    }
  });

  udpServer.on('error', (err) => {
    console.error('[UDP Discovery] Server error:', err.message);
  });

  udpServer.bind(9002, '0.0.0.0', () => {
    console.log(`[UDP Discovery] Listening for LAN auto-discovery beacons on UDP port 9002`);
  });
} catch (udpErr) {
  console.error('[UDP Discovery] Failed to bind UDP beacon:', udpErr.message);
}
