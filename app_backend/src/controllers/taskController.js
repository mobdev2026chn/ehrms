const Task = require('../models/Task');
const TaskDetails = require('../models/TaskDetails');
const TaskSettings = require('../models/TaskSettings');
const FormResponse = require('../models/FormResponse');

/**
 * DATA MODEL – taskId / _id semantics:
 * - tasks._id: MongoDB ObjectId (e.g. 6986ebfaefed8a6147709364)
 * - tasks.taskId: Human-readable TASK-XXXXXXXX-XXXX (e.g. TASK-69844967-989712-8903)
 * - task_details.taskId: = tasks._id (ObjectId) – lookup key, NOT same as tasks.taskId
 * - trackings.taskId: = tasks.taskId (TASK-XXXXXXXX-XXXX) – same format as tasks.taskId
 */

/** Build location object per spec: { lat, lng, address?, pincode?, recordedAt } */
function buildLocationObject(lat, lng, address, pincode) {
  const now = parseTimestamp(new Date());
  return {
    lat: Number(lat),
    lng: Number(lng),
    ...(address != null && address !== '' && { address: String(address) }),
    ...(pincode != null && pincode !== '' && { pincode: String(pincode) }),
    recordedAt: now,
  };
}

function normalizeDurationSeconds(value) {
  const num = Number(value);
  if (!Number.isFinite(num) || num < 0) return 0;
  return Math.round(num);
}

function normalizeTravelActivityDuration(input) {
  if (!input || typeof input !== 'object') return undefined;
  return {
    driveDuration: normalizeDurationSeconds(input.driveDuration),
    walkDuration: normalizeDurationSeconds(input.walkDuration),
    stopDuration: normalizeDurationSeconds(input.stopDuration),
  };
}

/** Valid status transitions for updateTask. Aligned with task status enum. */
const VALID_TRANSITIONS = {
  approved: ['assigned', 'pending', 'scheduled', 'reopened', 'not yet started', 'hold'],
  staffapproved: ['assigned', 'pending', 'scheduled', 'reopened', 'not yet started', 'hold'],
  rejected: ['assigned', 'pending', 'reopened', 'not yet started', 'hold', 'delayed tasks'],
  in_progress: ['approved', 'staffapproved', 'assigned', 'pending', 'exited', 'reopened', 'not yet started', 'pending', 'hold'],
  'in progress': ['approved', 'staffapproved', 'assigned', 'pending', 'exited', 'reopened', 'not yet started', 'hold'],
  arrived: ['in_progress', 'in progress'],
  'serving today': ['in_progress', 'in progress', 'reopened', 'pending'],
  'delayed tasks': ['in_progress', 'in progress', 'pending', 'reopened'],
  'completed tasks': ['arrived', 'in_progress', 'in progress', 'serving today'],
  completed: ['arrived', 'in_progress', 'in progress', 'holdOnArrival', 'reopenedOnArrival'],
  reopened: ['exited', 'completed', 'completed tasks', 'rejected'],
  reopenedOnArrival: ['exitOnArrival', 'exitedOnArrival'],
  hold: ['in_progress', 'in progress', 'pending', 'assigned'],
  exited: ['in_progress', 'in progress'],
  exitOnArrival: ['arrived', 'holdOnArrival', 'reopenedOnArrival'],
  exitedOnArrival: ['arrived'],
  holdOnArrival: ['arrived'],
  waiting_for_approval: ['arrived', 'in progress', 'in_progress', 'holdOnArrival', 'reopenedOnArrival'],
};
function normalizeStatusForTransition(s) {
  const v = String(s || '').toLowerCase().trim();
  if (v === 'in progress') return 'in_progress';
  return v;
}
function isValidStatusTransition(fromStatus, toStatus) {
  if (!toStatus) return true;
  const to = normalizeStatusForTransition(toStatus);
  const from = normalizeStatusForTransition(fromStatus);
  const key = Object.keys(VALID_TRANSITIONS).find((k) => k.toLowerCase() === to);
  const allowed = VALID_TRANSITIONS[to] || VALID_TRANSITIONS[to.replace(/\s+/g, '_')] || (key ? VALID_TRANSITIONS[key] : undefined);
  if (!allowed) return true; // Allow other transitions for backward compat
  const fromNorm = from.replace(/\s+/g, '_');
  const fromLower = fromNorm.toLowerCase();
  return allowed.includes(from) || allowed.includes(fromNorm) ||
    allowed.some((a) => String(a).toLowerCase() === fromLower);
}
const Customer = require('../models/Customer');
const Tracking = require('../models/Tracking');
const { parseTimestamp } = require('../utils/dateUtils');

const MINIMAL_TASK_KEYS = [
  'taskId', 'taskTitle', 'description', 'status', 'assignedTo', 'customerId',
  'assignedBy', 'assignedDate', 'expectedCompletionDate', 'earliestCompletionDate',
  'latestCompletionDate', 'businessId', 'source',
];

const EXTENDED_TASK_KEYS = [
  'sourceLocation', 'destinationLocation', 'destinationChanged', 'destinations',
  'startLocation', 'rideStartLocation', 'rideStartedAt', 'startTime', 'started',
  'tripDistanceKm', 'tripDurationSeconds', 'arrivalTime', 'arrived',
  'arrivedLatitude', 'arrivedLongitude', 'arrivedFullAddress', 'arrivedPincode',
  'arrivedDate', 'arrivedTime', 'arrivalLocation', 'sourceFullAddress',
  'photoProofUrl', 'photoProofUploadedAt', 'photoProofDescription', 'photoProofLat',
  'photoProofLng', 'photoProofAddress', 'otpCode', 'otpSentAt', 'otpVerifiedAt',
  'otpVerifiedLat', 'otpVerifiedLng', 'otpVerifiedAddress', 'progressSteps',
  'completedDate', 'completedBy', 'locationHistory', 'travelActivityDuration',
  'approvedAt', 'approvedBy', 'rejectedAt', 'rejectedBy',
];
// exit and restarted are stored in tasks collection and must never be unset

/** Build $unset for extended fields (to keep tasks collection minimal). Exported for trackingController. */
exports.buildUnsetExtended = function buildUnsetExtended() {
  const unset = {};
  for (const k of EXTENDED_TASK_KEYS) unset[k] = 1;
  return unset;
};
exports.normalizeTravelActivityDuration = normalizeTravelActivityDuration;

