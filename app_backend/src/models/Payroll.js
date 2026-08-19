const mongoose = require('mongoose');

const payrollSchema = new mongoose.Schema({
    employeeId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Staff',
        required: true
    },
    month: {
        type: Number,
        required: true,
        min: 1,
        max: 12
    },
    year: {
        type: Number,
        required: true
    },
    grossSalary: {
        type: Number,
        required: true
    },
    deductions: {
        type: Number,
        default: 0
    },
    netPay: {
        type: Number,
        required: true
    },
    components: [{
        name: String,
        amount: Number,
        type: {
            type: String,
            enum: ['earning', 'deduction']
        }
    }],
    status: {
        type: String,
        enum: ['Pending', 'Processed', 'Paid'],
        default: 'Pending'
    },
    processedAt: Date,
    paidAt: Date,
    payslipUrl: String,
    businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Company'
    }
}, {
    timestamps: true
});

payrollSchema.index({ employeeId: 1, month: 1, year: 1 }, { unique: true });
payrollSchema.index({ businessId: 1 });

module.exports = mongoose.model('Payroll', payrollSchema);
