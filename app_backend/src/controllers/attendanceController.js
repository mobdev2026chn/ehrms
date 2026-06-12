const Attendance = require('../models/Attendance');
const AttendanceLog = require('../models/AttendanceLog');
const PermissionRequest = require('../models/PermissionRequest');
const Staff = require('../models/Staff');
const User = require('../models/User'); // Import if needed
require('../models/AttendanceTemplate'); // ensure model registered for populate/lean paths via utils
const WeeklyHolidayTemplate = require('../models/WeeklyHolidayTemplate');
const Tracking = require('../models/Tracking');
const { reverseGeocode } = require('../services/geocodingService');
const { logTrackingWrite } = require('../utils/trackingLogger');
const { calculateAttendanceStats } = require('./payrollController');
const { getWeekOffConfigForStaff, isOddEvenSaturdayWeeklyOff } = require('../utils/weekOffHelper');
const { getHolidayTemplateForStaff, getHolidayForDate, getHolidaysForMonth } = require('../utils/holidayTemplateHelper');
const { loadAttendanceTemplateForStaff } = require('../utils/resolveStaffAttendanceTemplate');
const digitalOceanService = require('../services/digitalOceanService');
const {
    getBranchGeofenceTargets,
    isLatLngInsideBranchGeofence,
} = require('../utils/branchGeofence');
const { closeStaleOpenBreaksForStaff } = require('./breakController');

/** Build a single address string from address, area, city, pincode. */
function buildAddressString(address, area, city, pincode) {
  const parts = [address, area, city, pincode].filter(Boolean);
  return parts.length ? parts.join(', ') : '';
}

/** Client clocks may skew; all stored instants stay authoritative UTC on the server. */
const MAX_PUNCH_CLOCK_SKEW_MS = 5 * 60 * 1000;

/**
 * Resolve the punch instant the client captured at button-click time. The app sends the
 * tap timestamp so location/selfie/network latency does not push the saved time forward.
 * Falls back to the server `now` when the client value is missing, unparseable, in the
 * future beyond the allowed skew, or more than 48h in the past.
 */
function resolveClientPunchTime(clientInput, serverNow = new Date()) {
  const nowMs = serverNow.getTime();
  if (clientInput == null || clientInput === '') {
    return serverNow;
  }
  const ms = new Date(clientInput).getTime();
  if (!Number.isFinite(ms)) {
    return serverNow;
  }
  if (ms > nowMs + MAX_PUNCH_CLOCK_SKEW_MS) {
    console.warn('[Attendance] punch: client time in future; using server now');
    return serverNow;
  }
  if (ms < nowMs - 48 * 60 * 60 * 1000) {
    console.warn('[Attendance] punch: client time too far in past; using server now');
    return serverNow;
  }
  return new Date(ms);
}

/** Insert attendance punch tracking into trackings collection. */
async function insertAttendanceTracking(
    staffId,
    staffName,
    lat,
    lng,
    presenceStatus,
    trackingStatus,
    movementType,
    address,
    area,
    city,
    pincode
) {
    try {
        let resolvedPresenceStatus = presenceStatus;
        try {
            const staffDoc = await Staff.findById(staffId)
                .select('branchId')
                .populate('branchId', 'geofence branchName latitude longitude radius')
                .lean();
            const branch = staffDoc?.branchId;
            if (branch && typeof branch === 'object') {
                resolvedPresenceStatus = isLatLngInsideBranchGeofence(
                    branch,
                    Number(lat),
                    Number(lng),
                    0,
                )
                    ? 'in_office'
                    : 'out_of_office';
            } else if (!resolvedPresenceStatus) {
                resolvedPresenceStatus = 'out_of_office';
            }
        } catch (_) {
            if (!resolvedPresenceStatus) {
                resolvedPresenceStatus = 'out_of_office';
            }
        }

        let fullAddress = address || '';
        if (!fullAddress && (area || city || pincode)) {
            const parts = [pincode, area, city, address].filter(Boolean);
            fullAddress = parts.join(', ');
        }
        if (!fullAddress) {
            try {
                const geo = await reverseGeocode(Number(lat), Number(lng));
                fullAddress = geo?.address || geo?.fullAddress || '';
                if (!address && geo) address = geo.address;
                if (!pincode && geo?.pincode) pincode = geo.pincode;
            } catch (e) {
                console.log('[AttendanceTracking] Geocode failed:', e.message);
            }
        }
        const now = new Date();
        const doc = {
            staffId,
            staffName: staffName || undefined,
            latitude: Number(lat),
            longitude: Number(lng),
            timestamp: now,
            time: now,
            status: trackingStatus,
            presenceStatus: resolvedPresenceStatus,
            movementType: movementType || undefined,
            address: address || fullAddress || undefined,
            fullAddress: fullAddress || address || undefined,
            area: area || undefined,
            city: city || undefined,
            pincode: pincode || undefined,
        };
        const created = await Tracking.create(doc);
        logTrackingWrite('attendance_punch', {
            _id: String(created._id),
            staffId: String(staffId),
            staffName: staffName || undefined,
            latitude: doc.latitude,
            longitude: doc.longitude,
            presenceStatus: resolvedPresenceStatus,
        });
    } catch (e) {
        console.error('[AttendanceTracking] Insert failed:', e.message);
    }
}

// Helper to calculate distance
function getDistanceFromLatLonInKm(lat1, lon1, lat2, lon2) {
    var R = 6371; // Radius of the earth in km
    var dLat = deg2rad(lat2 - lat1);
    var dLon = deg2rad(lon2 - lon1);
    var a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2)
        ;
    var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    var d = R * c; // Distance in km
    return d;
}

function deg2rad(deg) {
    return deg * (Math.PI / 180);
}

/** Company shift document: open = flexible clock-in/out, required workHours per day. */
function isOpenShiftTiming(shiftTiming) {
    const type = String(shiftTiming?.shiftType || '').toLowerCase();
    return type === 'open' || type === 'open shift';
}

/**
 * App may send forceAppFine with optional fields. Only treat as override when the client
 * actually sent a number (or numeric string). Skips null/undefined so server-calculated
 * checkout values are not wiped: Number(null) === 0 is finite in JS and would zero
 * earlyMinutes/fineAmount for open-shift checkout when Flutter omits those keys as null.
 */
function hasExplicitAppFineNumeric(value) {
    if (value === null || value === undefined) return false;
    if (typeof value === 'string' && value.trim() === '') return false;
    return Number.isFinite(Number(value));
}

/** Multer / form fields send booleans as strings; JSON body may send real booleans. */
function isTruthyRequestBool(value) {
    return value === true || value === 'true' || String(value).toLowerCase() === 'true';
}

function staffShiftAssignmentKey(staff) {
    if (!staff) return '';
    const rawSid = staff.shiftId;
    let sid = '';
    if (rawSid != null && rawSid !== '') {
        sid =
            typeof rawSid === 'object' && rawSid._id != null
                ? String(rawSid._id).trim()
                : String(rawSid).trim();
    }
    const sn = (staff.shiftName || '').toString().trim();
    return sid || sn;
}

function isLikelyMongoObjectIdHex(v) {
    return /^[a-fA-F0-9]{24}$/i.test(String(v).trim());
}

function getAppliedShiftIdFromShiftTiming(shiftTiming) {
    const raw = shiftTiming?.effectiveShiftId;
    if (raw == null) return null;
    const shiftId = String(raw).trim();
    return isLikelyMongoObjectIdHex(shiftId) ? shiftId : null;
}

// True when company has no shifts config (use template) or staff has a matching shift assigned.
function isShiftAssignedForStaff(company, staff, attendanceTemplateDoc) {
    const { staffShiftKeyFromStaff } = require('../utils/leaveAttendanceHelper');
    const shifts = company?.settings?.attendance?.shifts;
    if (!shifts || !Array.isArray(shifts) || shifts.length === 0) return true;
    const key = staffShiftKeyFromStaff(staff, attendanceTemplateDoc);
    if (!key) {
        const raw = staffShiftAssignmentKey(staff);
        if (!raw) return false;
        return true;
    }
    return shifts.some((s) => {
        if (!s) return false;
        if (isLikelyMongoObjectIdHex(key)) {
            return s._id != null && String(s._id).toLowerCase() === key.toLowerCase();
        }
        if (s._id != null && String(s._id) === key) return true;
        return (s.name || '').toString().trim().toLowerCase() === key.toLowerCase();
    });
}

// Coerce a value that semantically means "true" into a real boolean.
// The attendance template can be persisted by a separate admin service that
// stores these flags as strings ("true"/"1"/"yes"/"on") or numbers (1) rather
// than a JS boolean. A strict `=== true` check silently turns those into
// `false`, which blocks punch-in on holidays/weekly-off even though the admin
// toggle is ON. Treat any recognised truthy representation as true.
function coerceTrue(value) {
    if (value === true) return true;
    if (typeof value === 'number') return value === 1;
    if (typeof value === 'string') {
        const v = value.trim().toLowerCase();
        return v === 'true' || v === '1' || v === 'yes' || v === 'on';
    }
    return false;
}

function normalizeTemplate(templateDoc) {
    if (!templateDoc) return {};
    let t = templateDoc.toObject ? templateDoc.toObject() : templateDoc;
    // Flatten settings if nested
    if (t.settings) {
        t = { ...t, ...t.settings };
    }
    return {
        ...t,
        requireSelfie: t.requireSelfie !== false,
        requireGeolocation: t.requireGeolocation !== false,
        allowAttendanceOnHolidays: coerceTrue(t.allowAttendanceOnHolidays),
        allowAttendanceOnWeeklyOff: coerceTrue(t.allowAttendanceOnWeeklyOff),
        // Respect template settings - default to true if not specified
        allowLateEntry: t.allowLateEntry !== false && t.lateEntryAllowed !== false,
        allowEarlyExit: t.allowEarlyExit !== false && t.earlyExitAllowed !== false,
        allowOvertime: t.allowOvertime !== false && t.overtimeAllowed !== false,
        // Explicitly include shiftType and openWorkHours if they exist in the original templateDoc
        shiftType: t.shiftType || 'standard',
        openWorkHours: t.openWorkHours || null,
        // For open shifts, explicitly set start/end times to null
        shiftStartTime: ((t.shiftType || '').toLowerCase() === 'open' || (t.shiftType || '').toLowerCase() === 'open shift') ? null : (t.shiftStartTime || '09:30'),
        shiftEndTime: ((t.shiftType || '').toLowerCase() === 'open' || (t.shiftType || '').toLowerCase() === 'open shift') ? null : (t.shiftEndTime || '18:30'),
    };
}

/** Upload attendance selfie to Digital Ocean S3. Returns public URL or null. [imageInput] may be a Buffer or a base64 / data-URL string. */
async function uploadAttendanceSelfie(imageInput, req, companyId, employeeName, type) {
    try {
        if (!imageInput) return null;
        let buffer;
        if (Buffer.isBuffer(imageInput)) {
            buffer = imageInput;
        } else if (typeof imageInput === 'string') {
            let base64Data = imageInput;
            if (imageInput.startsWith('data:image')) {
                base64Data = imageInput.replace(/^data:image\/\w+;base64,/, '');
            } else if (!imageInput.startsWith('/9j/') && !imageInput.startsWith('iVBOR')) {
                base64Data = imageInput;
            }
            buffer = Buffer.from(base64Data, 'base64');
        } else {
            return null;
        }
        if (!buffer || buffer.length === 0) return null;
        const result = await digitalOceanService.uploadAttendanceImage(
            buffer,
            req,
            companyId,
            employeeName || 'unknown',
            type || 'punch-in'
        );
        return result.success ? result.url : null;
    } catch (error) {
        console.error('[Attendance] Selfie upload error:', error.message);
        return null;
    }
}

/**
 * Upload punch selfie after HTTP response so the client is not blocked on Spaces latency.
 * Updates attendances.[fieldKey] when upload succeeds (punchInSelfie | punchOutSelfie).
 */
function scheduleDeferredAttendanceSelfieUpload(attendanceId, imageInput, req, companyId, employeeName, fieldKey) {
    const id = attendanceId;
    const punchType = fieldKey === 'punchOutSelfie' ? 'punch-out' : 'punch-in';
    setImmediate(() => {
        void (async () => {
            const t0 = Date.now();
            try {
                const url = await uploadAttendanceSelfie(imageInput, req, companyId, employeeName, punchType);
                if (url) {
                    await Attendance.findByIdAndUpdate(id, { [fieldKey]: url });
                }
                console.log('[Attendance] deferred selfie upload', {
                    attendanceId: String(id),
                    fieldKey,
                    ms: Date.now() - t0,
                    ok: Boolean(url),
                });
            } catch (e) {
                console.error('[Attendance] deferred selfie upload failed', String(id), fieldKey, e?.message);
            }
        })();
    });
}

// Helper function to calculate salary structure
function calculateSalaryStructure(salary) {
    if (!salary) return null;
    
    const basicSalary = salary.basicSalary || 0;
    const dearnessAllowance = salary.dearnessAllowance || (basicSalary > 0 ? basicSalary * 0.5 : 0);
    const houseRentAllowance = salary.houseRentAllowance || (basicSalary > 0 ? basicSalary * 0.2 : 0);
    const specialAllowance = salary.specialAllowance || 0;
    const employerPFRate = salary.employerPFRate || 0;
    const employerESIRate = salary.employerESIRate || 0;
    const employeePFRate = salary.employeePFRate || 0;
    const employeeESIRate = salary.employeeESIRate || 0;

    const grossFixedSalary = basicSalary + dearnessAllowance + houseRentAllowance + specialAllowance;
    const employerPF = employerPFRate > 0 ? (basicSalary * employerPFRate / 100) : 0;
    const employerESI = employerESIRate > 0 ? (grossFixedSalary * employerESIRate / 100) : 0;
    const grossSalary = grossFixedSalary + employerPF + employerESI;
    
    const employeePF = employeePFRate > 0 ? (basicSalary * employeePFRate / 100) : 0;
    const employeeESI = employeeESIRate > 0 ? (grossSalary * employeeESIRate / 100) : 0;
    const netMonthlySalary = grossSalary - employeePF - employeeESI;

    return {
        monthly: {
            basicSalary,
            grossSalary,
            netMonthlySalary
        }
    };
}

// Helper function to calculate working days for a month
function calculateWorkingDays(year, month, holidays, weeklyOffPattern, weeklyHolidays) {
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    let workingDays = 0;
    
    for (let d = 1; d <= daysInMonth; d++) {
        const date = new Date(year, month, d);
        const dayOfWeek = date.getDay();
        let isWeekOff = false;
        
        if (weeklyOffPattern === 'oddEvenSaturday') {
            if (dayOfWeek === 0) isWeekOff = true;
            else if (isOddEvenSaturdayWeeklyOff(year, month, d, 'local')) isWeekOff = true;
        } else {
            isWeekOff = weeklyHolidays.some(h => h.day === dayOfWeek);
        }
        
        if (!isWeekOff) {
            const isHoliday = holidays.some(h => {
                const hd = new Date(h.date);
                return hd.getDate() === d && hd.getMonth() === month && hd.getFullYear() === year;
            });
            if (!isHoliday) {
                workingDays++;
            }
        }
    }
    
    return workingDays || 30; // Fallback to 30 if calculation fails
}

// Helper function to calculate shift hours
function calculateShiftHours(startTime, endTime) {
    if (startTime == null || endTime == null) return 9;
    const ss = String(startTime).trim();
    const ee = String(endTime).trim();
    if (!ss || !ee) return 9;
    const [startHours, startMins] = ss.split(':').map(Number);
    const [endHours, endMins] = ee.split(':').map(Number);
    
    const startTotalMinutes = startHours * 60 + startMins;
    const endTotalMinutes = endHours * 60 + endMins;
    
    let diffMinutes = endTotalMinutes - startTotalMinutes;
    if (diffMinutes < 0) {
        diffMinutes += 24 * 60; // Handle overnight shifts
    }
    
    return diffMinutes / 60; // Convert to hours
}

// Helper: fine config from company.settings.payroll.fineCalculation only (not attendance)
const { getEffectiveFineConfig, calculateFineAmount, calculateOvertimePayAmount } = require('../utils/fineCalculationHelper');

// Helper function to calculate fine for late arrival.
// Uses formula: Fine = (Daily Salary ÷ Shift Hours) × (Late Minutes ÷ 60). Applies fineRules when present.
// When businessTimezone is provided, shift boundaries are built in that TZ (fixes production UTC server showing lateMinutes=0).
function calculateLateFine(punchInTime, attendanceDate, shiftStartTime, gracePeriodMinutes, dailySalary, shiftHours, fineConfig = null, businessTimezone = null, isOpenShiftDay = false, dailyGrossForRules = null) {
    console.log('[Fine] calculateLateFine called: isOpenShiftDay=', isOpenShiftDay, 'punchInTime=', punchInTime?.toISOString?.());
    if (isOpenShiftDay) {
        console.log('[Fine] calculateLateFine: Skipping late fine for open shift.');
        return { lateMinutes: 0, fineAmount: 0 };
    }
    let shiftStart;
    if (businessTimezone) {
        const { getShiftBoundaryAsUTCDate } = require('../utils/leaveAttendanceHelper');
        shiftStart = getShiftBoundaryAsUTCDate(attendanceDate, shiftStartTime, businessTimezone);
    } else {
        const [shiftHours_val, shiftMins] = shiftStartTime.split(':').map(Number);
        shiftStart = new Date(attendanceDate);
        shiftStart.setHours(shiftHours_val, shiftMins, 0, 0);
    }
    const graceTimeEnd = new Date(shiftStart.getTime() + gracePeriodMinutes * 60 * 1000);
    console.log('[Fine] Late check: punchInTime=', punchInTime?.toISOString?.(), 'shiftStart(UTC)=', shiftStart?.toISOString?.(), 'graceTimeEnd(UTC)=', graceTimeEnd?.toISOString?.(), 'graceMinutes=', gracePeriodMinutes);
    if (punchInTime <= graceTimeEnd) {
        console.log('[Fine] => within grace or before shift, lateMinutes=0');
        return { lateMinutes: 0, fineAmount: 0 };
    }
    const lateMinutes = Math.max(0, Math.round((punchInTime.getTime() - shiftStart.getTime()) / (1000 * 60)));
    if (lateMinutes <= 0) return { lateMinutes, fineAmount: 0 };
    if (fineConfig && fineConfig.enabled === false) return { lateMinutes, fineAmount: 0 };
    const fineAmount = calculateFineAmount(lateMinutes, 'lateArrival', fineConfig, dailySalary, shiftHours, dailyGrossForRules);
    return { lateMinutes, fineAmount };
}

// Helper function to calculate fine for early exit.
// Uses formula: Fine = (Daily Salary ÷ Shift Hours) × (Early Minutes ÷ 60). Applies fineRules when present.
// When businessTimezone is provided, shift end is built in that TZ (consistent with late calculation).
function calculateEarlyFine(punchOutTime, attendanceDate, shiftEndTime, dailySalary, shiftHours, fineConfig = null, businessTimezone = null, dailyGrossForRules = null, shiftStartTime = null) {
    let shiftEnd;
    if (businessTimezone) {
        const { getShiftBoundaryAsUTCDate } = require('../utils/leaveAttendanceHelper');
        shiftEnd = getShiftBoundaryAsUTCDate(attendanceDate, shiftEndTime, businessTimezone);
    } else {
        const [endHours, endMins] = shiftEndTime.split(':').map(Number);
        shiftEnd = new Date(attendanceDate);
        shiftEnd.setHours(endHours, endMins, 0, 0);
    }
    // Overnight shift (PM start / AM end, e.g. 21:00->06:00): the AM end-time is
    // built on the same calendar day as the PM start, landing *before* the shift
    // begins. Roll it forward one day so early-checkout minutes are correct.
    if (shiftStartTime) {
        const [sH, sM] = String(shiftStartTime).split(':').map(Number);
        const [eH, eM] = String(shiftEndTime).split(':').map(Number);
        const startMin = (sH || 0) * 60 + (sM || 0);
        const endMin = (eH || 0) * 60 + (eM || 0);
        if (endMin <= startMin) {
            shiftEnd = new Date(shiftEnd.getTime() + 24 * 60 * 60 * 1000);
        }
    }
    console.log('[Fine] Early check: punchOutTime=', punchOutTime?.toISOString?.(), 'shiftEnd(UTC)=', shiftEnd?.toISOString?.());
    if (punchOutTime >= shiftEnd) return { earlyMinutes: 0, fineAmount: 0 };
    const earlyMinutes = Math.max(0, Math.round((shiftEnd.getTime() - punchOutTime.getTime()) / (1000 * 60)));
    if (earlyMinutes <= 0) return { earlyMinutes, fineAmount: 0 };
    if (fineConfig && fineConfig.enabled === false) return { earlyMinutes, fineAmount: 0 };
    const fineAmount = calculateFineAmount(earlyMinutes, 'earlyExit', fineConfig, dailySalary, shiftHours, dailyGrossForRules);
    return { earlyMinutes, fineAmount };
}

function getMonthBoundsForDate(date) {
    const d = new Date(date);
    const start = new Date(d.getFullYear(), d.getMonth(), 1, 0, 0, 0, 0);
    const end = new Date(d.getFullYear(), d.getMonth() + 1, 1, 0, 0, 0, 0);
    return { start, end };
}

function toDateKeyInTimezone(date, timeZone) {
    if (!date) return '';
    const d = new Date(date);
    if (Number.isNaN(d.getTime())) return '';
    try {
        const parts = new Intl.DateTimeFormat('en-US', {
            timeZone: timeZone || 'UTC',
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        }).formatToParts(d);
        const year = parts.find((p) => p.type === 'year')?.value;
        const month = parts.find((p) => p.type === 'month')?.value;
        const day = parts.find((p) => p.type === 'day')?.value;
        if (year && month && day) return `${year}-${month}-${day}`;
        return d.toISOString().slice(0, 10);
    } catch (_) {
        // Fallback to UTC key when timezone formatter is unavailable.
        return d.toISOString().slice(0, 10);
    }
}

async function getApprovedPermissionForDate(employeeId, businessId, attendanceDate, businessTimezone = 'UTC') {
    if (!employeeId || !attendanceDate) return null;
    const dayStartUtc = new Date(attendanceDate);
    dayStartUtc.setUTCHours(0, 0, 0, 0);
    const rangeStart = new Date(dayStartUtc.getTime() - (24 * 60 * 60 * 1000));
    const rangeEnd = new Date(dayStartUtc.getTime() + (2 * 24 * 60 * 60 * 1000));
    const query = {
        employeeId,
        date: { $gte: rangeStart, $lt: rangeEnd },
        status: 'Approved'
    };
    if (businessId) query.businessId = businessId;
    let rows = await PermissionRequest.find(query)
        .select('date type requestedMinutes')
        .lean();
    // Backward compatibility: some old rows may have inconsistent business linkage.
    if ((!rows || rows.length === 0) && businessId) {
        const relaxedQuery = {
            employeeId,
            date: { $gte: rangeStart, $lt: rangeEnd },
            status: 'Approved'
        };
        rows = await PermissionRequest.find(relaxedQuery)
            .select('date type requestedMinutes businessId')
            .lean();
    }
    const attendanceKey = toDateKeyInTimezone(attendanceDate, businessTimezone);
    const matched = (Array.isArray(rows) ? rows : []).filter((row) => {
        const rowKey = toDateKeyInTimezone(row?.date, businessTimezone);
        return rowKey === attendanceKey;
    });
    console.log('[Permission][Lookup]', {
        employeeId: employeeId?.toString?.() || String(employeeId || ''),
        businessId: businessId?.toString?.() || String(businessId || ''),
        attendanceDate: new Date(attendanceDate).toISOString(),
        businessTimezone,
        attendanceKey,
        fetchedRows: Array.isArray(rows) ? rows.length : 0,
        matchedRows: matched.length
    });
    return matched;
}

