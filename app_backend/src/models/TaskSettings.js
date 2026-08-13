const mongoose = require('mongoose');

const taskSettingsSchema = new mongoose.Schema(
  {
    companyId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    settings: {
      autoApprove: { type: Boolean, default: false },
      enableOtpVerification: { type: Boolean, default: false },
      requireApprovalOnComplete: { type: Boolean, default: false },
      staffWhoCanSchedule: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }],
    },
  },
  { collection: 'task-settings', timestamps: true }
);

module.exports = mongoose.model('TaskSettings', taskSettingsSchema);
