const mongoose = require('mongoose');

const attendanceSchema = new mongoose.Schema(
  {
    employeeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Staff',
      required: true
    },
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Staff',
      default: null
    },
    date: {
      type: Date,
      required: true
    },
    punchIn: Date,
    punchOut: Date,
    status: {
      type: String,
      enum: ['Present', 'Absent', 'Half Day', 'On Leave', 'Not Marked', 'Pending', 'Approved', 'Rejected'],
      default: 'Not Marked'
    },
    leaveType: {
      type: String,
      enum: ['Sick Leave', 'Casual Leave', 'Earned Leave', 'Unpaid Leave', 'Half Day', 'Maternity Leave', 'Paternity Leave', 'Other Leave', 'Paid Holiday', 'Comp Off', 'Week Off', null],
      default: null
    },
    session: { type: String, enum: ['1', '2', null], default: null },
    halfDaySession: {
      type: String,
      enum: ['First Half Day', 'Second Half Day', null],
      default: null
    },
    approvedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User'
    },
    approvedAt: Date,
    remarks: String,
    workHours: Number,
    /** Eligible overtime minutes; standard shifts: past shift end minus otBuffer; open shifts: full minutes over required daily hours. */
    overtime: Number,
    /** Open shift only: sum of full buffer blocks covered by extra time, floor(extra/buffer)*buffer (tracking only; OT is not reduced). */
    bufferTime: { type: Number, default: 0 },
    /** Overtime pay in base currency when OT minutes >= shift otBufferMinutes and payroll fine/OT formula applies. */
    overtimeAmount: { type: Number, default: 0 },
    /**
     * Canonical overtime policy notice for the day (exact tooltip wording):
     *  - "Overtime is disabled for you."        → buffer configured but staff not allowed
     *  - "Overtime is not configured. Contact HR." → shift has no overtime buffer
     *  - "" (empty)                              → overtime is eligible (no notice)
     */
    overtimeNotice: { type: String, default: '' },
    /** Total fine duration in MINUTES (late + early). Display as hours by dividing by 60. */
    fineHours: Number,
    lateMinutes: Number,
    earlyMinutes: Number,
    permissionLateMinutes: { type: Number, default: 0 },
    permissionEarlyMinutes: { type: Number, default: 0 },
    permissionApprovedMinutes: { type: Number, default: 0 },
    permissionConsumedMinutes: { type: Number, default: 0 },
    permissionRemainingMinutes: { type: Number, default: 0 },
    /** Permission used beyond the shift's per-day allowance (exceed minutes), and the fine charged on it. */
    permissionFineMinutes: { type: Number, default: 0 },
    permissionFineAmount: { type: Number, default: 0 },
    /** Minutes a custom-time (`both`) permission's actual out→in exceeded the requested window, and the fine charged on them. Folded into fineAmount. */
    permissionOverrunMinutes: { type: Number, default: 0 },
    permissionOverrunFineAmount: { type: Number, default: 0 },
    /** Total fine amount in currency (late + early + permission overrun) from payroll fine calculation. */
    fineAmount: Number,
    break: {
      totalBreakMin: { type: Number, default: 0 },
      // Accumulated break duration in seconds — the source of truth for break-overage
      // fines, which are computed at second precision then floored to whole minutes
      // (so a sub-minute overage isn't rounded up into a fined minute).
      totalBreakSeconds: { type: Number, default: 0 },
      totalBreakCount: { type: Number, default: 0 },
      totalBreakFineMins: { type: Number, default: 0 },
      totalBreakFineAmount: { type: Number, default: 0 },
      breaks: [{
        startTime: { type: Date, default: null },
        endTime: { type: Date, default: null },
        duration: { type: Number, default: 0 },
        BreakCount: { type: Number, default: 0 },
        breakFineMins: { type: Number, default: 0 },
        breakFineAmount: { type: Number, default: 0 }
      }]
    },
    location: {
      latitude: Number,
      longitude: Number,
      address: String,
      area: String,
      city: String,
      pincode: String,
      punchIn: {
        latitude: Number,
        longitude: Number,
        address: String,
        area: String,
        city: String,
        pincode: String
      },
      punchOut: {
        latitude: Number,
        longitude: Number,
        address: String,
        area: String,
        city: String,
        pincode: String
      }
    },
    ipAddress: String,
    punchInIpAddress: String,
    punchOutIpAddress: String,
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business'
    },
    punchInSelfie: String,
    punchOutSelfie: String,
    punchInFaceMatch: Number,
    punchOutFaceMatch: Number,
    /** Selfie-stamped log of custom-time ('both') permission step-outs/returns for the day.
     *  `minutes` is the approved window total (To−From) at the time of stamping. */
    permissionPunches: [{
      kind: { type: String, enum: ['out', 'in'] },
      at: { type: Date },
      selfie: { type: String },
      minutes: { type: Number, default: 0 }
    }],
    leaveTemplateId: { type: mongoose.Schema.Types.ObjectId, ref: 'LeaveTemplate' },
    leaveId: { type: mongoose.Schema.Types.ObjectId, ref: 'Leave' },
    compensationType: { type: String, enum: ['paid', 'unpaid', 'weekOff', 'compOff'] },
    alternateWorkDate: Date,
    availableCasualLeaves: Number,
    /**
     * Embedded shift _id from company.settings.attendance.shifts resolved for this attendance day.
     * Preserved so historical attendance keeps correct shift even if assignment changes later.
     */
    appliedShiftId: { type: mongoose.Schema.Types.ObjectId },
    isPaidLeave: { type: Boolean, default: false },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    updatedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    fcmNotificationSentAt: { type: Date },
    fcmRejectionSentAt: { type: Date },
    fcmStatusChangeSentAt: { type: Date },
    /** Source of punch: app, software, webemp, webadmin */
    source: {
      type: String,
      enum: ['app', 'software', 'webemp', 'webadmin'],
      default: null
    }
  },
  { timestamps: true }
);

attendanceSchema.pre('save', async function () {
  if (this.employeeId && !this.user) {
    this.user = this.employeeId;
  }
  if (this.user && !this.employeeId) {
    this.employeeId = this.user;
  }
});

attendanceSchema.index({ employeeId: 1, date: 1 }, { unique: true });
attendanceSchema.index({ user: 1, date: 1 });
attendanceSchema.index({ date: 1 });
attendanceSchema.index({ businessId: 1 });
attendanceSchema.index({ alternateWorkDate: 1, compensationType: 1 });

module.exports = mongoose.model('Attendance', attendanceSchema);
