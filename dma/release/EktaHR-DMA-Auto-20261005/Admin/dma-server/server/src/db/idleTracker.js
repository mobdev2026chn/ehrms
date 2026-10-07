const { appendIdleLog, readIdleLogs, saveOpenIdlePeriods, loadOpenIdlePeriods, dayKey } = require('../storage/fileStore');
const { pushAlert } = require('../alerts');

// Persists every idle period (agent status IDLE -> anything else) to disk (storage/idle-logs), not MongoDB.
// One JSON line per idle period: { deviceId, hostname, userEmail, businessId, startAt, endAt, durationSec, endReason }
const LAST_SEEN_CHECKPOINT_MS = 60 * 1000;

// deviceId -> open idle period
const openIdle = new Map();
let lastCheckpointTs = 0;

function isValidUser(email) {
  const clean = (email || '').trim().toLowerCase();
  return clean && clean !== 'ektahr employee' && clean !== 'logged out' && clean !== '—';
}

function checkpoint() {
  lastCheckpointTs = Date.now();
  saveOpenIdlePeriods(openIdle);
}

async function closeIdlePeriod(deviceId, reason, endAt = new Date()) {
  const period = openIdle.get(deviceId);
  if (!period) return;
  openIdle.delete(deviceId);
  checkpoint();

  const startAt = new Date(period.startAt);
  const durationSec = Math.max(0, Math.round((endAt - startAt) / 1000));
  try {
    await appendIdleLog({
      deviceId: period.deviceId,
      hostname: period.hostname,
      userEmail: period.userEmail,
      businessId: period.businessId,
      startAt: startAt.toISOString(),
      endAt: new Date(endAt).toISOString(),
      durationSec,
      endReason: reason
    });
    console.log(`[IdleLog] ${deviceId} idle period closed (${reason}), duration ${durationSec}s`);
    if (reason.startsWith('status_')) {
      pushAlert({ type: 'IDLE_END', businessId: period.businessId, userEmail: period.userEmail, hostname: period.hostname, deviceId, idleSince: startAt.toISOString(), durationSec });
    }
  } catch (err) {
    console.error('[IdleLog] Error saving idle period:', err.message);
  }
}

// Called on every agent HEARTBEAT / instant status update
function trackStatus(deviceId, info) {
  if (!deviceId || !info) return;
  const status = (info.status || '').toUpperCase();
  const period = openIdle.get(deviceId);

  if (status === 'IDLE') {
    if (!period) {
      if (!isValidUser(info.currentUser)) return;
      const now = Date.now();
      // Agent flags IDLE only after IDLE_THRESHOLD_SECONDS without input, so the idle period actually began idleSeconds ago
      const startAt = new Date(now - (Number(info.idleSeconds) || 0) * 1000);
      openIdle.set(deviceId, {
        deviceId,
        hostname: info.hostname || deviceId,
        userEmail: (info.currentUser || '').trim().toLowerCase(),
        businessId: info.businessId || 'default',
        startAt: startAt.toISOString(),
        lastSeenAt: new Date(now).toISOString()
      });
      checkpoint();
      console.log(`[IdleLog] ${deviceId} (${info.currentUser}) went IDLE since ${startAt.toISOString()}`);
      const p = openIdle.get(deviceId);
      pushAlert({ type: 'IDLE_START', businessId: p.businessId, userEmail: p.userEmail, hostname: p.hostname, deviceId, idleSince: p.startAt });
    } else {
      period.lastSeenAt = new Date().toISOString();
      if (Date.now() - lastCheckpointTs > LAST_SEEN_CHECKPOINT_MS) checkpoint();
    }
  } else if (period) {
    closeIdlePeriod(deviceId, `status_${status.toLowerCase() || 'unknown'}`);
  }
}

function closeForDevice(deviceId, reason) {
  return closeIdlePeriod(deviceId, reason);
}