async function getConsumedPermissionMinutesForMonth({
    employeeId,
    attendanceDate,
    excludeAttendanceId = null
}) {
    if (!employeeId || !attendanceDate) return 0;
    const monthBounds = getMonthBoundsForDate(attendanceDate);
    const query = {
        employeeId,
        date: { $gte: monthBounds.start, $lt: monthBounds.end }
    };
    if (excludeAttendanceId) {
        query._id = { $ne: excludeAttendanceId };
    }
    const agg = await Attendance.aggregate([
        { $match: query },
        {
            $group: {
                _id: null,
                total: { $sum: { $ifNull: ['$permissionConsumedMinutes', 0] } }
            }
        }
    ]);
    return Math.max(0, Number(agg?.[0]?.total || 0));
}

async function resolveMonthlyPermissionQuotaMinutes(businessId) {
    if (!businessId) return 0;
    try {
        const Company = require('../models/Company');
        const company = await Company.findById(businessId)
            .select('settings.attendance.shifts.permissionPolicy.monthlyQuotaMinutes')
            .lean();
        const shifts = company?.settings?.attendance?.shifts || [];
        let maxQuota = 0;
        for (const shift of shifts) {
            const value = Math.max(
                0,
                Number(shift?.permissionPolicy?.monthlyQuotaMinutes || 0)
            );
            if (value > maxQuota) maxQuota = value;
        }
        return maxQuota;
    } catch (err) {
        console.warn(
            '[Permission][Quota Resolve] failed:',
            err?.message || err
        );
        return 0;
    }
}

async function applyPermissionQuotaAdjustment({
    employeeId,
    businessId,
    attendanceDate,
    attendanceId = null,
    businessTimezone = 'UTC',
    isOpenShiftDay,
    isCheckout = false,
    shiftPermissionPolicy,
    lateMinutes,
    earlyMinutes
}) {
    const attendanceIso = new Date(attendanceDate).toISOString();
    const attendanceIdStr = attendanceId ? attendanceId?.toString?.() || String(attendanceId) : null;
    const zero = {
        adjustedLateMinutes: Math.max(0, Number(lateMinutes) || 0),
        adjustedEarlyMinutes: Math.max(0, Number(earlyMinutes) || 0),
        permissionApprovedMinutes: 0,
        permissionConsumedMinutes: 0,
        permissionRemainingMinutes: 0,
        permissionLateMinutes: 0,
        permissionEarlyMinutes: 0
    };
    const policy = shiftPermissionPolicy || {};
    // A policy object present on the shift means Permission is configured. When it is configured
    // but explicitly disabled, the feature still works but fines are NOT waived (deducted in full).
    const isConfigured = !!(shiftPermissionPolicy && typeof shiftPermissionPolicy === 'object');
    const policyExplicitlyDisabled = isConfigured && shiftPermissionPolicy.enabled === false;
    let enabled = policy.enabled === true;
    let monthlyQuotaMinutes = Math.max(0, Number(policy.monthlyQuotaMinutes || 0));
    if (monthlyQuotaMinutes <= 0) {
        const resolvedMonthlyQuota = await resolveMonthlyPermissionQuotaMinutes(
            businessId
        );
        if (resolvedMonthlyQuota > 0) {
            monthlyQuotaMinutes = resolvedMonthlyQuota;
            console.log('[Permission][Quota Resolve]', {
                employeeId: employeeId?.toString?.() || String(employeeId || ''),
                businessId: businessId?.toString?.() || String(businessId || ''),
                attendanceDate: attendanceIso,
                resolvedMonthlyQuota
            });
        }
    }
    const applyTo = ['lateArrival', 'earlyExit', 'both'].includes(String(policy.applyTo || 'both'))
        ? String(policy.applyTo || 'both')
        : 'both';
    const approvedPermissions = await getApprovedPermissionForDate(
        employeeId,
        businessId,
        attendanceDate,
        businessTimezone
    );
    if (!Array.isArray(approvedPermissions) || approvedPermissions.length === 0) {
        console.log('[Permission][Skip]', {
            reason: 'no_approved_requests_for_day',
            employeeId: employeeId?.toString?.() || String(employeeId || ''),
            businessId: businessId?.toString?.() || String(businessId || ''),
            attendanceDate: new Date(attendanceDate).toISOString(),
            monthlyQuotaMinutes
        });
        return {
            ...zero,
            permissionRemainingMinutes: monthlyQuotaMinutes
        };
    }

    let approvedLateOnly = 0;
    let approvedEarlyOnly = 0;
    let approvedBothShared = 0;
    for (const req of approvedPermissions) {
        const mins = Math.max(0, Math.floor(Number(req?.requestedMinutes) || 0));
        if (mins <= 0) continue;
        const t = String(req?.type || 'both').trim();
        if (t === 'lateArrival') approvedLateOnly += mins;
        else if (t === 'earlyExit') approvedEarlyOnly += mins;
        else approvedBothShared += mins;
    }
    const approvedMinutesForDay = Math.max(
        0,
        approvedLateOnly + approvedEarlyOnly + approvedBothShared
    );
    if ((!enabled || monthlyQuotaMinutes <= 0) && approvedMinutesForDay > 0 && !policyExplicitlyDisabled) {
        // Fallback path for records where policy settings are missing/zero (legacy/unconfigured)
        // but approved permission exists for the day. Keeps permission usage fields consistent
        // with approved request minutes. Skipped when the shift explicitly disabled Permission —
        // there the fine must be deducted in full (no waiver).
        enabled = true;
        monthlyQuotaMinutes = Math.max(monthlyQuotaMinutes, approvedMinutesForDay);
        console.log('[Permission][Fallback]', {
            reason: !policy.enabled ? 'policy_disabled' : 'monthly_quota_zero',
            employeeId: employeeId?.toString?.() || String(employeeId || ''),
            businessId: businessId?.toString?.() || String(businessId || ''),
            attendanceDate: new Date(attendanceDate).toISOString(),
            approvedMinutesForDay,
            effectiveMonthlyQuotaMinutes: monthlyQuotaMinutes
        });
    }
    if (!enabled || monthlyQuotaMinutes <= 0) {
        console.log('[Permission][Skip]', {
            reason: !enabled ? 'policy_disabled' : 'monthly_quota_zero',
            employeeId: employeeId?.toString?.() || String(employeeId || ''),
            businessId: businessId?.toString?.() || String(businessId || ''),
            attendanceDate: new Date(attendanceDate).toISOString(),
            policy
        });
        return {
            ...zero,
            permissionApprovedMinutes: approvedMinutesForDay,
            permissionRemainingMinutes: monthlyQuotaMinutes
        };
    }

    // Shift-level policy gate.
    // IMPORTANT:
    // - `both` permission request remains a shared pool.
    // - policy decides which side can draw from this pool.
    let allowLateByPolicy = true;
    let allowEarlyByPolicy = true;
    if (applyTo === 'lateArrival') {
        allowEarlyByPolicy = false;
        approvedEarlyOnly = 0;
    } else if (applyTo === 'earlyExit') {
        allowLateByPolicy = false;
        approvedLateOnly = 0;
    }
    const approvedLateBeforeOpenRule = approvedLateOnly + approvedBothShared;
    const approvedEarlyBeforeOpenRule = approvedEarlyOnly + approvedBothShared;
    // Open shift: permission applies only at checkout and only to early-exit side.
    if (isOpenShiftDay && !isCheckout) {
        const consumedSoFarNoCurrent = await getConsumedPermissionMinutesForMonth({
            employeeId,
            attendanceDate,
            excludeAttendanceId: attendanceId
        });
        return {
            ...zero,
            // Visibility only on check-in; no consume until checkout.
            // Do not double-count shared `both` pool on visibility.
            permissionApprovedMinutes: Math.max(
                0,
                approvedLateOnly + approvedEarlyOnly + approvedBothShared
            ),
            permissionRemainingMinutes: Math.max(0, monthlyQuotaMinutes - consumedSoFarNoCurrent)
        };
    }
    if (isOpenShiftDay) {
        allowLateByPolicy = false;
        allowEarlyByPolicy = true;
        approvedLateOnly = 0;
    }
    const actualLate = Math.max(0, Number(lateMinutes) || 0);
    const actualEarly = Math.max(0, Number(earlyMinutes) || 0);
    // Daily allowance logic:
    // - lateArrival bucket is only for late
    // - earlyExit bucket is only for early
    // - both bucket is shared across late+early (late first, then early)
    const eligibleLateOnly = allowLateByPolicy ? Math.min(actualLate, approvedLateOnly) : 0;
    const lateNeedFromBoth = allowLateByPolicy ? Math.max(0, actualLate - eligibleLateOnly) : 0;
    const eligibleLateFromBoth = Math.min(lateNeedFromBoth, approvedBothShared);
    const remainingBothAfterLate = Math.max(0, approvedBothShared - eligibleLateFromBoth);
    const eligibleLate = eligibleLateOnly + eligibleLateFromBoth;
    const eligibleEarlyOnly = allowEarlyByPolicy ? Math.min(actualEarly, approvedEarlyOnly) : 0;
    const eligibleEarlyFromBoth = allowEarlyByPolicy
        ? Math.min(Math.max(0, actualEarly - eligibleEarlyOnly), remainingBothAfterLate)
        : 0;
    const eligibleEarly = eligibleEarlyOnly + eligibleEarlyFromBoth;
    const approvedEligibleForDay = eligibleLate + eligibleEarly;
    if (approvedEligibleForDay <= 0) {
        const consumedSoFarNoCurrent = await getConsumedPermissionMinutesForMonth({
            employeeId,
            attendanceDate,
            excludeAttendanceId: attendanceId
        });
        return {
            ...zero,
            permissionApprovedMinutes: approvedMinutesForDay,
            permissionRemainingMinutes: Math.max(0, monthlyQuotaMinutes - consumedSoFarNoCurrent)
        };
    }

    const consumedSoFarNoCurrent = await getConsumedPermissionMinutesForMonth({
        employeeId,
        attendanceDate,
        excludeAttendanceId: attendanceId
    });
    let remainingBefore = Math.max(0, monthlyQuotaMinutes - consumedSoFarNoCurrent);
    console.log('[Permission][Consumption Check]', {
        employeeId: employeeId?.toString?.() || String(employeeId || ''),
        businessId: businessId?.toString?.() || String(businessId || ''),
        attendanceDate: attendanceIso,
        attendanceId: attendanceIdStr,
        isCheckout: !!isCheckout,
        isOpenShiftDay: !!isOpenShiftDay,
        applyTo,
        approvedMinutesForDay,
        approvedEligibleForDay,
        eligibleLate,
        eligibleEarly,
        consumedSoFarNoCurrent,
        monthlyQuotaMinutes,
        remainingBefore
    });
    if (remainingBefore <= 0) {
        console.log('[Permission][Consumption Skip]', {
            reason: 'monthly_quota_exhausted',
            employeeId: employeeId?.toString?.() || String(employeeId || ''),
            attendanceDate: attendanceIso,
            attendanceId: attendanceIdStr,
            approvedMinutesForDay,
            consumedSoFarNoCurrent,
            monthlyQuotaMinutes
        });
        return {
            ...zero,
            permissionApprovedMinutes: approvedMinutesForDay
        };
    }

    // Consume from monthly remaining: late first, then early (deterministic).
    const consumeLate = Math.min(eligibleLate, remainingBefore);
    remainingBefore -= consumeLate;
    const consumeEarly = Math.min(eligibleEarly, remainingBefore);
    const consumed = consumeLate + consumeEarly;
    const remainingAfter = Math.max(0, monthlyQuotaMinutes - consumedSoFarNoCurrent - consumed);
    if (consumed > 0) {
        console.log('[Permission][Consumed]', {
            employeeId: employeeId?.toString?.() || String(employeeId || ''),
            businessId: businessId?.toString?.() || String(businessId || ''),
            attendanceDate: attendanceIso,
            attendanceId: attendanceIdStr,
            isCheckout: !!isCheckout,
            consumed,
            consumeLate,
            consumeEarly,
            approvedMinutesForDay,
            consumedSoFarNoCurrent,
            remainingAfter
        });
    } else {
        console.log('[Permission][Consumption Noop]', {
            employeeId: employeeId?.toString?.() || String(employeeId || ''),
            attendanceDate: attendanceIso,
            attendanceId: attendanceIdStr,
            isCheckout: !!isCheckout,
            eligibleLate,
            eligibleEarly,
            approvedMinutesForDay,
            consumedSoFarNoCurrent,
            remainingBefore
        });
    }

    return {
        adjustedLateMinutes: Math.max(0, actualLate - consumeLate),
        adjustedEarlyMinutes: Math.max(0, actualEarly - consumeEarly),
        permissionApprovedMinutes: approvedMinutesForDay,
        permissionConsumedMinutes: consumed,
        permissionRemainingMinutes: remainingAfter,
        permissionLateMinutes: consumeLate,
        permissionEarlyMinutes: consumeEarly
    };
}

// Helper function to calculate combined fine (late + early)
// @param {Object} leave - Optional approved leave (for Half Day session-aware calculation)
async function calculateCombinedFine(punchInTime, punchOutTime, attendanceDate, template, staff, company, leave = null, perDayOverride = null, context = null) {
    try {
        const checkInStr = punchInTime ? punchInTime.toISOString() : null;
        const checkOutStr = punchOutTime ? punchOutTime.toISOString() : null;
        console.log('[Fine] calculateCombinedFine called', { checkInTime: checkInStr, checkOutTime: checkOutStr, date: attendanceDate?.toISOString?.(), staffId: staff?._id?.toString() });
        const fineConfig = getEffectiveFineConfig(company || {});
        const isHalfDay = leave && String(leave.leaveType || '').trim().toLowerCase() === 'half day';
        // Use halfDaySession enum values ('First Half Day' / 'Second Half Day') - fallback to converting session numbers
        const session = isHalfDay ? (leave.halfDaySession || leave.halfDayType || (leave.session === '1' ? 'First Half Day' : leave.session === '2' ? 'Second Half Day' : null)) : null;
        const { getShiftTimings, getBusinessTimezone } = require('../utils/leaveAttendanceHelper');
        // Prefer the shift actually allocated for this day (stored on the attendance record as
        // appliedShiftId) so the fine always uses that day's shift — not the employee's current
        // assignment, which may have changed since. Null/unknown id falls back to live resolution.
        const forcedShiftId = context?.appliedShiftId || null;
        const dbShiftTimings = getShiftTimings(company, staff, attendanceDate, staff?.joiningDate, template, forcedShiftId);
        if (forcedShiftId) {
            console.log('[Fine] Shift anchored to appliedShiftId for the day:', String(forcedShiftId),
                '=> resolved shift:', dbShiftTimings?.effectiveShiftName, dbShiftTimings?.startTime, '-', dbShiftTimings?.endTime);
        }
        console.log('[Fine] calculateCombinedFine: dbShiftTimings=', JSON.stringify(dbShiftTimings));
        const businessTimezone = getBusinessTimezone(company);
        // Company embed may return null window; keep fine math stable with template then defaults.
        const dbShiftStartTime = dbShiftTimings.startTime || template?.shiftStartTime || '09:30';
        const dbShiftEndTime = dbShiftTimings.endTime || template?.shiftEndTime || '18:30';
        const dbGracePeriodMinutes = dbShiftTimings.gracePeriodMinutes ?? fineConfig?.graceTimeMinutes ?? 0;
        const shiftTypeLower = (dbShiftTimings.shiftType || 'standard').toString().toLowerCase();
        const isOpenShiftDay = (shiftTypeLower === 'open' || shiftTypeLower === 'open shift') && !isHalfDay;
        console.log('[Fine] calculateCombinedFine: isHalfDay=', isHalfDay, 'shiftTypeLower=', shiftTypeLower, 'isOpenShiftDay=', isOpenShiftDay);

        // Get shift timings (session-aware for Half Day, open shift uses required hours only, else fixed clock)
        let shiftStartTime, shiftEndTime, shiftHours;
        if (isOpenShiftDay) {
            shiftHours = Number(dbShiftTimings.openWorkHours || dbShiftTimings.workHours);
            if (!Number.isFinite(shiftHours) || shiftHours <= 0) shiftHours = 8;
            shiftStartTime = dbShiftStartTime;
            shiftEndTime = dbShiftEndTime;
        } else if (isHalfDay && (session === 'First Half Day' || session === 'Second Half Day')) {
            const { getWorkingSessionTimings } = require('../utils/leaveAttendanceHelper');
            // Calculate working session from DB shift times (use company halfDaySettings for custom midpoint)
            const sessionTimings = getWorkingSessionTimings(session, dbShiftStartTime, dbShiftEndTime, dbShiftTimings.halfDaySettings);
            if (sessionTimings) {
                shiftStartTime = sessionTimings.startTime;
                shiftEndTime = sessionTimings.endTime;
                shiftHours = calculateShiftHours(shiftStartTime, shiftEndTime); // 5 hours for half-day session
            } else {
                // Fallback to regular shift from DB
                shiftStartTime = dbShiftStartTime;
                shiftEndTime = dbShiftEndTime;
                shiftHours = calculateShiftHours(shiftStartTime, shiftEndTime);
            }
        } else {
            // Full-day: use DB shift times
            shiftStartTime = dbShiftStartTime;
            shiftEndTime = dbShiftEndTime;
            shiftHours = calculateShiftHours(shiftStartTime, shiftEndTime);
        }
        
        const gracePeriodMinutes = dbGracePeriodMinutes || template.gracePeriodMinutes || (fineConfig && fineConfig.graceTimeMinutes != null ? fineConfig.graceTimeMinutes : 0);
        
        // Per-day for fines: web parity — daily **net** for fixedPerHour derivation; daily **gross** for rule multipliers & shiftBased default.
        const salaryStructure = staff.salary ? calculateSalaryStructure(staff.salary) : null;
        const netMonthlySalary = salaryStructure?.monthly?.netMonthlySalary != null ? Number(salaryStructure.monthly.netMonthlySalary) : 0;
        const grossMonthlySalary = salaryStructure?.monthly?.grossSalary != null ? Number(salaryStructure.monthly.grossSalary) : 0;
        const attendanceYear = attendanceDate.getFullYear();
        const attendanceMonth1Based = attendanceDate.getMonth() + 1; // 1-12 for calculateAttendanceStats
        let dailyNet = null;
        let dailyGross = null;

        // For app punches, prefer per-day rates sent by the app (SharedPreferences preview parity).
        // This ensures fine + OT use the same per-day values the app used to compute/preview.
        const overrideNet = Number(perDayOverride?.appPerDayNetSalary);
        const overrideGross = Number(perDayOverride?.appPerdayGrossSalary);
        if (Number.isFinite(overrideNet) && overrideNet > 0) dailyNet = overrideNet;
        if (Number.isFinite(overrideGross) && overrideGross > 0) dailyGross = overrideGross;
        if ((dailyNet || dailyGross) && console && console.log) {
            console.log(
                '[Fine] perDaySource=appOverride',
                '| appPerDayNetSalary=',
                perDayOverride?.appPerDayNetSalary,
                'appPerdayGrossSalary=',
                perDayOverride?.appPerdayGrossSalary
            );
        }

        if (netMonthlySalary > 0 && staff._id) {
            try {
                const attendanceStats = await calculateAttendanceStats(staff._id, attendanceMonth1Based, attendanceYear);
                const thisMonthWorkingDays = attendanceStats.workingDaysFullMonth ?? attendanceStats.workingDays ?? 0;
                if (thisMonthWorkingDays > 0) {
                    if (dailyNet == null || dailyNet <= 0) dailyNet = netMonthlySalary / thisMonthWorkingDays;
                    if ((dailyGross == null || dailyGross <= 0) && grossMonthlySalary > 0) {
                        dailyGross = grossMonthlySalary / thisMonthWorkingDays;
                    }
                    if (!(Number.isFinite(overrideNet) && overrideNet > 0) && !(Number.isFinite(overrideGross) && overrideGross > 0)) {
                        console.log('[Fine] Daily (web-style): netMonthly=', netMonthlySalary, 'grossMonthly=', grossMonthlySalary, 'wd=', thisMonthWorkingDays, '=> dailyNet=', dailyNet, 'dailyGross=', dailyGross);
                    }
                }
            } catch (err) {
                console.error('[Fine] calculateAttendanceStats failed, using fallback working days:', err.message);
                const attendanceMonth0Based = attendanceDate.getMonth();
                let monthHolidays = [];
                if (staff.businessId) {
                    const holidayTemplate = await getHolidayTemplateForStaff(staff);
                    monthHolidays = getHolidaysForMonth(holidayTemplate, attendanceYear, attendanceMonth1Based);
                }
                const businessSettings = company?.settings?.business || {};
                const weeklyOffPattern = businessSettings.weeklyOffPattern || 'standard';
                const weeklyHolidays = businessSettings.weeklyHolidays || [{ day: 0, name: 'Sunday' }];
                const workingDays = calculateWorkingDays(attendanceYear, attendanceMonth0Based, monthHolidays, weeklyOffPattern, weeklyHolidays);
                if (workingDays > 0) {
                    if (dailyNet == null || dailyNet <= 0) dailyNet = netMonthlySalary / workingDays;
                    if ((dailyGross == null || dailyGross <= 0) && grossMonthlySalary > 0) dailyGross = grossMonthlySalary / workingDays;
                }
            }
        }
        
        // Half-day session: halve both net and gross (matches web half-day fine inputs).
        let effectiveDailyNet = (dailyNet && dailyNet > 0) ? dailyNet : 0;
        let effectiveDailyGross = (dailyGross && dailyGross > 0) ? dailyGross : effectiveDailyNet;
        if (isHalfDay && effectiveDailyNet > 0) {
            effectiveDailyNet = effectiveDailyNet / 2;
            effectiveDailyGross = effectiveDailyGross / 2;
            console.log('[Fine] Half-day: dailyNet/Gross halved for session => net=', effectiveDailyNet, 'gross=', effectiveDailyGross);
        }
        if (effectiveDailyNet <= 0) {
            console.log('[Fine] dailyNet missing or 0; late/early minutes will still be computed, fineAmount will be 0');
        }

        console.log('[Fine] Config: source=payroll.fineCalculation', 'enabled=', fineConfig?.enabled, 'calculationType=', fineConfig?.calculationType || 'shiftBased', 'dailyNet=', effectiveDailyNet, 'dailyGross=', effectiveDailyGross, 'shiftHours=', shiftHours, 'shiftStart=', shiftStartTime, 'shiftEnd=', shiftEndTime, 'businessTimezone=', businessTimezone);

        let lateFine;
        if (isOpenShiftDay) {
            lateFine = { lateMinutes: 0, fineAmount: 0 };
        } else if (isHalfDay && (session === 'First Half Day' || session === 'Second Half Day')) {
            const { calculateHalfDayLateFine } = require('../utils/leaveAttendanceHelper');
            const halfDayGrace = session === 'First Half Day' ? 0 : gracePeriodMinutes;
            lateFine = calculateHalfDayLateFine(punchInTime, attendanceDate, session, halfDayGrace, effectiveDailyNet, shiftHours, dbShiftStartTime, dbShiftEndTime, fineConfig, dbShiftTimings.halfDaySettings, effectiveDailyGross);
        } else {
            lateFine = calculateLateFine(punchInTime, attendanceDate, shiftStartTime, gracePeriodMinutes, effectiveDailyNet, shiftHours, fineConfig, businessTimezone, isOpenShiftDay, effectiveDailyGross);
        }
        let earlyFine = { earlyMinutes: 0, fineAmount: 0 };
        if (punchOutTime) {
            if (isOpenShiftDay && punchInTime) {
                const requiredMin = Math.round(shiftHours * 60);
                // Open shift shortfall must be based on actual worked minutes
                // between punch-in and punch-out, not fixed shift start.
                const workedMin = Math.max(
                    0,
                    Math.round((punchOutTime.getTime() - punchInTime.getTime()) / (1000 * 60))
                );
                const shortBy = Math.max(0, requiredMin - workedMin);
                earlyFine.earlyMinutes = shortBy;
                if (fineConfig && fineConfig.enabled && shortBy > 0 && effectiveDailyNet > 0) {
                    earlyFine.fineAmount = calculateFineAmount(shortBy, 'earlyExit', fineConfig, effectiveDailyNet, shiftHours, effectiveDailyGross);
                }
            } else if (isHalfDay && (session === 'First Half Day' || session === 'Second Half Day')) {
                const { calculateHalfDayEarlyFine } = require('../utils/leaveAttendanceHelper');
                earlyFine = calculateHalfDayEarlyFine(punchOutTime, attendanceDate, session, effectiveDailyNet, shiftHours, dbShiftStartTime, dbShiftEndTime, fineConfig, dbShiftTimings.halfDaySettings, effectiveDailyGross);
            } else {
                earlyFine = calculateEarlyFine(punchOutTime, attendanceDate, shiftEndTime, effectiveDailyNet, shiftHours, fineConfig, businessTimezone, effectiveDailyGross, shiftStartTime);
            }
        }

        let permissionLateUsed = 0;
        let permissionEarlyUsed = 0;
        let permissionApprovedMinutes = 0;
        let permissionConsumedMinutes = 0;
        let permissionRemainingMinutes = 0;
        try {
            const permissionAdj = await applyPermissionQuotaAdjustment({
                employeeId: staff?._id,
                businessId: staff?.businessId,
                attendanceDate,
                attendanceId: context?.attendanceId || null,
                isOpenShiftDay,
                isCheckout: !!punchOutTime,
                shiftPermissionPolicy: dbShiftTimings?.permissionPolicy || null,
                lateMinutes: lateFine.lateMinutes,
                earlyMinutes: earlyFine.earlyMinutes,
                businessTimezone
            });
            if (permissionAdj) {
                lateFine.lateMinutes = permissionAdj.adjustedLateMinutes;
                earlyFine.earlyMinutes = permissionAdj.adjustedEarlyMinutes;
                permissionLateUsed = permissionAdj.permissionLateMinutes;
                permissionEarlyUsed = permissionAdj.permissionEarlyMinutes;
                permissionApprovedMinutes = permissionAdj.permissionApprovedMinutes;
                permissionConsumedMinutes = permissionAdj.permissionConsumedMinutes;
                permissionRemainingMinutes = permissionAdj.permissionRemainingMinutes;

                // Recalculate fine amounts after permission reduction.
                if (fineConfig && fineConfig.enabled === false) {
                    lateFine.fineAmount = 0;
                    earlyFine.fineAmount = 0;
                } else {
                    lateFine.fineAmount = (lateFine.lateMinutes > 0 && effectiveDailyNet > 0)
                        ? calculateFineAmount(lateFine.lateMinutes, 'lateArrival', fineConfig, effectiveDailyNet, shiftHours, effectiveDailyGross)
                        : 0;
                    earlyFine.fineAmount = (earlyFine.earlyMinutes > 0 && effectiveDailyNet > 0)
                        ? calculateFineAmount(earlyFine.earlyMinutes, 'earlyExit', fineConfig, effectiveDailyNet, shiftHours, effectiveDailyGross)
                        : 0;
                }

                console.log('[Permission][Fine Adjust]', {
                    isOpenShiftDay,
                    policy: dbShiftTimings?.permissionPolicy || null,
                    permissionApprovedMinutes,
                    permissionConsumedMinutes,
                    permissionRemainingMinutes,
                    lateUsed: permissionLateUsed,
                    earlyUsed: permissionEarlyUsed,
                    remainingLate: lateFine.lateMinutes,
                    remainingEarly: earlyFine.earlyMinutes
                });
            }
        } catch (permissionErr) {
            console.error('[Permission][Fine Adjust] Failed:', permissionErr?.message);
        }

        // Apply fine amounts from payroll.fineCalculation when enabled (allowLateEntry/allowEarlyExit only control blocking punch, not whether fine is charged)
        const lateFineAmount = (fineConfig && fineConfig.enabled) ? (lateFine.fineAmount || 0) : 0;
        const earlyFineAmount = (fineConfig && fineConfig.enabled) ? (earlyFine.fineAmount || 0) : 0;

        const fineHours = lateFine.lateMinutes + earlyFine.earlyMinutes;
        const fineAmount = lateFineAmount + earlyFineAmount;

        // Reference shiftBased breakdown for manual testing (actual lines may use fineRules; see [Fine][formula][test] per leg)
        const testTag = '[Fine][formula][test]';
        if (fineConfig && fineConfig.enabled && effectiveDailyGross > 0 && shiftHours > 0) {
            const refHourly = effectiveDailyGross / shiftHours;
            const lateH = (Number(lateFine.lateMinutes) || 0) / 60;
            const earlyH = (Number(earlyFine.earlyMinutes) || 0) / 60;
            const refLatePart = refHourly * lateH;
            const refEarlyPart = refHourly * earlyH;
            console.log(
                testTag,
                'combined | ref_hourly_rate = dailySalary ÷ shiftHours =',
                effectiveDailyGross,
                '÷',
                shiftHours,
                '=',
                refHourly.toFixed(6)
            );
            console.log(
                testTag,
                'combined | if_shiftBased_1x_per_leg: late_part = hourly×(lateMin÷60) =',
                refHourly.toFixed(4),
                '×',
                lateH.toFixed(6),
                '=',
                refLatePart.toFixed(6),
                '| early_part =',
                refHourly.toFixed(4),
                '×',
                earlyH.toFixed(6),
                '=',
                refEarlyPart.toFixed(6)
            );
            console.log(
                testTag,
                'combined | ref_sum_1x =',
                refLatePart.toFixed(6),
                '+',
                refEarlyPart.toFixed(6),
                '=',
                (refLatePart + refEarlyPart).toFixed(6),
                '| actual stored: lateFineAmount=',
                lateFineAmount,
                'earlyFineAmount=',
                earlyFineAmount,
                'fineAmount=',
                fineAmount
            );
        }

        const out = {
            lateMinutes: lateFine.lateMinutes,
            earlyMinutes: earlyFine.earlyMinutes,
            fineHours: fineHours,
            fineAmount: fineAmount,
            lateFineAmount,
            earlyFineAmount,
            permissionLateMinutes: permissionLateUsed,
            permissionEarlyMinutes: permissionEarlyUsed,
            permissionApprovedMinutes,
            permissionConsumedMinutes,
            permissionRemainingMinutes
        };
        console.log('[Fine] Result:', JSON.stringify(out));
        // Formula summary with check-in/check-out times for debugging why lateMinutes might be 0
        console.log('[Fine FORMULA] Summary: checkInTime=', checkInStr, 'checkOutTime=', checkOutStr,
            '| dailyNet=', effectiveDailyNet, 'dailyGross=', effectiveDailyGross, 'shiftHours=', shiftHours, 'shiftStart=', shiftStartTime, 'shiftEnd=', shiftEndTime, 'businessTimezone=', businessTimezone,
            '| lateMinutes=', lateFine.lateMinutes, 'lateFineAmount=', lateFineAmount,
            '| earlyMinutes=', earlyFine.earlyMinutes, 'earlyFineAmount=', earlyFineAmount,
            '| totalFineAmount=', fineAmount);
        const formulaDesc = (fineConfig && fineConfig.calculationType) ? fineConfig.calculationType : 'shiftBased';
        console.log('[Fine AMOUNT TEST] --- Formula: ' + formulaDesc + ' ---');
        console.log('[Fine AMOUNT TEST] Times: checkInTime=' + checkInStr + ' | checkOutTime=' + (checkOutStr || 'null') + ' | attendanceDate=' + (attendanceDate?.toISOString?.() || ''));
        console.log('[Fine AMOUNT TEST] Inputs: dailyNet=' + effectiveDailyNet + ' dailyGross=' + effectiveDailyGross + ', shiftHours=' + shiftHours + ', shiftStart=' + shiftStartTime + ', shiftEnd=' + shiftEndTime + ', businessTimezone=' + businessTimezone);
        console.log('[Fine AMOUNT TEST] Late: minutes=' + lateFine.lateMinutes + ' => fineAmount=' + lateFineAmount + ' | Early: minutes=' + earlyFine.earlyMinutes + ' => fineAmount=' + earlyFineAmount);
        console.log('[Fine AMOUNT TEST] Formula (shiftBased): totalFineAmount = (dailySalary/shiftHours)*(lateMinutes/60) + (dailySalary/shiftHours)*(earlyMinutes/60) = lateFineAmount + earlyFineAmount');
        console.log('[Fine AMOUNT TEST] Result: totalFineAmount = ' + lateFineAmount + ' + ' + earlyFineAmount + ' = ' + fineAmount);
        return out;
    } catch (error) {
        console.error('[Fine] Calculation Error', error);
        return { lateMinutes: 0, earlyMinutes: 0, fineHours: 0, fineAmount: 0, lateFineAmount: 0, earlyFineAmount: 0 };
    }
}

