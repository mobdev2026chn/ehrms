const HolidayTemplate = require('../models/HolidayTemplate');

async function getHolidayTemplateForStaff(staff) {
    if (!staff) return null;

    const assignedTemplate = staff.holidayTemplateId;
    if (assignedTemplate) {
        if (typeof assignedTemplate === 'object' && assignedTemplate._id != null) {
            if (assignedTemplate.isActive !== false) {
                return assignedTemplate;
            }
        } else {
            const template = await HolidayTemplate.findById(assignedTemplate).lean();
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
