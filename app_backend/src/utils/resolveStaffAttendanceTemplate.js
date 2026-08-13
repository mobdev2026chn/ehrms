const AttendanceTemplate = require('../models/AttendanceTemplate');

/**
 * ObjectId (or id string) from Staff.attendanceTemplateId — works if the path holds
 * an ObjectId or a populated subdocument.
 */
function getStaffAttendanceTemplateObjectId(staff) {
    if (!staff || staff.attendanceTemplateId == null) return null;
    const v = staff.attendanceTemplateId;
    if (v != null && typeof v === 'object' && v._id != null) return v._id;
    return v;
}

/** ObjectId from Staff.businessId — same pattern when businessId is populated (Company doc). */
function normalizeBusinessIdRef(value) {
    if (value == null) return null;
    if (typeof value === 'object' && value._id != null) return value._id;
    return value;
}

/**
 * Load AttendanceTemplate for this staff. Returns null if id missing, document missing,
 * or template.businessId !== staff.businessId when both are set.
 *
 * @param {import('mongoose').Document|object} staff — must include attendanceTemplateId, businessId, _id (for logs)
 */
async function loadAttendanceTemplateForStaff(staff) {
    const templateId = getStaffAttendanceTemplateObjectId(staff);
    if (!templateId) return null;
    const doc = await AttendanceTemplate.findById(templateId).lean();
    if (!doc) {
        console.warn('[AttendanceTemplate] staff.attendanceTemplateId has no matching document', {
            staffId: staff._id?.toString?.(),
            attendanceTemplateId: String(templateId)
        });
        return null;
    }
    const staffBizId = normalizeBusinessIdRef(staff.businessId);
    const templateBizId = normalizeBusinessIdRef(doc.businessId);
    if (staffBizId && templateBizId) {
        if (String(templateBizId) !== String(staffBizId)) {
            console.warn('[AttendanceTemplate] document businessId does not match staff.businessId', {
                staffId: staff._id?.toString?.(),
                staffBusinessId: String(staffBizId),
                attendanceTemplateId: String(templateId),
                templateBusinessId: String(templateBizId)
            });
            return null;
        }
    }
    return doc;
}

module.exports = {
    getStaffAttendanceTemplateObjectId,
    loadAttendanceTemplateForStaff
};
