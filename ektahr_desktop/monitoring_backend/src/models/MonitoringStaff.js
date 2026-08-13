const mongoose = require('../config/mongoose');

const monitoringStaffSchema = new mongoose.Schema({
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    enabled: { type: Boolean, default: true }
}, { timestamps: true, collection: 'monitoringstaffs' });

monitoringStaffSchema.index({ businessId: 1, employeeId: 1 }, { unique: true });
monitoringStaffSchema.index({ businessId: 1 });

module.exports = mongoose.model('MonitoringStaff', monitoringStaffSchema);
