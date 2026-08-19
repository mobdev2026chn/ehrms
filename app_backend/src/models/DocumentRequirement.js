const mongoose = require('mongoose');

const DocumentRequirementSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true
    },
    type: {
      type: String,
      enum: ['form', 'document'],
      required: true
    },
    required: {
      type: Boolean,
      default: true
    },
    description: {
      type: String,
      trim: true
    },
    order: {
      type: Number,
      default: 0
    },
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: false,
      default: null // null means global default
    },
    isActive: {
      type: Boolean,
      default: true
    }
  },
  {
    timestamps: true
  }
);

module.exports = mongoose.model('DocumentRequirement', DocumentRequirementSchema);
