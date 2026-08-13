const express = require('express');
const router = express.Router();
const activityController = require('../controllers/activityController');
const { protectDevice } = require('../middleware/deviceAuth');
const rateLimit = require('express-rate-limit');

// Per-IP: allow ~200 devices × ~6/min (activity every 10s). Set UPLOAD_RATE_LIMIT_PER_MIN if needed.
const uploadLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: parseInt(process.env.UPLOAD_RATE_LIMIT_PER_MIN, 10) || 1200,
    message: { success: false, message: 'Rate limit exceeded' }
});

router.post('/upload', uploadLimiter, protectDevice, activityController.uploadActivity);

module.exports = router;
