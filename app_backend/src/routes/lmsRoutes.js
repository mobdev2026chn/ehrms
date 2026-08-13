const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const {
    getAllCourses,
    enrollCourse,
    getMyCourses,
    getCourseDetails,
    getMyProgress,
    completeLesson,
    updateProgress,
    getMySessions,
    createSession,
    updateSession,
    deleteSession,
    joinSession,
    leaveSession,
    getLearningEngine,
    logLearningActivity,
    getMyScores,
    generateAIQuiz,
    getAIQuiz,
    submitAIQuiz,
    submitCourseAssessment,
    getDepartments,
    getEmployees,
    getCategories,
} = require('../controllers/lmsController');

router.use(protect);

// Courses
router.get('/courses', getAllCourses);
router.post('/courses/:id/enroll', enrollCourse);
router.get('/my-courses', getMyCourses);
// GET /courses/:id/details - course with progress; GET /courses/:id uses same handler (web getCourseById)
router.get('/courses/:id/details', getCourseDetails);
router.get('/courses/:id', getCourseDetails);
router.get('/courses/:id/my-progress', getMyProgress);
router.post('/courses/:id/complete-lesson', completeLesson);
router.post('/courses/:id/progress', updateProgress);

// Live Sessions
router.get('/my-sessions', getMySessions);
router.post('/sessions', createSession);
router.put('/sessions/:id', updateSession);
router.delete('/sessions/:id', deleteSession);
router.post('/my-sessions/:id/join', joinSession);
router.post('/my-sessions/:id/leave', leaveSession);

// Learning Engine
router.get('/learning-engine', getLearningEngine);
router.post('/learning-engine/activity', logLearningActivity);
router.get('/analytics/my-scores', getMyScores);

// AI Quiz
router.post('/ai-quiz/generate', generateAIQuiz);
router.get('/ai-quiz/:id', getAIQuiz);
router.post('/ai-quiz/:id/submit', submitAIQuiz);

// Final Assessment
router.post('/courses/:id/assessment/submit', submitCourseAssessment);

// Meta (for schedule modal)
router.get('/departments', getDepartments);
router.get('/employees', getEmployees);
router.get('/categories', getCategories);

module.exports = router;
