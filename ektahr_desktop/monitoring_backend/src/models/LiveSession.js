const mongoose = require('../config/mongoose');

const liveSessionSchema = new mongoose.Schema({
    liveSessionId: { type: String, required: true, unique: true },
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    deviceId: { type: String, required: true },
    viewerUserId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    viewerName: { type: String },
    startedAt: { type: Date, default: Date.now },
    endedAt: { type: Date },
    durationSeconds: { type: Number, default: 0 },
    status: {
        type: String,
        enum: ['connecting', 'live', 'reconnecting', 'disconnected', 'ended', 'failed'],
        default: 'connecting'
    },
    quality: { type: String, enum: ['low', 'medium', 'high'], default: 'high' },
    fps: { type: Number, default: 0 },
    resolution: { type: String, default: '' },
    disconnectReason: { type: String, default: '' }
}, { timestamps: true, collection: 'monitoringlivesessions' });

liveSessionSchema.index({ tenantId: 1, employeeId: 1, startedAt: -1 });
liveSessionSchema.index({ deviceId: 1, status: 1 });

module.exports = mongoose.model('LiveSession', liveSessionSchema);
