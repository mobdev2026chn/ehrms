/**
 * Real-time updater for monitoringdailysummaries.
 * Called when activity logs or screenshots are inserted.
 * Time format: "minutes:seconds" (e.g. "130:20" = 130 min 20 sec).
 */
const MonitoringDailySummary = require('../models/MonitoringDailySummary');
const MonitoringSettings = require('../models/MonitoringSettings');

const DEFAULT_SETTINGS = {
    expectedActivityPerMinute: { keystrokes: 40, mouseClicks: 20, scrolls: 10 },
    scoreRange: { min: 0, max: 100 },
    weights: { activityWeight: 0.7, idleWeight: 0.3 }
};

// Formula: expectedActivityPerMinute + interval (windowSeconds) + weights from settings.
// key/mouse/scroll = min(1, value/expected); activityScore = max(key,mouse)*0.5 + avg(key,mouse,scroll)*0.5; idleFactor = (windowSec-idle)/windowSec; score = (activityScore*activityWeight + idleFactor*idleWeight)*100.
function computeProductivityScore(settings, perWindow, windowSeconds = 60) {
    const ps = settings?.productivitySettings ?? {};
    const exp = ps.expectedActivityPerMinute ?? DEFAULT_SETTINGS.expectedActivityPerMinute;
    const range = ps.scoreRange ?? DEFAULT_SETTINGS.scoreRange;
    const weights = ps.weights ?? DEFAULT_SETTINGS.weights;
    const activityWeight = Number(weights.activityWeight);
    const idleWeight = Number(weights.idleWeight);
    const sumW = activityWeight + idleWeight;
    const actW = sumW > 0 ? activityWeight / sumW : 0.7;
    const idlW = sumW > 0 ? idleWeight / sumW : 0.3;

    const windowSec = Math.max(1, Number(windowSeconds) || 60);
    const idleMax = windowSec;

    // Expected activity in settings is per minute; scale to this window
    const scale = windowSec / 60;
    const expectedKeys = (exp.keystrokes || 1) * scale;
    const expectedClicks = (exp.mouseClicks || 1) * scale;
    const expectedScrolls = (exp.scrolls || 1) * scale;

    const keyScore = Math.min(1, (perWindow.keystrokes || 0) / expectedKeys);
    const mouseScore = Math.min(1, (perWindow.mouseClicks || 0) / expectedClicks);
    const scrollScore = Math.min(1, (perWindow.scrollCount || 0) / expectedScrolls);

    const maxKeyMouse = Math.max(keyScore, mouseScore);
    const avgKeyMouseScroll = (keyScore + mouseScore + scrollScore) / 3;
    const activityScore = (maxKeyMouse * 0.5) + (avgKeyMouseScroll * 0.5);

    const idleSeconds = Math.min(idleMax, perWindow.idleSeconds || 0);
    const idleFactor = (idleMax - idleSeconds) / idleMax;

    let prod = (activityScore * actW + idleFactor * idlW) * 100;
    prod = Math.max(range.min ?? 0, Math.min(range.max ?? 100, prod));
    const result = Math.round(prod * 10) / 10;
    return result;
}

/**
 * Format total seconds as "minutes:seconds" (e.g. 7820 -> "130:20").
 */
