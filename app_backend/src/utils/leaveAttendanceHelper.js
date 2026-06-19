const Attendance = require('../models/Attendance');
const Leave = require('../models/Leave');
const Staff = require('../models/Staff');
const Company = require('../models/Company');
const LeaveTemplate = require('../models/LeaveTemplate');
const { calculateFineAmount } = require('./fineCalculationHelper');

/**
 * Half-day leave check-in/check-out logic (NEW IMPLEMENTATION based on company shift halfDaySettings):
 *
 * - Session 1 (First Half Day leave): employee is ON LEAVE for first half, WORKS second half (midpoint → shift end).
 *   Check-in: 
 *     - Allowed from (midpoint - secondHalfLoginGraceMinutes) to shift end
 *     - If secondHalfLoginGraceMinutes is 0/null: check-in from midpoint exactly
 *     - If secondHalfStrictLogin=true: no grace, check-in from midpoint only
 *     - If trying to check-in during first half (before allowed time): blocked with alert
 *   Check-out:
 *     - Allowed from midpoint to shift end (no restriction on late checkout)
 *     - If trying to check-out during first half: blocked with alert
 *
 * - Session 2 (Second Half Day leave): employee WORKS first half (shift start → midpoint), is ON LEAVE for second half.
 *   Check-in:
 *     - Allowed from shift start to midpoint (before midpoint, as midpoint = leave starts)
 *     - General shift grace time applies for late arrival fine calculation only
 *     - If trying to check-in during second half (at or after midpoint): blocked with alert
 *   Check-out:
 *     - Allowed from midpoint to (midpoint + firstHalfLogoutGraceMinutes)
 *     - If firstHalfLogoutGraceMinutes is 0/null: checkout at midpoint exactly
 *     - If trying to check-out after grace period (during second half): blocked with alert
 *
 * - customMidPointTime (e.g. 14:30) from company shift defines the boundary between first/second half; else equal halves.
 * - Example: Shift 10:00-19:00, midpoint 14:30, grace 30 mins
 *   - Session 1 (First half leave): Check-in 14:00-19:00, Check-out 14:30-19:00
 *   - Session 2 (Second half leave): Check-in 10:00-14:30, Check-out 14:30-15:00
 */

// Default half-day boundaries when shift not provided: Session 1 = 10:00–15:00, Session 2 = 15:00–19:00 (from 10:00–19:00 shift)
const DEFAULT_SHIFT_START = '10:00';
const DEFAULT_SHIFT_END = '19:00';

// Default business timezone when not set (shift times are in business local time; server may be UTC).
const DEFAULT_BUSINESS_TIMEZONE = process.env.BUSINESS_TIMEZONE || 'Asia/Kolkata';

/**
 * Get hour and minute of a date in a given timezone (for half-day session checks).
 * Shift times (e.g. 10:00–19:00) are in business local time; we must compare with "now" in that timezone.
 * @param {Date} date - Instant in time (e.g. new Date())
 * @param {string} [timeZone] - IANA timezone e.g. 'Asia/Kolkata'. If falsy, uses server local (date.getHours/getMinutes).
 * @returns {{ hour: number, minute: number, currentMinutes: number }}
 */
const getLocalHoursMinutes = (date, timeZone) => {
    const useTz = (timeZone && String(timeZone).trim()) || DEFAULT_BUSINESS_TIMEZONE;
    
    // Manual offset for Asia/Kolkata when Intl fails (UTC+5:30)
    const manualOffsetMinutes = (useTz === 'Asia/Kolkata' || useTz === 'Asia/Calcutta') ? 330 : null;
    
    try {
        // Use toLocaleString with timezone (more reliable than Intl format on some Windows/Node combos)
        const options = { timeZone: useTz, hour12: false, hour: '2-digit', minute: '2-digit' };
        const timeStr = date.toLocaleTimeString('en-GB', options);
        console.log('[getLocalHoursMinutes] converted', { utc: date.toISOString(), timeZone: useTz, timeStr });
        const parts = timeStr.split(':').map(s => parseInt(s.trim(), 10));
        const hour = Number.isFinite(parts[0]) ? parts[0] : 0;
        const minute = Number.isFinite(parts[1]) ? parts[1] : 0;
        const result = { hour, minute, currentMinutes: hour * 60 + minute };
        console.log('[getLocalHoursMinutes] result', result);
        return result;
    } catch (e) {
        console.error('[getLocalHoursMinutes] Intl failed', { error: e.message, useTz });
        
        // If we have manual offset for this timezone, use it
        if (manualOffsetMinutes !== null) {
            console.log('[getLocalHoursMinutes] using manual UTC offset for', useTz, '+', manualOffsetMinutes, 'minutes');
            const utcMinutes = date.getUTCHours() * 60 + date.getUTCMinutes();
            const localMinutes = (utcMinutes + manualOffsetMinutes) % (24 * 60);
            const hour = Math.floor(localMinutes / 60);
            const minute = localMinutes % 60;
            const result = { hour, minute, currentMinutes: localMinutes };
            console.log('[getLocalHoursMinutes] manual result', result);
            return result;
        }
        
        // Fallback: try default business timezone if we were using something else
        if (useTz !== DEFAULT_BUSINESS_TIMEZONE) {
            try {
                const options = { timeZone: DEFAULT_BUSINESS_TIMEZONE, hour12: false, hour: '2-digit', minute: '2-digit' };
                const timeStr = date.toLocaleTimeString('en-GB', options);
                const parts = timeStr.split(':').map(s => parseInt(s.trim(), 10));
                const hour = Number.isFinite(parts[0]) ? parts[0] : 0;
                const minute = Number.isFinite(parts[1]) ? parts[1] : 0;
                return { hour, minute, currentMinutes: hour * 60 + minute };
            } catch (_) {}
        }
        // Last resort: server local time (wrong if server TZ != business TZ; log it)
        const hour = date.getHours();
        const minute = date.getMinutes();
        console.warn('[getLocalHoursMinutes] Using server local time; business TZ may differ. useTz=', useTz, 'hour=', hour, 'minute=', minute);
        return { hour, minute, currentMinutes: hour * 60 + minute };
    }
};

/**
 * Get half-day session boundaries from shift timings.
 * When halfDaySettings.customMidPointTime is provided (from company shift), use it as session1End/session2Start.
 * Otherwise: equal halves. Session 1 = first (total/2) hrs, Session 2 = next (total/2) hrs.
 * E.g. 10:00–19:00 with customMidPointTime 14:30 → Session 1 = 10:00–14:30, Session 2 = 14:30–19:00.
 * @param {string} shiftStartTime - e.g. '10:00'
 * @param {string} shiftEndTime - e.g. '19:00'
 * @param {Object} [halfDaySettings] - from company shift: { customMidPointTime: '14:30', firstHalfLogoutGraceMinutes, secondHalfLoginGraceMinutes, secondHalfStrictLogin }
 * @returns {{ session1Start: string, session1End: string, session2Start: string, session2End: string }} HH:mm
 */
const getHalfDaySessionBoundaries = (shiftStartTime, shiftEndTime, halfDaySettings = null) => {
    const start = (shiftStartTime || DEFAULT_SHIFT_START).trim();
    const end = (shiftEndTime || DEFAULT_SHIFT_END).trim();
    if (halfDaySettings && halfDaySettings.customMidPointTime) {
        const mid = String(halfDaySettings.customMidPointTime).trim();
        return {
            session1Start: start,
            session1End: mid,
            session2Start: mid,
            session2End: end
        };
    }
    const [startH, startM] = start.split(':').map(Number);
    const [endH, endM] = end.split(':').map(Number);
    const startTotalMinutes = startH * 60 + (startM || 0);
    let endTotalMinutes = endH * 60 + (endM || 0);
    if (endTotalMinutes <= startTotalMinutes) endTotalMinutes += 24 * 60; // overnight
    const durationMinutes = endTotalMinutes - startTotalMinutes;
    const halfMinutes = Math.floor(durationMinutes / 2);
    const session1EndMinutes = startTotalMinutes + halfMinutes;
    const session1EndH = Math.floor(session1EndMinutes / 60) % 24;
    const session1EndM = session1EndMinutes % 60;
    const session1End = `${String(session1EndH).padStart(2, '0')}:${String(session1EndM).padStart(2, '0')}`;
    return {
        session1Start: start,
        session1End,
        session2Start: session1End,
        session2End: end
    };
};

/** Format HH:mm to "H:00 AM – H:00 PM" for display */
const formatTimeForMessage = (hhmm) => {
    const [h, m] = hhmm.split(':').map(Number);
    const hour = h % 12 || 12;
    const ampm = h < 12 ? 'AM' : 'PM';
    const min = m ? `:${String(m).padStart(2, '0')}` : '';
    return `${hour}${min} ${ampm}`;
};

/**
 * Get user-facing message for half-day session (for check-in/check-out block).
 * Card shows only "First Half Day leave" or "Second Half Day leave" (no timings, no extra sentence).
 */
const getHalfDaySessionMessage = (session, shiftStartTime, shiftEndTime, halfDaySettings = null) => {
    const s = String(session || '').trim();
    // Card label: session 1/First Half Day → show "Second Half Day leave", session 2/Second Half Day → show "First Half Day leave" (corrected for display)
    if (s === 'First Half Day' || s === '1') return 'First Half Day leave';
    if (s === 'Second Half Day' || s === '2') return 'Second Half Day leave';
    return 'Half-day leave';
};

const toMinutesOfDay = (hhmm) => {
    const [h, m] = String(hhmm || '0:0').split(':').map(Number);
    return h * 60 + (m || 0);
};

const formatMinutesToTime = (minutes) => {
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
};

/**
 * Get boundaries in minute-of-day for a session (for leave window checks).
 * @param {string} session - 'First Half Day' or 'Second Half Day'
 * @param {string} shiftStartTime
 * @param {string} shiftEndTime
 * @param {Object} [halfDaySettings] - from company shift (customMidPointTime, etc.)
 */
const getSessionBoundsMinutes = (session, shiftStartTime, shiftEndTime, halfDaySettings = null) => {
    const b = getHalfDaySessionBoundaries(shiftStartTime || DEFAULT_SHIFT_START, shiftEndTime || DEFAULT_SHIFT_END, halfDaySettings);
    if (session === 'First Half Day' || session === '1') return { start: toMinutesOfDay(b.session1Start), end: toMinutesOfDay(b.session1End) };
    if (session === 'Second Half Day' || session === '2') return { start: toMinutesOfDay(b.session2Start), end: toMinutesOfDay(b.session2End) };
    return null;
};

/**
 * Check if current time falls within the leave session window.
 * Uses business timezone; optional halfDaySettings for custom midpoint from company.
 * @param {number} [currentMinutesOverride] - If provided (0-1439), use instead of converting now in timeZone (avoids Intl timezone issues on server)
 */
const isCurrentlyInLeaveSession = (leave, now, shiftStartTime, shiftEndTime, timeZone, halfDaySettings = null, currentMinutesOverride = null) => {
    if (!leave || !/^approved$/i.test(leave.status)) return false;
    if (!isHalfDayLeaveType(leave.leaveType)) return true;
    const session = String(resolveHalfDaySession(leave) ?? '').trim();
    const bounds = getSessionBoundsMinutes(session, shiftStartTime, shiftEndTime, halfDaySettings);
    if (!bounds) {
        console.log('[isCurrentlyInLeaveSession] no bounds', { session, shiftStartTime, shiftEndTime });
        return false;
    }
    let currentMinutes;
    let hour;
    let minute;
    if (typeof currentMinutesOverride === 'number' && currentMinutesOverride >= 0 && currentMinutesOverride < 24 * 60) {
        currentMinutes = Math.floor(currentMinutesOverride);
        hour = Math.floor(currentMinutes / 60);
        minute = currentMinutes % 60;
    } else {
        const effectiveTz = timeZone || DEFAULT_BUSINESS_TIMEZONE;
        const got = getLocalHoursMinutes(now, effectiveTz);
        currentMinutes = got.currentMinutes;
        hour = got.hour;
        minute = got.minute;
    }
    const inSession = currentMinutes >= bounds.start && currentMinutes < bounds.end;
    console.log('[isCurrentlyInLeaveSession]', { session, hour, minute, currentMinutes, boundsStart: bounds.start, boundsEnd: bounds.end, inSession, usedClientLocal: typeof currentMinutesOverride === 'number' });
    return inSession;
};

