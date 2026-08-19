const mongoose = require('mongoose');

const grievanceEscalationRuleSchema = new mongoose.Schema({
    name: { type: String, required: true, trim: true, maxlength: 200 },
    description: { type: String, trim: true },
    categoryId: { type: mongoose.Schema.Types.ObjectId, ref: 'GrievanceCategory' },
    priority: { type: String, enum: ['Low', 'Medium', 'High', 'Critical'] },
    daysOpen: { type: Number, min: 1 },
    escalateTo: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    notifyCommittee: { type: Boolean, default: false },
    committeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'GrievanceCommittee' },
    slaDays: { type: Number, min: 1 },
    autoAssign: { type: Boolean, default: false },
    isActive: { type: Boolean, default: true },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true, index: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    softDeleted: { type: Boolean, default: false }
}, { timestamps: true });

module.exports = mongoose.model('GrievanceEscalationRule', grievanceEscalationRuleSchema);
