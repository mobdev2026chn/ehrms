/**
 * FCM (Firebase Cloud Messaging) – single module for all push notifications.
 * Uses Firebase Admin SDK. Set GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_PATH to service account JSON.
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

let _initialized = false;

function init() {
    if (_initialized) return admin.app();
    // Prefer env; then app_backend/firebase-service-account.json (works when PM2 runs from src/scripts)
    const appBackendPath = path.join(__dirname, '..', '..', 'firebase-service-account.json');
    const cwdPath = path.join(process.cwd(), 'firebase-service-account.json');
    let credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS ||
        process.env.FIREBASE_SERVICE_ACCOUNT_PATH ||
        appBackendPath;
    if (!credPath || !fs.existsSync(credPath)) {
        credPath = fs.existsSync(cwdPath) ? cwdPath : (credPath || appBackendPath);
    }
    if (!fs.existsSync(credPath)) {
        console.warn('[FCM] Service account file not found:', credPath, '- push notifications disabled');
        return null;
    }
    try {
        const key = JSON.parse(fs.readFileSync(credPath, 'utf8'));
        admin.initializeApp({ credential: admin.credential.cert(key) });
        _initialized = true;
        console.log('[FCM] Initialized successfully');
    } catch (e) {
        console.error('[FCM] Init failed:', e.message);
        return null;
    }
    return admin.app();
}

/**
 * Send a notification to a single device token.
 * Uses DATA-ONLY payload so the Flutter app's background handler runs when app is closed or in background,
 * so every notification is stored and shown in the in-app Notifications screen even if the user never taps it.
 * Do not add a top-level "notification" payload – that would prevent the app from storing when not tapped.
 * @param {string} token - FCM device token
 * @param {object} options - { title, body, data, androidTag? } (androidTag: same tag = replace previous notification on device)
 * @returns {Promise<{ success: boolean, error?: string }>}
 */
async function sendToToken(token, { title, body, data = {}, ...options } = {}) {
    const app = init();
    if (!app) {
        console.warn('[FCM] sendToToken: FCM not initialized, skip');
        return { success: false, error: 'FCM not initialized' };
    }
    if (!token || typeof token !== 'string') {
        console.warn('[FCM] sendToToken: missing or invalid token');
        return { success: false, error: 'Missing token' };
    }
    if (Array.isArray(token)) return { success: false, error: 'Must send to one token only, not multiple' };
    const tokenPreview = token.length > 24 ? token.substring(0, 12) + '...' + token.slice(-8) : token;
    const androidTag = options && options.androidTag ? String(options.androidTag) : null;
    console.log('[FCM] RECEIVED send request: title=', title || 'HRMS', 'token=', tokenPreview, 'tag=', androidTag || 'none');
    try {
        // Data-only payload: no top-level "notification". Title/body go in data so Flutter
        // background handler runs when app is closed and can store + show in Notifications screen.
        const dataObj = {
            title: String(title != null ? title : 'HRMS'),
            body: String(body != null ? body : ''),
            message: String(body != null ? body : ''),
            ...Object.fromEntries(
                Object.entries(data).map(([k, v]) => [String(k), String(v == null ? '' : v)])
            ),
        };
        const payload = {
            token,
            data: dataObj,
            android: {
                priority: 'high',
                // Required so data-only messages are delivered when app is in background or killed.
                ...(androidTag ? { notification: { tag: androidTag } } : {}),
            },
            // Optional: help delivery when app is in background (iOS).
            apns: {
                headers: { 'apns-priority': '10' },
                payload: { aps: { 'content-available': 1 } },
            },
        };
        const msgId = await admin.messaging().send(payload);
        console.log('[FCM] sendToToken: success messageId=', msgId);
        return { success: true };
    } catch (e) {
        const code = e.code || e.errorInfo?.code;
        const invalidToken = code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token' ||
            (e.message && String(e.message).includes('not found'));
        console.error('[FCM] sendToToken failed: code=', code, 'message=', e.message, 'tokenPreview=', tokenPreview);
        if (e.errorInfo) console.error('[FCM] errorInfo:', JSON.stringify(e.errorInfo));
        if (invalidToken) {
            console.log('[FCM] sendToToken: token invalid/unregistered – caller should clear stored token');
        }
        return { success: false, error: e.message, invalidToken: !!invalidToken };
    }
}

/**
 * Send "Leave approved" notification to the employee who requested the leave.
 * Uses leave.employeeId (staff id from leaves collection) to find that staff's FCM token.
 * Only call this from an authenticated route (e.g. updateLeaveStatus with protect middleware).
 * @param {object} leaveDoc - Leave document from leaves collection (status = Approved)
 * @param {object} [staff] - Staff document with fcmToken (optional; if not passed, loaded by leave.employeeId)
 */
