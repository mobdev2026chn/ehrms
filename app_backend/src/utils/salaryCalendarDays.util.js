/**
 * Parity with web `salaryCalculation.util.ts` / `oddEvenSaturday.util.ts`:
 * - `calculateDaysExcludingWeeklyOffsOnly`: month day-count excluding weekly offs only
 *   (holidays are NOT subtracted — avoids double exclusion when a holiday falls on a week off).
 * - `getCalendarDaysInMonth`: 28–31 for the month.
 */

/**
 * Web `oddEvenSaturday.util.ts` — uses ceil(day/7) bands, not ordinal Saturday index.
 * @param {Date} date - local midnight recommended
 */
function isOddEvenSaturdayWeeklyOffWeb(date) {
    const dayOfWeek = date.getDay();
    if (dayOfWeek === 0) return true;
    if (dayOfWeek === 6) {
        const weekOfMonth = Math.ceil(date.getDate() / 7);
        return weekOfMonth === 2 || weekOfMonth === 4;
    }
    return false;
}

function getCalendarDaysInMonth(year, monthIndex0) {
    return new Date(year, monthIndex0 + 1, 0).getDate();
}

/**
 * Whether `currentDate` is a weekly off per a Weekly Holiday Template's `weeklyHolidays`
 * entries, honoring optional `nthWeeks` (which occurrences of that weekday are off).
 *
 * Each entry: { day: 0-6, nthWeeks?: number[] }.
 *   - No/empty nthWeeks  → that weekday is off EVERY week.
 *   - nthWeeks present    → off only on listed occurrences. Week-of-month = ceil(date/7) (1..5);
 *                           `-1` means the LAST occurrence of that weekday in the month.
 * This lets "2nd & 4th Saturday" (nthWeeks [2,4]) exclude only those Saturdays instead of all.
 *
 * @param {Date} currentDate
 * @param {Array<{day:number, nthWeeks?:number[]}>} weeklyHolidays
 * @param {number} year
 * @param {number} monthIndex0
 * @returns {boolean}
 */
function isTemplateWeeklyOff(currentDate, weeklyHolidays, year, monthIndex0) {
    if (!Array.isArray(weeklyHolidays) || weeklyHolidays.length === 0) return false;
    const dayOfWeek = currentDate.getDay();
    const dom = currentDate.getDate();
    const weekOfMonth = Math.ceil(dom / 7); // 1..5
    const lastDom = new Date(year, monthIndex0 + 1, 0).getDate();
    const isLastOccurrence = dom + 7 > lastDom; // no later same-weekday in this month
    return weeklyHolidays.some((wh) => {
        if (Number(wh?.day) !== dayOfWeek) return false;
        const nth = Array.isArray(wh?.nthWeeks)
            ? wh.nthWeeks.map(Number).filter((n) => !Number.isNaN(n))
            : null;
        if (!nth || nth.length === 0) return true; // every occurrence
        if (nth.includes(weekOfMonth)) return true;
        if (nth.includes(-1) && isLastOccurrence) return true;
        return false;
    });
}

/**
 * @param {number} year
 * @param {number} monthIndex0 - 0 = January (same as JS Date month)
 * @param {'standard'|'oddEvenSaturday'} weeklyOffPattern
 * @param {Date|null} endDate - inclusive cap within month; null = end of month
 * @param {Array<{day:number,name?:string}>|null|undefined} weeklyHolidays
 */
function calculateDaysExcludingWeeklyOffsOnly(
    year,
    monthIndex0,
    weeklyOffPattern = 'standard',
    endDate = null,
    weeklyHolidays = null,
) {
    const lastDay = endDate ? new Date(endDate) : new Date(year, monthIndex0 + 1, 0);
    lastDay.setHours(23, 59, 59, 999);

    if (
        endDate &&
        (endDate.getMonth() !== monthIndex0 || endDate.getFullYear() !== year)
    ) {
        const monthEnd = new Date(year, monthIndex0 + 1, 0);
        lastDay.setTime(monthEnd.getTime());
        lastDay.setHours(23, 59, 59, 999);
    }

    const endDay = lastDay.getDate();
    let count = 0;
    const hasTemplateHolidays = Array.isArray(weeklyHolidays) && weeklyHolidays.length > 0;

    for (let day = 1; day <= endDay; day++) {
        const currentDate = new Date(year, monthIndex0, day);
        currentDate.setHours(0, 0, 0, 0);
        const dayOfWeek = currentDate.getDay();

        let isOff;
        if (weeklyOffPattern === 'oddEvenSaturday') {
            isOff = isOddEvenSaturdayWeeklyOffWeb(currentDate);
        } else if (hasTemplateHolidays) {
            // Honor the Weekly Holiday Template, including nthWeeks (e.g. only 2nd & 4th Saturday).
            isOff = isTemplateWeeklyOff(currentDate, weeklyHolidays, year, monthIndex0);
        } else {
            isOff = dayOfWeek === 0 || dayOfWeek === 6; // default Sat–Sun
        }
        if (!isOff) count++;
    }

    return count;
}

module.exports = {
    getCalendarDaysInMonth,
    calculateDaysExcludingWeeklyOffsOnly,
    isOddEvenSaturdayWeeklyOffWeb,
    isTemplateWeeklyOff,
};
