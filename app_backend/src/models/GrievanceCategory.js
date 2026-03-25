const mongoose = require('mongoose');

const grievanceCategorySchema = new mongoose.Schema({
    name: { type: String, required: true, trim: true, maxlength: 100 },
    description: { type: String, trim: true },
    isActive: { type: Boolean, default: true },
    requiresCommittee: { type: Boolean, default: false },
    autoNotifyCommittee: { type: Boolean, default: false },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true, index: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    softDeleted: { type: Boolean, default: false }
}, { timestamps: true });

grievanceCategorySchema.index({ businessId: 1, name: 1 }, { unique: true });

module.exports = mongoose.model('GrievanceCategory', grievanceCategorySchema);
