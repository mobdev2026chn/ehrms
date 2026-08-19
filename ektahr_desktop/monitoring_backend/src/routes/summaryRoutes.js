const express = require('express');
const router = express.Router();
const rateLimit = require('express-rate-limit');
const summaryController = require('../controllers/summaryController');
const { protectDevice } = require('../middleware/deviceAuth');

// Per-IP: allow 200 devices × 0.5/min (summary every 2 min)
const summaryLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: parseInt(process.env.SUMMARY_RATE_LIMIT_PER_MIN, 10) || 120,
    message: { success: false, message: 'Too many requests' }
});

router.get('/today', summaryLimiter, protectDevice, summaryController.getToday);
router.get('/today/updated', summaryLimiter, protectDevice, summaryController.getTodayUpdated);

module.exports = router;