/** Extract minimal fields for tasks collection. */
function getMinimalTaskFields(doc) {
  const obj = doc?.toObject ? doc.toObject() : { ...doc };
  const out = {};
  for (const k of MINIMAL_TASK_KEYS) {
    if (obj[k] !== undefined) out[k] = obj[k];
  }
  return out;
}

/** Generate taskId in format TASK-XXXXXXXX-XXXX (alphanumeric) */
function generateTaskId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const rand = () => chars[Math.floor(Math.random() * chars.length)];
  const p1 = Array(8).fill(0).map(() => rand()).join('');
  const p2 = Array(4).fill(0).map(() => rand()).join('');
  return `TASK-${p1}-${p2}`;
}

/** Fields that come from TaskSettings only – do not store in task_details */
const TASK_SETTINGS_ONLY_FIELDS = ['isOtpRequired', 'isGeoFenceRequired', 'isPhotoRequired', 'isFormRequired'];

/** Upsert full task details into task_details collection. Exported for use in trackingController.
 * fullDoc must include taskMongoId (tasks._id) for lookup; task_details.taskId stores tasks._id.
 */
exports.upsertTaskDetails = async function upsertTaskDetails(fullDoc) {
  const taskMongoId = fullDoc?.taskMongoId ?? fullDoc?._id;
  if (!fullDoc || !taskMongoId) return;
  try {
    const obj = fullDoc?.toObject ? fullDoc.toObject() : { ...fullDoc };
    delete obj.locationHistory;
    delete obj.__v;
    delete obj._id; // task_details gets its own _id
    obj.taskId = taskMongoId; // task_details.taskId = tasks._id (ObjectId)
    TASK_SETTINGS_ONLY_FIELDS.forEach((k) => delete obj[k]);
    const unsetFields = {};
    TASK_SETTINGS_ONLY_FIELDS.forEach((k) => { unsetFields[k] = 1; });
    await TaskDetails.findOneAndUpdate(
      { taskId: taskMongoId },
      { $set: obj, $unset: unsetFields },
      { upsert: true, new: true }
    );
    console.log('[Tasks] Upserted task_details for task:', taskMongoId);
  } catch (err) {
    console.warn('[Tasks] upsertTaskDetails error:', err.message);
  }
};

/** Normalize status for app: case-insensitive match, trim spaces, return canonical value so app never sees "Unknown". */
function normalizeStatusForApp(status) {
  if (status == null || typeof status !== 'string') return 'assigned';
  const s = status.trim().toLowerCase().replace(/\s+/g, ' ');
  const noSpaces = s.replace(/\s/g, '').replace(/_/g, '');
  const map = {
    hold: 'hold',
    onhold: 'hold',
    notyetstarted: 'assigned',
    delayedtasks: 'pending',
    servingtoday: 'in_progress',
    assigned: 'assigned',
    assignedtasks: 'assigned',
    pending: 'pending',
    pendingtasks: 'pending',
    scheduled: 'scheduled',
    scheduledtasks: 'scheduled',
    inprogress: 'in_progress',
    'in_progress': 'in_progress',
    completed: 'completed',
    completedtasks: 'completed',
    arrived: 'arrived',
    exited: 'exited',
    exitedonarrival: 'exitedOnArrival',
    exitonarrival: 'exitedOnArrival',
    holdonarrival: 'holdOnArrival',
    reopenedonarrival: 'reopenedOnArrival',
    waitingforapproval: 'waiting_for_approval',
    'waiting_for_approval': 'waiting_for_approval',
    approved: 'approved',
    staffapproved: 'staffapproved',
    rejected: 'rejected',
    reopened: 'reopened',
    cancelled: 'cancelled',
    cancelledtasks: 'cancelled',
    onlineready: 'onlineReady',
  };
  return map[noSpaces] || status;
}

/** Merge Task + TaskDetails for API response. Extended fields always from task_details. */
async function mergeTaskWithDetails(taskDoc) {
  if (!taskDoc) return null;
  const task = taskDoc.toObject ? taskDoc.toObject() : { ...taskDoc };
  const taskMongoId = task._id;
  let details = null;
  if (taskMongoId) {
    details = await TaskDetails.findOne({ taskId: taskMongoId }).lean();
  }
  const merged = { ...(details || {}), ...task };
  merged._id = task._id;
  // task.taskId = human-readable (TASK-XXXXXXXX-XXXX); details.taskId = ObjectId (for lookup only)
  merged.taskId = task.taskId || taskMongoId?.toString?.();
  if (details) {
    for (const k of EXTENDED_TASK_KEYS) {
      if (details[k] !== undefined) merged[k] = details[k];
    }
  }
  merged.status = normalizeStatusForApp(merged.status);
  return merged;
}
const fs = require('fs');
const { sendTaskOtpEmail } = require('../services/emailService');
const digitalOceanService = require('../services/digitalOceanService');

/** Normalize date fields in request body for correct UTC storage. */
function normalizeTaskBody(body) {
  const out = { ...body };
  const dateFields = ['expectedCompletionDate', 'assignedDate', 'earliestCompletionDate', 'latestCompletionDate'];
  for (const k of dateFields) {
    if (out[k] != null) out[k] = parseTimestamp(out[k]);
  }
  return out;
}

exports.createTask = async (req, res) => {
  try {
    const staffId = req.staff?._id;
    // businessId: from staff (staffs collection), else req.companyId (auth middleware), else body
    let businessId = req.staff?.businessId ?? req.companyId ?? req.body?.businessId;
    businessId = businessId?._id ?? businessId; // handle populated object
    const normalized = normalizeTaskBody(req.body);
    delete normalized.taskId; // Never use client taskId; always auto-generate
    const minimal = getMinimalTaskFields(normalized);
    // Auto-generate taskId in format TASK-XXXXXXXX-XXXX (alphanumeric); never use ObjectId
    minimal.taskId = generateTaskId();
    if (!minimal.source) minimal.source = 'app';
    // assignedBy: staff creating task (from auth) or fallback to assignedTo
    minimal.assignedBy = staffId ?? minimal.assignedTo ?? normalized.assignedTo;
    if (businessId) minimal.businessId = businessId;
    const now = parseTimestamp(new Date());
    if (staffId && !minimal.assignedDate) minimal.assignedDate = now;
    const newTask = new Task(minimal);
    await newTask.save();
    const fullDoc = { ...normalized, taskId: newTask.taskId, _id: newTask._id, taskMongoId: newTask._id };
    await exports.upsertTaskDetails(fullDoc);
    const merged = await mergeTaskWithDetails(newTask);
    res.status(201).json(merged);
  } catch (error) {
    console.error('[Tasks] createTask validation error:', error.message);
    console.error('[Tasks] Request body:', JSON.stringify(req.body, null, 2));
    if (error.errors) {
      Object.keys(error.errors).forEach((k) => {
        console.error(`[Tasks]   ${k}:`, error.errors[k]?.message);
      });
    }
    res.status(400).json({ message: error.message });
  }
};

