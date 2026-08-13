const mongoose = require('../config/mongoose');

const monitoringPauseSchema = new mongoose.Schema({
    employeeID: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    deviceId: { type: String, required: true },
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    startTime: { type: Date, required: true },
    endTime: { type: Date, default: null },
    totalSeconds: { type: Number, default: null },
    source: { type: String, default: '' }  // "software" | "web" | "app"
}, { timestamps: true, collection: 'monitoring_pause' });

monitoringPauseSchema.index({ tenantId: 1, employeeID: 1, startTime: -1 });
monitoringPauseSchema.index({ deviceId: 1, startTime: -1 });

module.exports = mongoose.model('MonitoringPause', monitoringPauseSchema);
