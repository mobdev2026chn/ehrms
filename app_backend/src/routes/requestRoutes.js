const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const { getLeaves, createLeave, getLeaveTypes, getLeaveTypesForApply, getLeaveBalance, checkLeaveDates, updateLeaveStatus } = require('../controllers/leaveController');
const { getReimbursements, createReimbursement } = require('../controllers/reimbursementController');

const { getLoans, createLoan } = require('../controllers/loanController');
const { requestPayslip, getPayslipRequests, viewPayslipRequest, downloadPayslipRequest } = require('../controllers/requestController');

// Leave Routes
router.get('/leave', protect, getLeaves);
router.get('/leave-types', protect, getLeaveTypes);
router.get('/leave-types/for-apply', protect, getLeaveTypesForApply);
router.get('/leave-balance', protect, getLeaveBalance);
router.post('/leave/check-dates', protect, checkLeaveDates);
router.post('/leave', protect, createLeave);
router.patch('/leave/:id/status', protect, updateLeaveStatus); // Approve/Reject leave

// Reimbursement (Expense) Routes
router.get('/reimbursement', protect, getReimbursements);
router.post('/reimbursement', protect, createReimbursement);
router.get('/expense', protect, getReimbursements);
router.post('/expense', protect, createReimbursement);

// Loan Routes
router.get('/loan', protect, getLoans);
router.post('/loan', protect, createLoan);

// Payslip Routes
router.get('/payslip', protect, getPayslipRequests);
router.post('/payslip', protect, requestPayslip);
router.get('/payslip/:id/view', protect, viewPayslipRequest);
router.get('/payslip/:id/download', protect, downloadPayslipRequest);

module.exports = router;
