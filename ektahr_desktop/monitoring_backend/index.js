const dns = require('dns');
try {
    dns.setDefaultResultOrder('ipv4first');
    dns.setServers(['8.8.8.8', '1.1.1.1', '8.8.4.4']);
} catch (e) {}

require('dotenv').config();
const path = require('path');
const Module = require('module');
const appBackendRoot = require('./src/config/appBackendPath');

// Ensure models loaded from app_backend can resolve dependencies (mongoose, bcrypt, etc.) from monitoring_backend node_modules
const origNodeModulePaths = Module._nodeModulePaths;
Module._nodeModulePaths = function (from) {
    const paths = origNodeModulePaths.call(this, from);
    const monitoringNodeModules = path.join(__dirname, 'node_modules');
    const appBackendNodeModules = path.join(appBackendRoot, 'node_modules');
    if (!paths.includes(monitoringNodeModules)) paths.push(monitoringNodeModules);
    if (!paths.includes(appBackendNodeModules)) paths.push(appBackendNodeModules);
    return paths;
};

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const connectDB = require('./src/config/db');

const deviceRoutes = require('./src/routes/deviceRoutes');
const activityRoutes = require('./src/routes/activityRoutes');
const breakRoutes = require('./src/routes/breakRoutes');
const pauseRoutes = require('./src/routes/pauseRoutes');
const meetingRoutes = require('./src/routes/meetingRoutes');
const summaryRoutes = require('./src/routes/summaryRoutes');
const debugRoutes = require('./src/routes/debugRoutes');
const liveStreamRoutes = require('./src/routes/liveStreamRoutes');

const app = express();
app.set('trust proxy', 1);
app.use(helmet());
app.use(cors({ origin: '*' }));
app.use(express.json({ limit: '50mb' }));

app.use('/api/device', deviceRoutes);
app.use('/api/v1/device', deviceRoutes);
app.use('/api/activity', activityRoutes);
app.use('/api/break', breakRoutes);
app.use('/api/pause', pauseRoutes);
app.use('/api/meeting', meetingRoutes);
app.use('/api/summary', summaryRoutes);
app.use('/api/debug', debugRoutes);
app.use('/api/live-stream', liveStreamRoutes);

app.get('/health', (req, res) => res.json({ ok: true }));

app.get('/api/debug', async (req, res) => {
    const useRedis = process.env.USE_REDIS === 'true' || process.env.USE_REDIS === '1';
    if (!useRedis) {
        return res.json({ useRedis: false, rsaSet: !!process.env.RSA_PRIVATE_KEY, hint: 'API processes uploads inline. No Redis or Worker needed.' });
    }
    try {
        const Bull = require('bull');
        const q = new Bull(process.env.REDIS_QUEUE_NAME || 'monitoring_processing_queue', process.env.REDIS_URL || 'redis://localhost:6379');
        const [waiting, active, completed, failed] = await Promise.all([q.getWaitingCount(), q.getActiveCount(), q.getCompletedCount(), q.getFailedCount()]);
        await q.close();
        res.json({ queue: { waiting, active, completed, failed }, rsaSet: !!process.env.RSA_PRIVATE_KEY, hint: 'Worker must be running (npm run worker) and RSA_PRIVATE_KEY set for data to reach MongoDB.' });
    } catch (e) {
        res.status(500).json({ error: e.message, hint: 'Is Redis running? Leave USE_REDIS unset to run without Redis.' });
    }
});

app.use((req, res) => {
    res.status(404).json({ success: false, message: 'Not found' });
});

const PORT = process.env.PORT || 9002;
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const QUEUE_NAME = process.env.REDIS_QUEUE_NAME || 'monitoring_processing_queue';
const USE_REDIS = process.env.USE_REDIS === 'true' || process.env.USE_REDIS === '1';

const listenServer = () => {
    const server = app.listen(PORT, () => console.log(`[MonitoringBackend] Service listening on port ${PORT}`));
    server.on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
            console.error(`[MonitoringBackend] Error: Port ${PORT} is already in use by another process (PID ${process.pid}).`);
            process.exit(1);
        } else {
            console.error(`[MonitoringBackend] Server error:`, err);
            process.exit(1);
        }
    });
};

const start = async () => {
    try {
        await connectDB();
        if (!USE_REDIS) {
            listenServer();
            return;
        }
        const Bull = require('bull');
        const redisQueue = new Bull(QUEUE_NAME, REDIS_URL);
        await Promise.race([
            redisQueue.client.ping(),
            new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 4000))
        ]);
        await redisQueue.close();
        listenServer();
    } catch (err) {
        listenServer();
    }
};

start();
