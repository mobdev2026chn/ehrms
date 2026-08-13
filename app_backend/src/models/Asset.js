const mongoose = require('mongoose');

const assetSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true,
        trim: true
    },
    type: {
        type: String,
        required: true
    },
    assetCategory: {
        type: String
    },
    serialNumber: {
        type: String,
        sparse: true
    },
    assetTypeId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'AssetType'
    },
    status: {
        type: String,
        enum: ['Working', 'Under Maintenance', 'Damaged', 'Retired'],
        default: 'Working'
    },
    location: {
        type: String,
        required: true
    },
    assignedTo: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Staff'
    },
    purchaseDate: Date,
    purchasePrice: Number,
    warrantyExpiry: Date,
    assetPhoto: String,
    image: String, // Alias for assetPhoto
    notes: String,
    businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Company',
        required: true
    },
    branchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Branch',
        required: true
    }
}, {
    timestamps: true
});

assetSchema.index({ type: 1 });
assetSchema.index({ status: 1 });
assetSchema.index({ assignedTo: 1 });
assetSchema.index({ businessId: 1 });
assetSchema.index({ branchId: 1 });

module.exports = mongoose.model('Asset', assetSchema);
