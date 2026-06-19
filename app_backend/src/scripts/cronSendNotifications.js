// Cron (this script): birthday + work-anniversary wish FCM only, once per day at 6:00 AM (CELEBRATION_CRON_TZ, 24h clock — override with CELEBRATION_CRON_*).
// Other FCM — run your separate cron; legacy kept commented below.
// Run: npm run cron (process stays idle between daily runs; no polling loop).
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const connectDB = require('../config/db');
const fcmService = require('../services/fcmService');
// const Leave = require('../models/Leave');
const Staff = require('../models/Staff');
const Announcement = require('../models/Announcement');
const mongoose = require('mongoose');
// const Expense = require('../models/Expense');
// const Reimbursement = require('../models/Reimbursement');
// const PayslipRequest = require('../models/PayslipRequest');
// const Loan = require('../models/Loan');
// const Attendance = require('../models/Attendance');
// const PerformanceReview = require('../models/PerformanceReview');
// const ReviewCycle = require('../models/ReviewCycle');
// const User = require('../models/User');
const Company = require('../models/Company');
const { formatCalendarDayInTimezone } = require('../utils/dateUtils');
const {
    getCelebrationWishFlags,
    getBusinessTimezone,
    getHourMinuteInTimezone,
} = require('../utils/celebrationWishHelper');

/** IANA TZ for the single daily clock (when this process fires the job). Default India. */
const CELEBRATION_CRON_TZ = (process.env.CELEBRATION_CRON_TZ || 'Asia/Kolkata').trim();
/** 24-hour clock: 6 = 6:00 AM, 18 = 6:00 PM */
const CELEBRATION_CRON_HOUR = Math.min(23, Math.max(0, parseInt(process.env.CELEBRATION_CRON_HOUR || '6', 10)));
const CELEBRATION_CRON_MINUTE = Math.min(59, Math.max(0, parseInt(process.env.CELEBRATION_CRON_MINUTE || '0', 10)));

/** How often (seconds) to poll for newly-published announcements that need a push. */
const ANNOUNCEMENT_POLL_INTERVAL_SEC = Math.max(15, parseInt(process.env.ANNOUNCEMENT_POLL_INTERVAL_SEC || '60', 10));
/**
 * Only announcements published/created at or after this instant are notified, so that turning the cron
 * on does NOT blast a push for every pre-existing announcement. The persistent fcmNotificationSentAt flag
 * then prevents duplicate sends across ticks/restarts. Set ANNOUNCEMENT_NOTIFY_SINCE (ISO date) to backfill
 * older announcements on purpose.
 */
const ANNOUNCEMENT_NOTIFY_SINCE = (() => {
    const raw = (process.env.ANNOUNCEMENT_NOTIFY_SINCE || '').trim();
    if (raw) {
        const d = new Date(raw);
        if (!isNaN(d.getTime())) return d;
    }
    return new Date(); // process start
})();

