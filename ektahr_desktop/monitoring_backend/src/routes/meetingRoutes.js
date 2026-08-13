const express = require('express');
const router = express.Router();
const meetingController = require('../controllers/meetingController');
const { protectDevice } = require('../middleware/deviceAuth');

router.post('/start', protectDevice, meetingController.startMeeting);
router.patch('/:id', protectDevice, meetingController.endMeeting);

module.exports = router;
