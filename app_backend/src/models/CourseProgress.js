const mongoose = require('mongoose');

// Match web backend (backend/src/models/CourseProgress.model.ts) for same courseprogress collection
const contentProgressSchema = new mongoose.Schema({
    contentId: { type: mongoose.Schema.Types.Mixed, required: true },
    viewed: { type: Boolean, default: false },
    viewedAt: { type: Date },
    watchTime: { type: Number, default: 0 },
}, { _id: false });

const courseProgressSchema = new mongoose.Schema({
    courseId: { type: mongoose.Schema.Types.ObjectId, ref: 'Course', required: true },
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    status: {
        type: String,
        enum: ['Not Started', 'In Progress', 'Completed', 'Failed', 'Expired'],
        default: 'Not Started',
    },
    completionPercentage: { type: Number, default: 0, min: 0, max: 100 },
    dueDate: { type: Date },
    deadlineWarning7dSentAt: { type: Date },
    deadlineWarning3dSentAt: { type: Date },
    deadlineWarning1dSentAt: { type: Date },
    openedAt: { type: Date },
    lastAccessedAt: { type: Date },
    timeSpent: { type: Number, default: 0, min: 0 },
    contentProgress: [contentProgressSchema],
    completedLessons: [{ type: String }],
    assessmentStatus: {
        type: String,
        enum: ['Not Started', 'In Progress', 'Passed', 'Failed', 'Requested'],
        default: 'Not Started',
    },
    assessmentScore: { type: Number, min: 0, max: 100 },
    assessmentAttempts: { type: Number, default: 0 },
    lastAssessmentDate: { type: Date },
    assessmentRemarks: { type: String, default: '' },
    completedAt: { type: Date },
    certificateUrl: { type: String },
    isAccessBlocked: { type: Boolean, default: false },
    toolsUnlocked: { type: Boolean, default: false },
    assignedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
}, { timestamps: true });

courseProgressSchema.index({ courseId: 1, employeeId: 1 }, { unique: true, sparse: true });
courseProgressSchema.index({ courseId: 1, userId: 1 }, { unique: true, sparse: true });
courseProgressSchema.index({ businessId: 1 });
courseProgressSchema.index({ dueDate: 1 });
courseProgressSchema.index({ status: 1 });
courseProgressSchema.index({ assessmentStatus: 1 });

module.exports = mongoose.model('CourseProgress', courseProgressSchema);
