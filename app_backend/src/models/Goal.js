const mongoose = require('mongoose');

const goalSchema = new mongoose.Schema(
  {
    employeeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Staff',
      required: true,
    },
    title: { type: String, required: true, trim: true },
    type: { type: String, required: true },
    kpi: { type: String, required: true },
    target: { type: String, required: true },
    weightage: { type: Number, required: true, min: 0, max: 100 },
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    progress: { type: Number, default: 0, min: 0, max: 100 },
    status: {
      type: String,
      enum: ['draft', 'pending', 'approved', 'rejected', 'modified', 'completed'],
      default: 'draft',
    },
    cycle: { type: String, required: true },
    achievements: String,
    challenges: String,
    managerNotes: String,
    hrNotes: String,
    modificationNotes: String,
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    assignedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    kraId: { type: mongoose.Schema.Types.ObjectId, ref: 'KRA' },
    completedAt: Date,
    completedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    completedApprovedAt: Date,
    completedApprovedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

goalSchema.index({ employeeId: 1, cycle: 1 });
goalSchema.index({ status: 1 });
goalSchema.index({ businessId: 1 });

module.exports = mongoose.model('Goal', goalSchema);
