const Company = require('../models/Company');

// Admin endpoints to read/write per-shift attendance-template policies:
// breakPolicy, permissionPolicy, overtimePolicy on company.settings.attendance.shifts[].
// These are the same fields read at runtime by leaveAttendanceHelper.getShiftTimings and
// enforced in breakController / attendanceController / requestController.

const resolveBusinessId = (req) =>
    req.companyId || req.user?.companyId || req.staff?.businessId || null;

const BREAK_FINE_TYPES = ['1xSalary', '2xSalary', '3xSalary', 'custom'];
const PERMISSION_APPLY_TO = ['lateArrival', 'earlyExit', 'both'];

const toBool = (v) => v === true || v === 'true' || v === 1 || v === '1';
const nonNegNum = (v) => Math.max(0, Number(v) || 0);

// Validate + normalize an incoming breakPolicy payload. Returns { value } or { error }.
const normalizeBreakPolicy = (raw) => {
    if (raw === null) return { value: undefined }; // null = unconfigure (revert to legacy default)
    if (typeof raw !== 'object') return { error: 'breakPolicy must be an object or null' };
    const fineType = String(raw.fineType || '1xSalary');
    if (!BREAK_FINE_TYPES.includes(fineType)) {
        return { error: 'breakPolicy.fineType must be one of ' + BREAK_FINE_TYPES.join(', ') };
    }
    return {
        value: {
            enabled: toBool(raw.enabled),
            allowedMinutes: nonNegNum(raw.allowedMinutes),
            fineEnabled: toBool(raw.fineEnabled),
            fineType,
            customFinePerHour: nonNegNum(raw.customFinePerHour)
        }
    };
};

const normalizePermissionPolicy = (raw) => {
    if (raw === null) return { value: undefined };
    if (typeof raw !== 'object') return { error: 'permissionPolicy must be an object or null' };
    const applyTo = String(raw.applyTo || 'both');
    if (!PERMISSION_APPLY_TO.includes(applyTo)) {
        return { error: 'permissionPolicy.applyTo must be one of ' + PERMISSION_APPLY_TO.join(', ') };
    }
    return {
        value: {
            enabled: toBool(raw.enabled),
            monthlyQuotaMinutes: nonNegNum(raw.monthlyQuotaMinutes),
            // Daily permission allowance (the "Allocated Permission Minutes" the daily
            // attendance fine deducts against). Previously omitted here, so the fine
            // path always saw 0 and fined the entire used duration. Now persisted so
            // admins can configure a real per-day allowance.
            dailyAllowedMinutes: nonNegNum(raw.dailyAllowedMinutes),
            applyTo
        }
    };
};

const normalizeOvertimePolicy = (raw) => {
    if (raw === null) return { value: undefined };
    if (typeof raw !== 'object') return { error: 'overtimePolicy must be an object or null' };
    // enabled is tri-state: null/undefined = fall back to AttendanceTemplate.allowOvertime.
    let enabled = null;
    if (raw.enabled != null) enabled = toBool(raw.enabled);
    // multiplier null = use company-level overtimePaySettings.defaultMultiplier.
    let multiplier = null;
    if (raw.multiplier != null) {
        const m = Number(raw.multiplier);
        if (!Number.isFinite(m) || m <= 0) {
            return { error: 'overtimePolicy.multiplier must be a positive number or null' };
        }
        multiplier = m;
    }
    return { value: { enabled, multiplier } };
};

// @desc    List shifts with their policies for the caller's company
// @route   GET /api/shift-policies
// @access  Admin/HR
const getShiftPolicies = async (req, res) => {
    try {
        const businessId = resolveBusinessId(req);
        if (!businessId) {
            return res.status(400).json({ success: false, error: { message: 'Business context required' } });
        }
        const company = await Company.findById(businessId)
            .select('settings.attendance.shifts')
            .lean();
        const shifts = company?.settings?.attendance?.shifts || [];
        const data = shifts.map((s) => ({
            _id: s._id ? String(s._id) : null,
            name: s.name || null,
            shiftType: s.shiftType || 'standard',
            otBufferMinutes: s.otBufferMinutes ?? 0,
            breakPolicy: s.breakPolicy || null,
            permissionPolicy: s.permissionPolicy || null,
            overtimePolicy: s.overtimePolicy || null
        }));
        return res.json({ success: true, data: { shifts: data } });
    } catch (error) {
        console.error('Get Shift Policies Error:', error);
        return res.status(500).json({ success: false, error: { message: error.message || 'Failed to fetch shift policies' } });
    }
};

