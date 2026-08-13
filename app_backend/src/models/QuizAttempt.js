const mongoose = require('mongoose');

const quizAttemptSchema = new mongoose.Schema({
    quizId: { type: mongoose.Schema.Types.ObjectId, ref: 'AIQuiz', required: true },
    employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }, // web backend may use userId
    responses: [{
        questionIndex: { type: Number },
        answer: { type: String },
    }],
    score: { type: Number },
    totalPoints: { type: Number },
    passed: { type: Boolean },
    completionTime: { type: Number },
}, { timestamps: true });

module.exports = mongoose.model('QuizAttempt', quizAttemptSchema);
