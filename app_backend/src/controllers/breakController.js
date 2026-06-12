const Break = require('../models/Break');
const Device = require('../models/Device');
const Staff = require('../models/Staff');
const Company = require('../models/Company');
const Attendance = require('../models/Attendance');
const AttendanceLog = require('../models/AttendanceLog');
const digitalOceanService = require('../services/digitalOceanService');
const { getEffectiveFineConfig, calculateFineAmount } = require('../utils/fineCalculationHelper');
const { getShiftTimings, calculateWorkHoursFromShift } = require('../utils/leaveAttendanceHelper');

function buildBreakLocation(payload = {}) {
    const latitude = payload.latitude ?? payload.lat ?? null;
    const longitude = payload.longitude ?? payload.lng ?? null;
    return {
        latitude: latitude != null ? Number(latitude) : null,
        longitude: longitude != null ? Number(longitude) : null,
        address: payload.address || '',
        area: payload.area || '',
        city: payload.city || '',
        pincode: payload.pincode || ''
    };
}

/** Client clocks may skew; ISO may parse oddly. All stored instants are authoritative UTC on server. */
const MAX_CLIENT_CLOCK_SKEW_MS = 5 * 60 * 1000;

/**
 * Fallback daily break allowance (minutes) used when the shift break policy does not
 * configure one (policy disabled or allowedMinutes=0). Keeps the app showing a concrete
 * break balance (default 1 hour/day) instead of "Unlimited". Fines stay OFF unless the
 * admin explicitly enables them on the shift break policy.
 */
const DEFAULT_BREAK_ALLOWED_MINUTES = 60;

function resolveServerBreakStartTime(clientStartInput) {
    const nowMs = Date.now();
    if (clientStartInput == null || clientStartInput === '') {
        return new Date(nowMs);
    }
    const ms = new Date(clientStartInput).getTime();
    if (!Number.isFinite(ms)) {
        return new Date(nowMs);
    }
    if (ms > nowMs + MAX_CLIENT_CLOCK_SKEW_MS) {
        console.warn('[Break] startBreak: client startTime in future; using server now');
        return new Date(nowMs);
    }
    if (ms < nowMs - 48 * 60 * 60 * 1000) {
        console.warn('[Break] startBreak: client startTime too far in past; using server now');
        return new Date(nowMs);
    }
    return new Date(ms);
}

/**
 * Never persist endTime < startTime (fixes bad attendance/break rows when client sends wrong instant).
 * Uses server time when client end is missing, invalid, before start, or too far in the future.
 */
function resolveServerBreakEndTime(breakStart, clientEndInput) {
    const startMs = new Date(breakStart).getTime();
    const nowMs = Date.now();
    if (!Number.isFinite(startMs)) {
        return new Date(nowMs);
    }
    let endMs = nowMs;
    if (clientEndInput != null && clientEndInput !== '') {
        const parsed = new Date(clientEndInput).getTime();
        if (Number.isFinite(parsed) && parsed >= startMs && parsed <= nowMs + MAX_CLIENT_CLOCK_SKEW_MS) {
            endMs = parsed;
        } else {
            console.warn('[Break] endBreak: invalid client endTime; using server now', {
                clientEndInput,
                startMs,
                nowMs
            });
        }
    }
    if (endMs < startMs) {
        console.warn('[Break] endBreak: end before start after resolve; clamping to max(now, start+1s)');
        endMs = Math.max(nowMs, startMs + 1000);
    }
    return new Date(endMs);
}

function serializeBreak(doc) {
    if (!doc) return null;
    const startTime = doc.startTime ? new Date(doc.startTime) : null;
    const endTime = doc.endTime ? new Date(doc.endTime) : null;
    return {
        id: doc._id?.toString?.() || doc.id,
        employeeID: doc.employeeID?.toString?.() || doc.employeeID,
        tenantId: doc.tenantId?.toString?.() || doc.tenantId,
        deviceId: doc.deviceId || '',
        source: doc.source || '',
        startTime,
        endTime,
        totalSeconds: doc.totalSeconds ?? null,
        breakMin: doc.breakMin ?? 0,
        breakCount: doc.breakCount ?? 0,
        breakFineMins: doc.breakFineMins ?? 0,
        breakFineAmount: doc.breakFineAmount ?? 0,
        durationSeconds: !endTime && startTime ? Math.max(0, Math.floor((Date.now() - startTime.getTime()) / 1000)) : (doc.totalSeconds ?? 0),
        breakStartSelfie: doc.breakStartSelfie || '',
        breakEndSelfie: doc.breakEndSelfie || '',
        breakStartLocation: doc.breakStartLocation || {},
        breakEndLocation: doc.breakEndLocation || {}
    };
}

function buildAddressString(address, area, city, pincode) {
    return [address, area, city, pincode]
        .map(value => value == null ? '' : String(value).trim())
        .filter(Boolean)
        .join(', ');
}

