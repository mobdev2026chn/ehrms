const mongoose = require('mongoose');

const grievanceSchema = new mongoose.Schema({
    ticketId: { type: String, required: true, unique: true, index: true },
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true, index: true },
    categoryId: { type: mongoose.Schema.Types.ObjectId, ref: 'GrievanceCategory', required: true },
    category: { type: String, required: true, trim: true },
    title: { type: String, required: true, trim: true, maxlength: 200 },
    description: { type: String, required: true, trim: true },
    incidentDate: { type: Date },
    peopleInvolved: { type: [String], default: [] },
    priority: {
        type: String,
        enum: ['Low', 'Medium', 'High', 'Critical'],
        default: 'Medium',
        required: true
    },
    isAnonymous: { type: Boolean, default: false },
    status: {
        type: String,
        enum: ['Submitted', 'Under Review', 'Assigned', 'Investigation', 'Action Taken', 'Escalated', 'Rejected', 'Closed'],
        default: 'Submitted',
        required: true,
        index: true
    },
    assignedTo: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    assignedToName: { type: String, trim: true },
    assignedAt: { type: Date },
    committeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'GrievanceCommittee' },
    committeeAssignedAt: { type: Date },
    slaDays: { type: Number, min: 1 },
    slaDueDate: { type: Date, index: true },
    slaBreached: { type: Boolean, default: false, index: true },
    slaBreachedAt: { type: Date },
    resolutionSummary: { type: String, trim: true },
    actionTaken: { type: String, trim: true },
    closedAt: { type: Date },
    closedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    rejectionReason: { type: String, trim: true },
    escalatedAt: { type: Date },
    escalatedTo: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    escalationReason: { type: String, trim: true },
    escalationLevel: { type: Number, default: 0, min: 0 },
    employeeRating: { type: Number, min: 1, max: 5 },
    employeeFeedback: { type: String, trim: true },
    feedbackSubmittedAt: { type: Date },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true, index: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    softDeleted: { type: Boolean, default: false, index: true }
}, { timestamps: true });

grievanceSchema.index({ businessId: 1, status: 1 });
grievanceSchema.index({ employeeId: 1, status: 1 });
grievanceSchema.index({ businessId: 1, createdAt: -1 });

grievanceSchema.pre('save', async function () {
    if (this.isNew && !this.ticketId) {
        try {
            const year = new Date().getFullYear();
            const count = await this.constructor.countDocuments({
                ticketId: new RegExp(`^GRV-${year}-`),
                businessId: this.businessId
            });
            const sequence = String(count + 1).padStart(4, '0');
            this.ticketId = `GRV-${year}-${sequence}`;
        } catch (err) {
            console.error('Error generating ticketId:', err);
        }
    }
});

module.exports = mongoose.model('Grievance', grievanceSchema);