/* OTHER FCM CRON — disabled here (separate worker). Remove this wrapper to restore.
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

async function runPerformanceDeadlineReminders() {
    let sent = 0;
    try {
        const now = new Date();
        now.setHours(0, 0, 0, 0);
        const cycles = await ReviewCycle.find({
            status: { $nin: ['completed', 'cancelled'] },
            endDate: { $gte: now },
        }).lean();

        for (const cycle of cycles) {
            const selfD = new Date(cycle.selfReviewDeadline);
            const mgrD = new Date(cycle.managerReviewDeadline);
            const hrD = new Date(cycle.hrReviewDeadline);
            selfD.setHours(0, 0, 0, 0);
            mgrD.setHours(0, 0, 0, 0);
            hrD.setHours(0, 0, 0, 0);

            const daysSelf = Math.ceil((selfD.getTime() - now.getTime()) / ONE_DAY_MS);
            const daysMgr = Math.ceil((mgrD.getTime() - now.getTime()) / ONE_DAY_MS);
            const daysHr = Math.ceil((hrD.getTime() - now.getTime()) / ONE_DAY_MS);

            const remDays = [0, 1, 3, 7];

            if (remDays.includes(daysSelf) && daysSelf >= 0) {
                const q = { reviewCycle: cycle.name, status: { $in: ['self-review-pending', 'draft'] } };
                if (cycle.businessId) q.businessId = cycle.businessId;
                const reviews = await PerformanceReview.find(q).select('employeeId fcmSelfReviewReminderDaysSent').lean();
                for (const r of reviews) {
                    const sentList = r.fcmSelfReviewReminderDaysSent || [];
                    if (sentList.includes(daysSelf)) continue;
                    const empId = r.employeeId && r.employeeId._id ? r.employeeId._id : r.employeeId;
                    const staff = await Staff.findById(empId).select('fcmToken').lean();
                    if (!staff?.fcmToken || typeof staff.fcmToken !== 'string' || !staff.fcmToken.trim()) continue;
                    let title = '', body = '';
                    if (daysSelf === 0) { title = 'Self Review Deadline Today'; body = `Your self-review for "${cycle.name}" is due today. Please submit as soon as possible.`; }
                    else if (daysSelf === 1) { title = 'Self Review Deadline Tomorrow'; body = `Your self-review for "${cycle.name}" is due tomorrow (${selfD.toLocaleDateString()}).`; }
                    else if (daysSelf === 3) { title = 'Self Review Deadline in 3 Days'; body = `Your self-review for "${cycle.name}" is due in 3 days (${selfD.toLocaleDateString()}).`; }
                    else if (daysSelf === 7) { title = 'Self Review Deadline in 7 Days'; body = `Your self-review for "${cycle.name}" is due in 7 days (${selfD.toLocaleDateString()}).`; }
                    if (!body) continue;
                    const res = await fcmService.sendPerformanceDeadlineNotification(empId, title, body, { type: 'self_review', reviewCycle: cycle.name, daysRemaining: String(daysSelf) });
                    if (res.success) {
                        await PerformanceReview.findByIdAndUpdate(r._id, { $addToSet: { fcmSelfReviewReminderDaysSent: daysSelf } });
                        sent++;
                    }
                }
            }

            if (remDays.includes(daysMgr) && daysMgr >= 0) {
                const q = { reviewCycle: cycle.name, status: { $in: ['self-review-submitted', 'manager-review-pending'] } };
                if (cycle.businessId) q.businessId = cycle.businessId;
                const reviews = await PerformanceReview.find(q).populate('managerId', 'fcmToken').lean();
                const byManager = new Map();
                for (const r of reviews) {
                    const mgr = r.managerId;
                    const mgrId = mgr && (mgr._id || mgr) ? String(mgr._id || mgr) : null;
                    if (!mgrId) continue;
                    if (!byManager.has(mgrId)) byManager.set(mgrId, []);
                    byManager.get(mgrId).push(r);
                }
                for (const [mgrId, revs] of byManager) {
                    const r0 = revs[0];
                    const sentList = r0.fcmManagerReviewReminderDaysSent || [];
                    if (sentList.includes(daysMgr)) continue;
                    const staff = await Staff.findById(mgrId).select('fcmToken').lean();
                    if (!staff?.fcmToken || typeof staff.fcmToken !== 'string' || !staff.fcmToken.trim()) continue;
                    let title = '', body = '';
                    if (daysMgr === 0) { title = 'Manager Review Deadline Today'; body = `You have ${revs.length} manager review(s) for "${cycle.name}" due today.`; }
                    else if (daysMgr === 1) { title = 'Manager Review Deadline Tomorrow'; body = `You have ${revs.length} manager review(s) for "${cycle.name}" due tomorrow.`; }
                    else if (daysMgr === 3) { title = 'Manager Review Deadline in 3 Days'; body = `You have ${revs.length} manager review(s) for "${cycle.name}" due in 3 days.`; }
                    else if (daysMgr === 7) { title = 'Manager Review Deadline in 7 Days'; body = `You have ${revs.length} manager review(s) for "${cycle.name}" due in 7 days.`; }
                    if (!body) continue;
                    const res = await fcmService.sendPerformanceDeadlineNotification(mgrId, title, body, { type: 'manager_review', reviewCycle: cycle.name, daysRemaining: String(daysMgr) });
                    if (res.success) {
                        for (const r of revs) {
                            await PerformanceReview.findByIdAndUpdate(r._id, { $addToSet: { fcmManagerReviewReminderDaysSent: daysMgr } });
                        }
                        sent++;
                    }
                }
            }

            if (remDays.includes(daysHr) && daysHr >= 0) {
                const q = { reviewCycle: cycle.name, status: { $in: ['manager-review-submitted', 'hr-review-pending'] } };
                if (cycle.businessId) q.businessId = cycle.businessId;
                const pending = await PerformanceReview.find(q).lean();
                const count = pending.length;
                if (count === 0) continue;
                const hrSent = cycle.fcmHrReviewReminderDaysSent || [];
                if (hrSent.includes(daysHr)) continue;
                const hrQuery = { role: { $regex: /^(HR|Admin)$/i } };
                if (cycle.businessId) hrQuery.companyId = cycle.businessId;
                const hrUsers = await User.find(hrQuery).select('_id').lean();
                let hrCycleSent = 0;
                for (const u of hrUsers) {
                    const staff = await Staff.findOne({ userId: u._id }).select('fcmToken _id').lean();
                    if (!staff?.fcmToken || typeof staff.fcmToken !== 'string' || !staff.fcmToken.trim()) continue;
                    let title = '', body = '';
                    if (daysHr === 0) { title = 'HR Review Deadline Today'; body = `You have ${count} HR review(s) for "${cycle.name}" due today.`; }
                    else if (daysHr === 1) { title = 'HR Review Deadline Tomorrow'; body = `You have ${count} HR review(s) for "${cycle.name}" due tomorrow.`; }
                    else if (daysHr === 3) { title = 'HR Review Deadline in 3 Days'; body = `You have ${count} HR review(s) for "${cycle.name}" due in 3 days.`; }
                    else if (daysHr === 7) { title = 'HR Review Deadline in 7 Days'; body = `You have ${count} HR review(s) for "${cycle.name}" due in 7 days.`; }
                    if (!body) continue;
                    const res = await fcmService.sendPerformanceDeadlineNotification(staff._id, title, body, { type: 'hr_review', reviewCycle: cycle.name, daysRemaining: String(daysHr) });
                    if (res.success) { sent++; hrCycleSent++; }
                }
                if (hrCycleSent > 0) {
                    await ReviewCycle.findByIdAndUpdate(cycle._id, { $addToSet: { fcmHrReviewReminderDaysSent: daysHr } });
                }
            }
        }
        return sent;
    } catch (e) {
        // Performance deadline error (silent in dev)
        return 0;
    }
}

async function sendToStaff(employeeId, fn, doc, updateField) {
    const empId = doc.employeeId && doc.employeeId._id ? doc.employeeId._id : doc.employeeId;
    if (!empId) return false;
    const staff = await Staff.findById(empId).select('fcmToken _id').lean();
    if (!staff || String(staff._id) !== String(empId)) return false;
    if (!staff.fcmToken || typeof staff.fcmToken !== 'string' || !staff.fcmToken.trim()) return false;
    const res = await fn(doc, staff);
    if (res.success) {
        await updateField(doc._id);
        return true;
    }
    return false;
}

async function runOnce() {
    try {
        const deactivatedResult = await Staff.updateMany(
            { status: { $regex: /^deactivated$/i }, fcmToken: { $exists: true, $ne: null } },
            { $unset: { fcmToken: 1 } }
        );
        if (deactivatedResult.modifiedCount > 0) { void 0; }

        let totalSent = 0;

        const pendingApproved = await Leave.find({
            status: 'Approved',
            approvedAt: { $exists: true, $ne: null },
            $or: [{ fcmNotificationSentAt: null }, { fcmNotificationSentAt: { $exists: false } }],
        }).lean();
        const pendingRejected = await Leave.find({
            status: 'Rejected',
            approvedAt: { $exists: true, $ne: null },
            $or: [{ fcmRejectionSentAt: null }, { fcmRejectionSentAt: { $exists: false } }],
        }).lean();
        const expenseApproved = await Expense.find({
            status: 'Approved',
            $or: [{ fcmNotificationSentAt: null }, { fcmNotificationSentAt: { $exists: false } }],
        }).lean();
        const expenseRejected = await Expense.find({
            status: 'Rejected',
            $or: [{ fcmRejectionSentAt: null }, { fcmRejectionSentAt: { $exists: false } }],
        }).lean();
        const reimbursementApproved = await Reimbursement.find({
            status: 'Approved',
            $or: [{ fcmNotificationSentAt: null }, { fcmNotificationSentAt: { $exists: false } }],
        }).lean();
        const reimbursementRejected = await Reimbursement.find({
            status: 'Rejected',
            $or: [{ fcmRejectionSentAt: null }, { fcmRejectionSentAt: { $exists: false } }],
        }).lean();
        const payslipApproved = await PayslipRequest.find({
            status: { $in: ['Approved', 'Generated'] },
            $or: [{ fcmNotificationSentAt: null }, { fcmNotificationSentAt: { $exists: false } }],
        }).lean();
        const payslipRejected = await PayslipRequest.find({
            status: 'Rejected',
            $or: [{ fcmRejectionSentAt: null }, { fcmRejectionSentAt: { $exists: false } }],
        }).lean();
        const loanApproved = await Loan.find({
            status: 'Approved',
            approvedAt: { $exists: true, $ne: null },
            $or: [{ fcmNotificationSentAt: null }, { fcmNotificationSentAt: { $exists: false } }],
        }).lean();
        const loanRejected = await Loan.find({
            status: 'Rejected',
            $or: [{ fcmRejectionSentAt: null }, { fcmRejectionSentAt: { $exists: false } }],
        }).lean();
        const attApproved = await Attendance.find({
            status: 'Approved',
            $or: [{ fcmNotificationSentAt: null }, { fcmNotificationSentAt: { $exists: false } }],
        }).lean();
        const attRejected = await Attendance.find({
            status: 'Rejected',
            $or: [{ fcmRejectionSentAt: null }, { fcmRejectionSentAt: { $exists: false } }],
        }).lean();
        const attStatusChangeRaw = await Attendance.find({
            status: { $in: ['Present', 'Absent', 'Half Day', 'On Leave'] },
            $or: [{ fcmStatusChangeSentAt: null }, { fcmStatusChangeSentAt: { $exists: false } }],
        }).lean();
        // Deduplicate by (employeeId, date) so we send only ONE notification per employee per date (avoids 3x same notification)
        const attStatusByKey = new Map();
        for (const doc of attStatusChangeRaw) {
            const empId = doc.employeeId && doc.employeeId._id ? doc.employeeId._id : doc.employeeId || doc.user && doc.user._id ? doc.user._id : doc.user;
            if (!empId) continue;
            const dateStr = doc.date ? new Date(doc.date).toISOString().slice(0, 10) : '';
            const key = `${String(empId)}_${dateStr}`;
            if (!attStatusByKey.has(key)) attStatusByKey.set(key, []);
            attStatusByKey.get(key).push(doc);
        }
        const attStatusChange = Array.from(attStatusByKey.values()).map(group => group[0]);

        const pendingCount = pendingApproved.length + pendingRejected.length + expenseApproved.length + expenseRejected.length +
            reimbursementApproved.length + reimbursementRejected.length +
            payslipApproved.length + payslipRejected.length + loanApproved.length + loanRejected.length +
            attApproved.length + attRejected.length + attStatusChange.length;
        if (pendingCount > 0) { void 0; }

        for (const leave of pendingApproved) {
            if (await sendToStaff(leave.employeeId, fcmService.sendLeaveApprovedNotification, leave, (id) =>
                Leave.findByIdAndUpdate(id, { fcmNotificationSentAt: new Date() })
            )) totalSent++;
        }

        for (const leave of pendingRejected) {
            if (await sendToStaff(leave.employeeId, fcmService.sendLeaveRejectedNotification, leave, (id) =>
                Leave.findByIdAndUpdate(id, { fcmRejectionSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of expenseApproved) {
            if (await sendToStaff(doc.employeeId, fcmService.sendExpenseApprovedNotification, doc, (id) =>
                Expense.findByIdAndUpdate(id, { fcmNotificationSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of expenseRejected) {
            if (await sendToStaff(doc.employeeId, fcmService.sendExpenseRejectedNotification, doc, (id) =>
                Expense.findByIdAndUpdate(id, { fcmRejectionSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of reimbursementApproved) {
            if (await sendToStaff(doc.employeeId, fcmService.sendExpenseApprovedNotification, doc, (id) =>
                Reimbursement.findByIdAndUpdate(id, { fcmNotificationSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of reimbursementRejected) {
            if (await sendToStaff(doc.employeeId, fcmService.sendExpenseRejectedNotification, doc, (id) =>
                Reimbursement.findByIdAndUpdate(id, { fcmRejectionSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of payslipApproved) {
            if (await sendToStaff(doc.employeeId, fcmService.sendPayslipApprovedNotification, doc, (id) =>
                PayslipRequest.findByIdAndUpdate(id, { fcmNotificationSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of payslipRejected) {
            if (await sendToStaff(doc.employeeId, fcmService.sendPayslipRejectedNotification, doc, (id) =>
                PayslipRequest.findByIdAndUpdate(id, { fcmRejectionSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of loanApproved) {
            if (await sendToStaff(doc.employeeId, fcmService.sendLoanApprovedNotification, doc, (id) =>
                Loan.findByIdAndUpdate(id, { fcmNotificationSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of loanRejected) {
            if (await sendToStaff(doc.employeeId, fcmService.sendLoanRejectedNotification, doc, (id) =>
                Loan.findByIdAndUpdate(id, { fcmRejectionSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of attApproved) {
            if (await sendToStaff(doc.employeeId, fcmService.sendAttendanceApprovedNotification, doc, (id) =>
                Attendance.findByIdAndUpdate(id, { fcmNotificationSentAt: new Date() })
            )) totalSent++;
        }

        for (const doc of attRejected) {
            if (await sendToStaff(doc.employeeId, fcmService.sendAttendanceRejectedNotification, doc, (id) =>
                Attendance.findByIdAndUpdate(id, { fcmRejectionSentAt: new Date() })
            )) totalSent++;
        }

        const attEmpId = (doc) => doc.employeeId && doc.employeeId._id ? doc.employeeId._id : doc.employeeId || doc.user && doc.user._id ? doc.user._id : doc.user;
        for (const doc of attStatusChange) {
            const empId = attEmpId(doc);
            const dateStr = doc.date ? new Date(doc.date).toISOString().slice(0, 10) : '';
            const groupKey = `${String(empId)}_${dateStr}`;
            const group = attStatusByKey.get(groupKey) || [doc];
            const updateAllInGroup = async () => {
                const ids = group.map(d => d._id).filter(Boolean);
                if (ids.length) await Attendance.updateMany({ _id: { $in: ids } }, { fcmStatusChangeSentAt: new Date() });
            };
            if (empId && await sendToStaff(empId, fcmService.sendAttendanceStatusChangeNotification, doc, () => updateAllInGroup())) totalSent++;
        }

        const perfReviewStatusChange = await PerformanceReview.find({
            status: { $nin: ['draft'] },
            $or: [
                { fcmStatusChangeSentForStatus: null },
                { fcmStatusChangeSentForStatus: { $exists: false } },
                { $expr: { $ne: ['$fcmStatusChangeSentForStatus', '$status'] } },
            ],
        }).populate('employeeId', '_id').lean();
        for (const doc of perfReviewStatusChange) {
            const empId = doc.employeeId && doc.employeeId._id ? doc.employeeId._id : doc.employeeId;
            const updateStatusSent = (id) => PerformanceReview.findByIdAndUpdate(id, { fcmStatusChangeSentForStatus: doc.status });
            if (empId && await sendToStaff(empId, fcmService.sendPerformanceReviewStatusChangeNotification, doc, updateStatusSent)) totalSent++;
        }

        const perfSent = await runPerformanceDeadlineReminders();
        totalSent += perfSent;

        const celebrationSent = await runCelebrationWishNotificationsThrottled();
        totalSent += celebrationSent;

        if (totalSent > 0) { void 0; }
    } catch (e) {
        console.error('[Cron] Error:', e.message);
    }
}
*/

