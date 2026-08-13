const mongoose = require('mongoose');

const candidateSchema = new mongoose.Schema({
    firstName: { type: String, required: true, trim: true },
    lastName: { type: String, required: true, trim: true },
    email: { type: String, required: true, lowercase: true, trim: true },
    phone: { type: String, required: true },
    countryCode: { type: String },
    dateOfBirth: { type: Date },
    gender: { type: String },
    currentCity: { type: String },
    preferredJobLocation: { type: String },
    position: { type: String, required: true },
    primarySkill: { type: String, required: true },
    status: { type: String, default: 'Applied' },
    source: { type: String, default: 'Manual' },
    totalYearsOfExperience: { type: Number },
    currentCompany: { type: String },
    currentJobTitle: { type: String },
    employmentType: { type: String, enum: ['Full-time', 'Contract', 'Internship'] },

    // Education array
    education: [{
        qualification: String,
        courseName: String,
        institution: String,
        university: String,
        yearOfPassing: String,
        percentage: String,
        cgpa: String
    }],

    // Experience array
    experience: [{
        company: String,
        role: String,
        designation: String,
        durationFrom: Date,
        durationTo: Date,
        keyResponsibilities: String,
        reasonForLeaving: String
    }],

    // Courses array
    courses: [{
        courseName: String,
        institution: String,
        completionDate: Date,
        duration: String,
        description: String,
        certificateUrl: String
    }],

    // Internships array
    internships: [{
        company: String,
        role: String,
        durationFrom: Date,
        durationTo: Date,
        keyResponsibilities: String,
        skillsLearned: String,
        mentorName: String
    }],

    // Documents array
    documents: [{
        type: String,
        url: String,
        name: String
    }],

    // Resume
    resume: {
        url: String,
        name: String,
        uploadedAt: Date
    },

    skills: [String],
    location: { type: String },
    jobId: { type: mongoose.Schema.Types.ObjectId, ref: 'JobOpening' },
    currentJobStage: { type: Number },
    completedJobStages: [{ type: Number }],
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    selectedOn: { type: Date },
    rejectedOn: { type: Date }
}, { timestamps: true });

// Indexes
candidateSchema.index({ email: 1 });
candidateSchema.index({ status: 1 });
candidateSchema.index({ businessId: 1 });
candidateSchema.index({ email: 1, jobId: 1 }, { unique: true });

module.exports = mongoose.model('Candidate', candidateSchema);
