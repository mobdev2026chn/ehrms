/**
 * Calendar yyyy-MM-dd for an instant in `timeZone` (e.g. Asia/Kolkata).
 * Falls back to fixed +5:30 when Intl is unavailable (some Windows Node builds).
 */
function formatCalendarDayInTimezone(dateObj, timeZone) {
  const d = new Date(dateObj);
  const tryTz = (zone) => {
    if (!zone || !String(zone).trim()) return null;
    try {
      const parts = new Intl.DateTimeFormat('en-CA', {
        timeZone: zone.trim(),
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      }).formatToParts(d);
      const y = parts.find((p) => p.type === 'year')?.value;
      const m = parts.find((p) => p.type === 'month')?.value;
      const day = parts.find((p) => p.type === 'day')?.value;
      if (y && m && day) return `${y}-${m.padStart(2, '0')}-${day.padStart(2, '0')}`;
    } catch (e) {
      /* try next */
    }
    return null;
  };
  const primaryTz = (timeZone && String(timeZone).trim()) || 'Asia/Kolkata';
  let out = tryTz(primaryTz);
  if (!out && primaryTz !== 'Asia/Kolkata') out = tryTz('Asia/Kolkata');
  if (out) return out;
  if (primaryTz === 'Asia/Kolkata' || primaryTz === 'Asia/Calcutta') {
    const istMs = d.getTime() + 330 * 60 * 1000;
    const u = new Date(istMs);
    return `${u.getUTCFullYear()}-${String(u.getUTCMonth() + 1).padStart(2, '0')}-${String(u.getUTCDate()).padStart(2, '0')}`;
  }
  const u = new Date(dateObj);
  return `${u.getUTCFullYear()}-${String(u.getUTCMonth() + 1).padStart(2, '0')}-${String(u.getUTCDate()).padStart(2, '0')}`;
}

/**
 * Parse timestamp from client. Clients should send UTC ISO strings (e.g. "2025-02-06T10:07:00.000Z").
 * If string has no timezone (no Z or offset), treat as UTC to avoid server-timezone misinterpretation.
 * MongoDB stores dates in UTC; this ensures correct storage regardless of server timezone.
 */
function parseTimestamp(value) {
  if (!value) return new Date();
  if (typeof value === 'number') return new Date(value);
  const str = String(value).trim();
  // ISO format without timezone: "2025-02-06T10:07:00" or "2025-02-06T10:07:00.000"
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(\.\d+)?$/.test(str) && !/[Z+-]\d{2}:?\d{2}$/.test(str)) {
    return new Date(str + 'Z'); // Assume UTC when no timezone
  }
  return new Date(str);
}

module.exports = { parseTimestamp, formatCalendarDayInTimezone };
