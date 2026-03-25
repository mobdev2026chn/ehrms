/**
 * TaskDetails – full task details (no location history; that's in trackings collection).
 * taskId here = tasks._id (ObjectId) – lookup key; NOT the same as tasks.taskId (TASK-XXX).
 * Upserted whenever a task is created/updated/arrived/verified/photo/end.
 */
const mongoose = require('mongoose');

const taskDetailsSchema = new mongoose.Schema({
  taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task', required: true, unique: true }, // = tasks._id
  taskTitle: { type: String, required: true },
  description: { type: String, default: '' },
  status: { type: String, default: 'assigned' },
  assignedTo: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
  customerId: { type: mongoose.Schema.Types.ObjectId, ref: 'Customer' },
  expectedCompletionDate: { type: Date },
  completedDate: { type: Date },
  startTime: { type: Date },
  started: { type: Date },
  startLocation: { lat: { type: Number }, lng: { type: Number } },
  sourceLocation: {
    lat: { type: Number },
    lng: { type: Number },
    address: { type: String },
    fullAddress: { type: String },
    pincode: { type: String },
  },
  destinationLocation: {
    lat: { type: Number },
    lng: { type: Number },
    address: { type: String },
    fullAddress: { type: String },
    pincode: { type: String },
  },
  destinationChanged: { type: Boolean, default: false },
  destinations: { type: Array, default: [] },
  tripDistanceKm: { type: Number },
  tripDurationSeconds: { type: Number },
  arrivalTime: { type: Date },
  arrived: { type: Date },
  arrivedLatitude: { type: Number },
  arrivedLongitude: { type: Number },
  arrivedFullAddress: { type: String },
  arrivedPincode: { type: String },
  arrivedDate: { type: Date },
  arrivedTime: { type: String },
  sourceFullAddress: { type: String },
  photoProofUrl: { type: String },
  photoProofUploadedAt: { type: Date },
  photoProofDescription: { type: String },
  photoProofLat: { type: Number },
  photoProofLng: { type: Number },
  photoProofAddress: { type: String },
  otpCode: { type: String },
  otpSentAt: { type: Date },
  otpVerifiedAt: { type: Date },
  otpVerifiedLat: { type: Number },
  otpVerifiedLng: { type: Number },
  otpVerifiedAddress: { type: String },
  progressSteps: {
    reachedLocation: { type: Boolean, default: false },
    photoProof: { type: Boolean, default: false },
    formFilled: { type: Boolean, default: false },
    otpVerified: { type: Boolean, default: false },
  },
  arrivedSelfieCheckinUrl: { type: String },
  arrivedSelfieCheckoutUrl: { type: String },
  arrivedSelfieCheckinTime: { type: Date },
  arrivedeSelfieCheckoutTime: { type: Date },
  // isOtpRequired, isGeoFenceRequired, isPhotoRequired, isFormRequired come from TaskSettings only – not stored here
  exit: { type: Array, default: [] },
  restarted: { type: Array, default: [] },
  approvedAt: { type: Date },
  approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
  rejectedAt: { type: Date },
  rejectedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
  completedAt: { type: Date },
  completedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
  rideStartedAt: { type: Date },
  rideStartLocation: {
    lat: { type: Number },
    lng: { type: Number },
    address: { type: String },
    pincode: { type: String },
    recordedAt: { type: Date },
  },
  arrivalLocation: {
    lat: { type: Number },
    lng: { type: Number },
    address: { type: String },
    pincode: { type: String },
    recordedAt: { type: Date },
  },
  // Per-segment ride distance & duration. segment: travel_started | travel_resumed; endType: travel_exited | arrived
  taskTravelDuration: { type: Array, default: [] }, // [{ segment, endType, durationSeconds, endTime }]
  taskTravelDistance: { type: Array, default: [] }, // [{ segment, endType, distanceKm, endTime }]
  travelActivityDuration: {
    driveDuration: { type: Number, default: 0 },
    walkDuration: { type: Number, default: 0 },
    stopDuration: { type: Number, default: 0 },
  },
}, { timestamps: true, strict: false });

module.exports = mongoose.model('TaskDetails', taskDetailsSchema);
