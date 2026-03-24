const Attendance = require('../models/Attendance');
const AttendanceLog = require('../models/AttendanceLog');
const Staff = require('../models/Staff');
const User = require('../models/User'); // Import if needed
require('../models/AttendanceTemplate'); // ensure model registered for populate/lean paths via utils
const WeeklyHolidayTemplate = require('../models/WeeklyHolidayTemplate');
const Tracking = require('../models/Tracking');
const { reverseGeocode } = require('../services/geocodingService');
const { logTrackingWrite } = require('../utils/trackingLogger');
const { calculateAttendanceStats } = require('./payrollController');
const { getWeekOffConfigForStaff } = require('../utils/weekOffHelper');
const { getHolidayTemplateForStaff, getHolidayForDate, getHolidaysForMonth } = require('../utils/holidayTemplateHelper');
const { loadAttendanceTemplateForStaff } = require('../utils/resolveStaffAttendanceTemplate');
const digitalOceanService = require('../services/digitalOceanService');

/** Build a single address string from address, area, city, pincode. */
function buildAddressString(address, area, city, pincode) {
  const parts = [address, area, city, pincode].filter(Boolean);
  return parts.length ? parts.join(', ') : '';
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
            presenceStatus,
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
            presenceStatus,
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

// Helper function to get shift timing from Company settings based on shiftName
// If shiftName is not provided, returns the first shift from the array
function getShiftFromCompanySettings(company, shiftName = null) {
    if (!company || !company.settings || !company.settings.attendance || !company.settings.attendance.shifts) {
        return null;
    }
    
    const shifts = company.settings.attendance.shifts;
    if (!Array.isArray(shifts) || shifts.length === 0) {
        return null;
    }
    
    // Find shift matching the shiftName (case-insensitive), or use first shift if shiftName is not provided
    let matchedShift = null;
    if (shiftName) {
        matchedShift = shifts.find(shift => {
            const shiftNameLower = (shift.name || '').toLowerCase();
            const staffShiftNameLower = (shiftName || '').toLowerCase();
            return shiftNameLower === staffShiftNameLower;
        });
    }
    
    // If no match found and shiftName was provided, return null
    // If shiftName was not provided, use first shift
    if (!matchedShift) {
        if (shiftName) {
            return null; // Shift name specified but not found
        }
        matchedShift = shifts[0]; // Use first shift as default
    }
    return matchedShift;
}

// True when company has no shifts config (use template) or staff has a matching shift assigned.
function isShiftAssignedForStaff(company, staff) {
    const shifts = company?.settings?.attendance?.shifts;
    if (!shifts || !Array.isArray(shifts) || shifts.length === 0) return true;
    const staffShiftName = (staff.shiftName || '').toString().trim();
    if (!staffShiftName) return false;
    const match = shifts.some(s => (s.name || '').toString().trim().toLowerCase() === staffShiftName.toLowerCase());
    return match;
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
        allowAttendanceOnHolidays: t.allowAttendanceOnHolidays === true,
        allowAttendanceOnWeeklyOff: t.allowAttendanceOnWeeklyOff === true,
        // Respect template settings - default to true if not specified
        allowLateEntry: t.allowLateEntry !== false && t.lateEntryAllowed !== false,
        allowEarlyExit: t.allowEarlyExit !== false && t.earlyExitAllowed !== false,
        allowOvertime: t.allowOvertime !== false && t.overtimeAllowed !== false,
    };
}

