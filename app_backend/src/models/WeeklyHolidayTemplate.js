const mongoose = require('mongoose');

/**
 * Weekly Holiday Template (collection: weeklyholidaytemplates).
 * Defines which days of the week are week-off for staff assigned to this template.
 * Week-off for a staff is resolved only from this template when staff.weeklyHolidayTemplateId is set.
 * If not set or template inactive, a default (e.g. Sunday only) is used; business/company is not used for week-off.
 */
const weeklyHolidayTemplateSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    description: { type: String, trim: true },
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      required: true,
    },
    settings: {
      weeklyHolidays: [
        {
          day: { type: Number, min: 0, max: 6 }, // 0=Sunday, 6=Saturday
          name: { type: String },
        },
      ],
      weeklyOffPattern: {
        type: String,
        enum: ['standard', 'oddEvenSaturday'],
        default: 'standard',
      },
      allowAttendanceOnWeeklyOff: { type: Boolean, default: false },
    },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true }
);

weeklyHolidayTemplateSchema.index({ businessId: 1, isActive: 1 });

module.exports = mongoose.model(
  'WeeklyHolidayTemplate',
  weeklyHolidayTemplateSchema
);