/**
 * Persists attendance.overtimeAmount (rupees) when eligible OT minutes >= shift otBufferMinutes.
 * Uses payroll fineCalculation gate + same shiftBased/fixedPerHour base as OT pay (see calculateOvertimePayAmount).
 * Pays for full stored overtime minutes (e.g. 143) when threshold met.
 */
async function applyOvertimeAmountForAttendance(
    attendance,
    staff,
    company,
    template,
    shiftTiming,
    attendanceDate,
    leaveForOt,
    perDayOverride
) {
    const logTag = '[OT Calc][amount]';
    const otRounded = Math.floor(Number(attendance.overtime) || 0);
    const buf = Math.max(0, Math.round(Number(shiftTiming?.otBufferMinutes) || 0));
    const fineConfig = getEffectiveFineConfig(company || {});
    const otSettings = company?.settings?.attendance?.overtimePaySettings;
    const otPayAllowed =
        fineConfig.enabled === true || otSettings?.enabled === true;

    console.log(logTag, 'inputs | attendanceId=%s staffId=%s | overtime(min)=%s otBufferMinutes=%s | threshold: pay only if overtime≥buffer → %s',
        attendance._id?.toString?.() || null,
        staff._id?.toString?.() || null,
        otRounded,
        buf,
        otRounded >= buf ? 'PASS' : 'FAIL');

    if (!shiftTiming || otRounded < buf) {
        const reason = !shiftTiming ? 'no_shiftTiming' : 'overtime_below_buffer';
        console.log(logTag, 'overtimeAmount=0 | reason=%s | formula: (if overtime < otBufferMinutes then no rupee OT)', reason);
        attendance.overtimeAmount = 0;
        return;
    }
    if (!otPayAllowed) {
        console.log(logTag, 'overtimeAmount=0 | reason=otPayDisabled | need payroll.fineCalculation enabled or attendance.overtimePaySettings.enabled');
        attendance.overtimeAmount = 0;
        return;
    }

    const payrollFc = company?.settings?.payroll?.fineCalculation;
    const configForOt = fineConfig.enabled
        ? fineConfig
        : {
            enabled: true,
            calculationType:
                fineConfig.calculationType ||
                (payrollFc?.calculationMethod === 'fixedPerHour' ||
                payrollFc?.calculationType === 'fixedPerHour'
                    ? 'fixedPerHour'
                    : 'shiftBased'),
            finePerHour: fineConfig.finePerHour ?? payrollFc?.finePerHour ?? 0,
            fineRules: []
        };

    const isHalfDay =
        leaveForOt &&
        String(leaveForOt.leaveType || '').trim().toLowerCase() === 'half day';
    const session = isHalfDay
        ? (leaveForOt.halfDaySession ||
            leaveForOt.halfDayType ||
            (leaveForOt.session === '1'
                ? 'First Half Day'
                : leaveForOt.session === '2'
                    ? 'Second Half Day'
                    : null))
        : null;

    const dbShiftTimings = shiftTiming;
    const shiftTypeLower = (dbShiftTimings.shiftType || 'standard').toString().toLowerCase();
    const isOpenShiftDay =
        (shiftTypeLower === 'open' || shiftTypeLower === 'open shift') && !isHalfDay;

    const dbShiftStartTime = dbShiftTimings.startTime || template?.shiftStartTime || '09:30';
    const dbShiftEndTime = dbShiftTimings.endTime || template?.shiftEndTime || '18:30';

    let shiftHours;
    if (isOpenShiftDay) {
        shiftHours = Number(dbShiftTimings.openWorkHours || dbShiftTimings.workHours);
        if (!Number.isFinite(shiftHours) || shiftHours <= 0) shiftHours = 8;
    } else if (isHalfDay && (session === 'First Half Day' || session === 'Second Half Day')) {
        const { getWorkingSessionTimings } = require('../utils/leaveAttendanceHelper');
        const sessionTimings = getWorkingSessionTimings(
            session,
            dbShiftStartTime,
            dbShiftEndTime,
            dbShiftTimings.halfDaySettings
        );
        if (sessionTimings) {
            shiftHours = calculateShiftHours(sessionTimings.startTime, sessionTimings.endTime);
        } else {
            shiftHours = calculateShiftHours(dbShiftStartTime, dbShiftEndTime);
        }
    } else {
        shiftHours = calculateShiftHours(dbShiftStartTime, dbShiftEndTime);
    }

    const salaryStructure = staff.salary ? calculateSalaryStructure(staff.salary) : null;
    const netMonthlySalary =
        salaryStructure?.monthly?.netMonthlySalary != null
            ? Number(salaryStructure.monthly.netMonthlySalary)
            : 0;
    const grossMonthlySalary =
        salaryStructure?.monthly?.grossSalary != null
            ? Number(salaryStructure.monthly.grossSalary)
            : 0;
    const attendanceYear = attendanceDate.getFullYear();
    const attendanceMonth1Based = attendanceDate.getMonth() + 1;
    let dailyNet = null;
    let dailyGross = null;

    // Prefer per-day rates passed from the mobile app on punch-out (SharedPreferences preview parity),
    // then staff preview fields (current month only).
    const overrideNet = Number(perDayOverride?.appPerDayNetSalary);
    const overrideGross = Number(perDayOverride?.appPerdayGrossSalary);
    if (Number.isFinite(overrideNet) && overrideNet > 0) dailyNet = overrideNet;
    if (Number.isFinite(overrideGross) && overrideGross > 0) dailyGross = overrideGross;
    if ((dailyNet || dailyGross) && console && console.log) {
        console.log(
            logTag,
            'perDaySource=appOverride',
            '| appPerDayNetSalary=',
            perDayOverride?.appPerDayNetSalary,
            'appPerdayGrossSalary=',
            perDayOverride?.appPerdayGrossSalary
        );
    }

    // Prefer per-day rates synced from payroll preview by the mobile app (current month only).
    const nowForMonthGuard = new Date();
    const isCurrentMonth =
        attendanceYear === nowForMonthGuard.getFullYear() &&
        attendanceMonth1Based === (nowForMonthGuard.getMonth() + 1);
    const appPerDayNet = Number(staff.appPerDayNetSalary);
    const appPerDayGross = Number(staff.appPerdayGrossSalary);

    // Note: dailyNet/dailyGross may already be set by app override.
    if (isCurrentMonth) {
        if ((dailyNet == null || dailyNet <= 0) && Number.isFinite(appPerDayNet) && appPerDayNet > 0) dailyNet = appPerDayNet;
        if ((dailyGross == null || dailyGross <= 0) && Number.isFinite(appPerDayGross) && appPerDayGross > 0) dailyGross = appPerDayGross;
        if ((dailyNet || dailyGross) && console && console.log && !(Number.isFinite(overrideNet) && overrideNet > 0) && !(Number.isFinite(overrideGross) && overrideGross > 0)) {
            console.log(
                logTag,
                'perDaySource=staffPreview',
                '| appPerDayNetSalary=',
                staff.appPerDayNetSalary,
                'appPerdayGrossSalary=',
                staff.appPerdayGrossSalary
            );
        }
    }

    // Fallback: derive per-day from monthly salary ÷ full-month working days (existing behavior).
    if ((dailyNet == null || dailyNet <= 0) && netMonthlySalary > 0 && staff._id) {
        try {
            const attendanceStats = await calculateAttendanceStats(
                staff._id,
                attendanceMonth1Based,
                attendanceYear
            );
            const thisMonthWorkingDays =
                attendanceStats.workingDaysFullMonth ?? attendanceStats.workingDays ?? 0;
            if (thisMonthWorkingDays > 0) {
                dailyNet = netMonthlySalary / thisMonthWorkingDays;
                if (grossMonthlySalary > 0) {
                    dailyGross = grossMonthlySalary / thisMonthWorkingDays;
                }
                console.log(
                    logTag,
                    'perDaySource=monthlyWd',
                    '| netMonthly=',
                    netMonthlySalary,
                    'grossMonthly=',
                    grossMonthlySalary,
                    'wd=',
                    thisMonthWorkingDays,
                    '=> dailyNet=',
                    dailyNet,
                    'dailyGross=',
                    dailyGross
                );
            }
        } catch (err) {
            console.error('[OT Pay] calculateAttendanceStats failed:', err.message);
            const attendanceMonth0Based = attendanceDate.getMonth();
            let monthHolidays = [];
            if (staff.businessId) {
                const holidayTemplate = await getHolidayTemplateForStaff(staff);
                monthHolidays = getHolidaysForMonth(
                    holidayTemplate,
                    attendanceYear,
                    attendanceMonth1Based
                );
            }
            const businessSettings = company?.settings?.business || {};
            const weeklyOffPattern = businessSettings.weeklyOffPattern || 'standard';
            const weeklyHolidays = businessSettings.weeklyHolidays || [{ day: 0, name: 'Sunday' }];
            const workingDays = calculateWorkingDays(
                attendanceYear,
                attendanceMonth0Based,
                monthHolidays,
                weeklyOffPattern,
                weeklyHolidays
            );
            if (workingDays > 0) {
                dailyNet = netMonthlySalary / workingDays;
                if (grossMonthlySalary > 0) dailyGross = grossMonthlySalary / workingDays;
            }
        }
    }

    // OT shiftBased base uses gross when available (same as fine calculation’s base daily salary).
    const baseDailyForOt =
        (dailyGross != null && dailyGross > 0) ? dailyGross : (dailyNet != null ? dailyNet : 0);
    let effectiveDailySalary = baseDailyForOt && baseDailyForOt > 0 ? baseDailyForOt : 0;
    if (isHalfDay && effectiveDailySalary > 0) {
        effectiveDailySalary = effectiveDailySalary / 2;
    }

    // Per-shift overtimePolicy.multiplier wins; else company default; else 1x.
    const shiftOtMult = Number(shiftTiming?.overtimePolicy?.multiplier);
    const mult =
        Number.isFinite(shiftOtMult) && shiftOtMult > 0
            ? shiftOtMult
            : (otSettings && Number(otSettings.defaultMultiplier) > 0
                ? Number(otSettings.defaultMultiplier)
                : 1);

    console.log(logTag, 'payContext | shiftType=%s shiftHours=%s | effectiveDailySalary=%s | halfDay=%s | calcType=%s | OTminutesPaid=%s (full stored overtime) | defaultMultiplier=%s',
        shiftTypeLower,
        shiftHours,
        effectiveDailySalary.toFixed ? effectiveDailySalary.toFixed(4) : effectiveDailySalary,
        isHalfDay,
        configForOt.calculationType || 'shiftBased',
        otRounded,
        mult);

    attendance.overtimeAmount = calculateOvertimePayAmount(
        otRounded,
        configForOt,
        effectiveDailySalary,
        shiftHours,
        mult
    );

    console.log(logTag, 'stored | overtimeAmount=%s INR', attendance.overtimeAmount);
}

