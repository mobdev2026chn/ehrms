const mongoose = require('mongoose');

const assetTypeSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true,
        trim: true
    },
    description: String,
    businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Company'
    }
}, {
    timestamps: true
});

assetTypeSchema.index({ businessId: 1 });

module.exports = mongoose.model('AssetType', assetTypeSchema);
