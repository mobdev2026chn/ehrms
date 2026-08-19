/**
 * FormResponse – mirrors backend formresponses collection.
 * Stores filled form data when staff completes a form for a task.
 */
const mongoose = require('mongoose');

const formResponseSchema = new mongoose.Schema({
  templateId: { type: mongoose.Schema.Types.ObjectId, ref: 'FormTemplate', required: true },
  taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task', required: true },
  staffId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
  responses: { type: mongoose.Schema.Types.Mixed, default: {} },
  isSubmitted: { type: Boolean, default: false },
  submittedAt: { type: Date },
  submittedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
}, { timestamps: true });

formResponseSchema.index({ businessId: 1 });
formResponseSchema.index({ templateId: 1 });
formResponseSchema.index({ taskId: 1 });
formResponseSchema.index({ staffId: 1 });
formResponseSchema.index({ taskId: 1, templateId: 1, staffId: 1 }, { unique: true });

module.exports = mongoose.model('FormResponse', formResponseSchema);
