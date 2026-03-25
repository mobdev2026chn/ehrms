const mongoose = require('mongoose');

/**
 * Tracking collection – stores every GPS point (every 15 sec) from mobile app.
 * taskId = tasks._id (ObjectId) – same as tasks collection ObjectId.
 * Admin fetches this data for live tracking view and history.
 */
const trackingSchema = new mongoose.Schema({
  taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task' }, // = tasks._id; optional for presence-only
  staffId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
  staffName: { type: String },
  latitude: { type: Number, required: true },
  longitude: { type: Number, required: true },
  timestamp: { type: Date, default: Date.now },
  batteryPercent: { type: Number },
  movementType: { type: String }, // driving | walking | stop
  accuracy: { type: Number }, // horizontal accuracy (meters) from device GPS
  destinationLat: { type: Number },
  destinationLng: { type: Number },
  address: { type: String }, // Reverse-geocoded from lat/lng
  fullAddress: { type: String },
  city: { type: String },
  area: { type: String },
  pincode: { type: String },
  // Exit ride
  exitStatus: { type: String }, // "exited"
  // Arrived / app session
  status: {
    type: String,
    enum: ['arrived', 'app_background', 'app_closed', 'in_progress', 'active', 'inactive', 'checked_in', 'checked_out'],
  },
  appStatus: {
    type: String,
    enum: ['app_closed', 'app_background', 'active', 'inactive', 'offline'],
  },
  time: { type: Date },
  exitReason: { type: String },
  exitedAt: { type: Date },
  presenceStatus: { type: String, enum: ['in_office', 'task', 'out_of_office'] }, // based on task status + branch geofence
}, { timestamps: true });

trackingSchema.index({ staffId: 1, timestamp: -1 });
trackingSchema.index({ taskId: 1, timestamp: -1 });
trackingSchema.index({ timestamp: -1 });

module.exports = mongoose.model('Tracking', trackingSchema);
