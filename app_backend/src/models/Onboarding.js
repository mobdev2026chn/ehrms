const mongoose = require('mongoose');

const ONBOARDING_STATUS = {
    NOT_STARTED: 'NOT_STARTED',
    IN_PROGRESS: 'IN_PROGRESS',
    COMPLETED: 'COMPLETED'
};

const DOCUMENT_STATUS = {
    NOT_STARTED: 'NOT_STARTED',
    PENDING: 'PENDING',
    COMPLETED: 'COMPLETED',
    REJECTED: 'REJECTED'
};

const onboardingDocumentSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true,
        trim: true
    },
    type: {
        type: String,
        required: true,
        trim: true
    },
    required: {
        type: Boolean,
        default: true
    },
    status: {
        type: String,
        enum: Object.values(DOCUMENT_STATUS),
        default: DOCUMENT_STATUS.NOT_STARTED
    },
    url: String,
    uploadedAt: Date,
    reviewedAt: Date,
    reviewedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    },
    notes: String
}, { _id: true });

const onboardingSchema = new mongoose.Schema({
    staffId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Staff',
        required: false,
        unique: true,
        sparse: true
    },
    candidateId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Candidate',
        required: false,
        sparse: true
    },
    status: {
        type: String,
        enum: Object.values(ONBOARDING_STATUS),
        default: ONBOARDING_STATUS.NOT_STARTED
    },
    documents: [onboardingDocumentSchema],
    progress: {
        type: Number,
        default: 0,
        min: 0,
        max: 100
    },
    startedAt: Date,
    completedAt: Date,
    businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Company'
    },
    createdBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }
}, { timestamps: true });

// Indexes
onboardingSchema.index({ businessId: 1 });
onboardingSchema.index({ status: 1 });
onboardingSchema.index({ createdAt: -1 });

// Calculate progress before saving
onboardingSchema.pre('save', function (next) {
    try {
        if (this.documents && Array.isArray(this.documents) && this.documents.length > 0) {
            const requiredDocs = this.documents.filter(doc => doc && doc.required);

            if (requiredDocs.length === 0) {
                this.progress = 100;
            } else {
                const completedRequiredDocs = requiredDocs.filter(
                    doc => doc && doc.status === DOCUMENT_STATUS.COMPLETED
                ).length;
                this.progress = Math.round((completedRequiredDocs / requiredDocs.length) * 100);
            }

            // Update status based on progress
            if (this.progress === 0) {
                this.status = ONBOARDING_STATUS.NOT_STARTED;
            } else if (this.progress === 100) {
                this.status = ONBOARDING_STATUS.COMPLETED;
                if (!this.completedAt) {
                    this.completedAt = new Date();
                }
            } else {
                this.status = ONBOARDING_STATUS.IN_PROGRESS;
                if (!this.startedAt) {
                    this.startedAt = new Date();
                }
            }
        } else {
            // No documents, set default progress
            this.progress = 0;
            if (!this.status || this.status === ONBOARDING_STATUS.NOT_STARTED) {
                this.status = ONBOARDING_STATUS.NOT_STARTED;
            }
        }
        
        if (next && typeof next === 'function') {
            next();
        }
    } catch (error) {
        console.error('Onboarding pre-save hook error:', error);
        if (next && typeof next === 'function') {
            next(error);
        }
    }
});

module.exports = mongoose.model('Onboarding', onboardingSchema);