async function sendLeaveApprovedNotification(leaveDoc, staff = null) {
    const Staff = require('../models/Staff');
    const employeeId = leaveDoc.employeeId && leaveDoc.employeeId._id ? leaveDoc.employeeId._id : leaveDoc.employeeId;
    if (!employeeId) {
        console.warn('[FCM] sendLeaveApproved: leave has no employeeId');
        return { success: false, error: 'No employeeId' };
    }
    const staffDoc = staff || await Staff.findById(employeeId).select('fcmToken _id').lean();
    if (!staffDoc) {
        console.warn('[FCM] sendLeaveApproved: staff not found', employeeId);
        return { success: false, error: 'Staff not found' };
    }
    const staffIdMatch = String(staffDoc._id) === String(employeeId);
    if (!staffIdMatch) {
        console.warn('[FCM] sendLeaveApproved: staff id mismatch – only sending to leave owner');
        return { success: false, error: 'Staff id must be leave owner' };
    }
    const fcmToken = staffDoc.fcmToken;
    if (!fcmToken || typeof fcmToken !== 'string') {
        console.log('[FCM] sendLeaveApproved: no fcmToken for employeeId=', employeeId);
        return { success: false, error: 'No FCM token for employee' };
    }
    const leaveType = leaveDoc.leaveType || 'Leave';
    const startDate = leaveDoc.startDate ? new Date(leaveDoc.startDate) : null;
    const dateStr = startDate
        ? startDate.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })
        : 'the requested date';
    const body = `Your leave request approved for ${leaveType} on ${dateStr}`;
    const staffIdStr = employeeId.toString && employeeId.toString() || String(employeeId);
    const leaveIdStr = (leaveDoc._id && leaveDoc._id.toString) ? leaveDoc._id.toString() : '';
    console.log('[FCM] Sending leave approved to this employee only: staffId=', staffIdStr, 'leaveId=', leaveIdStr, '(1 token, not broadcast)');
    return sendToToken(fcmToken, {
        title: 'Leave Approved',
        body,
        data: {
            module: 'leave',
            type: 'leave_approved',
            staffId: staffIdStr,
            leaveType,
            date: dateStr,
            leaveId: leaveIdStr,
        },
    });
}

/**
 * Send "Leave rejected" notification to the employee. Call when status changes from Pending to Rejected.
 */
async function sendLeaveRejectedNotification(leaveDoc, staff = null) {
    const Staff = require('../models/Staff');
    const employeeId = leaveDoc.employeeId && leaveDoc.employeeId._id ? leaveDoc.employeeId._id : leaveDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const staffDoc = staff || await Staff.findById(employeeId).select('fcmToken _id').lean();
    if (!staffDoc) {
        console.warn('[FCM] sendLeaveRejected: staff not found', employeeId);
        return { success: false, error: 'Staff not found' };
    }
    const staffIdMatch = String(staffDoc._id) === String(employeeId);
    if (!staffIdMatch) {
        console.warn('[FCM] sendLeaveRejected: staff id mismatch – only sending to leave owner');
        return { success: false, error: 'Staff id must be leave owner' };
    }
    const fcmToken = staffDoc.fcmToken;
    if (!fcmToken || typeof fcmToken !== 'string') {
        console.log('[FCM] sendLeaveRejected: no fcmToken for employeeId=', employeeId);
        return { success: false, error: 'No FCM token for employee' };
    }
    const leaveType = leaveDoc.leaveType || 'Leave';
    const startDate = leaveDoc.startDate ? new Date(leaveDoc.startDate) : null;
    const dateStr = startDate
        ? startDate.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })
        : '';
    const body = dateStr
        ? `Your leave request for ${leaveType} on ${dateStr} was rejected.`
        : `Your leave request for ${leaveType} was rejected.`;
    const staffIdStr = employeeId.toString && employeeId.toString() || String(employeeId);
    const leaveIdStr = (leaveDoc._id && leaveDoc._id.toString) ? leaveDoc._id.toString() : '';
    console.log('[FCM] Sending leave rejected to this employee only: staffId=', staffIdStr, 'leaveId=', leaveIdStr, '(1 token, not broadcast)');
    return sendToToken(fcmToken, {
        title: 'Leave Rejected',
        body,
        data: {
            module: 'leave',
            type: 'leave_rejected',
            staffId: staffIdStr,
            leaveType,
            date: dateStr,
            leaveId: leaveIdStr,
        },
    });
}

/**
 * Send a generic notification (for future use: loan approved, expense, etc.).
 * @param {string} token - FCM token
 * @param {string} title - Notification title
 * @param {string} body - Notification body
 * @param {object} data - Optional key-value data for app (strings only)
 */
async function sendNotification(token, title, body, data = {}) {
    return sendToToken(token, { title, body, data });
}

