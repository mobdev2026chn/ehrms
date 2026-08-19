const express = require('express');
const rateLimit = require('express-rate-limit');
const { createRateLimitHandler } = require('../utils/rateLimitHandler');
const router = express.Router();
const announcementController = require('../controllers/announcementController');
const { protect } = require('../middleware/authMiddleware');

const announcementLimiter = rateLimit({
    windowMs: 1 * 60 * 1000,
    limit: 60,
    standardHeaders: true,
    legacyHeaders: false,
    handler: createRateLimitHandler('Too many requests. Please try again later.'),
});

router.get('/for-employee', protect, announcementLimiter, announcementController.getAnnouncementsForEmployee);
router.get('/today', protect, announcementLimiter, announcementController.getTodayAnnouncementsForEmployee);

module.exports = router;
