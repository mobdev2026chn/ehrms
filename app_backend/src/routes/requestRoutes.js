const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const { getLeaves, createLeave, getLeaveTypes, getLeaveTypesForApply, getLeaveBalance, checkLeaveDates, updateLeaveStatus } = require('../controllers/leaveController');
const { getReimbursements, getReimbursementSummary, createReimbursement } = require('../controllers/reimbursementController');

const { getLoans, createLoan, getLoanSummary } = require('../controllers/loanController');
const {
  requestPayslip,
  getPayslipRequests,
  viewPayslipRequest,
  downloadPayslipRequest,
  createPermissionRequest,
  getPermissionRequests,
  cancelPermissionRequest,
  permissionOut,
  permissionIn,
  getPermissionBalance
} = require('../controllers/requestController');

// Leave Routes (supports both Mobile & Web HRMS endpoints)
router.get('/leave', protect, getLeaves);
router.get('/leave/my-requests', protect, getLeaves);
router.get('/leave/types', protect, getLeaveTypes);
router.get('/leave-types', protect, getLeaveTypes);
router.get('/leave-types/for-apply', protect, getLeaveTypesForApply);
router.get('/leave-balance', protect, getLeaveBalance);
router.post('/leave/check-dates', protect, checkLeaveDates);
router.post('/leave', protect, createLeave);
router.post('/leave/apply', protect, createLeave);
router.post('/leave/cancel/:id', protect, (req, res, next) => { req.body = { status: 'Cancelled' }; next(); }, updateLeaveStatus);
router.patch('/leave/:id/status', protect, updateLeaveStatus); // Approve/Reject leave

// Reimbursement (Expense) Routes
router.get('/reimbursement/summary', protect, getReimbursementSummary);
router.get('/reimbursement', protect, getReimbursements);
router.post('/reimbursement', protect, createReimbursement);
router.get('/expense/summary', protect, getReimbursementSummary);
router.get('/expense', protect, getReimbursements);
router.get('/expense/my-requests', protect, getReimbursements);
router.post('/expense', protect, createReimbursement);
router.post('/expense/apply', protect, createReimbursement);

// Loan Routes
router.get('/loan/summary', protect, getLoanSummary);
router.get('/loan', protect, getLoans);
router.get('/loan/my-requests', protect, getLoans);
router.post('/loan', protect, createLoan);
router.post('/loan/apply', protect, createLoan);

// Payslip Routes
router.get('/payslip', protect, getPayslipRequests);
router.get('/payslip/my-requests', protect, getPayslipRequests);
router.post('/payslip', protect, requestPayslip);
router.post('/payslip/apply', protect, requestPayslip);
router.get('/payslip/:id/view', protect, viewPayslipRequest);
router.get('/payslip/:id/download', protect, downloadPayslipRequest);

// Permission Routes
router.get('/permission', protect, getPermissionRequests);
router.get('/permission/my-requests', protect, getPermissionRequests);
router.get('/permission/my-quota', protect, getPermissionBalance);
router.get('/permission/balance', protect, getPermissionBalance);
router.post('/permission', protect, createPermissionRequest);
router.post('/permission/apply', protect, createPermissionRequest);
router.post('/permission/cancel/:id', protect, cancelPermissionRequest);
router.patch('/permission/:id/cancel', protect, cancelPermissionRequest);
router.post('/permission/:id/out', protect, permissionOut); // stamp actual step-out
router.post('/permission/:id/in', protect, permissionIn);   // stamp return + compute overrun

module.exports = router;
