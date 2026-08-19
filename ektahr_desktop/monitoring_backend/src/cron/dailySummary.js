/**
 * Daily summary: aggregates monitoringlogs, monitoringscreenshots
 * per employee per day and upserts monitoringDailySummary (score = average of log scores from monitoringlogs).
 * NOTE: Normal flow uses on-checkout insert in attendanceCheckCron (when staff checks out).
 * This script is for manual backfill (e.g. historical dates) or catch-up.
 * Run: node src/cron/dailySummary.js [YYYY-MM-DD]
 */
require('dotenv').config();
const path = require('path');
const mongoose = require('../config/mongoose');
const connectDB = require('../config/db');
const appBackendRoot = require('../config/appBackendPath');
const ActivityLog = require('../models/ActivityLog');
const Screenshot = require('../models/Screenshot');
const MonitoringSettings = require('../models/MonitoringSettings');
const MonitoringStaff = require('../models/MonitoringStaff');
const MonitoringDailySummary = require('../models/MonitoringDailySummary');
const dailySummaryUpdater = require('../services/dailySummaryUpdater');

function normalizeToDate(d) {
    const x = new Date(d);
    x.setUTCHours(0, 0, 0, 0);
    return x;
}

async function runDailySummary(targetDate) {
    await connectDB();

    const date = targetDate ? normalizeToDate(targetDate) : normalizeToDate(new Date());
    const start = new Date(date);
    const end = new Date(date);
    end.setUTCDate(end.getUTCDate() + 1);

    const pipeline = [
        { $match: { timestamp: { $gte: start, $lt: end } } },
        {
            $group: {
                _id: { tenantId: '$tenantId', employeeID: '$employeeID' },
                totalKeystrokes: { $sum: '$keystrokes' },
                totalMouseClicks: { $sum: '$mouseClicks' },
                totalScrollCount: { $sum: '$scrollCount' },
                totalIdleSeconds: { $sum: '$idleSeconds' },
                count: { $sum: 1 },
                firstTimestamp: { $min: '$timestamp' },
                lastTimestamp: { $max: '$timestamp' },
                sumOfScores: { $sum: { $cond: [{ $ne: ['$score', null] }, '$score', 0] } },
                scoreLogCount: { $sum: { $cond: [{ $ne: ['$score', null] }, 1, 0] } }
            }
        }
    ];

    const activityGroups = await ActivityLog.aggregate(pipeline);

    const screenshotPipeline = [
        { $match: { timestamp: { $gte: start, $lt: end } } },
        { $group: { _id: { tenantId: '$tenantId', employeeID: '$employeeID' }, count: { $sum: 1 } } }
    ];

    const screenshotGroups = await Screenshot.aggregate(screenshotPipeline);

    const businessIds = [...new Set(activityGroups.map((g) => g._id.tenantId.toString()))];
    const settingsMap = new Map();
    const staffSetMap = new Map();
    for (const bid of businessIds) {
        const s = await MonitoringSettings.findOne({ businessId: bid }).lean();
        settingsMap.set(bid, s);
        if (s?.monitoringEnabled === false) continue;
        const staffs = await MonitoringStaff.find({ businessId: bid, enabled: true }).select('employeeId').lean();
        const ids = new Set(staffs.map((st) => st.employeeId.toString()));
        staffSetMap.set(bid, ids);
    }

    let upserted = 0;

    for (const ag of activityGroups) {
        const businessId = ag._id.tenantId;
        const employeeId = ag._id.employeeID;
        const bidStr = businessId.toString();
        const settings = settingsMap.get(bidStr);
        if (settings?.monitoringEnabled === false) continue;
        const staffSet = staffSetMap.get(bidStr);
        if (staffSet && staffSet.size > 0 && !staffSet.has(employeeId.toString())) continue; // only track staff in MonitoringStaff when list exists

        const ssGroup = screenshotGroups.find(
            (s) => s._id.tenantId.toString() === bidStr && s._id.employeeID.toString() === employeeId.toString()
        );

        const totalMinutes = ag.count || 1;
        const totalIdleSeconds = ag.totalIdleSeconds || 0;
        const totalTrackedSeconds = Math.round(totalMinutes * 60);
        const scoreLogCount = ag.scoreLogCount ?? 0;
        const rawSumOfScores = ag.sumOfScores ?? 0;
        const avgScore = (scoreLogCount > 0) ? rawSumOfScores / scoreLogCount : 0;
        const productivityScore = Math.round(avgScore * 10) / 10;
        const sumOfScores = productivityScore; // sumOfScores = sum of scores / no of logs (average)
        const productiveSeconds = Math.max(0, totalTrackedSeconds - totalIdleSeconds);
        const unproductiveSeconds = totalIdleSeconds;
        const activeMinutes = Math.round(productiveSeconds / 60);

        await MonitoringDailySummary.findOneAndUpdate(
            { businessId, employeeId, date },
            {
                $set: {
                    businessId,
                    employeeId,
                    date,
                    productiveTime: productiveSeconds,
                    unproductiveTime: unproductiveSeconds,
                    totalTrackedTime: totalTrackedSeconds,
                    totalTrackedMinutes: Math.round(totalMinutes),
                    totalTrackedSeconds,
                    activeMinutes: Math.round(activeMinutes),
                    idleSec: totalIdleSeconds, // total idle seconds from activity logs for this date
                    activityTotals: {
                        keystrokes: ag.totalKeystrokes,
                        mouseClicks: ag.totalMouseClicks,
                        scrollCount: ag.totalScrollCount
                    },
                    productivityScore,
                    sumOfScores,
                    scoreLogCount,
                    screenshotCount: ssGroup?.count ?? 0,
                    screenshotsCaptured: ssGroup?.count ?? 0,
                    startedTime: ag.firstTimestamp ?? null,
                    endedTime: ag.lastTimestamp ?? null
                }
            },
            { upsert: true, new: true }
        );
        upserted++;
    }

    return upserted;
}

