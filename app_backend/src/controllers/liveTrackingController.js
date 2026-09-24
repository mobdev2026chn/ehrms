const mongoose = require('mongoose');
const LiveTracking = require('../models/LiveTracking');
const Staff = require('../models/Staff');
const Task = require('../models/Task');

/**
 * Helper to resolve staffId and adminId from authenticated request and task
 */
const resolveStaffAndAdmin = async (req, bodyTaskId) => {
  let staffId = req.user?._id;
  let adminId = req.user?.adminId || req.user?.companyId;
  let staffName = `${req.user?.firstName || ''} ${req.user?.lastName || ''}`.trim() || req.user?.name || '';
  let taskDoc = null;

  if (bodyTaskId) {
    if (mongoose.Types.ObjectId.isValid(bodyTaskId)) {
      taskDoc = await Task.findById(bodyTaskId);
    } else {
      taskDoc = await Task.findOne({ taskId: bodyTaskId });
    }
  }

  if (taskDoc) {
    if (!adminId && taskDoc.adminId) adminId = taskDoc.adminId;
    if (!staffId && taskDoc.staffId) staffId = taskDoc.staffId;
    if (!staffName && taskDoc.staffName) staffName = taskDoc.staffName;
  }

  if (staffId && (!adminId || !staffName)) {
    const staff = await Staff.findById(staffId).select('adminId companyId firstName lastName name');
    if (staff) {
      if (!adminId) adminId = staff.adminId || staff.companyId;
      if (!staffName) staffName = `${staff.firstName || ''} ${staff.lastName || ''}`.trim() || staff.name || '';
    }
  }

  return { staffId, adminId, staffName, taskDoc };
};

/**
 * @desc    Record a single live GPS tracking point
 * @route   POST /api/live-tracking/record
 * @access  Private (Staff / Mobile App)
 */
exports.recordLivePoint = async (req, res) => {
  try {
    const {
      taskId,
      taskIdStr,
      taskType,
      latitude,
      longitude,
      lat,
      lng,
      accuracy,
      speed,
      heading,
      altitude,
      batteryPercent,
      movementType,
      address,
      fullAddress,
      city,
      area,
      pincode,
      state,
      country,
      destinationLat,
      destinationLng,
      destinationAddress,
      distanceRemainingKm,
      status,
      appStatus,
      presenceStatus,
      exitReason,
      timestamp,
    } = req.body;

    const resolvedLat = Number(latitude != null ? latitude : lat);
    const resolvedLng = Number(longitude != null ? longitude : lng);

    if (!Number.isFinite(resolvedLat) || !Number.isFinite(resolvedLng)) {
      return res.status(400).json({
        success: false,
        message: 'Valid latitude and longitude are required',
      });
    }

    const { staffId, adminId, staffName, taskDoc } = await resolveStaffAndAdmin(
      req,
      taskId || taskIdStr
    );

    if (!staffId) {
      return res.status(401).json({
        success: false,
        message: 'Staff authentication required for tracking',
      });
    }

    const liveDoc = new LiveTracking({
      adminId: adminId || req.user?.adminId,
      staffId,
      staffName: staffName || undefined,
      taskId: taskDoc ? taskDoc._id : (mongoose.Types.ObjectId.isValid(taskId) ? taskId : undefined),
      taskIdStr: taskIdStr || taskDoc?.taskId || undefined,
      taskType: taskType || taskDoc?.taskType || undefined,
      latitude: resolvedLat,
      longitude: resolvedLng,
      accuracy: accuracy != null ? Number(accuracy) : undefined,
      speed: speed != null ? Number(speed) : undefined,
      heading: heading != null ? Number(heading) : undefined,
      altitude: altitude != null ? Number(altitude) : undefined,
      batteryPercent: batteryPercent != null ? Number(batteryPercent) : undefined,
      movementType: movementType || 'stop',
      address: address || undefined,
      fullAddress: fullAddress || address || undefined,
      city: city || undefined,
      area: area || undefined,
      pincode: pincode || undefined,
      state: state || undefined,
      country: country || undefined,
      destinationLat: destinationLat != null ? Number(destinationLat) : undefined,
      destinationLng: destinationLng != null ? Number(destinationLng) : undefined,
      destinationAddress: destinationAddress || undefined,
      distanceRemainingKm: distanceRemainingKm != null ? Number(distanceRemainingKm) : undefined,
      status: status || (taskDoc ? 'in_progress' : 'active'),
      appStatus: appStatus || 'active',
      presenceStatus: presenceStatus || (taskDoc ? 'task' : 'in_office'),
      exitReason: exitReason || undefined,
      timestamp: timestamp ? new Date(timestamp) : new Date(),
    });

    await liveDoc.save();

    return res.status(201).json({
      success: true,
      message: 'Live tracking point recorded successfully',
      data: liveDoc,
    });
  } catch (error) {
    console.error('[LiveTracking] recordLivePoint error:', error);
    return res.status(500).json({
      success: false,
      message: error.message || 'Failed to record live tracking point',
    });
  }
};

