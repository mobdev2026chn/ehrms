const mongoose = require('mongoose');
const Announcement = require('../models/Announcement');

/**
 * Build audience filter for announcements (web announcement collection).
 *
 * Targeting is driven by the RECIPIENT LIST, not by the audienceType string — the
 * web app has been observed to store targeted announcements with audienceType left
 * at its default ("all") or cased differently ("Specific"), which previously leaked
 * a personally-targeted announcement to every staff member. Rules:
 *  - Has a non-empty recipient list (web targetStaffIds or legacy assignedTo) →
 *    show ONLY to staff in that list, whatever audienceType says.
 *  - No recipient list AND not flagged "specific" → company-wide, show to everyone.
 *  - No recipient list but flagged "specific" (any casing) → show to NO ONE.
 */
function audienceFilter(staffId) {
    const id = staffId && mongoose.Types.ObjectId.isValid(staffId)
        ? (typeof staffId === 'string' ? new mongoose.Types.ObjectId(staffId) : staffId)
        : null;
    // A recipient field carries no specific targets when it is missing, null, or an empty array.
    const noTargets = (field) => ({
        $or: [
            { [field]: { $exists: false } },
            { [field]: null },
            { [field]: { $size: 0 } },
        ],
    });
    // True for missing/null/"all"/""/any non-"specific" value; false only when audienceType is "specific" (any casing/whitespace).
    const notFlaggedSpecific = { audienceType: { $not: /^\s*specific\s*$/i } };
    return {
        $or: [
            // Targeted: this staff is explicitly listed → always show to them (regardless of audienceType).
            ...(id ? [{ targetStaffIds: id }] : []),
            ...(id ? [{ assignedTo: id }] : []),
            // Company-wide: no recipient list on EITHER field AND not flagged "specific" → show to everyone.
            { $and: [noTargets('targetStaffIds'), noTargets('assignedTo'), notFlaggedSpecific] },
        ],
    };
}

/** Status: only "published" announcements are shown. */
const statusFilter = { $eq: 'published' };

/**
 * Date filter: published/effective and not expired.
 * Web: publishDate <= now; expiryDate missing or >= startOfToday.
 * Legacy: effectiveDate <= now; endDate missing or >= startOfToday.
 */
function dateFilter(now, startOfToday, useEndOfToday = false) {
    const upper = useEndOfToday ? new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999) : now;
    return {
        $and: [
            { $or: [{ publishDate: { $exists: true, $lte: upper } }, { effectiveDate: { $exists: true, $lte: upper } }] },
            {
                $or: [
                    { expiryDate: null },
                    { expiryDate: { $exists: false } },
                    { expiryDate: { $gte: startOfToday } },
                ],
            },
            {
                $or: [
                    { endDate: null },
                    { endDate: { $exists: false } },
                    { endDate: { $gte: startOfToday } },
                ],
            },
        ],
    };
}

/**
 * Get all announcements for the logged-in employee.
 * - All employees: assignedTo missing, null, or empty → show to everyone in business.
 * - Specific employees: assignedTo contains this staff's _id → show only to those staff.
 */
const getAnnouncementsForEmployee = async (req, res) => {
    try {
        if (!req.staff) {
            console.log('[Announcements] for-employee: no req.staff');
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        const staffId = req.staff._id;
        let businessId = req.staff.businessId || req.companyId;
        const staffName = req.staff.name || '—';
        const employeeId = req.staff.employeeId || '—';
        if (businessId && typeof businessId === 'string' && mongoose.Types.ObjectId.isValid(businessId)) {
            businessId = new mongoose.Types.ObjectId(businessId);
        }
        console.log('[Announcements] for-employee: staffId=%s, businessId=%s, name=%s, employeeId=%s', staffId, businessId, staffName, employeeId);

        if (!businessId) {
            console.log('[Announcements] for-employee: no businessId, returning []');
            return res.json({ success: true, data: [] });
        }

        const now = new Date();
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);

        const query = {
            businessId,
            status: statusFilter,
            $and: [dateFilter(now, startOfToday), audienceFilter(staffId)],
        };
        const announcements = await Announcement.find(query)
            .sort({ publishDate: -1, effectiveDate: -1, createdAt: -1 })
            .lean();

        const totalForBusiness = await Announcement.countDocuments({ businessId, status: statusFilter });
        console.log('[Announcements] for-employee: found %d for this employee (total published/Active for business: %d), titles=%s', announcements.length, totalForBusiness, announcements.map(a => a.title).join(', ') || '(none)');

        res.json({ success: true, data: Array.isArray(announcements) ? announcements : [] });
    } catch (error) {
        console.error('[Announcement Controller]', error);
        res.status(500).json({ success: false, message: 'Server Error' });
    }
};

/**
 * Get today's announcements for the logged-in employee (effective date is today or in the past, still active).
 */
const getTodayAnnouncementsForEmployee = async (req, res) => {
    try {
        if (!req.staff) {
            console.log('[Announcements] today: no req.staff');
            return res.json({ success: true, data: [] });
        }
        const staffId = req.staff._id;
        const businessId = req.staff.businessId;
        if (!businessId) {
            console.log('[Announcements] today: no businessId');
            return res.json({ success: true, data: [] });
        }

        const now = new Date();
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);

        const announcements = await Announcement.find({
            businessId,
            status: statusFilter,
            $and: [dateFilter(now, startOfToday, true), audienceFilter(staffId)],
        })
            .sort({ publishDate: -1, effectiveDate: -1, createdAt: -1 })
            .limit(20)
            .lean();

        console.log('[Announcements] today: staffId=%s, count=%d', staffId, announcements.length);

        res.json({ success: true, data: announcements });
    } catch (error) {
        console.error('[Announcement Controller] getToday', error);
        res.status(500).json({ success: false, message: 'Server Error' });
    }
};

module.exports = { getAnnouncementsForEmployee, getTodayAnnouncementsForEmployee, audienceFilter, dateFilter, statusFilter };
