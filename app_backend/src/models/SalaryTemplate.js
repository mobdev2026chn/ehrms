const mongoose = require('mongoose');

const SalaryTemplateSchema = new mongoose.Schema(
    {
        businessId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Company',
            required: true,
            index: true,
        },
        // Deprecated legacy key; keep for migration compatibility.
        templateKey: {
            type: String,
            required: false,
            trim: true,
            sparse: true,
        },
        name: {
            type: String,
            required: true,
            trim: true,
        },
        type: {
            type: String,
            enum: ['REGULAR', 'HOURLY', 'DAILY', 'MONTHLY'],
            required: false,
            default: 'REGULAR',
        },
        payableDaysRuleId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'SalaryPayableDaysRule',
            required: true,
        },
        earningComponentIds: [
            {
                type: mongoose.Schema.Types.ObjectId,
                ref: 'SalaryComponent',
            },
        ],
        deductionComponentIds: [
            {
                type: mongoose.Schema.Types.ObjectId,
                ref: 'SalaryComponent',
            },
        ],
        assignedStaff: [
            {
                type: mongoose.Schema.Types.ObjectId,
                ref: 'Staff',
            },
        ],
        isActive: {
            type: Boolean,
            default: true,
        },
    },
    { timestamps: true }
);

SalaryTemplateSchema.pre('save', function (next) {
    if (
        this.templateKey == null ||
        String(this.templateKey).trim() === ''
    ) {
        this.templateKey = undefined;
    }
    next();
});

SalaryTemplateSchema.index(
    { businessId: 1, templateKey: 1 },
    {
        name: 'businessId_1_templateKey_1',
        unique: true,
        partialFilterExpression: {
            templateKey: { $type: 'string', $ne: '' },
        },
    }
);
SalaryTemplateSchema.index({ businessId: 1, isActive: 1 });

module.exports = mongoose.model('SalaryTemplate', SalaryTemplateSchema);

