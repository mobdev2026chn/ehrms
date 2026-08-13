const mongoose = require('mongoose');

const grievanceStatusHistorySchema = new mongoose.Schema({
    grievanceId: { type: mongoose.Schema.Types.ObjectId, ref: 'Grievance', required: true, index: true },
    fromStatus: { type: String, default: '' },
    toStatus: { type: String, required: true },
    changedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    changedByName: { type: String, trim: true },
    reason: { type: String, trim: true },
    notes: { type: String, trim: true }
}, { timestamps: { createdAt: true, updatedAt: false } });

grievanceStatusHistorySchema.index({ grievanceId: 1, createdAt: -1 });

module.exports = mongoose.model('GrievanceStatusHistory', grievanceStatusHistorySchema);