function formatMinutesSeconds(totalSeconds) {
    const s = Math.round(Math.max(0, totalSeconds));
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${String(sec).padStart(2, '0')}`;
}

/**
 * Parse "minutes:seconds" to total seconds (e.g. "130:20" -> 7820).
 */
function parseMinutesSeconds(str) {
    if (!str || typeof str !== 'string') return 0;
    const parts = str.trim().split(':');
    if (parts.length < 2) return 0;
    const m = parseInt(parts[0], 10) || 0;
    const s = parseInt(parts[1], 10) || 0;
    return m * 60 + s;
}

/** Get seconds from stored value: number (seconds) or legacy "min:sec" string. */
function toSeconds(val) {
    if (val == null) return 0;
    if (typeof val === 'number') return Math.max(0, val);
    return parseMinutesSeconds(val);
}

/**
 * Add duration (seconds) to a time string, return new "minutes:seconds" string.
 */
function addSecondsToTimeString(timeStr, secondsToAdd) {
    const total = parseMinutesSeconds(timeStr) + Math.round(secondsToAdd);
    return formatMinutesSeconds(total);
}

/**
 * Update monitoringdailysummaries when an activity log is inserted.
 * Each activity log = 1 minute: productive = (60 - idleSeconds), unproductive = idleSeconds (capped at 60).
 * Break, Pause, Meeting are excluded (activity is never stored when device is in those statuses).
 * Also increments activityTotals (keystrokes, mouseClicks, scrollCount) from the log.
 * @param {ObjectId} tenantId
 * @param {ObjectId} employeeId
 * @param {Date} timestamp - log timestamp
 * @param {number} idleSeconds - from activity log
 * @param {number} durationSeconds - typically 60 (1 log = 1 min); may vary for first/last
 * @param {{ keystrokes?: number, mouseClicks?: number, scrollCount?: number }} [activityTotals] - activity counts from the log
 * @param {number} [logScore] - productivity score from this log (when provided, daily productivityScore = sum of all log scores / number of scores for that date)
 * @param {Object} [existingSettings] - if already fetched (e.g. from activityProcessor), pass to avoid re-fetch; used when computing productivity from formula (no logScore)
 */
<<<<<<< HEAD
=======
/** Max seconds to add per log; prevents inflation when gap between logs is huge (e.g. agent offline for days). */
const MAX_DURATION_PER_LOG_SEC = 300;

>>>>>>> development
async function updateFromActivityLog(tenantId, employeeId, timestamp, idleSeconds, durationSeconds = 60, activityTotals = {}, logScore = undefined, existingSettings = null) {
    const date = new Date(timestamp);
    date.setUTCHours(0, 0, 0, 0);

<<<<<<< HEAD
    const idle = Math.min(durationSeconds, Math.max(0, idleSeconds || 0));
    const productive = Math.max(0, durationSeconds - idle);
=======
    const durationCapped = Math.min(Math.max(0, durationSeconds || 60), MAX_DURATION_PER_LOG_SEC);
    const idle = Math.min(durationCapped, Math.max(0, idleSeconds || 0));
    const productive = Math.max(0, durationCapped - idle);
>>>>>>> development

    const doc = await MonitoringDailySummary.findOne({ businessId: tenantId, employeeId, date }).lean();
    const currentProd = toSeconds(doc?.productiveTime);
    const currentUnprod = toSeconds(doc?.unproductiveTime);

    const newProdSec = currentProd + productive;
    const newUnprodSec = currentUnprod + idle;
    const newTotalSec = newProdSec + newUnprodSec;

    const k = activityTotals.keystrokes ?? 0;
    const m = activityTotals.mouseClicks ?? 0;
    const s = activityTotals.scrollCount ?? 0;

    const totalKeystrokes = (doc?.activityTotals?.keystrokes ?? 0) + k;
    const totalMouseClicks = (doc?.activityTotals?.mouseClicks ?? 0) + m;
    const totalScrollCount = (doc?.activityTotals?.scrollCount ?? 0) + s;
    const totalIdleSeconds = newUnprodSec;
    const totalMinutes = newTotalSec > 0 ? newTotalSec / 60 : 1;

    let productivityScore;
    if (typeof logScore === 'number') {
        const currentCount = doc?.scoreLogCount ?? 0;
        const currentAvg = doc?.sumOfScores ?? 0; // sumOfScores stores average (sum of scores / no of logs)
        const previousSum = currentAvg * currentCount;
        const newSum = previousSum + logScore;
        const newCount = currentCount + 1;
        productivityScore = Math.round((newSum / newCount) * 10) / 10;
    } else {
        // Daily aggregate: normalize to per-minute (window = 60s) for formula
        const perMinute = {
            keystrokes: totalKeystrokes / totalMinutes,
            mouseClicks: totalMouseClicks / totalMinutes,
            scrollCount: totalScrollCount / totalMinutes,
            idleSeconds: totalIdleSeconds / totalMinutes
        };
        const settings = existingSettings ?? (await MonitoringSettings.findOne({ businessId: tenantId }).lean());
        productivityScore = computeProductivityScore(settings, perMinute, 60);
    }

    const activeMinutes = Math.round(newProdSec / 60);

    const tsDate = new Date(timestamp);
    const setFields = {
        productiveTime: newProdSec,
        unproductiveTime: newUnprodSec,
        totalTrackedTime: newTotalSec,
        totalTrackedSeconds: newTotalSec,
        totalTrackedMinutes: Math.round(totalMinutes),
        activeMinutes,
        idleSec: newUnprodSec, // total idle seconds from activity logs for this date
        productivityScore,
        activityTotals: {
            keystrokes: totalKeystrokes,
            mouseClicks: totalMouseClicks,
            scrollCount: totalScrollCount
        }
    };
    if (typeof logScore === 'number') {
        const currentCount = doc?.scoreLogCount ?? 0;
        const currentAvg = doc?.sumOfScores ?? 0;
        const previousSum = currentAvg * currentCount;
        const newCount = currentCount + 1;
        setFields.sumOfScores = (previousSum + logScore) / newCount; // sumOfScores = sum of scores / no of logs (average)
        setFields.scoreLogCount = newCount;
    }
    const update = {
        $set: setFields,
        $min: { startedTime: tsDate },
        $max: { endedTime: tsDate }
    };
    if (!doc) {
        update.$setOnInsert = { businessId: tenantId, employeeId, date };
    }
    await MonitoringDailySummary.findOneAndUpdate(
        { businessId: tenantId, employeeId, date },
        update,
        { upsert: true, setDefaultsOnInsert: true, new: true }
    );
}

/**
 * Increment screenshotCount in monitoringdailysummaries when a screenshot is captured.
 */
async function incrementScreenshotCount(tenantId, employeeId, timestamp) {
    const date = new Date(timestamp);
    date.setUTCHours(0, 0, 0, 0);

    await MonitoringDailySummary.findOneAndUpdate(
        { businessId: tenantId, employeeId, date },
        { $inc: { screenshotCount: 1, screenshotsCaptured: 1 }, $setOnInsert: { businessId: tenantId, employeeId, date } },
        { upsert: true }
    );
}

/**
 * Set checkInTime when user checks in (called from attendance flow).
 */
async function setCheckInTime(tenantId, employeeId, date, checkInTime) {
    const d = new Date(date);
    d.setUTCHours(0, 0, 0, 0);
    await MonitoringDailySummary.findOneAndUpdate(
        { businessId: tenantId, employeeId, date: d },
        { $set: { checkInTime: new Date(checkInTime) } },
        { upsert: true, setDefaultsOnInsert: true }
    );
}

/**
 * Set checkOutTime and final values when user checks out.
 */
async function setCheckOutTime(tenantId, employeeId, date, checkOutTime) {
    const d = new Date(date);
    d.setUTCHours(0, 0, 0, 0);
    await MonitoringDailySummary.findOneAndUpdate(
        { businessId: tenantId, employeeId, date: d },
        { $set: { checkOutTime: new Date(checkOutTime) } },
        { upsert: true }
    );
}

module.exports = {
    computeProductivityScore,
    formatMinutesSeconds,
    parseMinutesSeconds,
    toSeconds,
    addSecondsToTimeString,
    updateFromActivityLog,
    incrementScreenshotCount,
    setCheckInTime,
    setCheckOutTime
};
