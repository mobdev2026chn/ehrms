const mongoose = require('mongoose');

const grievanceFeedbackSchema = new mongoose.Schema({
    grievanceId: { type: mongoose.Schema.Types.ObjectId, ref: 'Grievance', required: true, unique: true, index: true },
    rating: { type: Number, required: true, min: 1, max: 5 },
    feedback: { type: String, required: true, trim: true },
    submittedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true }
}, { timestamps: { createdAt: true, updatedAt: false } });

module.exports = mongoose.model('GrievanceFeedback', grievanceFeedbackSchema);