async function _sendToEmployee(employeeId, title, body, data = {}, options = {}) {
    const Staff = require('../models/Staff');
    const staff = await Staff.findById(employeeId).select('fcmToken _id').lean();
    if (!staff) {
        console.log('[FCM] _sendToEmployee: staff not found employeeId=', employeeId);
        return { success: false, error: 'Staff not found' };
    }
    if (!staff.fcmToken || typeof staff.fcmToken !== 'string' || !staff.fcmToken.trim()) {
        console.log('[FCM] _sendToEmployee: no fcmToken for staffId=', staff._id, 'title=', title, '(app did not register token yet?)');
        return { success: false, error: 'No FCM token for employee' };
    }
    const result = await sendToToken(staff.fcmToken.trim(), { title, body, data, ...options });
    if (!result.success && result.invalidToken) {
        await Staff.findByIdAndUpdate(employeeId, { $unset: { fcmToken: 1 } });
        console.log('[FCM] _sendToEmployee: cleared invalid fcmToken for staffId=', employeeId);
    }
    return result;
}

async function sendExpenseApprovedNotification(expenseDoc, staff = null) {
    const employeeId = expenseDoc.employeeId && expenseDoc.employeeId._id ? expenseDoc.employeeId._id : expenseDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const amount = expenseDoc.amount ? `₹${expenseDoc.amount}` : '';
    const type = expenseDoc.expenseType || expenseDoc.type || 'Expense';
    const body = `Your ${type} request ${amount ? `of ${amount} ` : ''}has been approved.`;
    return _sendToEmployee(employeeId, 'Expense Approved', body, {
        module: 'expense',
        type: 'expense_approved',
        staffId: String(employeeId),
        expenseId: String(expenseDoc._id || ''),
    });
}

async function sendExpenseRejectedNotification(expenseDoc, staff = null) {
    const employeeId = expenseDoc.employeeId && expenseDoc.employeeId._id ? expenseDoc.employeeId._id : expenseDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const body = `Your expense request has been rejected.`;
    return _sendToEmployee(employeeId, 'Expense Rejected', body, {
        module: 'expense',
        type: 'expense_rejected',
        staffId: String(employeeId),
        expenseId: String(expenseDoc._id || ''),
    });
}

async function sendPayslipApprovedNotification(payslipDoc, staff = null) {
    const employeeId = payslipDoc.employeeId && payslipDoc.employeeId._id ? payslipDoc.employeeId._id : payslipDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const m = payslipDoc.month || 1;
    const y = payslipDoc.year || new Date().getFullYear();
    const body = `Your payslip request for ${monthNames[m-1]} ${y} has been approved.`;
    return _sendToEmployee(employeeId, 'Payslip Approved', body, {
        module: 'payslip',
        type: 'payslip_approved',
        staffId: String(employeeId),
        payslipId: String(payslipDoc._id || ''),
    });
}

async function sendPayslipRejectedNotification(payslipDoc, staff = null) {
    const employeeId = payslipDoc.employeeId && payslipDoc.employeeId._id ? payslipDoc.employeeId._id : payslipDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const body = `Your payslip request has been rejected.`;
    return _sendToEmployee(employeeId, 'Payslip Rejected', body, {
        module: 'payslip',
        type: 'payslip_rejected',
        staffId: String(employeeId),
        payslipId: String(payslipDoc._id || ''),
    });
}

async function sendLoanApprovedNotification(loanDoc, staff = null) {
    const employeeId = loanDoc.employeeId && loanDoc.employeeId._id ? loanDoc.employeeId._id : loanDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const amount = loanDoc.amount ? `₹${loanDoc.amount}` : '';
    const body = `Your loan request ${amount ? `of ${amount} ` : ''}has been approved.`;
    return _sendToEmployee(employeeId, 'Loan Approved', body, {
        module: 'loan',
        type: 'loan_approved',
        staffId: String(employeeId),
        loanId: String(loanDoc._id || ''),
    });
}

async function sendLoanRejectedNotification(loanDoc, staff = null) {
    const employeeId = loanDoc.employeeId && loanDoc.employeeId._id ? loanDoc.employeeId._id : loanDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const body = `Your loan request has been rejected.`;
    return _sendToEmployee(employeeId, 'Loan Rejected', body, {
        module: 'loan',
        type: 'loan_rejected',
        staffId: String(employeeId),
        loanId: String(loanDoc._id || ''),
    });
}