/** Upload attendance selfie to Digital Ocean S3. Returns public URL or null. */
async function uploadAttendanceSelfie(base64String, req, companyId, employeeName, type) {
    try {
        if (!base64String) return null;
        let base64Data = base64String;
        if (base64String.startsWith('data:image')) {
            base64Data = base64String.replace(/^data:image\/\w+;base64,/, '');
        } else if (!base64String.startsWith('/9j/') && !base64String.startsWith('iVBOR')) {
            base64Data = base64String;
        }
        const buffer = Buffer.from(base64Data, 'base64');
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
            else if (dayOfWeek === 6 && d % 2 === 0) isWeekOff = true;
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
    const [startHours, startMins] = startTime.split(':').map(Number);
    const [endHours, endMins] = endTime.split(':').map(Number);
    
    const startTotalMinutes = startHours * 60 + startMins;
    const endTotalMinutes = endHours * 60 + endMins;
    
    let diffMinutes = endTotalMinutes - startTotalMinutes;
    if (diffMinutes < 0) {
        diffMinutes += 24 * 60; // Handle overnight shifts
    }
    
    return diffMinutes / 60; // Convert to hours
}

// Helper: fine config from company.settings.payroll.fineCalculation only (not attendance)
const { getEffectiveFineConfig, calculateFineAmount } = require('../utils/fineCalculationHelper');

// Helper function to calculate fine for late arrival.
// Uses formula: Fine = (Daily Salary ÷ Shift Hours) × (Late Minutes ÷ 60). Applies fineRules when present.
// When businessTimezone is provided, shift boundaries are built in that TZ (fixes production UTC server showing lateMinutes=0).
function calculateLateFine(punchInTime, attendanceDate, shiftStartTime, gracePeriodMinutes, dailySalary, shiftHours, fineConfig = null, businessTimezone = null) {
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
    const fineAmount = calculateFineAmount(lateMinutes, 'lateArrival', fineConfig, dailySalary, shiftHours);
    return { lateMinutes, fineAmount };
}

// Helper function to calculate fine for early exit.
// Uses formula: Fine = (Daily Salary ÷ Shift Hours) × (Early Minutes ÷ 60). Applies fineRules when present.
// When businessTimezone is provided, shift end is built in that TZ (consistent with late calculation).
function calculateEarlyFine(punchOutTime, attendanceDate, shiftEndTime, dailySalary, shiftHours, fineConfig = null, businessTimezone = null) {
    let shiftEnd;
    if (businessTimezone) {
        const { getShiftBoundaryAsUTCDate } = require('../utils/leaveAttendanceHelper');
        shiftEnd = getShiftBoundaryAsUTCDate(attendanceDate, shiftEndTime, businessTimezone);
    } else {
        const [endHours, endMins] = shiftEndTime.split(':').map(Number);
        shiftEnd = new Date(attendanceDate);
        shiftEnd.setHours(endHours, endMins, 0, 0);
    }
    console.log('[Fine] Early check: punchOutTime=', punchOutTime?.toISOString?.(), 'shiftEnd(UTC)=', shiftEnd?.toISOString?.());
    if (punchOutTime >= shiftEnd) return { earlyMinutes: 0, fineAmount: 0 };
    const earlyMinutes = Math.max(0, Math.round((shiftEnd.getTime() - punchOutTime.getTime()) / (1000 * 60)));
    if (earlyMinutes <= 0) return { earlyMinutes, fineAmount: 0 };
    if (fineConfig && fineConfig.enabled === false) return { earlyMinutes, fineAmount: 0 };
    const fineAmount = calculateFineAmount(earlyMinutes, 'earlyExit', fineConfig, dailySalary, shiftHours);
    return { earlyMinutes, fineAmount };
}

// Helper function to calculate combined fine (late + early)
// @param {Object} leave - Optional approved leave (for Half Day session-aware calculation)
async function calculateCombinedFine(punchInTime, punchOutTime, attendanceDate, template, staff, company, leave = null) {
    try {
        const checkInStr = punchInTime ? punchInTime.toISOString() : null;
        const checkOutStr = punchOutTime ? punchOutTime.toISOString() : null;
        console.log('[Fine] calculateCombinedFine called', { checkInTime: checkInStr, checkOutTime: checkOutStr, date: attendanceDate?.toISOString?.(), staffId: staff?._id?.toString() });
        const fineConfig = getEffectiveFineConfig(company || {});
        const isHalfDay = leave && String(leave.leaveType || '').trim().toLowerCase() === 'half day';
        // Use halfDaySession enum values ('First Half Day' / 'Second Half Day') - fallback to converting session numbers
        const session = isHalfDay ? (leave.halfDaySession || leave.halfDayType || (leave.session === '1' ? 'First Half Day' : leave.session === '2' ? 'Second Half Day' : null)) : null;
        const { getShiftTimings, getBusinessTimezone } = require('../utils/leaveAttendanceHelper');
        const dbShiftTimings = getShiftTimings(company, staff);
        const businessTimezone = getBusinessTimezone(company);
        const dbShiftStartTime = dbShiftTimings.startTime;
        const dbShiftEndTime = dbShiftTimings.endTime;
        const dbGracePeriodMinutes = dbShiftTimings.gracePeriodMinutes ?? fineConfig?.graceTimeMinutes ?? 0;
        
        // Get shift timings (session-aware for Half Day, regular shift otherwise)
        let shiftStartTime, shiftEndTime, shiftHours;
        if (isHalfDay && (session === 'First Half Day' || session === 'Second Half Day')) {
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
        
        // Per-day salary for fine: same as dashboard — monthly NET salary first, then daily = netMonthlySalary / thisMonthWorkingDays
        const salaryStructure = staff.salary ? calculateSalaryStructure(staff.salary) : null;
        const netMonthlySalary = salaryStructure?.monthly?.netMonthlySalary != null ? Number(salaryStructure.monthly.netMonthlySalary) : 0;
        const attendanceYear = attendanceDate.getFullYear();
        const attendanceMonth1Based = attendanceDate.getMonth() + 1; // 1-12 for calculateAttendanceStats
        let dailySalary = null;
        if (netMonthlySalary > 0 && staff._id) {
            try {
                const attendanceStats = await calculateAttendanceStats(staff._id, attendanceMonth1Based, attendanceYear);
                const thisMonthWorkingDays = attendanceStats.workingDaysFullMonth ?? attendanceStats.workingDays ?? 0;
                if (thisMonthWorkingDays > 0) {
                    dailySalary = netMonthlySalary / thisMonthWorkingDays;
                    console.log('[Fine] Daily salary (dashboard formula): netMonthlySalary=', netMonthlySalary, ', thisMonthWorkingDays=', thisMonthWorkingDays, '=> dailySalary=', dailySalary);
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
                if (workingDays > 0) dailySalary = netMonthlySalary / workingDays;
            }
        }
        
        // For half-day: fine is based on half-day salary (1 day salary / 2). Full-day: use full daily salary.
        let effectiveDailySalary = (dailySalary && dailySalary > 0) ? dailySalary : 0;
        if (isHalfDay && effectiveDailySalary > 0) {
            effectiveDailySalary = effectiveDailySalary / 2;
            console.log('[Fine] Half-day: using half-day salary for fine (dailySalary/2)=', effectiveDailySalary);
        }
        if (effectiveDailySalary <= 0) {
            console.log('[Fine] dailySalary missing or 0; late/early minutes will still be computed, fineAmount will be 0');
        }

        console.log('[Fine] Config: source=payroll.fineCalculation', 'enabled=', fineConfig?.enabled, 'calculationType=', fineConfig?.calculationType || 'shiftBased', 'dailySalary=', effectiveDailySalary, 'shiftHours=', shiftHours, 'shiftStart=', shiftStartTime, 'shiftEnd=', shiftEndTime, 'businessTimezone=', businessTimezone);

        let lateFine;
        if (isHalfDay && (session === 'First Half Day' || session === 'Second Half Day')) {
            const { calculateHalfDayLateFine } = require('../utils/leaveAttendanceHelper');
            const halfDayGrace = session === 'First Half Day' ? 0 : gracePeriodMinutes;
            lateFine = calculateHalfDayLateFine(punchInTime, attendanceDate, session, halfDayGrace, effectiveDailySalary, shiftHours, dbShiftStartTime, dbShiftEndTime, fineConfig, dbShiftTimings.halfDaySettings);
        } else {
            lateFine = calculateLateFine(punchInTime, attendanceDate, shiftStartTime, gracePeriodMinutes, effectiveDailySalary, shiftHours, fineConfig, businessTimezone);
        }
        let earlyFine = { earlyMinutes: 0, fineAmount: 0 };
        if (punchOutTime) {
            if (isHalfDay && (session === 'First Half Day' || session === 'Second Half Day')) {
                const { calculateHalfDayEarlyFine } = require('../utils/leaveAttendanceHelper');
                earlyFine = calculateHalfDayEarlyFine(punchOutTime, attendanceDate, session, effectiveDailySalary, shiftHours, dbShiftStartTime, dbShiftEndTime, fineConfig, dbShiftTimings.halfDaySettings);
            } else {
                earlyFine = calculateEarlyFine(punchOutTime, attendanceDate, shiftEndTime, effectiveDailySalary, shiftHours, fineConfig, businessTimezone);
            }
        }

        // Apply fine amounts from payroll.fineCalculation when enabled (allowLateEntry/allowEarlyExit only control blocking punch, not whether fine is charged)
        const lateFineAmount = (fineConfig && fineConfig.enabled) ? (lateFine.fineAmount || 0) : 0;
        const earlyFineAmount = (fineConfig && fineConfig.enabled) ? (earlyFine.fineAmount || 0) : 0;

        const fineHours = lateFine.lateMinutes + earlyFine.earlyMinutes;
        const fineAmount = lateFineAmount + earlyFineAmount;

        const out = {
            lateMinutes: lateFine.lateMinutes,
            earlyMinutes: earlyFine.earlyMinutes,
            fineHours: fineHours,
            fineAmount: fineAmount,
            lateFineAmount,
            earlyFineAmount
        };
        console.log('[Fine] Result:', JSON.stringify(out));
        // Formula summary with check-in/check-out times for debugging why lateMinutes might be 0
        console.log('[Fine FORMULA] Summary: checkInTime=', checkInStr, 'checkOutTime=', checkOutStr,
            '| dailySalary=', effectiveDailySalary, 'shiftHours=', shiftHours, 'shiftStart=', shiftStartTime, 'shiftEnd=', shiftEndTime, 'businessTimezone=', businessTimezone,
            '| lateMinutes=', lateFine.lateMinutes, 'lateFineAmount=', lateFineAmount,
            '| earlyMinutes=', earlyFine.earlyMinutes, 'earlyFineAmount=', earlyFineAmount,
            '| totalFineAmount=', fineAmount);
        const formulaDesc = (fineConfig && fineConfig.calculationType) ? fineConfig.calculationType : 'shiftBased';
        console.log('[Fine AMOUNT TEST] --- Formula: ' + formulaDesc + ' ---');
        console.log('[Fine AMOUNT TEST] Times: checkInTime=' + checkInStr + ' | checkOutTime=' + (checkOutStr || 'null') + ' | attendanceDate=' + (attendanceDate?.toISOString?.() || ''));
        console.log('[Fine AMOUNT TEST] Inputs: dailySalary=' + effectiveDailySalary + ', shiftHours=' + shiftHours + ', shiftStart=' + shiftStartTime + ', shiftEnd=' + shiftEndTime + ', businessTimezone=' + businessTimezone);
        console.log('[Fine AMOUNT TEST] Late: minutes=' + lateFine.lateMinutes + ' => fineAmount=' + lateFineAmount + ' | Early: minutes=' + earlyFine.earlyMinutes + ' => fineAmount=' + earlyFineAmount);
        console.log('[Fine AMOUNT TEST] Formula (shiftBased): totalFineAmount = (dailySalary/shiftHours)*(lateMinutes/60) + (dailySalary/shiftHours)*(earlyMinutes/60) = lateFineAmount + earlyFineAmount');
        console.log('[Fine AMOUNT TEST] Result: totalFineAmount = ' + lateFineAmount + ' + ' + earlyFineAmount + ' = ' + fineAmount);
        return out;
    } catch (error) {
        console.error('[Fine] Calculation Error', error);
        return { lateMinutes: 0, earlyMinutes: 0, fineHours: 0, fineAmount: 0, lateFineAmount: 0, earlyFineAmount: 0 };
    }
}

// @desc    Check In
// @route   POST /api/attendance/checkin
// @access  Private
const checkIn = async (req, res) => {
    const { latitude, longitude, address, area, city, pincode, selfie, movementType, businessId: bodyBusinessId, source: bodySource } = req.body;

    const VALID_SOURCES = ['app', 'software', 'webemp', 'webadmin'];
    const source = (bodySource && VALID_SOURCES.includes(String(bodySource).toLowerCase()))
        ? String(bodySource).toLowerCase()
        : null;

    // Use req.staff from middleware
    if (!req.staff) {
        return res.status(404).json({ message: 'Staff record not found for this user' });
    }
    const staffId = req.staff._id;
    const nowForLog = new Date();
    console.log('[Attendance checkIn] request', { staffId: staffId?.toString(), date: nowForLog.toISOString?.()?.slice(0, 10), businessIdFromBody: bodyBusinessId ?? null });

    if (latitude === undefined || longitude === undefined) {
        return res.status(400).json({ message: 'Location coordinates are missing' });
    }

    const userLat = parseFloat(latitude);
    const userLng = parseFloat(longitude);

    // Date Logic: Store as Date object set to midnight (start of day) - UTC safe approach
    const now = new Date();
    // Create Date object for start/end of day in UTC to ensure MongoDB ISODate format
    const year = now.getUTCFullYear();
    const month = now.getUTCMonth();
    const day = now.getUTCDate();
    const startOfDay = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
    const endOfDay = new Date(Date.UTC(year, month, day, 23, 59, 59, 999));

    try {
        // Re-fetch staff (keep attendanceTemplateId as ObjectId; resolve template via collection lookup)
        const staff = await Staff.findById(staffId)
            .populate('branchId')
            .populate('weeklyHolidayTemplateId')
            .populate('holidayTemplateId');
        const templateDoc = await loadAttendanceTemplateForStaff(staff);
        const template = normalizeTemplate(templateDoc);

        // Salary must be configured to allow check-in (required for fine/late/early storage and payroll)
        const salaryStructure = staff.salary ? calculateSalaryStructure(staff.salary) : null;
        const netMonthlySalary = salaryStructure?.monthly?.netMonthlySalary != null ? Number(salaryStructure.monthly.netMonthlySalary) : 0;
        if (!staff.salary || netMonthlySalary <= 0) {
            return res.status(400).json({ message: 'Salary not configured. Contact HR.' });
        }

        const Company = require('../models/Company');
        const company = await Company.findById(staff.businessId);
        if (!isShiftAssignedForStaff(company, staff)) {
            return res.status(403).json({ message: 'Shift not assigned. Contact HR.' });
        }
        // PRIORITY 1: Check if On Approved Leave (highest priority - blocks all other rules)
        const Leave = require('../models/Leave');
        const { canCheckInWithHalfDayLeave, getShiftTimings, getBusinessTimezone } = require('../utils/leaveAttendanceHelper');
        const shiftForCheckIn = getShiftTimings(company, staff);
        const businessTimezone = getBusinessTimezone(company);
        const activeLeave = await Leave.findOne({
            employeeId: staffId,
            status: { $regex: /^approved$/i },
            startDate: { $lte: endOfDay },
            endDate: { $gte: startOfDay }
        });
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

        // 2. Check for Holiday
        const holidayTemplate = await getHolidayTemplateForStaff(staff);
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
            else if (dayOfWeek === 6 && now.getDate() % 2 === 0) isWeeklyOff = true;
        } else {
            isWeeklyOff = weekOffConfig.weeklyHolidays.some(h => h.day === dayOfWeek);
        }
        if (isWeeklyOff && template.allowAttendanceOnWeeklyOff === false) {
            return res.status(403).json({ message: 'Today is a Weekly Off. Check-in not allowed.' });
        }

        // 4. Check Late Entry - Always allow, but add warning if not allowed in settings
        // PRIORITY: Get shift timing from Company settings (matches shiftName if available, otherwise first shift)
        // Fallback to AttendanceTemplate if shift not found in Company settings
        let shiftTiming = null;
        if (company) {
            shiftTiming = getShiftFromCompanySettings(company, staff.shiftName || null);
        }
        
        const shiftStartStr = shiftTiming?.startTime || template.shiftStartTime || "09:30";
        const shiftEndStr = shiftTiming?.endTime || template.shiftEndTime || "18:30";
        const gracePeriod = shiftTiming?.gracePeriodMinutes ?? template.gracePeriodMinutes ?? 0;
        
        const [sHours, sMins] = shiftStartStr.split(':').map(Number);

        const shiftStart = new Date(now);
        shiftStart.setHours(sHours, sMins, 0, 0);
        const graceTimeEnd = new Date(shiftStart);
        graceTimeEnd.setMinutes(graceTimeEnd.getMinutes() + gracePeriod);

        const warnings = [];
        let lateMinutes = 0;
        if (now > graceTimeEnd) {
            // User is checking in late (after grace period)
            lateMinutes = Math.floor((now.getTime() - shiftStart.getTime()) / (1000 * 60));
            if (template.allowLateEntry === false) {
                // Add warning but still allow check-in
                warnings.push({
                    type: 'late_entry',
                    message: `Late entry not allowed. You are ${lateMinutes} minute(s) late. Shift start time: ${shiftStartStr}`,
                    minutes: lateMinutes,
                    notAllowed: true
                });
            }
            // If allowed, proceed silently (no warnings)
        }

        // Geofence Logic
        let activeBranch = null;
        let officeLat, officeLng, officeName, allowedRadiusMeters;
        let isGeofenceEnabled = false;

        if (staff.branchId) {
            activeBranch = staff.branchId;
            officeName = activeBranch.branchName || "Assigned Branch";

            if (activeBranch.geofence && activeBranch.geofence.enabled === true) {
                isGeofenceEnabled = true;
                officeLat = activeBranch.geofence.latitude;
                officeLng = activeBranch.geofence.longitude;
                allowedRadiusMeters = activeBranch.geofence.radius || 100;
            } else if (activeBranch.latitude && activeBranch.longitude) {
                isGeofenceEnabled = true;
                officeLat = activeBranch.latitude;
                officeLng = activeBranch.longitude;
                allowedRadiusMeters = activeBranch.radius || 100;
            }
        }

        if (isGeofenceEnabled && template.requireGeolocation !== false) {
            if (!officeLat || !officeLng) {
                console.warn(`[CheckIn Warning] Geofence enabled for ${officeName} but coordinates missing.`);
            } else {
                const distance = getDistanceFromLatLonInKm(userLat, userLng, officeLat, officeLng);
                const distanceInMeters = distance * 1000;
                if (distanceInMeters > allowedRadiusMeters) {
                    return res.status(400).json({
                        message: `Check-in denied. You are ${distanceInMeters.toFixed(0)}m away. Allowed: ${allowedRadiusMeters}m.`
                    });
                }
            }
        }

        // Check for existing attendance - check both employeeId and user fields
        // to find records created from web or app
        let existing = await Attendance.findOne({
            employeeId: staffId,
            date: { $gte: startOfDay, $lte: endOfDay }
        });

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
            let selfieUrl = null;
            if (selfie && template.requireSelfie !== false) {
                selfieUrl = await uploadAttendanceSelfie(selfie, req, staff.businessId ? String(staff.businessId) : undefined, staff.name, 'punch-in');
            }
            const fineShiftStartTime = shiftTiming?.startTime || template.shiftStartTime || '09:30';
            const fineShiftEndTime = shiftTiming?.endTime || template.shiftEndTime || '18:30';
            const fineGracePeriod = shiftTiming?.gracePeriodMinutes ?? template.gracePeriodMinutes ?? 0;
            const fineTemplate = {
                ...template,
                shiftStartTime: fineShiftStartTime,
                shiftEndTime: fineShiftEndTime,
                gracePeriodMinutes: fineGracePeriod
            };
            // Always calculate fine so lateMinutes/fineAmount respect grace period
            let fineResult = await calculateCombinedFine(now, null, startOfDay, fineTemplate, staff, company, activeLeave);
            existing.punchIn = now;

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
            
            existing.punchInSelfie = selfieUrl;
            existing.punchInIpAddress = req.ip || req.connection.remoteAddress;
            existing.ipAddress = req.ip || req.connection.remoteAddress;
            if (staff.businessId != null) {
                existing.businessId = staff.businessId;
                console.log('[Attendance checkIn] (half-day update) storing businessId in attendances:', staff.businessId?.toString());
            }
            existing.lateMinutes = fineResult.lateMinutes;
            existing.earlyMinutes = fineResult.earlyMinutes ?? 0;
            existing.fineHours = fineResult.fineHours ?? 0;
            existing.fineAmount = fineResult.fineAmount ?? 0;
            existing.workHours = 0;
            existing.isPaidLeave = false;  // check-in: set false
            if (source) existing.source = source;
            console.log('[Fine CHECK-IN] (half-day update) INSERTING: checkInTime=', existing.punchIn?.toISOString?.(), 'checkOutTime=null', 'lateMinutes=', existing.lateMinutes, 'earlyMinutes=', existing.earlyMinutes, 'fineAmount=', existing.fineAmount);
            await existing.save();
            const response = existing.toObject ? existing.toObject() : existing;
            if (warnings.length > 0) response.warnings = warnings;
            console.log('[Attendance checkIn] success (half-day update)', { staffId: staffId?.toString(), attendanceId: existing._id?.toString() });
            void Promise.allSettled([
                AttendanceLog.create({
                    attendanceId: existing._id,
                    action: 'PUNCH_IN',
                    performedBy: staffId,
                    performedByName: staff.name || undefined,
                    performedByEmail: staff.email || undefined,
                    selfieUrl: selfieUrl || undefined,
                    punchInDateTime: now,
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

        // Upload Selfie to S3 (attendance folder)
        let selfieUrl = null;
        if (selfie && template.requireSelfie !== false) {
            selfieUrl = await uploadAttendanceSelfie(selfie, req, staff.businessId ? String(staff.businessId) : undefined, staff.name, 'punch-in');
        }

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
        
        // Always calculate fine so lateMinutes/fineAmount are set (0 when on time or within grace)
        const fineResult = await calculateCombinedFine(now, null, startOfDay, fineTemplate, staff, company, activeLeave);

        console.log('[Fine CHECK-IN] INSERTING: checkInTime=', now.toISOString(), 'checkOutTime=null', 'lateMinutes=', fineResult.lateMinutes, 'earlyMinutes=', fineResult.earlyMinutes, 'fineAmount=', fineResult.fineAmount);
        // Create initial attendance record. Store businessId from staff (staffs collection).
        const businessIdToStore = staff.businessId;
        console.log('[Attendance checkIn] storing in attendances: businessId=', businessIdToStore?.toString(), '(from staffs collection; body businessId=', bodyBusinessId ?? 'not sent', ')');
        const attendance = await Attendance.create({
            employeeId: staffId,
            user: staffId,
            businessId: businessIdToStore,
            date: startOfDay,
            punchIn: now,
            status: (isHoliday || isWeeklyOff) ? 'Present' : 'Pending',
            isPaidLeave: false,  // check-in attendance: default false
            location: locationData,
            punchInSelfie: selfieUrl,
            ipAddress: req.ip || req.connection.remoteAddress,
            punchInIpAddress: req.ip || req.connection.remoteAddress,
            ...(source && { source }),
            // Fine calculation fields
            workHours: 0,
            fineHours: fineResult.fineHours,
            lateMinutes: fineResult.lateMinutes,
            earlyMinutes: fineResult.earlyMinutes,
            fineAmount: fineResult.fineAmount
        });

        // Include warnings in response if any
        const response = attendance.toObject ? attendance.toObject() : attendance;
        if (warnings.length > 0) {
            response.warnings = warnings;
        }

        console.log('[Attendance checkIn] success', { staffId: staffId?.toString(), attendanceId: response?._id?.toString?.() || response?.id, businessIdStored: response?.businessId?.toString?.() ?? response?.businessId });
        void Promise.allSettled([
            AttendanceLog.create({
                attendanceId: attendance._id,
                action: 'PUNCH_IN',
                performedBy: staffId,
                performedByName: staff.name || undefined,
                performedByEmail: staff.email || undefined,
                selfieUrl: selfieUrl || undefined,
                punchInDateTime: now,
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
    const { latitude, longitude, address, area, city, pincode, selfie, movementType, source: bodySource } = req.body;

    const VALID_SOURCES = ['app', 'software', 'webemp', 'webadmin'];
    const source = (bodySource && VALID_SOURCES.includes(String(bodySource).toLowerCase()))
        ? String(bodySource).toLowerCase()
        : null;

    if (!req.staff) {
        return res.status(404).json({ message: 'Staff record not found' });
    }
    const staffId = req.staff._id;
    const now = new Date();
    console.log('[Attendance checkOut] request', { staffId: staffId?.toString(), date: now.toISOString?.()?.slice(0, 10) });

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
        const Company = require('../models/Company');
        const company = await Company.findById(staff.businessId);
        if (!isShiftAssignedForStaff(company, staff)) {
            return res.status(403).json({ message: 'Shift not assigned. Contact HR.' });
        }
        const templateDoc = await loadAttendanceTemplateForStaff(staff);
        const template = normalizeTemplate(templateDoc);

        // Find today's attendance
        const attendance = await Attendance.findOne({
            employeeId: staffId,
            date: { $gte: startOfDay, $lte: endOfDay }
        });

        if (!attendance) {
            const legacyAttendance = await Attendance.findOne({
                user: staffId,
                date: { $gte: startOfDay, $lte: endOfDay }
            });

            if (!legacyAttendance) {
                return res.status(404).json({ message: 'No check-in record found for today' });
            }
            return processCheckOut(legacyAttendance, req, res, staff, now, { latitude, longitude, address, area, city, pincode, selfie, movementType }, template);
        }

        return processCheckOut(attendance, req, res, staff, now, { latitude, longitude, address, area, city, pincode, selfie, movementType }, template);

    } catch (error) {
        console.error('[Attendance checkOut] error', error);
        res.status(500).json({ message: error.message });
    }
};

async function processCheckOut(attendance, req, res, staff, now, data, template = {}) {
    const { latitude, longitude, address, area, city, pincode, selfie, source, movementType } = data;

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
    const company = await Company.findById(staff.businessId);

    const Leave = require('../models/Leave');
    const { canCheckOutWithHalfDayLeave, getShiftTimings, getBusinessTimezone, getWorkingSessionTimings } = require('../utils/leaveAttendanceHelper');
    const activeLeave = await Leave.findOne({
        employeeId: staff._id,
        status: { $regex: /^approved$/i },
        startDate: { $lte: endOfDay },
        endDate: { $gte: startOfDay }
    });
    if (activeLeave) {
        if (activeLeave.leaveType === 'Half Day') {
            const shiftForLeave = getShiftTimings(company, staff);
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
            return res.status(403).json({ message: 'Your leave request is approved for today. Enjoy your leave.' });
        }
    }

    // Check Early Exit - use session end time for half-day (first/second half), else full shift end
    let shiftTiming = null;
    if (company) {
        shiftTiming = getShiftFromCompanySettings(company, staff.shiftName || null);
    }
    let dbShiftStart = shiftTiming?.startTime || template.shiftStartTime || '09:30';
    let dbShiftEnd = shiftTiming?.endTime || template.shiftEndTime || '18:30';

    let shiftEndStr = dbShiftEnd;
    let shiftEnd = new Date(now);
    const isHalfDayCheckout = isHalfDayStatus || (activeLeave && String(activeLeave.leaveType || '').trim().toLowerCase() === 'half day');
    if (isHalfDayCheckout && company) {
        const dbShiftTimings = getShiftTimings(company, staff);
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

    const warnings = [];
    let earlyMinutes = 0;
    if (now < shiftEnd) {
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

    // Geofencing Check
    if (staff.branchId && latitude && longitude && template.requireGeolocation !== false) {
        const activeBranch = staff.branchId;
        if (activeBranch.geofence && activeBranch.geofence.enabled === true) {
            const officeLat = activeBranch.geofence.latitude;
            const officeLng = activeBranch.geofence.longitude;
            const allowedRadius = activeBranch.geofence.radius || 100;

            if (officeLat && officeLng) {
                const dist = getDistanceFromLatLonInKm(latitude, longitude, officeLat, officeLng) * 1000;
                if (dist > allowedRadius) {
                    return res.status(400).json({
                        message: `Check-out denied. You are ${dist.toFixed(0)}m away from branch.`
                    });
                }
            }
        }
    }

    // Upload Selfie to S3 (attendance folder)
    if (selfie && template.requireSelfie !== false) {
        const companyId = staff.businessId ? String(staff.businessId) : undefined;
        const selfieUrl = await uploadAttendanceSelfie(selfie, req, companyId, staff.name, 'punch-out');
        attendance.punchOutSelfie = selfieUrl;
    }

    // Update Fields
    attendance.punchOut = now;
    attendance.punchOutIpAddress = req.ip || req.connection.remoteAddress;
    if (source) attendance.source = source;

    if (latitude && longitude) {
        if (!attendance.location) attendance.location = {};
        attendance.location.punchOut = {
            latitude, longitude, address, area, city, pincode
        };
    }

    // Calculate Work Hours: store duration in minutes in attendances collection
    if (attendance.punchIn) {
        const durationMs = now - new Date(attendance.punchIn);
        const minutes = Math.round(durationMs / (1000 * 60));
        attendance.workHours = minutes; // store in minutes

        // Record Overtime if allowed
        if (template.allowOvertime) {
            // Use shift timing from Company settings if available
            const overtimeShiftEndStr = shiftTiming?.endTime || template.shiftEndTime || "18:30";
            const [eHours, eMins] = overtimeShiftEndStr.split(':').map(Number);
            const shiftEnd = new Date(now);
            shiftEnd.setHours(eHours, eMins, 0, 0);

            if (now > shiftEnd) {
                const otMs = now - shiftEnd;
                attendance.overtime = parseFloat((otMs / (1000 * 60 * 60)).toFixed(2));
            }
        }
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
    
    const fineResult = await calculateCombinedFine(
        attendance.punchIn,
        now,
        attendance.date,
        fineTemplate,
        staff,
        company,
        leaveForFine
    );

    // Use current calculation total (late + early) so fine is consistent with same shift/daily salary.
    // Do not add early to previous stored fine — check-in may have used different shift hours.
    const lateFineAmount = Number(fineResult.lateFineAmount) || 0;
    const earlyFineAmount = Number(fineResult.earlyFineAmount) || 0;
    const totalFineAmount = lateFineAmount + earlyFineAmount;

    // Set all fine fields from combined result so attendance collection has consistent fine amount and fine hours
    attendance.lateMinutes = fineResult.lateMinutes ?? attendance.lateMinutes ?? 0;
    attendance.earlyMinutes = fineResult.earlyMinutes ?? 0;
    attendance.fineHours = fineResult.fineHours ?? ((Number(attendance.lateMinutes) || 0) + (Number(attendance.earlyMinutes) || 0));
    attendance.fineAmount = totalFineAmount;

    console.log('[Fine CHECK-OUT] checkInTime=', attendance.punchIn?.toISOString?.(), 'checkOutTime=', now.toISOString(), 'lateFineAmount=', lateFineAmount, 'earlyFineAmount=', earlyFineAmount, 'totalFineAmount=', totalFineAmount, 'INSERTING: lateMinutes=', attendance.lateMinutes, 'earlyMinutes=', attendance.earlyMinutes, 'fineHours=', attendance.fineHours, 'fineAmount=', attendance.fineAmount);
    console.log('[Fine AMOUNT TEST] CHECK-OUT stored: lateMinutes=' + attendance.lateMinutes + ' lateFineAmount=' + lateFineAmount + ', earlyMinutes=' + attendance.earlyMinutes + ' earlyFineAmount=' + earlyFineAmount + ', totalFineAmount=' + totalFineAmount + ' (formula: lateFine + earlyFine)');

    await attendance.save();

    console.log('[Attendance CHECK-OUT] saved:', {
        staffId: staff._id?.toString(),
        attendanceId: attendance._id?.toString(),
        date: attendance.date,
        punchIn: attendance.punchIn,
        punchOut: attendance.punchOut,
        lateMinutes: attendance.lateMinutes,
        earlyMinutes: attendance.earlyMinutes,
        workHours: attendance.workHours,
        fineHours: attendance.fineHours,
        fineAmount: attendance.fineAmount,
    });

    // Include warnings in response if any
    const response = attendance.toObject ? attendance.toObject() : attendance;
    if (warnings.length > 0) {
        response.warnings = warnings;
    }

    console.log('[Attendance checkOut] success', { staffId: staff._id?.toString(), attendanceId: attendance._id?.toString(), punchIn: attendance.punchIn, punchOut: attendance.punchOut });
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
            punchOutDateTime: now,
            punchInAddress: (attendance.location?.punchIn && buildAddressString(attendance.location.punchIn.address, attendance.location.punchIn.area, attendance.location.punchIn.city, attendance.location.punchIn.pincode)) || undefined,
            punchOutAddress: buildAddressString(address, area, city, pincode) || undefined,
            timestamp: now
        }),
        (userLat !== 0 || userLng !== 0)
            ? insertAttendanceTracking(staff._id, staff.name, userLat, userLng, 'out_of_office', 'checked_out', movementType, address, area, city, pincode)
            : Promise.resolve()
    ]);
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
                    radius: b.geofence?.radius ?? b.radius ?? 100
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

        const { isCurrentlyInLeaveSession, getLeaveMessageForUI, canCheckInWithHalfDayLeave, canCheckOutWithHalfDayLeave, getHalfDaySessionMessage, getShiftTimings, getBusinessTimezone } = require('../utils/leaveAttendanceHelper');
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
        const dbShiftTimingsForLeave = getShiftTimings(company, staff);
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
        let leaveMessage = (halfDaySource && isToday) ? getLeaveMessageForUI(halfDayLeaveForHelper, now, shiftStartForLeave, shiftEndForLeave, businessTimezone, halfDaySettingsForLeave) : (activeLeave && isToday ? getLeaveMessageForUI(activeLeave, now, shiftStartForLeave, shiftEndForLeave, businessTimezone, halfDaySettingsForLeave) : null);
        if (halfDaySource && isToday && currentlyInLeaveSession) {
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
            if (isToday && currentlyInLeaveSession) {
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
                // When user is currently in their leave half, never allow check-in/out (override any helper result)
                if (currentlyInLeaveSession) {
                    checkInAllowed = false;
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
        // - In leave half (currentlyInLeaveSession): "You are on leave - First/Second Half", checkInAllowed/checkOutAllowed = false
        // - In working half: session timing message + "Check-in/out allowed for your working half.", checkInAllowed/checkOutAllowed from helpers
        if (halfDayLeave && halfDayLeave.message && isToday) {
            if (currentlyInLeaveSession) {
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

        const shiftAssigned = isShiftAssignedForStaff(company, staff);
        const resolvedAttendanceTemplateDoc = await loadAttendanceTemplateForStaff(staff);
        const finalTemplate = resolvedAttendanceTemplateDoc
            ? normalizeTemplate(resolvedAttendanceTemplateDoc)
            : {};
        
        // Merge shift timings from company settings into template only when shift is assigned
        if (shiftAssigned && dbShiftTimingsForLeave.startTime) {
            finalTemplate.shiftStartTime = dbShiftTimingsForLeave.startTime;
        }
        if (shiftAssigned && dbShiftTimingsForLeave.endTime) {
            finalTemplate.shiftEndTime = dbShiftTimingsForLeave.endTime;
        }
        if (shiftAssigned && dbShiftTimingsForLeave.gracePeriodMinutes !== undefined) {
            finalTemplate.gracePeriodMinutes = dbShiftTimingsForLeave.gracePeriodMinutes;
        }
        
        let isWeeklyOff = false;
        const holidayTemplate = await getHolidayTemplateForStaff(staff);
        const holidayInfo = getHolidayForDate(holidayTemplate, queryDate);
        const dayOfWeek = queryDate.getDay();
        const weekOffConfig = await getWeekOffConfigForStaff(staff, company);
        if (weekOffConfig.weeklyOffPattern === 'oddEvenSaturday') {
            if (dayOfWeek === 0) isWeeklyOff = true;
            else if (dayOfWeek === 6 && queryDate.getDate() % 2 === 0) isWeeklyOff = true;
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

        res.json({
            data: attendance,
            branch: branchInfo,
            template: finalTemplate,
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
    const enriched = [];
    for (const doc of attendanceList) {
        const plain = doc.toObject ? doc.toObject() : { ...doc };
        const isHalfDay = (plain.status === 'Half Day' || (plain.leaveType && String(plain.leaveType).toLowerCase() === 'half day'));
        if (isHalfDay && plain.date) {
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
        }
        enriched.push(plain);
    }
    return enriched;
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
            .limit(limit);

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

const getMonthAttendance = async (req, res) => {
    try {
        const { year, month } = req.query;
        if (!year || !month) {
            return res.status(400).json({ message: 'Year and Month are required' });
        }

        const startOfMonth = new Date(year, month - 1, 1);
        const endOfMonth = new Date(year, month, 0, 23, 59, 59, 999);

        // Fetch attendance
        const attendanceRaw = await Attendance.find({
            $or: [
                { employeeId: req.staff._id },
                { user: req.staff._id }
            ],
            date: { $gte: startOfMonth, $lte: endOfMonth }
        }).sort({ date: 1 });

        // Enrich records that have fineHours/lateMinutes but no fineAmount (e.g. Excel import) using payroll fine formula
        const Company = require('../models/Company');
        const Staff = require('../models/Staff');
        const { getRecordFineAmount, calculateAttendanceStats } = require('./payrollController');
        const { getEffectiveFineConfig } = require('../utils/fineCalculationHelper');
        const { getShiftTimings, calculateWorkHoursFromShift, getBusinessTimezone } = require('../utils/leaveAttendanceHelper');

        const companyForFine = await Company.findById(req.staff.businessId).lean();
        const businessTz = getBusinessTimezone(companyForFine);
        const staffWithSalary = await Staff.findById(req.staff._id).select('+salary').lean();
        const fineConfig = companyForFine ? getEffectiveFineConfig(companyForFine) : null;
        const shiftTimings = companyForFine && staffWithSalary ? getShiftTimings(companyForFine, staffWithSalary) : {};
        const shiftHours = Math.max(0, calculateWorkHoursFromShift(shiftTimings.startTime || '09:30', shiftTimings.endTime || '18:30') || 9);

        let dailySalaryForEnrich = 0;
        try {
            const stats = await calculateAttendanceStats(req.staff._id, Number(month), Number(year));
            const thisMonthWorkingDays = stats.workingDaysFullMonth ?? stats.workingDays ?? 0;
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
            const hasFineMinutes = (Number(doc.fineHours) || 0) > 0 || (Number(doc.lateMinutes) || 0) > 0;
            const status = (doc.status || '').trim().toLowerCase();
            const isEligible = status === 'present' || status === 'approved' || (doc.leaveType || '').trim().toLowerCase() === 'half day';
            if (hasFineMinutes && isEligible && !(Number(doc.fineAmount) > 0)) {
                const amount = getRecordFineAmount(doc, dailySalaryForEnrich, shiftHours, fineConfig);
                if (amount > 0) doc.fineAmount = amount;
            }
        }

        const attendance = await enrichWithLeaveDetails(attendanceRaw, req.staff._id);

        const staffForCalendar = await Staff.findById(req.staff._id)
            .populate('weeklyHolidayTemplateId')
            .populate('holidayTemplateId')
            .lean();
        const holidayTemplate = await getHolidayTemplateForStaff(staffForCalendar || req.staff);
        const holidays = getHolidaysForMonth(holidayTemplate, year, month);

        // Week-off from staff's WeeklyHolidayTemplate only (weeklyholidaytemplates collection via staff.weeklyHolidayTemplateId)
        const weekOffConfig = await getWeekOffConfigForStaff(staffForCalendar || req.staff, companyForFine);
        const weeklyOffPattern = weekOffConfig.weeklyOffPattern;
        const weeklyHolidays = weekOffConfig.weeklyHolidays;

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

        let workingDays = 0;
        let weekOffs = 0;
        let holidaysCount = 0;
        let weekOffDates = [];

        // Loop for stats - only for days 1..lastDayToCount (so future days are not counted as absent)
        for (let d = 1; d <= lastDayToCount; d++) {
            const date = new Date(year, month - 1, d);
            date.setHours(0, 0, 0, 0);

            const dayOfWeek = date.getDay();
            let isWeekOff = false;

            if (weeklyOffPattern === 'oddEvenSaturday') {
                if (dayOfWeek === 0) isWeekOff = true;
                else if (dayOfWeek === 6 && d % 2 === 0) isWeekOff = true;
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

        // Separate loop for weekOffDates (always for the full month to show in calendar)
        for (let d = 1; d <= totalDaysInMonth; d++) {
            // Create date in local timezone for day of week calculation
            const date = new Date(year, month - 1, d);
            const dayOfWeek = date.getDay();
            let isWeekOff = false;

            if (weeklyOffPattern === 'oddEvenSaturday') {
                if (dayOfWeek === 0) {
                    isWeekOff = true; // All Sundays are week off
                } else if (dayOfWeek === 6 && d % 2 === 0) {
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

        // Fetch leaves for the month
        const Leave = require('../models/Leave');
        const leaves = await Leave.find({
            employeeId: req.staff._id,
            status: { $regex: /^approved$/i },
            $or: [
                { startDate: { $gte: startOfMonth, $lte: endOfMonth } },
                { endDate: { $gte: startOfMonth, $lte: endOfMonth } },
                { startDate: { $lte: startOfMonth }, endDate: { $gte: endOfMonth } }
            ]
        });

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

        for (let d = 1; d <= totalDaysInMonth; d++) {
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
                } else if (dayOfWeek === 6 && d % 2 === 0) {
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

        // Dates in this month that are alternate work dates for this employee (compensation week-off or comp-off: they work on these days)
        const alternateWorkRecords = await Attendance.find({
            $or: [{ employeeId: req.staff._id }, { user: req.staff._id }],
            compensationType: { $in: ['weekOff', 'compOff'] },
            alternateWorkDate: { $gte: startOfMonth, $lte: endOfMonth }
        }).select('alternateWorkDate').lean();
        const alternateWorkDatesInMonth = alternateWorkRecords.map(r => formatDateString(r.alternateWorkDate)).filter(Boolean);

        // Attach AttendanceLog rows to each attendance document by attendanceId (punches, breaks,
        // and admin APPROVED/REJECTED — those use the admin as performedBy, so date-only + staff filter missed them).
        const attendanceIds = attendance
            .map(a => a._id)
            .filter(id => id != null);
        if (attendanceIds.length > 0) {
            const logs = await AttendanceLog.find({
                attendanceId: { $in: attendanceIds },
                timestamp: { $gte: startOfMonth, $lte: endOfMonth }
            }).sort({ timestamp: 1 }).lean();

            const logsByAttendanceId = {};
            logs.forEach(log => {
                const aid = log.attendanceId?.toString?.() ?? String(log.attendanceId);
                if (!aid) return;
                if (!logsByAttendanceId[aid]) logsByAttendanceId[aid] = [];
                logsByAttendanceId[aid].push(log);
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

        res.json({
            data: {
                attendance: attendanceForResponse,
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
                stats: {
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
                }
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

module.exports = { checkIn, checkOut, getTodayAttendance, getAttendanceHistory, getMonthAttendance, getFineCalculation };
