/**
 * Cache for attendance status per device (check-in/check-out from attendances).
 * Updated by attendanceCheckCron to avoid querying attendances on every agent request.
 * Collection: monitoringattendancecache
 */
const mongoose = require('../config/mongoose');


const cacheSchema = new mongoose.Schema({
    deviceId: { type: String, required: true, unique: true },
    employeeID: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    shouldTrack: { type: Boolean, default: false },
    lastCheckIn: { type: Date },
    lastCheckOut: { type: Date },
    /** Alert to show: 'start_tracking' | 'stop_tracking' | null. Cleared when agent acks. */
    alertToShow: { type: String, enum: ['start_tracking', 'stop_tracking', null], default: null },
    previousShouldTrack: { type: Boolean },
    /** Total tracked seconds reported by agent on last exit. Used to resume timer across sessions. */
    totalTrackedSecondsAtExit: { type: Number },
    totalTrackedSecondsAtExitUpdatedAt: { type: Date },
    lastUpdated: { type: Date, default: Date.now }
}, { timestamps: true, collection: 'monitoringattendancecache' });

// deviceId already indexed via unique: true above
cacheSchema.index({ lastUpdated: 1 });

module.exports = mongoose.model('MonitoringAttendanceCache', cacheSchema);
