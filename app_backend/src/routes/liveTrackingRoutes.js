const express = require('express');
const {
  recordLivePoint,
  recordLiveBatch,
  getLiveStaffLocations,
  getStaffLiveHistory,
  getTaskLiveTrail,
  updateTrackingStatus,
} = require('../controllers/liveTrackingController');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

// Mobile app: Record a live GPS point (during active ride or periodic presence)
router.post('/record', protect, recordLivePoint);
router.post('/store', protect, recordLivePoint); // Alias for compatibility

// Mobile app: Replay offline batch points
router.post('/batch', protect, recordLiveBatch);

// Mobile app: Update tracking event status (e.g. arrived, exited)
router.post('/status', protect, updateTrackingStatus);

// Admin / Dashboard: Get real-time positions for all active staff
router.get('/live', protect, getLiveStaffLocations);

// Admin / Staff: Get historical tracking breadcrumbs for a staff member
router.get('/staff/:id/history', protect, getStaffLiveHistory);

// Admin / Mobile: Get tracking trail for a specific task
router.get('/task/:taskId', protect, getTaskLiveTrail);

module.exports = router;