/**
 * Get leave message for UI: session-based for half-day, generic for full-day.
 * Half-day: First half leave / Second half leave with timings only (no check-in/out allowed text).
 */
const getLeaveMessageForUI = (leave, now, shiftStartTime, shiftEndTime, timeZone, halfDaySettings = null) => {
    if (!leave) return null;
    if (isHalfDayLeave(leave)) {
        const sessionMsg = getHalfDaySessionMessage(resolveHalfDaySession(leave), shiftStartTime, shiftEndTime, halfDaySettings);
        return sessionMsg;
    }
    return 'Your leave request is approved. Enjoy your leave.';
};

/**
 * Check if check-in is allowed given an approved Half Day leave and current time.
 * Grace from halfDaySettings:
 * - secondHalfLoginGraceMinutes: login allowed before mid time (check-in from mid - grace to shift end). E.g. 30 => can login from 14:00 when mid is 14:30.
 * - secondHalfStrictLogin: if true, no grace; check-in from midpoint only.
 *
 * - Session 1 (First Half Day leave): employee works SECOND HALF (midpoint to shift end)
 *   - Check-in from (midpoint - secondHalfLoginGraceMinutes) to shift end
 *   - If secondHalfStrictLogin or grace 0: check-in from midpoint only
 *
 * - Session 2 (Second Half Day leave): employee works FIRST HALF (shift start to midpoint)
 *   - Check-in from shift start to midpoint only
 *
 * @param {Object} leave - Approved leave with leaveType 'Half Day' and session '1' or '2'
 * @param {Date} now - Current time (server time)
 * @param {string} [shiftStartTime] - from business shift
 * @param {string} [shiftEndTime] - from business shift
 * @param {string} [timeZone] - Business timezone e.g. 'Asia/Kolkata'
 * @param {Object} [halfDaySettings] - from company shift: customMidPointTime, secondHalfLoginGraceMinutes, firstHalfLogoutGraceMinutes, secondHalfStrictLogin
 * @param {number} [shiftGracePeriodMinutes] - shift grace for fine calculation (not check-in window)
 */
const SESSION_2_EARLY_CHECKIN_MINUTES = 30; // fallback when no halfDaySettings

const resolveHalfDaySession = (leave) =>
    leave.halfDaySession
    || leave.halfDayType
    || (leave.session === '1' ? 'First Half Day' : leave.session === '2' ? 'Second Half Day' : null);

const isHalfDayLeaveType = (leaveType) => (leaveType || '').trim().toLowerCase() === 'half day';

/**
 * Robustly detect a half-day leave from a Leave document, independent of leaveType.
 * Half-day is a DURATION (First/Second Half) that can be applied to ANY leave type
 * (Casual, Sick, Earned, …), represented by session ('1'/'2') / halfDaySession /
 * halfDayType / days === 0.5. The legacy standalone 'Half Day' leaveType is still
 * recognised for backward compatibility.
 */
const isHalfDayLeave = (leave) => {
    if (!leave) return false;
    if (isHalfDayLeaveType(leave.leaveType)) return true;
    if (leave.session === '1' || leave.session === '2') return true;
    const hs = (leave.halfDaySession || leave.halfDayType || '').toString().trim().toLowerCase();
    if (hs === 'first half day' || hs === 'second half day') return true;
    return Number(leave.days) === 0.5;
};

const canCheckInWithHalfDayLeave = (leave, now, shiftStartTime, shiftEndTime, timeZone, halfDaySettings = null, shiftGracePeriodMinutes = 0) => {
    if (!leave || !isHalfDayLeaveType(leave.leaveType)) return { allowed: true };
    const session = String(resolveHalfDaySession(leave) ?? '').trim();
    const bounds = getSessionBoundsMinutes(session, shiftStartTime, shiftEndTime, halfDaySettings);
    if (!bounds) return { allowed: true };
    const shiftStartMin = toMinutesOfDay(shiftStartTime || DEFAULT_SHIFT_START);
    const shiftEndMin = toMinutesOfDay(shiftEndTime || DEFAULT_SHIFT_END);
    const effectiveTz = timeZone || DEFAULT_BUSINESS_TIMEZONE;
    const { currentMinutes } = getLocalHoursMinutes(now, effectiveTz);
    // Mid = boundary between first half and second half.
    const midMin = session === 'First Half Day' ? bounds.end : bounds.start;

    if (session === 'First Half Day') {
        // First Half Day leave: employee works SECOND HALF.
        // Early punch-in (before the second-half window) is allowed and recorded so the
        // employee can punch in ahead of the second half starting; late/fine logic handles
        // the actual session timing. We only block punch-in once the shift has already ended.
        const checkInUntil = shiftEndMin;

        if (currentMinutes > checkInUntil) {
            return { allowed: false, message: 'Check-in time has passed. Shift ends at ' + shiftEndTime + '.' };
        }
        return { allowed: true };
    }
    if (session === 'Second Half Day') {
        // Second Half Day leave: employee works FIRST HALF (shift start to midpoint)
        // Can check-in from shift start to midpoint (before midpoint, as midpoint = leave starts)
        const checkInFrom = shiftStartMin;
        const checkInUntil = midMin;
        
        // If trying to check-in before shift start
        if (currentMinutes < checkInFrom) {
            return { allowed: false, message: 'Check-in not allowed before shift start time: ' + shiftStartTime + '.' };
        }
        // If trying to check-in at or after midpoint (during second half = leave time)
        if (currentMinutes >= checkInUntil) {
            return { allowed: false, message: 'You are on leave for the second half and cannot check in/out during this time.' };
        }
        return { allowed: true };
    }
    return { allowed: true };
};

/**
 * For a First Half Day leave (employee works the SECOND half), check-in should become available a
 * little before the second half actually starts, so the employee can punch in ahead of time.
 * Returns true when `now` is inside the early-login window [mid - grace, mid) of a First Half Day leave.
 *
 * Although the clock is still technically inside the (first-half) leave session during this window,
 * the employee is about to start their working half and must be allowed to check in. Callers use this
 * to relax the "currently in leave session" block for the early second-half login only.
 *
 * Grace comes from halfDaySettings.secondHalfLoginGraceMinutes (fallback SESSION_2_EARLY_CHECKIN_MINUTES
 * = 30). If secondHalfStrictLogin is true, grace is 0 (window collapses, so this returns false until mid).
 */
const isWithinSecondHalfEarlyLoginWindow = (leave, now, shiftStartTime, shiftEndTime, timeZone, halfDaySettings = null, currentMinutesOverride = null) => {
    if (!leave || !isHalfDayLeaveType(leave.leaveType)) return false;
    const session = String(resolveHalfDaySession(leave) ?? '').trim();
    if (session !== 'First Half Day') return false;
    const bounds = getSessionBoundsMinutes(session, shiftStartTime, shiftEndTime, halfDaySettings);
    if (!bounds) return false;
    // First Half Day leave → working (second) half begins at the midpoint (bounds.end).
    const midMin = bounds.end;
    const strict = halfDaySettings?.secondHalfStrictLogin === true;
    const grace = strict ? 0 : (Number(halfDaySettings?.secondHalfLoginGraceMinutes ?? SESSION_2_EARLY_CHECKIN_MINUTES) || 0);
    const windowStart = midMin - grace;
    let currentMinutes;
    if (typeof currentMinutesOverride === 'number' && currentMinutesOverride >= 0 && currentMinutesOverride < 24 * 60) {
        currentMinutes = Math.floor(currentMinutesOverride);
    } else {
        const effectiveTz = timeZone || DEFAULT_BUSINESS_TIMEZONE;
        currentMinutes = getLocalHoursMinutes(now, effectiveTz).currentMinutes;
    }
    return currentMinutes >= windowStart && currentMinutes < midMin;
};

/**
 * Check if check-out is allowed given an approved Half Day leave and current time.
 * Uses halfDaySettings from business/company shift:
 * - firstHalfLogoutGraceMinutes: for Session 2 (Second Half Day leave), employee can logout up to this many minutes AFTER the midpoint. E.g. 60 => can logout until mid + 60 mins.
 *
 * - Session 1 (First Half Day leave): employee works SECOND HALF (midpoint to shift end)
 *   - Check-out allowed from midpoint to shift end.
 *
 * - Session 2 (Second Half Day leave): employee works FIRST HALF (shift start to midpoint)
 *   - Check-out allowed from shift start to (midpoint + firstHalfLogoutGraceMinutes). If grace is 0/null: logout at midpoint only.
 */
const canCheckOutWithHalfDayLeave = (leave, now, shiftStartTime, shiftEndTime, timeZone, halfDaySettings = null) => {
    if (!leave || !isHalfDayLeaveType(leave.leaveType)) return { allowed: true };
    const session = String(resolveHalfDaySession(leave) ?? '').trim();
    const bounds = getSessionBoundsMinutes(session, shiftStartTime, shiftEndTime, halfDaySettings);
    if (!bounds) return { allowed: true };
    const shiftStartMin = toMinutesOfDay(shiftStartTime || DEFAULT_SHIFT_START);
    const shiftEndMin = toMinutesOfDay(shiftEndTime || DEFAULT_SHIFT_END);
    const effectiveTz = timeZone || DEFAULT_BUSINESS_TIMEZONE;
    const { currentMinutes } = getLocalHoursMinutes(now, effectiveTz);
    const midMin = session === 'First Half Day' ? bounds.end : bounds.start;

    if (session === 'First Half Day') {
        // First Half Day leave: work SECOND HALF (midpoint to shift end). Check-out allowed from mid to shift end.
        if (currentMinutes < midMin) {
            return { allowed: false, message: 'You are on leave for the first half and cannot check in/out during this time.' };
        }
        if (currentMinutes > shiftEndMin) {
            return { allowed: false, message: 'Shift has ended.' };
        }
        return { allowed: true };
    }
    if (session === 'Second Half Day') {
        // Second Half Day leave: work FIRST HALF. Check-out allowed from shift start until (midpoint + firstHalfLogoutGraceMinutes).
        const graceMins = halfDaySettings?.firstHalfLogoutGraceMinutes ?? 0;
        const logoutUntil = midMin + graceMins;
        if (currentMinutes < shiftStartMin) {
            return { allowed: false, message: 'Check-out not allowed before shift start: ' + shiftStartTime + '.' };
        }
        if (currentMinutes > logoutUntil) {
            const untilTime = formatMinutesToTime(logoutUntil);
            return { allowed: false, message: 'Check-out allowed only until ' + untilTime + ' (midpoint + ' + graceMins + ' min grace).' };
        }
        return { allowed: true };
    }
    return { allowed: true };
};

/**
 * Get shift timings from company settings
 * @param {Object} company - Company document
 * @param {Object} staff - Staff document (optional, for staff-specific shift)
 * @returns {Object} - { startTime, endTime, gracePeriodMinutes } in HH:mm format
 */
/**
 * Get business timezone for half-day/attendance checks. Shift times are in this timezone.
 * @param {Object} company - Company document
 * @returns {string} IANA timezone e.g. 'Asia/Kolkata'
 */
const getBusinessTimezone = (company) => {
    const tz = company?.settings?.attendance?.timezone
        || company?.settings?.business?.timezone
        || company?.timezone;
    return (tz && typeof tz === 'string' && tz.trim()) ? tz.trim() : DEFAULT_BUSINESS_TIMEZONE;
};

