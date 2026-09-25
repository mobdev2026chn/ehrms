const mongoose = require('mongoose');

// Persists every idle period (agent status IDLE -> anything else) to 'dma_idle_logs' in DEV_HRMS.
// One document per idle period: { deviceId, hostname, userEmail, businessId, startAt, endAt, durationSec, endReason }
const COLLECTION = 'dma_idle_logs';
const LAST_SEEN_PERSIST_MS = 60 * 1000;

// deviceId -> { docId (Promise<ObjectId|null>), lastPersistTs }
const openIdle = new Map();

function idleCol() {
  if (mongoose.connection.readyState !== 1) return null;
  return mongoose.connection.useDb('DEV_HRMS').collection(COLLECTION);
}

function isValidUser(email) {
  const clean = (email || '').trim().toLowerCase();
  return clean && clean !== 'ektahr employee' && clean !== 'logged out' && clean !== '—';
}

async function openIdlePeriod(deviceId, info) {
  const col = idleCol();
  if (!col) return null;

  const now = Date.now();
  const idleSeconds = Number(info.idleSeconds) || 0;
  // Agent flags IDLE only after 300s without input, so the idle period actually began idleSeconds ago
  const startAt = new Date(now - idleSeconds * 1000);

  const res = await col.insertOne({
    deviceId,
    hostname: info.hostname || deviceId,
    userEmail: (info.currentUser || '').trim().toLowerCase(),
    businessId: info.businessId || 'default',
    startAt,
    endAt: null,
    durationSec: null,
    lastSeenAt: new Date(now),
    createdAt: new Date(now)
  });
  console.log(`[IdleLog] ${deviceId} (${info.currentUser}) went IDLE since ${startAt.toISOString()}`);
  return res.insertedId;
}

async function closeIdlePeriod(deviceId, reason, endAt = new Date()) {
  const entry = openIdle.get(deviceId);
  if (!entry) return;
  openIdle.delete(deviceId);

  try {
    const docId = await entry.docId;
    const col = idleCol();
    if (!docId || !col) return;

    const doc = await col.findOne({ _id: docId }, { projection: { startAt: 1 } });
    if (!doc) return;
    const durationSec = Math.max(0, Math.round((endAt - doc.startAt) / 1000));

    await col.updateOne({ _id: docId }, {
      $set: { endAt, durationSec, endReason: reason, lastSeenAt: endAt }
    });
    console.log(`[IdleLog] ${deviceId} idle period closed (${reason}), duration ${durationSec}s`);
  } catch (err) {
    console.error('[IdleLog] Error closing idle period:', err.message);
  }
}

// Called on every agent HEARTBEAT / instant status update
function trackStatus(deviceId, info) {
  if (!deviceId || !info) return;
  const status = (info.status || '').toUpperCase();
  const entry = openIdle.get(deviceId);

  if (status === 'IDLE') {
    if (!entry) {
      if (!isValidUser(info.currentUser)) return;
      const docId = openIdlePeriod(deviceId, info).catch(err => {
        console.error('[IdleLog] Error opening idle period:', err.message);
        return null;
      });
      openIdle.set(deviceId, { docId, lastPersistTs: Date.now() });
    } else if (Date.now() - entry.lastPersistTs > LAST_SEEN_PERSIST_MS) {
      // Keep lastSeenAt fresh so a server crash can still close the period at a sensible time
      entry.lastPersistTs = Date.now();
      entry.docId.then(docId => {
        const col = idleCol();
        if (docId && col) col.updateOne({ _id: docId }, { $set: { lastSeenAt: new Date() } }).catch(() => {});
      });
    }
  } else if (entry) {
    closeIdlePeriod(deviceId, `status_${status.toLowerCase() || 'unknown'}`);
  }
}

function closeForDevice(deviceId, reason) {
  return closeIdlePeriod(deviceId, reason);
}

// On startup, close idle periods left open by a previous server run at their last known heartbeat
async function closeStaleOpenPeriods() {
  const col = idleCol();
  if (!col) return;
  try {
    await col.createIndex({ businessId: 1, userEmail: 1, startAt: -1 });
    await col.createIndex({ deviceId: 1, endAt: 1 });

    const res = await col.updateMany({ endAt: null }, [
      {
        $set: {
          endAt: '$lastSeenAt',
          durationSec: { $max: [0, { $round: [{ $divide: [{ $subtract: ['$lastSeenAt', '$startAt'] }, 1000] }, 0] }] },
          endReason: 'server_restart'
        }
      }
    ]);
    if (res.modifiedCount) console.log(`[IdleLog] Closed ${res.modifiedCount} stale idle period(s) from previous run`);
  } catch (err) {
    console.error('[IdleLog] Error closing stale idle periods:', err.message);
  }
}

function initIdleTracker() {
  if (mongoose.connection.readyState === 1) closeStaleOpenPeriods();
  else mongoose.connection.once('open', closeStaleOpenPeriods);
}

function isSuperAdminScope(businessId) {
  return !businessId || businessId === 'all' || businessId === 'superadmin' || businessId === 'admin-super-001';
}

async function getIdleLogs({ businessId, userEmail, deviceId, from, to, limit = 500 }) {
  const col = idleCol();
  if (!col) return [];

  const filter = {};
  if (!isSuperAdminScope(businessId)) filter.businessId = businessId;
  if (userEmail) filter.userEmail = userEmail.trim().toLowerCase();
  if (deviceId) filter.deviceId = deviceId;
  if (from || to) {
    filter.startAt = {};
    if (from) filter.startAt.$gte = new Date(from);
    if (to) filter.startAt.$lte = new Date(to);
  }

  return col.find(filter, { projection: { lastSeenAt: 0 } })
    .sort({ startAt: -1 })
    .limit(Math.min(Number(limit) || 500, 5000))
    .toArray();
}

// Total idle time per user for one day (open periods are counted up to now)
async function getDailyIdleSummary({ businessId, date, tz = 'Asia/Kolkata' }) {
  const col = idleCol();
  if (!col) return [];

  const match = {};
  if (!isSuperAdminScope(businessId)) match.businessId = businessId;

  return col.aggregate([
    { $match: match },
    { $addFields: { day: { $dateToString: { format: '%Y-%m-%d', date: '$startAt', timezone: tz } } } },
    { $match: { day: date } },
    {
      $addFields: {
        effectiveSec: {
          $ifNull: ['$durationSec', { $round: [{ $divide: [{ $subtract: ['$$NOW', '$startAt'] }, 1000] }, 0] }]
        }
      }
    },
    {
      $group: {
        _id: { userEmail: '$userEmail', businessId: '$businessId' },
        totalIdleSec: { $sum: '$effectiveSec' },
        idleCount: { $sum: 1 },
        longestIdleSec: { $max: '$effectiveSec' },
        devices: { $addToSet: '$hostname' }
      }
    },
    {
      $project: {
        _id: 0,
        userEmail: '$_id.userEmail',
        businessId: '$_id.businessId',
        date,
        totalIdleSec: 1,
        idleCount: 1,
        longestIdleSec: 1,
        devices: 1
      }
    },
    { $sort: { totalIdleSec: -1 } }
  ]).toArray();
}

module.exports = { initIdleTracker, trackStatus, closeForDevice, getIdleLogs, getDailyIdleSummary };