/** Milliseconds until the next strictly-future CELEBRATION_CRON_HOUR:MINUTE in CELEBRATION_CRON_TZ (step 1s, max ~49h). */
function msUntilNextCronFire(fromMs = Date.now()) {
    const start = fromMs;
    for (let delta = 1000; delta < 49 * 60 * 60 * 1000; delta += 1000) {
        const t = start + delta;
        const hm = getHourMinuteInTimezone(new Date(t), CELEBRATION_CRON_TZ);
        if (hm.hour === CELEBRATION_CRON_HOUR && hm.minute === CELEBRATION_CRON_MINUTE) return delta;
    }
    return 24 * 60 * 60 * 1000;
}

function scheduleCelebrationCron() {
    const delay = msUntilNextCronFire();
    console.log(
        '[Cron] Next celebration wishes at',
        `${String(CELEBRATION_CRON_HOUR).padStart(2, '0')}:${String(CELEBRATION_CRON_MINUTE).padStart(2, '0')}`,
        CELEBRATION_CRON_TZ,
        '(in ~' + Math.round(delay / 60000) + ' min)',
    );
    setTimeout(async () => {
        try {
            await runCelebrationWishNotifications();
        } catch (e) {
            console.error('[Cron] celebration wishes:', e.message);
        }
        scheduleCelebrationCron();
    }, delay);
}

