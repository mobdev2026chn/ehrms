const mongoose = require('../config/mongoose');

const breakLocationSchema = new mongoose.Schema({
    latitude: { type: Number, default: null },
    longitude: { type: Number, default: null },
    address: { type: String, default: '' },
    area: { type: String, default: '' },
    city: { type: String, default: '' },
    pincode: { type: String, default: '' }
}, { _id: false });

const breakSchema = new mongoose.Schema({
    employeeID: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    deviceId: { type: String, required: true },
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    startTime: { type: Date, required: true },
    endTime: { type: Date, default: null },
    totalSeconds: { type: Number, default: null },
    breakMin: { type: Number, default: 0 },
    breakCount: { type: Number, default: 0 },
    breakFineMins: { type: Number, default: 0 },
    breakFineAmount: { type: Number, default: 0 },
    source: { type: String, default: '' },  // "software" | "web" | "app"
    breakStartSelfie: { type: String, default: '' },
    breakEndSelfie: { type: String, default: '' },
    breakStartLocation: { type: breakLocationSchema, default: () => ({}) },
    breakEndLocation: { type: breakLocationSchema, default: () => ({}) }
}, { timestamps: true, collection: 'break' });

breakSchema.index({ tenantId: 1, employeeID: 1, startTime: -1 });
breakSchema.index({ deviceId: 1, startTime: -1 });

module.exports = mongoose.model('Break', breakSchema);
