const Leave = require('../models/Leave');
const Staff = require('../models/Staff');
const User = require('../models/User');
const LeaveTemplate = require('../models/LeaveTemplate');
const HolidayTemplate = require('../models/HolidayTemplate');
const Attendance = require('../models/Attendance');
const Company = require('../models/Company');
const mongoose = require('mongoose');
const { markAttendanceForApprovedLeave, calculateAvailableLeaves } = require('../utils/leaveAttendanceHelper');
const { getWeekOffConfigForStaff } = require('../utils/weekOffHelper');

// Helper for date calculation
const calculateDays = (start, end) => {
    const startDate = new Date(start);
    const endDate = new Date(end);
    const diffTime = Math.abs(endDate - startDate);
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24)) + 1;
    return diffDays;
};

/**
 * Normalize a date to the calendar day at midnight UTC.
 * Prevents timezone shift: e.g. 2026-02-02 00:00 IST → store as 2026-02-02T00:00:00.000Z
 * Uses the date components from the parsed value (local interpretation) then builds UTC midnight.
 */
const normalizeToDateOnlyUTC = (dateInput) => {
    const d = new Date(dateInput);
    if (isNaN(d.getTime())) return dateInput;
    return new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0));
};

/** Format date to YYYY-MM-DD (UTC). */
const toDateStringUTC = (date) => {
    const d = new Date(date);
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, '0');
    const day = String(d.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
};

/** All calendar dates between start and end (inclusive), no holiday/weekoff filtering. */
const getCalendarDatesInRange = (startDate, endDate) => {
    const start = new Date(startDate);
    const end = new Date(endDate);
    const dates = [];
    const current = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate(), 0, 0, 0, 0));
    const endUtc = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate(), 0, 0, 0, 0));
    while (current <= endUtc) {
        dates.push(toDateStringUTC(current));
        current.setUTCDate(current.getUTCDate() + 1);
    }
    return dates;
};

/**
 * Get list of calendar dates between start and end (inclusive), then remove holidays (staff's holiday template)
 * and weekoffs (staff's weekly holiday template). Returns array of UTC date strings YYYY-MM-DD.
 * @param {Object} staff - Staff with populated holidayTemplateId and weeklyHolidayTemplateId (or ids)
 * @param {Date} startDate - start (UTC midnight)
 * @param {Date} endDate - end (UTC midnight)
 * @returns {Promise<string[]>} effective work dates in range
 */
const getEffectiveWorkDatesInRange = async (staff, startDate, endDate) => {
    const start = new Date(startDate);
    const end = new Date(endDate);
    const dates = [];
    const current = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate(), 0, 0, 0, 0));
    const endUtc = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate(), 0, 0, 0, 0));
    while (current <= endUtc) {
        dates.push(toDateStringUTC(current));
        current.setUTCDate(current.getUTCDate() + 1);
    }
    if (dates.length === 0) return [];

    // Holidays: staff's holidayTemplateId or business fallback
    let holidayDateSet = new Set();
    const holidayTemplateId = staff?.holidayTemplateId;
    if (holidayTemplateId) {
        const template = typeof holidayTemplateId === 'object' && holidayTemplateId._id
            ? holidayTemplateId
            : await HolidayTemplate.findById(holidayTemplateId).lean();
        if (template?.holidays && Array.isArray(template.holidays)) {
            template.holidays.forEach((h) => {
                if (h.date) holidayDateSet.add(toDateStringUTC(h.date));
            });
        }
    }
    if (holidayDateSet.size === 0 && staff?.businessId) {
        const bizTemplate = await HolidayTemplate.findOne({ businessId: staff.businessId, isActive: true }).lean();
        if (bizTemplate?.holidays && Array.isArray(bizTemplate.holidays)) {
            bizTemplate.holidays.forEach((h) => {
                if (h.date) holidayDateSet.add(toDateStringUTC(h.date));
            });
        }
    }

    // Week-off: staff's weeklyHolidayTemplateId
    const company = staff?.businessId ? await Company.findById(staff.businessId).lean() : null;
    const weekOffConfig = await getWeekOffConfigForStaff(staff || {}, company);
    const { weeklyOffPattern, weeklyHolidays } = weekOffConfig;

    const effective = dates.filter((dateStr) => {
        if (holidayDateSet.has(dateStr)) return false;
        const d = new Date(dateStr + 'T00:00:00.000Z');
        const dayOfWeek = d.getUTCDay();
        let isWeekOff = false;
        if (weeklyOffPattern === 'oddEvenSaturday') {
            if (dayOfWeek === 0) isWeekOff = true;
            else if (dayOfWeek === 6) {
                const dayOfMonth = d.getUTCDate();
                if (dayOfMonth % 2 === 0) isWeekOff = true;
            }
        } else {
            isWeekOff = (weeklyHolidays || []).some((h) => h.day === dayOfWeek);
        }
        return !isWeekOff;
    });
    return effective;
};

/**
 * Filter a list of date strings (YYYY-MM-DD) to only those that are working days (not holiday, not weekoff) for the staff.
 * Used when client sends selectedDates from calendar picker.
 * @param {Object} staff - Staff with populated holidayTemplateId and weeklyHolidayTemplateId (or ids)
 * @param {string[]} dateStrings - Sorted array of YYYY-MM-DD
 * @returns {Promise<string[]>} subset that are working days
 */