// @desc    Update break/permission/overtime policy on a specific shift
// @route   PUT /api/shift-policies/:shiftId
// @access  Admin/HR
// Body may include any subset of { breakPolicy, permissionPolicy, overtimePolicy }.
// Pass a policy as null to unconfigure it (revert that shift to legacy default behaviour).
const updateShiftPolicies = async (req, res) => {
    try {
        const businessId = resolveBusinessId(req);
        if (!businessId) {
            return res.status(400).json({ success: false, error: { message: 'Business context required' } });
        }
        const { shiftId } = req.params;
        if (!shiftId) {
            return res.status(400).json({ success: false, error: { message: 'shiftId is required' } });
        }

        const body = req.body || {};
        const hasBreak = Object.prototype.hasOwnProperty.call(body, 'breakPolicy');
        const hasPermission = Object.prototype.hasOwnProperty.call(body, 'permissionPolicy');
        const hasOvertime = Object.prototype.hasOwnProperty.call(body, 'overtimePolicy');
        if (!hasBreak && !hasPermission && !hasOvertime) {
            return res.status(400).json({
                success: false,
                error: { message: 'Provide at least one of breakPolicy, permissionPolicy, overtimePolicy' }
            });
        }

        // Validate/normalize each provided policy up front.
        const updates = {};
        if (hasBreak) {
            const r = normalizeBreakPolicy(body.breakPolicy);
            if (r.error) return res.status(400).json({ success: false, error: { message: r.error } });
            updates.breakPolicy = r.value;
        }
        if (hasPermission) {
            const r = normalizePermissionPolicy(body.permissionPolicy);
            if (r.error) return res.status(400).json({ success: false, error: { message: r.error } });
            updates.permissionPolicy = r.value;
        }
        if (hasOvertime) {
            const r = normalizeOvertimePolicy(body.overtimePolicy);
            if (r.error) return res.status(400).json({ success: false, error: { message: r.error } });
            updates.overtimePolicy = r.value;
        }

        const company = await Company.findById(businessId).select('settings.attendance.shifts');
        if (!company) {
            return res.status(404).json({ success: false, error: { message: 'Company not found' } });
        }
        const shifts = company.settings?.attendance?.shifts;
        if (!Array.isArray(shifts) || shifts.length === 0) {
            return res.status(404).json({ success: false, error: { message: 'No shifts configured for this company' } });
        }
        const shift = shifts.id ? shifts.id(shiftId) : shifts.find((s) => s._id && String(s._id) === String(shiftId));
        if (!shift) {
            return res.status(404).json({ success: false, error: { message: 'Shift not found' } });
        }

        // Apply. Assigning undefined clears the sub-doc (unconfigure); a plain object is cast to the sub-schema.
        Object.keys(updates).forEach((key) => {
            shift[key] = updates[key];
        });
        company.markModified('settings.attendance.shifts');
        await company.save();

        console.log('[ShiftPolicy][Update]', {
            businessId: String(businessId),
            shiftId: String(shiftId),
            updated: Object.keys(updates),
            by: req.user?._id ? String(req.user._id) : null
        });

        return res.json({
            success: true,
            data: {
                shift: {
                    _id: shift._id ? String(shift._id) : null,
                    name: shift.name || null,
                    breakPolicy: shift.breakPolicy || null,
                    permissionPolicy: shift.permissionPolicy || null,
                    overtimePolicy: shift.overtimePolicy || null
                }
            },
            message: 'Shift policies updated'
        });
    } catch (error) {
        console.error('Update Shift Policies Error:', error);
        return res.status(500).json({ success: false, error: { message: error.message || 'Failed to update shift policies' } });
    }
};

module.exports = { getShiftPolicies, updateShiftPolicies };
