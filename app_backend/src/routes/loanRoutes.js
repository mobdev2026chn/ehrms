const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const { getLoans, createLoan } = require('../controllers/loanController');

router.get('/', protect, getLoans);
router.post('/', protect, createLoan);
// router.get('/:id', protect, getLoanById); // If needed later

module.exports = router;
