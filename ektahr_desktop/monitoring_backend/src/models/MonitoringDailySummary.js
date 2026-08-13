const mongoose = require('../config/mongoose');

const monitoringDailySummarySchema = new mongoose.Schema({
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    date: { type: Date, required: true }, // start of day (UTC); document is summary for this date only

    // Core time fields (all in seconds, number) - excludes break, pause, meeting
    productiveTime: { type: Number, default: 0 },     // productive seconds
    unproductiveTime: { type: Number, default: 0 },   // unproductive/idle seconds
    totalTrackedTime: { type: Number, default: 0 }, // total tracked seconds

    totalTrackedSeconds: { type: Number, default: 0 },

    // Legacy/compat
    totalTrackedMinutes: { type: Number, default: 0 },
    activeMinutes: { type: Number, default: 0 },
    idleSec: { type: Number, default: 0 }, // total idle seconds from activity logs for this date only

    activityTotals: {
        keystrokes: { type: Number, default: 0 },
        mouseClicks: { type: Number, default: 0 },
        scrollCount: { type: Number, default: 0 }
    },

    productivityScore: { type: Number, default: 0 },
    sumOfScores: { type: Number, default: 0 },   // sum of scores / no of logs (average score for the date)
    scoreLogCount: { type: Number, default: 0 },   // number of logs with score

    screenshotCount: { type: Number, default: 0 },
    screenshotsCaptured: { type: Number, default: 0 }, // legacy alias

    checkInTime: { type: Date },
    checkOutTime: { type: Date },

    // Timer window for the day: first and last activity log timestamps (today)
    startedTime: { type: Date }, // datetime when monitoring timer started (first activity today)
    endedTime: { type: Date }    // datetime when monitoring timer stopped (last activity today)
}, { timestamps: true, collection: 'monitoringdailysummaries' });

monitoringDailySummarySchema.index({ businessId: 1, employeeId: 1, date: -1 }, { unique: true });
monitoringDailySummarySchema.index({ businessId: 1, date: -1 });

module.exports = mongoose.model('MonitoringDailySummary', monitoringDailySummarySchema);