// @desc    Check In
// @route   POST /api/attendance/checkin
// @access  Private
const checkIn = async (req, res) => {
    const {
        latitude,
        longitude,
        address,
        area,
        city,
        pincode,
        selfie,
        movementType,
        forceAppFine,
        lateMinutes: bodyLateMinutes,
        earlyMinutes: bodyEarlyMinutes,
        fineAmount: bodyFineAmount,
        businessId: bodyBusinessId,
        source: bodySource,
        punchInTime: bodyPunchInTime,
        clientTime: bodyClientTime
    } = req.body;

    let selfieInput = selfie;
    if (req.file && req.file.buffer && req.file.buffer.length > 0) {
        selfieInput = req.file.buffer;
    }

    const VALID_SOURCES = ['app', 'software', 'webemp', 'webadmin'];
    const source = (bodySource && VALID_SOURCES.includes(String(bodySource).toLowerCase()))
        ? String(bodySource).toLowerCase()
        : null;

    // Use req.staff from middleware
    if (!req.staff) {
        return res.status(404).json({ message: 'Staff record not found for this user' });
    }
    const staffId = req.staff._id;
    console.log('[Attendance checkIn] Staff Shift Name:', req.staff.shiftName);
    const nowForLog = new Date();
    console.log('[Attendance checkIn] request', { staffId: staffId?.toString(), date: nowForLog.toISOString?.()?.slice(0, 10), businessIdFromBody: bodyBusinessId ?? null });

    if (latitude === undefined || longitude === undefined) {
        return res.status(400).json({ message: 'Location coordinates are missing' });
    }

    const userLat = parseFloat(latitude);
    const userLng = parseFloat(longitude);

    // Date Logic: Store as Date object set to midnight (start of day) - UTC safe approach
    const now = new Date();
    // Punch instant captured by the app at button-click time (falls back to server now).
    // The day-bucket below intentionally stays on server `now` to avoid cross-day drift.
    const punchInAt = resolveClientPunchTime(bodyPunchInTime ?? bodyClientTime, now);
    // Create Date object for start/end of day in UTC to ensure MongoDB ISODate format
    const year = now.getUTCFullYear();
    const month = now.getUTCMonth();
    const day = now.getUTCDate();
    const startOfDay = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
    const endOfDay = new Date(Date.UTC(year, month, day, 23, 59, 59, 999));

    try {
        const checkInT0 = Date.now();
        // Re-fetch staff (keep attendanceTemplateId as ObjectId; resolve template via collection lookup)
        const staff = await Staff.findById(staffId)
            .populate('branchId')
            .populate('weeklyHolidayTemplateId')
            .populate('holidayTemplateId');
        console.log('[Attendance checkIn] Fetched Staff Details: _id=', staff._id?.toString(), 'shiftName=', staff.shiftName);

        // Punch-in is hit en masse at shift start. These reads are independent once we
        // have `staff`, so fan them out concurrently instead of paying ~5 serial Mongo
        // round-trips. Validation order below is unchanged — only the fetching moved up.
        const Company = require('../models/Company');
        const Leave = require('../models/Leave');
        const [templateDoc, company, activeLeave, holidayTemplate, existingByEmployee] = await Promise.all([
            loadAttendanceTemplateForStaff(staff),
            Company.findById(staff.businessId),
            Leave.findOne({
                employeeId: staffId,
                status: { $regex: /^approved$/i },
                startDate: { $lte: endOfDay },
                endDate: { $gte: startOfDay }
            }),
            getHolidayTemplateForStaff(staff),
            Attendance.findOne({
                employeeId: staffId,
                date: { $gte: startOfDay, $lte: endOfDay }
            })
        ]);
        const template = normalizeTemplate(templateDoc);
        console.log('[Attendance checkIn] template flags', {
            staffId: staffId?.toString(),
            templateName: template?.name ?? null,
            requireSelfie: template?.requireSelfie,
            requireGeolocation: template?.requireGeolocation
        });

        const hasSelfiePayload = Boolean(
            selfieInput &&
            (Buffer.isBuffer(selfieInput)
                ? selfieInput.length > 0
                : String(selfieInput).trim().length > 0)
        );
        if (template.requireSelfie !== false && !hasSelfiePayload) {
            return res.status(400).json({ message: 'Selfie is required for check-in.' });
        }
        console.log('[Attendance checkIn] start', {
            staffId: staffId?.toString(),
            contentLength: req.headers['content-length'],
            hasSelfie: hasSelfiePayload,
            selfieMultipart: Boolean(req.file && req.file.buffer && req.file.buffer.length > 0),
        });

        // Salary must be configured to allow check-in (required for fine/late/early storage and payroll)
        const salaryStructure = staff.salary ? calculateSalaryStructure(staff.salary) : null;
        const netMonthlySalary = salaryStructure?.monthly?.netMonthlySalary != null ? Number(salaryStructure.monthly.netMonthlySalary) : 0;
        if (!staff.salary || netMonthlySalary <= 0) {
            return res.status(400).json({ message: 'Salary not configured. Contact HR.' });
        }

        if (!isShiftAssignedForStaff(company, staff, templateDoc)) {
            return res.status(403).json({ message: 'Shift not assigned. Contact HR.' });
        }
        // PRIORITY 1: Check if On Approved Leave (highest priority - blocks all other rules)
        // `company`, `activeLeave` already fetched in the concurrent batch above.
        const { canCheckInWithHalfDayLeave, getShiftTimings, getBusinessTimezone } = require('../utils/leaveAttendanceHelper');
        const shiftForCheckIn = getShiftTimings(company, staff, startOfDay, staff?.joiningDate, templateDoc);
        const businessTimezone = getBusinessTimezone(company);
        if (activeLeave) {
            if (activeLeave.leaveType === 'Half Day') {
                const checkInResult = canCheckInWithHalfDayLeave(
                    activeLeave,
                    now,
                    shiftForCheckIn.startTime,
                    shiftForCheckIn.endTime,
                    businessTimezone,
                    shiftForCheckIn.halfDaySettings,
                    shiftForCheckIn.gracePeriodMinutes
                );
                if (!checkInResult.allowed) {
                    return res.status(403).json({ message: checkInResult.message || 'Half-day leave approved. Check-in not allowed at this time.' });
                }
            } else {
                return res.status(403).json({ message: 'You are on leave today. Enjoy your leave.' });
            }
        }

        // 2. Check for Holiday (holidayTemplate already fetched in the concurrent batch above)
        const isHoliday = !!getHolidayForDate(holidayTemplate, now);
        if (isHoliday && template.allowAttendanceOnHolidays === false) {
            return res.status(403).json({ message: 'Today is a Holiday. Check-in not allowed.' });
        }

        // 3. Check for Weekly Off (use staff's WeeklyHolidayTemplate if set, else company)
        const weekOffConfig = await getWeekOffConfigForStaff(staff, company);
        const dayOfWeek = now.getDay();
        let isWeeklyOff = false;
        if (weekOffConfig.weeklyOffPattern === 'oddEvenSaturday') {
            if (dayOfWeek === 0) isWeeklyOff = true;
            else if (dayOfWeek === 6 && isOddEvenSaturdayWeeklyOff(now.getFullYear(), now.getMonth(), now.getDate(), 'local')) isWeeklyOff = true;
        } else {
            isWeeklyOff = weekOffConfig.weeklyHolidays.some(h => h.day === dayOfWeek);
        }
        if (isWeeklyOff && template.allowAttendanceOnWeeklyOff === false) {
            // If it's the oddEvenSaturday pattern and today is Saturday, allow check-in regardless of the template setting
            if (weekOffConfig.weeklyOffPattern === 'oddEvenSaturday' && dayOfWeek === 6) {
                // Allow check-in
            } else {
                return res.status(403).json({ message: 'Today is a Weekly Off. Check-in not allowed.' });
            }
        }

        const warnings = [];

        // 4. Check Late Entry - Always allow, but add warning if not allowed in settings
        const shiftTiming = company ? shiftForCheckIn : null;
        const appliedShiftId = getAppliedShiftIdFromShiftTiming(shiftTiming);
        let shiftStartStr = null;
        let shiftEndStr = null;
        let lateMinutes = 0;

        if (isOpenShiftTiming({ shiftType: shiftTiming?.shiftType })) {
            // For open shifts, fixed start/end times are not applicable.
            // lateMinutes will remain 0 as initialized.
            console.log('[Fine] checkIn: Open shift detected, bypassing fixed shift time calculations.');
        } else {
            shiftStartStr = shiftTiming?.startTime || template.shiftStartTime || "09:30";
            shiftEndStr = shiftTiming?.endTime || template.shiftEndTime || "18:30";
            const gracePeriod = shiftTiming?.gracePeriodMinutes ?? template.gracePeriodMinutes ?? 0;
            const [sHours, sMins] = shiftStartStr.split(':').map(Number);

            const shiftStart = new Date(now);
            shiftStart.setHours(sHours, sMins, 0, 0);
            const graceTimeEnd = new Date(shiftStart);
            graceTimeEnd.setMinutes(graceTimeEnd.getMinutes() + gracePeriod);

            if (now > graceTimeEnd) {
                lateMinutes = Math.floor((now.getTime() - shiftStart.getTime()) / (1000 * 60));
                if (template.allowLateEntry === false) {
                    warnings.push({
                        type: 'late_entry',
                        message: `Late entry not allowed. You are ${lateMinutes} minute(s) late. Shift start time: ${shiftStartStr}`,
                        minutes: lateMinutes,
                        notAllowed: true
                    });
                }
            }
        }

        // Geofence Logic (supports multiple sub-locations via geofence.locations[])
        let activeBranch = null;
        let isGeofenceEnabled = false;
        let geofenceTargets = [];
        let officeName;

        if (staff.branchId) {
            activeBranch = staff.branchId;
            officeName = activeBranch.branchName || "Assigned Branch";
            const geofenceEval = getBranchGeofenceTargets(activeBranch);
            isGeofenceEnabled = geofenceEval.enabled === true;
            geofenceTargets = geofenceEval.targets || [];
        }

        if (isGeofenceEnabled && template.requireGeolocation !== false) {
            if (!Array.isArray(geofenceTargets) || geofenceTargets.length === 0) {
                console.warn(
                    `[CheckIn Warning] Geofence enabled for ${officeName} but no valid locations found.`
                );
            } else {
                let isInsideAny = false;
                let nearest = null; // { latitude, longitude, radius, label, distanceM }

                for (const t of geofenceTargets) {
                    const distKm = getDistanceFromLatLonInKm(userLat, userLng, t.latitude, t.longitude);
                    const distM = distKm * 1000;

                    if (distM <= t.radius) {
                        isInsideAny = true;
                        break;
                    }

                    if (!nearest || distM < nearest.distanceM) {
                        nearest = { ...t, distanceM: distM };
                    }
                }

                if (!isInsideAny) {
                    const label = nearest?.label || officeName || 'Allowed Location';
                    const allowed = nearest?.radius ?? 0;
                    const distance = nearest?.distanceM;
                    return res.status(400).json({
                        message: `Check-in denied. You are ${distance != null ? distance.toFixed(0) : 'unknown'}m away from allowed location(s). Allowed radius: ${allowed}m. (${label})`,
                    });
                }
            }
        }

        // Check for existing attendance - check both employeeId and user fields
        // to find records created from web or app. The employeeId lookup was already
        // run in the concurrent batch above; only fall back to the legacy `user`
        // field when that returned nothing.
        let existing = existingByEmployee;

        if (!existing) {
            existing = await Attendance.findOne({
                user: staffId,
                date: { $gte: startOfDay, $lte: endOfDay }
            });
        }

        // Half Day: if record exists for today and day is Half Day (approved leave or status), update existing instead of blocking
        const isHalfDayLeave = activeLeave && String(activeLeave.leaveType || '').trim().toLowerCase() === 'half day';
        const isHalfDayStatus = existing && String(existing.status || '').trim().toLowerCase() === 'half day';
        const isHalfDayDay = isHalfDayLeave || isHalfDayStatus;

        if (existing && isHalfDayDay) {
            // Update existing Half Day record with punchIn (do not create new, do not return "Already checked in")
            const deferHalfDaySelfie = Boolean(selfieInput && template.requireSelfie !== false);
            const fineShiftStartTime = shiftTiming?.startTime || template.shiftStartTime || '09:30';
            const fineShiftEndTime = shiftTiming?.endTime || template.shiftEndTime || '18:30';
            const fineGracePeriod = shiftTiming?.gracePeriodMinutes ?? template.gracePeriodMinutes ?? 0;
            const fineTemplate = {
                ...template,
                shiftStartTime: fineShiftStartTime,
                shiftEndTime: fineShiftEndTime,
                gracePeriodMinutes: fineGracePeriod
            };
            const useAppProvidedFine = source === 'app' && isTruthyRequestBool(forceAppFine);
            let permissionFromServer = null;
            if (useAppProvidedFine) {
                try {
                    permissionFromServer = await calculateCombinedFine(
                        now,
                        null,
                        startOfDay,
                        fineTemplate,
                        staff,
                        company,
                        activeLeave,
                        {
                            appPerDayNetSalary: req.body?.appPerDayNetSalary,
                            appPerdayGrossSalary: req.body?.appPerdayGrossSalary
                        },
                        { attendanceId: existing._id }
                    );
                } catch (permErr) {
                    console.error('[Permission][CHECK-IN][HALF-DAY][APP] calculateCombinedFine failed:', permErr?.message);
                }
            }
            // For app punches with forceAppFine=true, trust app fine payload and skip backend fine recomputation.
            const fineResult = useAppProvidedFine
                ? {
                    lateMinutes: hasExplicitAppFineNumeric(bodyLateMinutes)
                        ? Math.max(0, Math.round(Number(bodyLateMinutes)))
                        : 0,
                    earlyMinutes: hasExplicitAppFineNumeric(bodyEarlyMinutes)
                        ? Math.max(0, Math.round(Number(bodyEarlyMinutes)))
                        : 0,
                    fineAmount: hasExplicitAppFineNumeric(bodyFineAmount)
                        ? Math.max(0, Math.round(Number(bodyFineAmount) * 100) / 100)
                        : 0,
                    permissionLateMinutes: permissionFromServer?.permissionLateMinutes ?? existing.permissionLateMinutes ?? 0,
                    permissionEarlyMinutes: permissionFromServer?.permissionEarlyMinutes ?? existing.permissionEarlyMinutes ?? 0,
                    permissionApprovedMinutes: permissionFromServer?.permissionApprovedMinutes ?? existing.permissionApprovedMinutes ?? 0,
                    permissionConsumedMinutes: permissionFromServer?.permissionConsumedMinutes ?? existing.permissionConsumedMinutes ?? 0,
                    permissionRemainingMinutes: permissionFromServer?.permissionRemainingMinutes ?? existing.permissionRemainingMinutes ?? 0
                }
                : await calculateCombinedFine(
                    now,
                    null,
                    startOfDay,
                    fineTemplate,
                    staff,
                    company,
                    activeLeave,
                    {
                        appPerDayNetSalary: req.body?.appPerDayNetSalary,
                        appPerdayGrossSalary: req.body?.appPerdayGrossSalary
                    },
                    { attendanceId: existing._id, appliedShiftId: appliedShiftId || existing.appliedShiftId || null }
                );
            existing.punchIn = punchInAt;

            // Update location using Mongoose set() method for nested paths to avoid validation issues
            // This ensures punchOut is not touched if it doesn't exist
            existing.set('location.latitude', userLat);
            existing.set('location.longitude', userLng);
            existing.set('location.address', address || '');
            existing.set('location.area', area || '');
            existing.set('location.city', city || '');
            existing.set('location.pincode', pincode || '');
            
            // Update punchIn nested object
            existing.set('location.punchIn.latitude', userLat);
            existing.set('location.punchIn.longitude', userLng);
            existing.set('location.punchIn.address', address || '');
            existing.set('location.punchIn.area', area || '');
            existing.set('location.punchIn.city', city || '');
            existing.set('location.punchIn.pincode', pincode || '');
            
            // punchOut is NOT set - Mongoose will preserve existing value or leave it undefined
            // This avoids the "Cast to Object failed" error
            
            existing.punchInSelfie = null;
            existing.punchInIpAddress = req.ip || req.connection.remoteAddress;
            existing.ipAddress = req.ip || req.connection.remoteAddress;
            if (staff.businessId != null) {
                existing.businessId = staff.businessId;
                console.log('[Attendance checkIn] (half-day update) storing businessId in attendances:', staff.businessId?.toString());
            }
            if (appliedShiftId) {
                existing.appliedShiftId = appliedShiftId;
            }
            existing.lateMinutes = fineResult.lateMinutes ?? 0;
            existing.earlyMinutes = fineResult.earlyMinutes ?? 0;
            existing.fineHours = fineResult.fineHours ?? ((Number(existing.lateMinutes) || 0) + (Number(existing.earlyMinutes) || 0));
            existing.fineAmount = fineResult.fineAmount ?? 0;
            existing.permissionLateMinutes = fineResult.permissionLateMinutes ?? 0;
            existing.permissionEarlyMinutes = fineResult.permissionEarlyMinutes ?? 0;
            existing.permissionApprovedMinutes = fineResult.permissionApprovedMinutes ?? 0;
            existing.permissionConsumedMinutes = fineResult.permissionConsumedMinutes ?? 0;
            existing.permissionRemainingMinutes = fineResult.permissionRemainingMinutes ?? 0;
            // For app punches, prefer app-calculated values so DB matches app formula/logs.
            if (
                !useAppProvidedFine &&
                source === 'app' &&
                isTruthyRequestBool(forceAppFine) &&
                (Number(fineResult.permissionConsumedMinutes) || 0) <= 0
            ) {
                // If it's an open shift day, explicitly set lateMinutes and fineAmount to 0
                // regardless of app-provided values.
                const shiftTypeLower = (fineTemplate.shiftType || 'standard').toString().toLowerCase();
                const isOpenShiftDay = (shiftTypeLower === 'open' || shiftTypeLower === 'open shift');

                if (isOpenShiftDay) {
                    existing.lateMinutes = 0;
                    existing.fineAmount = 0;
                    existing.fineHours = existing.earlyMinutes;
                    console.log('[Fine STORE][CHECK-IN][HALF-DAY UPDATE][APP OVERRIDE] Open shift detected, lateMinutes and fineAmount forced to 0.');
                } else {
                    if (hasExplicitAppFineNumeric(bodyLateMinutes)) {
                        existing.lateMinutes = Math.max(0, Math.round(Number(bodyLateMinutes)));
                    }
                    if (hasExplicitAppFineNumeric(bodyEarlyMinutes)) {
                        existing.earlyMinutes = Math.max(0, Math.round(Number(bodyEarlyMinutes)));
                    }
                    if (hasExplicitAppFineNumeric(bodyFineAmount)) {
                        const serverFine = Number(fineResult.fineAmount) || 0;
                        const appFine = Math.max(0, Math.round(Number(bodyFineAmount) * 100) / 100);
                        // Use app fine if it's > 0, OR if server also thinks it's 0.
                        // This prevents app's "default 0" from wiping out server's correct calculation.
                        if (appFine > 0 || serverFine <= 0) {
                            existing.fineAmount = appFine;
                        }
                    }
                    existing.fineHours = (Number(existing.lateMinutes) || 0) + (Number(existing.earlyMinutes) || 0);
                    console.log('[Fine STORE][CHECK-IN][HALF-DAY UPDATE][APP OVERRIDE]', {
                        lateMinutes: existing.lateMinutes,
                        earlyMinutes: existing.earlyMinutes,
                        fineHours: existing.fineHours,
                        fineAmount: existing.fineAmount
                    });
                }
            }
            existing.workHours = 0;
            existing.isPaidLeave = false;  // check-in: set false
            if (source) existing.source = source;
            console.log('[Fine STORE][CHECK-IN][HALF-DAY UPDATE]', {
                attendanceId: existing._id?.toString?.() || null,
                lateMinutes: existing.lateMinutes,
                earlyMinutes: existing.earlyMinutes,
                fineHours: existing.fineHours,
                fineAmount: existing.fineAmount
            });
            await existing.save();
            const response = existing.toObject ? existing.toObject() : existing;
            if (warnings.length > 0) response.warnings = warnings;
            console.log('[Attendance checkIn] success (half-day update)', {
                staffId: staffId?.toString(),
                attendanceId: existing._id?.toString(),
                ms: Date.now() - checkInT0,
            });
            await closeStaleOpenBreaksForStaff(staff).catch((err) =>
                console.warn('[Attendance checkIn] closeStaleOpenBreaksForStaff', err?.message)
            );
            if (deferHalfDaySelfie) {
                scheduleDeferredAttendanceSelfieUpload(
                    existing._id,
                    selfieInput,
                    req,
                    staff.businessId ? String(staff.businessId) : undefined,
                    staff.name,
                    'punchInSelfie',
                );
            }
            void Promise.allSettled([
                AttendanceLog.create({
                    attendanceId: existing._id,
                    action: 'PUNCH_IN',
                    performedBy: staffId,
                    performedByName: staff.name || undefined,
                    performedByEmail: staff.email || undefined,
                    selfieUrl: undefined,
                    punchInDateTime: punchInAt,
                    punchInAddress: buildAddressString(address, area, city, pincode) || undefined,
                    timestamp: now
                }),
                insertAttendanceTracking(staffId, staff.name, userLat, userLng, 'in_office', 'checked_in', movementType, address, area, city, pincode)
            ]);
            return res.status(200).json(response);
        }

        if (existing) {
            return res.status(400).json({ message: 'Already checked in today' });
        }

        const deferCreateSelfie = Boolean(selfieInput && template.requireSelfie !== false);

        const locationData = {
            latitude: userLat,
            longitude: userLng,
            address: address || '',
            area: area || '',
            city: city || '',
            pincode: pincode || '',
            punchIn: {
                latitude: userLat,
                longitude: userLng,
                address: address || '',
                area: area || '',
                city: city || '',
                pincode: pincode || ''
            }
        };

        // Calculate fine for late arrival
        // Use shift timing from Company settings if available, otherwise use template
        const fineShiftStartTime = shiftTiming?.startTime || template.shiftStartTime || "09:30";
        const fineShiftEndTime = shiftTiming?.endTime || template.shiftEndTime || "18:30";
        const fineGracePeriod = shiftTiming?.gracePeriodMinutes ?? template.gracePeriodMinutes ?? 0;
        
        // Create a fine template object with shift timings
        const fineTemplate = {
            ...template,
            shiftStartTime: fineShiftStartTime,
            shiftEndTime: fineShiftEndTime,
            gracePeriodMinutes: fineGracePeriod
        };
        
        const useAppProvidedFine = source === 'app' && isTruthyRequestBool(forceAppFine);
        let permissionFromServer = null;
        if (useAppProvidedFine) {
            try {
                permissionFromServer = await calculateCombinedFine(
                    now,
                    null,
                    startOfDay,
                    fineTemplate,
                    staff,
                    company,
                    activeLeave,
                    {
                        appPerDayNetSalary: req.body?.appPerDayNetSalary,
                        appPerdayGrossSalary: req.body?.appPerdayGrossSalary
                    },
                    { appliedShiftId: appliedShiftId || null }
                );
            } catch (permErr) {
                console.error('[Permission][CHECK-IN][CREATE][APP] calculateCombinedFine failed:', permErr?.message);
            }
        }
        // For app punches with forceAppFine=true, trust app fine payload and skip backend fine recomputation.
        const fineResult = useAppProvidedFine
            ? {
                lateMinutes: hasExplicitAppFineNumeric(bodyLateMinutes)
                    ? Math.max(0, Math.round(Number(bodyLateMinutes)))
                    : 0,
                earlyMinutes: hasExplicitAppFineNumeric(bodyEarlyMinutes)
                    ? Math.max(0, Math.round(Number(bodyEarlyMinutes)))
                    : 0,
                fineAmount: hasExplicitAppFineNumeric(bodyFineAmount)
                    ? Math.max(0, Math.round(Number(bodyFineAmount) * 100) / 100)
                    : 0,
                permissionLateMinutes: permissionFromServer?.permissionLateMinutes ?? 0,
                permissionEarlyMinutes: permissionFromServer?.permissionEarlyMinutes ?? 0,
                permissionApprovedMinutes: permissionFromServer?.permissionApprovedMinutes ?? 0,
                permissionConsumedMinutes: permissionFromServer?.permissionConsumedMinutes ?? 0,
                permissionRemainingMinutes: permissionFromServer?.permissionRemainingMinutes ?? 0
            }
            : await calculateCombinedFine(
                now,
                null,
                startOfDay,
                fineTemplate,
                staff,
                company,
                activeLeave,
                null,
                { appliedShiftId: appliedShiftId || null }
            );
        // Create initial attendance record. Store businessId from staff (staffs collection).
        const businessIdToStore = staff.businessId;
        console.log('[Attendance checkIn] storing in attendances: businessId=', businessIdToStore?.toString(), '(from staffs collection; body businessId=', bodyBusinessId ?? 'not sent', ')');
        const attendance = await Attendance.create({
            employeeId: staffId,
            user: staffId,
            businessId: businessIdToStore,
            ...(appliedShiftId && { appliedShiftId }),
            date: startOfDay,
            punchIn: punchInAt,
            status: (isHoliday || isWeeklyOff) ? 'Present' : 'Pending',
            isPaidLeave: false,  // check-in attendance: default false
            location: locationData,
            punchInSelfie: null,
            ipAddress: req.ip || req.connection.remoteAddress,
            punchInIpAddress: req.ip || req.connection.remoteAddress,
            ...(source && { source }),
            // Fine calculation fields
            workHours: 0,
            fineHours: fineResult.fineHours ?? 0,
            lateMinutes: fineResult.lateMinutes ?? 0,
            earlyMinutes: fineResult.earlyMinutes ?? 0,
            fineAmount: fineResult.fineAmount ?? 0,
            permissionLateMinutes: fineResult.permissionLateMinutes ?? 0,
            permissionEarlyMinutes: fineResult.permissionEarlyMinutes ?? 0,
            permissionApprovedMinutes: fineResult.permissionApprovedMinutes ?? 0,
            permissionConsumedMinutes: fineResult.permissionConsumedMinutes ?? 0,
            permissionRemainingMinutes: fineResult.permissionRemainingMinutes ?? 0
        });
        // For app punches, prefer app-calculated values so DB matches app formula/logs.
        if (
            !useAppProvidedFine &&
            source === 'app' &&
            isTruthyRequestBool(forceAppFine) &&
            (Number(fineResult.permissionConsumedMinutes) || 0) <= 0
        ) {
            // If it's an open shift day, explicitly set lateMinutes and fineAmount to 0
            // regardless of app-provided values.
            const shiftTypeLower = (fineTemplate.shiftType || 'standard').toString().toLowerCase();
            const isOpenShiftDay = (shiftTypeLower === 'open' || shiftTypeLower === 'open shift');

            if (isOpenShiftDay) {
                attendance.lateMinutes = 0;
                attendance.fineAmount = 0;
                attendance.fineHours = attendance.earlyMinutes;
                console.log('[Fine STORE][CHECK-IN][CREATE][APP OVERRIDE] Open shift detected, lateMinutes and fineAmount forced to 0.');
            } else { 
                if (hasExplicitAppFineNumeric(bodyLateMinutes)) {
                    attendance.lateMinutes = Math.max(0, Math.round(Number(bodyLateMinutes)));
                }
                if (hasExplicitAppFineNumeric(bodyEarlyMinutes)) {
                    attendance.earlyMinutes = Math.max(0, Math.round(Number(bodyEarlyMinutes)));
                }
                if (hasExplicitAppFineNumeric(bodyFineAmount)) {
                    const serverFine = Number(fineResult.fineAmount) || 0;
                    const appFine = Math.max(0, Math.round(Number(bodyFineAmount) * 100) / 100);
                    if (appFine > 0 || serverFine <= 0) {
                        attendance.fineAmount = appFine;
                    }
                }
                attendance.fineHours =
                    (Number(attendance.lateMinutes) || 0) + (Number(attendance.earlyMinutes) || 0);
                console.log('[Fine STORE][CHECK-IN][CREATE][APP OVERRIDE]', {
                    lateMinutes: attendance.lateMinutes,
                    earlyMinutes: attendance.earlyMinutes,
                    fineHours: attendance.fineHours,
                    fineAmount: attendance.fineAmount
                });
            }
            await attendance.save();
        } 
        console.log('[Fine STORE][CHECK-IN][CREATE]', {
            attendanceId: attendance._id?.toString?.() || null,
            lateMinutes: attendance.lateMinutes,
            earlyMinutes: attendance.earlyMinutes,
            fineHours: attendance.fineHours,
            fineAmount: attendance.fineAmount
        });

        // Include warnings in response if any
        const response = attendance.toObject ? attendance.toObject() : attendance;
        if (warnings.length > 0) {
            response.warnings = warnings;
        }

        console.log('[Attendance checkIn] success', {
            staffId: staffId?.toString(),
            attendanceId: response?._id?.toString?.() || response?.id,
            businessIdStored: response?.businessId?.toString?.() ?? response?.businessId,
            ms: Date.now() - checkInT0,
        });
        await closeStaleOpenBreaksForStaff(staff).catch((err) =>
            console.warn('[Attendance checkIn] closeStaleOpenBreaksForStaff', err?.message)
        );
        if (deferCreateSelfie) {
            scheduleDeferredAttendanceSelfieUpload(
                attendance._id,
                selfieInput,
                req,
                staff.businessId ? String(staff.businessId) : undefined,
                staff.name,
                'punchInSelfie',
            );
        }
        void Promise.allSettled([
            AttendanceLog.create({
                attendanceId: attendance._id,
                action: 'PUNCH_IN',
                performedBy: staffId,
                performedByName: staff.name || undefined,
                performedByEmail: staff.email || undefined,
                selfieUrl: undefined,
                punchInDateTime: punchInAt,
                punchInAddress: buildAddressString(address, area, city, pincode) || undefined,
                timestamp: now
            }),
            insertAttendanceTracking(staffId, staff.name, userLat, userLng, 'in_office', 'checked_in', movementType, address, area, city, pincode)
        ]);
        res.status(201).json(response);

    } catch (error) {
        console.error('[Attendance checkIn] error', error);
        res.status(500).json({ message: error.message });
    }
};

