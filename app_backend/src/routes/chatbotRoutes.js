const express = require('express');
const router = express.Router();
const chatbotController = require('../controllers/chatbotController');
const { protect } = require('../middleware/authMiddleware');

router.post('/ask', protect, chatbotController.askQuestion);

module.exports = router;