async function createBreakLog({
    attendanceId,
    breakDoc,
    action,
    performedBy,
    performedByName,
    performedByEmail,
    selfieUrl,
    timestamp,
    startAddress,
    endAddress,
    startLocation,
    endLocation,
    totalSeconds,
    breakSummary,
    payload
}) {
    if (!breakDoc?._id || !performedBy) return;
    const logPayload = {
        // Use the day's attendance _id so attendance detail can fetch break logs.
        attendanceId: attendanceId || breakDoc._id,
        action,
        performedBy,
        performedByName: performedByName || undefined,
        performedByEmail: performedByEmail || undefined,
        selfieUrl: selfieUrl || undefined,
        timestamp: timestamp || new Date(),
        notes: `Break ${action === 'BREAK_START' ? 'started' : 'ended'} from app`,
        newValue: payload
    };

    if (action === 'BREAK_START') {
        logPayload.breakStartDateTime = breakDoc.startTime || timestamp || undefined;
        logPayload.breakStartAddress = startAddress || undefined;
        logPayload.breakStartLocation = startLocation || undefined;
    } else if (action === 'BREAK_END') {
        logPayload.breakStartDateTime = breakDoc.startTime || undefined;
        logPayload.breakEndDateTime = breakDoc.endTime || timestamp || undefined;
        logPayload.totalBreakSeconds = totalSeconds ?? breakDoc.totalSeconds ?? undefined;
        logPayload.breakStartAddress = startAddress || undefined;
        logPayload.breakEndAddress = endAddress || undefined;
        logPayload.breakStartLocation = startLocation || undefined;
        logPayload.breakEndLocation = endLocation || undefined;
        if (breakSummary) {
            logPayload.break = breakSummary;
        }
    }

    await AttendanceLog.create(logPayload)
        .catch(err => console.warn(`[AttendanceLog] ${action} create failed:`, err?.message));
}

async function getAttendanceIdForDate(employeeId, eventDate) {
    if (!employeeId || !eventDate) return null;
    const dt = new Date(eventDate);
    if (Number.isNaN(dt.getTime())) return null;
    const dayStart = new Date(Date.UTC(
        dt.getUTCFullYear(),
        dt.getUTCMonth(),
        dt.getUTCDate()
    ));
    const dayEnd = new Date(dayStart);
    dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);
    const attendanceDoc = await Attendance.findOne({
        employeeId,
        date: { $gte: dayStart, $lt: dayEnd }
    }).select('_id').lean();
    return attendanceDoc?._id || null;
}

function calculateSalaryStructure(salary = {}) {
    const grossSalary =
        (salary.basicSalary || 0)
        + (salary.dearnessAllowance || 0)
        + (salary.houseRentAllowance || 0)
        + (salary.specialAllowance || 0);
    const employeePF = grossSalary * ((salary.employeePFRate || 0) / 100);
    const employeeESI = grossSalary * ((salary.employeeESIRate || 0) / 100);
    const netMonthlySalary = grossSalary - employeePF - employeeESI;
    return { monthly: { grossSalary, netMonthlySalary } };
}

function resolveBreakDurationMinutes(breakDoc) {
    if (Number.isFinite(Number(breakDoc?.totalSeconds)) && Number(breakDoc.totalSeconds) >= 0) {
        return Math.max(0, Math.round(Number(breakDoc.totalSeconds) / 60));
    }
    const start = breakDoc?.startTime ? new Date(breakDoc.startTime).getTime() : null;
    const end = breakDoc?.endTime ? new Date(breakDoc.endTime).getTime() : null;
    if (!start || !end || end < start) return 0;
    return Math.max(0, Math.round((end - start) / (1000 * 60)));
}

/**
 * Tri-state parse of a shift `breakPolicy.enabled` flag coming from API / Mongo.
 * Mirrors the app's readBreakPolicyEnabledFromMap (bool, int 0/1, string "true"/"false").
 * Returns:
 *   true  -> breaks explicitly enabled for the shift
 *   false -> breaks explicitly disabled for the shift (block start)
 *   null  -> not configured / legacy row (caller preserves prior behaviour)
 */
function parseBreakPolicyEnabled(breakPolicy) {
    if (!breakPolicy || typeof breakPolicy !== 'object') return null;
    const e = breakPolicy.enabled;
    if (typeof e === 'boolean') return e;
    if (typeof e === 'number') return e !== 0;
    if (typeof e === 'string') {
        const s = e.trim().toLowerCase();
        if (s === 'true' || s === '1' || s === 'yes') return true;
        if (s === 'false' || s === '0' || s === 'no') return false;
    }
    return null;
}

