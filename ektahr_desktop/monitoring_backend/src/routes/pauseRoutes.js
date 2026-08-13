const express = require('express');
const router = express.Router();
const pauseController = require('../controllers/pauseController');
const { protectDevice } = require('../middleware/deviceAuth');

router.post('/start', protectDevice, pauseController.startPause);
router.patch('/:id', protectDevice, pauseController.endPause);

module.exports = router;