exports.getAllTasks = async (req, res) => {
  try {
    console.log('[Tasks] GET /tasks - fetching all tasks...');
    const tasks = await Task.find().populate('assignedTo').populate('customerId');
    const merged = await Promise.all(tasks.map((t) => mergeTaskWithDetails(t)));
    console.log('[Tasks] Fetched', merged.length, 'task(s)');
    res.status(200).json(merged);
  } catch (error) {
    console.error('[Tasks] Error fetching all tasks:', error.message);
    res.status(500).json({ message: error.message });
  }
};

exports.getTasksByStaffId = async (req, res) => {
  try {
    const { staffId } = req.params;
    console.log('[Tasks] GET /tasks/staff/:staffId - staffId:', staffId);
    const tasks = await Task.find({ assignedTo: staffId })
      .populate('assignedTo')
      .populate('customerId');
    const companyId = tasks[0] ? getCompanyIdFromTask(tasks[0]) : null;
    const mergedRaw = await Promise.all(tasks.map((t) => mergeTaskWithDetails(t)));
    const merged = await Promise.all(
      mergedRaw.map((t) => mergeTaskSettings(t, companyId))
    );
    console.log('[Tasks] Fetched', merged.length, 'task(s) for staff');
    res.status(200).json(merged);
  } catch (error) {
    console.error('[Tasks] Error fetching tasks by staff:', error.message);
    res.status(500).json({ message: error.message });
  }
};

/** Merge task-settings (enableOtpVerification, etc.) into task for API response. */
async function mergeTaskSettings(taskDoc, companyId) {
  const task = taskDoc?.toObject ? taskDoc.toObject() : { ...taskDoc };
  task.customFields = task.customFields || {};
  if (task.progressSteps?.otpVerified === true || task.otpVerifiedAt) {
    task.customFields.otpVerified = true;
    task.customFields.otpVerifiedAt = task.otpVerifiedAt || task.customFields.otpVerifiedAt;
  }
  try {
    let settings = null;
    // businessId in Staff/Task = businessId in task-settings; query by either
    if (companyId) {
      settings = await TaskSettings.findOne({
        $or: [{ companyId }, { businessId: companyId }],
      }).lean();
    }
    if (!settings && !companyId) {
      settings = await TaskSettings.findOne().lean();
    }
    task.customFields = task.customFields || {};
    if (settings) {
      // OTP required/not required comes only from TaskSettings (enableOtpVerification)
      task.customFields.otpRequired = settings.settings?.enableOtpVerification === true;
      if (settings.settings?.requireApprovalOnComplete !== undefined) {
        task.requireApprovalOnComplete = settings.settings.requireApprovalOnComplete;
      }
      if (settings.settings?.autoApprove !== undefined) {
        task.autoApprove = settings.settings.autoApprove;
      }
    } else {
      task.customFields.otpRequired = false;
    }
  } catch (err) {
    console.warn('[Tasks] mergeTaskSettings:', err.message);
  }
  return task;
}

function getCompanyIdFromTask(task) {
  const assignedTo = task?.assignedTo;
  const fromStaff = assignedTo?.businessId;
  const fromTask = task?.businessId;
  const id = fromStaff?._id ?? fromStaff ?? fromTask?._id ?? fromTask;
  return id || null;
}

/** Find battery percent from tracking record closest to given date (within 60 min). */
function batteryAtTime(trackingRecords, date) {
  if (!date || !Array.isArray(trackingRecords) || trackingRecords.length === 0) return undefined;
  const t = new Date(date).getTime();
  const oneHour = 60 * 60 * 1000;
  let best = null;
  let bestDiff = Infinity;
  for (const r of trackingRecords) {
    const rt = (r.timestamp || r.time) ? new Date(r.timestamp || r.time).getTime() : NaN;
    if (Number.isNaN(rt) || r.batteryPercent == null) continue;
    const diff = Math.abs(rt - t);
    if (diff <= oneHour && diff < bestDiff) {
      bestDiff = diff;
      best = r.batteryPercent;
    }
  }
  return best != null ? Number(best) : undefined;
}

function normalizeTravelMovementType(movementType) {
  const value = String(movementType || '').trim().toLowerCase();
  if (value === 'drive' || value === 'driving') return 'drive';
  if (value === 'walk' || value === 'walking') return 'walk';
  return 'stop';
}

function getTravelMetricsWindow(taskObj, endTimeInput) {
  const endTime = endTimeInput ? new Date(endTimeInput) : null;
  if (!endTime || Number.isNaN(endTime.getTime())) return null;

  const restarts = taskObj?.tasks_restarted || taskObj?.restarted || [];
  let startRaw = taskObj?.startTime || taskObj?.rideStartedAt || taskObj?.started;
  if (Array.isArray(restarts) && restarts.length > 0) {
    const last = restarts[restarts.length - 1];
    startRaw = last?.restartedAt || last?.resumedAt || last?.time || startRaw;
  }

  const startTime = startRaw ? new Date(startRaw) : null;
  if (!startTime || Number.isNaN(startTime.getTime()) || endTime <= startTime) {
    return null;
  }
  return { startTime, endTime };
}

