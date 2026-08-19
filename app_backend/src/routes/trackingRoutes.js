const express = require('express');
const {
  startTracking,
  getTrackingData,
  storeTracking,
  storePresenceTracking,
  getPresenceTrackingStatus,
  getPresenceTrackingData,
  exitTracking,
  restartTracking,
  arrivedTracking,
} = require('../controllers/trackingController');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

// Mobile app: store tracking point (Start Ride + every 15 sec)
router.post('/store', protect, storeTracking);

// Staff presence tracking (attendance-based, no task)
router.post('/presence/store', protect, storePresenceTracking);
router.get('/presence/status', protect, getPresenceTrackingStatus);
router.get('/presence', protect, getPresenceTrackingData);

// Mobile app: exit ride (reason required)
router.post('/exit', protect, exitTracking);

// Mobile app: restart task after exit
router.post('/restart', protect, restartTracking);

// Mobile app: arrived at destination
router.post('/arrived', protect, arrivedTracking);

// Admin fetches tracking records (staffId, taskId, from, to, limit)
router.get('/', protect, getTrackingData);

// Admin starts tracking a staff by staffId
router.post('/start', protect, startTracking);

module.exports = router;
