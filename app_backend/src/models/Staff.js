const mongoose = require('mongoose');
const MONITORING_STATUSES = require('../constants/monitoringStatus');

const staffSchema = new mongoose.Schema({
    employeeId: { type: String, required: true, unique: true },
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    branchId: { type: mongoose.Schema.Types.ObjectId, ref: 'Branch' },
    name: { type: String, required: true },
    email: { type: String, required: true, unique: true },
    password: { type: String, required: true },
    phone: { type: String },
    alternativePhone: { type: String },
    countryCode: { type: String, trim: true },
    designation: { type: String },
    department: { type: String },
    staffType: {
        type: String,
        enum: ['Full Time', 'Part Time', 'Contract', 'Intern'],
        default: 'Full Time'
    },
    role: {
        type: String,
        enum: ['Intern', 'Employee']
    },
    shiftName: { type: String },
    attendanceTemplateId: { type: mongoose.Schema.Types.ObjectId, ref: 'AttendanceTemplate' },
    leaveTemplateId: { type: mongoose.Schema.Types.ObjectId, ref: 'LeaveTemplate' },
    holidayTemplateId: { type: mongoose.Schema.Types.ObjectId, ref: 'HolidayTemplate' },
    weeklyHolidayTemplateId: { type: mongoose.Schema.Types.ObjectId, ref: 'WeeklyHolidayTemplate' },
    status: { type: String, default: 'Active' },
    joiningDate: { type: Date, default: Date.now },
    avatar: { type: String },
    gender: { type: String },
    maritalStatus: { type: String },
    dob: { type: Date },
    bloodGroup: { type: String },
    address: {
        line1: String,
        city: String,
        state: String,
        postalCode: String,
        country: String,
    },
    // Employment IDs (direct fields, not nested)
    uan: { type: String },
    pan: { type: String },
    aadhaar: { type: String },
    pfNumber: { type: String },
    esiNumber: { type: String },

    // Bank Details
    bankDetails: {
        bankName: String,
        accountNumber: String,
        ifscCode: String,
        accountHolderName: String,
        upiId: String,
    },

    // Reference to candidate for education, experience, and documents
    candidateId: { type: mongoose.Schema.Types.ObjectId, ref: 'Candidate' },

    // Hierarchy
    jobOpeningId: { type: mongoose.Schema.Types.ObjectId, ref: 'JobOpening' },
    managerId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    teamLeaderId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    hierarchyLevel: { type: Number, min: 1, max: 3, default: 3 },

    // Offer Letter
    offerLetterUrl: { type: String },
    offerLetterParsedAt: { type: Date },

    // Tasks module visibility – when true, show Tasks in app drawer
    locationAccess: { type: Boolean, default: false },

    // Device/app location permission snapshot from the mobile app.
    isGpsEnabled: { type: Boolean },
    isGpsAllowed: { type: String }, // "Allow all the time" | "Allow only while using the app" | "Ask every time" | "Don't allow"
    isEnabledPreciseLocation: { type: Boolean },

    // LMS access (employee portal "My Learning" visibility)
    lmsAccessEnabled: { type: Boolean, default: true },

    // Two-Factor Authentication
    twoFactorEnabled: { type: Boolean, default: false },

    // FCM token for push notifications (set by app via POST /api/notifications/fcm-token)
    fcmToken: { type: String },

    // Desktop monitoring agent status - must match Device.status in monitoringdevices
    monitoringStatus: {
        type: String,
        enum: MONITORING_STATUSES,
        default: 'inactive'
    },

    salary: {
        // Fixed Salary Components (Monthly)
        basicSalary: Number,
        dearnessAllowance: Number,
        houseRentAllowance: Number,
        specialAllowance: Number,

        // Employer Contribution Rates (%)
        employerPFRate: Number,
        employerESIRate: Number,

        // Variable Pay Rate (%)
        incentiveRate: Number,

        // Benefits Rates and Fixed Values
        gratuityRate: Number,
        statutoryBonusRate: Number,
        medicalInsuranceAmount: Number,

        // Allowances
        mobileAllowance: Number,
        mobileAllowanceType: {
            type: String,
            enum: ['monthly', 'yearly'],
            default: 'monthly'
        },

        // Employee Deduction Rates (%)
        employeePFRate: Number,
        employeeESIRate: Number
    }
}, { timestamps: true });

const bcrypt = require('bcrypt');

staffSchema.pre('save', async function () {
    if (!this.isModified('password')) {
        return;
    }
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
});

staffSchema.methods.matchPassword = async function (enteredPassword) {
    if (!enteredPassword || !this.password) {
        return false;
    }
    return await bcrypt.compare(enteredPassword, this.password);
};

module.exports = mongoose.model('Staff', staffSchema);
