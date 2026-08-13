const express = require('express');
const router = express.Router();
const liveStreamController = require('../controllers/liveStreamController');

router.post('/start', liveStreamController.startSession);
router.post('/end', liveStreamController.endSession);
router.get('/session/:liveSessionId', liveStreamController.getSessionStatus);
router.put('/session/metrics', liveStreamController.updateSessionMetrics);

module.exports = router;
