require('dotenv').config();
const express = require('express');
const path = require('path');
const connectDB = require('./src/config/db');
const cors = require('cors');
const helmet = require('helmet');

const authRoutes = require('./src/routes/authRoutes');
const attendanceRoutes = require('./src/routes/attendanceRoutes');
const dashboardRoutes = require('./src/routes/dashboardRoutes');
const requestRoutes = require('./src/routes/requestRoutes');
const loanRoutes = require('./src/routes/loanRoutes');
const payrollRoutes = require('./src/routes/payrollRoutes');
const chatbotRoutes = require('./src/routes/chatbotRoutes');
const holidayRoutes = require('./src/routes/holidayRoutes');
const onboardingRoutes = require('./src/routes/onboardingRoutes');
const assetsRoutes = require('./src/routes/assetsRoutes');
const announcementRoutes = require('./src/routes/announcementRoutes');
const taskRoutes = require('./src/routes/taskRoutes');
const customerRoutes = require('./src/routes/customerRoutes');
const trackingRoutes = require('./src/routes/trackingRoutes');
const breakRoutes = require('./src/routes/breakRoutes');
const { startPresenceTrackingStatusMonitor } = require('./src/services/presenceTrackingStatusService');
const notificationRoutes = require('./src/routes/notificationRoutes');
const monitoringRoutes = require('./src/routes/monitoringRoutes');
const grievanceRoutes = require('./src/routes/grievanceRoutes');

const app = express();

app.use('/uploads', express.static(path.join(process.cwd(), 'uploads')));
app.set('trust proxy', 1);

app.use(helmet());
//cors
// Configure CORS
//const allowedOrigins = ['https://ehrms.askeva.io', 'http://ehrms.askeva.io', 'http://localhost:8080', 'http://127.0.0.1:8080'];

// Configure CORS
const allowedOrigins = ['https://app.ektahr.com','https://my.ektahr.com','https://ehrms.askeva.net', 'http://ehrms.askeva.net', 'http://localhost:8080', 'http://127.0.0.1:8080'];

app.use(cors({
    origin: (origin, callback) => {
        if (!origin) return callback(null, true);
        if (origin.startsWith('http://localhost') || origin.startsWith('http://127.0.0.1')) {
            return callback(null, true);
        }
        if (allowedOrigins.includes(origin)) {
            callback(null, true);
        } else {
            callback(new Error('Not allowed by CORS'));
        }
    },
    credentials: true
}));

app.use(express.json({ limit: '50mb' }));

// Routes (rate limiting is applied at router level, not globally)
console.log('[Server] Registering routes...');
app.use('/api/auth', authRoutes);
console.log('[Server] Auth routes registered at /api/auth');
app.use('/api/attendance', attendanceRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/requests', requestRoutes);
app.use('/api/loans', loanRoutes);
app.use('/api/payrolls', payrollRoutes);
// Web frontend RTK uses `/api/payroll` (singular); keep alias for parity.
app.use('/api/payroll', payrollRoutes);
app.use('/api/chatbot', chatbotRoutes);
app.use('/api/holidays', holidayRoutes);
app.use('/api/onboarding', onboardingRoutes);
app.use('/api/assets', assetsRoutes);
app.use('/api/announcements', announcementRoutes);
app.use('/api/tasks', taskRoutes);
app.use('/api/customers', customerRoutes);
app.use('/api/tracking', trackingRoutes);
app.use('/api/breaks', breakRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/monitoring', monitoringRoutes);
app.use('/api/grievances', grievanceRoutes);

// Debug: Log all incoming requests (only in development)
if (process.env.NODE_ENV !== 'production') {
    app.use((req, res, next) => {
        console.log(`[Route Debug] ${req.method} ${req.path}`);
        next();
    });
}

// 404 handler - should return JSON, not HTML
app.use((req, res) => {
    console.error(`[404] Route not found: ${req.method} ${req.path}`);
    res.status(404).json({
        success: false,
        error: { message: `Route not found: ${req.method} ${req.path}` }
    });
});

const PORT = process.env.PORT || 5000;
// Listen on all interfaces so phones on the same LAN can reach the dev server (not only localhost).
const HOST = process.env.HOST || '0.0.0.0';

// Start Server
const startServer = async () => {
    try {
        await connectDB();
        // Under the PM2 load balancer (exec_mode: 'cluster') every worker runs this
        // file, so the background presence monitor would otherwise run once PER worker
        // — duplicating its periodic scan and racing on the same writes. PM2 numbers
        // workers via NODE_APP_INSTANCE (0,1,2,...); run the singleton monitor only on
        // worker 0. In fork mode / plain `node index.js` the var is unset, so it runs.
        const workerInstance = process.env.NODE_APP_INSTANCE;
        if (workerInstance === undefined || workerInstance === '0') {
            startPresenceTrackingStatusMonitor();
        } else {
            console.log(`[Server] Worker ${workerInstance}: skipping presence monitor (runs on worker 0 only)`);
        }
        app.listen(PORT, HOST, () => {
            console.log(`Server running on http://${HOST}:${PORT}`);
        });
    } catch (error) {
        console.error('Failed to start server:', error.message);
        process.exit(1);
    }
};

startServer();