/**
 * Upsert daily summary for a single staff (called on checkout).
 * @param {ObjectId} businessId - tenantId
 * @param {ObjectId} employeeId - staff _id
 * @param {Date} targetDate - date (start of day)
 * @returns {Promise<boolean>} - true if upserted
 */
async function upsertDailySummaryForStaff(businessId, employeeId, targetDate) {
    const date = normalizeToDate(targetDate);
    const start = new Date(date);
    const end = new Date(date);
    end.setUTCDate(end.getUTCDate() + 1);

    const AttendanceModel = require(path.join(appBackendRoot, 'src', 'models', 'Attendance'));
    const [aggResult, att] = await Promise.all([
        ActivityLog.aggregate([
            { $match: { tenantId: businessId, employeeID: employeeId, timestamp: { $gte: start, $lt: end } } },
            {
                $group: {
                    _id: null,
                    totalKeystrokes: { $sum: '$keystrokes' },
                    totalMouseClicks: { $sum: '$mouseClicks' },
                    totalScrollCount: { $sum: '$scrollCount' },
                    totalIdleSeconds: { $sum: '$idleSeconds' },
                    count: { $sum: 1 },
                    firstTimestamp: { $min: '$timestamp' },
                    lastTimestamp: { $max: '$timestamp' },
                    sumOfScores: { $sum: { $cond: [{ $ne: ['$score', null] }, '$score', 0] } },
                    scoreLogCount: { $sum: { $cond: [{ $ne: ['$score', null] }, 1, 0] } }
                }
            }
        ]),
        AttendanceModel.findOne({
            $or: [{ employeeId }, { user: employeeId }],
            date: { $gte: start, $lt: end }
        })
            .select('punchIn punchOut')
            .lean()
    ]);
    const ag = aggResult?.[0];
    if (!ag) return false;

    const [ssGroup] = await Screenshot.aggregate([
        { $match: { tenantId: businessId, employeeID: employeeId, timestamp: { $gte: start, $lt: end } } },
        { $group: { _id: null, count: { $sum: 1 } } }
    ]);

    const bidStr = businessId.toString();
    const settings = await MonitoringSettings.findOne({ businessId: bidStr }).lean();
    if (settings?.monitoringEnabled === false) return false;

    const totalMinutes = ag.count || 1;
    const totalIdleSeconds = ag.totalIdleSeconds || 0;
    const scoreLogCount = ag.scoreLogCount ?? 0;
    const rawSumOfScores = ag.sumOfScores ?? 0;
    const avgScore = (scoreLogCount > 0) ? rawSumOfScores / scoreLogCount : 0;
    const productivityScore = Math.round(avgScore * 10) / 10;
    const sumOfScores = productivityScore; // sumOfScores = sum of scores / no of logs (average)
    const totalTrackedSeconds = Math.round(totalMinutes * 60);
    const productiveSeconds = Math.max(0, totalTrackedSeconds - totalIdleSeconds);
    const unproductiveSeconds = totalIdleSeconds;
    const activeMinutes = Math.round(productiveSeconds / 60);

    const setFields = {
        businessId,
        employeeId,
        date,
        productiveTime: productiveSeconds,
        unproductiveTime: unproductiveSeconds,
        totalTrackedTime: totalTrackedSeconds,
        totalTrackedMinutes: Math.round(totalMinutes),
        totalTrackedSeconds,
        activeMinutes,
        idleSec: totalIdleSeconds, // total idle seconds from activity logs for this date
        activityTotals: { keystrokes: ag.totalKeystrokes, mouseClicks: ag.totalMouseClicks, scrollCount: ag.totalScrollCount },
        productivityScore,
        sumOfScores,
        scoreLogCount,
        screenshotCount: ssGroup?.count ?? 0,
        screenshotsCaptured: ssGroup?.count ?? 0
    };
    if (att?.punchIn) setFields.checkInTime = att.punchIn;
    if (att?.punchOut) setFields.checkOutTime = att.punchOut;
    if (ag?.firstTimestamp) setFields.startedTime = ag.firstTimestamp;
    if (ag?.lastTimestamp) setFields.endedTime = ag.lastTimestamp;

    await MonitoringDailySummary.findOneAndUpdate(
        { businessId, employeeId, date },
        { $set: setFields },
        { upsert: true, new: true }
    );
    return true;
}

async function run(targetDate) {
    const n = await runDailySummary(targetDate);
    process.exit(0);
}

if (require.main === module) {
    const arg = process.argv[2];
    const targetDate = arg ? new Date(arg) : undefined;
    run(targetDate).catch(() => {
        process.exit(1);
    });
}

module.exports = { runDailySummary, upsertDailySummaryForStaff };
