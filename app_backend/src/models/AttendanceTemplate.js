const mongoose = require('mongoose');

const attendanceTemplateSchema = new mongoose.Schema({
    name: { type: String, required: true },
    description: { type: String },
    isActive: { type: Boolean, default: true },

    // Attendance Requirements
    requireGeolocation: { type: Boolean, default: true },
    requireSelfie: { type: Boolean, default: true },

    // Attendance Rules
    allowAttendanceOnHolidays: { type: Boolean, default: false },
    allowAttendanceOnWeeklyOff: { type: Boolean, default: false },
    allowLateEntry: { type: Boolean, default: true },
    allowEarlyExit: { type: Boolean, default: true },
    allowOvertime: { type: Boolean, default: true },

    // Shift Settings (Simplified for this task)
    shiftStartTime: { type: String, default: "09:30" }, // HH:mm
    shiftEndTime: { type: String, default: "18:30" }, // HH:mm
    gracePeriodMinutes: { type: Number, default: 15 },

    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' }
}, { timestamps: true });

module.exports = mongoose.model('AttendanceTemplate', attendanceTemplateSchema);
