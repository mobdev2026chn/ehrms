/**
 * Desktop monitoring activity logs (from EktaHR Desktop Agent).
 * Collection: monitoringlogs
 */
const mongoose = require('mongoose');

const activityLogSchema = new mongoose.Schema({
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    deviceId: { type: String, required: true },
    employeeID: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    timestamp: { type: Date, required: true },
    keystrokes: { type: Number, default: 0 },
    mouseClicks: { type: Number, default: 0 },
    scrollCount: { type: Number, default: 0 },
    activeWindow: {
        processName: String,
        appName: String,
        windowTitle: String,
        durationSeconds: Number
    },
    idleSeconds: { type: Number, default: 0 }
}, { timestamps: true, collection: 'monitoringlogs' });

activityLogSchema.index({ tenantId: 1, employeeID: 1, timestamp: -1 });
activityLogSchema.index({ deviceId: 1, timestamp: -1 });

module.exports = mongoose.model('ActivityLog', activityLogSchema);