const getEffectiveWorkDatesFromList = async (staff, dateStrings) => {
    if (!dateStrings || dateStrings.length === 0) return [];
    const unique = [...new Set(dateStrings)];

    let holidayDateSet = new Set();
    const holidayTemplateId = staff?.holidayTemplateId;
    if (holidayTemplateId) {
        const template = typeof holidayTemplateId === 'object' && holidayTemplateId._id
            ? holidayTemplateId
            : await HolidayTemplate.findById(holidayTemplateId).lean();
        if (template?.holidays && Array.isArray(template.holidays)) {
            template.holidays.forEach((h) => {
                if (h.date) holidayDateSet.add(toDateStringUTC(h.date));
            });
        }
    }
    if (holidayDateSet.size === 0 && staff?.businessId) {
        const bizTemplate = await HolidayTemplate.findOne({ businessId: staff.businessId, isActive: true }).lean();
        if (bizTemplate?.holidays && Array.isArray(bizTemplate.holidays)) {
            bizTemplate.holidays.forEach((h) => {
                if (h.date) holidayDateSet.add(toDateStringUTC(h.date));
            });
        }
    }

    const company = staff?.businessId ? await Company.findById(staff.businessId).lean() : null;
    const weekOffConfig = await getWeekOffConfigForStaff(staff || {}, company);
    const { weeklyOffPattern, weeklyHolidays } = weekOffConfig;

    const effective = unique.filter((dateStr) => {
        if (holidayDateSet.has(dateStr)) return false;
        const d = new Date(dateStr + 'T00:00:00.000Z');
        const dayOfWeek = d.getUTCDay();
        let isWeekOff = false;
        if (weeklyOffPattern === 'oddEvenSaturday') {
            if (dayOfWeek === 0) isWeekOff = true;
            else if (dayOfWeek === 6 && d.getUTCDate() % 2 === 0) isWeekOff = true;
        } else {
            isWeekOff = (weeklyHolidays || []).some((h) => h.day === dayOfWeek);
        }
        return !isWeekOff;
    });
    return effective.sort();
};

