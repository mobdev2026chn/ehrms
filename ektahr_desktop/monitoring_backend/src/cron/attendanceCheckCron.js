/**
 * Attendance check cron: runs separately for best server performance.
 * Uses Attendance collection punchIn / punchOut for TODAY's record only (by date).
 * - No check-in for today (no attendance record or no punchIn for today) → do not track.
 *   After 12:00 AM, staff who did not check out the previous day are not tracked until they check in for the new date.
 * - Checked in for today (punchIn set, punchOut null) → track; show alert "You have checked in. Start tracking."
 * - Checked out for today (punchOut set) → insert productivity for that date if not there, then stop tracking; show alert "You have checked out. Stop tracking."
 * Updates MonitoringAttendanceCache. The agent polls /api/device/attendance-status which reads from cache.
 */
require('dotenv').config();
const path = require('path');
const mongoose = require('../config/mongoose');
const connectDB = require('../config/db');

const Device = require('../models/Device');
const MonitoringAttendanceCache = require('../models/MonitoringAttendanceCache');
const appBackendRoot = require('../config/appBackendPath');
const Attendance = require(path.join(appBackendRoot, 'src', 'models', 'Attendance'));
const { upsertDailySummaryForStaff } = require('./dailySummary');
const dailySummaryUpdater = require('../services/dailySummaryUpdater');

function startOfDayUTC(d) {
    const x = new Date(d);
    x.setUTCHours(0, 0, 0, 0);
    return x;
}

async function runAttendanceCheck() {
    await connectDB();

    const today = startOfDayUTC(new Date());

    // Only devices that are logged in and active (not exited/logout) – tracking is allowed only for these
    const devices = await Device.find({
        isActive: true,
        status: 'active'
    })
        .select('deviceId employeeID tenantId')
        .lean();

    let updated = 0;
    for (const dev of devices) {
        try {
            const endOfToday = new Date(today);
            endOfToday.setUTCDate(endOfToday.getUTCDate() + 1);
            // Attendance model: punchIn / punchOut define start and end of tracking for the day
            const att = await Attendance.findOne({
                $or: [{ employeeId: dev.employeeID }, { user: dev.employeeID }],
                date: { $gte: today, $lt: endOfToday }
            })
                .select('punchIn punchOut')
                .lean();

            const punchIn = att?.punchIn ? new Date(att.punchIn) : null;
            const punchOut = att?.punchOut ? new Date(att.punchOut) : null;
            // Track only when checked in and not yet checked out (no punchIn → don't track)
            const shouldTrack = !!(punchIn && !punchOut);

            const existing = await MonitoringAttendanceCache.findOne({ deviceId: dev.deviceId }).lean();
            const previousShouldTrack = existing?.shouldTrack ?? null;

            let alertToShow = null;
            if (previousShouldTrack === false && shouldTrack) {
                alertToShow = 'start_tracking';
                try {
                    await dailySummaryUpdater.setCheckInTime(dev.tenantId, dev.employeeID, today, punchIn);
                    await upsertDailySummaryForStaff(dev.tenantId, dev.employeeID, today);
                } catch (summaryErr) { /* ignore */ }
            } else if (previousShouldTrack === true && !shouldTrack) {
                alertToShow = 'stop_tracking';
                try {
                    await dailySummaryUpdater.setCheckOutTime(dev.tenantId, dev.employeeID, today, punchOut);
                    await upsertDailySummaryForStaff(dev.tenantId, dev.employeeID, today);
                } catch (summaryErr) { /* ignore */ }
            }

            await MonitoringAttendanceCache.findOneAndUpdate(
                { deviceId: dev.deviceId },
                {
                    $set: {
                        deviceId: dev.deviceId,
                        employeeID: dev.employeeID,
                        tenantId: dev.tenantId,
                        shouldTrack,
                        lastCheckIn: punchIn,
                        lastCheckOut: punchOut,
                        alertToShow,
                        previousShouldTrack: existing?.shouldTrack ?? shouldTrack,
                        lastUpdated: new Date()
                    }
                },
                { upsert: true, new: true }
            );
            updated++;
        } catch (err) { /* ignore */ }
    }

    return updated;
}

const INTERVAL_MS = 60 * 1000; // 1 min

if (require.main === module) {
    console.log('cron started');
    const runOnce = () => runAttendanceCheck().catch(() => {});
    runOnce();
    setInterval(runOnce, INTERVAL_MS);
}

module.exports = { runAttendanceCheck };
