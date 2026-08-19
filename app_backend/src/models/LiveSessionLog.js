const mongoose = require('mongoose');

// Matches web backend LiveSessionLog.model.ts — same collection (livesessionlogs) for heatmap live session count
const liveSessionLogSchema = new mongoose.Schema({
    sessionId: { type: mongoose.Schema.Types.ObjectId, ref: 'LiveSession', required: true },
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    joinedAt: { type: Date },
    leftAt: { type: Date },
    sessionPurpose: { type: String },
    feedbackSummary: { type: String },
    issues: { type: String },
    rating: { type: Number, min: 1, max: 5 },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
}, { timestamps: true });

liveSessionLogSchema.index({ sessionId: 1, employeeId: 1 }, { unique: true });
liveSessionLogSchema.index({ employeeId: 1 });
liveSessionLogSchema.index({ businessId: 1 });
liveSessionLogSchema.index({ joinedAt: 1 });

module.exports = mongoose.model('LiveSessionLog', liveSessionLogSchema);
