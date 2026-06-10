const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const { getReviewCycles, getKRAs } = require('../controllers/reviewCycleController');
const {
  getPerformanceReviews,
  getPerformanceReviewById,
  submitSelfReview,
  createSelfAssessment,
  getEmployeePerformanceSummary,
} = require('../controllers/performanceReviewController');

router.use(protect);

router.get('/cycles', getReviewCycles);
router.get('/kra', getKRAs);

// Performance review routes (employee app - my reviews)
// Order: specific paths before :id (otherwise "employee" would match :id)
router.get('/reviews', getPerformanceReviews);
router.get('/reviews/employee/summary', getEmployeePerformanceSummary);
// Employee-initiated self assessment (create own review).
router.post('/reviews/self-assessment', createSelfAssessment);
router.get('/reviews/:id', getPerformanceReviewById);
router.patch('/reviews/:id/self-review', submitSelfReview);

module.exports = router;
