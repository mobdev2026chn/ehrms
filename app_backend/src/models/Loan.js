const mongoose = require('mongoose');

const loanSchema = new mongoose.Schema({
    employeeId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Staff',
        required: true
    },
    loanType: {
        type: String,
        enum: ['Personal', 'Advance', 'Emergency'],
        required: true
    },
    amount: {
        type: Number,
        required: true,
        min: 0
    },
    purpose: {
        type: String,
        required: true
    },
    interestRate: {
        type: Number,
        default: 0
    },
    tenure: {
        type: Number,
        required: true,
        min: 1
    },
    emi: {
        type: Number,
        required: true
    },
    status: {
        type: String,
        enum: ['Pending', 'Approved', 'Active', 'Completed', 'Rejected'],
        default: 'Pending'
    },
    approvedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    },
    approvedAt: Date,
    rejectedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    rejectedAt: { type: Date },
    rejectionReason: { type: String },
    startDate: Date,
    endDate: Date,
    remainingAmount: {
        type: Number,
        default: 0
    },
    installments: [{
        dueDate: Date,
        amount: Number,
        paid: { type: Boolean, default: false },
        paidAt: Date
    }],
    businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Company'
    },
    fcmNotificationSentAt: { type: Date },
    fcmRejectionSentAt: { type: Date }
}, {
    timestamps: true
});

loanSchema.index({ employeeId: 1 });
loanSchema.index({ status: 1 });
loanSchema.index({ businessId: 1 });

module.exports = mongoose.model('Loan', loanSchema);