const getLeaves = async (req, res) => {
    try {
        const currentStaff = req.staff; // From middleware

        const { status, leaveType, page = 1, limit = 10, search, startDate, endDate } = req.query;
        const query = {};

        // Scope to current employee
        if (currentStaff) {
            query.employeeId = currentStaff._id;
        } else {
            return res.json({
                success: true,
                data: { leaves: [], pagination: { total: 0, page, limit, pages: 0 } }
            });
        }

        if (status && status !== 'all' && status !== 'All Status') query.status = status;
        if (leaveType && leaveType !== 'all') query.leaveType = leaveType;

        if (search) {
            query.$or = [
                { leaveType: { $regex: search, $options: 'i' } },
                { reason: { $regex: search, $options: 'i' } }
            ];
        }

        if (startDate || endDate) {
            // Robust UTC parsing: ignore local time shifts
            const parseDate = (d, isEnd) => {
                const date = new Date(d);
                const utc = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
                if (isEnd) utc.setUTCHours(23, 59, 59, 999);
                else utc.setUTCHours(0, 0, 0, 0);
                return utc;
            };

            const rangeStart = startDate ? parseDate(startDate, false) : new Date(0);
            const rangeEnd = endDate ? parseDate(endDate, true) : new Date(8640000000000000);

            // Simple, robust overlap query
            query.startDate = { $lte: rangeEnd };
            query.endDate = { $gte: rangeStart };
        }

        const skip = (Number(page) - 1) * Number(limit);

        const leaves = await Leave.find(query)
            .sort({ createdAt: -1 })
            .skip(skip)
            .limit(Number(limit))
            .lean();

        const total = await Leave.countDocuments(query);

        // Resolve approvedBy and rejectedBy: check Staff first, then User (same as Approved By)
        const toIdStr = (v) => (v && v._id != null ? v._id.toString() : v && v.toString ? v.toString() : null);
        const approvedByIds = [...new Set(leaves.map((l) => toIdStr(l.approvedBy)).filter(Boolean))];
        const rejectedByIds = [...new Set(leaves.map((l) => toIdStr(l.rejectedBy)).filter(Boolean))];
        const allIds = [...new Set([...approvedByIds, ...rejectedByIds])];
        const resolvedMap = {};
        for (const id of allIds) {
            const staff = await Staff.findById(id).select('name email').lean();
            if (staff) {
                resolvedMap[id] = { name: staff.name, email: staff.email || null };
            } else {
                const user = await User.findById(id).select('name email').lean();
                if (user) {
                    resolvedMap[id] = { name: user.name, email: user.email || null };
                }
            }
        }
        leaves.forEach((l) => {
            const aid = toIdStr(l.approvedBy);
            const rid = toIdStr(l.rejectedBy);
            if (aid) l.approvedBy = resolvedMap[aid] || (l.approvedBy && typeof l.approvedBy === 'object' && l.approvedBy.name ? l.approvedBy : null);
            if (rid) l.rejectedBy = resolvedMap[rid] || (l.rejectedBy && typeof l.rejectedBy === 'object' && l.rejectedBy.name ? l.rejectedBy : null);
        });

        // For app display "Half day on": prefer halfDayType (DB), then halfDaySession, then session
        const leavesWithHalfDayType = leaves.map((l) => {
            const halfDayType = l.halfDayType || l.halfDaySession ||
                (l.leaveType === 'Half Day' && (l.session === '1' ? 'First Half Day' : l.session === '2' ? 'Second Half Day' : null));
            if (l.leaveType === 'Half Day') {
                console.log('[getLeaves] Half Day leave', { id: l._id, rawHalfDayType: l.halfDayType, halfDaySession: l.halfDaySession, session: l.session, resolved: halfDayType });
            }
            return { ...l, halfDayType: halfDayType || undefined };
        });

        res.json({
            success: true,
            data: {
                leaves: leavesWithHalfDayType,
                pagination: {
                    page: Number(page),
                    limit: Number(limit),
                    total,
                    pages: Math.ceil(total / Number(limit))
                }
            }
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

const getLeaveTypes = async (req, res) => {
    try {
        const staffId = req.staff._id;
        const { month, year, startDate, endDate } = req.query;
        
        let rangeStart, rangeEnd;

        // Robust parsing: ignore local time shifts for boundaries
        const parseBoundaryDate = (d, isEnd) => {
            const date = new Date(d);
            if (isEnd) return new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999));
            return new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0));
        };

        if (startDate && endDate) {
            rangeStart = parseBoundaryDate(startDate, false);
            rangeEnd = parseBoundaryDate(endDate, true);
        } else {
            const now = new Date();
            const targetMonth = month ? parseInt(month) - 1 : now.getMonth();
            const targetYear = year ? parseInt(year) : now.getFullYear();
            rangeStart = new Date(Date.UTC(targetYear, targetMonth, 1, 0, 0, 0, 0));
            rangeEnd = new Date(Date.UTC(targetYear, targetMonth + 1, 0, 23, 59, 59, 999));
        }

        // 1. Fetch Approved leaves that overlap with the requested range
        const approvedLeaves = await Leave.find({
            employeeId: staffId,
            status: { $regex: /^approved$/i },
            startDate: { $lte: rangeEnd },
            endDate: { $gte: rangeStart }
        });

        // 2. Identify and group all leave types
        const staff = await Staff.findById(staffId).populate('leaveTemplateId');
        const typeGroups = new Map();

        // Single canonical key so "Casual Leave" and "Casual" (and "Sick Leave" / "Sick") count together
        const normalizeToKey = (str) => {
            const s = (str || '').toLowerCase().trim();
            const withoutLeave = s.replace(/\bleave\b/g, '').replace(/\s+/g, ' ').trim();
            return withoutLeave.replace(/\s+/g, '');
        };

        // Define default cards to show in UI
        const defaultTypes = ['Casual Leave', 'Sick Leave', 'Half Day', 'Earned Leave', 'Unpaid Leave'];

        // Add template types if they exist (avoid duplicate keys)
        if (staff?.leaveTemplateId?.leaveTypes) {
            staff.leaveTemplateId.leaveTypes.forEach(t => {
                if (t.type && !defaultTypes.some(dt => normalizeToKey(dt) === normalizeToKey(t.type))) {
                    defaultTypes.push(t.type);
                }
            });
        }

        // Initialize groups with original names (prefer default/template name for display)
        defaultTypes.forEach(t => {
            const key = normalizeToKey(t);
            if (!typeGroups.has(key)) {
                typeGroups.set(key, { originalName: t, takenCount: 0 });
            }
        });

        // 3. Process leaves and count days accurately within range (same key for "Casual" / "Casual Leave" etc.)
        approvedLeaves.forEach(l => {
            const key = normalizeToKey(l.leaveType);
            if (!typeGroups.has(key)) {
                typeGroups.set(key, { originalName: l.leaveType, takenCount: 0 });
            }

            const group = typeGroups.get(key);
            const lStart = new Date(l.startDate);
            const lEnd = new Date(l.endDate);

            // Use local components to be timezone-independent during the loop
            const current = new Date(Date.UTC(lStart.getFullYear(), lStart.getMonth(), lStart.getDate()));
            const end = new Date(Date.UTC(lEnd.getFullYear(), lEnd.getMonth(), lEnd.getDate()));

            while (current <= end) {
                // If this day of the leave falls within our filter range, count it
                if (current >= rangeStart && current <= rangeEnd) {
                    const typeKey = normalizeToKey(l.leaveType);
                    // Half Day stored as days=0.5; count 0.5 per day for display
                    if (typeKey === 'halfday') {
                        group.takenCount += 0.5;
                    } else {
                        group.takenCount += 1;
                    }
                }
                current.setUTCDate(current.getUTCDate() + 1);
            }
        });

        // Convert Map to response format
        const leaveSummary = Array.from(typeGroups.values()).map(g => ({
            type: g.originalName,
            takenCount: g.takenCount
        }));

        res.json({
            success: true,
            data: leaveSummary,
            range: { start: rangeStart, end: rangeEnd }
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

/**
 * Returns leave types for the Apply Leave dropdown: from staff's assigned leave template + Unpaid Leave.
 * Each item has { type, days } where days is the limit from template (null for Unpaid Leave).
 */
/**
 * Get availableCasualLeaves from the latest attendance record in the current month for this staff.
 * If the latest monthly attendance row does not carry availableCasualLeaves, caller should
 * fall back to leave-template-based calculation.
 * @param {ObjectId} employeeId - Staff/employee id
 * @returns {Promise<number|null>} available balance from latest current-month attendance row, or null
 */
const getAvailableCasualLeavesFromAttendances = async (employeeId) => {
    const now = new Date();
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1, 0, 0, 0, 0));
    const monthEnd = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0, 23, 59, 59, 999));
    const latest = await Attendance.findOne({
        $or: [{ employeeId }, { user: employeeId }],
        date: { $gte: monthStart, $lte: monthEnd }
    })
        .sort({ date: -1, updatedAt: -1, createdAt: -1 })
        .select('availableCasualLeaves')
        .lean();
    const val = latest?.availableCasualLeaves;
    return typeof val === 'number' && !Number.isNaN(val) ? Math.max(0, val) : null;
};

/**
 * Get total allowed leave days from staff's leave template. If multiple templates with same name
 * exist for the business, use the latest (by updatedAt).
 * @param {Object} staff - Staff document with populated leaveTemplateId
 * @returns {Promise<number>} sum of leaveTypes[].days from the latest template for that name+business
 */
const getTotalAllowedFromTemplate = async (staff) => {
    if (!staff?.leaveTemplateId) return 0;
    const assigned = staff.leaveTemplateId;
    const businessId = assigned.businessId || staff.businessId;
    const name = assigned.name;
    if (!businessId || !name) {
        const days = (assigned.leaveTypes || []).reduce((sum, t) => sum + (Number(t.days) || 0), 0);
        return days;
    }
    const latest = await LeaveTemplate.findOne({ businessId, name, isActive: true })
        .sort({ updatedAt: -1 })
        .lean();
    if (!latest?.leaveTypes || !Array.isArray(latest.leaveTypes)) return 0;
    return latest.leaveTypes.reduce((sum, t) => sum + (Number(t.days) || 0), 0);
};

