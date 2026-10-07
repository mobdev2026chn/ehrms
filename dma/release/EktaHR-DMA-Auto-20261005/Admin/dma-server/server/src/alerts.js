// Real-time admin alerts (e.g. "jagan@... is idle"). Kept in memory; the Admin Console polls
// GET /api/v1/alerts?since=<id> every few seconds and shows a toast + desktop notification.
const MAX_ALERTS = 1000;

const alerts = [];
let lastId = 0;

// type: 'IDLE_START' | 'IDLE_END'
function pushAlert({ type, businessId, userEmail, hostname, deviceId, idleSince, durationSec }) {
  const alert = {
    id: ++lastId,
    type,
    businessId: businessId || 'default',
    userEmail: (userEmail || '').toLowerCase(),
    hostname: hostname || deviceId,
    deviceId,
    idleSince: idleSince || null,
    durationSec: durationSec != null ? durationSec : null,
    at: new Date().toISOString()
  };
  alerts.push(alert);
  if (alerts.length > MAX_ALERTS) alerts.splice(0, alerts.length - MAX_ALERTS);
  return alert;
}

function isSuperScope(businessId) {
  return !businessId || businessId === 'all' || businessId === 'superadmin' || businessId === 'admin-super-001';
}

// Alerts for the admin's business newer than `since` (or the most recent `limit` when since < 0)
function getAlerts({ businessId, since = -1, limit = 50 }) {
  const scoped = alerts.filter(a => isSuperScope(businessId) || a.businessId === businessId);
  const sinceId = Number(since);
  const list = sinceId >= 0 ? scoped.filter(a => a.id > sinceId) : scoped.slice(-Math.min(Number(limit) || 50, 200));
  return { latestId: lastId, alerts: list };
}

module.exports = { pushAlert, getAlerts };
