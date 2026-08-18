const express = require('express');
const router = express.Router();
const deviceController = require('../controllers/deviceController');
const { protectDevice, protectDeviceForLogout } = require('../middleware/deviceAuth');
const rateLimit = require('express-rate-limit');

const registerLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 100,
    message: { success: false, message: 'Too many registration attempts' }
});

// Per-IP: allow 200 devices × 0.5/min (heartbeat every 2 min). Set HEARTBEAT_RATE_LIMIT_PER_MIN if needed.
const heartbeatLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: parseInt(process.env.HEARTBEAT_RATE_LIMIT_PER_MIN, 10) || 120,
    message: { success: false, message: 'Too many heartbeat requests' }
});

// Per-IP: allow 200 devices × 0.5/min (settings at most every 2 min). Set SETTINGS_RATE_LIMIT_PER_MIN if needed.
const settingsLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: parseInt(process.env.SETTINGS_RATE_LIMIT_PER_MIN, 10) || 120,
    message: { success: false, message: 'Too many settings requests' }
});

router.post('/register', registerLimiter, deviceController.registerDevice);
router.get('/settings', settingsLimiter, protectDevice, deviceController.getSettings);
router.get('/profile', protectDevice, deviceController.getProfile);
router.patch('/autoupdate', protectDevice, deviceController.updateAutoupdate);
router.get('/version-check', protectDevice, deviceController.versionCheck);
router.get('/attendance-status', protectDevice, deviceController.getAttendanceStatus);
router.post('/ack-attendance-alert', protectDevice, deviceController.ackAttendanceAlert);
router.post('/heartbeat', heartbeatLimiter, protectDevice, deviceController.heartbeat);
router.post('/set-inactive', protectDeviceForLogout, deviceController.setInactive);
router.post('/set-logout', protectDeviceForLogout, deviceController.setLogout);
router.post('/set-exit', protectDeviceForLogout, deviceController.setExit);
router.post('/start', protectDeviceForLogout, deviceController.startDevice);
router.get('/active-list', deviceController.getActiveDevicesList);

module.exports = router;