/**
 * Get the UTC Date for "attendance day at HH:mm" in business timezone.
 * Shift times (e.g. 10:00) are in business local time; server may be in UTC, so we must build
 * shift boundaries in business TZ to avoid production (UTC server) showing lateMinutes=0 when
 * the same punch-in is correctly late on local (IST server).
 * @param {Date} attendanceDate - UTC midnight of the attendance day (e.g. from startOfDay)
 * @param {string} timeStr - Time in HH:mm format (e.g. '10:00', '19:00')
 * @param {string} timeZone - IANA timezone e.g. 'Asia/Kolkata'
 * @returns {Date} UTC moment when it is timeStr in that timezone on the attendance calendar day
 */
function getShiftBoundaryAsUTCDate(attendanceDate, timeStr, timeZone) {
    const useTz = (timeZone && String(timeZone).trim()) || DEFAULT_BUSINESS_TIMEZONE;
    const local = getLocalHoursMinutes(attendanceDate, useTz);
    const minutesFromMidnightAtDate = local.hour * 60 + local.minute;
    const startOfDayInTZ = new Date(attendanceDate.getTime() - minutesFromMidnightAtDate * 60 * 1000);
    const [h, m] = (timeStr || '00:00').split(':').map(Number);
    const shiftMinutes = (h || 0) * 60 + (m || 0);
    return new Date(startOfDayInTZ.getTime() + shiftMinutes * 60 * 1000);
}

/**
 * Calendar-day difference in UTC (matches attendance.date storage).
 * @param {Date} attendanceDate
 * @param {Date} anchorDate
 */
const diffDaysUTC = (attendanceDate, anchorDate) => {
    if (!attendanceDate || !anchorDate) return 0;
    const a = new Date(attendanceDate);
    const b = new Date(anchorDate);
    const da = Date.UTC(a.getUTCFullYear(), a.getUTCMonth(), a.getUTCDate());
    const db = Date.UTC(b.getUTCFullYear(), b.getUTCMonth(), b.getUTCDate());
    return Math.round((da - db) / 86400000);
};

/** Single shift row as plain POJO so nested rotationalConfig.shiftIdsInCycle is enumerable (Mongoose subdocs). */
const shiftRowToPlain = (row) => {
    if (!row || typeof row !== 'object') return row;
    if (typeof row.toObject === 'function') {
        try {
            return row.toObject({ flattenMaps: true, virtuals: false });
        } catch (_) {
            return { ...row };
        }
    }
    return { ...row };
};

/** Lowercase 24-char hex for Mongo ObjectId comparisons (handles ObjectId, { $oid }, string). */
const normalizeShiftObjectIdStr = (v) => {
    if (v == null) return '';
    if (typeof v === 'object') {
        if (v._bsontype === 'ObjectID' || v.constructor?.name === 'ObjectId') {
            return String(v).toLowerCase();
        }
        if (v.$oid != null) return String(v.$oid).toLowerCase();
        if (v._id != null) return normalizeShiftObjectIdStr(v._id);
    }
    const s = String(v).trim().toLowerCase();
    return /^[a-f0-9]{24}$/.test(s) ? s : '';
};

const plainRotationalConfig = (wrapper) => {
    const w = shiftRowToPlain(wrapper);
    let rc = w.rotationalConfig;
    if (rc == null) return {};
    if (typeof rc === 'string') {
        try {
            rc = JSON.parse(rc);
        } catch (_) {
            return {};
        }
    }
    if (typeof rc !== 'object' || rc === null) return {};
    const base =
        typeof rc.toObject === 'function'
            ? rc.toObject({ flattenMaps: true, virtuals: false })
            : { ...rc };
    const o = { ...base };
    if (o.shiftIdsInCycle == null && o.shift_ids_in_cycle != null) o.shiftIdsInCycle = o.shift_ids_in_cycle;
    if (o.shiftNamesInCycle == null && o.shift_names_in_cycle != null) o.shiftNamesInCycle = o.shift_names_in_cycle;
    if (o.shiftIdsByWeekday == null && o.shift_ids_by_weekday != null) o.shiftIdsByWeekday = o.shift_ids_by_weekday;
    if (o.cycleLengthDays == null && o.cycle_length_days != null) o.cycleLengthDays = o.cycle_length_days;
    if (o.rotationType == null && o.rotation_type != null) o.rotationType = o.rotation_type;
    return o;
};

/** shiftIdsInCycle entries → lowercase hex strings (empty if unparseable). */
const normalizedCycleIdList = (cfg) => {
    const raw = cfg && cfg.shiftIdsInCycle;
    if (!Array.isArray(raw)) return [];
    const out = [];
    for (const el of raw) {
        if (el == null) continue;
        const id = normalizeShiftObjectIdStr(el);
        if (id) out.push(id);
    }
    return out;
};

/** Prefer richer rotationalConfig when several embedded rows share the same _id or name (stale partial subdocs). */
const rotationalConfigRichnessScore = (cfg) => {
    if (!cfg || typeof cfg !== 'object') return 0;
    const ids = normalizedCycleIdList(cfg).length;
    const wd = Array.isArray(cfg.shiftIdsByWeekday) ? cfg.shiftIdsByWeekday.filter(Boolean).length : 0;
    const wc = Array.isArray(cfg.weeklyDateAssignments) ? cfg.weeklyDateAssignments.filter(Boolean).length : 0;
    const names = Array.isArray(cfg.shiftNamesInCycle) ? cfg.shiftNamesInCycle.filter(Boolean).length : 0;
    const cld = Number(cfg.cycleLengthDays);
    const hasLen = Number.isFinite(cld) && cld > 0 ? 1 : 0;
    return ids * 1000 + wd * 100 + wc * 100 + names * 50 + hasLen * 10;
};

const shiftMatchQualityScore = (s) => {
    if (!s) return 0;
    const p = shiftRowToPlain(s);
    let sc = rotationalConfigRichnessScore(plainRotationalConfig(p));
    if (isRotationalShiftWrapper(p)) sc += 10000;
    if ((p.shiftType || '').toString().toLowerCase().trim() === 'rotational') sc += 500;
    return sc;
};

const pickBestShiftAmongDuplicates = (matches) => {
    if (!matches || matches.length === 0) return null;
    if (matches.length === 1) return matches[0];
    return matches.reduce((best, s) => (shiftMatchQualityScore(s) > shiftMatchQualityScore(best) ? s : best));
};

/**
 * Merge the strongest rotationalConfig from any embedded row with the same _id or same name as [wrapper].
 * Fixes Mongoose arrays where duplicate subdocuments share an id but only one row has shiftIdsInCycle filled in.
 */
const enrichWrapperRotationalFromDuplicateRows = (shifts, wrapper) => {
    if (!wrapper || !Array.isArray(shifts)) return wrapper;
    const w = shiftRowToPlain(wrapper);
    const wid = normalizeShiftObjectIdStr(w._id);
    const wname = (w.name || '').toString().trim().toLowerCase();
    if (!wid && !wname) return w;

    let bestRc = plainRotationalConfig(w);
    let bestScore = rotationalConfigRichnessScore(bestRc);

    for (const row of shifts) {
        if (!row) continue;
        const p = shiftRowToPlain(row);
        const pid = normalizeShiftObjectIdStr(p._id);
        const pname = (p.name || '').toString().trim().toLowerCase();
        const sameId = wid && pid === wid;
        const sameName = wname && pname === wname;
        if (!sameId && !sameName) continue;
        const rc = plainRotationalConfig(p);
        const sc = rotationalConfigRichnessScore(rc);
        if (sc > bestScore) {
            bestScore = sc;
            bestRc = rc;
        }
    }
    if (bestScore === 0) return w;

    const out = { ...w, rotationalConfig: { ...bestRc } };
    const st = (out.shiftType || '').toString().toLowerCase().trim();
    const hasCycle =
        normalizedCycleIdList(bestRc).length > 0 ||
        (Array.isArray(bestRc.shiftNamesInCycle) && bestRc.shiftNamesInCycle.filter(Boolean).length > 0) ||
        (Array.isArray(bestRc.shiftIdsByWeekday) && bestRc.shiftIdsByWeekday.filter(Boolean).length > 0) ||
        (Array.isArray(bestRc.weeklyDateAssignments) && bestRc.weeklyDateAssignments.filter(Boolean).length > 0);
    if (!st && hasCycle) out.shiftType = 'rotational';
    return out;
};

const shiftRowHasRotationalCycle = (wrapper) => {
    if (!wrapper) return false;
    const cfg = plainRotationalConfig(wrapper);
    const ids = normalizedCycleIdList(cfg);
    const names = Array.isArray(cfg.shiftNamesInCycle) ? cfg.shiftNamesInCycle.filter(Boolean) : [];
    const byWd = Array.isArray(cfg.shiftIdsByWeekday) ? cfg.shiftIdsByWeekday.filter(Boolean) : [];
    const byWc = Array.isArray(cfg.weeklyDateAssignments) ? cfg.weeklyDateAssignments.filter(Boolean) : [];
    return ids.length > 0 || names.length > 0 || byWd.length > 0 || byWc.length > 0;
};

const parseBoolLoose = (v) => {
    if (v === true || v === false) return v;
    if (typeof v === 'number') return v !== 0;
    if (typeof v === 'string') {
        const s = v.trim().toLowerCase();
        if (s === 'true' || s === '1' || s === 'yes') return true;
        if (s === 'false' || s === '0' || s === 'no') return false;
    }
    return false;
};

const normalizeAssignmentDateYmd = (raw) => {
    if (raw == null) return null;
    const s = String(raw).trim();
    if (!s) return null;
    const m = /^(\d{4}-\d{2}-\d{2})/.exec(s);
    if (m) return m[1];
    const d = new Date(s);
    if (Number.isNaN(d.getTime())) return null;
    return formatDateUtcYmd(d);
};

/** True when [rotationalConfig] has a cycle OR [shiftType] is rotational (cycle first — matches Flutter). */
const isRotationalShiftWrapper = (wrapper) => {
    if (!wrapper) return false;
    const w = shiftRowToPlain(wrapper);
    if (shiftRowHasRotationalCycle(w)) return true;
    const st = (w.shiftType || '').toString().toLowerCase().trim();
    return st === 'rotational';
};

/**
 * Assigned row may omit rotationalConfig while another company.shifts[] row (same _id or name) has it (Mongoose / UI duplicates).
 */
const wrapperWithMergedRotationalConfig = (shifts, wrapper) => {
    if (!wrapper || !Array.isArray(shifts)) return wrapper;
    const wPlain = shiftRowToPlain(wrapper);
    if (shiftRowHasRotationalCycle(wPlain)) return wPlain;
    const wname = (wPlain.name || '').toString().trim().toLowerCase();
    const wid = normalizeShiftObjectIdStr(wPlain._id);
    for (const row of shifts) {
        if (!row) continue;
        const rPlain = shiftRowToPlain(row);
        if (!shiftRowHasRotationalCycle(rPlain)) continue;
        const cfg = plainRotationalConfig(rPlain);
        const sname = (rPlain.name || '').toString().trim().toLowerCase();
        const sid = normalizeShiftObjectIdStr(rPlain._id);
        const sameId = wid && sid && wid === sid;
        const sameName = wname && sname && wname === sname;
        if (sameId || sameName) {
            return { ...wPlain, rotationalConfig: { ...cfg } };
        }
    }
    return wPlain;
};

const isLikelyMongoObjectIdHex = (v) => /^[a-fA-F0-9]{24}$/i.test(String(v).trim());

/**
 * Prefer explicit shiftId (24-char hex); else shiftName (may hold embedded shift _id as string).
 * When [shiftName] equals the attendance template label only (e.g. "Temp"), do not use it as a
 * company shift name — GET /attendance/today then falls back to shifts[0] like an unset key.
 */
