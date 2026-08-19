const mongoose = require('mongoose');

const grievanceAttachmentSchema = new mongoose.Schema({
    grievanceId: { type: mongoose.Schema.Types.ObjectId, ref: 'Grievance', required: true, index: true },
    filename: { type: String, required: true },
    originalName: { type: String, trim: true },
    fileUrl: { type: String, required: true },
    filePath: { type: String, trim: true },
    fileType: { type: String, required: true },
    fileSize: { type: Number, required: true, min: 0 },
    uploadedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    isInternal: { type: Boolean, default: false }
}, { timestamps: { createdAt: true, updatedAt: false } });

grievanceAttachmentSchema.index({ grievanceId: 1, createdAt: -1 });

module.exports = mongoose.model('GrievanceAttachment', grievanceAttachmentSchema);
