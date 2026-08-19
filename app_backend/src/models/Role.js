// Backend/src/models/Role.js
const mongoose = require('mongoose');

const roleSchema = new mongoose.Schema({
    name: { type: String, required: true },
    companyId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    description: { type: String },
    permissions: [{ type: String }], // Array of permission strings
    isSystemRole: { type: Boolean, default: false },
    isActive: { type: Boolean, default: true },
    branch: { type: String, default: "COMMON" },
    displayOrder: { type: Number, default: 0 },
    hierarchyLevel: { type: Number, default: 0 },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }
}, { timestamps: true });

module.exports = mongoose.model('Role', roleSchema);