function computeTravelMetricsFromTrackingRecords(trackingRecords, window) {
  if (!window) return null;
  const { startTime, endTime } = window;
  const totalSeconds = Math.max(0, Math.round((endTime.getTime() - startTime.getTime()) / 1000));

  const movementRecords = (trackingRecords || [])
    .map((record) => {
      const tsRaw = record.timestamp || record.time;
      const ts = tsRaw ? new Date(tsRaw) : null;
      if (!ts || Number.isNaN(ts.getTime())) return null;
      return { ...record, _ts: ts };
    })
    .filter((record) => record != null && record._ts <= endTime)
    .sort((a, b) => a._ts - b._ts);

  if (movementRecords.length === 0) {
    return {
      tripDurationSeconds: totalSeconds,
      travelActivityDuration: {
        driveDuration: 0,
        walkDuration: 0,
        stopDuration: totalSeconds,
      },
    };
  }

  let driveDuration = 0;
  let walkDuration = 0;
  let stopDuration = 0;

  for (let i = 0; i < movementRecords.length; i += 1) {
    const current = movementRecords[i];
    const next = movementRecords[i + 1];
    const segmentStart = i === 0
      ? startTime
      : new Date(Math.max(current._ts.getTime(), startTime.getTime()));
    const nextTime = next?._ts ?? endTime;
    const segmentEnd = new Date(Math.min(nextTime.getTime(), endTime.getTime()));
    if (segmentEnd <= segmentStart) continue;

    const durationSeconds = Math.round(
      (segmentEnd.getTime() - segmentStart.getTime()) / 1000
    );
    switch (normalizeTravelMovementType(current.movementType)) {
      case 'drive':
        driveDuration += durationSeconds;
        break;
      case 'walk':
        walkDuration += durationSeconds;
        break;
      case 'stop':
      default:
        stopDuration += durationSeconds;
        break;
    }
  }

  const accounted = driveDuration + walkDuration + stopDuration;
  if (accounted < totalSeconds) {
    stopDuration += (totalSeconds - accounted);
  }

  return {
    tripDurationSeconds: totalSeconds,
    travelActivityDuration: {
      driveDuration,
      walkDuration,
      stopDuration,
    },
  };
}

async function computePersistedTravelMetrics(taskMongoId, taskObj, endTimeInput) {
  const window = getTravelMetricsWindow(taskObj, endTimeInput);
  if (!taskMongoId || !window) return null;
  const trackingRecords = await Tracking.find({
    taskId: taskMongoId,
    timestamp: { $lte: window.endTime },
  })
    .select('timestamp time movementType latitude longitude status')
    .sort({ timestamp: 1 })
    .lean();
  return computeTravelMetricsFromTrackingRecords(trackingRecords, window);
}

exports.computePersistedTravelMetrics = computePersistedTravelMetrics;

exports.getTaskById = async (req, res) => {
  try {
    const taskId = req.params.id;
    console.log('[Tasks] GET /tasks/:id - taskId:', taskId);
    const task = await Task.findById(taskId).populate('assignedTo').populate('customerId');
    if (!task) {
      console.log('[Tasks] Task not found:', taskId);
      return res.status(404).json({ message: 'Task not found' });
    }
    const mergedTask = await mergeTaskWithDetails(task);
    const companyId = getCompanyIdFromTask(task);
    const merged = await mergeTaskSettings(mergedTask, companyId);

    const trackingRecords = await Tracking.find({ taskId: task._id }).sort({ timestamp: 1 }).lean();
    if (trackingRecords.length > 0) {
      if (merged.startTime) merged.startBatteryPercent = batteryAtTime(trackingRecords, merged.startTime);
      if (merged.arrivalTime) merged.arrivalBatteryPercent = batteryAtTime(trackingRecords, merged.arrivalTime);
      if (merged.photoProofUploadedAt) merged.photoProofBatteryPercent = batteryAtTime(trackingRecords, merged.photoProofUploadedAt);
      if (merged.otpVerifiedAt) merged.otpVerifiedBatteryPercent = batteryAtTime(trackingRecords, merged.otpVerifiedAt);
      if (merged.completedDate) merged.completedBatteryPercent = batteryAtTime(trackingRecords, merged.completedDate);
      const exits = merged.exit || [];
      merged.exit = exits.map((ex) => ({
        ...ex,
        batteryPercent: batteryAtTime(trackingRecords, ex.exitedAt || ex.time),
      }));
      const restarts = merged.restarted || [];
      merged.restarted = restarts.map((rs) => ({
        ...rs,
        batteryPercent: batteryAtTime(trackingRecords, rs.restartedAt || rs.resumedAt || rs.time),
      }));
    }

    const persistedTravelMetrics = computeTravelMetricsFromTrackingRecords(
      trackingRecords,
      getTravelMetricsWindow(merged, merged.arrivalTime || merged.arrived)
    );
    if (persistedTravelMetrics) {
      merged.tripDurationSeconds = persistedTravelMetrics.tripDurationSeconds;
      merged.travelActivityDuration = persistedTravelMetrics.travelActivityDuration;
    }

    console.log('[Tasks] Fetched task:', task.taskId || taskId);
    res.status(200).json(merged);
  } catch (error) {
    console.error('[Tasks] Error fetching task by id:', error.message);
    res.status(500).json({ message: error.message });
  }
};