// On startup, close idle periods left open by a previous server run at their last known heartbeat
async function initIdleTracker() {
  const stale = loadOpenIdlePeriods();
  const ids = Object.keys(stale);
  for (const id of ids) {
    openIdle.set(id, stale[id]);
    await closeIdlePeriod(id, 'server_restart', new Date(stale[id].lastSeenAt || stale[id].startAt));
  }
  if (ids.length) console.log(`[IdleLog] Closed ${ids.length} stale idle period(s) from previous run`);
}

function openPeriodsFor(businessId, isSuper) {
  return [...openIdle.values()]
    .filter(p => isSuper || p.businessId === businessId)
    .map(p => ({ ...p, endAt: null, durationSec: null, open: true }));
}

function isSuperAdminScope(businessId) {
  return !businessId || businessId === 'all' || businessId === 'superadmin' || businessId === 'admin-super-001';
}

async function getIdleLogs({ businessId, userEmail, deviceId, from, to, limit = 500 }) {
  const isSuper = isSuperAdminScope(businessId);
  const fromDate = from ? new Date(from) : new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const toDate = to ? new Date(to) : new Date();

  let logs = [
    ...readIdleLogs({ businessId, fromDay: dayKey(fromDate), toDay: dayKey(toDate) }),
    ...openPeriodsFor(businessId, isSuper)
  ];

  const email = userEmail ? userEmail.trim().toLowerCase() : null;
  logs = logs.filter(l =>
    (!email || l.userEmail === email) &&
    (!deviceId || l.deviceId === deviceId) &&
    new Date(l.startAt) >= fromDate &&
    new Date(l.startAt) <= toDate
  );

  logs.sort((a, b) => new Date(b.startAt) - new Date(a.startAt));
  return logs.slice(0, Math.min(Number(limit) || 500, 5000));
}

// Idle periods that started on one day (yyyy-mm-dd, office timezone), optionally for one employee
function getIdleLogsForDay({ businessId, date, userEmail }) {
  const isSuper = isSuperAdminScope(businessId);
  const email = userEmail ? userEmail.trim().toLowerCase() : null;
  const logs = [
    ...readIdleLogs({ businessId, fromDay: date, toDay: date }),
    ...openPeriodsFor(businessId, isSuper).filter(p => dayKey(p.startAt) === date)
  ].filter(l => !email || l.userEmail === email);

  return logs
    .map(l => ({
      ...l,
      durationSec: l.durationSec != null ? l.durationSec : Math.round((Date.now() - new Date(l.startAt)) / 1000)
    }))
    .sort((a, b) => new Date(a.startAt) - new Date(b.startAt));
}

// Total idle time per user for one day (open periods are counted up to now)
async function getDailyIdleSummary({ businessId, date }) {
  const isSuper = isSuperAdminScope(businessId);
  const logs = [
    ...readIdleLogs({ businessId, fromDay: date, toDay: date }),
    ...openPeriodsFor(businessId, isSuper).filter(p => dayKey(p.startAt) === date)
  ];

  const byUser = new Map();
  for (const l of logs) {
    const sec = l.durationSec != null ? l.durationSec : Math.round((Date.now() - new Date(l.startAt)) / 1000);
    const key = `${l.userEmail}|${l.businessId}`;
    const row = byUser.get(key) || { userEmail: l.userEmail, businessId: l.businessId, date, totalIdleSec: 0, idleCount: 0, longestIdleSec: 0, devices: [] };
    row.totalIdleSec += sec;
    row.idleCount += 1;
    row.longestIdleSec = Math.max(row.longestIdleSec, sec);
    if (l.hostname && !row.devices.includes(l.hostname)) row.devices.push(l.hostname);
    byUser.set(key, row);
  }

  return [...byUser.values()].sort((a, b) => b.totalIdleSec - a.totalIdleSec);
}

module.exports = { initIdleTracker, trackStatus, closeForDevice, getIdleLogs, getIdleLogsForDay, getDailyIdleSummary };