/**
 * @desc    Record a batch of offline tracking points
 * @route   POST /api/live-tracking/batch
 * @access  Private (Staff / Mobile App)
 */
exports.recordLiveBatch = async (req, res) => {
  try {
    const { points } = req.body;
    if (!Array.isArray(points) || points.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Points array is required and must not be empty',
      });
    }

    const { staffId, adminId, staffName } = await resolveStaffAndAdmin(req, null);

    const docsToInsert = points
      .map((p) => {
        const lat = Number(p.latitude != null ? p.latitude : p.lat);
        const lng = Number(p.longitude != null ? p.longitude : p.lng);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

        return {
          adminId: p.adminId || adminId,
          staffId: p.staffId || staffId,
          staffName: p.staffName || staffName,
          taskId: mongoose.Types.ObjectId.isValid(p.taskId) ? p.taskId : undefined,
          taskIdStr: p.taskIdStr || (typeof p.taskId === 'string' ? p.taskId : undefined),
          taskType: p.taskType || undefined,
          latitude: lat,
          longitude: lng,
          accuracy: p.accuracy != null ? Number(p.accuracy) : undefined,
          speed: p.speed != null ? Number(p.speed) : undefined,
          heading: p.heading != null ? Number(p.heading) : undefined,
          batteryPercent: p.batteryPercent != null ? Number(p.batteryPercent) : undefined,
          movementType: p.movementType || 'stop',
          address: p.address,
          fullAddress: p.fullAddress || p.address,
          city: p.city,
          area: p.area,
          pincode: p.pincode,
          status: p.status || 'offline',
          appStatus: p.appStatus || 'active',
          presenceStatus: p.presenceStatus || 'out_of_office',
          timestamp: p.timestamp ? new Date(p.timestamp) : new Date(),
        };
      })
      .filter(Boolean);

    if (docsToInsert.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No valid GPS points found in batch payload',
      });
    }

    const inserted = await LiveTracking.insertMany(docsToInsert, { ordered: false });

    return res.status(201).json({
      success: true,
      message: `Successfully stored ${inserted.length} offline tracking points`,
      insertedCount: inserted.length,
    });
  } catch (error) {
    console.error('[LiveTracking] recordLiveBatch error:', error);
    return res.status(500).json({
      success: false,
      message: error.message || 'Failed to process tracking batch',
    });
  }
};

/**
 * @desc    Get the latest live location for all active staff under an admin
 * @route   GET /api/live-tracking/live
 * @access  Private (Admin / Manager)
 */
