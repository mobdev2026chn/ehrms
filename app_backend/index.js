require('dotenv').config();
const express = require('express');
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
const trackingRoutes = require('./src/routes/trackingRoutes');
const notificationRoutes = require('./src/routes/notificationRoutes');

const app = express();
app.set('trust proxy', 1);

app.use(helmet());
//cors
// Configure CORS
//const allowedOrigins = ['https://ehrms.askeva.io', 'http://ehrms.askeva.io', 'http://localhost:8080', 'http://127.0.0.1:8080'];

// Configure CORS
const allowedOrigins = ['https://app.ektahr.com', 'http://localhost:8080', 'http://127.0.0.1:8080'];

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
app.use('/api/chatbot', chatbotRoutes);
app.use('/api/holidays', holidayRoutes);
app.use('/api/onboarding', onboardingRoutes);
app.use('/api/assets', assetsRoutes);
app.use('/api/announcements', announcementRoutes);
app.use('/api/tasks', taskRoutes);
app.use('/api/tracking', trackingRoutes);
app.use('/api/notifications', notificationRoutes);

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
<<<<<<< HEAD
        app.listen(PORT, () => {
            console.log(`Server running on port ${PORT}`);
=======
        startPresenceTrackingStatusMonitor();
        app.listen(PORT, HOST, () => {
            console.log(`Server running on http://${HOST}:${PORT}`);
>>>>>>> development
        });
    } catch (error) {
        console.error('Failed to start server:', error.message);
        process.exit(1);
    }
};

startServer();