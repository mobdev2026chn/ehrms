const mongoose = require('mongoose');

const grievanceNoteSchema = new mongoose.Schema({
    grievanceId: { type: mongoose.Schema.Types.ObjectId, ref: 'Grievance', required: true, index: true },
    noteType: {
        type: String,
        enum: ['Internal', 'Investigation', 'Public'],
        default: 'Internal',
        required: true
    },
    content: { type: String, required: true, trim: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    createdByName: { type: String, trim: true }
}, { timestamps: true });

grievanceNoteSchema.index({ grievanceId: 1, noteType: 1, createdAt: -1 });

module.exports = mongoose.model('GrievanceNote', grievanceNoteSchema);