async function getBreakFineContext(staff, dayDate) {
    const company = await Company.findById(staff.businessId)
        .select('settings.payroll.fineCalculation settings.attendance.shifts settings.business.timezone settings.business.weeklyOffPattern settings.business.weeklyHolidays settings.attendance.timezone timezone')
        .lean();
    const payrollFineConfig = getEffectiveFineConfig(company || {});

    let dailyNet = 0;
    let dailyGross = 0;
    if (staff?.salary) {
        const salaryStructure = calculateSalaryStructure(staff.salary);
        const monthlyNet = Number(salaryStructure?.monthly?.netMonthlySalary) || 0;
        const monthlyGross = Number(salaryStructure?.monthly?.grossSalary) || 0;
        // Per-day denominator follows the company-level basis on the businesses table
        // (settings.payroll.fineCalculation.daysBasis): fixed days / exclude week-offs /
        // calendar days. Default (incl. legacy docs) is exclude-week-offs. Falls back to
        // 30 when unresolvable. Same basis as the check-in/out fine.
        let denominatorDays = 30;
        try {
            const { resolveFineDenominatorDays } = require('../utils/fineCalculationHelper');
            const { getWeekOffConfigForStaff } = require('../utils/weekOffHelper');
            const day = dayDate ? new Date(dayDate) : new Date();
            const weekCfg = await getWeekOffConfigForStaff(staff, company);
            const resolved = resolveFineDenominatorDays({
                company,
                year: day.getFullYear(),
                month1: day.getMonth() + 1,
                weeklyOffPattern: weekCfg?.weeklyOffPattern,
                weeklyHolidays: weekCfg?.weeklyHolidays,
            });
            if (Number.isFinite(resolved) && resolved > 0) denominatorDays = resolved;
        } catch (denErr) {
            console.error('[Break Fine] days-basis denominator resolve failed, using 30:', denErr?.message);
        }
        if (monthlyNet > 0) dailyNet = monthlyNet / denominatorDays;
        if (monthlyGross > 0) dailyGross = monthlyGross / denominatorDays;
    }
    // App-sent per-day rates are a fallback only when the salary structure is unavailable,
    // so the configured payable-days rule governs the break fine when salary is known.
    if (dailyNet <= 0) dailyNet = Number(staff?.appPerDayNetSalary) || 0;
    if (dailyGross <= 0) dailyGross = Number(staff?.appPerdayGrossSalary) || 0;
    if (dailyGross <= 0) dailyGross = dailyNet;

    const shiftTiming = getShiftTimings(company || {}, staff, dayDate, staff?.joiningDate || null, null);
    const shiftBreakPolicy = shiftTiming?.breakPolicy || {};
    // Open shifts are fined for early exit (under-worked hours) ONLY — never for
    // late arrival or break overage. Time spent on breaks already reduces worked
    // hours, so it is captured by the early-exit shortfall; charging a separate
    // break fine would double-count it.
    const shiftTypeLower = (shiftTiming?.shiftType || '').toString().toLowerCase();
    const isOpenShift = shiftTypeLower === 'open' || shiftTypeLower === 'open shift';
    const policyEnabledExplicit = parseBreakPolicyEnabled(shiftBreakPolicy);
    const policyEnabled = shiftBreakPolicy?.enabled === true;
    const configuredAllowedBreakMin = Math.max(0, Number(shiftBreakPolicy?.allowedMinutes || 0));
    // Scenario 3: disabled + quota > 0 → breaks are allowed but ALL minutes go to fine.
    const isDisabledWithQuota = policyEnabledExplicit === false && configuredAllowedBreakMin > 0;
    const hasConfiguredAllowance = policyEnabled && configuredAllowedBreakMin > 0;
    // Business rules:
    // - Enabled + quota > 0: allowance = configured value.
    // - Disabled + quota > 0: allowance = 0 so every minute is "exceeded" and fined.
    // - Enabled/disabled + quota = 0: use default 60-min display allowance (no fines).
    const effectiveAllowedBreakMin = hasConfiguredAllowance
        ? configuredAllowedBreakMin
        : (isDisabledWithQuota ? 0 : DEFAULT_BREAK_ALLOWED_MINUTES);
    const isUnlimitedBreak = false;
    // Fines apply when:
    //   (a) enabled + quota > 0 + fineEnabled, OR
    //   (b) disabled + quota > 0 (all break is fine, open shifts excluded).
    const breakFineEnabled =
        !isOpenShift && (
            isDisabledWithQuota ||
            (policyEnabled && hasConfiguredAllowance && shiftBreakPolicy?.fineEnabled === true)
        );
    const allowedBreakMin = effectiveAllowedBreakMin;

    let fineConfig = payrollFineConfig;
    if (breakFineEnabled) {
        const fineType = String(shiftBreakPolicy?.fineType || '1xSalary');
        if (fineType === 'custom') {
            fineConfig = {
                enabled: true,
                calculationType: 'fixedPerHour',
                finePerHour: Math.max(0, Number(shiftBreakPolicy?.customFinePerHour || 0)),
                fineRules: []
            };
        } else {
            fineConfig = {
                enabled: true,
                calculationType: 'shiftBased',
                finePerHour: 0,
                fineRules: [{ type: fineType, applyTo: 'earlyExit' }]
            };
        }
    } else {
        fineConfig = { ...payrollFineConfig, enabled: false };
    }

    let shiftHours = 9;
    if (isOpenShift) {
        const openHours = Number(shiftTiming?.openWorkHours || shiftTiming?.workHours);
        if (Number.isFinite(openHours) && openHours > 0) shiftHours = openHours;
    } else {
        const fixedHours = calculateWorkHoursFromShift(shiftTiming?.startTime || '09:30', shiftTiming?.endTime || '18:30');
        if (Number.isFinite(fixedHours) && fixedHours > 0) shiftHours = fixedHours;
    }

    return {
        allowedBreakMin,
        fineConfig,
        breakPolicy: {
            enabled: policyEnabled,
            // Tri-state: false only when the shift explicitly disables breaks.
            // Legacy shifts without a configured policy stay null so startBreak
            // preserves prior behaviour instead of blocking them.
            enabledExplicit: policyEnabledExplicit,
            // True only when breaks are enabled AND a real allowance (allowedMinutes > 0)
            // was set. Enabled-but-unconfigured (allowedMinutes = 0) reports false so
            // callers can block with a "contact HR" message instead of silently
            // falling back to the default allowance.
            configured: hasConfiguredAllowance,
            // Raw configured value from the shift template (before fallback).
            configuredAllowedMinutes: configuredAllowedBreakMin,
            // True when break is disabled but a quota was set → breaks allowed, all as fine.
            isDisabledWithQuota,
            isUnlimitedBreak,
            allowedMinutes: effectiveAllowedBreakMin,
            fineEnabled: breakFineEnabled,
            fineType: String(shiftBreakPolicy?.fineType || '1xSalary'),
            customFinePerHour: Math.max(0, Number(shiftBreakPolicy?.customFinePerHour || 0))
        },
        dailyNet,
        dailyGross,
        shiftHours
    };
}

