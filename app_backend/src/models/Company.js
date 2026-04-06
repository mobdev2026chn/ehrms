const mongoose = require('mongoose');
const { Schema } = mongoose;

const CompanySchema = new Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true
    },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true
    },
    phone: {
      type: String,
      required: true
    },
    address: {
      street: String,
      city: String,
      state: String,
      zipCode: String,
      country: {
        type: String,
        default: 'India'
      }
    },
    logo: String,
    taxId: String,
    registrationNumber: String,
    subscriptionPlan: {
      type: String,
      enum: ['standard', 'medium', 'enterprise'],
      default: 'standard'
    },
    subscriptionPlanId: {
      type: Schema.Types.ObjectId,
      ref: 'SubscriptionPlan'
    },
    planType: {
      type: String,
      enum: ['trial', 'standard', 'premium'],
      default: 'trial'
    },
    subscriptionStatus: {
      type: String,
      enum: ['active', 'suspended', 'expired', 'trial', 'cancelled'],
      default: 'trial'
    },
    subscriptionStartDate: Date,
    subscriptionEndDate: Date,
    subscriptionRenewalDate: Date,
    trial: {
      isTrial: {
        type: Boolean,
        default: true
      },
      trialStartDate: Date,
      trialEndDate: Date
    },
    userLimits: {
      maxAdmins: { type: Number, default: 5 },
      maxRecruiters: { type: Number, default: 10 },
      maxManagers: { type: Number, default: 20 }
    },
    usage: {
      currentAdmins: { type: Number, default: 0 },
      currentRecruiters: { type: Number, default: 0 },
      currentManagers: { type: Number, default: 0 }
    },
    isActive: { type: Boolean, default: true },
    isSuspended: { type: Boolean, default: false },
    activatedAt: Date,
    deactivatedAt: Date,
    suspendedAt: Date,
    suspendedReason: String,
    createdBy: { type: Schema.Types.ObjectId, ref: 'User' },
    updatedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    deletedAt: Date,
    settings: {
      attendance: {
        geofence: {
          enabled: { type: Boolean, default: false },
          latitude: Number,
          longitude: Number,
          radius: Number
        },
        shifts: [{
          name: String,
          shiftType: {
            type: String,
            enum: ['standard', 'rotational', 'open'],
            default: 'standard'
          },
          startTime: String,
          endTime: String,
          /** Minutes after shift end with no OT accrual; OT = max(0, minutes past shift end − buffer). */
          otBufferMinutes: { type: Number, default: 0 },
          /** Open shifts: required hours per day (e.g. 9). */
          workHours: { type: Number, default: null },
          /** Rotational wrapper: cycle of embedded shift _ids or names (see main HRMS backend). */
          rotationalConfig: {
            rotationType: {
              type: String,
              enum: ['weekly', 'daily', 'custom', 'byWeekday'],
              default: null
            },
            cycleLengthDays: { type: Number, default: null },
            /** Mixed so ObjectId, 24-char hex strings, and legacy {$oid} shapes all hydrate (avoids empty cycle on read). */
            shiftIdsInCycle: [{ type: Schema.Types.Mixed }],
            shiftNamesInCycle: [{ type: String }],
            shiftIdsByWeekday: [{
              day: { type: Number },
              shiftId: { type: Schema.Types.Mixed }
            }]
          },
          graceTime: {
            value: Number,
            unit: { type: String, enum: ['minutes', 'hours'], default: 'minutes' }
          },
          halfDaySettings: {
            enabled: { type: Boolean, default: false },
            customMidPointTime: { type: String, default: null },
            firstHalfEndTime: { type: String, default: null },
            secondHalfStartTime: { type: String, default: null },
            firstHalfLogoutGraceMinutes: { type: Number, default: 30 },
            secondHalfLoginGraceMinutes: { type: Number, default: 0 },
            secondHalfStrictLogin: { type: Boolean, default: true }
          }
        }],
        automationRules: {
          autoMarkAbsent: { type: Boolean, default: false },
          autoMarkHalfDay: { type: Boolean, default: false },
          allowAttendanceOnWeeklyOff: { type: Boolean, default: false }
        },
        fineSettings: {
          enabled: { type: Boolean, default: false },
          graceTimeMinutes: { type: Number, default: 10 },
          finePerHour: { type: Number, default: 50 },
          calculationType: {
            type: String,
            enum: ['shiftBased', 'fixedPerHour', 'custom'],
            default: 'shiftBased'
          },
          fineRules: [{
            type: {
              type: String,
              enum: ['1xSalary', '2xSalary', '3xSalary', 'halfDay', 'fullDay', 'custom'],
              required: true
            },
            customAmount: Number,
            customAmountUnit: {
              type: String,
              enum: ['perMinute', 'perHour', 'fixed'],
              default: 'perHour'
            },
            applyTo: {
              type: String,
              enum: ['lateArrival', 'earlyExit', 'both'],
              default: 'lateArrival'
            }
          }]
        }
      },
      business: {
        weeklyHolidays: [{
          day: { type: Number, min: 0, max: 6 },
          name: String
        }],
        weeklyOffPattern: {
          type: String,
          enum: ['standard', 'oddEvenSaturday'],
          default: 'standard'
        },
        allowAttendanceOnWeeklyOff: { type: Boolean, default: false }
      },
      payroll: {
        calculationLogic: String,
        payableDaysRuleId: { type: Schema.Types.Mixed },
        payableDaysRule: { type: Schema.Types.Mixed },
        payslipCustomization: Schema.Types.Mixed,
        processingRules: {
          autoProcess: { type: Boolean, default: false },
          processDate: { type: Number, min: 1, max: 28, default: 1 },
          allowManualAdjustments: { type: Boolean, default: true },
          requireApproval: { type: Boolean, default: false },
          notifyOnCompletion: { type: Boolean, default: true }
        },
        cycle: {
          cycleType: {
            type: String,
            enum: ['monthly', 'biweekly', 'weekly'],
            default: 'monthly'
          },
          startDate: { type: Number, min: 1, max: 31, default: 1 },
          endDate: { type: Number, min: 1, max: 31, default: 30 },
          paymentDate: { type: Number, min: 1, max: 31, default: 5 },
          cutoffDate: { type: Number, min: 1, max: 31, default: 25 }
        },
        attendanceCalculation: {
          enabled: { type: Boolean, default: true },
          useAttendanceForProration: { type: Boolean, default: true },
          considerHalfDays: { type: Boolean, default: true },
          considerLateArrivals: { type: Boolean, default: false }
        },
        deductions: {
          autoCalculatePF: { type: Boolean, default: true },
          autoCalculateESI: { type: Boolean, default: true },
          applyTaxDeductions: { type: Boolean, default: false }
        },
        reimbursement: {
          autoIncludeApproved: { type: Boolean, default: true },
          includeInGross: { type: Boolean, default: true }
        },
        payslip: {
          isPayslipAutoGenerated: { type: Boolean, default: false }
        },
        fineCalculation: {
          enabled: { type: Boolean, default: false },
          applyFines: { type: Boolean, default: true },
          calculationMethod: {
            type: String,
            enum: ['shiftBased', 'fixedPerHour', 'custom'],
            default: 'shiftBased'
          },
          formula: {
            type: String,
            default: 'Fine = (Daily Salary ÷ Shift Hours) × Late Hours. Example: If shift is 9 hours (10 AM - 7 PM) and daily salary is ₹1000, hourly rate is ₹111.11. For 1 hour late, fine = ₹111.11'
          },
          fineRules: [{
            type: {
              type: String,
              enum: ['1xSalary', '2xSalary', '3xSalary', 'halfDay', 'fullDay', 'custom'],
              required: true
            },
            customAmount: Number,
            customAmountUnit: {
              type: String,
              enum: ['perMinute', 'perHour', 'fixed'],
              default: 'perHour'
            },
            applyTo: {
              type: String,
              enum: ['lateArrival', 'earlyExit', 'both'],
              default: 'lateArrival'
            }
          }]
        }
      }
    }
  },
  { timestamps: true }
);

CompanySchema.index({ isActive: 1 });
CompanySchema.index({ deletedAt: 1 });
CompanySchema.index({ 'trial.trialEndDate': 1 });

/**
 * Mongo collection must match the main HRMS TypeScript `Business` model (default: `businesses`).
 * Legacy deployments that only have `companies` can set MONGOOSE_COMPANY_COLLECTION=companies.
 */
const COMPANY_COLLECTION = process.env.MONGOOSE_COMPANY_COLLECTION || 'businesses';
module.exports = mongoose.model('Company', CompanySchema, COMPANY_COLLECTION);
