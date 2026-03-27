const mongoose = require('mongoose');

const SalaryComponentSchema = new mongoose.Schema(
    {
        businessId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Company',
            required: true,
            index: true,
        },
        // Legacy string key support.
        key: {
            type: String,
            required: true,
            trim: true,
        },
        kind: {
            type: String,
            enum: ['earning', 'deduction'],
            required: true,
        },
        name: {
            type: String,
            required: true,
            trim: true,
        },
        basis: {
            type: String,
            enum: ['fixed', 'percentOfBasic'],
            required: true,
        },
        value: { type: Number, default: 0 },
        consideredForEPF: { type: Boolean, default: false },
        consideredForESI: { type: Boolean, default: false },
        isBasicBase: { type: Boolean, default: false },
        taxImplication: {
            type: String,
            enum: ['pre-tax', 'post-tax'],
            default: 'pre-tax',
        },
    },
    { timestamps: true }
);

SalaryComponentSchema.index(
    { businessId: 1, key: 1 },
    { unique: true, sparse: true }
);

module.exports = mongoose.model('SalaryComponent', SalaryComponentSchema);

