const mongoose = require('mongoose');

const defaultPfEsi = {
    employerPFRate: 0,
    employeePFRate: 0,
    pfThreshold: 0,
    pfStaticAmount: 0,
    employerESIRate: 0,
    employeeESIRate: 0,
    esiThreshold: 0,
};

const SalaryPayrollConfigSchema = new mongoose.Schema(
    {
        businessId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Company',
            required: true,
            unique: true,
        },
        pfEsiSettings: {
            type: {
                employerPFRate: { type: Number, default: 0 },
                employeePFRate: { type: Number, default: 0 },
                pfThreshold: { type: Number, default: 0 },
                pfStaticAmount: { type: Number, default: 0 },
                employerESIRate: { type: Number, default: 0 },
                employeeESIRate: { type: Number, default: 0 },
                esiThreshold: { type: Number, default: 0 },
            },
            default: () => ({ ...defaultPfEsi }),
        },
        activePayableDaysRuleId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'SalaryPayableDaysRule',
            default: null,
        },
    },
    { timestamps: true }
);

module.exports = mongoose.model(
    'SalaryPayrollConfig',
    SalaryPayrollConfigSchema
);

