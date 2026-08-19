const mongoose = require('mongoose');

const payslipRequestSchema = new mongoose.Schema({
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    month: { type: Number, required: true, min: 1, max: 12 }, // 1-12 (January = 1, December = 12)
    year: { type: Number, required: true }, // e.g., 2026
    reason: { type: String, default: '' },
    status: { type: String, enum: ['Pending', 'Approved', 'Generated', 'Rejected'], default: 'Pending' },
    approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    rejectedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    actionReason: { type: String },
    payrollId: { type: mongoose.Schema.Types.ObjectId, ref: 'Payroll' },
    approvedAt: { type: Date },
    fcmNotificationSentAt: { type: Date },
    fcmRejectionSentAt: { type: Date }
}, { timestamps: true });

// Index to prevent duplicate requests for same employee, month, and year
payslipRequestSchema.index({ employeeId: 1, month: 1, year: 1 });

module.exports = mongoose.model('PayslipRequest', payslipRequestSchema);
