const mongoose = require('../config/mongoose');

const productivityScoreSchema = new mongoose.Schema({
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    employeeID: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    activityLogId: { type: mongoose.Schema.Types.ObjectId, ref: 'ActivityLog', required: true },
    timestamp: { type: Date, required: true },
    score: { type: Number, default: 0 },
    keystrokes: { type: Number },
    mouseClicks: { type: Number },
    scrollCount: { type: Number },
    idleSeconds: { type: Number, default: 0 }
}, { timestamps: true, collection: 'monitoringscores' });

productivityScoreSchema.index({ tenantId: 1, employeeID: 1, timestamp: -1 });

module.exports = mongoose.model('ProductivityScore', productivityScoreSchema);