async function uploadBreakSelfie(base64String, req, companyId, employeeName, type) {
    try {
        if (!base64String) return null;
        let base64Data = base64String;
        if (base64String.startsWith('data:image')) {
            base64Data = base64String.replace(/^data:image\/\w+;base64,/, '');
        }
        const buffer = Buffer.from(base64Data, 'base64');
        const now = new Date();
        const monthFolder = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
        const baseFolder = digitalOceanService.getBaseFolder(req);
        const targetFolder = `${baseFolder}/ekta_hr/break/s/${monthFolder}`;
        const fileName = digitalOceanService.generateSecureFileName(
            String(type || 'break-start').replace('-', '_'),
            'jpg'
        );
        const result = await digitalOceanService.uploadImage(buffer, targetFolder, {
            fileName,
            format: 'jpg'
        });
        return result.success ? result.url : null;
    } catch (error) {
        console.error('[Break] Selfie upload error:', error.message);
        return null;
    }
}

/**
 * Upload a break selfie to Spaces AFTER the HTTP response so the user is not blocked
 * on S3 latency. Back-fills breakStartSelfie / breakEndSelfie on the Break doc once
 * the upload succeeds (mirrors the deferred attendance-selfie path).
 */
function scheduleDeferredBreakSelfieUpload(breakId, base64String, req, companyId, employeeName, type, fieldKey) {
    if (!base64String) return;
    setImmediate(() => {
        void (async () => {
            const t0 = Date.now();
            try {
                const url = await uploadBreakSelfie(base64String, req, companyId, employeeName, type);
                if (url) {
                    await Break.findByIdAndUpdate(breakId, { [fieldKey]: url });
                }
                console.log('[Break] deferred selfie upload', {
                    breakId: String(breakId),
                    fieldKey,
                    ms: Date.now() - t0,
                    ok: Boolean(url)
                });
            } catch (e) {
                console.error('[Break] deferred selfie upload failed', String(breakId), fieldKey, e?.message);
            }
        })();
    });
}

/** Same UTC calendar day as attendances.date / check-in (midnight UTC). */
function startOfUtcDay(d = new Date()) {
    const x = new Date(d);
    return new Date(Date.UTC(
        x.getUTCFullYear(),
        x.getUTCMonth(),
        x.getUTCDate(),
        0, 0, 0, 0
    ));
}

/**
 * End any open break rows whose startTime is before today's UTC day start.
 * Matches attendance check-in day logic so yesterday's unfinished break does not
 * block startBreak or inflate today's break timer.
 */
