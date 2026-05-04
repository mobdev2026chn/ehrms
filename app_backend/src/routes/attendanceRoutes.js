const express = require('express');
const multer = require('multer');
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

const attendanceSelfieMemory = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 5 * 1024 * 1024 },
});

/** Parse multipart punch bodies (optional); JSON check-in/out unchanged when not multipart. */
function optionalAttendanceSelfieMultipart(req, res, next) {
    const ct = String(req.headers['content-type'] || '').toLowerCase();
    if (ct.includes('multipart/form-data')) {
        return attendanceSelfieMemory.single('selfie')(req, res, next);
    }
    next();
}

// Apply rate limiting after authentication for all attendance routes
router.post('/checkin', protect, attendanceLimiter, optionalAttendanceSelfieMultipart, checkIn);
router.put('/checkout', protect, attendanceLimiter, optionalAttendanceSelfieMultipart, checkOut);
router.get('/today', protect, attendanceLimiter, getTodayAttendance);
router.get('/employee/:employeeId', protect, attendanceLimiter, getEmployeeAttendance);
router.get('/month', protect, attendanceLimiter, getMonthAttendance);
router.get('/history', protect, attendanceLimiter, getAttendanceHistory);
router.get('/fine-calculation', protect, attendanceLimiter, getFineCalculation);

module.exports = router;