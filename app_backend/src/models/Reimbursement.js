const mongoose = require('mongoose');

const reimbursementSchema = new mongoose.Schema({
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    type: {
        type: String,
        enum: ['Travel', 'Meal', 'Accommodation', 'Other', 'Food'],
        required: true
    },
    amount: { type: Number, required: true, min: 0 },
    description: { type: String, required: true },
    date: { type: Date, required: true },
    receipt: { type: String },
    proofFiles: [{ type: String }], // Array of file URLs
    status: {
        type: String,
        enum: ['Pending', 'Approved', 'Rejected', 'Processed', 'Paid'],
        default: 'Pending'
    },
    approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    approvedAt: { type: Date },
    rejectedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    rejectedAt: { type: Date },
    rejectionReason: { type: String },
    fcmNotificationSentAt: { type: Date },
    fcmRejectionSentAt: { type: Date },
    paidAt: { type: Date },
    processedInPayroll: { type: mongoose.Schema.Types.ObjectId, ref: 'Payroll' },
    processedAt: { type: Date },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' }
}, { timestamps: true });

reimbursementSchema.index({ employeeId: 1 });
reimbursementSchema.index({ status: 1 });
reimbursementSchema.index({ businessId: 1 });

module.exports = mongoose.model('Reimbursement', reimbursementSchema);
