/**
 * Birthday / work-anniversary detection for FCM wishes (aligned with dashboard celebrations,
 * using each company's business timezone for "today"). Send time is controlled by the cron scheduler.
 */
const { formatCalendarDayInTimezone } = require('./dateUtils');
const { getBusinessTimezone } = require('./leaveAttendanceHelper');

function getMonthDayInTimezone(dateObj, timeZone) {
    const d = new Date(dateObj);
    const tz = (timeZone && String(timeZone).trim()) || 'Asia/Kolkata';
    try {
        const parts = new Intl.DateTimeFormat('en-GB', {
            timeZone: tz,
            month: 'numeric',
            day: 'numeric',
        }).formatToParts(d);
        const monthRaw = parts.find((p) => p.type === 'month')?.value;
        const dayRaw = parts.find((p) => p.type === 'day')?.value;
        const month = parseInt(monthRaw, 10) - 1;
        const day = parseInt(dayRaw, 10);
        if (Number.isFinite(month) && Number.isFinite(day)) return { month, day };
    } catch (_) {
        /* fall through */
    }
    if (tz === 'Asia/Kolkata' || tz === 'Asia/Calcutta') {
        const istMs = d.getTime() + 330 * 60 * 1000;
        const u = new Date(istMs);
        return { month: u.getUTCMonth(), day: u.getUTCDate() };
    }
    return { month: d.getMonth(), day: d.getDate() };
}

function getHourMinuteInTimezone(dateObj, timeZone) {
    const tz = (timeZone && String(timeZone).trim()) || 'Asia/Kolkata';
    try {
        const parts = new Intl.DateTimeFormat('en-GB', {
            timeZone: tz,
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
        }).formatToParts(new Date(dateObj));
        const hour = parseInt(parts.find((p) => p.type === 'hour')?.value || '0', 10);
        const minute = parseInt(parts.find((p) => p.type === 'minute')?.value || '0', 10);
        if (Number.isFinite(hour) && Number.isFinite(minute)) {
            return { hour, minute, currentMinutes: hour * 60 + minute };
        }
    } catch (_) {
        /* fall through */
    }
    if (tz === 'Asia/Kolkata' || tz === 'Asia/Calcutta') {
        const d = new Date(dateObj);
        const utcMin = d.getUTCHours() * 60 + d.getUTCMinutes();
        const localMinutes = (utcMin + 330) % (24 * 60);
        const hour = Math.floor(localMinutes / 60);
        const minute = localMinutes % 60;
        return { hour, minute, currentMinutes: localMinutes };
    }
    const d = new Date(dateObj);
    return { hour: d.getHours(), minute: d.getMinutes(), currentMinutes: d.getHours() * 60 + d.getMinutes() };
}

/** ISO yyyy-MM-dd + years; clamps day for shorter months (incl. Feb 29 → Feb 28). */
function addYearsToIsoDate(yyyyMmDd, yearsToAdd) {
    const [y, m, d] = yyyyMmDd.split('-').map((n) => parseInt(n, 10));
    const y2 = y + yearsToAdd;
    const maxDay = new Date(y2, m, 0).getDate();
    const d2 = Math.min(d, maxDay);
    return `${y2}-${String(m).padStart(2, '0')}-${String(d2).padStart(2, '0')}`;
}

/**
 * @param {object} staff — lean doc with dob, joiningDate
 * @param {Date} now
 * @param {string} timeZone — IANA
 * @returns {{ isBirthdayToday: boolean, isWorkAnniversaryToday: boolean }}
 */
function getCelebrationWishFlags(staff, now, timeZone) {
    const tz = (timeZone && String(timeZone).trim()) || 'Asia/Kolkata';
    const { month: tm, day: td } = getMonthDayInTimezone(now, tz);
    let isBirthdayToday = false;
    let isWorkAnniversaryToday = false;

    if (staff.dob) {
        const { month: bm, day: bd } = getMonthDayInTimezone(staff.dob, tz);
        isBirthdayToday = bm === tm && bd === td;
    }

    if (staff.joiningDate) {
        const { month: jm, day: jdDay } = getMonthDayInTimezone(staff.joiningDate, tz);
        const sameCalendarDay = jm === tm && jdDay === td;
        if (sameCalendarDay) {
            const joinKey = formatCalendarDayInTimezone(staff.joiningDate, tz);
            const todayKey = formatCalendarDayInTimezone(now, tz);
            const oneYearAfterKey = addYearsToIsoDate(joinKey, 1);
            const hasCompletedOneYear = todayKey >= oneYearAfterKey;
            if (hasCompletedOneYear) {
                const joinYear = parseInt(joinKey.slice(0, 4), 10);
                const todayYear = parseInt(todayKey.slice(0, 4), 10);
                const yearsOfService = todayYear - joinYear;
                if (yearsOfService >= 1) isWorkAnniversaryToday = true;
            }
        }
    }

    return { isBirthdayToday, isWorkAnniversaryToday };
}

module.exports = {
    getBusinessTimezone,
    getCelebrationWishFlags,
    getHourMinuteInTimezone,
};
