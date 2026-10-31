const http = require('http');
const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const { connectMongo } = require('./db/mongo');
const { login, logout, verifyTokenMiddleware, requireAdminRole, agentAuthMiddleware } = require('./controllers/authController');
const { getAllDevices, getLanAgents, postScreenshot, getScreenshots, serveScreenshotFile, downloadAgent } = require('./controllers/deviceController');
const { startRetentionJob, STORAGE_DIR } = require('./storage/fileStore');
const { getActivitySummary, getEmployeeActivity } = require('./controllers/activityController');
const { getAlerts } = require('./alerts');
const { initWebSocketServer, hasActiveViewers } = require('./ws/signalingServer');
const { initIdleTracker, getIdleLogs, getDailyIdleSummary } = require('./db/idleTracker');
const { DMA_MODE, IS_ONLINE, MODE_SOURCE, ONLINE_SERVER_URL, DMA_ENV, ENV_SOURCE, HRMS_API_URL, USE_DATABASE, JWT_SECRET_SOURCE } = require('./config');
const { getPublishedAgent } = require('./agentUpdate');
const adminConsoleUpdate = require('./adminConsoleUpdate');
const { startAutoUpdate } = adminConsoleUpdate;

console.log(`[Env] ${DMA_ENV} (from ${ENV_SOURCE}): logins via ${HRMS_API_URL}` +
  `${USE_DATABASE && process.env.MONGODB_URI ? ' (DEV_HRMS database first)' : ''}`);
// The online server never signs tokens with the public default secret (config.js)
console.log(`[Config] ${DMA_MODE} server (mode from ${MODE_SOURCE}); token secret from ${JWT_SECRET_SOURCE}`);

// Connect to EktaHR MongoDB
connectMongo();
initIdleTracker();
startRetentionJob();
console.log(`[Storage] Screenshots & idle logs saved on disk at ${STORAGE_DIR}`);
console.log(`[Config] Idle after ${require('./config').IDLE_THRESHOLD_SECONDS}s without input (IDLE_THRESHOLD_SECONDS in .env)`);

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
// Tells the Admin Console whether this is an office LAN server or the online server, and (on a LAN
// server) which online server to also sign in to for employees on other networks
app.get('/api/v1/server-info', (req, res) => res.json({ success: true, mode: DMA_MODE, env: DMA_ENV, onlineServerUrl: ONLINE_SERVER_URL }));
app.get('/api/v1/download/agent', downloadAgent);
app.get('/download/agent', downloadAgent);
// Newest agent this server hands out: { version, sha256, size } - used by Settings > Update in the
// agent, and handy in a browser to see which version is hosted
app.get('/api/v1/agent/latest', (req, res) => res.json({ success: true, ...(getPublishedAgent() || { version: null }) }));

