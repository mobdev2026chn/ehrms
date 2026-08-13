const mongoose = require('mongoose');

// Match web backend (backend/src/models/AIQuiz.model.ts) for same aiquizzes collection
const questionSchema = new mongoose.Schema({
    type: { type: String, enum: ['MCQ', 'True/False', 'Short Answer', 'multiple-choice', 'true-false', 'short-answer'], default: 'MCQ' },
    question: { type: String, required: true },
    options: [String],
    correctAnswer: { type: mongoose.Schema.Types.Mixed },
    explanation: { type: String },
    points: { type: Number, default: 1 },
    rationale: { type: String },
}, { _id: true });

const aiQuizSchema = new mongoose.Schema({
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    courseId: { type: mongoose.Schema.Types.ObjectId, ref: 'Course', required: true },
    lessonTitles: [String],
    difficulty: { type: String, enum: ['Easy', 'Medium', 'Difficult', 'Hard'], default: 'Medium' },
    questionCount: { type: Number, default: 5 },
    title: { type: String, default: '' },
    questions: [questionSchema],
    totalPoints: { type: Number, default: 0 },
    passingScore: { type: Number, default: 60 },
    materialId: { type: mongoose.Schema.Types.Mixed },
    status: { type: String, enum: ['Draft', 'Submitted'], default: 'Draft' },
    responses: [{
        questionIndex: Number,
        answer: String,
        isCorrect: Boolean,
        resolvedCorrectAnswer: String,
    }],
    score: { type: Number, default: 0 },
    completionTime: Number,
    submittedAt: Date,
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
}, { timestamps: true });

aiQuizSchema.index({ employeeId: 1, courseId: 1 });
aiQuizSchema.index({ userId: 1, courseId: 1 });
aiQuizSchema.index({ businessId: 1 });

module.exports = mongoose.model('AIQuiz', aiQuizSchema);
