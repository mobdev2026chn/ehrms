const mongoose = require('mongoose');

/**
 * PresenceTracking – staff location tracking based on attendance presence.
 * Used when staff is checked in (punchIn exists, punchOut does not) and not on leave.
 * Separate from task Tracking – task flow uses Tracking collection with taskId.
 * presenceStatus: 'in_office' | 'task' | 'out_of_office'
 * (task is handled by tasks module; this collection uses presence-style statuses)
 */
const presenceTrackingSchema = new mongoose.Schema(
  {
    staffId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    staffName: { type: String },
    latitude: { type: Number, required: true },
    longitude: { type: Number, required: true },
    timestamp: { type: Date, default: Date.now },
    accuracy: { type: Number },
    batteryPercent: { type: Number },
    movementType: { type: String },
    address: { type: String },
    fullAddress: { type: String },
    city: { type: String },
    area: { type: String },
    pincode: { type: String },
    presenceStatus: {
      type: String,
      enum: ['in_office', 'task', 'out_of_office'],
      required: true,
    },
  },
  { timestamps: true }
);

presenceTrackingSchema.index({ staffId: 1, timestamp: -1 });
presenceTrackingSchema.index({ timestamp: -1 });

module.exports = mongoose.model('PresenceTracking', presenceTrackingSchema);
