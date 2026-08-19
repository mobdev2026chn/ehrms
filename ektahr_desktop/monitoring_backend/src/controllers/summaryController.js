const path = require('path');
const MonitoringAttendanceCache = require('../models/MonitoringAttendanceCache');
const MonitoringDailySummary = require('../models/MonitoringDailySummary');
const Screenshot = require('../models/Screenshot');
const dailySummaryUpdater = require('../services/dailySummaryUpdater');
const appBackendRoot = require('../config/appBackendPath');
const Attendance = require(path.join(appBackendRoot, 'src', 'models', 'Attendance'));

/** Convert seconds to HH:MM:SS (e.g. 6529 -> "01:48:49"). */
function secondsToHhMmSs(totalSeconds) {
    const sec = Math.max(0, Math.floor(Number(totalSeconds) || 0));
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    return [h, m, s].map((n) => String(n).padStart(2, '0')).join(':');
}

/** Convert seconds to display format Xh Ym Zs (e.g. 6529 -> "1h 48m 49s", 180 -> "0h 3m 0s", 0 -> "0s"). Always shows h, m, s when non-zero total. */
function secondsToDisplay(totalSeconds) {
    const sec = Math.max(0, Math.floor(Number(totalSeconds) || 0));
    if (sec === 0) return '0s';
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    return `${h}h ${m}m ${s}s`;
}

/** GET /summary/today - Fetch from monitoringdailysummaries for timer/dashboard. All values come from DB only (no frontend calculation).
 *  - Unproductive / idle: from dailySummary.idleSec only (total idle seconds from activity logs).
 *  - Productive, totalTracked: from daily summary document.
 *  - Productivity: use only productivityScore (from monitoringdailysummaries.productivityScore). Display value as percentage and label as "Productivity score".
 *    Do NOT compute productivity as activeMinutes/totalWorkMinutes or active vs total; that calculation is removed.
 *  - summaryUpdatedAt: use to detect when to refresh (e.g. after logs are inserted). Poll GET /summary/today/updated for cheap refresh check.
 */
