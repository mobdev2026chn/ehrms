const mongoose = require('mongoose');

const branchSchema = new mongoose.Schema({
    branchName: { type: String, required: true },
    branchCode: { type: String, required: true, unique: true },
    isHeadOffice: { type: Boolean, default: false },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    email: { type: String },
    contactNumber: { type: String },
    countryCode: { type: String },
    address: {
        street: String,
        city: String,
        state: String,
        zip: String,
        country: String
    },
    status: { type: String, enum: ['ACTIVE', 'INACTIVE'], default: 'ACTIVE' },
    logo: { type: String },
    geofence: {
        enabled: { type: Boolean, default: false },
        latitude: { type: Number },
        longitude: { type: Number },
        radius: { type: Number, default: 100 },
        // Multiple sub-geofence circles for this branch.
        // Example: geofence.locations[] each with its own latitude/longitude/radius.
        locations: [
            {
                latitude: { type: Number },
                longitude: { type: Number },
                radius: { type: Number, default: 50 },
                label: { type: String },
            }
        ]
    },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }
}, { timestamps: true });

module.exports = mongoose.model('Branch', branchSchema);
