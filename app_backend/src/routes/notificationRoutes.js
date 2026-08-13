const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const { registerFcmToken, sendPush } = require('../controllers/notificationController');

router.post('/fcm-token', protect, registerFcmToken);
router.post('/send-push', sendPush);

module.exports = router;
