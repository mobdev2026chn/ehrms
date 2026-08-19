/**
 * Desktop monitoring agent: store activity snapshots and update staff monitoring status.
 */
const ActivityLog = require('../models/ActivityLog');
const Staff = require('../models/Staff');
const MONITORING_STATUSES = require('../constants/monitoringStatus');

/**
 * POST /api/monitoring/activity
 * Body: { deviceId, timestamp, keystrokes, mouseClicks, scrollCount, activeWindow?, idleSeconds }
 * Staff/tenant from JWT (req.staff).
 */
const storeActivity = async (req, res) => {
  try {
    const staff = req.staff;
    if (!staff || !staff._id) {
      return res.status(401).json({ success: false, message: 'Staff not found' });
    }
    const tenantId = staff.businessId || req.companyId;
    if (!tenantId) {
      return res.status(400).json({ success: false, message: 'Tenant/company not found for staff' });
    }

    const {
      deviceId,
      timestamp,
      keystrokes = 0,
      mouseClicks = 0,
      scrollCount = 0,
      activeWindow,
      idleSeconds = 0
    } = req.body;

    if (!deviceId) {
      return res.status(400).json({ success: false, message: 'deviceId is required' });
    }

    const ts = timestamp ? new Date(timestamp) : new Date();
    if (Number.isNaN(ts.getTime())) {
      return res.status(400).json({ success: false, message: 'Invalid timestamp' });
    }

    const activeWindowNormalized = activeWindow
      ? {
          processName: activeWindow.processName ?? null,
          appName: activeWindow.appName ?? null,
          windowTitle: activeWindow.windowTitle ?? null,
          durationSeconds: typeof activeWindow.durationSeconds === 'number' ? activeWindow.durationSeconds : 0
        }
      : undefined;

    const log = await ActivityLog.create({
      tenantId,
      deviceId,
      employeeID: staff._id,
      timestamp: ts,
      keystrokes: Number(keystrokes) || 0,
      mouseClicks: Number(mouseClicks) || 0,
      scrollCount: Number(scrollCount) || 0,
      activeWindow: activeWindowNormalized,
      idleSeconds: Number(idleSeconds) || 0
    });

    return res.status(201).json({
      success: true,
      id: log._id,
      timestamp: log.timestamp
    });
  } catch (error) {
    console.error('[Monitoring] storeActivity error:', error.message);
    return res.status(500).json({
      success: false,
      message: error.message || 'Failed to store activity'
    });
  }
};

/**
 * POST /api/monitoring/status
 * Body: { status: 'active' | 'inactive' | 'logout' | 'exited' | 'break' | 'meeting' | 'pause' | 'offline' }
 * Called by desktop agent on login / logout / exit / break / meeting / pause.
 */
const setMonitoringStatus = async (req, res) => {
  try {
    const staff = req.staff;
    if (!staff || !staff._id) {
      return res.status(401).json({ success: false, message: 'Staff not found' });
    }

    const { status } = req.body;
    if (!status || !MONITORING_STATUSES.includes(status)) {
      return res.status(400).json({
        success: false,
        message: 'status must be one of: ' + MONITORING_STATUSES.join(', ')
      });
    }

    await Staff.findByIdAndUpdate(staff._id, { monitoringStatus: status });
    return res.status(200).json({ success: true, status });
  } catch (error) {
    console.error('[Monitoring] setMonitoringStatus error:', error.message);
    return res.status(500).json({
      success: false,
      message: error.message || 'Failed to update status'
    });
  }
};

module.exports = {
  storeActivity,
  setMonitoringStatus
};