// Admin Console auto-update (adminConsoleUpdate.js). Public: the release this server hands out
// (server code, web console, agent - never .env). Admin only: this console's version, settings, update.
app.get('/api/v1/admin-console/latest', (req, res) => res.json({ success: true, version: adminConsoleUpdate.publishedVersion() }));
app.get('/api/v1/admin-console/manifest', (req, res) => res.json({ success: true, ...adminConsoleUpdate.getManifest() }));
app.get('/api/v1/admin-console/file', (req, res) => {
  const file = adminConsoleUpdate.resolvePackageFile(String(req.query.path || ''));
  if (!file) return res.status(404).json({ error: 'Not part of the Admin Console release' });
  res.sendFile(file);
});
app.get('/api/v1/admin-console/status', verifyTokenMiddleware, requireAdminRole, async (req, res) => {
  if (req.query.check === '1' && adminConsoleUpdate.CAN_SELF_UPDATE) await adminConsoleUpdate.checkLatest();
  const agent = getPublishedAgent();
  res.json({
    success: true, ...adminConsoleUpdate.getStatus(),
    env: DMA_ENV, mode: DMA_MODE, onlineServerUrl: ONLINE_SERVER_URL, agentVersion: agent ? agent.version : null
  });
});
app.put('/api/v1/admin-console/settings', verifyTokenMiddleware, requireAdminRole, (req, res) => {
  if (typeof (req.body || {}).autoUpdate !== 'boolean') return res.status(400).json({ success: false, error: 'autoUpdate (true/false) required' });
  res.json({ success: true, settings: adminConsoleUpdate.writeSettings({ autoUpdate: req.body.autoUpdate }) });
});
app.post('/api/v1/admin-console/update', verifyTokenMiddleware, requireAdminRole, async (req, res) => {
  if (!adminConsoleUpdate.CAN_SELF_UPDATE) {
    return res.status(400).json({ success: false, error: 'This console runs on a server that is updated by its deploy (git pull).' });
  }
  try {
    await adminConsoleUpdate.checkLatest();
    const status = adminConsoleUpdate.getStatus();
    if (!status.updateAvailable) return res.json({ success: true, updating: false, ...status });
    // Files are put in place first; the server then restarts into the new version (~1 s)
    res.json({ success: true, ...(await adminConsoleUpdate.installUpdate()) });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// Devices API
app.get('/api/v1/devices', verifyTokenMiddleware, requireAdminRole, getAllDevices);
app.get('/api/v1/devices/list', verifyTokenMiddleware, requireAdminRole, getAllDevices);
app.get('/api/devices/list', verifyTokenMiddleware, requireAdminRole, getAllDevices); // was open to anyone
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
// Live admin alerts (employee went idle / came back), polled by the Admin Console
app.get('/api/v1/alerts', verifyTokenMiddleware, requireAdminRole, (req, res) => {
  const since = req.query.since !== undefined ? Number(req.query.since) : -1;
  res.json({ success: true, ...getAlerts({ businessId: req.user.businessId, since, limit: req.query.limit }) });
});

// Date-wise employee activity (idle time + screenshots) for the Admin Console "Activity Report"
app.get('/api/v1/activity/summary', verifyTokenMiddleware, requireAdminRole, getActivitySummary);
app.get('/api/v1/activity/employee', verifyTokenMiddleware, requireAdminRole, getEmployeeActivity);
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
app.post('/api/v1/device/screenshot', agentAuthMiddleware, postScreenshot);
app.post('/api/device/screenshot', agentAuthMiddleware, postScreenshot);
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
// Address to listen on: all networks (default), or e.g. 127.0.0.1 behind a reverse proxy / for tests
const LISTEN_HOST = process.env.LISTEN_HOST || '0.0.0.0';
const server = http.createServer(app);

// Initialize WebSocket Signaling
initWebSocketServer(server);

// After an Admin Console update the previous server may still be closing: retry while the port is busy
let listenTries = 0;
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE' && ++listenTries <= 30) {
    console.warn(`[EktaDMA Server] Port ${PORT} still in use - retrying (${listenTries})`);
    setTimeout(() => server.listen(PORT, LISTEN_HOST), 1000);
    return;
  }
  console.error('[EktaDMA Server] Cannot listen:', err.message);
  process.exit(1);
});

server.listen(PORT, LISTEN_HOST, () => {
  console.log(`=======================================================`);
  console.log(`[EktaDMA Server] Running on http://${LISTEN_HOST}:${PORT}`);
  console.log(`[WebSocket] Listening on ws://${LISTEN_HOST}:${PORT}/agent & /viewer`);
  console.log(`[LAN Guard] ${LAN_ONLY ? 'LAN-only mode ON (public IPs are rejected)' : 'LAN-only mode OFF'}`);
  console.log(IS_ONLINE
    ? '[Mode] ONLINE server: employees on any network, agent & viewer tokens required'
    : `[Mode] Office LAN server${ONLINE_SERVER_URL ? ` (Admin Console also shows online employees from ${ONLINE_SERVER_URL})` : ''}`);
  console.log(`=======================================================`);
});



// Zero-Conf UDP LAN Server Beacon for Instant Auto-Discovery (office LAN servers only — agents
// must never mistake the online server for the office one)
function startUdpBeacon(attempt) {
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
    try { udpServer.close(); } catch (e) {}
    // The previous server (Admin Console update) may still hold the port for a moment
    if (err.code === 'EADDRINUSE' && attempt < 30) {
      setTimeout(() => startUdpBeacon(attempt + 1), 1000);
      return;
    }
    console.error('[UDP Discovery] Server error:', err.message);
  });

  udpServer.bind(9002, LISTEN_HOST, () => {
    console.log(`[UDP Discovery] Listening for LAN auto-discovery beacons on UDP port 9002`);
  });
}

if (!IS_ONLINE) {
  try {
    startUdpBeacon(1);
  } catch (udpErr) {
    console.error('[UDP Discovery] Failed to bind UDP beacon:', udpErr.message);
  }
}

// Office server inside the Admin Console: keep itself up to date from the online server
startAutoUpdate(hasActiveViewers);
