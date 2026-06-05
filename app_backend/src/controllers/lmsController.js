const mongoose = require('mongoose');
const Course = require('../models/Course');
const CourseProgress = require('../models/CourseProgress');
const LiveSession = require('../models/LiveSession');
const LiveSessionLog = require('../models/LiveSessionLog');
const SessionLog = require('../models/SessionLog');
const LearningActivity = require('../models/LearningActivity');
const AIQuiz = require('../models/AIQuiz');
const QuizAttempt = require('../models/QuizAttempt');
const Staff = require('../models/Staff');

// Validate MongoDB ObjectId (24 hex characters) to avoid CastError and return clear 400
const isValidObjectId = (id) => {
    if (id == null || typeof id !== 'string') return false;
    const s = id.trim();
    return s.length === 24 && /^[0-9a-fA-F]{24}$/.test(s);
};

// Helper: get staff ID from request (LMS uses Staff id for employeeId in CourseProgress/QuizAttempt)
const getStaffId = (req) => {
    const id = req.staff?._id || req.user?._id;
    return id ? (typeof id === 'string' ? id : id.toString()) : null;
};

// Helper: get Staff id for LMS (CourseProgress/QuizAttempt use employeeId = Staff id). Resolve from user when needed so web and app match.
const getLmsStaffId = async (req) => {
    if (req.staff?._id) {
        const id = (typeof req.staff._id === 'string' ? req.staff._id : req.staff._id.toString());
        console.log('[LMS getLmsStaffId] from req.staff:', id);
        return id;
    }
    if (req.user?._id) {
        const staff = await Staff.findOne({ userId: req.user._id }).select('_id').lean();
        if (staff) {
            console.log('[LMS getLmsStaffId] from Staff userId lookup:', staff._id?.toString());
            return staff._id.toString();
        }
        console.log('[LMS getLmsStaffId] no Staff found for userId:', req.user._id);
    }
    return null;
};

// Build query filter for LMS collections: web backend may use userId, app uses employeeId. Query both so same DB shows same data.
const lmsUserFilter = (staffId, userId) => {
    const conditions = [];
    if (staffId) conditions.push({ employeeId: staffId });
    if (userId) conditions.push({ userId: userId });
    if (conditions.length === 0) return null;
    return conditions.length === 1 ? conditions[0] : { $or: conditions };
};

// Helper: get businessId
const getBusinessId = (req) => req.staff?.businessId || req.user?.companyId;

