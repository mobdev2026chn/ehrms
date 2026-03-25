const express = require('express');
const { storeActivity, setMonitoringStatus } = require('../controllers/monitoringController');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

// Desktop agent: submit activity snapshot (every minute or so)
router.post('/activity', protect, storeActivity);

// Desktop agent: set monitoring status on login / logout / exit
router.post('/status', protect, setMonitoringStatus);

module.exports = router;
