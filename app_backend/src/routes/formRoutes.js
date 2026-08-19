const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const {
  getAssignedTemplates,
  getFormResponses,
  createFormResponse,
} = require('../controllers/formController');

router.get('/templates/assigned', protect, getAssignedTemplates);
router.get('/responses', protect, getFormResponses);
router.post('/responses', protect, createFormResponse);

module.exports = router;
