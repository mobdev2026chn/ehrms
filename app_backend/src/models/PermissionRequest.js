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
    // Planned out/in window for a `both` (custom-time) permission, stored as
    // "HH:mm" strings. Optional — only set when the employee picks a window.
    fromTime: { type: String, trim: true },
    toTime: { type: String, trim: true },
    // Real stamps recorded when the employee taps Permission Out / Permission In
    // on the dashboard. actualMinutes is the measured out→in duration; any
    // overrunMinutes beyond requestedMinutes is fined for that day.
    actualOutAt: { type: Date },
    actualInAt: { type: Date },
    actualMinutes: { type: Number, default: 0, min: 0 },
    overrunMinutes: { type: Number, default: 0, min: 0 },
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
