const mongoose = require('mongoose');
const Tracking = require('../models/Tracking');
const Staff = require('../models/Staff');
const Company = require('../models/Company');
const { getBusinessTimezone } = require('./leaveAttendanceHelper');
const { formatCalendarDayInTimezone } = require('./dateUtils');

/**
 * Resolve company business IANA timezone for a staff doc or id.
 * @param {import('mongoose').Types.ObjectId|string|{ businessId?: import('mongoose').Types.ObjectId }} staffOrId
 */
async function resolveBusinessTimezone(staffOrId) {
  let businessId = null;
  if (staffOrId != null && typeof staffOrId === 'object' && staffOrId.businessId) {
    businessId = staffOrId.businessId;
  } else {
    const sid =
      staffOrId != null && typeof staffOrId === 'object' && staffOrId._id ? staffOrId._id : staffOrId;
    if (sid) {
      const s = await Staff.findById(sid).select('businessId').lean();
      businessId = s?.businessId;
    }
  }
  if (!businessId) return getBusinessTimezone(null);
  const c = await Company.findById(businessId).select('settings.business.timezone timezone').lean();
  return getBusinessTimezone(c);
}

/**
 * Number of distinct tasks the staff has tracking for on the same business-calendar day as `atTime`
 * (timestamp <= atTime), plus `taskId` if provided so the first point of a new task counts immediately.
 */
async function computeDailyTaskCountForStaff({ staffId, taskId, atTime, timeZone }) {
  const useTz = (timeZone && String(timeZone).trim()) || getBusinessTimezone(null);
  const staffObjectId = mongoose.Types.ObjectId.isValid(String(staffId))
    ? new mongoose.Types.ObjectId(String(staffId))
    : staffId;
  const calendarDayKey = formatCalendarDayInTimezone(atTime, useTz);

  const rows = await Tracking.aggregate([
    {
      $match: {
        staffId: staffObjectId,
        taskId: { $exists: true, $ne: null },
        timestamp: { $lte: atTime },
      },
    },
    {
      $addFields: {
        _dayKey: {
          $dateToString: { format: '%Y-%m-%d', date: '$timestamp', timezone: useTz },
        },
      },
    },
    { $match: { _dayKey: calendarDayKey } },
    { $group: { _id: '$taskId' } },
  ]);

  const ids = new Set(rows.map((r) => String(r._id)));
  if (taskId != null && taskId !== '') {
    const tid = taskId._id || taskId;
    ids.add(String(tid));
  }
  return ids.size;
}

module.exports = { resolveBusinessTimezone, computeDailyTaskCountForStaff };