exports.updateTask = async (req, res) => {
  try {
    const taskId = req.params.id;
    const {
      status,
      startTime,
      started,
      startLocation,
      startLat,
      startLng,
      sourceLocation,
      destinationLocation,
      destinationChanged,
      tripDistanceKm,
      tripDurationSeconds,
      arrivalTime,
    } = req.body;
    const resolvedStartLocation = startLocation || (startLat != null && startLng != null ? { lat: startLat, lng: startLng } : null);
    console.log('[Tasks] PATCH /tasks/:id - full body:', JSON.stringify(req.body));
    const updateData = {};
    if (status != null) updateData.status = status;
    const now = new Date();
    if (status === 'in_progress') {
      updateData.rideStartedAt = parseTimestamp(now);
      if (resolvedStartLocation) {
        updateData.rideStartLocation = buildLocationObject(
          resolvedStartLocation.lat,
          resolvedStartLocation.lng,
          resolvedStartLocation.address ?? resolvedStartLocation.fullAddress,
          resolvedStartLocation.pincode
        );
      }
    }
    if (startTime != null) updateData.startTime = parseTimestamp(startTime);
    if (started != null) updateData.started = parseTimestamp(started);
    if (resolvedStartLocation != null) updateData.startLocation = resolvedStartLocation;
    if (sourceLocation != null) updateData.sourceLocation = sourceLocation;
    if (destinationLocation != null) {
      updateData.destinationLocation = destinationLocation;
      updateData.destinationChanged = destinationChanged !== false;
    }
    if (destinationChanged != null && destinationLocation == null)
      updateData.destinationChanged = destinationChanged;
    if (tripDistanceKm != null) updateData.tripDistanceKm = Number(tripDistanceKm);
    if (tripDurationSeconds != null) updateData.tripDurationSeconds = Number(tripDurationSeconds);
    if (arrivalTime != null) updateData.arrivalTime = parseTimestamp(arrivalTime);
    const staffId = req.staff?._id;
    if ((status === 'approved' || status === 'staffapproved') && staffId) {
      updateData.approvedAt = parseTimestamp(new Date());
      updateData.approvedBy = staffId;
    }
    if (status === 'rejected' && staffId) {
      updateData.rejectedAt = new Date();
      updateData.rejectedBy = staffId;
    }

    const task = await Task.findById(taskId).populate('assignedTo').populate('customerId');
    if (!task) return res.status(404).json({ message: 'Task not found' });

    if (status != null && !isValidStatusTransition(task.status, status)) {
      const msg = `Invalid status transition: ${task.status} → ${status}`;
      console.log('[Tasks] PATCH rejected:', msg);
      return res.status(400).json({ message: msg });
    }

    const details = await TaskDetails.findOne({ taskId: task._id }).lean();
    const fullDoc = { ...(details || {}), ...req.body, ...updateData, taskMongoId: task._id };
    if (destinationLocation != null) {
      fullDoc.destinations = fullDoc.destinations || [];
      fullDoc.destinations.push({
        lat: Number(destinationLocation.lat),
        lng: Number(destinationLocation.lng),
        address: destinationLocation.address || '',
        changedAt: parseTimestamp(new Date()),
      });
    }
    const minimalUpdate = getMinimalTaskFields(fullDoc);
    delete minimalUpdate.taskId; // Never overwrite taskId – set at creation (TASK-XXXXXXXX-XXXX)
    const updateOp = {};
    if (Object.keys(minimalUpdate).length > 0) updateOp.$set = minimalUpdate;
    updateOp.$unset = exports.buildUnsetExtended();
    // Update tasks collection (status, etc.)
    await Task.findByIdAndUpdate(taskId, updateOp);
    // Sync to task_details (approve → approved, start ride → in_progress)
    await exports.upsertTaskDetails(fullDoc);
    const updatedTask = await Task.findById(taskId).populate('assignedTo').populate('customerId');
    const merged = await mergeTaskWithDetails(updatedTask);
    const companyId = getCompanyIdFromTask(updatedTask);
    const finalMerged = await mergeTaskSettings(merged, companyId);
    console.log('[Tasks] Updated task:', task.taskId);
    res.status(200).json(finalMerged);
  } catch (error) {
    console.error('[Tasks] Error updating task:', error.message);
    res.status(500).json({ message: error.message });
  }
};

// POST /tasks/:id/location – broadcast live GPS for Socket.io. Location stored in trackings collection.
exports.updateLocation = async (req, res) => {
  try {
    const taskId = req.params.id;
    const { lat, lng, timestamp, batteryPercent, movementType } = req.body;
    if (lat == null || lng == null) {
      return res.status(400).json({ message: 'lat and lng required' });
    }
    const point = {
      lat: Number(lat),
      lng: Number(lng),
      timestamp: parseTimestamp(timestamp),
      batteryPercent: batteryPercent != null ? Number(batteryPercent) : undefined,
    };
    const task = await Task.findById(taskId)
      .select('taskId assignedTo')
      .populate('assignedTo', 'name');
    if (!task) {
      return res.status(404).json({ message: 'Task not found' });
    }
    // Note: Tracking storage is via POST /api/tracking/store (mobile calls it separately)
    // Broadcast to Socket.io for live view (staff + admin)
    const io = req.app.get('io');
    if (io) {
      const staffIdStr = task.assignedTo?._id?.toString();
      const payload = {
        taskId,
        taskMongoId: taskId,
        staffId: staffIdStr || undefined,
        latitude: point.lat,
        longitude: point.lng,
        timestamp: point.timestamp,
        batteryPercent: point.batteryPercent,
        movementType: movementType || undefined,
        staffName: task.assignedTo?.name,
      };
      io.to(`task:${taskId}`).emit('tracking:location', payload);
      io.to('admin:tracking').emit('tracking:location', payload);
      // Admin tracking by staffId (admin at 192.168.16.114 joins admin:staff:${staffId})
      if (staffIdStr) io.to(`admin:staff:${staffIdStr}`).emit('tracking:location', payload);
    }
    res.status(200).json({ success: true, taskId: task.taskId });
  } catch (error) {
    console.error('[Tasks] Error updating location:', error.message);
    res.status(500).json({ message: error.message });
  }
};

// PATCH /tasks/:id/steps – update step completion (reachedLocation, photoProof, formFilled, otpVerified).
exports.updateSteps = async (req, res) => {
  try {
    const taskId = req.params.id;
    const { reachedLocation, photoProof, formFilled, otpVerified } = req.body;
    const updateData = {};
    if (reachedLocation !== undefined) updateData['progressSteps.reachedLocation'] = !!reachedLocation;
    if (photoProof !== undefined) updateData['progressSteps.photoProof'] = !!photoProof;
    if (formFilled !== undefined) updateData['progressSteps.formFilled'] = !!formFilled;
    if (otpVerified !== undefined) updateData['progressSteps.otpVerified'] = !!otpVerified;
    if (Object.keys(updateData).length === 0) {
      return res.status(400).json({ message: 'At least one step field required' });
    }
    const task = await Task.findById(taskId).populate('assignedTo').populate('customerId');
    if (!task) return res.status(404).json({ message: 'Task not found' });
    const details = await TaskDetails.findOne({ taskId: task._id }).lean();
    const fullDoc = {
      ...(details || {}),
      taskMongoId: task._id,
      progressSteps: {
        ...(details?.progressSteps || {}),
        ...(reachedLocation !== undefined && { reachedLocation: !!reachedLocation }),
        ...(photoProof !== undefined && { photoProof: !!photoProof }),
        ...(formFilled !== undefined && { formFilled: !!formFilled }),
        ...(otpVerified !== undefined && { otpVerified: !!otpVerified }),
      },
    };
    await exports.upsertTaskDetails(fullDoc);
    const merged = await mergeTaskWithDetails(task);
    console.log('[Tasks] Updated steps for task:', task.taskId);
    res.status(200).json(merged);
  } catch (error) {
    console.error('[Tasks] Error updating steps:', error.message);
    res.status(500).json({ message: error.message });
  }
};