/** Birthday / work anniversary wish push once per calendar day (company TZ). FCM only to that staff row’s fcmToken (the person celebrating). */
async function runCelebrationWishNotifications() {
    const now = new Date();
    let sent = 0;
    try {
        const staffList = await Staff.find({
            status: { $regex: /^active$/i },
            businessId: { $exists: true, $ne: null },
            fcmToken: { $exists: true, $ne: null, $nin: [null, ''] },
            $or: [
                { dob: { $exists: true, $ne: null } },
                { joiningDate: { $exists: true, $ne: null } },
            ],
        })
            .select('dob joiningDate businessId fcmToken fcmBirthdayWishSentDateKey fcmAnniversaryWishSentDateKey')
            .lean();

        const rawBiz = staffList.map((s) => s.businessId).filter(Boolean);
        const uniqueBizStr = [...new Set(rawBiz.map((id) => String(id)))];
        const tzByBiz = new Map();
        if (uniqueBizStr.length > 0) {
            const companies = await Company.find({ _id: { $in: uniqueBizStr } })
                .select('settings.business.timezone settings.attendance.timezone timezone')
                .lean();
            for (const c of companies) {
                tzByBiz.set(String(c._id), getBusinessTimezone(c));
            }
        }

        for (const s of staffList) {
            const token = s.fcmToken && String(s.fcmToken).trim();
            if (!token) continue;
            const bizId = s.businessId ? String(s.businessId) : '';
            if (!bizId) continue;
            const tz = tzByBiz.get(bizId) || 'Asia/Kolkata';

            const todayKey = formatCalendarDayInTimezone(now, tz);
            const flags = getCelebrationWishFlags(s, now, tz);

            if (flags.isBirthdayToday && s.fcmBirthdayWishSentDateKey !== todayKey) {
                const res = await fcmService.sendCelebrationWishNotification(s._id, 'birthday', todayKey);
                if (res.success) {
                    await Staff.findByIdAndUpdate(s._id, { fcmBirthdayWishSentDateKey: todayKey });
                    sent++;
                } else if (res.invalidToken) {
                    await Staff.findByIdAndUpdate(s._id, { $unset: { fcmToken: 1 } });
                }
            }
            if (flags.isWorkAnniversaryToday && s.fcmAnniversaryWishSentDateKey !== todayKey) {
                const res = await fcmService.sendCelebrationWishNotification(s._id, 'anniversary', todayKey);
                if (res.success) {
                    await Staff.findByIdAndUpdate(s._id, { fcmAnniversaryWishSentDateKey: todayKey });
                    sent++;
                } else if (res.invalidToken) {
                    await Staff.findByIdAndUpdate(s._id, { $unset: { fcmToken: 1 } });
                }
            }
        }
    } catch (e) {
        console.error('[Cron] celebration wishes:', e.message);
    }
    return sent;
}