async function sendAttendanceApprovedNotification(attendanceDoc, staff = null) {
    const employeeId = attendanceDoc.employeeId && attendanceDoc.employeeId._id ? attendanceDoc.employeeId._id : attendanceDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const dateStr = attendanceDoc.date ? new Date(attendanceDoc.date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
    const body = dateStr ? `Your attendance for ${dateStr} has been approved.` : `Your attendance has been approved.`;
    return _sendToEmployee(employeeId, 'Attendance Approved', body, {
        module: 'attendance',
        type: 'attendance_approved',
        staffId: String(employeeId),
        attendanceId: String(attendanceDoc._id || ''),
    });
}

async function sendAttendanceRejectedNotification(attendanceDoc, staff = null) {
    const employeeId = attendanceDoc.employeeId && attendanceDoc.employeeId._id ? attendanceDoc.employeeId._id : attendanceDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const body = `Your attendance request has been rejected.`;
    return _sendToEmployee(employeeId, 'Attendance Rejected', body, {
        module: 'attendance',
        type: 'attendance_rejected',
        staffId: String(employeeId),
        attendanceId: String(attendanceDoc._id || ''),
    });
}

async function sendAttendanceStatusChangeNotification(attendanceDoc, staff = null) {
    const employeeId = attendanceDoc.employeeId && attendanceDoc.employeeId._id ? attendanceDoc.employeeId._id : attendanceDoc.employeeId
        || attendanceDoc.user && attendanceDoc.user._id ? attendanceDoc.user._id : attendanceDoc.user;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const dateStr = attendanceDoc.date ? new Date(attendanceDoc.date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
    const dateKey = attendanceDoc.date ? new Date(attendanceDoc.date).toISOString().slice(0, 10) : '';
    const status = (attendanceDoc.status || 'Updated').trim();
    const body = dateStr ? `Your attendance for ${dateStr} has been marked as ${status}.` : `Your attendance has been marked as ${status}.`;
    const androidTag = dateKey ? `att_status_${employeeId}_${dateKey}` : null;
    return _sendToEmployee(employeeId, 'Attendance Updated', body, {
        module: 'attendance',
        type: 'attendance_status_changed',
        staffId: String(employeeId),
        attendanceId: String(attendanceDoc._id || ''),
    }, androidTag ? { androidTag } : {});
}

async function sendPerformanceDeadlineNotification(staffIdOrUserId, title, body, data = {}) {
    const Staff = require('../models/Staff');
    const User = require('../models/User');
    let staff = await Staff.findById(staffIdOrUserId).select('fcmToken userId').lean();
    if (!staff) {
        staff = await Staff.findOne({ userId: staffIdOrUserId }).select('fcmToken _id').lean();
    }
    if (!staff || !staff.fcmToken || typeof staff.fcmToken !== 'string' || !staff.fcmToken.trim()) {
        return { success: false, error: 'No FCM token' };
    }
    return sendToToken(staff.fcmToken.trim(), { title, body, data: { module: 'performance', ...data } });
}

const PERFORMANCE_REVIEW_STATUS_LABELS = {
    'draft': 'Draft',
    'self-review-pending': 'Self review pending',
    'self-review-submitted': 'Self review submitted',
    'manager-review-pending': 'Manager review pending',
    'manager-review-submitted': 'Manager review submitted',
    'hr-review-pending': 'HR review pending',
    'hr-review-submitted': 'HR review submitted',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
};

async function sendPerformanceReviewStatusChangeNotification(reviewDoc, staff = null) {
    const employeeId = reviewDoc.employeeId && reviewDoc.employeeId._id ? reviewDoc.employeeId._id : reviewDoc.employeeId;
    if (!employeeId) return { success: false, error: 'No employeeId' };
    const cycle = reviewDoc.reviewCycle || 'Performance Review';
    const status = (reviewDoc.status || '').trim();
    const statusLabel = PERFORMANCE_REVIEW_STATUS_LABELS[status] || status.replace(/-/g, ' ') || 'Updated';
    const body = `Your performance review for "${cycle}" has been updated to ${statusLabel}.`;
    const androidTag = `perf_review_${employeeId}_${String(reviewDoc._id)}`;
    return _sendToEmployee(employeeId, 'Performance Review Updated', body, {
        module: 'performance',
        type: 'performance_review_status_changed',
        staffId: String(employeeId),
        reviewId: String(reviewDoc._id || ''),
        reviewCycle: cycle,
        status,
    }, { androidTag });
}

module.exports = {
    init,
    sendToToken,
    sendLeaveApprovedNotification,
    sendLeaveRejectedNotification,
    sendExpenseApprovedNotification,
    sendExpenseRejectedNotification,
    sendPayslipApprovedNotification,
    sendPayslipRejectedNotification,
    sendLoanApprovedNotification,
    sendLoanRejectedNotification,
    sendAttendanceApprovedNotification,
    sendAttendanceRejectedNotification,
    sendAttendanceStatusChangeNotification,
    sendPerformanceDeadlineNotification,
    sendPerformanceReviewStatusChangeNotification,
    sendNotification,
};
