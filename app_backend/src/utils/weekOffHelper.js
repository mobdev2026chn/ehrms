/**
 * Shared week-off config resolution: staff's WeeklyHolidayTemplate when assigned,
 * otherwise business (Company.settings.business) weeklyOffPattern and weeklyHolidays.
 * Used by attendance and payroll so behaviour is consistent.
 */

const WeeklyHolidayTemplate = require('../models/WeeklyHolidayTemplate');

const DEFAULT_CONFIG = {
  weeklyOffPattern: 'standard',
  weeklyHolidays: [{ day: 0, name: 'Sunday' }],
};

/**
 * Get week-off config from company.settings.business (for fallback when no template).
 * @param {Object} company - Company doc (plain or mongoose)
 * @returns {{ weeklyOffPattern: string, weeklyHolidays: Array<{day: number, name?: string}> }}
 */
function getBusinessWeekOffConfig(company) {
  if (!company || !company.settings || !company.settings.business) {
    return { ...DEFAULT_CONFIG };
  }
  const business = company.settings.business;
  const weeklyOffPattern =
    (business.weeklyOffPattern === 'standard' || business.weeklyOffPattern === 'oddEvenSaturday')
      ? business.weeklyOffPattern
      : DEFAULT_CONFIG.weeklyOffPattern;
  const weeklyHolidays =
    Array.isArray(business.weeklyHolidays) && business.weeklyHolidays.length > 0
      ? business.weeklyHolidays
      : DEFAULT_CONFIG.weeklyHolidays;
  return { weeklyOffPattern, weeklyHolidays };
}

/**
 * Get week-off config for a staff: staff's WeeklyHolidayTemplate when assigned and active,
 * otherwise business (Company.settings.business) weeklyOffPattern and weeklyHolidays.
 * @param {Object} staff - Staff doc (weeklyHolidayTemplateId may be populated or ObjectId)
 * @param {Object} company - Company doc (required for fallback when no template)
 * @returns {Promise<{ weeklyOffPattern: string, weeklyHolidays: Array<{day: number, name?: string}> }>}
 */
async function getWeekOffConfigForStaff(staff, company) {
  const templateId = staff?.weeklyHolidayTemplateId;
  const businessFallback = () => getBusinessWeekOffConfig(company);

  if (!templateId) {
    return businessFallback();
  }

  // Use populated template if already loaded
  const template = staff.weeklyHolidayTemplateId;
  if (template && typeof template === 'object' && template._id != null) {
    if (template.isActive === false) return businessFallback();
    const s = template.settings || {};
    return {
      weeklyOffPattern: s.weeklyOffPattern || DEFAULT_CONFIG.weeklyOffPattern,
      weeklyHolidays:
        Array.isArray(s.weeklyHolidays) && s.weeklyHolidays.length > 0
          ? s.weeklyHolidays
          : DEFAULT_CONFIG.weeklyHolidays,
    };
  }

  // Fetch from WeeklyHolidayTemplate collection
  const doc = await WeeklyHolidayTemplate.findById(templateId).lean();
  if (!doc || doc.isActive === false) return businessFallback();
  const s = doc.settings || {};
  return {
    weeklyOffPattern: s.weeklyOffPattern || DEFAULT_CONFIG.weeklyOffPattern,
    weeklyHolidays:
      Array.isArray(s.weeklyHolidays) && s.weeklyHolidays.length > 0
        ? s.weeklyHolidays
        : DEFAULT_CONFIG.weeklyHolidays,
  };
}

module.exports = {
  getWeekOffConfigForStaff,
  getBusinessWeekOffConfig,
  DEFAULT_CONFIG,
};
