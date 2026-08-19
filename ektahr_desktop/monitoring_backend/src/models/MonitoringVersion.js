const mongoose = require('../config/mongoose');

const platformSchema = new mongoose.Schema({
    name: { type: String, required: true },
    downloadUrl: { type: String, required: true }
}, { _id: false });

const monitoringVersionSchema = new mongoose.Schema({
    version: { type: String, required: true },
    platforms: [platformSchema],
    description: { type: String },
    releaseNotes: [{ type: String }],
    forceUpdate: { type: Boolean, default: false },
    status: { type: String, enum: ['active', 'deprecated'], default: 'active' }
}, { timestamps: true, collection: 'monitoringversions' });

monitoringVersionSchema.index({ status: 1, createdAt: -1 });
monitoringVersionSchema.index({ version: 1 });

module.exports = mongoose.model('MonitoringVersion', monitoringVersionSchema);
