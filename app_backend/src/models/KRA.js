const mongoose = require('mongoose');

const kraSchema = new mongoose.Schema(
  {
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    title: { type: String, required: true, trim: true },
    description: String,
    kpi: { type: String, required: true },
    target: { type: String, required: true },
    currentValue: String,
    status: {
      type: String,
      enum: ['Pending', 'At risk', 'Needs attention', 'On track', 'Closed'],
      default: 'Pending',
    },
    timeframe: {
      type: String,
      enum: ['Weekly', 'Monthly', 'Quarterly', 'Yearly'],
      required: true,
    },
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    overallPercent: { type: Number, default: 0, min: 0, max: 100 },
    milestones: [{
      name: String,
      target: String,
      achieved: { type: Boolean, default: false },
      achievedAt: Date,
    }],
    goalIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Goal' }],
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
  },
  { timestamps: true }
);

module.exports = mongoose.model('KRA', kraSchema);
