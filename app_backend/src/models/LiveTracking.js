const mongoose = require('mongoose');

/**
 * LiveTracking Model – Dedicated collection for high-frequency live GPS breadcrumbs
 * Supports both internal and external task tracking, live location monitoring, and travel trails.
 * Includes a 2-month (60-day = 5,184,000 seconds) TTL index on createdAt for automatic data pruning.
 */
const liveTrackingSchema = new mongoose.Schema(
  {
    // Tenant & Staff Identifiers
    adminId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Admin',
      index: true,
    },
    staffId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Staff',
      required: true,
      index: true,
    },
    staffName: {
      type: String,
      trim: true,
    },

    // Task Association (optional: present when on an active task / journey)
    taskId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Task',
      index: true,
    },
    taskIdStr: {
      type: String, // e.g. "TSK-2026-001" or "TSK-FJ-..."
      trim: true,
      index: true,
    },
    taskType: {
      type: String,
      enum: ['Internal', 'External'],
    },

    // Precise GPS Location
    latitude: {
      type: Number,
      required: true,
    },
    longitude: {
      type: Number,
      required: true,
    },
    accuracy: {
      type: Number, // horizontal accuracy in meters
    },
    speed: {
      type: Number, // speed in m/s or km/h
    },
    heading: {
      type: Number, // bearing in degrees (0 - 360)
    },
    altitude: {
      type: Number, // altitude in meters
    },
    batteryPercent: {
      type: Number, // device battery percentage
    },

    // Movement Classification
    movementType: {
      type: String,
      enum: ['driving', 'walking', 'stop', 'moving', 'stationary', 'unknown'],
      default: 'stop',
    },

    // Reverse-Geocoded Address
    address: {
      type: String,
      trim: true,
    },
    fullAddress: {
      type: String,
      trim: true,
    },
    city: {
      type: String,
      trim: true,
    },
    area: {
      type: String,
      trim: true,
    },
    pincode: {
      type: String,
      trim: true,
    },
    state: {
      type: String,
      trim: true,
    },
    country: {
      type: String,
      trim: true,
    },

    // Destination Details (if travelling towards a task or branch location)
    destinationLat: {
      type: Number,
    },
    destinationLng: {
      type: Number,
    },
    destinationAddress: {
      type: String,
      trim: true,
    },
    distanceRemainingKm: {
      type: Number,
    },

    // Status Tracking
    status: {
      type: String,
      enum: [
        'in_progress',
        'arrived',
        'exited',
        'active',
        'inactive',
        'checked_in',
        'checked_out',
        'offline',
      ],
      default: 'active',
    },
    appStatus: {
      type: String,
      enum: ['active', 'app_background', 'app_closed', 'inactive', 'offline'],
      default: 'active',
    },
    presenceStatus: {
      type: String,
      enum: ['in_office', 'task', 'out_of_office'],
    },
    exitReason: {
      type: String,
      trim: true,
    },
    exitedAt: {
      type: Date,
    },
    isLive: {
      type: Boolean,
      default: true,
    },

    // Timestamp
    timestamp: {
      type: Date,
      default: Date.now,
      index: true,
    },
  },
  {
    timestamps: true,
    collection: 'livetrackings', // Dedicated MongoDB collection name
  }
);

// ── Compound Indexes for High-Performance Queries ────────────────────────────
liveTrackingSchema.index({ adminId: 1, staffId: 1, timestamp: -1 });
liveTrackingSchema.index({ staffId: 1, timestamp: -1 });
liveTrackingSchema.index({ taskId: 1, timestamp: -1 });
liveTrackingSchema.index({ adminId: 1, timestamp: -1 });

// ── TTL Index: 2 Months (60 days = 5,184,000 seconds) ────────────────────────
// MongoDB will automatically delete documents once createdAt is older than 60 days.
liveTrackingSchema.index(
  { createdAt: 1 },
  { expireAfterSeconds: 60 * 24 * 60 * 60 } // 5,184,000 seconds
);

module.exports = mongoose.model('LiveTracking', liveTrackingSchema);
