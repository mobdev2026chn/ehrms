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
    if (leave.leaveType === 'Half Day') {
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
        // First Half Day leave: employee works SECOND HALF. Check-in allowed from (mid - secondHalfLoginGraceMinutes) to shift end.
        // secondHalfLoginGraceMinutes = login allowed before mid time (e.g. 30 min before 14:30 => from 14:00). If secondHalfStrictLogin: from mid only.
        const strict = halfDaySettings && halfDaySettings.secondHalfStrictLogin === true;
        const graceMins = halfDaySettings?.secondHalfLoginGraceMinutes ?? 0;
        const checkInFrom = (strict || graceMins === 0) ? midMin : midMin - graceMins;
        const checkInUntil = shiftEndMin;

        if (currentMinutes < checkInFrom) {
            return { allowed: false, message: 'You are on leave for the first half and cannot check in/out during this time.' };
        }
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
    const tz = company?.settings?.business?.timezone || company?.timezone;
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

const getShiftTimings = (company, staff = null) => {
    // Default shift timings
    let startTime = '09:30';
    let endTime = '18:30';
    let gracePeriodMinutes = 0;
    let halfDaySettings = null;

    // Check company settings for shifts
    if (company && company.settings && company.settings.attendance && company.settings.attendance.shifts) {
        const shifts = company.settings.attendance.shifts;
        if (Array.isArray(shifts) && shifts.length > 0) {
            // Use first shift as default (or match staff's shiftName if provided)
            const shift = staff && staff.shiftName
                ? shifts.find(s => s.name === staff.shiftName) || shifts[0]
                : shifts[0];
            
            if (shift.startTime) startTime = shift.startTime;
            if (shift.endTime) endTime = shift.endTime;
            
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
        }
    }

    return { startTime, endTime, gracePeriodMinutes, halfDaySettings };
};

/**
 * Calculate work hours from shift timings
 * @param {String} startTime - Shift start time in HH:mm format
 * @param {String} endTime - Shift end time in HH:mm format
 * @returns {Number} - Work hours (in hours, e.g., 8.5 for 8 hours 30 minutes)
 */
const calculateWorkHoursFromShift = (startTime, endTime) => {
    try {
        const [startHours, startMins] = startTime.split(':').map(Number);
        const [endHours, endMins] = endTime.split(':').map(Number);
        
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
        const { startTime, endTime } = getShiftTimings(company, staff);
        const workHours = calculateWorkHoursFromShift(startTime, endTime);

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

            // Create punch in/out times based on shift timings
            const [startHours, startMins] = startTime.split(':').map(Number);
            const [endHours, endMins] = endTime.split(':').map(Number);
            
            const punchIn = new Date(startOfDay.getTime() + (startHours * 60 + startMins) * 60 * 1000);
            const punchOut = new Date(startOfDay.getTime() + (endHours * 60 + endMins) * 60 * 1000);

            let attendance = await Attendance.findOne({
                employeeId: employeeId,
                date: { $gte: startOfDay, $lte: endOfDay }
            });

            const isHalfDayLeave = leave.leaveType === 'Half Day';
            const halfDaySessionValue = isHalfDayLeave
                ? (leave.halfDaySession || leave.halfDayType || (leave.session === '1' ? 'First Half Day' : leave.session === '2' ? 'Second Half Day' : null))
                : null;
            const sessionRemarks = isHalfDayLeave
                ? (halfDaySessionValue === 'First Half Day'
                    ? 'Half day leave approved - First Half Day. Employee should punch in for verification.' 
                    : 'Half day leave approved - Second Half Day. Employee should punch in for verification.')
                : 'On Leave (approved)';

            if (attendance) {
                // Update existing attendance record
                attendance.status = isHalfDayLeave ? 'Half Day' : 'On Leave';
                attendance.leaveType = leave.leaveType;
                attendance.session = isHalfDayLeave ? (leave.session || null) : null;
                attendance.halfDaySession = halfDaySessionValue;
                attendance.remarks = (attendance.remarks || '').trim() ? (attendance.remarks + ' ' + sessionRemarks) : sessionRemarks;
                // Full-day leave: no check-in/check-out
                if (!isHalfDayLeave) {
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
                    status: isHalfDayLeave ? 'Half Day' : 'On Leave',
                    leaveType: leave.leaveType,
                    session: isHalfDayLeave ? (leave.session || null) : null,
                    halfDaySession: halfDaySessionValue,
                    approvedBy: leave.approvedBy,
                    approvedAt: leave.approvedAt || new Date(),
                    businessId: businessId,
                    workHours: isHalfDayLeave ? undefined : 0,
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
const calculateHalfDayLateFine = (punchInTime, attendanceDate, session, gracePeriodMinutes, dailySalary, shiftHours, shiftStartTime, shiftEndTime, fineConfig = null, halfDaySettings = null) => {
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
    const fineAmount = calculateFineAmount(lateMinutes, 'lateArrival', fineConfig, dailySalary, shiftHours);
    return { lateMinutes, fineAmount };
};

/**
 * Calculate early logout fine for Half Day session. Uses effective fine config (formula + fineRules).
 * @param {Object} [fineConfig] - from getEffectiveFineConfig(company)
 * @returns {{ earlyMinutes: number, fineAmount: number }}
 */
const calculateHalfDayEarlyFine = (punchOutTime, attendanceDate, session, dailySalary, shiftHours, shiftStartTime, shiftEndTime, fineConfig = null, halfDaySettings = null) => {
    const timings = getWorkingSessionTimings(session, shiftStartTime, shiftEndTime, halfDaySettings);
    if (!timings) return { earlyMinutes: 0, fineAmount: 0 };
    const [endHours, endMins] = timings.endTime.split(':').map(Number);
    const shiftEnd = new Date(attendanceDate);
    shiftEnd.setHours(endHours, endMins, 0, 0);
    if (punchOutTime >= shiftEnd) return { earlyMinutes: 0, fineAmount: 0 };
    const earlyMinutes = Math.max(0, Math.round((shiftEnd.getTime() - punchOutTime.getTime()) / (1000 * 60)));
    if (earlyMinutes <= 0) return { earlyMinutes, fineAmount: 0 };
    if (fineConfig && fineConfig.enabled === false) return { earlyMinutes, fineAmount: 0 };
    const fineAmount = calculateFineAmount(earlyMinutes, 'earlyExit', fineConfig, dailySalary, shiftHours);
    return { earlyMinutes, fineAmount };
};

module.exports = {
    markAttendanceForApprovedLeave,
    calculateAvailableLeaves,
    revertAttendanceForDeletedLeave,
    canCheckInWithHalfDayLeave,
    canCheckOutWithHalfDayLeave,
    getHalfDaySessionMessage,
    isCurrentlyInLeaveSession,
    getLeaveMessageForUI,
    getWorkingSessionTimings,
    calculateHalfDayLateFine,
    calculateHalfDayEarlyFine,
    getShiftTimings,
    calculateWorkHoursFromShift,
    getBusinessTimezone,
    getShiftBoundaryAsUTCDate
};