const staffShiftKeyFromStaff = (staff, attendanceTemplateDoc) => {
    if (!staff) return '';
    const rawSid = staff.shiftId;
    let sid = '';
    if (rawSid != null && rawSid !== '') {
        sid =
            typeof rawSid === 'object' && rawSid._id != null
                ? String(rawSid._id).trim()
                : String(rawSid).trim();
    }
    if (sid && isLikelyMongoObjectIdHex(sid)) {
        return sid.toLowerCase();
    }
    const sn = (staff.shiftName || '').toString().trim();
    let templateName = '';
    if (attendanceTemplateDoc) {
        const tdoc =
            typeof attendanceTemplateDoc.toObject === 'function'
                ? attendanceTemplateDoc.toObject()
                : attendanceTemplateDoc;
        templateName = (tdoc.name || '').toString().trim();
    }
    if (templateName && sn === templateName) {
        return sid || '';
    }
    if (sn && isLikelyMongoObjectIdHex(sn)) {
        return sn.toLowerCase();
    }
    return sid || sn;
};

/**
 * Match staff shift key to embedded shift by _id (24-char hex → id only) or name (case-insensitive).
 * When several rows share the same display name, prefer the rotational / cycle-config row.
 */
const findShiftByStaffKey = (shifts, staffShiftKey) => {
    if (!staffShiftKey || !Array.isArray(shifts)) return null;
    const key = String(staffShiftKey).trim();
    if (!key) return null;
    const keyLower = key.toLowerCase();

    // If staff key is open (any case), prefer shift row that is open by type or by name "OPEN" / "open shift".
    if (keyLower === 'open' || keyLower === 'open shift') {
        const openShift = shifts.find(s => {
            const sShiftType = (s.shiftType || '').toString().toLowerCase();
            if (sShiftType === 'open' || sShiftType === 'open shift') return true;
            const nm = (s.name || '').toString().trim().toLowerCase();
            return nm === 'open' || nm === 'open shift';
        });
        if (openShift) {
            return openShift;
        }
    }

    if (isLikelyMongoObjectIdHex(key)) {
        const keyNorm = key.toLowerCase();
        const matches = shifts.filter((s) => {
            if (!s || s._id == null) return false;
            const sid = normalizeShiftObjectIdStr(s._id);
            return sid === keyNorm;
        });
        if (matches.length === 0) return null;
        return pickBestShiftAmongDuplicates(matches);
    }

    const matches = shifts.filter((s) => {
        if (!s) return false;
        if (s._id != null && String(s._id) === key) return true;
        if ((s.name || '').toString().trim().toLowerCase() === keyLower) return true;
        return false;
    });
    if (matches.length === 0) return null;
    return pickBestShiftAmongDuplicates(matches);
};

/**
 * For rotational wrapper shift, return the effective standard/open row for this calendar day.
 * - rotationType `byWeekday`: map UTC weekday (Sun=0…Sat=6) via shiftIdsByWeekday[].day → shiftId.
 * - rotationType `weekly`: index = UTC calendar weekday (Sun=0…Sat=6) mod cycleLengthDays (or array length).
 * - rotationType `custom` / `daily` / default: index = diffDaysUTC(attendance, anchor) mod cycle length (joining date anchor).
 */
const resolveEffectiveShiftRaw = (shifts, wrapper, attendanceDate, rotationAnchorDate) => {
    if (!wrapper || !Array.isArray(shifts)) return wrapper;
    if (!isRotationalShiftWrapper(wrapper)) return wrapper;
    const cfg = plainRotationalConfig(wrapper);
    const rotationType = (cfg.rotationType || 'custom').toString().toLowerCase().trim();

    /**
     * Leaf slot row only (parity with Flutter isLeafShiftRow): skip template; allow mis-tagged "rotational" rows that have a window but no cycle.
     */
    const isLeafShiftRow = (s) => {
        if (!s) return false;
        const p = shiftRowToPlain(s);
        if (!isRotationalShiftWrapper(p)) return true;
        const st = (p.startTime || '').toString().trim();
        const en = (p.endTime || '').toString().trim();
        const hasWindow = !!(st && en);
        const hasCycle = shiftRowHasRotationalCycle(p);
        return hasWindow && !hasCycle;
    };

    if (rotationType === 'byweekday' || rotationType === 'by_weekday') {
        const entries = Array.isArray(cfg.shiftIdsByWeekday) ? cfg.shiftIdsByWeekday.filter(Boolean) : [];
        if (entries.length === 0) return wrapper;
        const att = attendanceDate || new Date();
        const y = att.getUTCFullYear();
        const mo = att.getUTCMonth();
        const d = att.getUTCDate();
        const jsDow = new Date(Date.UTC(y, mo, d)).getUTCDay();
        const row = entries.find((e) => e && Number(e.day) === jsDow);
        if (!row || row.shiftId == null) return wrapper;
        const needle = normalizeShiftObjectIdStr(row.shiftId);
        const effective = shifts.find((s) => {
            if (!isLeafShiftRow(s) || s._id == null) return false;
            return needle && normalizeShiftObjectIdStr(s._id) === needle;
        });
        return effective || wrapper;
    }

    if (rotationType === 'byweekcalendar' || rotationType === 'by_week_calendar') {
        const rows = Array.isArray(cfg.weeklyDateAssignments) ? cfg.weeklyDateAssignments.filter(Boolean) : [];
        if (rows.length === 0) return wrapper;
        const targetDate = formatDateUtcYmd(attendanceDate || new Date());
        let anyWeekOff = false;
        let lastWorkRow = null;
        for (const e of rows) {
            if (!e || normalizeAssignmentDateYmd(e.date) !== targetDate) continue;
            if (parseBoolLoose(e.isWeekOff)) {
                anyWeekOff = true;
                continue;
            }
            if (e.shiftId != null) lastWorkRow = e;
        }
        if (anyWeekOff) {
            return {
                ...wrapper,
                __rotationWeekOff: true,
                __rotationDate: targetDate,
                __rotationType: rotationType
            };
        }
        if (!lastWorkRow || lastWorkRow.shiftId == null) return wrapper;
        const needle = normalizeShiftObjectIdStr(lastWorkRow.shiftId);
        const effective = shifts.find((s) => {
            if (!isLeafShiftRow(s) || s._id == null) return false;
            return needle && normalizeShiftObjectIdStr(s._id) === needle;
        });
        return effective || wrapper;
    }

    const ids = normalizedCycleIdList(cfg);
    const names = Array.isArray(cfg.shiftNamesInCycle) ? cfg.shiftNamesInCycle.filter(Boolean) : [];
    let cycleLen = Number(cfg.cycleLengthDays);
    if (!Number.isFinite(cycleLen) || cycleLen <= 0) {
        cycleLen = ids.length || names.length || 0;
    }
    if (cycleLen <= 0) return wrapper;

    let idx;
    if (rotationType === 'weekly') {
        // Same UTC calendar day as diffDaysUTC: use Y/M/D from the attendance instant in UTC.
        const att = attendanceDate || new Date();
        const y = att.getUTCFullYear();
        const mo = att.getUTCMonth();
        const d = att.getUTCDate();
        const jsDow = new Date(Date.UTC(y, mo, d)).getUTCDay(); // 0 = Sun .. 6 = Sat
        idx = jsDow % cycleLen;
    } else {
        // custom, daily, or unknown: days since anchor (joining date), modulo cycle length
        const anchor = rotationAnchorDate ?? attendanceDate ?? new Date();
        let diff = diffDaysUTC(attendanceDate || new Date(), anchor);
        idx = diff % cycleLen;
        if (idx < 0) idx += cycleLen;
    }

    const effectiveIdHex = ids.length > 0 ? ids[idx % ids.length] : null;
    const effectiveName = names.length > 0 ? names[idx % names.length] : null;
    const nameLower = effectiveName != null ? String(effectiveName).trim().toLowerCase() : '';
    let effective = effectiveIdHex
        ? shifts.find(
              (s) =>
                  isLeafShiftRow(s) &&
                  normalizeShiftObjectIdStr(s._id) === effectiveIdHex
          )
        : null;
    if (!effective && nameLower) {
        effective = shifts.find(
            (s) =>
                isLeafShiftRow(s) &&
                (s.name || '').toString().trim().toLowerCase() === nameLower
        );
    }
    return effective || wrapper;
};

/**
 * When the resolved embedded shift omits start/end (hydration / partial subdocs), copy window from
 * the matching row in company.settings.attendance.shifts (Flutter: resolveStandardShiftWindowFromCompany).
 */
const enrichStandardShiftTimesFromShiftsList = (shifts, shift) => {
    if (!shift || !Array.isArray(shifts)) return shift;
    const plain = shiftRowToPlain(shift);
    let startTime = (plain.startTime || '').toString().trim();
    let endTime = (plain.endTime || '').toString().trim();
    if (startTime && endTime) return plain;
    const sid = plain._id != null ? normalizeShiftObjectIdStr(plain._id) : '';
    const sn = (plain.name || '').toString().trim().toLowerCase();
    for (const row of shifts) {
        const r = shiftRowToPlain(row);
        const rid = r._id != null ? normalizeShiftObjectIdStr(r._id) : '';
        const rn = (r.name || '').toString().trim().toLowerCase();
        const idMatch = sid && rid && sid === rid;
        const nameMatch = sn && rn && sn === rn;
        if (!idMatch && !nameMatch) continue;
        const rs = (r.startTime || '').toString().trim();
        const re = (r.endTime || '').toString().trim();
        if (rs) startTime = startTime || rs;
        if (re) endTime = endTime || re;
        if (startTime && endTime) break;
    }
    if (startTime) plain.startTime = startTime;
    if (endTime) plain.endTime = endTime;
    return plain;
};

/**
 * Required paid hours for open shifts from embedded shift; fall back to plain company POJO
 * when Mongoose subdoc does not surface `workHours` (observed with some loads).
 */
const resolveOpenShiftWorkHoursRaw = (company, shift) => {
    let raw = shift?.workHours ?? shift?.openWorkHours;
    if (raw != null && raw !== '') {
        const n = Number(raw);
        if (Number.isFinite(n) && n > 0) return n;
    }
    try {
        const plain = typeof company?.toObject === 'function' ? company.toObject() : company;
        const arr = plain?.settings?.attendance?.shifts;
        if (!Array.isArray(arr)) return null;
        const sid = shift?._id != null ? String(shift._id) : null;
        const sname = (shift?.name || '').toString().trim().toLowerCase();
        const match = arr.find((s) => {
            if (!s) return false;
            if (sid && s._id != null && String(s._id) === sid) return true;
            if (sname && (s.name || '').toString().trim().toLowerCase() === sname) return true;
            return false;
        });
        const mwh = match?.workHours ?? match?.openWorkHours;
        if (match && mwh != null && mwh !== '') {
            const n = Number(mwh);
            if (Number.isFinite(n) && n > 0) return n;
        }
    } catch (_) {}
    return null;
};

/**
 * @param {Object} company
 * @param {Object|null} staff
 * @param {Date|null} [attendanceDate] - calendar day for rotational resolution (default: now)
 * @param {Date|null} [rotationAnchorDate] - default staff.joiningDate or now
 */
/** YYYY-MM-DD in UTC for shift-resolution logs (matches attendance date storage). */
const formatDateUtcYmd = (d) => {
    if (!d || !(d instanceof Date) || Number.isNaN(d.getTime())) return null;
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, '0');
    const day = String(d.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
};

/**
 * Structured log payload: attendance UTC date, assigned rotational wrapper, cycle slot index,
 * full cycle as sub-shifts with resolved timings (after enrich).
 */