/**
 * Get total leave days from staff's assigned template (sum of all leaveTypes[].days).
 * Used when attendances have no availableCasualLeaves - this is the pool for all leave types.
 * @param {Object} staff - Staff document with populated leaveTemplateId
 * @returns {number} sum of leaveTypes[].days (0 if no template)
 */
const getTotalLeavesFromAssignedTemplate = (staff) => {
    if (!staff?.leaveTemplateId?.leaveTypes || !Array.isArray(staff.leaveTemplateId.leaveTypes)) return 0;
    return staff.leaveTemplateId.leaveTypes.reduce(
        (sum, t) => sum + (Number(t.days) || Number(t.limit) || 0),
        0
    );
};

/**
 * Get available leave pool for balance validation.
 * - If current-month attendances have availableCasualLeaves for this staff: use latest document's value.
 * - If not: get total from template assigned to staff (sum of all leaveTypes[].days).
 * Do NOT reduce this balance using Approved/Pending leaves here.
 * @param {ObjectId} employeeId - Staff/employee id
 * @param {Object} staff - Staff document with populated leaveTemplateId
 * @returns {Promise<number>} available balance (0 if none)
 */
const getAvailableLeavePool = async (employeeId, staff) => {
    const fromAttendance = await getAvailableCasualLeavesFromAttendances(employeeId);
    if (typeof fromAttendance === 'number' && !Number.isNaN(fromAttendance)) {
        return fromAttendance;
    }
    // No current-month availableCasualLeaves in attendances: use template assigned to staff.
    const totalAllowed = getTotalLeavesFromAssignedTemplate(staff);
    return Math.max(0, totalAllowed);
};