/** Active staff (with an FCM token) who should receive a given announcement, per its audience rules. */
async function resolveAnnouncementAudience(ann) {
    const baseQuery = {
        status: { $regex: /^active$/i },
        fcmToken: { $exists: true, $ne: null, $nin: [null, ''] },
    };
    if (ann.businessId) baseQuery.businessId = ann.businessId;

    // Targeting is driven by the recipient list, NOT the audienceType string (the web app may store a
    // targeted announcement with audienceType "all"/"Specific"). Mirrors audienceFilter in announcementController.
    const targetIds = []
        .concat(Array.isArray(ann.targetStaffIds) ? ann.targetStaffIds : [])
        .concat(Array.isArray(ann.assignedTo) ? ann.assignedTo : [])
        .filter((x) => x && mongoose.Types.ObjectId.isValid(x));
    const flaggedSpecific = typeof ann.audienceType === 'string' && /^\s*specific\s*$/i.test(ann.audienceType);
    if (targetIds.length > 0) {
        // Has a recipient list → push only to those staff.
        baseQuery._id = { $in: targetIds };
    } else if (flaggedSpecific) {
        // Flagged "specific" but no recipients → nobody.
        return [];
    }
    // Otherwise → company-wide, push to everyone in the business.
    return Staff.find(baseQuery).select('fcmToken _id').lean();
}