const getRotationalCycleDebugInfo = (shifts, wrapper, attendanceDate, rotationAnchorDate) => {
    if (!wrapper || !Array.isArray(shifts)) return null;
    const w = shiftRowToPlain(wrapper);
    if (!isRotationalShiftWrapper(w)) return null;
    const cfg = plainRotationalConfig(w);
    const rotationType = (cfg.rotationType || 'custom').toString().toLowerCase().trim();
    const att = attendanceDate ? new Date(attendanceDate) : new Date();
    const ymd = formatDateUtcYmd(att);

    const isLeafShiftRow = (s) => {
        if (!s) return false;
        const p = shiftRowToPlain(s);
        if (!isRotationalShiftWrapper(p)) return true;
        const st = (p.startTime || '').toString().trim();
        const en = (p.endTime || '').toString().trim();
        const hasWindow = !!(st && en);
        const hasCycle = shiftRowHasRotationalCycle(p);
        return hasWindow && !hasCycle;
    };

    const resolveLeafByIdOrName = (idHex, nm) => {
        let leaf = null;
        if (idHex) {
            leaf = shifts.find((s) => isLeafShiftRow(s) && normalizeShiftObjectIdStr(s._id) === idHex);
        }
        if (!leaf && nm) {
            const nl = String(nm).trim().toLowerCase();
            leaf = shifts.find(
                (s) => isLeafShiftRow(s) && (s.name || '').toString().trim().toLowerCase() === nl
            );
        }
        return leaf || null;
    };

    const legSummary = (s) => {
        if (!s) {
            return {
                name: null,
                id: null,
                shiftType: null,
                startTime: null,
                endTime: null,
                workHours: null
            };
        }
        const p = enrichStandardShiftTimesFromShiftsList(shifts, shiftRowToPlain(s));
        const st = (p.shiftType || '').toString().toLowerCase().trim();
        const rawWh = p.workHours ?? p.openWorkHours;
        const wh = rawWh != null && rawWh !== '' ? Number(rawWh) : null;
        return {
            name: (p.name || '').toString().trim() || null,
            id: p._id != null ? normalizeShiftObjectIdStr(p._id) : null,
            shiftType: st || null,
            startTime: (p.startTime || '').toString().trim() || null,
            endTime: (p.endTime || '').toString().trim() || null,
            workHours: Number.isFinite(wh) ? wh : null
        };
    };

    const wrapperOut = {
        name: (w.name || '').toString().trim() || null,
        id: normalizeShiftObjectIdStr(w._id) || null,
        shiftType: (w.shiftType || '').toString().toLowerCase().trim() || null
    };

    const weekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    if (rotationType === 'byweekday' || rotationType === 'by_weekday') {
        const entries = Array.isArray(cfg.shiftIdsByWeekday) ? cfg.shiftIdsByWeekday.filter(Boolean) : [];
        const y = att.getUTCFullYear();
        const mo = att.getUTCMonth();
        const d = att.getUTCDate();
        const jsDow = new Date(Date.UTC(y, mo, d)).getUTCDay();
        const subShifts = entries.map((e) => {
            const needle = e && e.shiftId != null ? normalizeShiftObjectIdStr(e.shiftId) : '';
            const leaf = needle
                ? shifts.find((s) => isLeafShiftRow(s) && normalizeShiftObjectIdStr(s._id) === needle)
                : null;
            const wd = e != null ? Number(e.day) : null;
            return {
                weekday0Sun6Sat: Number.isFinite(wd) ? wd : null,
                weekdayShort: Number.isFinite(wd) && wd >= 0 && wd <= 6 ? weekdayShort[wd] : null,
                ruleShiftId: needle || null,
                ...legSummary(leaf)
            };
        });
        const row = entries.find((e) => e && Number(e.day) === jsDow);
        const effLeaf = row && row.shiftId != null ? resolveLeafByIdOrName(normalizeShiftObjectIdStr(row.shiftId), null) : null;
        return {
            kind: 'rotational',
            rotationMode: 'byWeekday',
            dateUtc: ymd,
            utcWeekday0Sun6Sat: jsDow,
            utcWeekdayLabel: weekdayShort[jsDow],
            anchorUtc: formatDateUtcYmd(rotationAnchorDate ? new Date(rotationAnchorDate) : null),
            assignedWrapper: wrapperOut,
            subShifts,
            effectiveForDate: {
                weekday0Sun6Sat: jsDow,
                ...legSummary(effLeaf)
            }
        };
    }

    const ids = normalizedCycleIdList(cfg);
    const names = Array.isArray(cfg.shiftNamesInCycle) ? cfg.shiftNamesInCycle.filter(Boolean) : [];
    let cycleLen = Number(cfg.cycleLengthDays);
    if (!Number.isFinite(cycleLen) || cycleLen <= 0) {
        cycleLen = ids.length || names.length || 0;
    }
    if (cycleLen <= 0) {
        return {
            kind: 'rotational',
            rotationMode: rotationType,
            dateUtc: ymd,
            anchorUtc: formatDateUtcYmd(rotationAnchorDate ? new Date(rotationAnchorDate) : null),
            assignedWrapper: wrapperOut,
            error: 'cycle_empty',
            subShifts: []
        };
    }

    let idx;
    let diffDaysUtc = null;
    if (rotationType === 'weekly') {
        const y = att.getUTCFullYear();
        const mo = att.getUTCMonth();
        const d = att.getUTCDate();
        const jsDow = new Date(Date.UTC(y, mo, d)).getUTCDay();
        idx = jsDow % cycleLen;
        diffDaysUtc = null;
    } else {
        const anchor = rotationAnchorDate ? new Date(rotationAnchorDate) : att;
        diffDaysUtc = diffDaysUTC(att, anchor);
        idx = diffDaysUtc % cycleLen;
        if (idx < 0) idx += cycleLen;
    }

    const subShifts = [];
    for (let i = 0; i < cycleLen; i++) {
        const idHex = ids.length > 0 ? ids[i % ids.length] : null;
        const nm = names.length > 0 ? names[i % names.length] : null;
        const leaf = resolveLeafByIdOrName(idHex, nm);
        subShifts.push({
            cycleSlotIndex0: i,
            cycleSlotIndex1: i + 1,
            ruleShiftId: idHex,
            ruleShiftName: nm || null,
            ...legSummary(leaf)
        });
    }

    const effId = ids.length > 0 ? ids[idx % ids.length] : null;
    const effNm = names.length > 0 ? names[idx % names.length] : null;
    const effLeaf = resolveLeafByIdOrName(effId, effNm);

    return {
        kind: 'rotational',
        rotationMode: rotationType === 'weekly' ? 'weekly' : 'custom',
        dateUtc: ymd,
        anchorUtc: formatDateUtcYmd(rotationAnchorDate ? new Date(rotationAnchorDate) : null),
        diffDaysUtcFromAnchor: diffDaysUtc,
        assignedWrapper: wrapperOut,
        cycleLengthDays: cycleLen,
        cycleDayIndex0: idx,
        cycleDayIndex1: idx + 1,
        subShifts,
        effectiveForDate: {
            cycleSlotIndex0: idx,
            cycleSlotIndex1: idx + 1,
            ruleShiftId: effId,
            ruleShiftName: effNm || null,
            ...legSummary(effLeaf)
        }
    };
};

