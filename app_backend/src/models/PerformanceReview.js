const mongoose = require('mongoose');

const performanceReviewSchema = new mongoose.Schema(
  {
    employeeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Staff',
      required: true,
      index: true,
    },
    reviewCycle: {
      type: String,
      required: true,
      trim: true,
    },
    reviewPeriod: {
      startDate: { type: Date, required: true },
      endDate: { type: Date, required: true },
    },
    reviewType: {
      type: String,
      enum: ['Quarterly', 'Half-Yearly', 'Annual', 'Probation', 'Custom'],
      required: true,
    },
    status: {
      type: String,
      enum: [
        'draft',
        'self-review-pending',
        'self-review-submitted',
        'manager-review-pending',
        'manager-review-submitted',
        'hr-review-pending',
        'hr-review-submitted',
        'completed',
        'cancelled',
      ],
      default: 'draft',
      index: true,
    },
    selfReview: {
      overallRating: { type: Number, min: 1, max: 5 },
      strengths: [String],
      areasForImprovement: [String],
      achievements: [String],
      challenges: [String],
      goalsAchieved: [String],
      comments: String,
      submittedAt: Date,
    },
    managerId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    managerReview: {
      overallRating: { type: Number, min: 1, max: 5 },
      technicalSkills: { type: Number, min: 1, max: 5 },
      communication: { type: Number, min: 1, max: 5 },
      teamwork: { type: Number, min: 1, max: 5 },
      leadership: { type: Number, min: 1, max: 5 },
      problemSolving: { type: Number, min: 1, max: 5 },
      punctuality: { type: Number, min: 1, max: 5 },
      strengths: [String],
      areasForImprovement: [String],
      achievements: [String],
      feedback: String,
      recommendations: String,
      submittedAt: Date,
    },
    hrReview: {
      overallRating: { type: Number, min: 1, max: 5 },
      alignmentWithCompanyValues: { type: Number, min: 1, max: 5 },
      growthPotential: { type: Number, min: 1, max: 5 },
      feedback: String,
      recommendations: String,
      submittedAt: Date,
    },
    finalRating: { type: Number, min: 1, max: 5 },
    finalComments: String,
    completedAt: Date,
    completedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    goalIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Goal' }],
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      required: true,
      index: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    fcmSelfReviewReminderDaysSent: [Number],
    fcmManagerReviewReminderDaysSent: [Number],
    /** Last status for which we sent FCM to employee (so we notify on each status change) */
    fcmStatusChangeSentForStatus: { type: String, default: null },
  },
  { timestamps: true }
);

performanceReviewSchema.index({ employeeId: 1, reviewCycle: 1 });
performanceReviewSchema.index({ employeeId: 1, status: 1 });
performanceReviewSchema.index({ businessId: 1, reviewCycle: 1 });

module.exports = mongoose.model('PerformanceReview', performanceReviewSchema);