// @desc    Check Out
// @route   PUT /api/attendance/checkout
// @access  Private
const checkOut = async (req, res) => {
    const {
        latitude,
        longitude,
        address,
        area,
        city,
        pincode,
        selfie,
        movementType,
        forceAppFine,
        lateMinutes: bodyLateMinutes,
        earlyMinutes: bodyEarlyMinutes,
        fineAmount: bodyFineAmount,
        source: bodySource,
        punchOutTime: bodyPunchOutTime,
        clientTime: bodyClientTime
    } = req.body;

    let selfieInput = selfie;
    if (req.file && req.file.buffer && req.file.buffer.length > 0) {
        selfieInput = req.file.buffer;
    }

    const VALID_SOURCES = ['app', 'software', 'webemp', 'webadmin'];
    const source = (bodySource && VALID_SOURCES.includes(String(bodySource).toLowerCase()))
        ? String(bodySource).toLowerCase()
        : null;

    if (!req.staff) {
        return res.status(404).json({ message: 'Staff record not found' });
    }
    const staffId = req.staff._id;
    const now = new Date();
    // Punch-out instant captured by the app at button-click time (falls back to server now).
    const punchOutAt = resolveClientPunchTime(bodyPunchOutTime ?? bodyClientTime, now);
    console.log('[Attendance checkOut] request', {
        staffId: staffId?.toString(),
        date: now.toISOString?.()?.slice(0, 10),
        contentLength: req.headers['content-length'],
    });

    // Create Date object for start/end of day in UTC to ensure MongoDB ISODate format
    const year = now.getUTCFullYear();
    const month = now.getUTCMonth();
    const day = now.getUTCDate();
    const startOfDay = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
    const endOfDay = new Date(Date.UTC(year, month, day, 23, 59, 59, 999));

    try {
        const staff = await Staff.findById(staffId)
            .populate('branchId')
            .populate('weeklyHolidayTemplateId')
            .populate('holidayTemplateId');

        // Independent of each other once `staff` is known — fan out concurrently to
        // cut serial Mongo round-trips. `company` is reused by processCheckOut below.
        const Company = require('../models/Company');
        const [templateDoc, company, attendanceByEmployee] = await Promise.all([
            loadAttendanceTemplateForStaff(staff),
            Company.findById(staff.businessId),
            Attendance.findOne({
                employeeId: staffId,
                date: { $gte: startOfDay, $lte: endOfDay }
            })
        ]);
        if (!isShiftAssignedForStaff(company, staff, templateDoc)) {
            return res.status(403).json({ message: 'Shift not assigned. Contact HR.' });
        }
        const template = normalizeTemplate(templateDoc);
        console.log('[Attendance checkOut] template flags', {
            staffId: staffId?.toString(),
            templateName: template?.name ?? null,
            requireSelfie: template?.requireSelfie,
            requireGeolocation: template?.requireGeolocation
        });

        // Find today's attendance (employeeId lookup already done in the batch above)
        const attendance = attendanceByEmployee;

        if (!attendance) {
            const legacyAttendance = await Attendance.findOne({
                user: staffId,
                date: { $gte: startOfDay, $lte: endOfDay }
            });

            if (!legacyAttendance) {
                return res.status(404).json({ message: 'No check-in record found for today' });
            }
            // `await` so any rejection from processCheckOut is caught below and
            // returned as JSON. Without it the rejected promise escapes this
            // try/catch and Express 5 forwards it to the default error handler,
            // which replies with an opaque HTML "Internal Server Error" page.
            return await processCheckOut(
                legacyAttendance,
                req,
                res,
                staff,
                now,
                {
                    latitude,
                    longitude,
                    address,
                    area,
                    city,
                    pincode,
                    selfie: selfieInput,
                    movementType,
                    source,
                    forceAppFine,
                    lateMinutes: bodyLateMinutes,
                    earlyMinutes: bodyEarlyMinutes,
                    fineAmount: bodyFineAmount
                },
                template,
                company
            );
        }

        return await processCheckOut(
            attendance,
            req,
            res,
            staff,
            now,
            {
                latitude,
                longitude,
                address,
                area,
                city,
                pincode,
                selfie: selfieInput,
                movementType,
                source,
                forceAppFine,
                lateMinutes: bodyLateMinutes,
                earlyMinutes: bodyEarlyMinutes,
                fineAmount: bodyFineAmount
            },
            template,
            company
        );

    } catch (error) {
        console.error('[Attendance checkOut] error', error);
        res.status(500).json({ message: error.message });
    }
};

async function processCheckOut(attendance, req, res, staff, now, data, template = {}, companyPrefetched = null) {
    const {
        latitude,
        longitude,
        address,
        area,
        city,
        pincode,
        selfie,
        source,
        movementType,
        forceAppFine,
        lateMinutes: bodyLateMinutes,
        earlyMinutes: bodyEarlyMinutes,
        fineAmount: bodyFineAmount
    } = data;

    // Punch-out instant captured by the app at button-click time (falls back to
    // server now). Recomputed here because `punchOutAt` from the checkOut wrapper
    // is not in this function's scope — processCheckOut is a sibling, not nested.
    const punchOutAt = resolveClientPunchTime(req.body?.punchOutTime ?? req.body?.clientTime, now);

    const checkoutT0 = Date.now();
    console.log('[Attendance processCheckOut] start', {
        contentLength: req.headers['content-length'],
        attendanceId: attendance._id?.toString(),
    });

    const hasCheckOutSelfiePayload = Boolean(
        selfie &&
        (Buffer.isBuffer(selfie) ? selfie.length > 0 : String(selfie).trim().length > 0)
    );
    if (template.requireSelfie !== false && !hasCheckOutSelfiePayload) {
        return res.status(400).json({ message: 'Selfie is required for check-out.' });
    }

    // Half Day: allow updating punchOut even if already set (update existing record)
    const isHalfDayStatus = attendance && String(attendance.status || '').trim().toLowerCase() === 'half day';
    if (attendance.punchOut && !isHalfDayStatus) {
        return res.status(400).json({ message: 'Already checked out today' });
    }

    const year = now.getUTCFullYear();
    const month = now.getUTCMonth();
    const day = now.getUTCDate();
    const startOfDay = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
    const endOfDay = new Date(Date.UTC(year, month, day, 23, 59, 59, 999));

    const Company = require('../models/Company');
    const Leave = require('../models/Leave');
    // Reuse company fetched by the checkOut wrapper; fall back to a fetch only if
    // this function is ever called without it. Leave lookup is independent, so run
    // the (possible) company fetch and the leave fetch concurrently.
    const [company, activeLeave] = await Promise.all([
        companyPrefetched != null
            ? Promise.resolve(companyPrefetched)
            : Company.findById(staff.businessId),
        Leave.findOne({
            employeeId: staff._id,
            status: { $regex: /^approved$/i },
            startDate: { $lte: endOfDay },
            endDate: { $gte: startOfDay }
        })
    ]);

    const shiftDay = attendance.date ? new Date(attendance.date) : startOfDay;
    const {
        canCheckOutWithHalfDayLeave,
        getShiftTimings,
        getBusinessTimezone,
        getWorkingSessionTimings,
        computeOpenShiftOvertimeWithBufferTracking
    } = require('../utils/leaveAttendanceHelper');
    const shiftResolved = company
        ? getShiftTimings(company, staff, shiftDay, staff?.joiningDate, template)
        : null;
    if (activeLeave) {
        if (activeLeave.leaveType === 'Half Day') {
            const shiftForLeave = shiftResolved;
            const tzForLeave = getBusinessTimezone(company);
            const checkOutResult = canCheckOutWithHalfDayLeave(
                activeLeave,
                now,
                shiftForLeave?.startTime,
                shiftForLeave?.endTime,
                tzForLeave,
                shiftForLeave?.halfDaySettings
            );
            if (!checkOutResult.allowed) {
                return res.status(403).json({ message: checkOutResult.message || 'Half-day leave (Session 2). Check-out not allowed.' });
            }
        } else {
            // Full-day (or any non-half-day) approved leave: block check-out only when there is no open session.
            // If punch-in exists (e.g. web check-in during paid leave), allow app to complete punch-out.
            const hasOpenSession = Boolean(attendance.punchIn) && !attendance.punchOut;
            if (!hasOpenSession) {
                return res.status(403).json({ message: 'Your leave request is approved for today. Enjoy your leave.' });
            }
        }
    }

    // Check Early Exit - use session end time for half-day (first/second half), else full shift end
    const shiftTiming = shiftResolved;
    const appliedShiftId = getAppliedShiftIdFromShiftTiming(shiftTiming);
    let dbShiftStart = shiftTiming?.startTime || template.shiftStartTime || '09:30';
    let dbShiftEnd = shiftTiming?.endTime || template.shiftEndTime || '18:30';

    let shiftEndStr = dbShiftEnd;
    let shiftEnd = new Date(now);
    const isHalfDayCheckout = isHalfDayStatus || (activeLeave && String(activeLeave.leaveType || '').trim().toLowerCase() === 'half day');
    if (isHalfDayCheckout && company) {
        const dbShiftTimings = shiftResolved || {};
        dbShiftStart = dbShiftTimings.startTime || dbShiftStart;
        dbShiftEnd = dbShiftTimings.endTime || dbShiftEnd;
        const halfDaySettings = dbShiftTimings.halfDaySettings ?? null;
        let leaveSession = attendance.halfDaySession || (attendance.session === '1' ? 'First Half Day' : attendance.session === '2' ? 'Second Half Day' : null);
        if (!leaveSession && activeLeave) {
            leaveSession = activeLeave.halfDaySession || (activeLeave.session === '1' ? 'First Half Day' : activeLeave.session === '2' ? 'Second Half Day' : null);
        }
        const workingTimings = leaveSession ? getWorkingSessionTimings(leaveSession, dbShiftStart, dbShiftEnd, halfDaySettings) : null;
        if (workingTimings && workingTimings.endTime) {
            shiftEndStr = workingTimings.endTime;
            const [eHours, eMins] = shiftEndStr.split(':').map(Number);
            shiftEnd.setHours(eHours, eMins, 0, 0);
        } else {
            const [eHours, eMins] = dbShiftEnd.split(':').map(Number);
            shiftEnd.setHours(eHours, eMins, 0, 0);
        }
    } else {
        const [eHours, eMins] = dbShiftEnd.split(':').map(Number);
        shiftEnd.setHours(eHours, eMins, 0, 0);
    }

    const isOpenShiftCheckout = !isHalfDayCheckout && isOpenShiftTiming({ shiftType: shiftTiming?.shiftType });

    const warnings = [];
    let earlyMinutes = 0;
    if (isOpenShiftCheckout && attendance.punchIn) {
        const reqH = Number(shiftTiming?.workHours || shiftTiming?.openWorkHours);
        const requiredHours = (Number.isFinite(reqH) && reqH > 0) ? reqH : 8;
        const requiredMin = Math.round(requiredHours * 60);
        
        let effectivePunchIn = new Date(attendance.punchIn);
        if (shiftTiming?.startTime) {
            const { getShiftBoundaryAsUTCDate } = require('../utils/leaveAttendanceHelper');
            const businessTimezone = (company?.settings?.attendance?.timezone || company?.settings?.business?.timezone || company?.timezone || 'Asia/Kolkata');
            const shiftStartUTC = getShiftBoundaryAsUTCDate(shiftDay, shiftTiming.startTime, businessTimezone);
            if (effectivePunchIn > shiftStartUTC) {
                effectivePunchIn = shiftStartUTC;
            }
        }
        
        const workedMin = Math.max(0, Math.floor((now.getTime() - effectivePunchIn.getTime()) / (1000 * 60)));
        earlyMinutes = Math.max(0, requiredMin - workedMin);
        if (earlyMinutes > 0) {
            const notAllowed = template.allowEarlyExit === false;
            warnings.push({
                type: 'early_checkout',
                message: `You are checking out ${earlyMinutes} minute(s) before completing your required ${requiredHours} hour(s) for today.`,
                minutes: earlyMinutes,
                notAllowed
            });
        }
    } else if (now < shiftEnd) {
        earlyMinutes = Math.floor((shiftEnd.getTime() - now.getTime()) / (1000 * 60));
        if (template.allowEarlyExit === false) {
            warnings.push({
                type: 'early_checkout',
                message: `You are punching out ${earlyMinutes} minute(s) early. Shift end time for your working half: ${shiftEndStr}`,
                minutes: earlyMinutes,
                notAllowed: true
            });
        }
    }

    // Geofencing Check (supports multiple sub-locations via geofence.locations[])
    if (
        staff.branchId &&
        latitude !== undefined &&
        longitude !== undefined &&
        template.requireGeolocation !== false
    ) {
        const activeBranch = staff.branchId;
        const officeName = activeBranch.branchName || "Assigned Branch";

        const userLat = parseFloat(latitude);
        const userLng = parseFloat(longitude);
        const geofenceEval = getBranchGeofenceTargets(activeBranch);

        if (geofenceEval.enabled === true) {
            const geofenceTargets = geofenceEval.targets || [];

            if (!Array.isArray(geofenceTargets) || geofenceTargets.length === 0) {
                console.warn(
                    `[CheckOut Warning] Geofence enabled for ${officeName} but no valid locations found.`
                );
            } else if (Number.isFinite(userLat) && Number.isFinite(userLng)) {
                let isInsideAny = false;
                let nearest = null; // { latitude, longitude, radius, label, distanceM }

                for (const t of geofenceTargets) {
                    const distKm = getDistanceFromLatLonInKm(userLat, userLng, t.latitude, t.longitude);
                    const distM = distKm * 1000;

                    if (distM <= t.radius) {
                        isInsideAny = true;
                        break;
                    }

                    if (!nearest || distM < nearest.distanceM) {
                        nearest = { ...t, distanceM: distM };
                    }
                }

                if (!isInsideAny) {
                    const label = nearest?.label || officeName || 'Allowed Location';
                    const allowed = nearest?.radius ?? 0;
                    const distance = nearest?.distanceM;
                    return res.status(400).json({
                        message: `Check-out denied. You are ${distance != null ? distance.toFixed(0) : 'unknown'}m away from allowed location(s). Allowed radius: ${allowed}m. (${label})`,
                    });
                }
            }
        }
    }

    const deferCheckoutSelfie = Boolean(selfie && template.requireSelfie !== false);
    const companyIdForDefer = staff.businessId ? String(staff.businessId) : undefined;
    if (deferCheckoutSelfie) {
        attendance.punchOutSelfie = null;
    }

    // Update Fields
    attendance.punchOut = punchOutAt;
    attendance.punchOutIpAddress = req.ip || req.connection.remoteAddress;
    if (appliedShiftId) attendance.appliedShiftId = appliedShiftId;
    if (source) attendance.source = source;

    if (latitude && longitude) {
        if (!attendance.location) attendance.location = {};
        attendance.location.punchOut = {
            latitude, longitude, address, area, city, pincode
        };
    }

    // Calculate Work Hours: store duration in minutes in attendances collection.
    // Uses the click-time punch-out instant so loading latency does not inflate work hours.
    if (attendance.punchIn) {
        const durationMs = punchOutAt - new Date(attendance.punchIn);
        const minutes = Math.round(durationMs / (1000 * 60));
        attendance.workHours = minutes; // store in minutes

        // Overtime (minutes): only for overtimeEligible staff when template allows OT.
        // Standard/rotational: gross past shift end minus otBufferMinutes. Open shift: full extra vs required daily minutes; bufferTime tracks threshold only.
        const otEligible = staff.overtimeEligible === true;
        // Per-shift overtimePolicy.enabled (tri-state) overrides the template flag when configured.
        const shiftOtEnabled = shiftTiming?.overtimePolicy?.enabled;
        const otAllowedByPolicy = shiftOtEnabled == null
            ? template.allowOvertime !== false
            : shiftOtEnabled === true;
        if (otEligible && otAllowedByPolicy) {
            const stType = (shiftTiming?.shiftType || 'standard').toString().toLowerCase();
            const hasEndTime = shiftTiming?.endTime && String(shiftTiming.endTime).trim().length > 0;
            if (stType === 'open' && isOpenShiftCheckout) {
                const reqH = Number(shiftTiming?.workHours || shiftTiming?.openWorkHours);
                const requiredHours = (Number.isFinite(reqH) && reqH > 0) ? reqH : 8;
                const requiredMin = Math.round(requiredHours * 60);
                const bufferMin = Math.max(0, Math.round(Number(shiftTiming?.otBufferMinutes) || 0));
                const { overtimeMinutes, bufferTimeUsed } = computeOpenShiftOvertimeWithBufferTracking(
                    minutes,
                    requiredMin,
                    bufferMin
                );
                attendance.overtime = overtimeMinutes;
                attendance.bufferTime = bufferTimeUsed;
            } else if (stType !== 'open' && hasEndTime && punchOutAt > shiftEnd) {
                const bufferMin = Math.max(0, Math.round(Number(shiftTiming?.otBufferMinutes) || 0));
                const grossMin = Math.floor((punchOutAt.getTime() - shiftEnd.getTime()) / (60 * 1000));
                attendance.overtime = Math.max(0, grossMin - bufferMin);
                attendance.bufferTime = 0;
                console.log('[OT Minutes][fixed shift] formula: grossPastEnd = floor((punchOut−shiftEnd)/1min) = %s | overtime = max(0, gross − otBuffer) = max(0, %s − %s) = %s',
                    grossMin, grossMin, bufferMin, attendance.overtime);
            } else {
                attendance.overtime = 0;
                attendance.bufferTime = 0;
                console.log('[OT Minutes] overtime=0 | shiftType=%s openCheckout=%s hasEndTime=%s punchAfterShiftEnd=%s',
                    stType, stType === 'open' && isOpenShiftCheckout, !!hasEndTime, punchOutAt > shiftEnd);
            }
        } else {
            attendance.overtime = 0;
            attendance.bufferTime = 0;
            console.log('[OT Minutes] overtime=0 | reason=%s',
                !otEligible ? 'staff_not_overtimeEligible' : 'shift_or_template_disallows_overtime');
        }

        let leaveForOt = activeLeave;
        if (!leaveForOt && isHalfDayStatus && attendance.session) {
            leaveForOt = {
                leaveType: 'Half Day',
                session: attendance.session,
                status: 'Approved'
            };
        }
        await applyOvertimeAmountForAttendance(
            attendance,
            staff,
            company,
            template,
            shiftTiming,
            shiftDay,
            leaveForOt,
            {
                appPerDayNetSalary: data?.appPerDayNetSalary,
                appPerdayGrossSalary: data?.appPerdayGrossSalary
            }
        );
    } else {
        attendance.overtimeAmount = 0;
    }

    // Recalculate fine with punch-out (includes both late arrival and early exit)
    // Use shift timing from Company settings if available, otherwise use template
    const fineShiftStartTime = shiftTiming?.startTime || template.shiftStartTime || "09:30";
    const fineShiftEndTime = shiftTiming?.endTime || template.shiftEndTime || "18:30";
    const fineGracePeriod = shiftTiming?.gracePeriodMinutes ?? template.gracePeriodMinutes ?? 0;
    
    // Create a fine template object with shift timings
    const fineTemplate = {
        ...template,
        shiftStartTime: fineShiftStartTime,
        shiftEndTime: fineShiftEndTime,
        gracePeriodMinutes: fineGracePeriod
    };
    
    // For Half Day: use session-aware fine calculation
    // If activeLeave exists, use it; otherwise construct from attendance if status is Half Day
    let leaveForFine = activeLeave;
    if (!leaveForFine && isHalfDayStatus && attendance.session) {
        leaveForFine = {
            leaveType: 'Half Day',
            session: attendance.session,
            status: 'Approved'
        };
    }
    
    const useAppProvidedFine = source === 'app' && isTruthyRequestBool(forceAppFine);
    let permissionFromServer = null;
    if (useAppProvidedFine) {
        try {
            permissionFromServer = await calculateCombinedFine(
                attendance.punchIn,
                now,
                attendance.date,
                fineTemplate,
                staff,
                company,
                leaveForFine,
                {
                    appPerDayNetSalary: data?.appPerDayNetSalary,
                    appPerdayGrossSalary: data?.appPerdayGrossSalary
                },
                { attendanceId: attendance._id, appliedShiftId: attendance.appliedShiftId || appliedShiftId || null }
            );
        } catch (permErr) {
            console.error('[Permission][CHECK-OUT][APP] calculateCombinedFine failed:', permErr?.message);
        }
    }
    // For app punches with forceAppFine=true, trust app fine payload and skip backend fine recomputation.
    const fineResult = useAppProvidedFine
        ? {
            lateMinutes: hasExplicitAppFineNumeric(bodyLateMinutes)
                ? Math.max(0, Math.round(Number(bodyLateMinutes)))
                : (attendance.lateMinutes ?? 0),
            earlyMinutes: hasExplicitAppFineNumeric(bodyEarlyMinutes)
                ? Math.max(0, Math.round(Number(bodyEarlyMinutes)))
                : 0,
            fineAmount: hasExplicitAppFineNumeric(bodyFineAmount)
                ? Math.max(0, Math.round(Number(bodyFineAmount) * 100) / 100)
                : (attendance.fineAmount ?? 0),
            lateFineAmount: hasExplicitAppFineNumeric(bodyFineAmount)
                ? Math.max(0, Math.round(Number(bodyFineAmount) * 100) / 100)
                : (attendance.fineAmount ?? 0),
            earlyFineAmount: 0,
            permissionLateMinutes: permissionFromServer?.permissionLateMinutes ?? attendance.permissionLateMinutes ?? 0,
            permissionEarlyMinutes: permissionFromServer?.permissionEarlyMinutes ?? attendance.permissionEarlyMinutes ?? 0,
            permissionApprovedMinutes: permissionFromServer?.permissionApprovedMinutes ?? attendance.permissionApprovedMinutes ?? 0,
            permissionConsumedMinutes: permissionFromServer?.permissionConsumedMinutes ?? attendance.permissionConsumedMinutes ?? 0,
            permissionRemainingMinutes: permissionFromServer?.permissionRemainingMinutes ?? attendance.permissionRemainingMinutes ?? 0
        }
        : await calculateCombinedFine(
            attendance.punchIn,
            now,
            attendance.date,
            fineTemplate,
            staff,
            company,
            leaveForFine,
            {
                appPerDayNetSalary: data?.appPerDayNetSalary,
                appPerdayGrossSalary: data?.appPerdayGrossSalary
            },
            { attendanceId: attendance._id, appliedShiftId: attendance.appliedShiftId || appliedShiftId || null }
        );
    const lateFineAmount = Number(fineResult.lateFineAmount) || 0;
    const earlyFineAmount = Number(fineResult.earlyFineAmount) || 0;
    const totalFineAmount = lateFineAmount + earlyFineAmount;

    attendance.lateMinutes = fineResult.lateMinutes ?? attendance.lateMinutes ?? 0;
    attendance.earlyMinutes = fineResult.earlyMinutes ?? 0;
    attendance.fineHours =
        fineResult.fineHours ??
        ((Number(attendance.lateMinutes) || 0) + (Number(attendance.earlyMinutes) || 0));
    attendance.fineAmount = totalFineAmount;
    attendance.permissionLateMinutes = fineResult.permissionLateMinutes ?? 0;
    attendance.permissionEarlyMinutes = fineResult.permissionEarlyMinutes ?? 0;
    attendance.permissionApprovedMinutes = fineResult.permissionApprovedMinutes ?? 0;
    attendance.permissionConsumedMinutes = fineResult.permissionConsumedMinutes ?? 0;
    attendance.permissionRemainingMinutes = fineResult.permissionRemainingMinutes ?? 0;
    // For app punches, prefer app-calculated values so DB matches app formula/logs.
    if (
        !useAppProvidedFine &&
        source === 'app' &&
        isTruthyRequestBool(forceAppFine) &&
        (Number(fineResult.permissionConsumedMinutes) || 0) <= 0
    ) {
        if (hasExplicitAppFineNumeric(bodyLateMinutes)) {
            attendance.lateMinutes = Math.max(0, Math.round(Number(bodyLateMinutes)));
        }
        if (hasExplicitAppFineNumeric(bodyEarlyMinutes)) {
            attendance.earlyMinutes = Math.max(0, Math.round(Number(bodyEarlyMinutes)));
        }
        if (hasExplicitAppFineNumeric(bodyFineAmount)) {
            const serverFine = Number(totalFineAmount) || 0;
            const appFine = Math.max(0, Math.round(Number(bodyFineAmount) * 100) / 100);
            if (appFine > 0 || serverFine <= 0) {
                attendance.fineAmount = appFine;
            }
        }
        attendance.fineHours =
            (Number(attendance.lateMinutes) || 0) + (Number(attendance.earlyMinutes) || 0);
        console.log('[Fine STORE][CHECK-OUT][APP OVERRIDE]', {
            lateMinutes: attendance.lateMinutes,
            earlyMinutes: attendance.earlyMinutes,
            fineHours: attendance.fineHours,
            fineAmount: attendance.fineAmount
        });
    }
    console.log('[Fine STORE][CHECK-OUT]', {
        attendanceId: attendance._id?.toString?.() || null,
        lateMinutes: attendance.lateMinutes,
        earlyMinutes: attendance.earlyMinutes,
        fineHours: attendance.fineHours,
        lateFineAmount,
        earlyFineAmount,
        fineAmount: attendance.fineAmount
    });

    // Auto Half-Day: when the employee worked fewer minutes than a full day's required
    // working hours, classify the day as Half Day (payroll counts it as 0.5). Gated by the
    // company automationRules.autoMarkHalfDay flag. Days governed by an approved leave or an
    // existing Half Day status are left untouched (those are authoritative).
    const autoMarkHalfDayEnabled = company?.settings?.attendance?.automationRules?.autoMarkHalfDay === true;
    if (autoMarkHalfDayEnabled && !activeLeave && !isHalfDayStatus && attendance.punchIn && attendance.punchOut) {
        const { calculateWorkHoursFromShift } = require('../utils/leaveAttendanceHelper');
        const stType = (shiftTiming?.shiftType || 'standard').toString().toLowerCase();
        let requiredFullDayMin = null;
        if (stType === 'open' || stType === 'open shift') {
            const reqH = Number(shiftTiming?.workHours ?? shiftTiming?.openWorkHours);
            if (Number.isFinite(reqH) && reqH > 0) requiredFullDayMin = Math.round(reqH * 60);
        } else if (shiftTiming?.startTime && shiftTiming?.endTime) {
            const fullDayHours = calculateWorkHoursFromShift(shiftTiming.startTime, shiftTiming.endTime);
            if (Number.isFinite(fullDayHours) && fullDayHours > 0) requiredFullDayMin = Math.round(fullDayHours * 60);
        }
        const workedMin = Number(attendance.workHours) || 0;
        if (requiredFullDayMin && requiredFullDayMin > 0 && workedMin < requiredFullDayMin) {
            attendance.status = 'Half Day';
            console.log('[Auto Half-Day][CHECK-OUT] worked %s min < required %s min => status=Half Day (attendanceId=%s)',
                workedMin, requiredFullDayMin, attendance._id?.toString?.() || null);
        }
    }

    await attendance.save();

    if (deferCheckoutSelfie) {
        scheduleDeferredAttendanceSelfieUpload(
            attendance._id,
            selfie,
            req,
            companyIdForDefer,
            staff.name,
            'punchOutSelfie',
        );
    }

    console.log('[Attendance CHECK-OUT] saved:', {
        staffId: staff._id?.toString(),
        attendanceId: attendance._id?.toString(),
        date: attendance.date,
        punchIn: attendance.punchIn,
        punchOut: attendance.punchOut,
        lateMinutes: attendance.lateMinutes,
        earlyMinutes: attendance.earlyMinutes,
        workHours: attendance.workHours,
        overtimeMinutes: attendance.overtime,
        bufferTimeMinutes: attendance.bufferTime,
        overtimeAmount: attendance.overtimeAmount,
        overtimeEligible: staff.overtimeEligible === true,
        fineHours: attendance.fineHours,
        fineAmount: attendance.fineAmount,
    });

    // Include warnings in response if any
    const response = attendance.toObject ? attendance.toObject() : attendance;
    if (warnings.length > 0) {
        response.warnings = warnings;
    }

    console.log('[Attendance checkOut] success', {
        staffId: staff._id?.toString(),
        attendanceId: attendance._id?.toString(),
        punchIn: attendance.punchIn,
        punchOut: attendance.punchOut,
        ms: Date.now() - checkoutT0,
    });
    const userLat = latitude != null ? parseFloat(latitude) : (attendance.location?.punchOut?.latitude ?? attendance.location?.punchIn?.latitude ?? 0);
    const userLng = longitude != null ? parseFloat(longitude) : (attendance.location?.punchOut?.longitude ?? attendance.location?.punchIn?.longitude ?? 0);
    void Promise.allSettled([
        AttendanceLog.create({
            attendanceId: attendance._id,
            action: 'PUNCH_OUT',
            performedBy: staff._id,
            performedByName: staff.name || undefined,
            performedByEmail: staff.email || undefined,
            selfieUrl: attendance.punchOutSelfie || undefined,
            punchInDateTime: attendance.punchIn || undefined,
            punchOutDateTime: punchOutAt,
            punchInAddress: (attendance.location?.punchIn && buildAddressString(attendance.location.punchIn.address, attendance.location.punchIn.area, attendance.location.punchIn.city, attendance.location.punchIn.pincode)) || undefined,
            punchOutAddress: buildAddressString(address, area, city, pincode) || undefined,
            timestamp: now
        }),
        (userLat !== 0 || userLng !== 0)
            ? insertAttendanceTracking(staff._id, staff.name, userLat, userLng, 'out_of_office', 'checked_out', movementType, address, area, city, pincode)
            : Promise.resolve()
    ]);
    console.log('[Attendance processCheckOut] done', {
        ms: Date.now() - checkoutT0,
        attendanceId: attendance._id?.toString(),
    });
    res.json(response);
}

