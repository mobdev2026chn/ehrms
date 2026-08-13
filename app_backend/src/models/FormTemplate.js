/**
 * FormTemplate – mirrors backend formtemplates collection.
 * Used by app for arrived screen: staff fills assigned forms before completing task.
 */
const mongoose = require('mongoose');

const formTemplateFieldSchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true },
  type: {
    type: String,
    enum: ['Text', 'Image', 'Dropdown', 'Number', 'Date', 'Email', 'Phone', 'Textarea'],
    default: 'Text',
  },
  mandatory: { type: Boolean, default: false },
  cameraOnly: { type: Boolean, default: false },
  options: [{ type: String, trim: true }],
  order: { type: Number, default: 0 },
}, { _id: true });

const formTemplateSchema = new mongoose.Schema({
  templateName: { type: String, required: true, trim: true },
  fields: [formTemplateFieldSchema],
  businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
  createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  isActive: { type: Boolean, default: true },
  assignedTo: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }],
  deactivatedAt: { type: Date },
}, { timestamps: true });

formTemplateSchema.index({ businessId: 1, isActive: 1 });
formTemplateSchema.index({ businessId: 1, templateName: 1 });
formTemplateSchema.index({ 'assignedTo': 1 });

module.exports = mongoose.model('FormTemplate', formTemplateSchema);
