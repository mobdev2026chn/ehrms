/**
 * Monitoring status enum - must match status values in monitoringdevices collection.
 * Used by Staff.monitoringStatus and Device.status to keep them in sync.
 */
const MONITORING_STATUSES = Object.freeze([
    'active',
    'inactive',
    'logout',
    'exited',
    'break',
    'meeting',
    'pause',
    'offline'
]);

module.exports = MONITORING_STATUSES;
