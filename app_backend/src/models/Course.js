const mongoose = require('mongoose');

const materialSchema = new mongoose.Schema({
    type: { type: String, enum: ['YOUTUBE', 'PDF', 'VIDEO', 'DRIVE', 'URL', 'PPT'], default: 'URL' },
    title: { type: String },
    lessonTitle: { type: String },
    url: { type: String },
    filePath: { type: String },
    originalFileName: { type: String },
    order: { type: Number, default: 0 },
    content: { type: String }, // Optional text content for AI quiz generation
    description: { type: String },
}, { _id: true });

const courseSchema = new mongoose.Schema({
    title: { type: String, required: true },
    description: { type: String },
    category: { type: String, default: 'GENERAL' },
    language: { type: String },
    thumbnailUrl: { type: String },
    status: { type: String, enum: ['Draft', 'Published', 'Archived'], default: 'Published' },
    isMandatory: { type: Boolean, default: false },
    instructor: { type: String, default: 'Admin' },
    materials: [materialSchema],
    contents: [materialSchema],
    completionDuration: {
        value: { type: Number },
        unit: { type: String, enum: ['Days', 'Weeks', 'Months'] },
    },
    duration: { type: Number },
    assignmentType: { type: String, enum: ['DEPARTMENT', 'INDIVIDUAL', 'ALL'] },
    departments: [{ type: mongoose.Schema.Types.ObjectId }],
    assignedEmployees: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }],
    qualificationScore: { type: Number },
    isLiveAssessment: { type: Boolean, default: false },
    assessmentQuestions: mongoose.Schema.Types.Mixed,
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
}, { timestamps: true });

module.exports = mongoose.model('Course', courseSchema);
