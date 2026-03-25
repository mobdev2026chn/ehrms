const express = require('express');
const { protect } = require('../middleware/authMiddleware');
const { createCustomer, getAllCustomers, getCustomerById, updateCustomer } = require('../controllers/customerController');
const router = express.Router();

router.get('/', protect, getAllCustomers);
router.get('/:id', protect, getCustomerById);
router.post('/', protect, createCustomer);
router.patch('/:id', protect, updateCustomer);

module.exports = router;