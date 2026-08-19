const mongoose = require('mongoose');

const sessionLogSchema = new mongoose.Schema({
    sessionId: { type: mongoose.Schema.Types.ObjectId, ref: 'LiveSession', required: true },
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    joinedAt: { type: Date },
    left: { type: Boolean, default: false },
    leftAt: { type: Date },
    feedbackSummary: { type: String },
    issues: { type: String },
    rating: { type: Number },
}, { timestamps: true });

module.exports = mongoose.model('SessionLog', sessionLogSchema);
