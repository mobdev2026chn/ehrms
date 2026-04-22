const mongoose = require('mongoose');

const permissionRequestSchema = new mongoose.Schema(
  {
    employeeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Staff',
      required: true,
    },
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      required: true,
    },
    date: { type: Date, required: true },
    type: {
      type: String,
      enum: ['lateArrival', 'earlyExit', 'both'],
      default: 'both',
      required: true,
    },
    requestedMinutes: { type: Number, required: true, min: 1 },
    reason: { type: String, required: true, trim: true },
    status: {
      type: String,
      enum: ['Pending', 'Approved', 'Rejected', 'Cancelled'],
      default: 'Pending',
    },
    approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    approvedAt: Date,
    approvalReason: String,
    rejectedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    rejectedAt: Date,
    rejectionReason: String,
  },
  { timestamps: true }
);

permissionRequestSchema.index({ businessId: 1, date: 1 });
permissionRequestSchema.index({ employeeId: 1, date: 1 });
permissionRequestSchema.index({ status: 1 });

module.exports = mongoose.model('PermissionRequest', permissionRequestSchema);
