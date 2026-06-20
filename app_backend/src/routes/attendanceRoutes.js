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
// Canonical face identity (1-to-many over Staff.faceEnrollEmbeddings) — shared by
// the EHRMS app's anti buddy-punch guard and the face-app kiosk.
const { verifyIdentity, identifyFace } = require('../controllers/authController');

// Shared-secret gate for the face-app KIOSK (not a logged-in staff). The kiosk
// sends x-face-kiosk-secret; matched against FACE_KIOSK_SECRET. If the secret is
// unset the route is disabled (503) so it can never be hit unauthenticated.
function faceKioskAuth(req, res, next) {
    const secret = process.env.FACE_KIOSK_SECRET;
    if (!secret) return res.status(503).json({ matched: false, reason: 'kiosk_identify_disabled' });
    if ((req.headers['x-face-kiosk-secret'] || '') !== secret) {
        return res.status(401).json({ matched: false, reason: 'unauthorized' });
    }
    next();
}

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

// 1-to-many face identity against the canonical Staff.faceEnrollEmbeddings store.
router.post('/verify-identity', protect, attendanceLimiter, verifyIdentity); // EHRMS app guard (1-to-many self/buddy check)
router.post('/identify-face', faceKioskAuth, identifyFace);                  // face-app kiosk identify (shared secret)

module.exports = router;