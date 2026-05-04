const mongoose = require('mongoose');
const HolidayTemplate = require('../models/HolidayTemplate');

async function getHolidayTemplateForStaff(staff) {
    if (!staff) return null;

    const ref = staff.holidayTemplateId;
    if (ref) {
        // Mongoose ObjectId has a truthy ._id (points to itself), so a bare
        // holidayTemplateId was incorrectly returned as the "template" with no
        // .holidays — only resolve populated docs that actually carry holidays.
        const bareId =
            ref instanceof mongoose.Types.ObjectId ||
            (typeof ref === 'string' && mongoose.Types.ObjectId.isValid(ref));

        const populatedDoc =
            typeof ref === 'object' &&
            ref != null &&
            !(ref instanceof mongoose.Types.ObjectId) &&
            Array.isArray(ref.holidays);

        if (populatedDoc && ref.isActive !== false) {
            return ref;
        }

        const templateId = bareId ? ref : ref._id;
        if (templateId) {
            const template = await HolidayTemplate.findById(templateId).lean();
            if (template && template.isActive !== false) {
                return template;
            }
        }
    }

    if (!staff.businessId) return null;

    return HolidayTemplate.findOne({
        businessId: staff.businessId,
        isActive: true
    }).lean();
}

function isSameHolidayDate(left, right) {
    const leftDate = new Date(left);
    const rightDate = new Date(right);

    return (
        leftDate.getFullYear() === rightDate.getFullYear() &&
        leftDate.getMonth() === rightDate.getMonth() &&
        leftDate.getDate() === rightDate.getDate()
    );
}

function getHolidayForDate(holidayTemplate, date) {
    return (holidayTemplate?.holidays || []).find((holiday) =>
        isSameHolidayDate(holiday.date, date)
    ) || null;
}

function getHolidaysForMonth(holidayTemplate, year, month) {
    return (holidayTemplate?.holidays || []).filter((holiday) => {
        const holidayDate = new Date(holiday.date);
        return holidayDate.getFullYear() === Number(year) && (holidayDate.getMonth() + 1) === Number(month);
    });
}

module.exports = {
    getHolidayTemplateForStaff,
    getHolidayForDate,
    getHolidaysForMonth
};
