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
    const weeklyHolidayDays =
        weeklyHolidays && weeklyHolidays.length > 0
            ? new Set(weeklyHolidays.map((wh) => Number(wh.day)))
            : null;

    for (let day = 1; day <= endDay; day++) {
        const currentDate = new Date(year, monthIndex0, day);
        currentDate.setHours(0, 0, 0, 0);
        const dayOfWeek = currentDate.getDay();

        if (weeklyOffPattern === 'oddEvenSaturday') {
            if (!isOddEvenSaturdayWeeklyOffWeb(currentDate)) count++;
        } else if (weeklyHolidayDays && weeklyHolidayDays.has(dayOfWeek)) {
            /* week off */
        } else if (!weeklyHolidayDays && (dayOfWeek === 0 || dayOfWeek === 6)) {
            /* default Sat–Sun */
        } else {
            count++;
        }
    }

    return count;
}

module.exports = {
    getCalendarDaysInMonth,
    calculateDaysExcludingWeeklyOffsOnly,
    isOddEvenSaturdayWeeklyOffWeb,
};