// GET /tasks/:id/completion-report – full task completion report with timeline + route from DB.
exports.getCompletionReport = async (req, res) => {
  try {
    const taskId = req.params.id;
    const task = await Task.findById(taskId)
      .populate('assignedTo', 'name')
      .populate('customerId')
      .lean();
    if (!task) {
      return res.status(404).json({ message: 'Task not found' });
    }
    const details = await TaskDetails.findOne({ taskId: task._id }).lean();
    const taskObj = { ...(details || {}), ...task };
    if (details) {
      for (const k of EXTENDED_TASK_KEYS) {
        if (details[k] !== undefined) taskObj[k] = details[k];
      }
    }

    const trackingRecords = await Tracking.find({ taskId: task._id })
      .sort({ timestamp: 1 })
      .lean();

    const persistedTravelMetrics = computeTravelMetricsFromTrackingRecords(
      trackingRecords,
      getTravelMetricsWindow(taskObj, taskObj.arrivalTime || taskObj.arrived)
    );
    if (persistedTravelMetrics) {
      taskObj.tripDurationSeconds = persistedTravelMetrics.tripDurationSeconds;
      taskObj.travelActivityDuration = persistedTravelMetrics.travelActivityDuration;
    }

    const routePoints = trackingRecords
          .filter((r) => r.latitude != null && r.longitude != null)
          .map((r) => ({
            lat: r.latitude,
            lng: r.longitude,
            timestamp: r.timestamp,
            movementType: r.movementType,
            address: r.address || r.fullAddress,
          }));

    const timeline = [];
    const hasRestarts = ((taskObj.tasks_restarted || taskObj.restarted || []).length > 0);

    if (taskObj.startTime && !hasRestarts) {
      timeline.push({
        type: 'start',
        label: 'Start',
        time: taskObj.startTime,
        address: taskObj.sourceLocation?.address || taskObj.sourceLocation?.fullAddress,
        lat: taskObj.sourceLocation?.lat,
        lng: taskObj.sourceLocation?.lng,
        batteryPercent: batteryAtTime(trackingRecords, taskObj.startTime),
      });
    }

    const MOVEMENT_DEBOUNCE_MS = 60 * 1000; // Only show movement change if sustained (next record same type) or ≥1 min since last
    let lastMovementType = null;
    let lastMovementTime = null;
    let hasHadExit = false;
    let hasArrived = false;
    for (let i = 0; i < trackingRecords.length; i++) {
      const tr = trackingRecords[i];
      const ts = tr.timestamp || tr.time;
      if (!ts) continue;
      if (tr.status === 'arrived') {
        hasArrived = true;
        timeline.push({
          type: 'arrived',
          label: 'Arrived',
          time: ts,
          address: tr.fullAddress || tr.address,
          lat: tr.latitude,
          lng: tr.longitude,
          batteryPercent: tr.batteryPercent != null ? Number(tr.batteryPercent) : undefined,
        });
      } else if (tr.exitStatus === 'exited') {
        hasHadExit = true;
        timeline.push({
          type: 'exit',
          label: 'Outage',
          time: tr.exitedAt || ts,
          address: tr.address || tr.fullAddress,
          lat: tr.latitude,
          lng: tr.longitude,
          exitReason: tr.exitReason,
          batteryPercent: tr.batteryPercent != null ? Number(tr.batteryPercent) : undefined,
        });
      } else if (!hasArrived && tr.movementType && tr.movementType !== lastMovementType) {
        const tsMs = new Date(ts).getTime();
        const next = trackingRecords[i + 1];
        const nextHasSameType = next && next.movementType === tr.movementType && next.status !== 'arrived';
        const enoughTimeSinceLast = lastMovementTime == null || (tsMs - lastMovementTime >= MOVEMENT_DEBOUNCE_MS);
        if (nextHasSameType || enoughTimeSinceLast) {
          lastMovementType = tr.movementType;
          lastMovementTime = tsMs;
          let label =
            tr.movementType === 'drive' || tr.movementType === 'driving'
              ? 'Ride'
              : tr.movementType === 'walk' || tr.movementType === 'walking'
                ? 'Walk'
                : tr.movementType === 'stop'
                  ? 'Stop'
                  : tr.movementType;
          let type = 'movement';
          if ((label === 'Start' || tr.movementType === 'start') && hasHadExit) {
            label = 'Resumed';
            type = 'restart';
          }
          timeline.push({
            type,
            label,
            time: ts,
            address: tr.fullAddress || tr.address,
            lat: tr.latitude,
            lng: tr.longitude,
            movementType: tr.movementType,
            batteryPercent: tr.batteryPercent != null ? Number(tr.batteryPercent) : undefined,
          });
        }
      }
    }

    const exits = taskObj.tasks_exit || taskObj.exit || [];
    for (const ex of exits) {
      const loc = ex.exitLocation || ex;
      const exTime = ex.exitedAt || ex.time;
      if (!timeline.some((t) => t.type === 'exit' && new Date(t.time).getTime() === new Date(exTime).getTime())) {
        timeline.push({
          type: 'exit',
          label: 'Outage',
          time: exTime,
          address: loc.address || loc.fullAddress,
          lat: loc.lat,
          lng: loc.lng,
          exitReason: ex.exitReason,
          batteryPercent: batteryAtTime(trackingRecords, exTime),
        });
      }
    }

    const restarts = taskObj.tasks_restarted || taskObj.restarted || [];
    for (const rs of restarts) {
      const loc = rs.restartLocation || rs;
      const rsTime = rs.restartedAt || rs.resumedAt || rs.time;
      timeline.push({
        type: 'restart',
        label: 'Resumed',
        time: rsTime,
        address: loc.address || loc.fullAddress,
        lat: loc.lat,
        lng: loc.lng,
        batteryPercent: batteryAtTime(trackingRecords, rsTime),
      });
    }

    if (taskObj.photoProofUploadedAt) {
      timeline.push({
        type: 'photo',
        label: 'Photo proof uploaded',
        time: taskObj.photoProofUploadedAt,
        address: taskObj.photoProofAddress,
        lat: taskObj.photoProofLat,
        lng: taskObj.photoProofLng,
        batteryPercent: batteryAtTime(trackingRecords, taskObj.photoProofUploadedAt),
      });
    }

    if (taskObj.otpVerifiedAt) {
      timeline.push({
        type: 'otp',
        label: 'OTP verified',
        time: taskObj.otpVerifiedAt,
        address: taskObj.otpVerifiedAddress,
        lat: taskObj.otpVerifiedLat,
        lng: taskObj.otpVerifiedLng,
        batteryPercent: batteryAtTime(trackingRecords, taskObj.otpVerifiedAt),
      });
    }

    if (taskObj.arrivalTime && !timeline.some((t) => t.type === 'arrived')) {
      timeline.push({
        type: 'arrived',
        label: 'Arrived',
        time: taskObj.arrivalTime,
        address: taskObj.arrivedFullAddress,
        lat: taskObj.arrivedLatitude,
        lng: taskObj.arrivedLongitude,
        batteryPercent: batteryAtTime(trackingRecords, taskObj.arrivalTime),
      });
    }

    if (taskObj.completedDate) {
      timeline.push({
        type: 'completed',
        label: 'Completed',
        time: taskObj.completedDate,
        address: taskObj.arrivedFullAddress,
        lat: taskObj.arrivedLatitude,
        lng: taskObj.arrivedLongitude,
        batteryPercent: batteryAtTime(trackingRecords, taskObj.completedDate),
      });
    }

    timeline.sort((a, b) => {
      const ta = a.time ? new Date(a.time).getTime() : 0;
      const tb = b.time ? new Date(b.time).getTime() : 0;
      return ta - tb;
    });

    const formResponses = await FormResponse.find({ taskId: task._id })
      .populate('templateId', 'templateName fields')
      .lean();

    res.status(200).json({
      task: taskObj,
      timeline,
      routePoints,
      formResponses: formResponses || [],
    });
  } catch (error) {
    console.error('[Tasks] getCompletionReport error:', error.message);
    res.status(500).json({ message: error.message });
  }
};

