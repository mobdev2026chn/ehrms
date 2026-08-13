const mongoose = require('mongoose');

const expenseSchema = new mongoose.Schema({
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    expenseType: { type: String, required: true }, // e.g., "Travel", "Food"
    amount: { type: Number, required: true },
    date: { type: Date, required: true },
    description: { type: String },
    status: { type: String, enum: ['Pending', 'Approved', 'Rejected', 'Paid'], default: 'Pending' },
    approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    approvedAt: { type: Date },
    rejectedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    rejectedAt: { type: Date },
    rejectionReason: { type: String },
    fcmNotificationSentAt: { type: Date },
    fcmRejectionSentAt: { type: Date }
}, { timestamps: true });

module.exports = mongoose.model('Expense', expenseSchema);
