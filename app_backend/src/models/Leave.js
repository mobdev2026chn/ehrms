const mongoose = require('mongoose');

const leaveSchema = new mongoose.Schema({
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
    leaveType: {
        type: String,
        required: true,
        trim: true
        // No enum - validated against template leaveTypes only
    },
    session: {
        type: String,
        enum: ['1', '2', null],
        default: null
    },
    halfDaySession: {
        type: String,
        enum: ['First Half Day', 'Second Half Day', null],
        default: null
    },
    // Same values as halfDaySession; some clients send halfDayType (e.g. "Second Half Day")
    halfDayType: {
        type: String,
        enum: ['First Half Day', 'Second Half Day', null],
        default: null
    },
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    days: { type: Number, required: true, min: 0.5 },
    reason: { type: String, required: true },
    status: {
        type: String,
        enum: ['Pending', 'Approved', 'Rejected', 'Cancelled'],
        default: 'Pending'
    },
    approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    approvedAt: { type: Date },
    rejectedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    rejectedAt: { type: Date },
    rejectionReason: { type: String },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    // Set when FCM "leave approved" notification has been sent (by API or cron)
    fcmNotificationSentAt: { type: Date },
    // Set when FCM "leave rejected" notification has been sent
    fcmRejectionSentAt: { type: Date }
}, { timestamps: true });

leaveSchema.index({ employeeId: 1 });
leaveSchema.index({ status: 1 });
leaveSchema.index({ startDate: 1, endDate: 1 });
leaveSchema.index({ businessId: 1 });

// Post-save hook to mark attendance as "On Leave" when leave is approved
leaveSchema.post('save', async function(doc) {
    // Only process if status is "Approved" and this is a new approval (not just an update)
    if (doc.status === 'Approved' && doc.approvedAt) {
        try {
            const { markAttendanceForApprovedLeave } = require('../utils/leaveAttendanceHelper');
            await markAttendanceForApprovedLeave(doc);
        } catch (error) {
            console.error('[Leave Model] Error marking attendance in post-save hook:', error);
            // Don't throw error to prevent save failure
        }
    } else if (doc.status === 'Cancelled' || doc.status === 'Rejected') {
        try {
            const { revertAttendanceForDeletedLeave } = require('../utils/leaveAttendanceHelper');
            await revertAttendanceForDeletedLeave(doc);
        } catch (error) {
            console.error('[Leave Model] Error reverting attendance in post-save hook:', error);
        }
    }
});

// Post-update hook for findOneAndUpdate operations
leaveSchema.post('findOneAndUpdate', async function(doc) {
    if (doc && doc.status === 'Approved' && doc.approvedAt) {
        try {
            const { markAttendanceForApprovedLeave } = require('../utils/leaveAttendanceHelper');
            await markAttendanceForApprovedLeave(doc);
        } catch (error) {
            console.error('[Leave Model] Error marking attendance in post-update hook:', error);
        }
    } else if (doc && (doc.status === 'Cancelled' || doc.status === 'Rejected')) {
        try {
            const { revertAttendanceForDeletedLeave } = require('../utils/leaveAttendanceHelper');
            await revertAttendanceForDeletedLeave(doc);
        } catch (error) {
            console.error('[Leave Model] Error reverting attendance in post-update hook:', error);
        }
    }
});

// Post-remove hook for deletion
leaveSchema.post('remove', async function(doc) {
    try {
        const { revertAttendanceForDeletedLeave } = require('../utils/leaveAttendanceHelper');
        await revertAttendanceForDeletedLeave(doc);
    } catch (error) {
        console.error('[Leave Model] Error reverting attendance in post-remove hook:', error);
    }
});

// Post hook for findOneAndDelete
leaveSchema.post('findOneAndDelete', async function(doc) {
    if (doc) {
        try {
            const { revertAttendanceForDeletedLeave } = require('../utils/leaveAttendanceHelper');
            await revertAttendanceForDeletedLeave(doc);
        } catch (error) {
            console.error('[Leave Model] Error reverting attendance in post-findOneAndDelete hook:', error);
        }
    }
});

module.exports = mongoose.model('Leave', leaveSchema);