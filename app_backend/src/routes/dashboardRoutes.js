const express = require('express');
const rateLimit = require('express-rate-limit');
const { createRateLimitHandler } = require('../utils/rateLimitHandler');
const router = express.Router();
const dashboardController = require('../controllers/dashboardController');
const { protect } = require('../middleware/authMiddleware');

// Dashboard: 100 req/min per IP
const dashboardLimiter = rateLimit({
    windowMs: 1 * 60 * 1000,
    limit: 100,
    standardHeaders: true,
    legacyHeaders: false,
    handler: createRateLimitHandler('Too many dashboard requests. Please wait a moment and try again.')
});

// Apply rate limiting after authentication for dashboard routes
router.get('/stats', protect, dashboardLimiter, dashboardController.getDashboardStats);
router.get('/employee', protect, dashboardLimiter, dashboardController.getEmployeeDashboardStats);

module.exports = router;