// GET /tasks/:id/tracking-path – full GPS path for admin replay (from trackings collection).
exports.getTrackingPath = async (req, res) => {
  try {
    const taskId = req.params.id;
    const task = await Task.findById(taskId)
      .select('taskId status assignedTo customerId')
      .populate('assignedTo', 'name')
      .populate('customerId', 'address city pincode');
    if (!task) {
      return res.status(404).json({ message: 'Task not found' });
    }
    const trackingRecords = await Tracking.find({ taskId: task._id })
      .sort({ timestamp: 1 })
      .lean();
    const points = trackingRecords
      .filter((r) => r.latitude != null && r.longitude != null)
      .map((r) => ({
        latitude: r.latitude,
        longitude: r.longitude,
        timestamp: r.timestamp,
        batteryPercent: r.batteryPercent,
      }));
    res.status(200).json({
      taskId: task.taskId,
      status: task.status,
      staff: task.assignedTo,
      customer: task.customerId,
      path: points,
    });
  } catch (error) {
    console.error('[Tasks] Error fetching tracking path:', error.message);
    res.status(500).json({ message: error.message });
  }
};

// POST /tasks/:id/photo – upload photo proof to Digital Ocean only (employees/.../documents/tasks-proof).
exports.uploadPhotoProof = async (req, res) => {
  try {
    const taskId = req.params.id;
    const file = req.file;
    const description = req.body?.description?.trim();
    if (!file) {
      return res.status(400).json({ message: 'Photo file required' });
    }
    const task = await Task.findById(taskId).populate('assignedTo').populate('customerId');
    if (!task) return res.status(404).json({ message: 'Task not found' });
    const companyId = getCompanyIdFromTask(task);
    const employeeName = task.assignedTo?.name || 'unknown';
    const buffer = fs.readFileSync(file.path);
    const format = file.mimetype?.includes('png') ? 'png' : 'jpg';

    const doResult = await digitalOceanService.uploadImage(buffer, undefined, {
      req,
      companyId: companyId ? String(companyId) : undefined,
      employeeName,
      category: 'employees',
      subfolder: 'documents/tasks-proof',
      format,
    });
    if (!doResult.success || !doResult.url) {
      if (file.path && fs.existsSync(file.path)) {
        try {
          fs.unlinkSync(file.path);
        } catch (e) {
          /* ignore */
        }
      }
      const errMsg = doResult.error || 'Digital Ocean upload failed';
      return res.status(500).json({
        message:
          `Photo upload failed: ${errMsg}. Configure DIGITAL_OCEAN_ACCESS_KEY, DIGITAL_OCEAN_SECRET_KEY, and bucket (see server logs).`,
      });
    }
    const photoUrl = doResult.url;
    if (file.path && fs.existsSync(file.path)) {
      try { fs.unlinkSync(file.path); } catch (e) { /* ignore */ }
    }
    const { lat, lng, fullAddress } = req.body;
    const details = await TaskDetails.findOne({ taskId: task._id }).lean();
    const fullDoc = {
      ...(details || {}),
      taskMongoId: task._id,
      photoProofUrl: photoUrl,
      photoProofUploadedAt: new Date(),
      progressSteps: {
        ...(details?.progressSteps || {}),
        photoProof: true,
      },
    };
    if (description) fullDoc.photoProofDescription = description;
    if (lat != null) fullDoc.photoProofLat = Number(lat);
    if (lng != null) fullDoc.photoProofLng = Number(lng);
    if (fullAddress) fullDoc.photoProofAddress = String(fullAddress);
    await exports.upsertTaskDetails(fullDoc);
    const merged = await mergeTaskWithDetails(task);
    const finalMerged = await mergeTaskSettings(merged, companyId);
    console.log('[Tasks] Photo proof uploaded for task:', task.taskId);
    res.status(200).json(finalMerged);
  } catch (error) {
    console.error('[Tasks] uploadPhotoProof error:', error.message);
    res.status(500).json({ message: error.message });
  }
};

// POST /tasks/:id/send-otp – generate 4-digit OTP, send via SendPulse/emailService to customer email.
exports.sendOtp = async (req, res) => {
  try {
    const idParam = req.params.id;
    let task = await Task.findById(idParam).populate('customerId');
    if (!task) {
      task = await Task.findOne({ taskId: idParam }).populate('customerId');
    }
    if (!task) {
      return res.status(404).json({ message: 'Task not found' });
    }
    const merged = await mergeTaskWithDetails(task);
    const customer = merged.customerId || task.customerId;
    if (!customer) {
      return res.status(400).json({ message: 'Task has no customer' });
    }
    const email = customer.emailId || customer.email;
    if (!email || !email.trim()) {
      return res.status(400).json({
        message: 'Customer email is required to send OTP. Please add email to customer.',
      });
    }
    const otp = String(Math.floor(1000 + Math.random() * 9000));
    const taskMongoId = task._id.toString();
    const subject = `Your OTP for Task #${task.taskId}`;
    const html = `
      <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto;">
        <h2 style="color: #333;">OTP Verification</h2>
        <p>Hello ${customer.customerName},</p>
        <p>Your 4-digit OTP for task <strong>#${task.taskId}</strong> is:</p>
        <p style="font-size: 28px; font-weight: bold; letter-spacing: 8px; color: #1976d2;">${otp}</p>
        <p>Please share this OTP with the field staff to verify task completion.</p>
        <p style="color: #666; font-size: 12px;">This OTP is valid for 10 minutes. Do not share with anyone else.</p>
      </div>
    `;
    const result = await sendTaskOtpEmail(email.trim(), subject, html);
    if (!result.success) {
      return res.status(500).json({
        message: result.error || 'Failed to send OTP. Set SENDPULSE_CLIENT_ID, SENDPULSE_CLIENT_SECRET, SENDPULSE_FROM_EMAIL in .env',
      });
    }
    const details = await TaskDetails.findOne({ taskId: task._id }).lean();
    const fullDoc = {
      ...(details || {}),
      taskMongoId: task._id,
      otpCode: otp,
      otpSentAt: new Date(),
    };
    await exports.upsertTaskDetails(fullDoc);
    console.log('[Tasks] OTP sent to', email, 'for task:', task.taskId);
    res.status(200).json({
      success: true,
      message: 'OTP sent to customer email',
      email: email.replace(/(.{2})(.*)(@.*)/, '$1***$3'),
    });
  } catch (error) {
    console.error('[Tasks] sendOtp error:', error.message);
    res.status(500).json({ message: error.message });
  }
};

