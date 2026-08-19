const mongoose = require('../config/mongoose');

const activityLogSchema = new mongoose.Schema({
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    deviceId: { type: String, required: true },
    employeeID: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    timestamp: { type: Date, required: true },
    keystrokes: { type: Number },
    mouseClicks: { type: Number },
    scrollCount: { type: Number },
    activeWindow: {
        processName: String,
        appName: String,
        windowTitle: String,
        durationSeconds: Number
    },
    idleSeconds: { type: Number, default: 0 },
    score: { type: Number } // productivity score for this log (same formula as daily summary)
}, { timestamps: true, collection: 'monitoringlogs' });

activityLogSchema.index({ tenantId: 1, employeeID: 1, timestamp: -1 });
activityLogSchema.index({ deviceId: 1, timestamp: -1 });

module.exports = mongoose.model('ActivityLog', activityLogSchema);
