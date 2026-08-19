const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const { getAssets, getAssetById, getAssetTypes, getBranches } = require('../controllers/assetsController');

// Asset routes
router.get('/', protect, getAssets);
router.get('/types', protect, getAssetTypes);
router.get('/:id', protect, getAssetById);

// Branch routes (for filtering)
router.get('/branches/list', protect, getBranches);

module.exports = router;
