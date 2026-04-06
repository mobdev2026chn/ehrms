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
 * oddEvenSaturday: week off on 2nd, 4th, 6th Saturday of the month (ordinal), not by calendar
 * date parity (e.g. 14th/28th). Sundays are handled by callers.
 * @param {number} fullYear
 * @param {number} monthIndex0 - 0 = January
 * @param {number} dayOfMonth - 1–31
 * @param {'local'|'utc'} calendar - match how the caller interprets the calendar day
 * @returns {boolean} true if this day is Saturday and is an even-indexed Saturday (off)
 */
function isOddEvenSaturdayWeeklyOff(fullYear, monthIndex0, dayOfMonth, calendar = 'local') {
  const getDow = (y, m, dom) =>
    calendar === 'utc'
      ? new Date(Date.UTC(y, m, dom)).getUTCDay()
      : new Date(y, m, dom).getDay();
  if (getDow(fullYear, monthIndex0, dayOfMonth) !== 6) return false;
  let ordinal = 0;
  for (let d = 1; d <= dayOfMonth; d++) {
    if (getDow(fullYear, monthIndex0, d) === 6) ordinal++;
  }
  return ordinal % 2 === 0;
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
  isOddEvenSaturdayWeeklyOff,
  DEFAULT_CONFIG,
};
