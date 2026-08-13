const mongoose = require('mongoose');

const leaveTemplateSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    description: { type: String, trim: true },
    leaveTypes: [
      {
        type: { type: String, required: true, trim: true },
        days: { type: Number, required: true, min: 0 },
        limit: { type: Number, min: 0 }, // optional alias used by some code
        carryForward: { type: Boolean, default: false },
        maxCarryForward: { type: Number, min: 0 }
      }
    ],
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    assignedStaff: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }],
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    isActive: { type: Boolean, default: true }
  },
  { timestamps: true }
);

leaveTemplateSchema.index({ businessId: 1, name: 1 }, { unique: true });
leaveTemplateSchema.index({ businessId: 1, isActive: 1 });

module.exports = mongoose.model('LeaveTemplate', leaveTemplateSchema);