// GET /lms/courses - List all published courses (for library)
const getAllCourses = async (req, res) => {
    try {
        const courses = await Course.find({ status: 'Published' }).sort({ createdAt: -1 }).limit(50);
        res.json({ success: true, data: courses });
    } catch (err) {
        console.error('[LMS] getAllCourses error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/courses/:id/enroll - Self-enroll in course
const enrollCourse = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        const { id } = req.params;
        if (!filter) return res.status(401).json({ success: false, message: 'Unauthorized' });

        const course = await Course.findById(id);
        if (!course || course.status !== 'Published') return res.status(404).json({ success: false, message: 'Course not found' });

        let progress = await CourseProgress.findOne({ courseId: id, ...filter });
        if (progress) return res.json({ success: true, data: progress });

        progress = await CourseProgress.create({
            courseId: id,
            employeeId: staffId || undefined,
            userId: userId || undefined,
            status: 'Not Started',
            contentProgress: [],
            completedLessons: [],
            businessId: getBusinessId(req),
        });
        res.status(201).json({ success: true, data: progress });
    } catch (err) {
        console.error('[LMS] enrollCourse error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// GET /lms/my-courses - Employee's enrolled courses (query by employeeId or userId so web and app see same data)
// Why "only 1 course" when courseprogresses has 5 for this staff?
// 1) Query identity: filter uses staffId (from req.staff or Staff.findOne({ userId })) OR userId. If app sends different user/staff, only docs matching that identity are returned.
// 2) Missing course: .populate('courseId') can be null if the course was deleted. We .filter(p => p.courseId) so progress rows with missing/invalid courseId are dropped and never shown.
const getMyCourses = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        if (!filter) return res.status(401).json({ success: false, message: 'Unauthorized' });

        const progressList = await CourseProgress.find(filter)
            .populate('courseId')
            .sort({ updatedAt: -1 });

        const withNullCourse = progressList.filter(p => !p.courseId);
        if (withNullCourse.length > 0) {
            console.log('[LMS getMyCourses] filter=', JSON.stringify(filter), 'total progress=', progressList.length, 'dropped (courseId not in courses collection):', withNullCourse.length, 'progress _ids:', withNullCourse.map(p => p._id?.toString()));
        }

        const data = progressList
            .filter(p => p.courseId)
            .map(p => ({
                _id: p._id,
                courseId: p.courseId,
                status: p.status,
                completionPercentage: p.completionPercentage,
                lastAccessedAt: p.lastAccessedAt,
                timeSpent: p.timeSpent,
                createdAt: p.createdAt,
            }));

        res.json({ success: true, data });
    } catch (err) {
        console.error('[LMS] getMyCourses error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// GET /lms/courses/:id/details - Course details with progress (query by employeeId or userId for same data as web)
const getCourseDetails = async (req, res) => {
    try {
        const { id } = req.params;
        if (!isValidObjectId(id)) {
            return res.status(400).json({
                success: false,
                message: 'Invalid course ID. Course ID must be a 24-character hex string.',
            });
        }

        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;

        const course = await Course.findById(id);
        if (!course) return res.status(404).json({ success: false, message: 'Course not found' });

        let progress = null;
        const userFilter = lmsUserFilter(staffId, userId);
        if (userFilter) {
            progress = await CourseProgress.findOne({ courseId: id, ...userFilter });
        }

        
        res.json({ success: true, data: { course, progress } });
    } catch (err) {
        if (err.name === 'CastError') {
            return res.status(400).json({
                success: false,
                message: 'Invalid course ID format.',
            });
        }
        console.error('[LMS] getCourseDetails error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// GET /lms/courses/:id/my-progress
const getMyProgress = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        const { id } = req.params;
        if (!filter) return res.status(401).json({ success: false, message: 'Unauthorized' });

        const progress = await CourseProgress.findOne({ courseId: id, ...filter });
        res.json({ success: true, data: progress || {} });
    } catch (err) {
        console.error('[LMS] getMyProgress error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/courses/:id/complete-lesson - Mark lesson complete (by lessonTitle)
// Web may send lessonId (alias for lessonTitle) for compatibility
const completeLesson = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        const { id } = req.params;
        const { lessonTitle, lessonId } = req.body || {};
        const lesson = lessonTitle || lessonId;
        if (!filter || !lesson) return res.status(400).json({ success: false, message: 'Missing lessonTitle or lessonId' });

        let progress = await CourseProgress.findOne({ courseId: id, ...filter });
        if (!progress) {
            progress = await CourseProgress.create({
                courseId: id,
                employeeId: staffId || undefined,
                userId: userId || undefined,
                status: 'In Progress',
                contentProgress: [],
                completedLessons: [lesson],
                completionPercentage: 0,
            });
        } else {
            if (!progress.completedLessons.includes(lesson)) {
                progress.completedLessons.push(lesson);
                await progress.save();
            }
        }

        const course = await Course.findById(id);
        const allMaterials = [...(course?.materials || []), ...(course?.contents || [])];
        const lessonMaterials = allMaterials.filter(m => (m.lessonTitle || 'Course Materials') === lesson);
        for (const m of lessonMaterials) {
            const existing = progress.contentProgress.find(p => String(p.contentId) === String(m._id));
            if (!existing) {
                progress.contentProgress.push({ contentId: m._id, viewed: true, viewedAt: new Date() });
            } else if (!existing.viewed) {
                existing.viewed = true;
                existing.viewedAt = new Date();
            }
        }
        const total = allMaterials.length;
        const viewed = progress.contentProgress.filter(p => p.viewed).length;
        progress.completionPercentage = total > 0 ? Math.round((viewed / total) * 100) : 0;
        progress.status = progress.completionPercentage >= 100 ? 'Completed' : 'In Progress';
        progress.lastAccessedAt = new Date();
        await progress.save();

        res.json({ success: true, data: progress });
    } catch (err) {
        console.error('[LMS] completeLesson error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/courses/:id/progress - Update content progress
const updateProgress = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        const { id } = req.params;
        const { contentId, completed, watchTime } = req.body;
        if (!filter || !contentId) return res.status(400).json({ success: false, message: 'Missing contentId' });

        let progress = await CourseProgress.findOne({ courseId: id, ...filter });
        if (!progress) {
            progress = await CourseProgress.create({
                courseId: id,
                employeeId: staffId || undefined,
                userId: userId || undefined,
                status: 'In Progress',
                contentProgress: [],
                completedLessons: [],
            });
        }

        let entry = progress.contentProgress.find(p => String(p.contentId) === String(contentId));
        if (!entry) {
            progress.contentProgress.push({
                contentId,
                viewed: !!completed,
                viewedAt: completed ? new Date() : undefined,
            });
        } else {
            entry.viewed = completed !== undefined ? completed : entry.viewed;
            entry.viewedAt = completed ? new Date() : entry.viewedAt;
        }
        if (watchTime) progress.timeSpent = (progress.timeSpent || 0) + watchTime;
        progress.lastAccessedAt = new Date();

        const course = await Course.findById(id);
        const total = (course?.materials?.length || 0) + (course?.contents?.length || 0);
        const viewed = progress.contentProgress.filter(p => p.viewed).length;
        progress.completionPercentage = total > 0 ? Math.round((viewed / total) * 100) : 0;
        progress.status = progress.completionPercentage >= 100 ? 'Completed' : 'In Progress';
        await progress.save();

        res.json({ success: true, data: progress });
    } catch (err) {
        console.error('[LMS] updateProgress error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// --- Live Sessions ---

// GET /lms/my-sessions - Employee's live sessions
const getMySessions = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        if (!staffId) return res.status(401).json({ success: false, message: 'Unauthorized' });

        const staff = await Staff.findById(staffId);
        const departmentId = staff?.department;
        const query = { status: { $ne: 'Cancelled' } };

        const orConditions = [
            { assignmentType: 'All' },
            { assignedEmployees: staffId },
        ];
        if (departmentId) orConditions.push({ assignmentType: 'Department', departments: departmentId });
        query.$or = orConditions;

        const sessions = await LiveSession.find(query)
            .populate('trainerId', 'name')
            .populate('assignedEmployees', 'name')
            .sort({ dateTime: 1 });

        const sessionLogs = await SessionLog.find({ employeeId: staffId }).lean();
        const logMap = Object.fromEntries(sessionLogs.map(l => [String(l.sessionId), l]));

        const data = sessions.map(s => {
            const log = logMap[s._id.toString()];
            return {
                ...s.toObject(),
                mySessionLog: log,
                myAttendance: log,
            };
        });

        res.json({ success: true, data });
    } catch (err) {
        console.error('[LMS] getMySessions error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/sessions - Create session
const createSession = async (req, res) => {
    try {
        const staffId = getStaffId(req);
        const userId = req.user?._id;
        if (!staffId) return res.status(401).json({ success: false, message: 'Unauthorized' });

        const staff = await Staff.findById(staffId);
        const {
            title, description, agenda, category, platform, meetingLink,
            dateTime, duration, assignmentType, departments, assignedEmployees,
        } = req.body;

        const session = await LiveSession.create({
            title,
            description,
            agenda,
            category: category || 'Normal Session',
            platform: platform || 'Google Meet',
            meetingLink,
            dateTime: dateTime ? new Date(dateTime) : new Date(),
            duration: duration || 60,
            assignmentType: assignmentType || 'All',
            departments: departments || [],
            assignedEmployees: assignedEmployees || [],
            trainerId: staffId,
            trainerName: staff?.name || 'Host',
            createdBy: userId,
            businessId: getBusinessId(req),
        });

        res.status(201).json({ success: true, data: session });
    } catch (err) {
        console.error('[LMS] createSession error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// PUT /lms/sessions/:id - Update session
const updateSession = async (req, res) => {
    try {
        const { id } = req.params;
        const { title, description, agenda, dateTime, duration, meetingLink, status, recordingUrl } = req.body;

        const session = await LiveSession.findByIdAndUpdate(id, {
            ...(title && { title }),
            ...(description !== undefined && { description }),
            ...(agenda !== undefined && { agenda }),
            ...(dateTime && { dateTime: new Date(dateTime) }),
            ...(duration !== undefined && { duration }),
            ...(meetingLink !== undefined && { meetingLink }),
            ...(status && { status }),
            ...(recordingUrl !== undefined && { recordingUrl }),
        }, { new: true });

        if (!session) return res.status(404).json({ success: false, message: 'Session not found' });
        res.json({ success: true, data: session });
    } catch (err) {
        console.error('[LMS] updateSession error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// DELETE /lms/sessions/:id
const deleteSession = async (req, res) => {
    try {
        const { id } = req.params;
        const session = await LiveSession.findByIdAndDelete(id);
        if (!session) return res.status(404).json({ success: false, message: 'Session not found' });
        res.json({ success: true });
    } catch (err) {
        console.error('[LMS] deleteSession error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/my-sessions/:id/join
const joinSession = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const { id } = req.params;
        if (!staffId) return res.status(401).json({ success: false, message: 'Unauthorized' });

        await SessionLog.findOneAndUpdate(
            { sessionId: id, employeeId: staffId },
            { $set: { joinedAt: new Date(), left: false } },
            { upsert: true }
        );
        res.json({ success: true });
    } catch (err) {
        console.error('[LMS] joinSession error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/my-sessions/:id/leave
const leaveSession = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const { id } = req.params;
        const { feedbackSummary, issues, rating } = req.body || {};
        if (!staffId) return res.status(401).json({ success: false, message: 'Unauthorized' });

        await SessionLog.findOneAndUpdate(
            { sessionId: id, employeeId: staffId },
            { $set: { left: true, leftAt: new Date(), feedbackSummary, issues, rating } },
            { upsert: true }
        );
        res.json({ success: true });
    } catch (err) {
        console.error('[LMS] leaveSession error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// --- Learning Engine ---

// GET /lms/learning-engine — heatmap from ALL sources (same as web backend): LearningActivity, QuizAttempt, AIQuiz submitted, CourseProgress views, SessionLog (live sessions)
const getLearningEngine = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        if (!filter) return res.status(401).json({ success: false, message: 'Unauthorized' });

        const start = new Date(Date.now() - 371 * 24 * 60 * 60 * 1000);
        const end = new Date();
        const toKey = (d) => d.toISOString().slice(0, 10);

        // Aggregate by date: same shape as web (totalMinutes, lessonsCompleted, quizzesAttempted, assessmentsAttempted, liveSessionsAttended)
        const byDate = new Map();
        const init = (key) => {
            if (!byDate.has(key)) byDate.set(key, { totalMinutes: 0, lessonsCompleted: 0, quizzesAttempted: 0, assessmentsAttempted: 0, liveSessionsAttended: 0 });
        };

        // Source 1: LearningActivity (explicit logging)
        const activities = await LearningActivity.find({
            ...filter,
            date: { $gte: start, $lte: end },
        }).sort({ date: 1 }).lean();
        activities.forEach((a) => {
            const key = toKey(a.date);
            init(key);
            const e = byDate.get(key);
            e.totalMinutes += a.totalMinutes || 0;
            e.lessonsCompleted += a.lessonsCompleted || 0;
            e.quizzesAttempted += a.quizzesAttempted || 0;
            e.assessmentsAttempted += a.assessmentsAttempted || 0;
            e.liveSessionsAttended += a.liveSessionsAttended || 0;
        });

        // Source 2: QuizAttempt (app practice quizzes)
        const quizAttempts = await QuizAttempt.find({
            ...filter,
            createdAt: { $gte: start, $lte: end },
        }).select('createdAt').lean();
        quizAttempts.forEach((q) => {
            if (!q.createdAt) return;
            const key = toKey(q.createdAt);
            init(key);
            byDate.get(key).quizzesAttempted += 1;
        });

        // Source 3: AIQuiz submitted (same as web — counts toward heatmap quizzes)
        const aiQuizzesSubmitted = await AIQuiz.find({
            ...filter,
            status: 'Submitted',
            submittedAt: { $exists: true, $ne: null, $gte: start, $lte: end },
        }).select('submittedAt').lean();
        aiQuizzesSubmitted.forEach((q) => {
            if (!q.submittedAt) return;
            const key = toKey(q.submittedAt);
            init(key);
            byDate.get(key).quizzesAttempted += 1;
        });

        // Source 4a: LiveSessionLog (web backend collection — same as learningEngine.controller.ts)
        if (staffId) {
            const liveLogFilter = {
                employeeId: staffId,
                joinedAt: { $gte: start, $lte: end },
            };
            const businessId = getBusinessId(req);
            if (businessId) liveLogFilter.businessId = businessId;
            const liveSessionLogs = await LiveSessionLog.find(liveLogFilter).select('joinedAt').lean();
            liveSessionLogs.forEach((l) => {
                if (!l.joinedAt) return;
                const key = toKey(l.joinedAt);
                init(key);
                byDate.get(key).liveSessionsAttended += 1;
            });
            // Source 4b: SessionLog (app-originated joins; add to same count)
            const sessionLogs = await SessionLog.find({
                employeeId: staffId,
                joinedAt: { $gte: start, $lte: end },
            }).select('joinedAt').lean();
            sessionLogs.forEach((l) => {
                if (!l.joinedAt) return;
                const key = toKey(l.joinedAt);
                init(key);
                byDate.get(key).liveSessionsAttended += 1;
            });
        }

        // Source 5: CourseProgress contentProgress.viewedAt (lessons/content viewed)
        const progressList = await CourseProgress.find({
            ...filter,
            'contentProgress.viewedAt': { $gte: start, $lte: end },
        }).select('contentProgress.viewedAt').lean();
        progressList.forEach((p) => {
            (p.contentProgress || []).forEach((cp) => {
                if (cp.viewedAt) {
                    const key = toKey(cp.viewedAt);
                    if (key >= toKey(start) && key <= toKey(end)) {
                        init(key);
                        const e = byDate.get(key);
                        e.lessonsCompleted += 1;
                        e.totalMinutes = (e.totalMinutes || 0) + 5;
                    }
                }
            });
        });

        // Build heatmap array with activityScore and activityLevel (same shape as web hrms.askeva.net/api/lms/learning-engine)
        const heatmap = Array.from(byDate.entries()).map(([date, agg]) => {
            const activityScore = (agg.totalMinutes || 0) * 1 + (agg.lessonsCompleted || 0) * 10 +
                (agg.quizzesAttempted || 0) * 15 + (agg.assessmentsAttempted || 0) * 20 + (agg.liveSessionsAttended || 0) * 20;
            let activityLevel = 'none';
            if (activityScore > 60) activityLevel = 'high';
            else if (activityScore > 40) activityLevel = 'medium';
            else if (activityScore > 0) activityLevel = 'low';
            return {
                date,
                totalMinutes: agg.totalMinutes || 0,
                lessonsCompleted: agg.lessonsCompleted || 0,
                quizzesAttempted: agg.quizzesAttempted || 0,
                assessmentsAttempted: agg.assessmentsAttempted || 0,
                liveSessionsAttended: agg.liveSessionsAttended || 0,
                activityScore,
                activityLevel,
            };
        });

        const nowDate = new Date();
        const todayStr = nowDate.toISOString().slice(0, 10);

        // Same response shape as web: dailyGoal, skills, heatmap, frictionCourses, recommendations, performanceMatrix, scoreHistory, readiness
        const dailyGoal = {
            date: nowDate.toISOString(),
            targetMinutes: 30,
            currentMinutes: 0,
            tasksCompleted: 0,
            tasksTarget: 3,
            streakDays: 0,
            longestStreak: 0,
            streakFrozen: false,
            status: 'pending',
            message: 'Start a streak today!',
        };

        const skills = [
            { skillId: 's1', name: 'Compliance', competence: 90, confidence: 100, gap: 0, category: 'Domain' },
            { skillId: 's2', name: 'Technical', competence: 60, confidence: 50, gap: 20, category: 'Technical' },
        ];

        const readiness = {
            targetRole: 'Employee',
            currentScore: 65,
            missingSkills: ['Advanced Compliance'],
            nextMilestone: 'Complete Training',
        };

        res.json({
            success: true,
            dailyGoal,
            skills,
            heatmap,
            frictionCourses: [],
            recommendations: [],
            performanceMatrix: [],
            scoreHistory: [],
            thisWeekMinutes: 0,
            lastWeekMinutes: 0,
            readiness,
        });
    } catch (err) {
        console.error('[LMS] getLearningEngine error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// Helper: compute due date from completionDuration and start date
function addDuration(startDate, duration) {
    if (!duration || !duration.value || !duration.unit) return null;
    const d = new Date(startDate);
    const v = Number(duration.value) || 0;
    switch (String(duration.unit)) {
        case 'Days': d.setDate(d.getDate() + v); break;
        case 'Weeks': d.setDate(d.getDate() + v * 7); break;
        case 'Months': d.setMonth(d.getMonth() + v); break;
        default: return null;
    }
    return d;
}

// GET /lms/analytics/my-scores — same response shape as web (summary, courses, quizStats); query by employeeId or userId
const getMyScores = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        console.log('[LMS getMyScores] staffId=', staffId, 'userId=', userId, 'filter=', JSON.stringify(filter));
        if (!filter) return res.status(401).json({ success: false, message: 'Unauthorized' });

        const progressList = await CourseProgress.find(filter)
            .populate('courseId')
            .lean();

        const totalCourses = progressList.length;
        const completedCourses = progressList.filter(p => p.status === 'Completed').length;
        const inProgress = progressList.filter(p => p.status === 'In Progress').length;
        const overallScore = totalCourses > 0
            ? Math.round(progressList.reduce((s, p) => s + (p.completionPercentage || 0), 0) / totalCourses)
            : 0;

        const now = new Date();
        const courses = progressList.map(p => {
            const course = p.courseId;
            const start = p.createdAt ? new Date(p.createdAt) : new Date();
            const dueDate = course?.completionDuration ? addDuration(start, course.completionDuration) : null;
            const daysRemaining = dueDate
                ? Math.ceil((dueDate.getTime() - now.getTime()) / (24 * 60 * 60 * 1000))
                : null;
            const dueDateStr = dueDate ? dueDate.toISOString().slice(0, 10) : null;
            return {
                courseId: course?._id,
                title: course?.title,
                category: course?.category ?? null,
                status: p.status,
                progress: p.completionPercentage || 0,
                assessmentStatus: p.assessmentStatus ?? 'Not Started',
                assessmentScore: p.assessmentScore ?? null,
                timeSpentMinutes: p.timeSpent ?? 0,
                dueDate: dueDateStr,
                daysRemaining,
                completedAt: p.status === 'Completed' ? p.updatedAt : null,
                openedAt: p.lastAccessedAt || p.createdAt,
            };
        });

        // Quiz stats: use aiquizzes (AIQuiz) same as web — totalAssigned = AIQuiz count, totalCompleted = status === 'Submitted'
        const aiQuizzes = await AIQuiz.find(filter).select('difficulty status').lean();
        console.log('[LMS getMyScores] aiQuizzes.length=', aiQuizzes.length, 'docs=', aiQuizzes.map(q => ({ difficulty: q.difficulty, status: q.status })));

        const quizAttempts = await QuizAttempt.find(filter)
            .populate('quizId')
            .lean();
        console.log('[LMS getMyScores] quizAttempts.length=', quizAttempts.length, 'rawAttempts=', quizAttempts.length ? quizAttempts.map(a => ({ quizId: a.quizId?._id, employeeId: a.employeeId, userId: a.userId, passed: a.passed })) : []);

        let totalAssigned, totalCompleted, completionPercent, easy, medium, hard;

        if (aiQuizzes.length > 0) {
            // Same logic as web: use aiquizzes collection
            totalAssigned = aiQuizzes.length;
            totalCompleted = aiQuizzes.filter(q => (q.status || '').toString() === 'Submitted').length;
            completionPercent = totalAssigned > 0 ? Math.round((totalCompleted / totalAssigned) * 100) : 0;
            const normalizeDiff = (d) => (d === 'Difficult' ? 'Hard' : (d || 'Medium'));
            const byDiff = { Easy: { total: 0, completed: 0 }, Medium: { total: 0, completed: 0 }, Hard: { total: 0, completed: 0 } };
            aiQuizzes.forEach((q) => {
                const key = normalizeDiff(q.difficulty);
                if (byDiff[key]) {
                    byDiff[key].total += 1;
                    if ((q.status || '').toString() === 'Submitted') byDiff[key].completed += 1;
                }
            });
            const toStat = (o) => ({
                total: o.total,
                completed: o.completed,
                percent: o.total > 0 ? Math.round((o.completed / o.total) * 100) : 0,
                beatsPercent: 0,
            });
            easy = toStat(byDiff.Easy);
            medium = toStat(byDiff.Medium);
            hard = toStat(byDiff.Hard);
        } else {
            // Fallback: from QuizAttempt (app-only when no AIQuiz docs)
            const byDiff = { Easy: new Map(), Medium: new Map(), Hard: new Map() };
            for (const a of quizAttempts) {
                const qid = a.quizId?._id?.toString();
                if (!qid) continue;
                const diff = (a.quizId?.difficulty || 'Medium').trim();
                const key = byDiff[diff] || byDiff.Medium;
                if (!key.has(qid)) key.set(qid, { completed: false });
                if (a.passed !== undefined && a.passed !== null) key.get(qid).completed = true;
            }
            const toStat = (m) => {
                const total = m.size;
                const completed = [...m.values()].filter((x) => x.completed).length;
                return { total, completed, percent: total > 0 ? Math.round((completed / total) * 100) : 0, beatsPercent: 0 };
            };
            const uniqueQuizzes = new Set(quizAttempts.map((a) => a.quizId?._id?.toString()).filter(Boolean));
            totalAssigned = uniqueQuizzes.size;
            totalCompleted = [...uniqueQuizzes].filter((qid) =>
                quizAttempts.some((a) => a.quizId?._id?.toString() === qid && a.passed !== undefined && a.passed !== null)
            ).length;
            completionPercent = totalAssigned > 0 ? Math.round((totalCompleted / totalAssigned) * 100) : 0;
            easy = toStat(byDiff.Easy);
            medium = toStat(byDiff.Medium);
            hard = toStat(byDiff.Hard);
        }

        console.log('[LMS getMyScores] quizStats: totalAssigned=', totalAssigned, 'totalCompleted=', totalCompleted, 'source=', aiQuizzes.length > 0 ? 'AIQuiz' : 'QuizAttempt');

        res.json({
            success: true,
            data: {
                summary: {
                    totalCourses,
                    completedCourses,
                    inProgress,
                    overallScore,
                    passedAssessments: totalCompleted,
                    failedAssessments: totalAssigned - totalCompleted,
                },
                courses,
                quizStats: {
                    totalAssigned,
                    totalCompleted,
                    completionPercent,
                    easy,
                    medium,
                    hard,
                },
            },
        });
    } catch (err) {
        console.error('[LMS] getMyScores error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// --- AI Quiz ---

// Extract YouTube video ID from common URL formats (for transcript fetch)
function getYouTubeVideoId(url) {
    if (!url || typeof url !== 'string') return null;
    const u = url.trim();
    const m = u.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/);
    return m ? m[1] : null;
}

// Fetch YouTube transcript for a video ID or URL; returns plain text or null
async function fetchYouTubeTranscript(videoIdOrUrl) {
    try {
        const { YoutubeTranscript } = await import('youtube-transcript');
        const list = await YoutubeTranscript.fetchTranscript(videoIdOrUrl);
        if (Array.isArray(list) && list.length > 0) {
            return list.map((item) => item.text).join(' ');
        }
    } catch (err) {
        console.log('[LMS] YouTube transcript fetch failed:', err.message);
    }
    return null;
}

// POST /lms/ai-quiz/generate
// Uses GEMINI_API_KEY from .env when available for AI-generated questions based on lesson content.
// For VIDEO/YOUTUBE materials, fetches YouTube transcript when content is missing so quiz is based on video.
const generateAIQuiz = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const { courseId, lessonTitles, questionCount, difficulty, materialId, materialIds } = req.body;
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        if ((!staffId && !userId) || !courseId) return res.status(400).json({ success: false, message: 'Missing courseId' });

        const geminiKey = process.env.GEMINI_API_KEY;
        const geminiModel = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
        const count = Math.min(parseInt(questionCount, 10) || 5, 50);
        let questions = [];
        console.log('[LMS generateAIQuiz] courseId=', courseId, 'staffId=', staffId, 'userId=', userId);

        const course = await Course.findById(courseId).lean();
        let materials = course?.materials || course?.contents || [];
        const lessons = course?.lessons || [];
        // If no top-level materials, flatten from lessons so we can fetch transcript for video lessons
        if (materials.length === 0 && lessons?.length) {
            materials = lessons.flatMap((l) => (l.materials || []).map((m) => ({ ...m, lessonTitle: l.title || m.lessonTitle || m.title })));
        }
        const materialsList = materials.map((m, i) => ({
            _id: m._id,
            order: i + 1,
            type: m.type || 'URL',
            title: m.title || m.lessonTitle || 'Untitled',
            lessonTitle: m.lessonTitle || m.title,
            url: m.url || m.filePath || m.link,
            content: m.content || m.description || '',
        }));

        // Enrich VIDEO/YOUTUBE materials with transcript when content is empty
        for (const m of materialsList) {
            const isVideo = (m.type || '').toUpperCase() === 'VIDEO' || (m.type || '').toUpperCase() === 'YOUTUBE';
            const hasNoContent = !(m.content && String(m.content).trim());
            if (isVideo && hasNoContent && m.url) {
                const ytId = getYouTubeVideoId(m.url);
                if (ytId) {
                    const transcript = await fetchYouTubeTranscript(ytId);
                    if (transcript) {
                        m.content = transcript;
                        console.log('[LMS generateAIQuiz] YouTube transcript loaded for', m.lessonTitle || m.title, 'length=', transcript.length);
                    }
                }
            }
        }

        // When app sends materialIds (from selected lessons), use exactly those materials for the quiz.
        const idSet = Array.isArray(materialIds) && materialIds.length
            ? new Set(materialIds.map((id) => String(id)))
            : null;
        const relevanceFilter = idSet
            ? materialsList.filter((m) => m._id && idSet.has(String(m._id)))
            : (lessonTitles?.length
                ? materialsList.filter((m) => {
                    const mt = String(m.lessonTitle || '').trim().toLowerCase();
                    return lessonTitles.some((t) => {
                        const tt = String(t || '').trim().toLowerCase();
                        return tt && (mt.includes(tt) || mt === tt || tt.includes(mt));
                    });
                })
                : materialsList);
        if (idSet && relevanceFilter.length === 0) {
            console.log('[LMS generateAIQuiz] materialIds sent but no materials matched: materialIds=', materialIds?.length, 'materialsList=', materialsList?.length);
            return res.status(400).json({
                success: false,
                message: 'Selected lesson materials could not be found. Please try again.',
            });
        }
        const materialFocus = materialId
            ? materialsList.find((m) => m._id && String(m._id) === String(materialId)) || relevanceFilter[0]
            : relevanceFilter[0];

        // Align with web (hrms.askeva.net): allow quiz when we have text/transcript OR YouTube URLs.
        // Web sends YouTube URLs to Gemini as fileData so Gemini analyzes video directly (no transcript needed).
        let materialsForPrompt = relevanceFilter.length ? relevanceFilter : materialsList;
        if (materialFocus && materialsForPrompt.length > 1) {
            const focusFirst = [materialFocus, ...materialsForPrompt.filter((m) => m._id && String(m._id) !== String(materialFocus._id))];
            materialsForPrompt = focusFirst;
        }
        const materialsWithText = materialsForPrompt.filter((m) => m.content && String(m.content).trim());
        const youtubeMaterials = materialsForPrompt.filter((m) => {
            const type = (m.type || '').toUpperCase();
            if (type !== 'VIDEO' && type !== 'YOUTUBE') return false;
            const url = (m.url || '').trim();
            return url && getYouTubeVideoId(url);
        });
        const hasContent = materialsWithText.length > 0 || youtubeMaterials.length > 0;
        if (!hasContent) {
            console.log('[LMS generateAIQuiz] No lesson content: materialsWithText=0, youtubeMaterials=0, materialsForPrompt=', materialsForPrompt?.length);
            return res.status(400).json({
                success: false,
                message: 'Selected lessons have no text or transcript available. Use lessons with video captions (e.g. YouTube) or text content to generate a quiz.',
            });
        }
        const lessonContentBlocks = [];
        for (const m of materialsWithText) {
            const lessonTitle = m.lessonTitle || m.title || 'Course Materials';
            const block = `Lesson: ${lessonTitle}\nMaterial: ${m.title || 'Untitled'} (${m.type || 'URL'})\nContent:\n${String(m.content).trim()}`;
            lessonContentBlocks.push(block);
        }
        const fullLessonContent = lessonContentBlocks.join('\n\n');

        if (geminiKey && geminiKey.trim()) {
            try {
                const { GoogleGenAI } = await import('@google/genai');
                const ai = new GoogleGenAI({ apiKey: geminiKey });
                const instructionStart = `You are a quiz generator. Generate exactly ${count} quiz questions based ONLY on the learning content provided (text and/or videos below).
RULES:
- Each question must be answerable from the lesson content (text or video). Test facts, concepts, and details from the content.
- Do NOT ask about "course description", "qualification", "attendance", "participation", or metadata.
- Difficulty: ${difficulty || 'Medium'}.
- Return ONLY a valid JSON array. Each item: question, type ("multiple-choice" or "true-false"), options (4 for mc, ["True","False"] for tf), correctAnswer, points:1.`;
                const instructionEnd = `Return JSON array format: [{"question":"...","type":"multiple-choice","options":["A","B","C","D"],"correctAnswer":"A","points":1}]`;

                let response;
                if (youtubeMaterials.length > 0) {
                    // Web-style: pass YouTube URLs to Gemini so it analyzes video directly (no transcript required)
                    const parts = [];
                    for (const m of youtubeMaterials) {
                        const url = (m.url || '').trim();
                        if (!url) continue;
                        parts.push({
                            fileData: {
                                fileUri: url,
                                mimeType: 'video/*',
                            },
                        });
                        parts.push({
                            text: `YouTube video titled "${m.title || m.lessonTitle || 'Video'}". Analyze its content for the quiz.`,
                        });
                    }
                    const textContent = fullLessonContent
                        ? `\n\nText/transcript content:\n${fullLessonContent}\n\n`
                        : '';
                    parts.push({
                        text: `${instructionStart}${textContent}\n${instructionEnd}`,
                    });
                    response = await ai.models.generateContent({
                        model: geminiModel,
                        contents: [{ role: 'user', parts }],
                        config: { maxOutputTokens: 2048 },
                    });
                } else {
                    const prompt = `${instructionStart}

LEARNING CONTENT (use only this for questions):
${fullLessonContent}

${instructionEnd}`;
                    response = await ai.models.generateContent({
                        model: geminiModel,
                        contents: prompt,
                        config: { maxOutputTokens: 2048 },
                    });
                }
                const text = response?.text?.trim?.() || '';
                const jsonMatch = text.match(/\[[\s\S]*\]/);
                if (jsonMatch) {
                    const parsed = JSON.parse(jsonMatch[0]);
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        questions = parsed.slice(0, count).map((q, idx) => ({
                            question: String(q.question || '').trim() || `Question ${idx + 1}`,
                            type: ['multiple-choice', 'true-false'].includes(q.type) ? q.type : 'multiple-choice',
                            options: Array.isArray(q.options) ? q.options.map(String) : ['Option A', 'Option B', 'Option C', 'Option D'],
                            correctAnswer: q.correctAnswer != null ? String(q.correctAnswer) : (q.options && q.options[0] ? String(q.options[0]) : 'Option A'),
                            points: Math.max(1, parseInt(q.points, 10) || 1),
                            explanation: q.explanation || (q.correctAnswer != null ? `The correct answer is ${String(q.correctAnswer)}.` : ''),
                        }));
                    }
                }
            } catch (geminiErr) {
                console.error('[LMS] generateAIQuiz Gemini error:', geminiErr);
            }
        }

        if (questions.length === 0) {
            for (let i = 0; i < count; i++) {
                questions.push({
                    question: `Sample question ${i + 1} from ${(lessonTitles || [course?.title || 'course']).join(', ')}`,
                    type: 'multiple-choice',
                    options: ['Option A', 'Option B', 'Option C', 'Option D'],
                    correctAnswer: 'Option A',
                    points: 1,
                    explanation: 'The correct answer is Option A.',
                });
            }
        }

        const rawDiff = (difficulty || 'Medium').trim();
        const normalizedDifficulty = rawDiff === 'Hard' ? 'Difficult' : (['Easy', 'Medium', 'Difficult'].includes(rawDiff) ? rawDiff : 'Medium');
        const quizTitle = course?.title ? `Practice: ${course.title}` : 'Practice Quiz';

        const totalPoints = questions.reduce((s, q) => s + (q.points || 1), 0);
        const quiz = await AIQuiz.create({
            courseId,
            employeeId: staffId || undefined,
            userId: userId || undefined,
            lessonTitles: lessonTitles || [],
            difficulty: normalizedDifficulty,
            questionCount: questions.length,
            title: quizTitle,
            questions,
            totalPoints,
            passingScore: Math.ceil(totalPoints * 0.6),
            materialId,
            businessId: getBusinessId(req) || undefined,
        });
        console.log('[LMS generateAIQuiz] AIQuiz created: _id=', quiz._id, 'employeeId=', quiz.employeeId, 'userId=', quiz.userId);

        res.status(201).json({ success: true, data: quiz });
    } catch (err) {
        console.error('[LMS] generateAIQuiz error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// GET /lms/ai-quiz/:id
const getAIQuiz = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const { id } = req.params;
        const quiz = await AIQuiz.findById(id).populate('courseId', 'title');
        if (!quiz) return res.status(404).json({ success: false, message: 'Quiz not found' });
        const owns = (staffId && String(quiz.employeeId) === String(staffId)) || (userId && quiz.userId && String(quiz.userId) === String(userId));
        if (!owns) return res.status(403).json({ success: false, message: 'Forbidden' });
        res.json({ success: true, data: quiz });
    } catch (err) {
        console.error('[LMS] getAIQuiz error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/ai-quiz/:id/submit
const submitAIQuiz = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const { id } = req.params;
        const { responses, completionTime } = req.body || {};
        console.log('[LMS submitAIQuiz] quizId=', id, 'staffId=', staffId, 'userId=', userId, 'req.user=', req.user?._id, 'req.staff=', req.staff?._id);

        const quiz = await AIQuiz.findById(id);
        if (!quiz) return res.status(404).json({ success: false, message: 'Quiz not found' });
        const owns = (staffId && String(quiz.employeeId) === String(staffId)) || (userId && quiz.userId && String(quiz.userId) === String(userId));
        if (!owns) {
            console.log('[LMS submitAIQuiz] Forbidden: quiz.employeeId=', quiz.employeeId, 'quiz.userId=', quiz.userId);
            return res.status(403).json({ success: false, message: 'Forbidden' });
        }

        let earned = 0;
        const resolvedResponses = (responses || []).map((r, i) => {
            const q = quiz.questions[i];
            const correct = q && String(r.answer) === String(q.correctAnswer);
            if (correct) earned += q.points || 1;
            return {
                questionIndex: i,
                answer: r.answer ?? '',
                isCorrect: !!correct,
                resolvedCorrectAnswer: q?.correctAnswer != null ? String(q.correctAnswer) : undefined,
            };
        });
        const questionResults = (responses || []).map((r, i) => {
            const q = quiz.questions[i];
            const correct = q && String(r.answer) === String(q.correctAnswer);
            return {
                questionIndex: i,
                question: q?.question ?? `Question ${i + 1}`,
                userAnswer: r.answer ?? '',
                correct,
                correctAnswer: q?.correctAnswer != null ? String(q.correctAnswer) : '',
                rationale: q?.rationale ?? q?.explanation ?? (q?.correctAnswer != null ? `The correct answer is ${String(q.correctAnswer)}.` : null),
            };
        });
        const totalPoints = quiz.questions.reduce((s, q) => s + (q.points || 1), 0);
        const passed = earned >= (quiz.passingScore || Math.ceil(totalPoints * 0.6));

        const attemptDoc = {
            quizId: quiz._id,
            employeeId: staffId || undefined,
            userId: userId || undefined,
            responses: responses || [],
            score: earned,
            totalPoints,
            passed,
            completionTime,
        };
        await QuizAttempt.create(attemptDoc);
        await AIQuiz.findByIdAndUpdate(id, {
            $set: {
                status: 'Submitted',
                responses: resolvedResponses,
                score: earned,
                completionTime: completionTime ?? null,
                submittedAt: new Date(),
            },
        });
        console.log('[LMS submitAIQuiz] QuizAttempt created; AIQuiz updated (status, responses, score, completionTime, submittedAt)');

        const proficiency = totalPoints > 0 ? Math.round((earned / totalPoints) * 100) : 0;
        res.json({
            success: true,
            data: {
                score: earned,
                passed,
                totalPoints,
                earnedPoints: earned,
                proficiency,
                questionResults,
            },
        });
    } catch (err) {
        console.error('[LMS] submitAIQuiz error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/courses/:id/assessment/submit - Submit final assessment
const submitCourseAssessment = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        const { id: courseId } = req.params;
        const { answers } = req.body || {};
        if (!filter || !courseId) return res.status(400).json({ success: false, message: 'Missing courseId' });

        const course = await Course.findById(courseId).lean();
        if (!course) return res.status(404).json({ success: false, message: 'Course not found' });

        const assessmentQuestions = course.assessmentQuestions;
        if (!assessmentQuestions || !Array.isArray(assessmentQuestions)) {
            return res.status(400).json({ success: false, message: 'No assessment questions for this course' });
        }

        const flatQuestions = assessmentQuestions.flatMap((g) =>
            (g.questions || []).map((q) => ({ ...q, lessonTitle: g.lessonTitle }))
        );
        if (flatQuestions.length === 0) {
            return res.status(400).json({ success: false, message: 'No assessment questions' });
        }

        const answerMap = {};
        for (const a of answers || []) {
            if (a.questionId && Array.isArray(a.answers)) {
                answerMap[a.questionId] = a.answers;
            }
        }

        let totalMarks = 0;
        let earnedMarks = 0;
        const questionResults = [];

        for (const q of flatQuestions) {
            const qId = q.id ?? q._id?.toString();
            const marks = q.marks || 1;
            totalMarks += marks;
            const userAnswers = answerMap[qId] || [];
            const correctStrs = Array.isArray(q.correctAnswers)
                ? q.correctAnswers.map(String).sort()
                : [String(q.correctAnswers ?? '')];
            const userStrs = userAnswers.map(String).filter(Boolean).sort();
            const isCorrect = correctStrs.length === userStrs.length &&
                correctStrs.every((c, i) => (userStrs[i] ?? '') === c);
            if (isCorrect) earnedMarks += marks;
            questionResults.push({
                questionId: qId,
                correctAnswer: correctStrs.length === 1 ? correctStrs[0] : correctStrs,
                userAnswer: userStrs.length === 1 ? userStrs[0] : userStrs,
                isCorrect,
                marksAwarded: isCorrect ? marks : 0,
                marksTotal: marks,
            });
        }

        const passingScore = course.qualificationScore || 80;
        const score = totalMarks > 0 ? Math.round((earnedMarks / totalMarks) * 100) : 0;
        const passed = score >= passingScore;

        const progress = await CourseProgress.findOne({ courseId, ...filter });
        if (progress) {
            progress.assessmentStatus = passed ? 'Passed' : 'Failed';
            progress.assessmentScore = score;
            progress.assessmentAttempts = (progress.assessmentAttempts || 0) + 1;
            if (passed) progress.status = 'Completed';
            await progress.save();
        }

        res.json({
            success: true,
            data: {
                score,
                passed,
                totalPoints: totalMarks,
                earnedPoints: earnedMarks,
                questionResults,
            },
        });
    } catch (err) {
        console.error('[LMS] submitCourseAssessment error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// POST /lms/learning-engine/activity — log activity for heatmap (match web logLearningActivity)
const logLearningActivity = async (req, res) => {
    try {
        const staffId = await getLmsStaffId(req);
        const userId = req.user?._id ? (typeof req.user._id === 'string' ? req.user._id : req.user._id.toString()) : null;
        const filter = lmsUserFilter(staffId, userId);
        if (!filter) return res.status(401).json({ success: false, message: 'Unauthorized' });

        const body = req.body || {};
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        const totalMinutes = Math.max(0, Number(body.totalMinutes) || 0);
        const lessonsCompleted = Math.max(0, Number(body.lessonsCompleted) || 0);
        const quizzesAttempted = Math.max(0, Number(body.quizzesAttempted) || 0);
        const assessmentsAttempted = Math.max(0, Number(body.assessmentsAttempted) || 0);
        const liveSessionsAttended = Math.max(0, Number(body.liveSessionsAttended) || 0);

        const activityScore = totalMinutes * 1 + lessonsCompleted * 10 + quizzesAttempted * 15 +
            assessmentsAttempted * 20 + liveSessionsAttended * 20;

        let doc = await LearningActivity.findOne({ ...filter, date: today });
        const updatePayload = {
            $inc: {
                totalMinutes,
                lessonsCompleted,
                quizzesAttempted,
                assessmentsAttempted,
                liveSessionsAttended,
                activityScore,
            },
        };
        if (doc) {
            await LearningActivity.updateOne({ _id: doc._id }, updatePayload);
        } else {
            doc = await LearningActivity.create({
                employeeId: staffId || undefined,
                userId: userId || undefined,
                date: today,
                totalMinutes,
                lessonsCompleted,
                quizzesAttempted,
                assessmentsAttempted,
                liveSessionsAttended,
                activityScore: totalMinutes * 1 + lessonsCompleted * 10 + quizzesAttempted * 15 +
                    assessmentsAttempted * 20 + liveSessionsAttended * 20,
            });
        }

        res.json({ success: true });
    } catch (err) {
        console.error('[LMS] logLearningActivity error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// --- Departments & Employees (for schedule modal) ---

// GET /lms/departments
const getDepartments = async (req, res) => {
    try {
        const departments = await Staff.distinct('department').then(arr =>
            arr.filter(Boolean).map(name => ({ _id: name, name }))
        );
        res.json({ success: true, data: { departments } });
    } catch (err) {
        console.error('[LMS] getDepartments error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// GET /lms/employees
const getEmployees = async (req, res) => {
    try {
        const staff = await Staff.find({ status: 'Active' })
            .select('name email')
            .limit(1000)
            .lean();
        res.json({ success: true, data: { staff } });
    } catch (err) {
        console.error('[LMS] getEmployees error:', err);
        res.status(500).json({ success: false, message: err.message });
    }
};

// GET /lms/categories
const getCategories = async (req, res) => {
    const categories = ['Development', 'Business', 'Design', 'Marketing', 'IT & Software', 'Personal Development', 'GENERAL'];
    res.json({ success: true, data: categories });
};

module.exports = {
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
    getDepartments,
    getEmployees,
    getCategories,
    submitCourseAssessment,
};
