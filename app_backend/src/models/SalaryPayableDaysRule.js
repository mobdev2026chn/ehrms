const mongoose = require('mongoose');

const SalaryPayableDaysRuleSchema = new mongoose.Schema(
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
            required: false,
            trim: true,
            sparse: true,
        },
        title: {
            type: String,
            required: true,
            trim: true,
        },
        type: {
            type: String,
            enum: ['calendarMonth', 'fixedDays'],
            required: true,
        },
        daysPerMonth: { type: Number, default: 0 },
    },
    { timestamps: true }
);

SalaryPayableDaysRuleSchema.index(
    { businessId: 1, key: 1 },
    { unique: true, sparse: true }
);

module.exports = mongoose.model(
    'SalaryPayableDaysRule',
    SalaryPayableDaysRuleSchema
);

