const mongoose = require('mongoose');

// Align with customers collection / Customer.model.ts: businessId, addedBy, customerName, etc.
const customerSchema = new mongoose.Schema(
  {
    customerName: { type: String, required: true, trim: true },
    customerNumber: { type: String, required: true, trim: true },
    companyName: { type: String, trim: true },
    address: { type: String, required: true, trim: true },
    emailId: { type: String, required: true, lowercase: true, trim: true },
    city: { type: String, required: true, trim: true },
    pincode: { type: String, required: true, trim: true },
    countryCode: { type: String, trim: true },
    email: { type: String }, // alias
    status: {
      type: String,
      enum: ['Not yet Started', 'Pending', 'In progress', 'Serving Today', 'Delayed Tasks', 'Completed Tasks', 'Reopened', 'Rejected', 'Hold'],
      default: 'Not yet Started'
    },
    completedDate: { type: Date },
    expectedCompletionDate: { type: Date },
    customFields: { type: mongoose.Schema.Types.Mixed, default: {} },
    source: { type: String, default: 'web' },
    addedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    /**
     * When non-empty, only these staff may see the customer in the app.
     * Empty/undefined = visible to all staff in the company.
     */
    visibleToStaffIds: {
      type: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }],
      default: undefined,
    },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Business', required: true }
  },
  { timestamps: true }
);

customerSchema.index({ businessId: 1 });
customerSchema.index({ customerNumber: 1, businessId: 1 }, { unique: true });
customerSchema.index({ emailId: 1, businessId: 1 });
customerSchema.index({ addedBy: 1 });
customerSchema.index({ createdAt: -1 });

module.exports = mongoose.model('Customer', customerSchema);