exports.closeStaleOpenBreaksForStaff = async function closeStaleOpenBreaksForStaff(staff) {
    if (!staff?._id || !staff.businessId) return { closed: 0 };
    const dayStart = startOfUtcDay(new Date());
    const stale = await Break.find({
        employeeID: staff._id,
        tenantId: staff.businessId,
        endTime: null,
        startTime: { $lt: dayStart }
    });
    let closed = 0;
    for (const doc of stale) {
        const startMs = new Date(doc.startTime).getTime();
        if (!Number.isFinite(startMs)) {
            doc.endTime = dayStart;
            doc.totalSeconds = 0;
            await doc.save();
            closed += 1;
            continue;
        }
        let endMs = dayStart.getTime();
        if (endMs <= startMs) {
            endMs = startMs + 1000;
        }
        const endBoundary = new Date(endMs);
        const totalSeconds = Math.max(
            0,
            Math.floor((endBoundary.getTime() - startMs) / 1000)
        );
        doc.endTime = endBoundary;
        doc.totalSeconds = totalSeconds;
        await doc.save();
        closed += 1;
    }
    if (closed > 0) {
        await Staff.updateOne(
            { _id: staff._id },
            { $set: { monitoringStatus: 'active' } }
        ).catch(() => {});
        console.log('[Break] closeStaleOpenBreaksForStaff closed=%s staff=%s', closed, staff._id?.toString?.());
    }
    return { closed };
};

async function getActiveBreak(staff) {
    return Break.findOne({
        employeeID: staff._id,
        tenantId: staff.businessId,
        endTime: null
    }).sort({ startTime: -1 });
}

function getAppDeviceId(staffId) {
    return `app:${staffId}`;
}

