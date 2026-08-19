const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const {
  getGoals,
  getGoalById,
  createGoal,
  updateGoalProgress,
  completeGoal,
} = require('../controllers/pmsController');

router.use(protect);

router.get('/', getGoals);
router.get('/:id', getGoalById);
router.post('/', createGoal);
router.patch('/:id/progress', updateGoalProgress);
router.patch('/:id/complete', completeGoal);

module.exports = router;
