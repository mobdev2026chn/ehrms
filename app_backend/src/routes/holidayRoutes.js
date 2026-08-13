
const express = require('express');
const router = express.Router();
const { getEmployeeHolidays, getWeekOffConfig } = require('../controllers/holidayController');
// Assuming authMiddleware has a 'protect' or similar function.
// Checking requestRoutes.js (Step 16) shows: const { protect } = require('../middleware/authMiddleware');
const { protect } = require('../middleware/authMiddleware');

router.get('/employee', protect, getEmployeeHolidays);
router.get('/weekoff-config', protect, getWeekOffConfig);

module.exports = router;
