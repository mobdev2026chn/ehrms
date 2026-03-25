const Tracking = require('../models/Tracking');

const PRESENCE_INACTIVE_AFTER_MS = 10 * 60 * 1000;
const PRESENCE_STATUS_MONITOR_INTERVAL_MS = 60 * 1000;

let monitorHandle = null;

function buildPresenceOnlyQuery(extra = {}) {
  return {
    ...extra,
    $or: [{ taskId: null }, { taskId: { $exists: false } }],
  };
}

async function markLatestPresenceTrackingInactiveForStaff(staffId) {
  if (!staffId) return 0;

  const cutoff = new Date(Date.now() - PRESENCE_INACTIVE_AFTER_MS);
  const latest = await Tracking.findOne(buildPresenceOnlyQuery({ staffId }))
    .select('_id timestamp status')
    .sort({ timestamp: -1 })
    .lean();

  if (!latest?._id || latest.status !== 'active') return 0;
  if (!latest.timestamp || new Date(latest.timestamp) >= cutoff) return 0;

  const result = await Tracking.updateOne(
    { _id: latest._id, status: 'active' },
    {
      $set: {
        status: 'inactive',
        appStatus: 'inactive',
      },
    }
  );

  return result.modifiedCount || 0;
}

async function markStalePresenceTrackingsInactive() {
  const cutoff = new Date(Date.now() - PRESENCE_INACTIVE_AFTER_MS);
  const staleLatestTrackings = await Tracking.aggregate([
    { $match: buildPresenceOnlyQuery() },
    { $sort: { staffId: 1, timestamp: -1 } },
    {
      $group: {
        _id: '$staffId',
        latestId: { $first: '$_id' },
        latestTimestamp: { $first: '$timestamp' },
        latestStatus: { $first: '$status' },
      },
    },
    {
      $match: {
        latestStatus: 'active',
        latestTimestamp: { $lt: cutoff },
      },
    },
  ]);

  const staleIds = staleLatestTrackings
    .map((item) => item.latestId)
    .filter(Boolean);

  if (staleIds.length === 0) return 0;

  const result = await Tracking.updateMany(
    { _id: { $in: staleIds }, status: 'active' },
    {
      $set: {
        status: 'inactive',
        appStatus: 'inactive',
      },
    }
  );

  return result.modifiedCount || 0;
}

function startPresenceTrackingStatusMonitor() {
  if (monitorHandle) return;

  const runMonitor = async () => {
    try {
      const updated = await markStalePresenceTrackingsInactive();
      if (updated > 0) {
        console.log(`[PresenceTracking] Marked ${updated} stale staff tracking record(s) inactive`);
      }
    } catch (error) {
      console.error('[PresenceTracking] Inactive monitor failed:', error.message);
    }
  };

  runMonitor();
  monitorHandle = setInterval(runMonitor, PRESENCE_STATUS_MONITOR_INTERVAL_MS);
  if (typeof monitorHandle.unref === 'function') {
    monitorHandle.unref();
  }
}

module.exports = {
  markLatestPresenceTrackingInactiveForStaff,
  markStalePresenceTrackingsInactive,
  startPresenceTrackingStatusMonitor,
};
