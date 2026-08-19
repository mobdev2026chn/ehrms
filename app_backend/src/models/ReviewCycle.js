const mongoose = require('mongoose');

const reviewCycleSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    type: {
      type: String,
      enum: ['Quarterly', 'Half-Yearly', 'Annual', 'Probation', 'Custom'],
      required: true,
    },
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    goalSubmissionDeadline: { type: Date, required: true },
    selfReviewDeadline: { type: Date, required: true },
    managerReviewDeadline: { type: Date, required: true },
    hrReviewDeadline: { type: Date, required: true },
    status: {
      type: String,
      enum: ['draft', 'active', 'goal-submission', 'self-review', 'manager-review', 'hr-review', 'completed', 'cancelled'],
      default: 'draft',
    },
    description: String,
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true, index: true },
    fcmHrReviewReminderDaysSent: [Number],
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  },
  { timestamps: true }
);

reviewCycleSchema.index({ businessId: 1, name: 1 }, { unique: true });
reviewCycleSchema.index({ businessId: 1, status: 1 });

module.exports = mongoose.model('ReviewCycle', reviewCycleSchema);