const getShiftTimings = (
    company,
    staff = null,
    attendanceDate = null,
    rotationAnchorDate = null,
    attendanceTemplateDoc = null,
    forcedShiftId = null
) => {
    /** No fabricated window: null when company/embed does not provide both start and end. */
    let startTime = null;
    let endTime = null;
    let gracePeriodMinutes = 0;
    let halfDaySettings = null;
    let shiftType = 'standard';
    /** Required paid/work hours per day when shiftType === 'open' (e.g. 9). */
    let openWorkHours = null;
    /** OT buffer on underlying standard shift (minutes after shift end before OT counts). */
    let otBufferMinutes = 0;
    /** For open shifts: duplicate of openWorkHours for controllers expecting workHours. */
    let workHours = null;
    let permissionPolicy = null;
    let breakPolicy = null;
    let overtimePolicy = null;
    /** Embedded company row used for timings after rotational resolution (for logs / UI). */
    let effectiveShiftName = null;
    /** Mongo ObjectId string of the resolved embedded shift row (same calendar day as timings). */
    let effectiveShiftId = null;
    /** True when the shift template marks this calendar day as a week-off (rotational byWeekCalendar). */
    let weekOff = false;

    const dateForShift = attendanceDate ? new Date(attendanceDate) : new Date();
    // Match Flutter rotational_shift_util: anchor = joiningDate ?? attendance calendar day (not "server now").
    const anchor =
        rotationAnchorDate != null && rotationAnchorDate !== undefined
            ? rotationAnchorDate
            : (staff && staff.joiningDate ? staff.joiningDate : dateForShift);

    const staffIdStr = staff && staff._id != null ? String(staff._id) : null;
    const attendanceYmd = formatDateUtcYmd(dateForShift);
    const anchorYmd = formatDateUtcYmd(anchor);

    // Check company settings for shifts
    if (company && company.settings && company.settings.attendance && company.settings.attendance.shifts) {
        const shiftsRaw = company.settings.attendance.shifts;
        const shifts = Array.isArray(shiftsRaw) ? shiftsRaw.map(shiftRowToPlain) : [];
        if (shifts.length > 0) {
            let shift;
            let wrapperWasRotational = false;
            // When the caller supplies the shift actually allocated/applied for this day
            // (attendance.appliedShiftId), resolve directly to that embedded row and bypass the
            // current-assignment + rotational resolution. This keeps a day's fine tied to the shift
            // that was in effect THAT day, even if the employee's shift assignment changed later.
            // Falls back to assignment-based resolution when the id is missing or no longer present
            // among embedded shifts (legacy records / deleted shifts).
            const forcedKey = forcedShiftId != null ? normalizeShiftObjectIdStr(forcedShiftId) : null;
            const forcedRow = forcedKey
                ? shifts.find((s) => s && s._id != null && normalizeShiftObjectIdStr(s._id) === forcedKey)
                : null;
            if (forcedRow) {
                shift = enrichStandardShiftTimesFromShiftsList(shifts, shiftRowToPlain(forcedRow));
            } else {
            const staffShiftKey = staffShiftKeyFromStaff(staff, attendanceTemplateDoc);
            let wrapper = staffShiftKey
                ? findShiftByStaffKey(shifts, staffShiftKey) || shifts[0]
                : shifts[0];
            wrapper = enrichWrapperRotationalFromDuplicateRows(shifts, wrapper);
            wrapper = wrapperWithMergedRotationalConfig(shifts, wrapper);
            wrapperWasRotational = wrapper != null && isRotationalShiftWrapper(wrapper);

            // console.log('[API][getShiftTimings] input', {
            //     attendanceDateUtc: attendanceYmd,
            //     rotationAnchorUtc: anchorYmd,
            //     staffId: staffIdStr,
            //     staffShiftKey: staffShiftKey || null,
            //     embeddedShiftsCount: shifts.length,
            //     wrapperName,
            //     wrapperId,
            //     wrapperIsRotational: wrapperRotational,
            //     mergedRotationalConfigFromSibling: mergedSiblingConfig
            // });

            // const rotationalCycleDetail = getRotationalCycleDebugInfo(shifts, wrapper, dateForShift, anchor);
            // if (rotationalCycleDetail) {
            //     console.log(
            //         '[API][getShiftTimings] rotationalCycleDetail',
            //         JSON.stringify(rotationalCycleDetail, null, 2)
            //     );
            // }

            shift = resolveEffectiveShiftRaw(shifts, wrapper, dateForShift, anchor);
            // A rotational byWeekCalendar shift can designate a specific date as a week-off
            // (weeklyDateAssignments[].isWeekOff); resolveEffectiveShiftRaw flags it as
            // __rotationWeekOff on the resolved row. Capture it before enrich/return drop the
            // marker so callers (e.g. the month calendar) render "Week Off" rather than the
            // shift's default window.
            weekOff = parseBoolLoose(shift && shift.__rotationWeekOff);
            shift = enrichStandardShiftTimesFromShiftsList(shifts, shift);
            }
            effectiveShiftName = (shift.name || '').toString().trim() || null;
            effectiveShiftId = shift._id != null ? String(shift._id) : null;
            // console.log('[API][getShiftTimings] resolvedRow', {
            //     effectiveShiftName,
            //     effectiveShiftId,
            //     rawStartTime: rawStartAfterResolve || null,
            //     rawEndTime: rawEndAfterResolve || null,
            //     resolvedToDifferentRowThanWrapper: resolvedDiffersFromWrapper
            // });
            // console.log('[Fine][getShiftTimings] Raw shift object: name=', shift.name, 'shiftType=', shift.shiftType, '_id=', effectiveShiftId);

            shiftType = (shift.shiftType || '').toString().toLowerCase().trim();
            if (!shiftType && shift.startTime && shift.endTime) {
                shiftType = 'standard';
            }
            // console.log('[Fine][getShiftTimings] After initial shiftType assignment: shiftType=', shiftType);
            // If the shift name is "OPEN" / "open shift" (any case), treat as open shift.
            const shiftNameLower = (shift.name || '').toString().toLowerCase().trim();
            if (shiftNameLower === 'open' || shiftNameLower === 'open shift') {
                shiftType = 'open';
                // console.log('[Fine][getShiftTimings] ShiftType updated to OPEN based on name (override): shiftType=', shiftType);
            }

            if (shiftType === 'open' || shiftType === 'open shift') {
                const resolvedWh = resolveOpenShiftWorkHoursRaw(company, shift);
                // console.log('[Fine][getShiftTimings] Raw shift.workHours from DB:', shift.workHours, 'resolved=', resolvedWh);
                openWorkHours = Number(resolvedWh != null ? resolvedWh : shift.workHours);
                if (!Number.isFinite(openWorkHours) || openWorkHours <= 0) openWorkHours = 8;
                workHours = openWorkHours;
                otBufferMinutes = Math.max(0, Math.floor(Number(shift.otBufferMinutes ?? 0) || 0));
                startTime = null; // Explicitly set to null for open shifts
                endTime = null;   // Explicitly set to null for open shifts
                // console.log('[Fine][getShiftTimings] Open Shift Details: shiftType=', shiftType, 'openWorkHours=', openWorkHours, 'workHours=', workHours, 'otBufferMinutes=', otBufferMinutes, 'startTime=', startTime, 'endTime=', endTime);
            } else {
                const stWin = (shift.startTime || '').toString().trim();
                const enWin = (shift.endTime || '').toString().trim();
                if (stWin && enWin) {
                    startTime = stWin;
                    endTime = enWin;
                } else {
                    startTime = null;
                    endTime = null;
                }
                if (shiftType === 'standard') {
                    otBufferMinutes = Math.max(0, Math.floor(Number(shift.otBufferMinutes ?? 0) || 0));
                }
            }
            if (!shiftType || shiftType === '') {
                shiftType = wrapperWasRotational ? 'rotational' : 'standard';
            }

            // Extract grace time from shift.graceTime.value and shift.graceTime.unit
            if (shift.graceTime) {
                if (shift.graceTime.unit === 'hours') {
                    gracePeriodMinutes = (shift.graceTime.value || 0) * 60;
                } else {
                    gracePeriodMinutes = shift.graceTime.value || 0;
                }
            }
            // Half-day leave settings from company (customMidPointTime, firstHalfEndTime, secondHalfStartTime, etc.)
            if (shift.halfDaySettings && shift.halfDaySettings.enabled) {
                halfDaySettings = {
                    customMidPointTime: shift.halfDaySettings.customMidPointTime || shift.halfDaySettings.firstHalfEndTime || shift.halfDaySettings.secondHalfStartTime || null,
                    firstHalfLogoutGraceMinutes: shift.halfDaySettings.firstHalfLogoutGraceMinutes ?? 0,
                    secondHalfLoginGraceMinutes: shift.halfDaySettings.secondHalfLoginGraceMinutes ?? 0,
                    secondHalfStrictLogin: shift.halfDaySettings.secondHalfStrictLogin === true
                };
            }
            if (shift.permissionPolicy && typeof shift.permissionPolicy === 'object') {
                permissionPolicy = {
                    enabled: shift.permissionPolicy.enabled === true,
                    monthlyQuotaMinutes: Math.max(0, Number(shift.permissionPolicy.monthlyQuotaMinutes || 0)),
                    applyTo: ['lateArrival', 'earlyExit', 'both'].includes(String(shift.permissionPolicy.applyTo || 'both'))
                        ? String(shift.permissionPolicy.applyTo || 'both')
                        : 'both'
                };
            }
            if (shift.breakPolicy && typeof shift.breakPolicy === 'object') {
                const fineTypeRaw = String(shift.breakPolicy.fineType || '1xSalary');
                breakPolicy = {
                    enabled: shift.breakPolicy.enabled === true,
                    allowedMinutes: Math.max(0, Number(shift.breakPolicy.allowedMinutes || 0)),
                    fineEnabled: shift.breakPolicy.fineEnabled === true,
                    fineType: ['1xSalary', '2xSalary', '3xSalary', 'custom'].includes(fineTypeRaw)
                        ? fineTypeRaw
                        : '1xSalary',
                    customFinePerHour: Math.max(0, Number(shift.breakPolicy.customFinePerHour || 0))
                };
            }
            if (shift.overtimePolicy && typeof shift.overtimePolicy === 'object') {
                const rawEnabled = shift.overtimePolicy.enabled;
                const rawMult = Number(shift.overtimePolicy.multiplier);
                overtimePolicy = {
                    // Tri-state: null = not configured (fall back to AttendanceTemplate.allowOvertime).
                    enabled: rawEnabled == null ? null : rawEnabled === true,
                    multiplier: Number.isFinite(rawMult) && rawMult > 0 ? rawMult : null
                };
            }

            const missingStandardWindow =
                shiftType !== 'open' &&
                shiftType !== 'open shift' &&
                (!startTime || !endTime);
            // console.log('[API][getShiftTimings] output', {
            //     attendanceDateUtc: attendanceYmd,
            //     staffId: staffIdStr,
            //     shiftType,
            //     startTime: shiftType === 'open' || shiftType === 'open shift' ? null : startTime,
            //     endTime: shiftType === 'open' || shiftType === 'open shift' ? null : endTime,
            //     openWorkHours: shiftType === 'open' || shiftType === 'open shift' ? openWorkHours : null,
            //     otBufferMinutes,
            //     gracePeriodMinutes,
            //     effectiveShiftName,
            //     effectiveShiftId,
            //     missingStandardWindow
            // });
        } else {
            // console.log('[API][getShiftTimings] embedded_shifts_empty', {
            //     attendanceDateUtc: attendanceYmd,
            //     staffId: staffIdStr,
            //     staffShiftKey: staffShiftKeyFromStaff(staff, attendanceTemplateDoc) || null
            // });
        }
    } else {
        // console.log('[API][getShiftTimings] no_company_shifts', {
        //     attendanceDateUtc: attendanceYmd,
        //     staffId: staffIdStr,
        //     hasCompany: !!company,
        //     hasAttendanceSettings: !!(company && company.settings && company.settings.attendance)
        // });
    }

    return {
        startTime,
        endTime,
        gracePeriodMinutes,
        halfDaySettings,
        shiftType,
        openWorkHours,
        otBufferMinutes,
        workHours,
        permissionPolicy,
        breakPolicy,
        overtimePolicy,
        effectiveShiftName,
        effectiveShiftId,
        weekOff
    };
};

/**
 * Calculate work hours from shift timings
 * @param {String} startTime - Shift start time in HH:mm format
 * @param {String} endTime - Shift end time in HH:mm format
 * @returns {Number} - Work hours (in hours, e.g., 8.5 for 8 hours 30 minutes)
 */
const calculateWorkHoursFromShift = (startTime, endTime) => {
    try {
        if (startTime == null || endTime == null) return null;
        const ss = String(startTime).trim();
        const ee = String(endTime).trim();
        if (!ss || !ee) return null;
        const [startHours, startMins] = ss.split(':').map(Number);
        const [endHours, endMins] = ee.split(':').map(Number);
        
        const startMinutes = startHours * 60 + startMins;
        const endMinutes = endHours * 60 + endMins;
        const diffMinutes = endMinutes - startMinutes;
        
        return diffMinutes / 60.0; // Convert to hours
    } catch (error) {
        console.error('[LeaveAttendanceHelper] Error calculating work hours:', error);
        return 8.0; // Default 8 hours
    }
};

/**
 * Mark attendance as "Present" for all dates covered by an approved leave
 * This is called when a leave is approved
 * Checks leaveTemplate to ensure leave is valid and within limits
 * @param {Object} leave - The approved leave document
 */