// POST /tasks/:id/verify-otp – verify OTP, set otpVerified true.
exports.verifyOtp = async (req, res) => {
  try {
    const taskId = req.params.id;
    const { otp } = req.body;
    if (!otp || String(otp).length !== 4) {
      return res.status(400).json({ message: 'Valid 4-digit OTP required' });
    }
    const task = await Task.findById(taskId).populate('assignedTo').populate('customerId');
    if (!task) {
      return res.status(404).json({ message: 'Task not found' });
    }
    const details = await TaskDetails.findOne({ taskId: task._id }).lean();
    const storedOtp = details?.otpCode;
    if (!storedOtp) {
      return res.status(400).json({ message: 'No OTP sent for this task. Please send OTP first.' });
    }
    const otpStr = String(otp).trim();
    if (otpStr !== storedOtp) {
      return res.status(400).json({ message: 'Invalid OTP. Please try again.' });
    }
    const { lat, lng, fullAddress } = req.body;
    const fullDoc = {
      ...(details || {}),
      taskMongoId: task._id,
      progressSteps: {
        ...(details?.progressSteps || {}),
        otpVerified: true,
      },
      otpVerifiedAt: new Date(),
    };
    if (lat != null) fullDoc.otpVerifiedLat = Number(lat);
    if (lng != null) fullDoc.otpVerifiedLng = Number(lng);
    if (fullAddress) fullDoc.otpVerifiedAddress = String(fullAddress);
    await exports.upsertTaskDetails(fullDoc);
    const merged = await mergeTaskWithDetails(task);
    const companyId = getCompanyIdFromTask(task);
    const finalMerged = await mergeTaskSettings(merged, companyId);
    console.log('[Tasks] OTP verified for task:', task.taskId);
    res.status(200).json(finalMerged);
  } catch (error) {
    console.error('[Tasks] verifyOtp error:', error.message);
    res.status(500).json({ message: error.message });
  }
};

// POST /tasks/:id/end – set status completed or waiting_for_approval per settings.
exports.endTask = async (req, res) => {
  try {
    const taskId = req.params.id;
    const staffId = req.staff?._id;
    const task = await Task.findById(taskId).populate('assignedTo').populate('customerId');
    if (!task) return res.status(404).json({ message: 'Task not found' });
    const statusLower = String(task.status || '').toLowerCase().replace(/\s+/g, '');
    const canComplete = ['arrived', 'holdonarrival', 'reopenedonarrival'].includes(statusLower);
    const alreadyDone = ['completed', 'waiting_for_approval'].includes(statusLower);
    if (alreadyDone) {
      // Idempotent: already completed, return success
      const companyId = getCompanyIdFromTask(task);
      const merged = await mergeTaskWithDetails(task);
      const finalMerged = await mergeTaskSettings(merged, companyId);
      return res.status(200).json(finalMerged);
    }
    if (!canComplete) {
      return res.status(400).json({
        message: `Invalid status for complete: task must be arrived, holdOnArrival, or reopenedOnArrival, got ${task.status}`,
      });
    }
    const companyId = getCompanyIdFromTask(task);
    let requireApprovalOnComplete = false;
    try {
      if (companyId) {
        const bid = companyId._id ?? companyId;
        const settings = await TaskSettings.findOne({
          $or: [{ companyId: bid }, { businessId: bid }],
        }).lean();
        requireApprovalOnComplete = settings?.settings?.requireApprovalOnComplete === true;
      }
    } catch (err) {
      console.warn('[Tasks] endTask TaskSettings:', err.message);
    }
    const newStatus = requireApprovalOnComplete ? 'waiting_for_approval' : 'completed';
    const completedAt = parseTimestamp(new Date());
    await Task.findByIdAndUpdate(taskId, {
      $set: { status: newStatus },
      $unset: exports.buildUnsetExtended(),
    }, { runValidators: false });
    const details = await TaskDetails.findOne({ taskId: task._id }).lean();
    const fullDoc = {
      ...(details || {}),
      taskMongoId: task._id,
      status: newStatus,
      completedDate: completedAt,
      completedBy: staffId,
    };
    const persistedTravelMetrics = await computePersistedTravelMetrics(
      task._id,
      details || task,
      details?.arrivalTime || details?.arrived || task.arrivalTime || completedAt
    );
    if (persistedTravelMetrics) {
      fullDoc.tripDurationSeconds = persistedTravelMetrics.tripDurationSeconds;
      fullDoc.travelActivityDuration = persistedTravelMetrics.travelActivityDuration;
    }
    const travelActivityDuration = normalizeTravelActivityDuration(
      req.body?.travelActivityDuration
    );
    if (travelActivityDuration && !persistedTravelMetrics) {
      fullDoc.travelActivityDuration = travelActivityDuration;
    }
    await exports.upsertTaskDetails(fullDoc);
    const updatedTask = await Task.findById(taskId).populate('assignedTo').populate('customerId');
    const merged = await mergeTaskWithDetails(updatedTask);
    const finalMerged = await mergeTaskSettings(merged, companyId);
    console.log('[Tasks] Task ended:', task.taskId, 'status:', newStatus);
    res.status(200).json(finalMerged);
  } catch (error) {
    console.error('[Tasks] Error ending task:', error.message);
    res.status(500).json({ message: error.message });
  }
};