/**
 * Send a push for every newly-published announcement that hasn't been notified yet.
 * Guarded by ANNOUNCEMENT_NOTIFY_SINCE so pre-existing announcements are never back-blasted, and by the
 * persistent fcmNotificationSentAt flag so each announcement notifies its audience exactly once.
 */
async function runAnnouncementNotifications() {
    let sent = 0;
    try {
        const now = new Date();
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
        const pending = await Announcement.find({
            status: { $in: ['published', 'Active'] },
            $or: [{ fcmNotificationSentAt: null }, { fcmNotificationSentAt: { $exists: false } }],
            // Published/effective now or earlier...
            $and: [
                { $or: [{ publishDate: { $lte: now } }, { effectiveDate: { $lte: now } }] },
                // ...not expired...
                { $or: [{ expiryDate: null }, { expiryDate: { $exists: false } }, { expiryDate: { $gte: startOfToday } }] },
                { $or: [{ endDate: null }, { endDate: { $exists: false } }, { endDate: { $gte: startOfToday } }] },
                // ...and created/published only after the notifier went live (no back-blast of history).
                { $or: [{ publishDate: { $gte: ANNOUNCEMENT_NOTIFY_SINCE } }, { createdAt: { $gte: ANNOUNCEMENT_NOTIFY_SINCE } }] },
            ],
        }).lean();

        for (const ann of pending) {
            const audience = await resolveAnnouncementAudience(ann);
            let delivered = 0;
            for (const staff of audience) {
                const token = staff.fcmToken && String(staff.fcmToken).trim();
                if (!token) continue;
                const res = await fcmService.sendAnnouncementNotificationToToken(token, ann);
                if (res.success) { delivered++; sent++; }
                else if (res.invalidToken) {
                    await Staff.findByIdAndUpdate(staff._id, { $unset: { fcmToken: 1 } });
                }
            }
            // Mark as notified regardless of audience size so we don't re-scan it every tick.
            await Announcement.findByIdAndUpdate(ann._id, { fcmNotificationSentAt: new Date() });
            console.log('[Cron] Announcement "%s" (%s): pushed to %d/%d staff', ann.title, String(ann._id), delivered, audience.length);
        }
    } catch (e) {
        console.error('[Cron] announcement notifications:', e.message);
    }
    return sent;
}

function scheduleAnnouncementPoll() {
    setInterval(() => {
        runAnnouncementNotifications().catch((e) => console.error('[Cron] announcement poll:', e.message));
    }, ANNOUNCEMENT_POLL_INTERVAL_SEC * 1000);
}

async function start() {
    console.log(
        '[Cron] Started — daily celebration wishes at',
        `${String(CELEBRATION_CRON_HOUR).padStart(2, '0')}:${String(CELEBRATION_CRON_MINUTE).padStart(2, '0')}`,
        CELEBRATION_CRON_TZ,
    );
    await connectDB();
    fcmService.init();
    scheduleCelebrationCron();
    console.log(
        '[Cron] Announcement push poller every', ANNOUNCEMENT_POLL_INTERVAL_SEC, 's;',
        'notifying announcements published on/after', ANNOUNCEMENT_NOTIFY_SINCE.toISOString(),
    );
    runAnnouncementNotifications().catch((e) => console.error('[Cron] announcement initial:', e.message));
    scheduleAnnouncementPoll();
}

start().catch((e) => {
    console.error('[Cron] Startup failed:', e.message);
    process.exit(1);
});