// @desc    Get Today's Attendance
// @route   GET /api/attendance/today
// @access  Private
const getTodayAttendance = async (req, res) => {
    try {
        if (!req.staff) return res.status(404).json({ message: 'Staff not found' });

        let queryDate = new Date();
        if (req.query.date) {
            const parts = req.query.date.split('-').map(Number);
            if (parts.length === 3) {
                // components: YYYY, MM-1, DD - create UTC date
                queryDate = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
            } else {
                queryDate = new Date(req.query.date);
            }
        }

        // Create Date object for start/end of day in UTC to ensure MongoDB ISODate format
        const year = queryDate.getUTCFullYear();
        const month = queryDate.getUTCMonth();
        const day = queryDate.getUTCDate();
        const startOfDay = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
        const endOfDay = new Date(Date.UTC(year, month, day, 23, 59, 59, 999));

        console.log('[Attendance getStatus] request', { staffId: req.staff._id?.toString(), date: req.query.date || 'today', queryDate: queryDate.toISOString?.() || queryDate });

        // Fetch attendance for the requested date (client's "today" or explicit date)
        let attendance = await Attendance.findOne({
            $or: [{ employeeId: req.staff._id }, { user: req.staff._id }],
            date: { $gte: startOfDay, $lte: endOfDay }
        }).lean();

        // If not found and client sent a date, try server's current date (timezone mismatch: stored date may be server UTC day)
        if (!attendance && req.query.date) {
            const serverNow = new Date();
            const sy = serverNow.getUTCFullYear();
            const sm = serverNow.getUTCMonth();
            const sd = serverNow.getUTCDate();
            const serverStart = new Date(Date.UTC(sy, sm, sd, 0, 0, 0, 0));
            const serverEnd = new Date(Date.UTC(sy, sm, sd, 23, 59, 59, 999));
            attendance = await Attendance.findOne({
                $or: [{ employeeId: req.staff._id }, { user: req.staff._id }],
                date: { $gte: serverStart, $lte: serverEnd }
            }).lean();
        }

        // Fetch Staff with Branch and Template
        const staff = await Staff.findById(req.staff._id)
            .populate('branchId')
            .populate('attendanceTemplateId')
            .populate('weeklyHolidayTemplateId')
            .populate('holidayTemplateId');

        // Fetch Company to get shift settings
        const Company = require('../models/Company');
        const company = await Company.findById(req.staff.businessId);

        const attendanceTemplateLeanEarly = await loadAttendanceTemplateForStaff(staff);

        // Branch Info (include status and geofence for app-side check-in/out validation)
        let branchInfo = null;
        if (staff.branchId) {
            const b = staff.branchId;
            const geofenceEnabled = b.geofence?.enabled === true;
            const lat = b.geofence?.latitude ?? b.latitude;
            const lng = b.geofence?.longitude ?? b.longitude;
            branchInfo = {
                name: b.branchName || b.name,
                latitude: lat,
                longitude: lng,
                radius: b.geofence?.radius ?? b.radius ?? 100,
                status: b.status || 'ACTIVE',
                geofence: {
                    enabled: geofenceEnabled,
                    latitude: lat,
                    longitude: lng,
                    radius: b.geofence?.radius ?? b.radius ?? 100,
                    locations: b.geofence?.locations
                }
            };
        }

        // Check for Leave - First check attendance record status, then check approved leave
        const Leave = require('../models/Leave');
        
        // Check if attendance record has status "On Leave"
        const attendanceStatusIsOnLeave = attendance && attendance.status === 'On Leave';
        
        // Check for approved leave from Leave collection
        const activeLeave = await Leave.findOne({
            employeeId: req.staff._id,
            status: { $regex: /^approved$/i },
            startDate: { $lte: endOfDay },
            endDate: { $gte: startOfDay }
        });
        
        const serverNow = new Date();
        // Use client's current time for half-day checks when provided (avoids server timezone issues)
        let now = serverNow;
        if (req.query.clientTime) {
            const clientDate = new Date(req.query.clientTime);
            if (!isNaN(clientDate.getTime())) {
                now = clientDate;
                console.log('[Attendance getStatus] using clientTime for half-day', { clientTime: req.query.clientTime, now: now.toISOString() });
            }
        }
        const isToday = queryDate.getUTCFullYear() === now.getUTCFullYear() &&
            queryDate.getUTCMonth() === now.getUTCMonth() &&
            queryDate.getUTCDate() === now.getUTCDate();
        
        console.log('[Attendance getStatus] Date comparison', {
            queryDate: queryDate.toISOString(),
            now: now.toISOString(),
            isToday,
            queryDateUTC: { year: queryDate.getUTCFullYear(), month: queryDate.getUTCMonth(), date: queryDate.getUTCDate() },
            nowUTC: { year: now.getUTCFullYear(), month: now.getUTCMonth(), date: now.getUTCDate() }
        });

        const { isCurrentlyInLeaveSession, isWithinSecondHalfEarlyLoginWindow, getLeaveMessageForUI, canCheckInWithHalfDayLeave, canCheckOutWithHalfDayLeave, getHalfDaySessionMessage, getShiftTimings, getBusinessTimezone } = require('../utils/leaveAttendanceHelper');
        // Case-insensitive: treat "half day", "Half Day", "HALF DAY" etc. as half-day leave (DB may store different casing)
        const isHalfDayLeaveType = (lt) => (lt || '').trim().toLowerCase() === 'half day';
        // Resolve session '1' or '2' from Leave/attendance (use halfDaySession first, then halfDayType, then session)
        const resolveSession = (l) => {
            const raw = l.session
                ?? (l.halfDaySession === 'First Half Day' ? '1' : l.halfDaySession === 'Second Half Day' ? '2' : null)
                ?? (l.halfDayType === 'First Half Day' ? '1' : l.halfDayType === 'Second Half Day' ? '2' : null);
            return raw != null ? String(raw).trim() : null;
        };
        const resolveHalfDayDisplay = (l) =>
            l.halfDaySession ?? l.halfDayType ?? (resolveSession(l) === '1' ? 'First Half Day' : resolveSession(l) === '2' ? 'Second Half Day' : null);
        const dbShiftTimingsForLeave = getShiftTimings(
            company,
            staff,
            queryDate,
            staff?.joiningDate,
            attendanceTemplateLeanEarly
        );
        const shiftStartForLeave = dbShiftTimingsForLeave.startTime || null;
        const shiftEndForLeave = dbShiftTimingsForLeave.endTime || null;
        const halfDaySettingsForLeave = dbShiftTimingsForLeave.halfDaySettings || null;
        const businessTimezone = getBusinessTimezone(company) || 'Asia/Kolkata';

        // Device local time HH:mm (24h) for half-day check when server Intl timezone is unreliable
        let clientCurrentMinutesOverride = null;
        if (req.query.clientLocalTime && typeof req.query.clientLocalTime === 'string') {
            const match = req.query.clientLocalTime.trim().match(/^(\d{1,2}):(\d{1,2})$/);
            if (match) {
                const h = parseInt(match[1], 10);
                const m = parseInt(match[2], 10);
                if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
                    clientCurrentMinutesOverride = h * 60 + m;
                }
            }
        }

        // If approved leave exists, it overrides any existing attendance status
        if (activeLeave) {
            const leaveStatus = isHalfDayLeaveType(activeLeave.leaveType) ? 'Half Day' : 'On Leave';
            const halfDaySessionVal = activeLeave.halfDaySession || activeLeave.halfDayType || (activeLeave.session === '1' ? 'First Half Day' : activeLeave.session === '2' ? 'Second Half Day' : null);
            const sessionVal = activeLeave.session || (activeLeave.halfDaySession === 'First Half Day' ? '1' : activeLeave.halfDaySession === 'Second Half Day' ? '2' : null) || (activeLeave.halfDayType === 'First Half Day' ? '1' : activeLeave.halfDayType === 'Second Half Day' ? '2' : null);
            if (attendance) {
                attendance.status = leaveStatus;
                if (isHalfDayLeaveType(activeLeave.leaveType) && (halfDaySessionVal || sessionVal)) {
                    attendance.halfDaySession = attendance.halfDaySession || halfDaySessionVal;
                    attendance.session = attendance.session || sessionVal;
                }
            } else {
                attendance = {
                    status: leaveStatus,
                    date: startOfDay,
                    employeeId: req.staff._id,
                    ...(isHalfDayLeaveType(activeLeave.leaveType) && { halfDaySession: halfDaySessionVal, session: sessionVal })
                };
            }
        }

        // Half-day: prefer approved Leave over attendance for which half (so "Second Half" leave shows as leave on second half, not first).
        const hasApprovedHalfDayLeave = activeLeave && isHalfDayLeaveType(activeLeave.leaveType);
        const hasAttendanceHalfDaySession = attendance && (attendance.halfDaySession === 'First Half Day' || attendance.halfDaySession === 'Second Half Day');
        const hasAttendanceHalfDay = attendance && (attendance.status === 'Half Day' || hasAttendanceHalfDaySession) && (attendance.halfDaySession || attendance.session);
        const attHalfDaySource = hasAttendanceHalfDay ? {
            session: attendance.session || (attendance.halfDaySession === 'First Half Day' ? '1' : attendance.halfDaySession === 'Second Half Day' ? '2' : null),
            halfDaySession: attendance.halfDaySession || (attendance.session === '1' ? 'First Half Day' : attendance.session === '2' ? 'Second Half Day' : null)
        } : null;
        // Prefer approved Leave so API and UI show correct "First Half" / "Second Half"; fall back to attendance when no leave.
        const halfDaySource = (hasApprovedHalfDayLeave ? activeLeave : null) || attHalfDaySource;
        
        console.log('[Attendance getStatus] Half-day source check', {
            hasApprovedHalfDayLeave,
            hasAttendanceHalfDay,
            activeLeaveType: activeLeave?.leaveType,
            attendanceStatus: attendance?.status,
            attHalfDaySession: attendance?.halfDaySession,
            attSession: attendance?.session,
            halfDaySourceExists: !!halfDaySource,
            halfDaySourceSession: halfDaySource?.session,
            halfDaySourceHalfDaySession: halfDaySource?.halfDaySession
        });

        // Normalize so helpers always get session + halfDaySession (Leave may have only halfDayType). Pass leaveType 'Half Day' so helpers recognize it.
        const halfDayLeaveForHelper = (halfDaySource && activeLeave && isHalfDayLeaveType(activeLeave.leaveType))
            ? {
                ...activeLeave,
                leaveType: 'Half Day',
                ...halfDaySource,
                session: halfDaySource.session ?? (halfDaySource.halfDayType === 'First Half Day' ? '1' : halfDaySource.halfDayType === 'Second Half Day' ? '2' : null) ?? resolveSession(halfDaySource),
                halfDaySession: halfDaySource.halfDaySession ?? halfDaySource.halfDayType ?? (resolveSession(halfDaySource) === '1' ? 'First Half Day' : resolveSession(halfDaySource) === '2' ? 'Second Half Day' : null)
            }
            : activeLeave;

        // isOnLeave = true only when there is an approved leave in Leave collection for this date; else false
        const isOnLeave = !!activeLeave;
        // For half-day, "currently in leave session" drives message and check-in/out; use client local time when provided
        const currentlyInLeaveSession = halfDaySource && isToday && isCurrentlyInLeaveSession(halfDayLeaveForHelper, now, shiftStartForLeave, shiftEndForLeave, businessTimezone, halfDaySettingsForLeave, clientCurrentMinutesOverride);
        // First Half Day leave: the employee works the SECOND half. Just before the second half begins
        // (within the secondHalfLoginGraceMinutes window) we must let them punch in even though the clock
        // is still inside the first (leave) half. In that window, do NOT treat it as a blocking leave
        // session — otherwise the app hides the punch card and shows "You are on leave - First Half".
        const earlySecondHalfLogin = halfDaySource && isToday && isWithinSecondHalfEarlyLoginWindow(halfDayLeaveForHelper, now, shiftStartForLeave, shiftEndForLeave, businessTimezone, halfDaySettingsForLeave, clientCurrentMinutesOverride);
        const inLeaveSessionBlocking = currentlyInLeaveSession && !earlySecondHalfLogin;
        let leaveMessage = (halfDaySource && isToday) ? getLeaveMessageForUI(halfDayLeaveForHelper, now, shiftStartForLeave, shiftEndForLeave, businessTimezone, halfDaySettingsForLeave) : (activeLeave && isToday ? getLeaveMessageForUI(activeLeave, now, shiftStartForLeave, shiftEndForLeave, businessTimezone, halfDaySettingsForLeave) : null);
        if (halfDaySource && isToday && inLeaveSessionBlocking) {
            const sessionNum = resolveSession(halfDaySource);
            leaveMessage = sessionNum === '1' ? 'You are on leave - First Half' : sessionNum === '2' ? 'You are on leave - Second Half' : leaveMessage;
        }

        // Half-day leave: session-based check-in/check-out allowed flags (from attendance.halfDaySession when present, else leave)
        let halfDayLeave = null;
        let checkInAllowed = true;
        let checkOutAllowed = true;
        
        console.log('[Attendance getStatus] Before half-day processing', {
            halfDaySourceExists: !!halfDaySource,
            isToday,
            defaultCheckInAllowed: checkInAllowed,
            defaultCheckOutAllowed: checkOutAllowed
        });
        
        if (halfDaySource) {
            const sessionNum = resolveSession(halfDaySource);
            const sessionStr = sessionNum || String(halfDaySource.session ?? '').trim();
            const halfDayDisplay = resolveHalfDayDisplay(halfDaySource);
            let halfDayMsg = getHalfDaySessionMessage(sessionNum, shiftStartForLeave, shiftEndForLeave, halfDaySettingsForLeave);
            if (isToday && inLeaveSessionBlocking) {
                halfDayMsg = sessionNum === '1' ? 'You are on leave - First Half' : sessionNum === '2' ? 'You are on leave - Second Half' : halfDayMsg;
            }
            halfDayLeave = {
                session: halfDaySource.session || (sessionNum || null),
                halfDaySession: halfDayDisplay,
                halfDayType: halfDayDisplay,
                message: halfDayMsg
            };
            if (isToday) {
                console.log('[Attendance getStatus] Processing half-day for today', {
                    isToday,
                    halfDayLeaveForHelper: halfDayLeaveForHelper ? {
                        leaveType: halfDayLeaveForHelper.leaveType,
                        session: halfDayLeaveForHelper.session,
                        halfDaySession: halfDayLeaveForHelper.halfDaySession
                    } : null,
                    now: now.toISOString(),
                    shiftStartForLeave,
                    shiftEndForLeave,
                    businessTimezone
                });
                
                // Second Half Day leave → check-in allowed only in first half (shift start → mid). First Half Day leave → check-in allowed only in second half (mid → shift end).
                const checkInResult = canCheckInWithHalfDayLeave(halfDayLeaveForHelper, now, shiftStartForLeave, shiftEndForLeave, businessTimezone, halfDaySettingsForLeave, dbShiftTimingsForLeave.gracePeriodMinutes);
                const checkOutResult = canCheckOutWithHalfDayLeave(halfDayLeaveForHelper, now, shiftStartForLeave, shiftEndForLeave, businessTimezone, halfDaySettingsForLeave);
                
                console.log('[Attendance getStatus] Validation results', {
                    checkInResult,
                    checkOutResult
                });
                
                checkInAllowed = checkInResult.allowed;
                checkOutAllowed = checkOutResult.allowed;
                // When user is currently in their leave half, never allow check-in/out (override any helper
                // result) — with exceptions for a First Half Day leave (employee works the SECOND half):
                //   • In the early second-half login window, OR
                //   • Anywhere in the first (leave) half: the employee is still allowed to punch in ahead of
                //     their working (second) half. This mirrors canCheckInWithHalfDayLeave (POST), which
                //     permits early check-in for a First Half Day leave until shift end; the fine/late logic
                //     handles the actual session timing. Check-out stays closed until the working half starts.
                if (inLeaveSessionBlocking) {
                    if (sessionNum === '1') {
                        // First Half Day leave: honor the check-in helper (allowed before shift end) so the
                        // employee can punch in early for the second half; keep check-out blocked.
                        checkInAllowed = checkInResult.allowed;
                        checkOutAllowed = false;
                    } else {
                        checkInAllowed = false;
                        checkOutAllowed = false;
                    }
                } else if (earlySecondHalfLogin) {
                    // Honor the check-in helper's verdict (allowed) but keep check-out closed until the
                    // working half actually starts.
                    checkOutAllowed = false;
                }
                console.log('[Attendance getStatus] Half-day leave', {
                    leaveId: activeLeave?._id,
                    halfDaySession: halfDayDisplay,
                    session: sessionNum,
                    sessionNum,
                    firstHalfLeave: sessionNum === '1',
                    secondHalfLeave: sessionNum === '2',
                    currentlyInLeaveSession,
                    earlySecondHalfLogin,
                    checkInAllowed,
                    checkOutAllowed,
                    leaveMessage: halfDayMsg,
                    shiftStartForLeave,
                    shiftEndForLeave,
                    businessTimezone
                });
            } else {
                console.log('[Attendance getStatus] Not today, skipping half-day validation', {
                    isToday,
                    queryDate: queryDate.toISOString(),
                    now: now.toISOString()
                });
            }
        } else if (activeLeave && isToday) {
            checkInAllowed = false;
            checkOutAllowed = false;
        }
        // For half-day: set leaveMessage and flags explicitly by current time
        // - In leave half (inLeaveSessionBlocking): "You are on leave - First/Second Half", checkInAllowed/checkOutAllowed = false
        // - In working half OR early second-half login window: session timing message + "Check-in/out allowed
        //   for your working half.", checkInAllowed/checkOutAllowed from helpers
        if (halfDayLeave && halfDayLeave.message && isToday) {
            if (inLeaveSessionBlocking) {
                const sessionNum = resolveSession(halfDaySource);
                leaveMessage = sessionNum === '1' ? 'You are on leave - First Half' : sessionNum === '2' ? 'You are on leave - Second Half' : halfDayLeave.message;
            } else {
                leaveMessage = halfDayLeave.message + '. Check-in/out allowed for your working half.';
            }
        } else if (halfDayLeave && halfDayLeave.message) {
            leaveMessage = leaveMessage || halfDayLeave.message;
            if (leaveMessage === 'Your leave request is approved. Enjoy your leave.') {
                leaveMessage = (checkInAllowed || checkOutAllowed)
                    ? halfDayLeave.message + '. Check-in/out allowed for your working half.'
                    : halfDayLeave.message;
            }
        }

        const resolvedAttendanceTemplateDoc = attendanceTemplateLeanEarly;
        const shiftAssigned = isShiftAssignedForStaff(company, staff, resolvedAttendanceTemplateDoc);
        const finalTemplate = resolvedAttendanceTemplateDoc
            ? normalizeTemplate(resolvedAttendanceTemplateDoc)
            : {};
        
        // Explicitly get shift timings and merge into finalTemplate
        const {
            shiftType: resolvedShiftType,
            openWorkHours: resolvedOpenWorkHours,
            startTime: resolvedShiftStartTime,
            endTime: resolvedShiftEndTime,
            gracePeriodMinutes: resolvedGracePeriodMinutes,
            effectiveShiftName: resolvedEffectiveShiftName,
            effectiveShiftId: resolvedEffectiveShiftId
        } = getShiftTimings(
            company,
            staff,
            queryDate,
            staff?.joiningDate,
            resolvedAttendanceTemplateDoc
        );

        finalTemplate.shiftType = resolvedShiftType || finalTemplate.shiftType;
        if (resolvedEffectiveShiftName) {
            finalTemplate.shiftName = resolvedEffectiveShiftName;
        }
        finalTemplate.openWorkHours = resolvedOpenWorkHours || finalTemplate.openWorkHours;
        // Company embed: do not fall back to attendance template when window is unknown (null both).
        const rs = resolvedShiftType ? String(resolvedShiftType).toLowerCase().trim() : '';
        if (rs === 'open' || rs === 'open shift') {
            finalTemplate.shiftStartTime = null;
            finalTemplate.shiftEndTime = null;
            if (resolvedGracePeriodMinutes !== undefined && resolvedGracePeriodMinutes !== null) {
                finalTemplate.gracePeriodMinutes = resolvedGracePeriodMinutes;
            }
        } else {
            if (resolvedShiftStartTime && resolvedShiftEndTime) {
                finalTemplate.shiftStartTime = resolvedShiftStartTime;
                finalTemplate.shiftEndTime = resolvedShiftEndTime;
            } else {
                finalTemplate.shiftStartTime = null;
                finalTemplate.shiftEndTime = null;
            }
            if (resolvedGracePeriodMinutes !== undefined && resolvedGracePeriodMinutes !== null) {
                finalTemplate.gracePeriodMinutes = resolvedGracePeriodMinutes;
            }
        }

        // Merge shift timings from company settings into template only when shift is assigned
        if (shiftAssigned) {
            const stLeave = (dbShiftTimingsForLeave.shiftType || 'standard').toString().toLowerCase();
            finalTemplate.shiftType = dbShiftTimingsForLeave.shiftType || 'standard';
            if (stLeave === 'open' || stLeave === 'open shift') {
                finalTemplate.openWorkHours = dbShiftTimingsForLeave.openWorkHours;
                finalTemplate.shiftStartTime = null;
                finalTemplate.shiftEndTime = null;
                if (dbShiftTimingsForLeave.gracePeriodMinutes !== undefined) {
                    finalTemplate.gracePeriodMinutes = dbShiftTimingsForLeave.gracePeriodMinutes;
                }
            } else {
                if (dbShiftTimingsForLeave.startTime && dbShiftTimingsForLeave.endTime) {
                    finalTemplate.shiftStartTime = dbShiftTimingsForLeave.startTime;
                    finalTemplate.shiftEndTime = dbShiftTimingsForLeave.endTime;
                } else {
                    finalTemplate.shiftStartTime = null;
                    finalTemplate.shiftEndTime = null;
                }
                if (dbShiftTimingsForLeave.gracePeriodMinutes !== undefined) {
                    finalTemplate.gracePeriodMinutes = dbShiftTimingsForLeave.gracePeriodMinutes;
                }
            }
        }

        {
            const shiftNameForLog = (resolvedEffectiveShiftName
                || finalTemplate.shiftName
                || finalTemplate.name
                || '(unnamed)').toString().trim();
            const calY = queryDate.getUTCFullYear();
            const calM = queryDate.getUTCMonth() + 1;
            const calD = queryDate.getUTCDate();
            const attendanceDateStr = `${calY}-${String(calM).padStart(2, '0')}-${String(calD).padStart(2, '0')}`;
            const stLower = (finalTemplate.shiftType || '').toString().toLowerCase();
            const isOpenTpl = stLower === 'open' || stLower === 'open shift';
            const startLog = finalTemplate.shiftStartTime != null && finalTemplate.shiftStartTime !== ''
                ? finalTemplate.shiftStartTime
                : (isOpenTpl ? '(open — no fixed start)' : '(none)');
            const endLog = finalTemplate.shiftEndTime != null && finalTemplate.shiftEndTime !== ''
                ? finalTemplate.shiftEndTime
                : (isOpenTpl ? '(open — no fixed end)' : '(none)');
            const shiftIdForLog = resolvedEffectiveShiftId || '(none)';
            console.log(
                'shift start time******',
                startLog,
                '| shiftName=',
                shiftNameForLog,
                '| shiftId=',
                shiftIdForLog,
                '| attendanceDate=',
                attendanceDateStr,
                '| staffId=',
                String(req.staff._id)
            );
            console.log(
                'shift end time******',
                endLog,
                '| shiftName=',
                shiftNameForLog,
                '| shiftId=',
                shiftIdForLog,
                '| attendanceDate=',
                attendanceDateStr,
                '| staffId=',
                String(req.staff._id)
            );
        }
        
        let isWeeklyOff = false;
        const holidayTemplate = await getHolidayTemplateForStaff(staff);
        const holidayInfo = getHolidayForDate(holidayTemplate, queryDate);
        const dayOfWeek = queryDate.getDay();
        const weekOffConfig = await getWeekOffConfigForStaff(staff, company);
        if (weekOffConfig.weeklyOffPattern === 'oddEvenSaturday') {
            if (dayOfWeek === 0) isWeeklyOff = true;
            else if (dayOfWeek === 6 && isOddEvenSaturdayWeeklyOff(queryDate.getFullYear(), queryDate.getMonth(), queryDate.getDate(), 'local')) isWeeklyOff = true;
        } else {
            isWeeklyOff = weekOffConfig.weeklyHolidays.some(h => h.day === dayOfWeek);
        }

        // If this date is a week-off (or we're checking), see if it's an alternate work date for this employee
        // (compensation: employee took week-off or comp-off on another day and will work on this date instead)
        let isAlternateWorkDate = false;
        const alternateWorkRecord = await Attendance.findOne({
            $or: [{ employeeId: req.staff._id }, { user: req.staff._id }],
            alternateWorkDate: { $gte: startOfDay, $lte: endOfDay },
            compensationType: { $in: ['weekOff', 'compOff'] }
        }).lean();
        if (alternateWorkRecord) isAlternateWorkDate = true;

        // Today is the "off" day when employee has compensationType weekOff or compOff (they work on alternateWorkDate instead)
        const isCompensationWeekOff = !!(attendance && attendance.compensationType === 'weekOff');
        const isCompensationCompOff = !!(attendance && attendance.compensationType === 'compOff');
        if (isCompensationWeekOff || isCompensationCompOff) {
            checkInAllowed = false;
            checkOutAllowed = false;
        }
        // Paid leave day: On Leave + isPaidLeave, not comp off/week off - block check-in/check-out
        const compType = (attendance?.compensationType || '').toString().toLowerCase();
        const isPaidLeaveToday = !!(attendance && (attendance.status === 'On Leave' || String(attendance.status || '').toLowerCase() === 'on leave') &&
            attendance.isPaidLeave === true &&
            compType !== 'weekoff' && compType !== 'compoff');
        if (isPaidLeaveToday) {
            checkInAllowed = false;
            checkOutAllowed = false;
        }

        console.log('[Attendance getStatus] response', {
            staffId: req.staff._id?.toString(),
            date: req.query.date || 'today',
            isOnLeave,
            hasAttendance: !!attendance,
            attendanceStatus: attendance?.status ?? null,
            checkInAllowed,
            checkOutAllowed,
            hasHalfDayLeave: !!halfDayLeave
        });

        // For half-day leave always send session message (never generic "Enjoy your leave"); for full-day use generic when no message
        const finalLeaveMessage = (halfDayLeave && halfDayLeave.message)
            ? (leaveMessage && leaveMessage !== 'Your leave request is approved. Enjoy your leave.' ? leaveMessage : halfDayLeave.message)
            : (leaveMessage || (isOnLeave ? 'Your leave request is approved. Enjoy your leave.' : null));

        const hasPunchIn = !!(attendance && attendance.punchIn);
        const hasPunchOut = !!(attendance && attendance.punchOut);
        const checkedIn = hasPunchIn && !hasPunchOut;

        /** Full embedded shift rows for the app to resolve [appliedShiftId] (template payload may omit or truncate). */
        const businessShifts =
            company &&
            company.settings &&
            company.settings.attendance &&
            Array.isArray(company.settings.attendance.shifts)
                ? JSON.parse(JSON.stringify(company.settings.attendance.shifts))
                : null;

        console.log('[API][GET /api/attendance/today] template.shiftTimings', {
            staffId: req.staff._id?.toString(),
            queryDate: req.query.date || 'today',
            shiftType: finalTemplate.shiftType ?? null,
            shiftStartTime: finalTemplate.shiftStartTime ?? finalTemplate.startTime ?? null,
            shiftEndTime: finalTemplate.shiftEndTime ?? finalTemplate.endTime ?? null,
            openWorkHours: finalTemplate.openWorkHours ?? null,
            shiftName: finalTemplate.shiftName ?? finalTemplate.name ?? null,
            shiftAssigned
        });

        res.json({
            data: attendance,
            branch: branchInfo,
            template: finalTemplate,
            businessShifts,
            shiftAssigned,
            isOnLeave: isOnLeave,
            leaveMessage: finalLeaveMessage,
            leaveInfo: activeLeave,
            halfDayLeave,
            checkInAllowed,
            checkOutAllowed,
            isHoliday: !!holidayInfo,
            holidayInfo: holidayInfo,
            isWeeklyOff: isWeeklyOff,
            weeklyOffPattern: weekOffConfig.weeklyOffPattern,
            isAlternateWorkDate: isAlternateWorkDate,
            isCompensationWeekOff: isCompensationWeekOff,
            isCompensationCompOff: isCompensationCompOff,
            isPaidLeaveToday: isPaidLeaveToday,
            hasPunchIn,
            hasPunchOut,
            checkedIn
        });
    } catch (error) {
        console.error('[Attendance getStatus] error', error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// Helper: enrich attendance record with half-day leave details from Leaves collection
const enrichWithLeaveDetails = async (attendanceList, staffId) => {
    const Leave = require('../models/Leave');
    // Each half-day record needs its matching approved Leave. This used to await a
    // findOne() per record inside a sequential for-loop (N+1: K half-day rows = K
    // serial round-trips). Map to concurrent lookups so they overlap; Promise.all
    // preserves input order. Full days do no DB work.
    return Promise.all(attendanceList.map(async (doc) => {
        const plain = doc.toObject ? doc.toObject() : { ...doc };
        const isHalfDay = (plain.status === 'Half Day' || (plain.leaveType && String(plain.leaveType).toLowerCase() === 'half day'));
        if (!(isHalfDay && plain.date)) return plain;

        const attDate = new Date(plain.date);
        // Create Date object for start/end of day in UTC to ensure MongoDB ISODate format
        const year = attDate.getUTCFullYear();
        const month = attDate.getUTCMonth();
        const day = attDate.getUTCDate();
        const startOfDay = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
        const endOfDay = new Date(Date.UTC(year, month, day, 23, 59, 59, 999));
        const leave = await Leave.findOne({
            employeeId: plain.employeeId || staffId,
            leaveType: 'Half Day',
            status: { $regex: /^approved$/i },
            startDate: { $lte: endOfDay },
            endDate: { $gte: startOfDay }
        }).populate('approvedBy', 'name email').lean();
        if (leave) {
            plain.leaveDetails = {
                session: leave.session || null,
                leaveType: leave.leaveType,
                startDate: leave.startDate,
                endDate: leave.endDate,
                status: leave.status,
                reason: leave.reason,
                approvedAt: leave.approvedAt || null,
                approvedBy: leave.approvedBy ? { name: leave.approvedBy.name || null, email: leave.approvedBy.email || null } : null
            };
        }
        return plain;
    }));
};

// @desc    Get Attendance History
const getAttendanceHistory = async (req, res) => {
    try {
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 10;
        const skip = (page - 1) * limit;

        const query = {
            // Query either employeeId OR user field to catch all records
            $or: [
                { employeeId: req.staff._id },
                { user: req.staff._id }
            ]
        };

        if (req.query.date) {
            const d = new Date(req.query.date);
            const start = new Date(d.setHours(0, 0, 0, 0));
            const end = new Date(d.setHours(23, 59, 59, 999));
            query.date = { $gte: start, $lte: end };
        }

        const attendance = await Attendance.find(query)
            .sort({ date: -1 })
            .skip(skip)
            .limit(limit)
            .lean();

        const total = await Attendance.countDocuments(query);
        const data = await enrichWithLeaveDetails(attendance, req.staff._id);

        res.json({
            data,
            pagination: {
                page, limit, total, pages: Math.ceil(total / limit)
            }
        });

    } catch (error) {
        console.error(error); // Log error
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Employee attendance in a date range (same collection/query shape as month view; used by web salary overview)
// @route   GET /api/attendance/employee/:employeeId
// @access  Private — only own staff id
const getEmployeeAttendance = async (req, res) => {
    try {
        const { employeeId } = req.params;
        const { startDate, endDate, page = 1, limit = 100 } = req.query;

        if (!req.staff) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        if (String(employeeId) !== String(req.staff._id)) {
            return res.status(403).json({ success: false, message: 'Forbidden' });
        }
        if (!startDate || !endDate) {
            return res.status(400).json({ success: false, message: 'startDate and endDate are required' });
        }

        const parseYmd = (ymd) => {
            const parts = String(ymd).split('-').map(Number);
            if (parts.length !== 3 || parts.some((n) => Number.isNaN(n))) return null;
            const [y, m, d] = parts;
            return new Date(y, m - 1, d);
        };
        const start = parseYmd(startDate);
        const end = parseYmd(endDate);
        if (!start || !end) {
            return res.status(400).json({ success: false, message: 'Invalid startDate or endDate' });
        }
        start.setHours(0, 0, 0, 0);
        end.setHours(23, 59, 59, 999);

        const query = {
            $or: [
                { employeeId: req.staff._id },
                { user: req.staff._id }
            ],
            date: { $gte: start, $lte: end }
        };

        const p = Math.max(1, parseInt(page, 10) || 1);
        const l = Math.min(500, Math.max(1, parseInt(limit, 10) || 100));
        const skip = (p - 1) * l;

        const attendanceRaw = await Attendance.find(query)
            .sort({ date: 1 })
            .skip(skip)
            .limit(l)
            .lean();

        const total = await Attendance.countDocuments(query);
        const attendance = await enrichWithLeaveDetails(attendanceRaw, req.staff._id);

        return res.json({
            success: true,
            data: {
                attendance,
                pagination: {
                    page: p,
                    limit: l,
                    total,
                    pages: Math.ceil(total / l) || 0
                }
            }
        });
    } catch (error) {
        console.error('[getEmployeeAttendance]', error);
        return res.status(500).json({ success: false, message: 'Server Error' });
    }
};

const getMonthAttendance = async (req, res) => {
    try {
        const { year, month } = req.query;
        if (!year || !month) {
            return res.status(400).json({ message: 'Year and Month are required' });
        }

        const __monthT0 = Date.now();
        const startOfMonth = new Date(year, month - 1, 1);
        const endOfMonth = new Date(year, month, 0, 23, 59, 59, 999);

        // Models/helpers used below — required up-front so the reads can be batched.
        const Company = require('../models/Company');
        const Staff = require('../models/Staff');
        const Leave = require('../models/Leave');
        const { getRecordFineAmount } = require('./payrollController');
        const { getEffectiveFineConfig } = require('../utils/fineCalculationHelper');
        const { getShiftTimings, calculateWorkHoursFromShift, getBusinessTimezone } = require('../utils/leaveAttendanceHelper');

        // Balance the load: these reads are independent of each other, so issue them on one concurrent
        // wave instead of a chain of sequential awaits (previously Attendance -> Company -> Staff ->
        // Staff(populate) -> stats -> Leave, six serial round-trips). Collapsing them is what lets the
        // calendar populate on the first tap instead of lagging behind / appearing to need a second click.
        // staffDoc is fetched once with both +salary and the calendar template populates (previously this
        // was two separate Staff.findById calls for the same _id).
        const [attendanceRaw, companyForFine, staffDoc, leaves, alternateWorkRecords] = await Promise.all([
            Attendance.find({
                $or: [
                    { employeeId: req.staff._id },
                    { user: req.staff._id }
                ],
                date: { $gte: startOfMonth, $lte: endOfMonth }
            }).sort({ date: 1 }).lean(),
            Company.findById(req.staff.businessId).lean(),
            Staff.findById(req.staff._id)
                .select('+salary')
                .populate('weeklyHolidayTemplateId')
                .populate('holidayTemplateId')
                .lean(),
            Leave.find({
                employeeId: req.staff._id,
                status: { $regex: /^approved$/i },
                $or: [
                    { startDate: { $gte: startOfMonth, $lte: endOfMonth } },
                    { endDate: { $gte: startOfMonth, $lte: endOfMonth } },
                    { startDate: { $lte: startOfMonth }, endDate: { $gte: endOfMonth } }
                ]
            }),
            // Alternate work dates (compensation week-off / comp-off) — independent of the
            // other reads, so it joins the same concurrent wave instead of a later serial await.
            Attendance.find({
                $or: [{ employeeId: req.staff._id }, { user: req.staff._id }],
                compensationType: { $in: ['weekOff', 'compOff'] },
                alternateWorkDate: { $gte: startOfMonth, $lte: endOfMonth }
            }).select('alternateWorkDate').lean()
        ]);

        // Enrich records that have fineHours/lateMinutes but no fineAmount (e.g. Excel import) using payroll fine formula
        const businessTz = getBusinessTimezone(companyForFine);
        const staffWithSalary = staffDoc;
        const staffForCalendar = staffDoc;
        const fineConfig = companyForFine ? getEffectiveFineConfig(companyForFine) : null;

        // Calendar template + week-off config — needed for the calendar output below AND to derive the
        // full-month working-day count used as the daily-salary (fine) divisor. Fetch the two
        // independent reads concurrently.
        const [holidayTemplate, weekOffConfig] = await Promise.all([
            getHolidayTemplateForStaff(staffForCalendar || req.staff),
            getWeekOffConfigForStaff(staffForCalendar || req.staff, companyForFine),
        ]);
        const holidays = getHolidaysForMonth(holidayTemplate, year, month);
        const weeklyOffPattern = weekOffConfig.weeklyOffPattern;
        const weeklyHolidays = weekOffConfig.weeklyHolidays;

        // Full-month working days = days in month − week-offs − holidays (whole month, no today/joining
        // cap). Computed locally from data already in hand. This used to come from
        // calculateAttendanceStats(), which re-fetched Attendance, Staff, Company, the week-off config
        // and the holiday template all over again (~5 duplicate DB reads + extra day-loops + another
        // Leave.find) purely to produce this one divisor — the main reason this endpoint loaded slowly.
        // Formula mirrors payrollController.calculateAttendanceStats' workingDaysFullMonth.
        const daysInMonthForSalary = new Date(year, month, 0).getDate();
        let weeklyOffDaysFull = 0;
        let holidaysFull = 0;
        for (let day = 1; day <= daysInMonthForSalary; day++) {
            const dow = new Date(year, month - 1, day).getDay();
            if (holidays.some(h => new Date(h.date).getDate() === day)) {
                holidaysFull++;
                continue;
            }
            let isWoff = false;
            if (weeklyOffPattern === 'oddEvenSaturday') {
                if (dow === 0) isWoff = true;
                else if (dow === 6 && isOddEvenSaturdayWeeklyOff(year, month - 1, day, 'local')) isWoff = true;
            } else {
                isWoff = weeklyHolidays.some(h => h.day === dow);
            }
            if (isWoff) weeklyOffDaysFull++;
        }
        const workingDaysFullMonth = daysInMonthForSalary - weeklyOffDaysFull - holidaysFull;

        let dailySalaryForEnrich = 0;
        try {
            const thisMonthWorkingDays = workingDaysFullMonth;
            if (thisMonthWorkingDays > 0 && staffWithSalary && staffWithSalary.salary) {
                const s = staffWithSalary.salary;
                const gf = (s.basicSalary || 0) + (s.dearnessAllowance || 0) + (s.houseRentAllowance || 0) + (s.specialAllowance || 0);
                const epf = (s.employerPFRate || 0) / 100 * (s.basicSalary || 0);
                const eesi = (s.employerESIRate || 0) / 100 * gf;
                const gross = gf + epf + eesi;
                const empPF = (s.employeePFRate || 0) / 100 * (s.basicSalary || 0);
                const empESI = (s.employeeESIRate || 0) / 100 * gross;
                dailySalaryForEnrich = (gross - empPF - empESI) / thisMonthWorkingDays;
            }
        } catch (e) {
            console.warn('[getMonthAttendance] Could not compute daily salary for fine enrichment:', e?.message);
        }

        for (const doc of attendanceRaw) {
            // Fine enrichment is supplementary to the calendar (it only sets
            // doc.fineAmount). A throw here — e.g. a record with an odd shift config,
            // a bad date, or missing salary — must NOT take down the whole month
            // response, which would leave the app's calendar blank/colorless. Guard
            // per-record so one bad row is skipped instead of 500-ing the endpoint.
            try {
                const shiftTimings = companyForFine && staffWithSalary ? getShiftTimings(companyForFine, staffWithSalary, doc.date ? new Date(doc.date) : new Date(), staffWithSalary?.joiningDate) : {};
                const shiftHours = Math.max(0, calculateWorkHoursFromShift(shiftTimings.startTime || '09:30', shiftTimings.endTime || '18:30') || 9);
                const hasFineMinutes = (Number(doc.fineHours) || 0) > 0 || (Number(doc.lateMinutes) || 0) > 0;
                const status = (doc.status || '').trim().toLowerCase();
                const isEligible = status === 'present' || status === 'approved' || (doc.leaveType || '').trim().toLowerCase() === 'half day';
                if (hasFineMinutes && isEligible && !(Number(doc.fineAmount) > 0)) {
                    const amount = getRecordFineAmount(doc, dailySalaryForEnrich, shiftHours, fineConfig);
                    if (amount > 0) doc.fineAmount = amount;
                }
            } catch (fineErr) {
                console.warn('[getMonthAttendance] fine enrichment skipped for a record:', fineErr?.message);
            }
        }

        // Leave-detail enrichment is needed for leaveType display, but if it throws
        // (e.g. a malformed leave record) the calendar should still render with the
        // raw attendance rows rather than failing the entire request.
        let attendance;
        try {
            attendance = await enrichWithLeaveDetails(attendanceRaw, req.staff._id);
        } catch (leaveErr) {
            console.warn('[getMonthAttendance] enrichWithLeaveDetails failed, using raw records:', leaveErr?.message);
            attendance = attendanceRaw;
        }

        // holidayTemplate / holidays / weekOffConfig (weeklyOffPattern, weeklyHolidays) were resolved
        // up-front in the concurrent wave above and reused here — no second round-trip.

        // Stats calculation
        const totalDaysInMonth = new Date(year, month, 0).getDate();

        // Cap at today: working days and absent count only for dates up to today (same as dashboard/payroll)
        const now = new Date();
        const currentYear = now.getFullYear();
        const currentMonth = now.getMonth() + 1;
        const currentDay = now.getDate();
        let lastDayToCount = totalDaysInMonth;
        if (Number(year) > currentYear || (Number(year) === currentYear && Number(month) > currentMonth)) {
            lastDayToCount = 0;
        } else if (Number(year) === currentYear && Number(month) === currentMonth) {
            lastDayToCount = currentDay;
        }

        // Date of Joining: nothing exists before the employee joined, so days before the
        // joining date must not be counted (working days) or marked absent/week-off/holiday.
        // firstCountableDay is the first day of THIS month that is on/after the joining date.
        let firstCountableDay = 1;
        const joiningDateRaw = staffWithSalary?.joiningDate || staffForCalendar?.joiningDate;
        if (joiningDateRaw) {
            const joinD = new Date(joiningDateRaw);
            if (!Number.isNaN(joinD.getTime())) {
                const joinYear = joinD.getFullYear();
                const joinMonth = joinD.getMonth() + 1;
                if (Number(year) < joinYear || (Number(year) === joinYear && Number(month) < joinMonth)) {
                    // Entire requested month precedes the joining month → nothing countable.
                    firstCountableDay = totalDaysInMonth + 1;
                } else if (Number(year) === joinYear && Number(month) === joinMonth) {
                    firstCountableDay = joinD.getDate();
                }
            }
        }

        let workingDays = 0;
        let weekOffs = 0;
        let holidaysCount = 0;
        let weekOffDates = [];

        // Loop for stats - only for days firstCountableDay..lastDayToCount (so days before the
        // joining date and future days are not counted as working/absent)
        for (let d = firstCountableDay; d <= lastDayToCount; d++) {
            const date = new Date(year, month - 1, d);
            date.setHours(0, 0, 0, 0);

            const dayOfWeek = date.getDay();
            let isWeekOff = false;

            if (weeklyOffPattern === 'oddEvenSaturday') {
                if (dayOfWeek === 0) isWeekOff = true;
                else if (dayOfWeek === 6 && isOddEvenSaturdayWeeklyOff(year, month - 1, d, 'local')) isWeekOff = true;
            } else {
                isWeekOff = weeklyHolidays.some(h => h.day === dayOfWeek);
            }

            if (isWeekOff) {
                weekOffs++;
            } else {
                const isHoliday = holidays.some(h => {
                    const hd = new Date(h.date);
                    return hd.getDate() === d;
                });

                if (isHoliday) holidaysCount++;
                else workingDays++;
            }
        }

        // Separate loop for weekOffDates (full month for calendar, but not before the joining date)
        for (let d = firstCountableDay; d <= totalDaysInMonth; d++) {
            // Create date in local timezone for day of week calculation
            const date = new Date(year, month - 1, d);
            const dayOfWeek = date.getDay();
            let isWeekOff = false;

            if (weeklyOffPattern === 'oddEvenSaturday') {
                if (dayOfWeek === 0) {
                    isWeekOff = true; // All Sundays are week off
                } else if (dayOfWeek === 6 && isOddEvenSaturdayWeeklyOff(year, month - 1, d, 'local')) {
                    isWeekOff = true; // Even Saturdays are week off
                }
            } else {
                // Standard pattern: Check weeklyHolidays array
                isWeekOff = weeklyHolidays.some(h => h.day === dayOfWeek);
            }

            if (isWeekOff) {
                // Use UTC methods to get consistent date string
                const dateStr = `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
                weekOffDates.push(dateStr);
            }
        }

        // Helper function to format date string consistently (YYYY-MM-DD) in server local time
        const formatDateString = (dateObj) => {
            const d = new Date(dateObj);
            const year = d.getFullYear();
            const month = String(d.getMonth() + 1).padStart(2, '0');
            const day = String(d.getDate()).padStart(2, '0');
            return `${year}-${month}-${day}`;
        };

        /** Calendar yyyy-MM-dd for an instant in the **business timezone** (e.g. IST).
         *  e.g. 2026-03-16T18:30:00.000Z → 2026-03-17 in Asia/Kolkata (midnight boundary).
         *  If Intl/timezone data fails on the host (seen on some Windows Node builds), use fixed +5:30 for India. */
        const formatAttendanceCalendarDay = (dateObj) => {
            const d = new Date(dateObj);
            const tryTz = (zone) => {
                if (!zone || !String(zone).trim()) return null;
                try {
                    const parts = new Intl.DateTimeFormat('en-CA', {
                        timeZone: zone.trim(),
                        year: 'numeric',
                        month: '2-digit',
                        day: '2-digit'
                    }).formatToParts(d);
                    const y = parts.find(p => p.type === 'year')?.value;
                    const m = parts.find(p => p.type === 'month')?.value;
                    const day = parts.find(p => p.type === 'day')?.value;
                    if (y && m && day) {
                        return `${y}-${m.padStart(2, '0')}-${day.padStart(2, '0')}`;
                    }
                } catch (e) { /* try next */ }
                return null;
            };
            const primaryTz = (businessTz && String(businessTz).trim()) || 'Asia/Kolkata';
            let out = tryTz(primaryTz);
            if (!out && primaryTz !== 'Asia/Kolkata') {
                out = tryTz('Asia/Kolkata');
            }
            if (out) {
                return out;
            }
            const z = primaryTz;
            if (z === 'Asia/Kolkata' || z === 'Asia/Calcutta') {
                const istMs = d.getTime() + 330 * 60 * 1000;
                const u = new Date(istMs);
                return `${u.getUTCFullYear()}-${String(u.getUTCMonth() + 1).padStart(2, '0')}-${String(u.getUTCDate()).padStart(2, '0')}`;
            }
            const u = new Date(dateObj);
            return `${u.getUTCFullYear()}-${String(u.getUTCMonth() + 1).padStart(2, '0')}-${String(u.getUTCDate()).padStart(2, '0')}`;
        };

        // Create a set of dates that have attendance records (business-calendar day)
        const attendanceDateSet = new Set();
        attendance.forEach(a => {
            const dateStr = formatAttendanceCalendarDay(a.date);
            attendanceDateSet.add(dateStr);
        });

        // Create a set of holiday dates
        const holidayDateSet = new Set();
        holidays.forEach(h => {
            const dateStr = formatDateString(h.date);
            holidayDateSet.add(dateStr);
        });

        // Leaves for the month already fetched in the concurrent wave above (variable: leaves).
        const leaveDateSet = new Set();
        leaves.forEach(leave => {
            let curr = new Date(leave.startDate);
            const end = new Date(leave.endDate);
            while (curr <= end) {
                if (curr >= startOfMonth && curr <= endOfMonth) {
                    leaveDateSet.add(formatDateString(curr));
                }
                curr.setDate(curr.getDate() + 1);
            }
        });

        // Week-off dates for calendar: always use full template-based list so that week-off always
        // displays as week-off (not as leave). Alternate work dates are sent separately and the
        // frontend shows those as working days (not violet).
        // (Previously we filtered out week-off dates that had attendance, which caused week-off
        // days with "On Leave" to show as leave instead of week off.)

        // Calculate absent dates: working days without attendance records
        const absentDates = [];
        const presentDates = [];
        const holidayDates = [];
        const leaveDates = Array.from(leaveDateSet);

        // Today in business timezone (string compare yyyy-MM-dd)
        const todayStr = formatAttendanceCalendarDay(new Date());

        for (let d = firstCountableDay; d <= totalDaysInMonth; d++) {
            // Create date string directly in YYYY-MM-DD format (avoids timezone issues)
            const dateStr = `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
            // Create date object for day of week calculation (using local time for day calculation)
            const date = new Date(year, month - 1, d);
            const dayOfWeek = date.getDay();

            // PRIORITY 1: Check if it's a leave day (Approved leave overrides everything)
            if (leaveDateSet.has(dateStr)) {
                // If there's an attendance record, we might want to override its status in the response
                // But leaveDates is already being populated and returned.
                // We should ensure this date is NOT in presentDates or absentDates.
                continue;
            }

            // Check if attendance exists - attendance takes precedence over week off/holiday (but not over leave)
            if (attendanceDateSet.has(dateStr)) {
                // Find the attendance record to get status (match by UTC calendar date)
                const attRecord = attendance.find(a => {
                    const attDateStr = formatAttendanceCalendarDay(a.date);
                    return attDateStr === dateStr;
                });
                if (attRecord) {
                    const status = (attRecord.status || '').trim().toLowerCase();
                    if (status === 'present' || status === 'approved') {
                        presentDates.push(dateStr);
                    } else if (status === 'absent' || status === 'pending' || status === 'rejected') {
                        // So calendar (dashboard + attendance history) can highlight these dates as red
                        absentDates.push(dateStr);
                    }
                }
                // If attendance exists, skip further checks (attendance overrides week off/holiday)
                continue;
            }

            // Check if it's a holiday (only if no attendance and not on leave)
            const isHoliday = holidayDateSet.has(dateStr);
            if (isHoliday) {
                holidayDates.push(dateStr);
                continue;
            }

            // Check if it's a week off (only if no attendance, holiday or leave)
            let isWeekOff = false;

            if (weeklyOffPattern === 'oddEvenSaturday') {
                if (dayOfWeek === 0) {
                    isWeekOff = true; // All Sundays are week off
                } else if (dayOfWeek === 6 && isOddEvenSaturdayWeeklyOff(year, month - 1, d, 'local')) {
                    isWeekOff = true; // Even Saturdays are week off
                }
            } else {
                isWeekOff = weeklyHolidays.some(h => h.day === dayOfWeek);
            }
            
            // IMPORTANT: Sundays (day 0) are ALWAYS week off, regardless of configuration
            if (dayOfWeek === 0) {
                isWeekOff = true;
            }

            // Skip week offs (only if no attendance record exists)
            if (isWeekOff) {
                continue;
            }

            // If we reach here, it's a working day without attendance = absent
            // BUT: Never mark Sundays as absent
            if (dayOfWeek === 0) {
                continue;
            }

            // Also: Never mark future dates as absent (only up to today)
            if (dateStr > todayStr) {
                continue;
            }
            
            absentDates.push(dateStr);
        }

        // Dates in this month that are alternate work dates for this employee (compensation week-off or
        // comp-off: they work on these days). alternateWorkRecords fetched in the concurrent wave above.
        const alternateWorkDatesInMonth = alternateWorkRecords.map(r => formatDateString(r.alternateWorkDate)).filter(Boolean);

        // Attach AttendanceLog rows to each attendance document by attendanceId (punches, breaks,
        // and admin APPROVED/REJECTED — those use the admin as performedBy, so date-only + staff filter missed them).
        const attendanceIds = attendance
            .map(a => a._id)
            .filter(id => id != null);
        if (attendanceIds.length > 0) {
            const attendanceIdSet = new Set(
                attendanceIds
                    .map(id => id?.toString?.() ?? String(id))
                    .filter(Boolean)
            );
            const staffIdAsString = String(req.staff._id);
            // The two AttendanceLog reads (logs-by-attendanceId and the orphan break-log fallback)
            // are independent queries — run them concurrently instead of one after the other.
            const [logs, orphanBreakLogs] = await Promise.all([
                AttendanceLog.find({
                    attendanceId: { $in: attendanceIds },
                    timestamp: { $gte: startOfMonth, $lte: endOfMonth }
                }).sort({ timestamp: 1 }).lean(),
                AttendanceLog.find({
                    action: { $in: ['BREAK_START', 'BREAK_END'] },
                    timestamp: { $gte: startOfMonth, $lte: endOfMonth },
                    $or: [
                        { performedBy: req.staff._id },
                        { 'newValue.employeeID': req.staff._id },
                        { 'newValue.employeeID': staffIdAsString }
                    ]
                }).sort({ timestamp: 1 }).lean()
            ]);

            const logsByAttendanceId = {};
            logs.forEach(log => {
                const aid = log.attendanceId?.toString?.() ?? String(log.attendanceId);
                if (!aid) return;
                if (!logsByAttendanceId[aid]) logsByAttendanceId[aid] = [];
                logsByAttendanceId[aid].push(log);
            });

            // Backward-compatible fallback:
            // Old break logs were written with break _id in attendanceId.
            // Attach those logs by business-calendar date so they appear in app history.
            const attendanceIdByDate = {};
            attendance.forEach(a => {
                const aid = a._id?.toString?.() ?? String(a._id);
                if (!aid) return;
                const dKey = formatAttendanceCalendarDay(a.date);
                if (dKey && !attendanceIdByDate[dKey]) {
                    attendanceIdByDate[dKey] = aid;
                }
            });

            orphanBreakLogs.forEach(log => {
                const existingAid = log.attendanceId?.toString?.() ?? String(log.attendanceId || '');
                if (existingAid && attendanceIdSet.has(existingAid)) {
                    return;
                }
                const when = log.breakEndDateTime || log.breakStartDateTime || log.timestamp;
                if (!when) return;
                const dKey = formatAttendanceCalendarDay(when);
                const mappedAttendanceId = dKey ? attendanceIdByDate[dKey] : null;
                if (!mappedAttendanceId) return;
                if (!logsByAttendanceId[mappedAttendanceId]) {
                    logsByAttendanceId[mappedAttendanceId] = [];
                }
                logsByAttendanceId[mappedAttendanceId].push(log);
            });

            attendance.forEach(a => {
                const id = a._id?.toString?.() ?? String(a._id);
                a.logs = id ? (logsByAttendanceId[id] || []) : [];
            });
        }

        // Normalize attendance date to business-calendar yyyy-MM-dd (matches salary/calendar in company TZ)
        const attendanceForResponse = attendance.map(a => {
            const aObj = (a && typeof a.toObject === 'function') ? a.toObject() : { ...a };
            aObj.date = formatAttendanceCalendarDay(a.date);
            return aObj;
        });

        const businessShifts =
            companyForFine &&
            companyForFine.settings &&
            companyForFine.settings.attendance &&
            Array.isArray(companyForFine.settings.attendance.shifts)
                ? companyForFine.settings.attendance.shifts
                : null;

        // Perf probe: how long the whole month endpoint took (DB + compute). Read this in the
        // server console while loading the calendar to see if the latency is server-side.
        console.log(`[Perf] getMonthAttendance ${year}-${month} took ${Date.now() - __monthT0}ms (records: ${attendanceRaw.length})`);

        // Diagnostic: flag a fully-empty payload for a current/past month (a future month
        // is legitimately empty). If this ever logs for the current month while the app
        // shows "data disappeared", it pins the blank to the server side (wrong staff
        // context, date-range mismatch, or a transient empty DB read) rather than the app.
        const __isFutureMonth = (Number(year) > now.getFullYear()) ||
            (Number(year) === now.getFullYear() && Number(month) > (now.getMonth() + 1));
        if (!__isFutureMonth &&
            attendanceRaw.length === 0 &&
            presentDates.length === 0 &&
            absentDates.length === 0 &&
            holidays.length === 0) {
            console.warn(`[getMonthAttendance][EMPTY] ${year}-${month} returned no attendance/present/absent/holiday for staff=${req.staff && req.staff._id} business=${req.staff && req.staff.businessId} — investigate (range ${startOfMonth.toISOString()}..${endOfMonth.toISOString()})`);
        }

        res.json({
            data: {
                attendance: attendanceForResponse,
                businessShifts,
                holidays,
                weekOffDates: weekOffDates,
                alternateWorkDatesInMonth,
                absentDates,
                presentDates,
                holidayDates,
                leaveDates,
                settings: {
                    weeklyOffPattern,
                    weeklyHolidays
                },
                // Stats are summary counters only — the calendar coloring above does
                // not depend on them. Wrap the whole block so a throw in any counter
                // (e.g. a malformed leave/date) degrades to zeroed stats instead of
                // 500-ing the request and blanking the calendar.
                stats: (() => {
                  try {
                    return {
                    workingDays,
                    holidaysCount,
                    weekOffs,
                    presentDays: (() => {
                        const leaveRecords = leaves.filter(l => l.isHalfDay === true || (l.leaveType || '').trim().toLowerCase() === 'half day');
                        const leaveDateSetHalf = new Set();
                        leaveRecords.forEach(leave => {
                            let curr = new Date(leave.startDate);
                            const end = new Date(leave.endDate);
                            while (curr <= end) {
                                if (curr >= startOfMonth && curr <= endOfMonth) {
                                    leaveDateSetHalf.add(formatDateString(curr));
                                }
                                curr.setDate(curr.getDate() + 1);
                            }
                        });

                        const dateMap = {};
                        attendance.forEach(a => {
                            const d = formatAttendanceCalendarDay(a.date);
                            const status = (a.status || '').trim().toLowerCase();
                            const leaveType = (a.leaveType || '').trim().toLowerCase();
                            const isPaidLeave = a.isPaidLeave === true;
                            const compensationType = (a.compensationType || '').trim().toLowerCase();
                            dateMap[d] = {
                                attendanceStatus: status,
                                attendanceLeaveType: leaveType,
                                isPaidLeave,
                                compensationType
                            };
                        });
                        leaveDateSetHalf.forEach(d => {
                            if (!dateMap[d]) dateMap[d] = {};
                            dateMap[d].hasHalfDayLeave = true;
                        });

                        return Object.entries(dateMap).reduce((sum, [date, data]) => {
                            if (date > todayStr) return sum; // Only count dates up to today
                            const status = data.attendanceStatus || '';
                            const attLeaveType = data.attendanceLeaveType || '';
                            const isHalfDay = status === 'half day' || attLeaveType === 'half day' || data.hasHalfDayLeave === true;
                            if (isHalfDay) return sum + 0.5;
                            if (status === 'present' || status === 'approved') return sum + 1;
                            return sum;
                        }, 0);
                    })(),
                    paidLeaveDays: (() => {
                        const leaveRecords = leaves.filter(l => l.isHalfDay === true || (l.leaveType || '').trim().toLowerCase() === 'half day');
                        const leaveDateSetHalf = new Set();
                        leaveRecords.forEach(leave => {
                            let curr = new Date(leave.startDate);
                            const end = new Date(leave.endDate);
                            while (curr <= end) {
                                if (curr >= startOfMonth && curr <= endOfMonth) {
                                    leaveDateSetHalf.add(formatDateString(curr));
                                }
                                curr.setDate(curr.getDate() + 1);
                            }
                        });
                        const dateMap = {};
                        attendance.forEach(a => {
                            const d = formatAttendanceCalendarDay(a.date);
                            const status = (a.status || '').trim().toLowerCase();
                            const leaveType = (a.leaveType || '').trim().toLowerCase();
                            const isPaidLeave = a.isPaidLeave === true;
                            const compensationType = (a.compensationType || '').trim().toLowerCase();
                            dateMap[d] = {
                                attendanceStatus: status,
                                attendanceLeaveType: leaveType,
                                isPaidLeave,
                                compensationType
                            };
                        });
                        leaveDateSetHalf.forEach(d => {
                            if (!dateMap[d]) dateMap[d] = {};
                            dateMap[d].hasHalfDayLeave = true;
                        });
                        return Object.entries(dateMap).reduce((sum, [date, data]) => {
                            if (date > todayStr) return sum;
                            const status = (data.attendanceStatus || '').trim().toLowerCase();
                            const isPaid = data.isPaidLeave === true;
                            const comp = (data.compensationType || '').trim().toLowerCase();
                            if (status === 'on leave' && isPaid && comp !== 'weekoff' && comp !== 'compoff') return sum + 1;
                            return sum;
                        }, 0);
                    })(),
                    absentDays: Math.max(0, workingDays - (() => {
                        const leaveRecords = leaves.filter(l => l.isHalfDay === true || (l.leaveType || '').trim().toLowerCase() === 'half day');
                        const leaveDateSetHalf = new Set();
                        leaveRecords.forEach(leave => {
                            let curr = new Date(leave.startDate);
                            const end = new Date(leave.endDate);
                            while (curr <= end) {
                                if (curr >= startOfMonth && curr <= endOfMonth) {
                                    leaveDateSetHalf.add(formatDateString(curr));
                                }
                                curr.setDate(curr.getDate() + 1);
                            }
                        });

                        const dateMap = {};
                        attendance.forEach(a => {
                            const d = formatAttendanceCalendarDay(a.date);
                            const status = (a.status || '').trim().toLowerCase();
                            const leaveType = (a.leaveType || '').trim().toLowerCase();
                            const isPaidLeave = a.isPaidLeave === true;
                            const compensationType = (a.compensationType || '').trim().toLowerCase();
                            dateMap[d] = {
                                attendanceStatus: status,
                                attendanceLeaveType: leaveType,
                                isPaidLeave,
                                compensationType
                            };
                        });
                        leaveDateSetHalf.forEach(d => {
                            if (!dateMap[d]) dateMap[d] = {};
                            dateMap[d].hasHalfDayLeave = true;
                        });

                        const presentOnly = Object.entries(dateMap).reduce((sum, [date, data]) => {
                            if (date > todayStr) return sum;
                            const status = data.attendanceStatus || '';
                            const attLeaveType = data.attendanceLeaveType || '';
                            const isHalfDay = status === 'half day' || attLeaveType === 'half day' || data.hasHalfDayLeave === true;
                            if (isHalfDay) return sum + 0.5;
                            if (status === 'present' || status === 'approved') return sum + 1;
                            return sum;
                        }, 0);
                        const paidLeaveOnly = Object.entries(dateMap).reduce((sum, [date, data]) => {
                            if (date > todayStr) return sum;
                            const status = (data.attendanceStatus || '').trim().toLowerCase();
                            const isPaid = data.isPaidLeave === true;
                            const comp = (data.compensationType || '').trim().toLowerCase();
                            if (status === 'on leave' && isPaid && comp !== 'weekoff' && comp !== 'compoff') return sum + 1;
                            return sum;
                        }, 0);
                        return presentOnly + paidLeaveOnly;
                    })())
                    };
                  } catch (statsErr) {
                    console.warn('[getMonthAttendance] stats computation failed, returning zeros:', statsErr?.message);
                    return { workingDays, holidaysCount, weekOffs, presentDays: 0, paidLeaveDays: 0, absentDays: 0 };
                  }
                })()
            }
        });

    } catch (error) {
        console.error(error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Get company fine calculation config (company.settings.payroll.fineCalculation) for staff's businessId
// @route   GET /api/attendance/fine-calculation
// @access  Private
const getFineCalculation = async (req, res) => {
    try {
        if (!req.staff) return res.status(404).json({ success: false, error: { message: 'Staff not found' } });
        const businessId = req.staff.businessId?._id ?? req.staff.businessId;
        if (!businessId) return res.status(400).json({ success: false, error: { message: 'Staff has no business assigned' } });
        const Company = require('../models/Company');
        const company = await Company.findById(businessId).select('settings.payroll.fineCalculation settings.payroll.payslip').lean();
        const fineCalculation = company?.settings?.payroll?.fineCalculation ?? null;
        const payslip = company?.settings?.payroll?.payslip ?? null;
        return res.json({ success: true, data: fineCalculation, payslip });
    } catch (error) {
        console.error('[Attendance getFineCalculation]', error);
        return res.status(500).json({ success: false, error: { message: error.message || 'Failed to fetch fine calculation' } });
    }
};

module.exports = { checkIn, checkOut, getTodayAttendance, getAttendanceHistory, getEmployeeAttendance, getMonthAttendance, getFineCalculation };
