const mongoose = require('mongoose');

const liveSessionSchema = new mongoose.Schema({
    title: { type: String, required: true },
    description: { type: String },
    agenda: { type: String },
    category: { type: String, default: 'Normal Session' },
    platform: { type: String, default: 'Google Meet' },
    meetingLink: { type: String, required: true },
    dateTime: { type: Date, required: true },
    duration: { type: Number, default: 60 },
    status: { type: String, enum: ['Scheduled', 'Live', 'Completed', 'Cancelled'], default: 'Scheduled' },
    assignmentType: { type: String, enum: ['All', 'Department', 'Individual'], default: 'All' },
    departments: [{ type: String }],
    assignedEmployees: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }],
    trainerId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    trainerName: { type: String },
    recordingUrl: { type: String },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
}, { timestamps: true });

module.exports = mongoose.model('LiveSession', liveSessionSchema);
