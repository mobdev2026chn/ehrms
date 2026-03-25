const mongoose = require('mongoose');

const attendanceLogSchema = new mongoose.Schema(
  {
    attendanceId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Attendance',
      required: true,
      index: true
    },
    action: {
      type: String,
      enum: ['PUNCH_IN', 'PUNCH_OUT', 'BREAK_START', 'BREAK_END', 'CREATED', 'UPDATED', 'APPROVED', 'REJECTED', 'STATUS_CHANGED', 'FINE_CALCULATED', 'FINE_ADJUSTED', 'LEAVE_MARKED', 'NOTES_ADDED'],
      required: true
    },
    performedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Staff',
      required: true
    },
    // performedBy = employee ID (staff who did check-in/check-out)
    performedByName: String,
    performedByEmail: String,
    oldValue: mongoose.Schema.Types.Mixed,
    newValue: mongoose.Schema.Types.Mixed,
    changes: [{
      field: String,
      oldValue: mongoose.Schema.Types.Mixed,
      newValue: mongoose.Schema.Types.Mixed
    }],
    userAgent: String,
    notes: String,
    selfieUrl: String,
    punchInDateTime: Date,
    punchOutDateTime: Date,
    punchInAddress: String,
    punchOutAddress: String,
    breakStartDateTime: Date,
    breakEndDateTime: Date,
    totalBreakSeconds: Number,
    breakStartAddress: String,
    breakEndAddress: String,
    breakStartLocation: mongoose.Schema.Types.Mixed,
    breakEndLocation: mongoose.Schema.Types.Mixed,
    timestamp: {
      type: Date,
      default: Date.now
    }
  },
  { timestamps: true }
);

attendanceLogSchema.index({ attendanceId: 1, timestamp: -1 });
attendanceLogSchema.index({ performedBy: 1, timestamp: -1 });
attendanceLogSchema.index({ action: 1, timestamp: -1 });

module.exports = mongoose.model('AttendanceLog', attendanceLogSchema);