const markAttendanceForApprovedLeave = async (leave) => {
    try {
        if (!leave || !/^approved$/i.test(leave.status)) {
            return;
        }

        const { employeeId, startDate, endDate, businessId, leaveType, days } = leave;
        
        // Fetch staff with leaveTemplateId populated
        const staff = await Staff.findById(employeeId).populate('leaveTemplateId');
        if (!staff) {
            console.error(`[LeaveAttendanceHelper] Staff not found: ${employeeId}`);
            return;
        }

        // Check if staff has a leaveTemplateId
        if (!staff.leaveTemplateId) {
            console.log(`[LeaveAttendanceHelper] Staff ${employeeId} has no leaveTemplateId, skipping attendance marking`);
            return;
        }

        // Get leaveTemplate
        const leaveTemplate = await LeaveTemplate.findById(staff.leaveTemplateId);
        if (!leaveTemplate) {
            console.error(`[LeaveAttendanceHelper] LeaveTemplate not found: ${staff.leaveTemplateId}`);
            return;
        }

        const isHalfDay = (leaveType || '').trim().toLowerCase() === 'half day';
        let leaveConfig = null;

        if (!leaveTemplate.leaveTypes || !Array.isArray(leaveTemplate.leaveTypes)) {
            if (!isHalfDay) {
                console.log(`[LeaveAttendanceHelper] LeaveTemplate has no leaveTypes array`);
                return;
            }
        } else {
            leaveConfig = leaveTemplate.leaveTypes.find(
                t => t.type && t.type.toLowerCase() === leaveType.toLowerCase()
            );
            if (!leaveConfig && !isHalfDay) {
                console.log(`[LeaveAttendanceHelper] LeaveType "${leaveType}" not found in template`);
                return;
            }
        }

        // Check if user has already exceeded their leave limit (including pending leaves)
        const leaveDate = new Date(startDate);
        // Use the calculateAvailableLeaves function defined in this file
        const leaveInfo = await calculateAvailableLeaves(staff, leaveType, leaveDate);
        
        // Check if there are pending leaves that would exceed the limit
        // We need to check if current approved + pending leaves exceed the limit
        // Handle both "Casual" and "Casual Leave" formats
        const leaveTypeLower = leaveType.toLowerCase().trim();
        const isCasual = leaveTypeLower === 'casual' || leaveTypeLower.startsWith('casual');
        const targetYear = leaveDate.getFullYear();
        const targetMonth = leaveDate.getMonth();
        const rangeStart = isCasual
            ? new Date(targetYear, targetMonth, 1)
            : new Date(targetYear, 0, 1);
        const rangeEnd = isCasual
            ? new Date(targetYear, targetMonth + 1, 0, 23, 59, 59)
            : new Date(targetYear, 11, 31, 23, 59, 59);

        // Get all pending leaves of this type in the period
        const pendingLeaves = await Leave.find({
            employeeId: employeeId,
            _id: { $ne: leave._id }, // Exclude current leave
            leaveType: { $regex: new RegExp(`^${leaveType}$`, 'i') },
            status: 'Pending',
            $or: [
                { startDate: { $gte: rangeStart, $lte: rangeEnd } },
                { endDate: { $gte: rangeStart, $lte: rangeEnd } },
                { startDate: { $lte: rangeStart }, endDate: { $gte: rangeEnd } }
            ]
        });

        const pendingDays = pendingLeaves.reduce((sum, l) => sum + l.days, 0);
        
        // If total (used + current + pending) exceeds limit, don't mark as present (skip for Half Day if no limit)
        if (!isHalfDay && leaveInfo.totalAvailable !== null && (leaveInfo.used + days + pendingDays) > leaveInfo.totalAvailable) {
            console.log(`[LeaveAttendanceHelper] Leave limit would be exceeded. Used: ${leaveInfo.used}, Current: ${days}, Pending: ${pendingDays}, Total Available: ${leaveInfo.totalAvailable}`);
            return;
        }

        // Get company for shift timings
        const company = await Company.findById(businessId);

        // Generate all dates between startDate and endDate (inclusive) using UTC calendar day
        const dates = [];
        const start = new Date(startDate);
        const end = new Date(endDate);
        const startUtc = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate());
        const endUtc = Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate());
        let currentUtc = startUtc;
        const oneDayMs = 24 * 60 * 60 * 1000;
        while (currentUtc <= endUtc) {
            dates.push(new Date(currentUtc));
            currentUtc += oneDayMs;
        }

        // Mark attendance for each calendar day; use local midnight so it matches check-in (attendance controller uses local date)
        for (const date of dates) {
            const y = date.getUTCFullYear(), m = date.getUTCMonth(), d = date.getUTCDate();
            const startOfDay = new Date(y, m, d, 0, 0, 0, 0);
            const endOfDay = new Date(y, m, d, 23, 59, 59, 999);

            const { startTime, endTime } = getShiftTimings(company, staff, date, staff?.joiningDate);
            const punchStart = startTime || DEFAULT_SHIFT_START;
            const punchEnd = endTime || DEFAULT_SHIFT_END;

            // Create punch in/out times based on shift timings (fallback when embed has no window)
            const [startHours, startMins] = punchStart.split(':').map(Number);
            const [endHours, endMins] = punchEnd.split(':').map(Number);
            
            const punchIn = new Date(startOfDay.getTime() + (startHours * 60 + startMins) * 60 * 1000);
            const punchOut = new Date(startOfDay.getTime() + (endHours * 60 + endMins) * 60 * 1000);

            let attendance = await Attendance.findOne({
                employeeId: employeeId,
                date: { $gte: startOfDay, $lte: endOfDay }
            });

            const isHalfDayRow = isHalfDayLeave(leave);
            const halfDaySessionValue = isHalfDayRow ? resolveHalfDaySession(leave) : null;
            const sessionRemarks = isHalfDayRow
                ? (halfDaySessionValue === 'First Half Day'
                    ? 'Half day leave approved - First Half Day. Employee should punch in for verification.'
                    : 'Half day leave approved - Second Half Day. Employee should punch in for verification.')
                : 'On Leave (approved)';
            // For a half-day of a real leave type (e.g. Casual/Sick), keep the
            // Attendance.leaveType within its enum; map session ('1'/'2') -> session.
            const attendanceSession = isHalfDayRow
                ? (leave.session || (halfDaySessionValue === 'First Half Day' ? '1' : halfDaySessionValue === 'Second Half Day' ? '2' : null))
                : null;

            if (attendance) {
                // Update existing attendance record
                attendance.status = isHalfDayRow ? 'Half Day' : 'On Leave';
                attendance.leaveType = leave.leaveType;
                attendance.session = attendanceSession;
                attendance.halfDaySession = halfDaySessionValue;
                attendance.remarks = (attendance.remarks || '').trim() ? (attendance.remarks + ' ' + sessionRemarks) : sessionRemarks;
                // Full-day leave: no check-in/check-out
                if (!isHalfDayRow) {
                    attendance.punchIn = undefined;
                    attendance.punchOut = undefined;
                    attendance.workHours = 0;
                }
                attendance.approvedBy = leave.approvedBy;
                attendance.approvedAt = leave.approvedAt || new Date();
                await attendance.save();
            } else {
                await Attendance.create({
                    employeeId: employeeId,
                    user: employeeId,
                    date: startOfDay,
                    status: isHalfDayRow ? 'Half Day' : 'On Leave',
                    leaveType: leave.leaveType,
                    session: attendanceSession,
                    halfDaySession: halfDaySessionValue,
                    approvedBy: leave.approvedBy,
                    approvedAt: leave.approvedAt || new Date(),
                    businessId: businessId,
                    workHours: isHalfDayRow ? undefined : 0,
                    remarks: sessionRemarks
                });
            }
        }

        console.log(`[LeaveAttendanceHelper] Marked attendance as On Leave for ${dates.length} days for leave ${leave._id}`);
    } catch (error) {
        console.error('[LeaveAttendanceHelper] Error marking attendance for approved leave:', error);
        throw error;
    }
};

/**
 * Revert attendance for a deleted or cancelled leave
 * @param {Object} leave - The leave document
 */
const revertAttendanceForDeletedLeave = async (leave) => {
    try {
        if (!leave) return;

        const { employeeId, startDate, endDate } = leave;
        
        // Generate all dates between startDate and endDate (inclusive) using UTC calendar day
        const dates = [];
        const start = new Date(startDate);
        const end = new Date(endDate);
        const startUtc = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate());
        const endUtc = Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate());
        let currentUtc = startUtc;
        const oneDayMs = 24 * 60 * 60 * 1000;
        while (currentUtc <= endUtc) {
            dates.push(new Date(currentUtc));
            currentUtc += oneDayMs;
        }

        for (const date of dates) {
            const y = date.getUTCFullYear(), m = date.getUTCMonth(), d = date.getUTCDate();
            const startOfDay = new Date(y, m, d, 0, 0, 0, 0);
            const endOfDay = new Date(y, m, d, 23, 59, 59, 999);

            const attendance = await Attendance.findOne({
                employeeId: employeeId,
                date: { $gte: startOfDay, $lte: endOfDay }
            });

            if (attendance && (attendance.status === 'On Leave' || attendance.status === 'Half Day')) {
                if (!attendance.punchIn && !attendance.punchOut) {
                     await Attendance.deleteOne({ _id: attendance._id });
                } else {
                    attendance.status = 'Pending';
                    attendance.leaveType = undefined;
                    attendance.session = undefined;
                    attendance.halfDaySession = undefined;
                    attendance.approvedBy = undefined;
                    attendance.approvedAt = undefined;
                    attendance.remarks = (attendance.remarks || '')
                        .replace(/On Leave/i, '')
                        .replace(/\[Half Day - (Session [12]|[12])\]/i, '')
                        .replace(/Half Day - (Session [12]|[12])/i, '')
                        .replace(/Half-day leave \(First Half Day\) approved/gi, '')
                        .replace(/Half-day leave \(Second Half Day\) approved/gi, '')
                        .replace(/Half-day leave \(Session [12]\) approved/gi, '')
                        .replace(/On Leave \(approved\)/gi, '')
                        .trim();
                    await attendance.save();
                }
            }
        }
        console.log(`[LeaveAttendanceHelper] Reverted attendance for ${dates.length} days for leave ${leave._id}`);
    } catch (error) {
        console.error('[LeaveAttendanceHelper] Error reverting attendance for deleted leave:', error);
    }
};

/**
 * Calculate available leaves considering carryForward logic
 * @param {Object} staff - Staff document with populated leaveTemplateId
 * @param {String} leaveType - Type of leave (e.g., 'Casual', 'Sick')
 * @param {Date} targetDate - Date for which to calculate available leaves (defaults to current month)
 * @returns {Object} - { baseLimit, carriedForward, totalAvailable, used, balance }
 */
const calculateAvailableLeaves = async (staff, leaveType, targetDate = new Date()) => {
    if (!staff || !staff.leaveTemplateId) {
        return { baseLimit: null, carriedForward: 0, totalAvailable: null, used: 0, balance: 999 };
    }

    const template = staff.leaveTemplateId;
    let baseLimit = null;
    let carryForward = false;

    // Find leave config from template
    if (template.leaveTypes && Array.isArray(template.leaveTypes)) {
        const leaveConfig = template.leaveTypes.find(
            t => t.type && t.type.toLowerCase() === leaveType.toLowerCase()
        );
        if (leaveConfig) {
            baseLimit = leaveConfig.days || leaveConfig.limit || null;
            carryForward = leaveConfig.carryForward === true;
        }
    }

    if (baseLimit === null) {
        return { baseLimit: null, carriedForward: 0, totalAvailable: null, used: 0, balance: 999 };
    }

        // Determine if this is a monthly (Casual) or yearly (Sick) leave
        // Handle both "Casual" and "Casual Leave" formats
        const leaveTypeLower = leaveType.toLowerCase().trim();
        const isCasual = leaveTypeLower === 'casual' || leaveTypeLower.startsWith('casual');
    const targetYear = targetDate.getFullYear();
    const targetMonth = targetDate.getMonth();

    // Calculate range for current period
    const rangeStart = isCasual
        ? new Date(targetYear, targetMonth, 1)
        : new Date(targetYear, 0, 1);
    const rangeEnd = isCasual
        ? new Date(targetYear, targetMonth + 1, 0, 23, 59, 59)
        : new Date(targetYear, 11, 31, 23, 59, 59);

    // Build a flexible regex that handles:
    // 1. Case-insensitivity
    // 2. Optional "Leave" suffix
    // 3. Leading/trailing whitespace
    const normalizedType = (leaveType || '').trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const flexibleRegex = new RegExp(`^\\s*${normalizedType}(\\s+leave)?\\s*$`, 'i');
    
    // Get ALL relevant leaves in current period (Approved and Pending)
    const relevantLeaves = await Leave.find({
        employeeId: staff._id,
        leaveType: { $regex: flexibleRegex },
        status: { $regex: /^(approved|pending)$/i },
        $or: [
            { startDate: { $gte: rangeStart, $lte: rangeEnd } },
            { endDate: { $gte: rangeStart, $lte: rangeEnd } },
            { startDate: { $lte: rangeStart }, endDate: { $gte: rangeEnd } }
        ]
    });

    let approvedDays = 0;
    let pendingDays = 0;

    relevantLeaves.forEach(l => {
        const lStart = new Date(l.startDate);
        const lEnd = new Date(l.endDate);
        
        // Calculate overlap with target period
        const overlapStart = lStart > rangeStart ? lStart : rangeStart;
        const overlapEnd = lEnd < rangeEnd ? lEnd : rangeEnd;
        
        if (overlapEnd >= overlapStart) {
            // Normalize to midnight for accurate day counting
            const oStart = new Date(overlapStart.getFullYear(), overlapStart.getMonth(), overlapStart.getDate());
            const oEnd = new Date(overlapEnd.getFullYear(), overlapEnd.getMonth(), overlapEnd.getDate());
            const diffTime = Math.abs(oEnd - oStart);
            const overlapDays = Math.round(diffTime / (1000 * 60 * 60 * 24)) + 1;
            // Half day leave: use stored l.days (0.5) or 0.5 per day; full day: use overlap days
            const isHalfDay = (l.leaveType || '').trim().toLowerCase() === 'half day';
            const contribution = isHalfDay ? (l.days != null && l.days > 0 ? l.days : overlapDays * 0.5) : overlapDays;
            
            if (/^approved$/i.test(l.status)) {
                approvedDays += contribution;
            } else if (/^pending$/i.test(l.status)) {
                pendingDays += contribution;
            }
        }
    });

    const used = approvedDays;
    const pending = pendingDays;

    // Calculate carried forward leaves if carryForward is enabled
    let carriedForward = 0;
    if (carryForward) {
        // For monthly leaves (Casual), check previous month
        // For yearly leaves (Sick), check previous year
        if (isCasual) {
            // Previous month
            const prevMonth = targetMonth === 0 ? 11 : targetMonth - 1;
            const prevYear = targetMonth === 0 ? targetYear - 1 : targetYear;
            const prevRangeStart = new Date(prevYear, prevMonth, 1);
            const prevRangeEnd = new Date(prevYear, prevMonth + 1, 0, 23, 59, 59);

            const prevMonthLeaves = await Leave.find({
                employeeId: staff._id,
                leaveType: { $regex: flexibleRegex },
                status: { $regex: /^approved$/i },
                $or: [
                    { startDate: { $gte: prevRangeStart, $lte: prevRangeEnd } },
                    { endDate: { $gte: prevRangeStart, $lte: prevRangeEnd } },
                    { startDate: { $lte: prevRangeStart }, endDate: { $gte: prevRangeEnd } }
                ]
            });

            let prevApprovedDays = 0;
            prevMonthLeaves.forEach(l => {
                const lStart = new Date(l.startDate);
                const lEnd = new Date(l.endDate);
                const overlapStart = lStart > prevRangeStart ? lStart : prevRangeStart;
                const overlapEnd = lEnd < prevRangeEnd ? lEnd : prevRangeEnd;
                if (overlapEnd >= overlapStart) {
                    const oStart = new Date(overlapStart.getFullYear(), overlapStart.getMonth(), overlapStart.getDate());
                    const oEnd = new Date(overlapEnd.getFullYear(), overlapEnd.getMonth(), overlapEnd.getDate());
                    const overlapDays = Math.round(Math.abs(oEnd - oStart) / (1000 * 60 * 60 * 24)) + 1;
                    const isHalfDay = (l.leaveType || '').trim().toLowerCase() === 'half day';
                    prevApprovedDays += isHalfDay ? (l.days != null && l.days > 0 ? l.days : overlapDays * 0.5) : overlapDays;
                }
            });
            carriedForward = Math.max(0, baseLimit - prevApprovedDays);
        } else {
            // Previous year
            const prevYear = targetYear - 1;
            const prevRangeStart = new Date(prevYear, 0, 1);
            const prevRangeEnd = new Date(prevYear, 11, 31, 23, 59, 59);

            const prevYearLeaves = await Leave.find({
                employeeId: staff._id,
                leaveType: { $regex: flexibleRegex },
                status: { $regex: /^approved$/i },
                $or: [
                    { startDate: { $gte: prevRangeStart, $lte: prevRangeEnd } },
                    { endDate: { $gte: prevRangeStart, $lte: prevRangeEnd } },
                    { startDate: { $lte: prevRangeStart }, endDate: { $gte: prevRangeEnd } }
                ]
            });

            let prevApprovedDays = 0;
            prevYearLeaves.forEach(l => {
                const lStart = new Date(l.startDate);
                const lEnd = new Date(l.endDate);
                const overlapStart = lStart > prevRangeStart ? lStart : prevRangeStart;
                const overlapEnd = lEnd < prevRangeEnd ? lEnd : prevRangeEnd;
                if (overlapEnd >= overlapStart) {
                    const oStart = new Date(overlapStart.getFullYear(), overlapStart.getMonth(), overlapStart.getDate());
                    const oEnd = new Date(overlapEnd.getFullYear(), overlapEnd.getMonth(), overlapEnd.getDate());
                    const overlapDays = Math.round(Math.abs(oEnd - oStart) / (1000 * 60 * 60 * 24)) + 1;
                    const isHalfDay = (l.leaveType || '').trim().toLowerCase() === 'half day';
                    prevApprovedDays += isHalfDay ? (l.days != null && l.days > 0 ? l.days : overlapDays * 0.5) : overlapDays;
                }
            });
            carriedForward = Math.max(0, baseLimit - prevApprovedDays);
        }
    }

    const totalAvailable = baseLimit + carriedForward;
    // Balance check should consider BOTH approved and pending to prevent over-drafting
    const balance = Math.max(0, totalAvailable - (used + pending));

    return {
        baseLimit,
        carriedForward,
        totalAvailable,
        used, // ONLY approved (this is what "Taken" usually shows)
        pending, // separately returned
        balance,
        isMonthly: isCasual,
        carryForwardEnabled: carryForward
    };
};

