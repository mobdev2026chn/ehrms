const express = require('express');
const rateLimit = require('express-rate-limit');
const { protect } = require('../middleware/authMiddleware');
const { createRateLimitHandler } = require('../utils/rateLimitHandler');
const { getCurrentBreak, startBreak, endBreak } = require('../controllers/breakController');

const router = express.Router();

const breakLimiter = rateLimit({
    windowMs: 1 * 60 * 1000,
    limit: 60,
    standardHeaders: true,
    legacyHeaders: false,
    handler: createRateLimitHandler('Too many break requests. Please wait a moment and try again.')
});

router.get('/current', protect, breakLimiter, getCurrentBreak);
router.post('/start', protect, breakLimiter, startBreak);
router.patch('/:id/end', protect, breakLimiter, endBreak);

module.exports = router;
