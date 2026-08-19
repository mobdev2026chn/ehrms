const Staff = require('../models/Staff');
const Company = require('../models/Company');
const { getHolidayTemplateForStaff } = require('../utils/holidayTemplateHelper');
const { getWeekOffConfigForStaff } = require('../utils/weekOffHelper');

// @desc    Get holidays for employee
// @route   GET /api/holidays/employee
// @access  Private
const getEmployeeHolidays = async (req, res) => {
    try {
        const { year, month, search, page = 1, limit = 100 } = req.query;

        // Ensure we have staff info (populated by auth middleware)
        if (!req.staff) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }

        const businessId = req.staff.businessId;
        if (!businessId) {
            return res.status(400).json({ success: false, message: 'Staff is not assigned to a business/company' });
        }

        const staff = await Staff.findById(req.staff._id).select('businessId holidayTemplateId').lean();
        const holidayTemplate = await getHolidayTemplateForStaff(staff || req.staff);

        if (!holidayTemplate) {
            return res.json({
                success: true,
                data: {
                    holidays: [],
                    pagination: { page: Number(page), limit: Number(limit), total: 0, pages: 0 }
                }
            });
        }

        // Filter holidays by year if provided
        let holidays = holidayTemplate.holidays || [];

        if (year) {
            const filterYear = Number(year);
            holidays = holidays.filter((holiday) => {
                const holidayDate = new Date(holiday.date);
                return holidayDate.getFullYear() === filterYear;
            });
        }

        // Optional month (1–12), aligned with web GET /holidays/employee?year=&month=
        if (month !== undefined && month !== null && month !== '') {
            const filterMonth = Number(month);
            if (!Number.isNaN(filterMonth) && filterMonth >= 1 && filterMonth <= 12) {
                holidays = holidays.filter((holiday) => {
                    const holidayDate = new Date(holiday.date);
                    return holidayDate.getMonth() + 1 === filterMonth;
                });
            }
        }

        // Search functionality
        if (search) {
            const searchLower = search.toLowerCase();
            holidays = holidays.filter((holiday) => {
                return holiday.name.toLowerCase().includes(searchLower) ||
                    holiday.type.toLowerCase().includes(searchLower);
            });
        }

        // Sort by date
        holidays.sort((a, b) => {
            return new Date(a.date).getTime() - new Date(b.date).getTime();
        });

        // Pagination
        const total = holidays.length;
        const skip = (Number(page) - 1) * Number(limit);
        const paginatedHolidays = holidays.slice(skip, skip + Number(limit));

        // Get upcoming holidays (next 5)
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const upcomingHolidays = holidays
            .filter((holiday) => new Date(holiday.date) >= today)
            .slice(0, 5);

        res.json({
            success: true,
            data: {
                holidays: paginatedHolidays,
                upcomingHolidays,
                totalHolidays: total,
                pagination: {
                    page: Number(page),
                    limit: Number(limit),
                    total,
                    pages: Math.ceil(total / Number(limit))
                }
            }
        });

    } catch (error) {
        console.error('Get Holidays Error:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to fetch holidays' }
        });
    }
};

// @desc    Get weekly-off configuration for the logged-in employee
// @route   GET /api/holidays/weekoff-config
// @access  Private
// Returns the recurring week-off rule so clients can compute which weekdays/Saturdays are
// off without one request per month: { weeklyOffPattern, weeklyHolidays: [{ day, name }] }.
// day uses JS getDay() numbering: 0 = Sunday ... 6 = Saturday.
const getWeekOffConfig = async (req, res) => {
    try {
        if (!req.staff) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        const staff = await Staff.findById(req.staff._id)
            .select('businessId weeklyHolidayTemplateId')
            .populate('weeklyHolidayTemplateId')
            .lean();
        const company = staff?.businessId
            ? await Company.findById(staff.businessId).select('settings.business').lean()
            : null;
        const config = await getWeekOffConfigForStaff(staff || req.staff, company);
        res.json({
            success: true,
            data: {
                weeklyOffPattern: config.weeklyOffPattern,
                weeklyHolidays: (config.weeklyHolidays || []).map((h) => ({
                    day: h.day,
                    name: h.name || null
                }))
            }
        });
    } catch (error) {
        console.error('Get WeekOff Config Error:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to fetch week-off config' }
        });
    }
};

module.exports = {
    getEmployeeHolidays,
    getWeekOffConfig
};