exports.getCurrentBreak = async (req, res) => {
    try {
        if (!req.staff?._id) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        const staff = await Staff.findById(req.staff._id).select('_id businessId');
        if (!staff?.businessId) {
            return res.status(404).json({ success: false, message: 'Staff business not found' });
        }
        await exports.closeStaleOpenBreaksForStaff(staff);
        const activeBreak = await getActiveBreak(staff);
        return res.status(200).json({
            success: true,
            hasActiveBreak: !!activeBreak,
            data: serializeBreak(activeBreak)
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

/**
 * GET /api/breaks/today
 * Authoritative daily break summary for the logged-in employee:
 * - today's breaks (UTC day, ascending by startTime, including the live ongoing one)
 * - total break time used today (completed + live elapsed)
 * - allowed break minutes from the shift break policy + remaining balance
 * Used by the dashboard punch card (list + total) and the break screen (balance).
 */
exports.getTodayBreakSummary = async (req, res) => {
    try {
        if (!req.staff?._id) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        const staff = await Staff.findById(req.staff._id)
            .select('_id businessId appPerDayNetSalary appPerdayGrossSalary salary joiningDate shiftId shiftName');
        if (!staff?.businessId) {
            return res.status(404).json({ success: false, message: 'Staff business not found' });
        }

        await exports.closeStaleOpenBreaksForStaff(staff);

        const now = new Date();
        const dayStart = startOfUtcDay(now);
        const dayEnd = new Date(dayStart);
        dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);

        const [rows, fineCtx] = await Promise.all([
            Break.find({
                employeeID: staff._id,
                tenantId: staff.businessId,
                startTime: { $gte: dayStart, $lt: dayEnd }
            }).sort({ startTime: 1 }).lean(),
            getBreakFineContext(staff, now)
        ]);

        const nowMs = now.getTime();
        let totalSeconds = 0;
        let activeBreak = null;
        const breaks = rows.map((doc) => {
            const startTime = doc.startTime ? new Date(doc.startTime) : null;
            const endTime = doc.endTime ? new Date(doc.endTime) : null;
            const ongoing = !endTime;
            let durationSeconds;
            if (ongoing) {
                durationSeconds = startTime
                    ? Math.max(0, Math.floor((nowMs - startTime.getTime()) / 1000))
                    : 0;
            } else if (Number.isFinite(Number(doc.totalSeconds)) && Number(doc.totalSeconds) >= 0) {
                durationSeconds = Number(doc.totalSeconds);
            } else if (startTime && endTime) {
                durationSeconds = Math.max(0, Math.floor((endTime.getTime() - startTime.getTime()) / 1000));
            } else {
                durationSeconds = 0;
            }
            totalSeconds += durationSeconds;
            const entry = {
                id: doc._id?.toString?.() || doc.id,
                startTime,
                endTime,
                ongoing,
                durationSeconds,
                durationMin: Math.round(durationSeconds / 60)
            };
            if (ongoing) activeBreak = serializeBreak(doc);
            return entry;
        });

        const totalBreakMin = Math.round(totalSeconds / 60);
        const isUnlimited = fineCtx.breakPolicy.isUnlimitedBreak;
        const allowedMinutes = fineCtx.breakPolicy.allowedMinutes;
        const allowedSeconds = isUnlimited ? null : allowedMinutes * 60;
        const remainingMin = isUnlimited
            ? null
            : Math.max(0, allowedMinutes - totalBreakMin);
        const remainingSeconds = isUnlimited
            ? null
            : Math.max(0, (allowedMinutes * 60) - totalSeconds);

        return res.status(200).json({
            success: true,
            data: {
                breaks,
                totalBreakSeconds: totalSeconds,
                totalBreakMin,
                totalBreakCount: breaks.length,
                policyEnabled: fineCtx.breakPolicy.enabled,
                // True only when the shift explicitly disabled breaks (not legacy).
                // The app uses this to block starting a new break.
                policyDisabled: fineCtx.breakPolicy.enabledExplicit === false,
                // False when breaks are enabled but no allowance was configured
                // (allowedMinutes = 0). The app blocks starting a break in that case
                // with a "contact HR" message.
                policyConfigured: fineCtx.breakPolicy.configured,
                // Raw allowance from the shift template (0 when not set).
                configuredAllowedMinutes: fineCtx.breakPolicy.configuredAllowedMinutes ?? 0,
                // True when disabled + quota > 0: breaks allowed, all minutes → fine.
                policyIsDisabledWithQuota: fineCtx.breakPolicy.isDisabledWithQuota ?? false,
                isUnlimited,
                allowedMinutes,
                allowedSeconds,
                remainingMin,
                remainingSeconds,
                hasActiveBreak: !!activeBreak,
                activeBreak
            }
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

exports.startBreak = async (req, res) => {
    try {
        const { latitude, longitude, selfie, startTime } = req.body;
        if (!req.staff?._id) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        if (latitude === undefined || longitude === undefined) {
            return res.status(400).json({ success: false, message: 'Location coordinates are missing' });
        }
        if (!selfie) {
            return res.status(400).json({ success: false, message: 'Break start selfie is required' });
        }

        const staff = await Staff.findById(req.staff._id).select('_id businessId name email userId appPerDayNetSalary appPerdayGrossSalary salary joiningDate shiftId shiftName');
        if (!staff?.businessId) {
            return res.status(404).json({ success: false, message: 'Staff business not found' });
        }

        await exports.closeStaleOpenBreaksForStaff(staff);
        const activeBreak = await getActiveBreak(staff);
        if (activeBreak) {
            return res.status(409).json({
                success: false,
                message: 'You are already on break. End that break to start a new one.',
                data: serializeBreak(activeBreak)
            });
        }

        // Selfie goes to Spaces AFTER we respond (see deferred upload below), so the
        // user is not blocked on S3 latency. The Break doc starts with an empty selfie
        // and is back-filled once the upload finishes.
        const resolvedStartTime = resolveServerBreakStartTime(startTime);

        // Authoritative break-policy gate: the shift's breakPolicy decides whether
        // breaks are allowed at all. The app already hides the break button when the
        // policy is disabled, but enforce it server-side too so a break can never be
        // started for a shift that explicitly turned breaks off.
        const startFineCtx = await getBreakFineContext(staff, resolvedStartTime);
        // Block only when no quota is configured (quota = 0), regardless of enabled/disabled.
        // disabled + quota > 0 (isDisabledWithQuota): break is ALLOWED, all minutes go to fine.
        if (startFineCtx.breakPolicy.enabledExplicit === false && !startFineCtx.breakPolicy.isDisabledWithQuota) {
            return res.status(403).json({
                success: false,
                message: 'Break is not configured for your shift. Contact HR.'
            });
        }
        if (startFineCtx.breakPolicy.enabled === true && startFineCtx.breakPolicy.configured === false) {
            return res.status(403).json({
                success: false,
                message: 'Break is not configured for your shift. Contact HR.'
            });
        }

        // Breaks are only valid while the employee is actively punched in for that day:
        // a break cannot start before punch-in, nor after punch-out has happened.
        const breakDayStart = startOfUtcDay(resolvedStartTime);
        const breakDayEnd = new Date(breakDayStart);
        breakDayEnd.setUTCDate(breakDayEnd.getUTCDate() + 1);
        const todayAttendance = await Attendance.findOne({
            employeeId: staff._id,
            date: { $gte: breakDayStart, $lt: breakDayEnd }
        }).select('punchIn punchOut').lean();
        if (!todayAttendance || !todayAttendance.punchIn) {
            return res.status(409).json({
                success: false,
                message: 'Please punch in before starting a break.'
            });
        }
        if (todayAttendance.punchOut) {
            return res.status(409).json({
                success: false,
                message: 'You have already punched out. Breaks are not allowed after punch-out.'
            });
        }

        // Creating the break row and looking up today's attendance id are independent
        // (both keyed only off resolvedStartTime), so run them concurrently.
        const [doc, attendanceId] = await Promise.all([
            Break.create({
                employeeID: staff._id,
                deviceId: getAppDeviceId(staff._id),
                tenantId: staff.businessId,
                startTime: resolvedStartTime,
                source: 'app',
                breakStartSelfie: '',
                breakStartLocation: buildBreakLocation(req.body)
            }),
            getAttendanceIdForDate(staff._id, resolvedStartTime)
        ]);

        const breakStartAddress = buildAddressString(
            doc.breakStartLocation?.address,
            doc.breakStartLocation?.area,
            doc.breakStartLocation?.city,
            doc.breakStartLocation?.pincode
        );
        await createBreakLog({
            attendanceId,
            breakDoc: doc,
            action: 'BREAK_START',
            performedBy: req.user?._id || staff.userId || staff._id,
            performedByName: req.user?.name || staff.name,
            performedByEmail: req.user?.email || staff.email,
            selfieUrl: undefined,
            timestamp: doc.startTime,
            startAddress: breakStartAddress,
            startLocation: doc.breakStartLocation || {},
            payload: {
                breakId: doc._id,
                employeeID: doc.employeeID,
                tenantId: doc.tenantId,
                deviceId: doc.deviceId,
                source: doc.source,
                startTime: doc.startTime,
                endTime: doc.endTime,
                totalSeconds: doc.totalSeconds,
                breakStartSelfie: doc.breakStartSelfie || '',
                breakEndSelfie: doc.breakEndSelfie || '',
                breakStartLocation: doc.breakStartLocation || {},
                breakEndLocation: doc.breakEndLocation || {}
            }
        });

        await Staff.updateOne({ _id: staff._id }, { $set: { monitoringStatus: 'break' } });

        // Upload the selfie to Spaces off the request path; back-fill it on the Break doc.
        scheduleDeferredBreakSelfieUpload(
            doc._id,
            selfie,
            req,
            String(staff.businessId),
            staff.name,
            'break-start',
            'breakStartSelfie'
        );

        return res.status(201).json({
            success: true,
            message: 'Break started successfully',
            data: serializeBreak(doc)
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

exports.endBreak = async (req, res) => {
    try {
        const { id } = req.params;
        const { latitude, longitude, selfie, endTime } = req.body;
        if (!req.staff?._id) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        if (latitude === undefined || longitude === undefined) {
            return res.status(400).json({ success: false, message: 'Location coordinates are missing' });
        }
        if (!selfie) {
            return res.status(400).json({ success: false, message: 'Kindly End the Break' });
        }

        const staff = await Staff.findById(req.staff._id).select('_id businessId name email userId appPerDayNetSalary appPerdayGrossSalary salary joiningDate shiftId shiftName');
        if (!staff?.businessId) {
            return res.status(404).json({ success: false, message: 'Staff business not found' });
        }

        const doc = await Break.findOne({
            _id: id,
            employeeID: staff._id,
            tenantId: staff.businessId,
            endTime: null
        });

        if (!doc) {
            return res.status(404).json({ success: false, message: 'Break not found or already ended' });
        }

        const resolvedEndTime = resolveServerBreakEndTime(doc.startTime, endTime);
        const totalSeconds = Math.max(
            0,
            Math.floor((resolvedEndTime.getTime() - new Date(doc.startTime).getTime()) / 1000)
        );

        doc.endTime = resolvedEndTime;
        doc.totalSeconds = totalSeconds;
        // Selfie is uploaded to Spaces after the response and back-filled on the doc.
        doc.breakEndSelfie = '';
        doc.breakEndLocation = buildBreakLocation(req.body);
        // (single doc.save() below, after break-fine fields are computed)

        const dayStart = new Date(Date.UTC(
            resolvedEndTime.getUTCFullYear(),
            resolvedEndTime.getUTCMonth(),
            resolvedEndTime.getUTCDate()
        ));
        const dayEnd = new Date(dayStart);
        dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);

        // Today's attendance row and the break-fine context (Company lookup + shift
        // resolution) are independent reads — fetch them concurrently.
        const [attendanceDoc, fineCtx] = await Promise.all([
            Attendance.findOne({
                employeeId: staff._id,
                date: { $gte: dayStart, $lt: dayEnd }
            }).select('break').lean(),
            getBreakFineContext(staff, resolvedEndTime)
        ]);

        const previousTotalBreakMin = Number(attendanceDoc?.break?.totalBreakMin) || 0;
        const previousTotalFineAmount =
            Number(attendanceDoc?.break?.totalBreakFineAmount)
            || Number(attendanceDoc?.break?.breakFineAmount)
            || 0;
        const previousTotalFineMins =
            Number(attendanceDoc?.break?.totalBreakFineMins)
            || Number(attendanceDoc?.break?.breakFineMins)
            || 0;
        const previousTotalBreakCount = Number(attendanceDoc?.break?.totalBreakCount) || 0;
        const currentBreakMin = resolveBreakDurationMinutes(doc);

        const totalBreakAfterCurrent = previousTotalBreakMin + currentBreakMin;
        const totalFineMinsAfterCurrent = Math.max(0, totalBreakAfterCurrent - fineCtx.allowedBreakMin);
        const currentBreakFineMins = Math.max(0, totalFineMinsAfterCurrent - Math.max(0, previousTotalFineMins));
        const currentBreakFineAmount = currentBreakFineMins > 0
            ? calculateFineAmount(
                currentBreakFineMins,
                'earlyExit',
                fineCtx.fineConfig,
                fineCtx.dailyNet,
                fineCtx.shiftHours,
                fineCtx.dailyGross
            )
            : 0;
        const totalFineAmountAfterCurrent = previousTotalFineAmount + currentBreakFineAmount;
        const breakTestTag = '[BreakFine][formula][test]';
        console.log(
            breakTestTag,
            'incremental | prevTotalBreakMin=',
            previousTotalBreakMin,
            '| currentBreakMin=',
            currentBreakMin,
            '| allowedBreakMin=',
            fineCtx.allowedBreakMin,
            '| currentBreakFineMins=',
            currentBreakFineMins,
            '| prevTotalFineAmount=',
            previousTotalFineAmount,
            '| currentBreakFineAmount=',
            currentBreakFineAmount,
            '| totalFineAmountAfterCurrent=',
            totalFineAmountAfterCurrent
        );

        doc.breakMin = currentBreakMin;
        doc.breakCount = previousTotalBreakCount + 1;
        doc.breakFineMins = currentBreakFineMins;
        doc.breakFineAmount = currentBreakFineAmount;

        const breakEndAddress = buildAddressString(
            doc.breakEndLocation?.address,
            doc.breakEndLocation?.area,
            doc.breakEndLocation?.city,
            doc.breakEndLocation?.pincode
        );
        const breakStartAddress = buildAddressString(
            doc.breakStartLocation?.address,
            doc.breakStartLocation?.area,
            doc.breakStartLocation?.city,
            doc.breakStartLocation?.pincode
        );

        // Persist the break row, roll up today's attendance break totals, and resolve
        // the attendance id for the log — all independent, so run them concurrently.
        const [, , attendanceId] = await Promise.all([
            doc.save(),
            Attendance.updateOne(
                {
                    employeeId: staff._id,
                    date: { $gte: dayStart, $lt: dayEnd }
                },
                {
                    $set: {
                        break: {
                            totalBreakMin: totalBreakAfterCurrent,
                            totalBreakCount: previousTotalBreakCount + 1,
                            totalBreakFineMins: totalFineMinsAfterCurrent,
                            totalBreakFineAmount: totalFineAmountAfterCurrent,
                            breaks: [
                                ...((attendanceDoc?.break?.breaks && Array.isArray(attendanceDoc.break.breaks)) ? attendanceDoc.break.breaks : []),
                                {
                                    startTime: doc.startTime || null,
                                    endTime: doc.endTime || null,
                                    duration: currentBreakMin,
                                    BreakCount: previousTotalBreakCount + 1,
                                    breakFineMins: currentBreakFineMins,
                                    breakFineAmount: currentBreakFineAmount
                                }
                            ]
                        }
                    }
                }
            ),
            getAttendanceIdForDate(staff._id, doc.endTime || resolvedEndTime)
        ]);
        await createBreakLog({
            attendanceId,
            breakDoc: doc,
            action: 'BREAK_END',
            performedBy: req.user?._id || staff.userId || staff._id,
            performedByName: req.user?.name || staff.name,
            performedByEmail: req.user?.email || staff.email,
            selfieUrl: undefined,
            timestamp: doc.endTime,
            startAddress: breakStartAddress,
            endAddress: breakEndAddress,
            startLocation: doc.breakStartLocation || {},
            endLocation: doc.breakEndLocation || {},
            totalSeconds,
            breakSummary: {
                BreakMin: currentBreakMin,
                breakFineMins: currentBreakFineMins,
                breakFineAmount: currentBreakFineAmount
            },
            payload: {
                breakId: doc._id,
                employeeID: doc.employeeID,
                tenantId: doc.tenantId,
                deviceId: doc.deviceId,
                source: doc.source,
                startTime: doc.startTime,
                endTime: doc.endTime,
                totalSeconds: doc.totalSeconds,
                breakStartSelfie: doc.breakStartSelfie || '',
                breakEndSelfie: doc.breakEndSelfie || '',
                breakStartLocation: doc.breakStartLocation || {},
                breakEndLocation: doc.breakEndLocation || {},
                breakSummary: {
                    BreakMin: currentBreakMin,
                    breakFineMins: currentBreakFineMins,
                    breakFineAmount: currentBreakFineAmount
                },
                attendanceBreakTotals: {
                    totalBreakMin: totalBreakAfterCurrent,
                    totalBreakCount: previousTotalBreakCount + 1,
                    totalBreakFineMins: totalFineMinsAfterCurrent,
                    totalBreakFineAmount: totalFineAmountAfterCurrent
                }
            }
        });

        // Staff and Device status updates are independent — run concurrently.
        await Promise.all([
            Staff.updateOne({ _id: staff._id }, { $set: { monitoringStatus: 'active' } }),
            doc.deviceId
                ? Device.updateOne(
                    { deviceId: doc.deviceId },
                    { $set: { status: 'active', lastSeenAt: new Date() } }
                )
                : Promise.resolve()
        ]);

        // Upload the end selfie to Spaces off the request path; back-fill it on the doc.
        scheduleDeferredBreakSelfieUpload(
            doc._id,
            selfie,
            req,
            String(staff.businessId),
            staff.name,
            'break-end',
            'breakEndSelfie'
        );

        return res.status(200).json({
            success: true,
            message: 'Break ended successfully',
            data: serializeBreak(doc)
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};
