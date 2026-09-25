const http = require('http');
const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const { connectMongo } = require('./db/mongo');
const { login, logout, verifyTokenMiddleware, requireAdminRole } = require('./controllers/authController');
const { getAllDevices, getLanAgents, postScreenshot, getScreenshots, serveScreenshotFile, downloadAgent } = require('./controllers/deviceController');
const { startRetentionJob, STORAGE_DIR } = require('./storage/fileStore');
const { initWebSocketServer } = require('./ws/signalingServer');
const { initIdleTracker, getIdleLogs, getDailyIdleSummary } = require('./db/idleTracker');

// Connect to EktaHR MongoDB
connectMongo();
initIdleTracker();
startRetentionJob();
console.log(`[Storage] Screenshots & idle logs saved on disk at ${STORAGE_DIR}`);

const { LAN_ONLY, isPrivateIp, lanOnlyHttp } = require('./lanGuard');

const app = express();
app.use(lanOnlyHttp);
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Auth & Public API
app.post('/api/v1/auth/login', login);
app.post('/api/device/register', login);
app.post('/api/v1/auth/logout', verifyTokenMiddleware, logout);
app.get('/api/v1/health', (req, res) => res.json({ status: 'OK', ok: true, message: 'EktaDMA Server Active' }));
app.get('/health', (req, res) => res.json({ status: 'OK', ok: true, message: 'EktaDMA Server Active' }));
app.get('/api/health', (req, res) => res.json({ status: 'OK', ok: true, message: 'EktaDMA Server Active' }));
app.get('/api/v1/download/agent', downloadAgent);
app.get('/download/agent', downloadAgent);

// Devices API
app.get('/api/v1/devices', verifyTokenMiddleware, requireAdminRole, getAllDevices);
app.get('/api/v1/devices/list', verifyTokenMiddleware, requireAdminRole, getAllDevices);
app.get('/api/devices/list', getAllDevices);
app.get('/api/v1/lan/agents', verifyTokenMiddleware, requireAdminRole, getLanAgents);

// Idle Time Logs API (scoped to the admin's businessId from the JWT)
app.get('/api/v1/idle-logs', verifyTokenMiddleware, requireAdminRole, async (req, res) => {
  try {
    const { userEmail, deviceId, from, to, limit } = req.query;
    const logs = await getIdleLogs({ businessId: req.user.businessId, userEmail, deviceId, from, to, limit });
    res.json({ success: true, logs });
  } catch (err) {
    console.error('[IdleLog] Error fetching idle logs:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch idle logs' });
  }
});
app.get('/api/v1/idle-logs/summary', verifyTokenMiddleware, requireAdminRole, async (req, res) => {
  try {
    const tz = req.query.tz || 'Asia/Kolkata';
    const date = req.query.date || new Date().toLocaleDateString('en-CA', { timeZone: tz });
    const summary = await getDailyIdleSummary({ businessId: req.user.businessId, date, tz });
    res.json({ success: true, date, summary });
  } catch (err) {
    console.error('[IdleLog] Error fetching idle summary:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch idle summary' });
  }
});

const fs = require('fs');
const path = require('path');

// Screenshot API
app.post('/api/v1/device/screenshot', postScreenshot);
app.post('/api/device/screenshot', postScreenshot);
app.get('/api/v1/devices/:deviceId/screenshots', verifyTokenMiddleware, requireAdminRole, getScreenshots);
app.get('/api/devices/:deviceId/screenshots', verifyTokenMiddleware, requireAdminRole, getScreenshots);
// Screenshot image files live on disk; <img> tags can't send headers, so ?token= is accepted here
app.get('/api/v1/screenshots/file/:businessId/:deviceId/:day/:file', (req, res, next) => {
  if (!req.headers.authorization && req.query.token) req.headers.authorization = `Bearer ${req.query.token}`;
  next();
}, verifyTokenMiddleware, requireAdminRole, serveScreenshotFile);

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
  console.log(`[LAN Guard] ${LAN_ONLY ? 'LAN-only mode ON (public IPs are rejected)' : 'LAN-only mode OFF'}`);
  console.log(`=======================================================`);
});



// Zero-Conf UDP LAN Server Beacon for Instant Auto-Discovery
try {
  const dgram = require('dgram');
  const udpServer = dgram.createSocket('udp4');

  udpServer.on('message', (msg, rinfo) => {
    if (!isPrivateIp(rinfo.address)) return;
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
