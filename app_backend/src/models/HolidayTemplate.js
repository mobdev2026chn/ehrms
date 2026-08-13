
const mongoose = require('mongoose');

const holidayTemplateSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true,
        trim: true
    },
    description: {
        type: String,
        trim: true
    },
    holidays: [{
        name: { type: String, required: true },
        date: { type: Date, required: true },
        type: {
            type: String,
            enum: ['National', 'Regional', 'Company'],
            default: 'National'
        }
    }],
    businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Company', // In Loan.js it refers to Company
        required: true
    },
    assignedStaff: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Staff'
    }],
    createdBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    isActive: {
        type: Boolean,
        default: true
    }
}, {
    timestamps: true
});

holidayTemplateSchema.index({ businessId: 1, name: 1 }, { unique: true });
holidayTemplateSchema.index({ businessId: 1, isActive: 1 });

module.exports = mongoose.model('HolidayTemplate', holidayTemplateSchema);
