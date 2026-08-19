const mongoose = require('../config/mongoose');

const screenshotSchema = new mongoose.Schema({
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    employeeID: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    deviceId: { type: String, required: true },
    timestamp: { type: Date, required: true },
    cloudinaryPublicId: { type: String },
    cloudinaryUrl: { type: String },
    secureUrl: { type: String },
    width: { type: Number },
    height: { type: Number },
    size: { type: Number }
}, { timestamps: true, collection: 'monitoringscreenshots' });

screenshotSchema.index({ tenantId: 1, employeeID: 1, timestamp: -1 });
screenshotSchema.index({ deviceId: 1, timestamp: -1 });

module.exports = mongoose.model('Screenshot', screenshotSchema);
