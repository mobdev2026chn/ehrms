const mongoose = require('../config/mongoose');
const MONITORING_STATUSES = require('../constants/monitoringStatus');

const deviceSchema = new mongoose.Schema({
    deviceId: { type: String, required: true, unique: true },
    employeeID: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    machineName: { type: String },
    osVersion: { type: String },
    agentVersion: { type: String },
    systemIp: { type: String },
    systemModel: { type: String },
    lastSeenAt: { type: Date, default: Date.now },
    isActive: { type: Boolean, default: true },
    status: { type: String, enum: MONITORING_STATUSES, default: 'active' },
    consentAt: { type: Date },
    autoupdate: { type: Boolean, default: false }
}, { timestamps: true, collection: 'monitoringdevices' });

deviceSchema.index({ tenantId: 1, deviceId: 1 });
deviceSchema.index({ employeeID: 1, tenantId: 1 });
deviceSchema.index({ lastSeenAt: 1 });
deviceSchema.index({ status: 1 });

module.exports = mongoose.model('Device', deviceSchema);
