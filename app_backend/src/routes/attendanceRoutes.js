const express = require('express');
const rateLimit = require('express-rate-limit');
const { createRateLimitHandler } = require('../utils/rateLimitHandler');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const {
    checkIn,
    checkOut,
    getTodayAttendance,
    getAttendanceHistory,
    getEmployeeAttendance,
    getMonthAttendance,
    getFineCalculation
} = require('../controllers/attendanceController');

// Attendance: 120 req/min per IP (check-in, check-out, today, month, history)
const attendanceLimiter = rateLimit({
    windowMs: 1 * 60 * 1000,
    limit: 120,
    standardHeaders: true,
    legacyHeaders: false,
    handler: createRateLimitHandler('Too many attendance requests. Please wait a moment and try again.')
});

// Apply rate limiting after authentication for all attendance routes
router.post('/checkin', protect, attendanceLimiter, checkIn);
router.put('/checkout', protect, attendanceLimiter, checkOut);
router.get('/today', protect, attendanceLimiter, getTodayAttendance);
router.get('/employee/:employeeId', protect, attendanceLimiter, getEmployeeAttendance);
router.get('/month', protect, attendanceLimiter, getMonthAttendance);
router.get('/history', protect, attendanceLimiter, getAttendanceHistory);
router.get('/fine-calculation', protect, attendanceLimiter, getFineCalculation);

module.exports = router;