exports.getLiveStaffLocations = async (req, res) => {
  try {
    const adminId = req.user?.adminId || req.user?._id;
    if (!adminId) {
      return res.status(401).json({ success: false, message: 'Unauthorized admin session' });
    }

    // Aggregate to get the most recent tracking document per staff member
    const latestPerStaff = await LiveTracking.aggregate([
      { $match: { adminId: new mongoose.Types.ObjectId(adminId) } },
      { $sort: { timestamp: -1 } },
      {
        $group: {
          _id: '$staffId',
          latestRecord: { $first: '$$ROOT' },
        },
      },
      {
        $lookup: {
          from: 'staffs',
          localField: '_id',
          foreignField: '_id',
          as: 'staffDetails',
        },
      },
      {
        $unwind: {
          path: '$staffDetails',
          preserveNullAndEmptyArrays: true,
        },
      },
      {
        $project: {
          staffId: '$_id',
          staffName: {
            $ifNull: [
              '$latestRecord.staffName',
              { $concat: ['$staffDetails.firstName', ' ', '$staffDetails.lastName'] },
            ],
          },
          employeeId: '$staffDetails.employeeId',
          workMode: '$staffDetails.workMode.mode',
          latitude: '$latestRecord.latitude',
          longitude: '$latestRecord.longitude',
          accuracy: '$latestRecord.accuracy',
          speed: '$latestRecord.speed',
          batteryPercent: '$latestRecord.batteryPercent',
          movementType: '$latestRecord.movementType',
          address: '$latestRecord.address',
          fullAddress: '$latestRecord.fullAddress',
          city: '$latestRecord.city',
          status: '$latestRecord.status',
          appStatus: '$latestRecord.appStatus',
          presenceStatus: '$latestRecord.presenceStatus',
          taskId: '$latestRecord.taskId',
          taskIdStr: '$latestRecord.taskIdStr',
          taskType: '$latestRecord.taskType',
          lastSeen: '$latestRecord.timestamp',
        },
      },
      { $sort: { lastSeen: -1 } },
    ]);

    return res.status(200).json({
      success: true,
      count: latestPerStaff.length,
      data: latestPerStaff,
    });
  } catch (error) {
    console.error('[LiveTracking] getLiveStaffLocations error:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * @desc    Get historical GPS breadcrumbs for a staff member
 * @route   GET /api/live-tracking/staff/:id/history
 * @access  Private (Admin / Staff)
 */
exports.getStaffLiveHistory = async (req, res) => {
  try {
    const { id } = req.params; // Staff ObjectId
    const { date, startDate, endDate, limit = 500 } = req.query;

    const query = { staffId: new mongoose.Types.ObjectId(id) };

    if (date) {
      const start = new Date(`${date}T00:00:00.000Z`);
      const end = new Date(`${date}T23:59:59.999Z`);
      query.timestamp = { $gte: start, $lte: end };
    } else if (startDate || endDate) {
      query.timestamp = {};
      if (startDate) query.timestamp.$gte = new Date(startDate);
      if (endDate) query.timestamp.$lte = new Date(endDate);
    }

    const history = await LiveTracking.find(query)
      .sort({ timestamp: 1 })
      .limit(Number(limit))
      .lean();

    return res.status(200).json({
      success: true,
      count: history.length,
      data: history,
    });
  } catch (error) {
    console.error('[LiveTracking] getStaffLiveHistory error:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * @desc    Get breadcrumb trail for a specific task
 * @route   GET /api/live-tracking/task/:taskId
 * @access  Private
 */
exports.getTaskLiveTrail = async (req, res) => {
  try {
    const { taskId } = req.params;
    const query = mongoose.Types.ObjectId.isValid(taskId)
      ? { $or: [{ taskId: new mongoose.Types.ObjectId(taskId) }, { taskIdStr: taskId }] }
      : { taskIdStr: taskId };

    const points = await LiveTracking.find(query).sort({ timestamp: 1 }).lean();

    return res.status(200).json({
      success: true,
      count: points.length,
      data: points,
    });
  } catch (error) {
    console.error('[LiveTracking] getTaskLiveTrail error:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * @desc    Update staff tracking status (e.g. arrived, exit ride)
 * @route   POST /api/live-tracking/status
 * @access  Private
 */
exports.updateTrackingStatus = async (req, res) => {
  try {
    const { status, exitReason, taskId, latitude, longitude, address } = req.body;
    const { staffId, adminId, staffName } = await resolveStaffAndAdmin(req, taskId);

    const record = new LiveTracking({
      adminId,
      staffId,
      staffName,
      taskId: mongoose.Types.ObjectId.isValid(taskId) ? taskId : undefined,
      latitude: Number(latitude) || 0,
      longitude: Number(longitude) || 0,
      address,
      status: status || 'active',
      exitReason: exitReason || undefined,
      exitedAt: status === 'exited' ? new Date() : undefined,
      timestamp: new Date(),
    });

    await record.save();

    return res.status(200).json({
      success: true,
      message: `Tracking status updated to ${status}`,
      data: record,
    });
  } catch (error) {
    console.error('[LiveTracking] updateTrackingStatus error:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};