const getLeaveTypesForApply = async (req, res) => {
    try {
        const staffId = req.staff._id;
        const staff = await Staff.findById(staffId).populate('leaveTemplateId');

        const list = [];

        // Static option: Half Day always visible (counts as 0.5 day, deducted from availableCasualLeaves)
        const hasHalfDay = list.some(t => (t.type || '').toLowerCase().replace(/\s+/g, '') === 'halfday');
        if (!hasHalfDay) {
            list.push({ type: 'Half Day', days: 0.5 });
        }

        if (staff?.leaveTemplateId?.leaveTypes && Array.isArray(staff.leaveTemplateId.leaveTypes)) {
            staff.leaveTemplateId.leaveTypes.forEach(t => {
                if (t.type) {
                    const typeNorm = (t.type || '').toLowerCase().replace(/\s+/g, '');
                    if (typeNorm === 'halfday') return; // already added as static
                    const days = t.days != null ? t.days : (t.limit != null ? t.limit : null);
                    list.push({ type: t.type, days });
                }
            });
        }

        const hasUnpaid = list.some(
            t => (t.type || '').toLowerCase().replace(/\s+/g, '') === 'unpaidleave'
        );
        if (!hasUnpaid) {
            list.push({ type: 'Unpaid Leave', days: null });
        }

        res.json({ success: true, data: list });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

/**
 * Classify selected date strings into: paid leave, pending leave, approved leave, week off, holiday.
 * Used by checkLeaveDates to return specific messages to the UI.
 * @returns {Promise<{ paidLeaveDates: string[], pendingLeaveDates: string[], approvedLeaveDates: string[], weekOffDates: string[], holidayDates: string[] }>}
 */
const getLeaveDateCheckDetails = async (employeeId, staff, dateStrings) => {
    const paidLeaveDates = [];
    const pendingLeaveDates = [];
    const approvedLeaveDates = [];
    const weekOffDates = [];
    const holidayDates = [];
    if (!dateStrings || dateStrings.length === 0) {
        return { paidLeaveDates, pendingLeaveDates, approvedLeaveDates, weekOffDates, holidayDates };
    }
    const dateSet = new Set(dateStrings);
    const objId = new mongoose.Types.ObjectId(employeeId.toString());
    const startUtc = new Date(dateStrings[0] + 'T00:00:00.000Z');
    const endUtc = new Date(dateStrings[dateStrings.length - 1] + 'T23:59:59.999Z');

    // Holidays
    let holidayDateSet = new Set();
    const holidayTemplateId = staff?.holidayTemplateId;
    if (holidayTemplateId) {
        const template = typeof holidayTemplateId === 'object' && holidayTemplateId._id
            ? holidayTemplateId
            : await HolidayTemplate.findById(holidayTemplateId).lean();
        if (template?.holidays && Array.isArray(template.holidays)) {
            template.holidays.forEach((h) => { if (h.date) holidayDateSet.add(toDateStringUTC(h.date)); });
        }
    }
    if (holidayDateSet.size === 0 && staff?.businessId) {
        const biz = await HolidayTemplate.findOne({ businessId: staff.businessId, isActive: true }).lean();
        if (biz?.holidays && Array.isArray(biz.holidays)) {
            biz.holidays.forEach((h) => { if (h.date) holidayDateSet.add(toDateStringUTC(h.date)); });
        }
    }
    dateStrings.forEach((d) => { if (holidayDateSet.has(d)) holidayDates.push(d); });

    // Week off
    const company = staff?.businessId ? await Company.findById(staff.businessId).lean() : null;
    const weekOffConfig = await getWeekOffConfigForStaff(staff || {}, company);
    const { weeklyOffPattern, weeklyHolidays } = weekOffConfig;
    dateStrings.forEach((dateStr) => {
        if (holidayDateSet.has(dateStr)) return;
        const d = new Date(dateStr + 'T00:00:00.000Z');
        const dayOfWeek = d.getUTCDay();
        let isWeekOff = false;
        if (weeklyOffPattern === 'oddEvenSaturday') {
            if (dayOfWeek === 0) isWeekOff = true;
            else if (dayOfWeek === 6 && d.getUTCDate() % 2 === 0) isWeekOff = true;
        } else {
            isWeekOff = (weeklyHolidays || []).some((h) => h.day === dayOfWeek);
        }
        if (isWeekOff) weekOffDates.push(dateStr);
    });

    // Paid leave (attendances with isPaidLeave)
    const paidAttendances = await Attendance.find({
        $or: [{ employeeId: objId }, { user: objId }],
        date: { $gte: startUtc, $lte: endUtc },
        isPaidLeave: true
    }).select('date').lean();
    paidAttendances.forEach((a) => {
        if (a.date) {
            const ds = toDateStringUTC(a.date);
            if (dateSet.has(ds)) paidLeaveDates.push(ds);
        }
    });

    // Pending and Approved leaves
    const leaves = await Leave.find({
        employeeId: objId,
        status: { $in: ['Pending', 'Approved'] },
        startDate: { $lte: endUtc },
        endDate: { $gte: startUtc }
    }).select('startDate endDate status').lean();
    dateStrings.forEach((dateStr) => {
        const day = new Date(dateStr + 'T12:00:00.000Z');
        for (const l of leaves) {
            const start = new Date(l.startDate);
            const end = new Date(l.endDate);
            if (day >= start && day <= end) {
                if (String(l.status).toLowerCase() === 'approved') {
                    approvedLeaveDates.push(dateStr);
                } else {
                    pendingLeaveDates.push(dateStr);
                }
                break;
            }
        }
    });

    return {
        paidLeaveDates: [...new Set(paidLeaveDates)],
        pendingLeaveDates: [...new Set(pendingLeaveDates)],
        approvedLeaveDates: [...new Set(approvedLeaveDates)],
        weekOffDates: [...new Set(weekOffDates)],
        holidayDates: [...new Set(holidayDates)]
    };
};

/**
 * Check if any of the given date strings (YYYY-MM-DD) have existing Approved/Pending leave or isPaidLeave in attendances for this employee.
 * @returns {Promise<boolean>} true if conflict
 */
const hasLeaveOrPaidLeaveConflict = async (employeeId, dateStrings) => {
    if (!dateStrings || dateStrings.length === 0) return false;
    const objId = new mongoose.Types.ObjectId(employeeId.toString());
    const startUtc = new Date(dateStrings[0] + 'T00:00:00.000Z');
    const endStr = dateStrings[dateStrings.length - 1];
    const endUtc = new Date(endStr + 'T23:59:59.999Z');
    const existingLeave = await Leave.findOne({
        employeeId: objId,
        status: { $in: ['Pending', 'Approved'] },
        startDate: { $lte: endUtc },
        endDate: { $gte: startUtc }
    });
    if (existingLeave) return true;
    const dateSet = new Set(dateStrings);
    const attendances = await Attendance.find({
        $or: [{ employeeId: objId }, { user: objId }],
        date: { $gte: startUtc, $lte: endUtc },
        isPaidLeave: true
    })
        .select('date')
        .lean();
    for (const a of attendances) {
        if (a.date && dateSet.has(toDateStringUTC(a.date))) return true;
    }
    return false;
};

/**
 * POST /leave/check-dates: For leave apply UI. Accepts either startDate+endDate (range) or selectedDates (array).
 * Returns effective work dates, hasConflict, and details for UI messages: paidLeaveDates, pendingLeaveDates, approvedLeaveDates, weekOffDates, holidayDates.
 */
const checkLeaveDates = async (req, res) => {
    try {
        const { startDate: startParam, endDate: endParam, selectedDates } = req.body;
        const staffId = req.staff._id;
        const staff = await Staff.findById(staffId)
            .populate('leaveTemplateId')
            .populate('holidayTemplateId')
            .populate('weeklyHolidayTemplateId');
        if (!staff) {
            return res.status(400).json({ success: false, error: { message: 'Staff not found' } });
        }
        let dateStrings;
        let effectiveDates;
        if (Array.isArray(selectedDates) && selectedDates.length > 0) {
            const normalized = selectedDates
                .map((d) => { const p = new Date(d); return isNaN(p.getTime()) ? null : toDateStringUTC(p); })
                .filter(Boolean);
            dateStrings = [...new Set(normalized)].sort();
            effectiveDates = await getEffectiveWorkDatesFromList(staff, dateStrings);
        } else if (startParam && endParam) {
            const startDate = normalizeToDateOnlyUTC(startParam);
            const endDate = normalizeToDateOnlyUTC(endParam);
            effectiveDates = await getEffectiveWorkDatesInRange(staff, startDate, endDate);
            dateStrings = effectiveDates;
        } else {
            return res.status(400).json({
                success: false,
                error: { message: 'Provide startDate and endDate, or selectedDates array' }
            });
        }
        const hasConflict = await hasLeaveOrPaidLeaveConflict(staffId, effectiveDates);
        const details = await getLeaveDateCheckDetails(staffId, staff, dateStrings || effectiveDates);
        res.json({
            success: true,
            data: {
                hasConflict,
                effectiveDates,
                effectiveDays: effectiveDates.length,
                paidLeaveDates: details.paidLeaveDates,
                pendingLeaveDates: details.pendingLeaveDates,
                approvedLeaveDates: details.approvedLeaveDates,
                weekOffDates: details.weekOffDates,
                holidayDates: details.holidayDates
            }
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

/**
 * GET /leave-balance: available pool from attendances (availableCasualLeaves) or from template assigned to staff (sum of leaveTypes.days minus used).
 */
const getLeaveBalance = async (req, res) => {
    try {
        const staffId = req.staff._id;
        const staff = await Staff.findById(staffId).populate('leaveTemplateId');
        const availableCasualLeaves = await getAvailableLeavePool(staffId, staff);
        const totalAllowed = staff ? await getTotalAllowedFromTemplate(staff) : 0;
        res.json({
            success: true,
            data: { availableCasualLeaves, totalAllowed }
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

/** Normalize leave type to a key for matching (e.g. "Casual Leave" and "Casual" both -> "casual"). */
const leaveTypeMatchKey = (s) => {
    if (!s || typeof s !== 'string') return '';
    return s.toLowerCase().trim().replace(/\s+leave\s*$/i, '').replace(/\s+/g, '');
};

// Map template/database leave type names to canonical values for consistent storage
const normalizeLeaveType = (raw) => {
    const t = (raw || '').trim().toLowerCase();
    if (!t) return null;
    if (/^\s*half\s*day\s*(leave)?\s*$/i.test(raw) || t === 'half day') return 'Half Day';
    if (/^\s*first\s*half\s*(leave)?\s*$/i.test(raw) || t === 'first half') return { canonical: 'Half Day', session: '1', halfDaySession: 'First Half Day' };
    if (/^\s*second\s*half\s*(leave)?\s*$/i.test(raw) || t === 'second half') return { canonical: 'Half Day', session: '2', halfDaySession: 'Second Half Day' };
    if (/^\s*first\s*half\s*day\s*$/i.test(raw) || (raw || '').trim() === 'First Half Day') return { canonical: 'Half Day', session: '1', halfDaySession: 'First Half Day' };
    if (/^\s*second\s*half\s*day\s*$/i.test(raw) || (raw || '').trim() === 'Second Half Day') return { canonical: 'Half Day', session: '2', halfDaySession: 'Second Half Day' };
    if (/^\s*casual\s*(leave)?\s*$/i.test(raw) || t === 'casual') return 'Casual Leave';
    if (/^\s*sick\s*(leave)?\s*$/i.test(raw) || t === 'sick') return 'Sick Leave';
    if (/^\s*earned\s*(leave)?\s*$/i.test(raw) || t === 'earned') return 'Earned Leave';
    if (/^\s*unpaid\s*(leave)?\s*$/i.test(raw) || t === 'unpaid') return 'Unpaid';
    if (/^\s*paid\s*(leave)?\s*$/i.test(raw) || t === 'paid') return 'Paid';
    if (/^\s*maternity\s*(leave)?\s*$/i.test(raw) || t === 'maternity') return 'Maternity';
    if (/^\s*paternity\s*(leave)?\s*$/i.test(raw) || t === 'paternity') return 'Paternity';
    if (/^\s*other\s*$/i.test(raw) || t === 'other') return 'Other';
    return raw.trim(); // Keep template-defined names as-is
};

const createLeave = async (req, res) => {
    try {
        console.log('[Leave Submit] Request Body:', JSON.stringify(req.body));
        console.log('[Leave Submit] leaveType value:', req.body?.leaveType, '(type:', typeof req.body?.leaveType, ')');

        let { startDate, endDate, leaveType, reason, session, halfDaySession, selectedDates } = req.body;
        const currentStaffId = req.staff._id;

        leaveType = (leaveType || '').trim();
        if (!leaveType) {
            return res.status(400).json({ success: false, error: { message: 'Leave type is required' } });
        }

        // Normalize to canonical value (matches DB/template names to expected format)
        const normalized = normalizeLeaveType(leaveType);
        if (normalized && typeof normalized === 'object') {
            leaveType = normalized.canonical;
            session = normalized.session;
            if (normalized.halfDaySession) halfDaySession = normalized.halfDaySession;
        } else if (normalized) {
            leaveType = normalized;
        }

        // Half-day: accept halfDaySession from client ('First Half Day' | 'Second Half Day') and set session 1/2
        if (leaveType === 'Half Day' && (halfDaySession === 'First Half Day' || halfDaySession === 'Second Half Day')) {
            session = halfDaySession === 'First Half Day' ? '1' : '2';
        }

        const staff = await Staff.findById(currentStaffId)
            .populate('leaveTemplateId')
            .populate('holidayTemplateId')
            .populate('weeklyHolidayTemplateId');

        if (!staff) {
            return res.status(400).json({ success: false, error: { message: 'Staff profile not found' } });
        }

        let effectiveDates;
        let startDateNorm;
        let endDateNorm;

        if (Array.isArray(selectedDates) && selectedDates.length > 0) {
            // Calendar selection: client sent list of selected dates (YYYY-MM-DD or ISO)
            const normalizedStrings = selectedDates
                .map((d) => {
                    const parsed = new Date(d);
                    if (isNaN(parsed.getTime())) return null;
                    return toDateStringUTC(parsed);
                })
                .filter(Boolean);
            if (normalizedStrings.length === 0) {
                return res.status(400).json({ success: false, error: { message: 'Invalid selected dates' } });
            }
            effectiveDates = await getEffectiveWorkDatesFromList(staff, normalizedStrings);
            if (leaveType === 'Half Day') {
                if (effectiveDates.length !== 1) {
                    return res.status(400).json({
                        success: false,
                        error: { message: 'Half Day leave requires exactly one working day. Selected date may be a holiday or week off.' }
                    });
                }
                startDateNorm = normalizeToDateOnlyUTC(effectiveDates[0] + 'T00:00:00.000Z');
                endDateNorm = startDateNorm;
            } else {
                if (effectiveDates.length === 0) {
                    return res.status(400).json({
                        success: false,
                        error: { message: 'Selected dates are all holidays or week offs. No working days to apply leave.' }
                    });
                }
                startDateNorm = normalizeToDateOnlyUTC(effectiveDates[0] + 'T00:00:00.000Z');
                endDateNorm = normalizeToDateOnlyUTC(effectiveDates[effectiveDates.length - 1] + 'T00:00:00.000Z');
            }
        } else {
            // Start/end range: use all calendar days (no holiday/weekoff filtering). Only check leave already applied.
            startDate = normalizeToDateOnlyUTC(startDate);
            endDate = normalizeToDateOnlyUTC(endDate);
            if (!startDate || !endDate || isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
                return res.status(400).json({ success: false, error: { message: 'startDate and endDate are required' } });
            }
            if (startDate > endDate) {
                return res.status(400).json({ success: false, error: { message: 'Start date must be on or before end date.' } });
            }
            effectiveDates = getCalendarDatesInRange(startDate, endDate);
            if (leaveType === 'Half Day' && effectiveDates.length !== 1) {
                return res.status(400).json({
                    success: false,
                    error: { message: 'Half Day leave requires exactly one date (start and end must be the same).' }
                });
            }
            startDateNorm = startDate;
            endDateNorm = endDate;
        }

        // Calculate days: Half Day = 0.5, else = count of effective work days
        const days = leaveType === 'Half Day' ? 0.5 : effectiveDates.length;

        const isUnpaidLeave = /^\s*unpaid(\s+leave)?\s*$/i.test(leaveType);

        // Leave balance validation: use available pool (from attendances or template). Unpaid Leave has no limit.
        // Pool is shared across all leave types (e.g. 5 total = 3 casual + 2 half-days + 1 sick).
        if (!isUnpaidLeave) {
            const availableCasualLeaves = await getAvailableLeavePool(currentStaffId, staff);
            if (availableCasualLeaves <= 0) {
                return res.status(400).json({
                    success: false,
                    error: { message: "You don't have enough leave balance." }
                });
            }
            if (availableCasualLeaves === 0.5) {
                if (leaveType !== 'Half Day') {
                    return res.status(400).json({
                        success: false,
                        error: { message: "You don't have enough leave balance." }
                    });
                }
                // 0.5 balance: only 1 Half Day allowed (days is already 0.5)
            } else if (days > availableCasualLeaves) {
                return res.status(400).json({
                    success: false,
                    error: { message: "You don't have enough leave balance." }
                });
            }
        }

        // Validation for Half Day
        if (leaveType === 'Half Day') {
            if (!session || !['1', '2'].includes(session)) {
                return res.status(400).json({ success: false, error: { message: 'Session (1 or 2) is mandatory for Half Day leave' } });
            }
            // Session 1 only: block if user has already checked in for that date (attendance has punchIn)
            if (session === '1') {
                const startOfDay = new Date(startDateNorm);
                const endOfDay = new Date(Date.UTC(startDateNorm.getUTCFullYear(), startDateNorm.getUTCMonth(), startDateNorm.getUTCDate(), 23, 59, 59, 999));
                const todayAttendance = await Attendance.findOne({
                    $or: [{ employeeId: currentStaffId }, { user: currentStaffId }],
                    date: { $gte: startOfDay, $lte: endOfDay },
                    punchIn: { $exists: true, $ne: null }
                });
                if (todayAttendance) {
                    return res.status(400).json({
                        success: false,
                        error: { message: 'You are already check in for session 1' }
                    });
                }
            }
        }

        let limit = null;
        let leaveConfig = null;

        // Validate leave type against template if staff has a template assigned
        if (staff.leaveTemplateId) {
            const template = staff.leaveTemplateId;
            let leaveTypeFound = false;

            // 1. Check leaveTypes array (primary check) — match flexibly so "Casual" in template matches "Casual Leave"
            if (template.leaveTypes && Array.isArray(template.leaveTypes) && template.leaveTypes.length > 0) {
                const leaveKey = leaveTypeMatchKey(leaveType);
                leaveConfig = template.leaveTypes.find(t => t.type && leaveTypeMatchKey(t.type) === leaveKey);
                if (leaveConfig) {
                    limit = leaveConfig.limit || leaveConfig.days;
                    leaveTypeFound = true;
                }
            }

            // 2. Check limits object (fallback) — try both exact and match key
            if (!leaveTypeFound && template.limits && typeof template.limits === 'object') {
                const leaveKey = leaveTypeMatchKey(leaveType);
                const limitValue = template.limits[leaveType] || template.limits[leaveType.toLowerCase()] ||
                    (leaveKey && (template.limits[leaveKey] || template.limits[leaveKey + ' leave']));
                if (limitValue !== undefined && limitValue !== null) {
                    limit = limitValue;
                    leaveConfig = { type: leaveType, days: limitValue };
                    leaveTypeFound = true;
                }
            }

            // 3. Check individual fields (e.g., casualLimit) (fallback) — use match key so "Casual Leave" -> casualLimit
            if (!leaveTypeFound) {
                const leaveKey = leaveTypeMatchKey(leaveType);
                const fieldName = (leaveKey || leaveType.toLowerCase().replace(/\s+/g, '')) + 'Limit';
                const fieldValue = template[fieldName];
                if (fieldValue !== undefined && fieldValue !== null) {
                    limit = fieldValue;
                    leaveConfig = { type: leaveType, days: fieldValue };
                    leaveTypeFound = true;
                }
            }

            // Use overall template count for any leave name: if type not found by name, use total pool from template
            // (Balance validation already uses getAvailableLeavePool = attendance or template total − used.)
            if (!leaveTypeFound) {
                const isUnpaid = /^\s*unpaid(\s+leave)?\s*$/i.test(leaveType);
                const isHalfDay = /^\s*half\s*day\s*$/i.test(leaveType) ||
                    /^\s*first\s*half\s*$/i.test(leaveType) || /^\s*second\s*half\s*$/i.test(leaveType);
                if (isUnpaid || isHalfDay) {
                    limit = null;
                } else {
                    limit = getTotalLeavesFromAssignedTemplate(staff);
                }
            }
        }

        // Balance validation is done above using availableCasualLeaves from attendances.
        // Template limit is used only for type validation and display (totalAllowed).

        // Check conflict: existing Approved/Pending leave or isPaidLeave in attendances on any effective date
        const conflict = await hasLeaveOrPaidLeaveConflict(currentStaffId, effectiveDates);
        if (conflict) {
            return res.status(400).json({
                success: false,
                error: {
                    message: 'You already have leave on one or more of these days. Please choose different dates.'
                }
            });
        }

        const halfDaySessionVal = leaveType === 'Half Day' ? (session === '1' ? 'First Half Day' : session === '2' ? 'Second Half Day' : null) : null;
        const leaveDoc = {
            employeeId: staff._id,
            businessId: staff.businessId,
            leaveType,
            startDate: startDateNorm,
            endDate: endDateNorm,
            days,
            reason,
            session: leaveType === 'Half Day' ? session : null,
            halfDaySession: halfDaySessionVal,
            halfDayType: halfDaySessionVal
        };
        console.log('[Leave Submit] Before Leave.create - leaveType:', leaveType, '| full doc:', JSON.stringify(leaveDoc));

        const leave = await Leave.create(leaveDoc);

        res.status(201).json({
            success: true,
            data: { leave }
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};


// @desc    Approve or Reject Leave
// @route   PATCH /api/requests/leave/:id/approve or /api/requests/leave/:id/reject
// @access  Private (Admin/HR)
const updateLeaveStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status, rejectionReason } = req.body;
        const approverId = req.staff?._id || req.user?._id;

        if (!['Approved', 'Rejected'].includes(status)) {
            return res.status(400).json({
                success: false,
                error: { message: 'Invalid status. Must be "Approved" or "Rejected"' }
            });
        }

        const leave = await Leave.findById(id);
        if (!leave) {
            return res.status(404).json({
                success: false,
                error: { message: 'Leave not found' }
            });
        }

        // If approving, check limits one last time
        if (status === 'Approved') {
            const staff = await Staff.findById(leave.employeeId).populate('leaveTemplateId');
            if (staff && staff.leaveTemplateId) {
                const leaveInfo = await calculateAvailableLeaves(staff, leave.leaveType, leave.startDate);
                
                // When approving, we check if the ALREADY APPLIED leave (which is in Pending)
                // would still be within limits. calculateAvailableLeaves includes Pending leaves.
                // If used > totalAvailable, it means some leaves were approved in between that 
                // now make this one exceed the limit.
                if (leaveInfo.totalAvailable !== null && leaveInfo.used > leaveInfo.totalAvailable) {
                    return res.status(400).json({
                        success: false,
                        error: { 
                            message: `Cannot approve leave. ${leave.leaveType} limit exceeded for this ${leaveInfo.isMonthly ? 'month' : 'year'}.`,
                            details: leaveInfo
                        }
                    });
                }
            }
        }

        // Update leave status
        leave.status = status;
        if (status === 'Approved') {
            leave.approvedBy = approverId;
            leave.approvedAt = new Date();
            leave.rejectedBy = undefined;
            leave.rejectedAt = undefined;
            leave.rejectionReason = undefined;
        } else if (status === 'Rejected') {
            leave.rejectedBy = approverId;
            leave.rejectedAt = new Date();
            if (rejectionReason) leave.rejectionReason = rejectionReason;
            leave.approvedBy = undefined;
            leave.approvedAt = undefined;
        }

        await leave.save();

        // Send FCM only to the one employee who owns this leave (leave.employeeId). Never broadcast to all.
        const fcmService = require('../services/fcmService');
        const leaveOwnerId = leave.employeeId && leave.employeeId._id ? leave.employeeId._id : leave.employeeId;
        const staffForNotification = await Staff.findById(leaveOwnerId).select('fcmToken _id').lean();
        if (!staffForNotification || String(staffForNotification._id) !== String(leaveOwnerId)) {
            console.warn('[updateLeaveStatus] Staff for leave owner not found or mismatch – skip FCM');
        }
        console.log('[updateLeaveStatus] Sending notification to leave owner only: employeeId=', leaveOwnerId?.toString(), 'leaveId=', leave._id?.toString());
        if (status === 'Approved') {
            try {
                await markAttendanceForApprovedLeave(leave);
            } catch (error) {
                console.error('[updateLeaveStatus] Error marking attendance:', error);
            }
            try {
                const result = await fcmService.sendLeaveApprovedNotification(leave, staffForNotification);
                if (result.success) {
                    leave.fcmNotificationSentAt = new Date();
                    await leave.save();
                    console.log('[updateLeaveStatus] FCM leave approved: SENT OK employeeId=', leaveOwnerId?.toString());
                } else {
                    console.warn('[updateLeaveStatus] FCM leave approved: NOT SENT –', result.error);
                }
            } catch (error) {
                console.error('[updateLeaveStatus] FCM leave approved: exception –', error.message);
            }
        } else if (status === 'Rejected') {
            try {
                const result = await fcmService.sendLeaveRejectedNotification(leave, staffForNotification);
                if (result.success) {
                    leave.fcmRejectionSentAt = new Date();
                    await leave.save();
                    console.log('[updateLeaveStatus] FCM leave rejected: SENT OK employeeId=', leaveOwnerId?.toString());
                } else {
                    console.warn('[updateLeaveStatus] FCM leave rejected: NOT SENT –', result.error);
                }
            } catch (error) {
                console.error('[updateLeaveStatus] FCM leave rejected: exception –', error.message);
            }
        }

        res.json({
            success: true,
            data: { leave }
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

module.exports = {
    getLeaves,
    getLeaveTypes,
    getLeaveTypesForApply,
    getLeaveBalance,
    checkLeaveDates,
    createLeave,
    updateLeaveStatus
};