/**
 * Get working session timings for Half Day leave, calculated from shift times.
 * Uses halfDaySettings.customMidPointTime when provided (from company shift).
 * Session 1 leave → employee works Session 2 (mid to shift end)
 * Session 2 leave → employee works Session 1 (shift start to mid)
 */
const getWorkingSessionTimings = (session, shiftStartTime, shiftEndTime, halfDaySettings = null) => {
    if (!session) return null;
    try {
        const b = getHalfDaySessionBoundaries(shiftStartTime || DEFAULT_SHIFT_START, shiftEndTime || DEFAULT_SHIFT_END, halfDaySettings);
        // If 'First Half Day' leave, employee works SECOND HALF
        if (session === 'First Half Day' || session === '1') {
            return { startTime: b.session2Start, endTime: b.session2End };
        }
        // If 'Second Half Day' leave, employee works FIRST HALF
        if (session === 'Second Half Day' || session === '2') {
            return { startTime: b.session1Start, endTime: b.session1End };
        }
        return null;
    } catch (error) {
        console.error('[getWorkingSessionTimings] Error calculating from shift times:', error);
        return null;
    }
};

/**
 * Calculate late check-in fine for Half Day session.
 * Uses fine config from company.settings.payroll.fineCalculation only: formula + fineRules.
 * @param {Object} [fineConfig] - from getEffectiveFineConfig(company)
 * @returns {{ lateMinutes: number, fineAmount: number }}
 */
const calculateHalfDayLateFine = (punchInTime, attendanceDate, session, gracePeriodMinutes, dailySalary, shiftHours, shiftStartTime, shiftEndTime, fineConfig = null, halfDaySettings = null, dailyGrossForRules = null) => {
    const timings = getWorkingSessionTimings(session, shiftStartTime, shiftEndTime, halfDaySettings);
    if (!timings) return { lateMinutes: 0, fineAmount: 0 };
    const [startHours, startMins] = timings.startTime.split(':').map(Number);
    const shiftStart = new Date(attendanceDate);
    shiftStart.setHours(startHours, startMins, 0, 0);
    const graceTimeEnd = new Date(shiftStart);
    graceTimeEnd.setMinutes(graceTimeEnd.getMinutes() + gracePeriodMinutes);
    if (punchInTime <= graceTimeEnd) return { lateMinutes: 0, fineAmount: 0 };
    const lateMinutes = Math.max(0, Math.round((punchInTime.getTime() - shiftStart.getTime()) / (1000 * 60)));
    if (lateMinutes <= 0) return { lateMinutes, fineAmount: 0 };
    if (fineConfig && fineConfig.enabled === false) return { lateMinutes, fineAmount: 0 };
    console.log(
        '[Fine][formula][test][half-day][lateArrival] input | minutes=%s dailyNet=%s dailyGross=%s shiftHours=%s calcType=%s',
        lateMinutes,
        dailySalary,
        dailyGrossForRules,
        shiftHours,
        fineConfig?.calculationType || 'shiftBased'
    );
    const fineAmount = calculateFineAmount(lateMinutes, 'lateArrival', fineConfig, dailySalary, shiftHours, dailyGrossForRules);
    console.log(
        '[Fine][formula][test][half-day][lateArrival] output | formula=Fine=(base÷shiftHours)×(minutes÷60) | finalFine=%s',
        fineAmount
    );
    return { lateMinutes, fineAmount };
};

/**
 * Calculate early logout fine for Half Day session. Uses effective fine config (formula + fineRules).
 * @param {Object} [fineConfig] - from getEffectiveFineConfig(company)
 * @returns {{ earlyMinutes: number, fineAmount: number }}
 */
const calculateHalfDayEarlyFine = (punchOutTime, attendanceDate, session, dailySalary, shiftHours, shiftStartTime, shiftEndTime, fineConfig = null, halfDaySettings = null, dailyGrossForRules = null) => {
    const timings = getWorkingSessionTimings(session, shiftStartTime, shiftEndTime, halfDaySettings);
    if (!timings) return { earlyMinutes: 0, fineAmount: 0 };
    const [endHours, endMins] = timings.endTime.split(':').map(Number);
    const shiftEnd = new Date(attendanceDate);
    shiftEnd.setHours(endHours, endMins, 0, 0);
    if (punchOutTime >= shiftEnd) return { earlyMinutes: 0, fineAmount: 0 };
    const earlyMinutes = Math.max(0, Math.round((shiftEnd.getTime() - punchOutTime.getTime()) / (1000 * 60)));
    if (earlyMinutes <= 0) return { earlyMinutes, fineAmount: 0 };
    if (fineConfig && fineConfig.enabled === false) return { earlyMinutes, fineAmount: 0 };
    console.log(
        '[Fine][formula][test][half-day][earlyExit] input | minutes=%s dailyNet=%s dailyGross=%s shiftHours=%s calcType=%s',
        earlyMinutes,
        dailySalary,
        dailyGrossForRules,
        shiftHours,
        fineConfig?.calculationType || 'shiftBased'
    );
    const fineAmount = calculateFineAmount(earlyMinutes, 'earlyExit', fineConfig, dailySalary, shiftHours, dailyGrossForRules);
    console.log(
        '[Fine][formula][test][half-day][earlyExit] output | formula=Fine=(base÷shiftHours)×(minutes÷60) | finalFine=%s',
        fineAmount
    );
    return { earlyMinutes, fineAmount };
};

/**
 * Open shift OT + buffer tracking (minutes). OT equals full extra worked time above required shift length.
 * bufferTimeUsed repeats in full buffer blocks: floor(extra / buffer) * buffer (tracking only; OT is not reduced).
 * @param {number} workedMinutes
 * @param {number} requiredShiftMinutes  daily required minutes for the open shift
 * @param {number} bufferTimeMinutes  otBufferMinutes from shift (0 if unset)
 * @returns {{ overtimeMinutes: number, bufferTimeUsed: number }}
 */
const computeOpenShiftOvertimeWithBufferTracking = (
    workedMinutes,
    requiredShiftMinutes,
    bufferTimeMinutes
) => {
    const w = Math.round(Number(workedMinutes) || 0);
    const shiftMin = Math.max(0, Math.round(Number(requiredShiftMinutes) || 0));
    const buf = Math.max(0, Math.round(Number(bufferTimeMinutes) || 0));
    const extraMinutes = w - shiftMin;
    if (extraMinutes <= 0) {
        console.log('[OT Minutes][open shift] workMins=%s requiredMins=%s (%.2fh) extra=%s → overtime=0 bufferTime=0',
            w, shiftMin, shiftMin / 60, extraMinutes);
        return { overtimeMinutes: 0, bufferTimeUsed: 0 };
    }
    let bufferTimeUsed = 0;
    if (buf > 0) {
        bufferTimeUsed = Math.floor(extraMinutes / buf) * buf;
    }
    const fullBlocks = buf > 0 ? Math.floor(extraMinutes / buf) : 0;
    console.log('[OT Minutes][open shift] formula: extra = workMins − requiredMins = %s − %s = %s | bufferTrack = floor(extra÷otBuffer)×otBuffer = floor(%s÷%s)×%s = %s',
        w, shiftMin, extraMinutes, extraMinutes, buf || 'n/a', buf || 0, bufferTimeUsed);
    console.log('[OT Minutes][open shift] result: overtimeMinutes=%s bufferTimeUsed=%s (fullBufferBlocks=%s)',
        extraMinutes, bufferTimeUsed, fullBlocks);
    return { overtimeMinutes: extraMinutes, bufferTimeUsed };
};

module.exports = {
    markAttendanceForApprovedLeave,
    calculateAvailableLeaves,
    revertAttendanceForDeletedLeave,
    isHalfDayLeave,
    isHalfDayLeaveType,
    resolveHalfDaySession,
    canCheckInWithHalfDayLeave,
    canCheckOutWithHalfDayLeave,
    isWithinSecondHalfEarlyLoginWindow,
    getHalfDaySessionMessage,
    isCurrentlyInLeaveSession,
    getLeaveMessageForUI,
    getWorkingSessionTimings,
    calculateHalfDayLateFine,
    calculateHalfDayEarlyFine,
    getShiftTimings,
    getHalfDaySessionBoundaries,
    staffShiftKeyFromStaff,
    calculateWorkHoursFromShift,
    getBusinessTimezone,
    getShiftBoundaryAsUTCDate,
    computeOpenShiftOvertimeWithBufferTracking
};
