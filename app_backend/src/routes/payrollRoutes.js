const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const {
    getPayrolls,
    getPayrollById,
    getPayrollStats,
    previewPayrollEmployee,
    createPayroll,
    exportPayroll,
    generatePayroll,
    bulkGeneratePayroll,
    generatePayslip,
    markPayrollAsPaid,
    updatePayroll,
    processPayroll
} = require('../controllers/payrollController');

// Routes from the screenshot and reference implementation
router.get('/', protect, getPayrolls);
router.get('/stats', protect, getPayrollStats);
router.post('/preview', protect, previewPayrollEmployee);
router.get('/export', protect, exportPayroll);
router.get('/:id', protect, getPayrollById);
router.post('/', protect, createPayroll);
router.post('/generate', protect, generatePayroll);
router.post('/bulk-generate', protect, bulkGeneratePayroll);
router.post('/:id/payslip', protect, generatePayslip);
router.post('/:id/mark-paid', protect, markPayrollAsPaid);
router.put('/:id', protect, updatePayroll);
router.post('/process', protect, processPayroll);

module.exports = router;