exports.getToday = async (req, res) => {
    try {
        const device = req.device;
        const employeeId = device?.employeeID;
        const tenantId = device?.tenantId;
        if (!employeeId || !tenantId) {
            return res.status(401).json({ message: 'Device context missing' });
        }
        const now = new Date();
        const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 0, 0, 0, 0));
        const end = new Date(start);
        end.setUTCDate(end.getUTCDate() + 1);

        let totalTrackedSeconds = 0;
        let productiveSeconds = 0;
        let unproductiveSeconds = 0;
        let activeMinutes = 0;
        let idleMinutes = 0;
        let productivityScore = 0;

        const [dailySummary, cache, lastScreenshot, attRecord] = await Promise.all([
            MonitoringDailySummary.findOne({ businessId: tenantId, employeeId, date: start }).lean(),
            device?.deviceId
                ? MonitoringAttendanceCache.findOne({ deviceId: device.deviceId }).select('lastCheckIn lastCheckOut totalTrackedSecondsAtExit totalTrackedSecondsAtExitUpdatedAt').lean()
                : null,
            device?.deviceId
                ? Screenshot.findOne({ deviceId: device.deviceId, tenantId, timestamp: { $gte: start, $lt: end } }).sort({ timestamp: -1 }).select('timestamp').lean()
                : null,
            Attendance.findOne({
                $or: [{ employeeId }, { user: employeeId }],
                date: { $gte: start, $lt: end }
            })
                .select('punchIn punchOut')
                .lean()
        ]);

        if (dailySummary) {
            totalTrackedSeconds = dailySummary.totalTrackedSeconds ?? dailySummaryUpdater.toSeconds(dailySummary.totalTrackedTime);
            productiveSeconds = dailySummaryUpdater.toSeconds(dailySummary.productiveTime);
            unproductiveSeconds = Math.max(dailySummaryUpdater.toSeconds(dailySummary.unproductiveTime), typeof dailySummary.idleSec === 'number' ? dailySummary.idleSec : 0);
            activeMinutes = Math.round(productiveSeconds / 60);
            idleMinutes = Math.round(unproductiveSeconds / 60);
            productivityScore = dailySummary.productivityScore ?? 0;
        }

        const deviceId = device?.deviceId;
        let lastCheckIn = cache?.lastCheckIn ?? attRecord?.punchIn ?? null;
        let lastCheckOut = cache?.lastCheckOut ?? attRecord?.punchOut ?? null;
        const lastScreenshotAt = lastScreenshot?.timestamp ?? null;

        if (deviceId && (lastCheckIn != null || lastCheckOut != null) && (!cache?.lastCheckIn && !cache?.lastCheckOut)) {
            try {
                const setFields = { lastUpdated: new Date() };
                if (lastCheckIn != null) setFields.lastCheckIn = lastCheckIn;
                if (lastCheckOut != null) setFields.lastCheckOut = lastCheckOut;
                await MonitoringAttendanceCache.findOneAndUpdate(
                    { deviceId },
                    { $set: setFields, $setOnInsert: { deviceId, employeeID: employeeId, tenantId } },
                    { upsert: true }
                );
            } catch { /* ignore */ }
        }

        if (deviceId && cache) {
            const exitSec = cache.totalTrackedSecondsAtExit;
            const exitAt = cache.totalTrackedSecondsAtExitUpdatedAt ? new Date(cache.totalTrackedSecondsAtExitUpdatedAt) : null;
            const todayEnd = new Date(start);
            todayEnd.setUTCDate(todayEnd.getUTCDate() + 1);
            if (typeof exitSec === 'number' && exitSec > totalTrackedSeconds && exitAt && exitAt >= start && exitAt < todayEnd) {
                totalTrackedSeconds = exitSec;
            }
        }

        const totalWorkMinutes = Math.round(totalTrackedSeconds / 60);
        const idleSec = unproductiveSeconds;

        const payload = {
            totalWorkMinutes,
            totalTrackedSeconds,
            productiveSeconds,
            unproductiveSeconds,
            idleSec,
            activeMinutes,
            idleMinutes,
            productivityScore,
            score: productivityScore,
            productivityScoreDisplay: `${Math.round(productivityScore)}%`,
            productivityScoreLabel: 'Productivity score',
            totalTrackedTimeHhMmSs: secondsToHhMmSs(totalTrackedSeconds),
            totalTrackedTimeDisplay: secondsToDisplay(totalTrackedSeconds),
            productiveTimeHhMmSs: secondsToHhMmSs(productiveSeconds),
            productiveTimeDisplay: secondsToDisplay(productiveSeconds),
            unproductiveTimeHhMmSs: secondsToHhMmSs(unproductiveSeconds),
            unproductiveTimeDisplay: secondsToDisplay(unproductiveSeconds),
            idleSecHhMmSs: secondsToHhMmSs(idleSec),
            idleSecDisplay: secondsToDisplay(idleSec),
            status: device.status ?? 'active',
            lastCheckIn: lastCheckIn ? lastCheckIn.toISOString() : null,
            lastCheckOut: lastCheckOut ? lastCheckOut.toISOString() : null,
            lastScreenshotAt: lastScreenshotAt ? lastScreenshotAt.toISOString() : null,
            startedTime: dailySummary?.startedTime ? dailySummary.startedTime.toISOString() : null,
            endedTime: dailySummary?.endedTime ? dailySummary.endedTime.toISOString() : null,
            summaryUpdatedAt: dailySummary?.updatedAt ? dailySummary.updatedAt.toISOString() : null
        };

        if (dailySummary) {
            payload.date = dailySummary.date;
            payload.totalTrackedMinutes = dailySummary.totalTrackedMinutes ?? totalWorkMinutes;
            payload.totalTrackedTime = dailySummary.totalTrackedTime ?? totalTrackedSeconds;
            payload.productiveTime = productiveSeconds;
            payload.unproductiveTime = unproductiveSeconds;
            payload.activityTotals = dailySummary.activityTotals ?? { keystrokes: 0, mouseClicks: 0, scrollCount: 0 };
            payload.screenshotCount = dailySummary.screenshotCount ?? 0;
            payload.screenshotsCaptured = dailySummary.screenshotsCaptured ?? dailySummary.screenshotCount ?? 0;
            payload.scoreLogCount = dailySummary.scoreLogCount ?? 0;
            payload.sumOfScores = dailySummary.sumOfScores ?? productivityScore;
            payload.checkInTime = dailySummary.checkInTime ? dailySummary.checkInTime.toISOString() : null;
            payload.checkOutTime = dailySummary.checkOutTime ? dailySummary.checkOutTime.toISOString() : null;
        }

        res.status(200).json(payload);
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

/** GET /summary/today/updated - Returns only the daily summary updatedAt for this device. Poll this to know when to refetch /summary/today (e.g. after logs are inserted). */
exports.getTodayUpdated = async (req, res) => {
    try {
        const device = req.device;
        const employeeId = device?.employeeID;
        const tenantId = device?.tenantId;
        if (!employeeId || !tenantId) {
            return res.status(401).json({ message: 'Device context missing' });
        }
        const now = new Date();
        const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 0, 0, 0, 0));
        const doc = await MonitoringDailySummary.findOne({ businessId: tenantId, employeeId, date: start })
            .select('updatedAt')
            .lean();
        res.status(200).json({
            updatedAt: doc?.updatedAt ? doc.updatedAt.toISOString() : null
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};
