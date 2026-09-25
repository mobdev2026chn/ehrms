const { getDevicesList } = require('../db/mongo');
const { getIdleLogsForDay, getDailyIdleSummary } = require('../db/idleTracker');
const { listScreenshotsByDay, dayKey } = require('../storage/fileStore');

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const NOT_A_USER = ['', 'ektahr employee', 'logged out', '—'];

function requestedDay(req) {
  const date = (req.query.date || '').trim();
  return DATE_RE.test(date) ? date : dayKey(new Date());
}

// Date-wise activity per employee: total idle time + screenshot count
// GET /api/v1/activity/summary?date=yyyy-mm-dd
async function getActivitySummary(req, res) {
  try {
    const businessId = req.user.businessId;
    const date = requestedDay(req);

    const [devices, idleSummary] = await Promise.all([
      getDevicesList(businessId),
      getDailyIdleSummary({ businessId, date })
    ]);
    const screenshots = listScreenshotsByDay({ businessId, day: date });

    const employees = new Map();
    const ensure = (email) => {
      const key = (email || '').trim().toLowerCase();
      if (NOT_A_USER.includes(key)) return null;
      if (!employees.has(key)) {
        employees.set(key, {
          userEmail: key,
          fullName: key,
          department: '',
          designation: '',
          online: false,
          totalIdleSec: 0,
          idleCount: 0,
          longestIdleSec: 0,
          screenshotCount: 0,
          firstActivityAt: null,
          lastActivityAt: null,
          devices: []
        });
      }
      return employees.get(key);
    };

    // All staff of the admin's company (so employees with no data still show up)
    for (const d of devices) {
      const row = ensure(d.currentUser);
      if (!row) continue;
      if (d.fullName) row.fullName = d.fullName;
      if (d.department) row.department = d.department;
      if (d.designation) row.designation = d.designation;
      if (d.status && d.status !== 'OFFLINE' && d.status !== 'LOGGED_OUT') row.online = true;
    }

    for (const s of idleSummary) {
      const row = ensure(s.userEmail);
      if (!row) continue;
      row.totalIdleSec = s.totalIdleSec;
      row.idleCount = s.idleCount;
      row.longestIdleSec = s.longestIdleSec;
      for (const h of s.devices || []) if (!row.devices.includes(h)) row.devices.push(h);
    }

    for (const ss of screenshots) {
      const row = ensure(ss.currentUser);
      if (!row) continue;
      row.screenshotCount += 1;
      if (!row.firstActivityAt || ss.timestamp < row.firstActivityAt) row.firstActivityAt = ss.timestamp;
      if (!row.lastActivityAt || ss.timestamp > row.lastActivityAt) row.lastActivityAt = ss.timestamp;
      if (ss.hostname && !row.devices.includes(ss.hostname)) row.devices.push(ss.hostname);
    }

    const list = [...employees.values()].sort((a, b) =>
      (b.screenshotCount + b.idleCount > 0) - (a.screenshotCount + a.idleCount > 0) ||
      a.fullName.localeCompare(b.fullName)
    );

    res.json({ success: true, date, employees: list });
  } catch (err) {
    console.error('[Activity] Error building summary:', err);
    res.status(500).json({ success: false, error: 'Failed to load activity summary' });
  }
}

// One employee's idle periods and screenshots for a date
// GET /api/v1/activity/employee?email=...&date=yyyy-mm-dd
async function getEmployeeActivity(req, res) {
  try {
    const businessId = req.user.businessId;
    const date = requestedDay(req);
    const email = (req.query.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ success: false, error: 'email is required' });

    const idleLogs = getIdleLogsForDay({ businessId, date, userEmail: email });
    const screenshots = listScreenshotsByDay({ businessId, day: date, userEmail: email });
    const totalIdleSec = idleLogs.reduce((sum, l) => sum + (l.durationSec || 0), 0);

    res.json({
      success: true,
      date,
      userEmail: email,
      totals: {
        totalIdleSec,
        idleCount: idleLogs.length,
        longestIdleSec: idleLogs.reduce((m, l) => Math.max(m, l.durationSec || 0), 0),
        screenshotCount: screenshots.length
      },
      idleLogs,
      screenshots
    });
  } catch (err) {
    console.error('[Activity] Error loading employee activity:', err);
    res.status(500).json({ success: false, error: 'Failed to load employee activity' });
  }
}

module.exports = { getActivitySummary, getEmployeeActivity };
