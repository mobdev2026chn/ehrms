const mongoose = require('mongoose');
const PerformanceReview = require('../models/PerformanceReview');
const Staff = require('../models/Staff');
const Goal = require('../models/Goal');

/**
 * Get performance reviews - for employee app: myReviews=true returns only own reviews
 */
const getPerformanceReviews = async (req, res) => {
  try {
    const { status, reviewCycle, page = 1, limit = 20, myReviews } = req.query;
    const myReviewsFlag = String(myReviews) === 'true';
    const user = req.user;
    const staff = req.staff;

    const query = {};

    if (user?.companyId && mongoose.Types.ObjectId.isValid(user.companyId)) {
      query.businessId = new mongoose.Types.ObjectId(user.companyId);
    } else if (staff?.businessId && mongoose.Types.ObjectId.isValid(staff.businessId)) {
      query.businessId = new mongoose.Types.ObjectId(staff.businessId);
    }

    if (myReviewsFlag || !user?.role || user.role === 'Employee' || user.role === 'EmployeeAdmin') {
      const staffDoc = staff?._id ? await Staff.findById(staff._id) : await Staff.findOne({ userId: user?._id });
      if (!staffDoc) {
        return res.status(404).json({
          success: false,
          error: { message: 'Staff record not found' },
        });
      }
      query.employeeId = staffDoc._id;
    }

    if (reviewCycle) query.reviewCycle = reviewCycle;
    if (status) {
      if (typeof status === 'string' && status.includes(',')) {
        query.status = { $in: status.split(',').map((s) => s.trim()).filter(Boolean) };
      } else {
        query.status = status;
      }
    }

    const skip = (Number(page) - 1) * Number(limit);

    const reviews = await PerformanceReview.find(query)
      .populate('employeeId', 'name employeeId designation department email')
      .populate('managerId', 'name employeeId designation')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(Number(limit))
      .lean();

    const total = await PerformanceReview.countDocuments(query);

    res.json({
      success: true,
      data: {
        reviews,
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total,
          pages: Math.ceil(total / Number(limit)) || 1,
        },
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch performance reviews' },
    });
  }
};

/**
 * Get single performance review by ID
 */
const getPerformanceReviewById = async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: { message: 'Invalid review ID format' },
      });
    }

    const review = await PerformanceReview.findById(id)
      .populate('employeeId', 'name employeeId designation department email phone')
      .populate('managerId', 'name employeeId designation email')
      .populate('goalIds');

    if (!review) {
      return res.status(404).json({
        success: false,
        error: { message: 'Performance review not found' },
      });
    }

    const user = req.user;
    const staff = req.staff;
    const staffDoc = staff?._id ? await Staff.findById(staff._id) : await Staff.findOne({ userId: user?._id });

    if (staffDoc) {
      const reviewEmpId = review.employeeId?._id ?? review.employeeId;
      const empIdStr = (reviewEmpId && reviewEmpId.toString) ? reviewEmpId.toString() : String(reviewEmpId);
      const staffIdStr = (staffDoc._id && staffDoc._id.toString) ? staffDoc._id.toString() : String(staffDoc._id);
      if (empIdStr !== staffIdStr) {
        return res.status(403).json({
          success: false,
          error: { message: 'Access denied. You can only view your own performance reviews.' },
        });
      }
    }

    res.json({
      success: true,
      data: { review },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch performance review' },
    });
  }
};

/**
 * Submit self-review (employee)
 */
const submitSelfReview = async (req, res) => {
  try {
    const { id } = req.params;
    const { overallRating, strengths, areasForImprovement, achievements, challenges, goalsAchieved, comments } = req.body;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: { message: 'Invalid review ID format' },
      });
    }

    const review = await PerformanceReview.findById(id);
    if (!review) {
      return res.status(404).json({
        success: false,
        error: { message: 'Performance review not found' },
      });
    }

    const user = req.user;
    const staff = req.staff;
    const staffDoc = staff?._id ? await Staff.findById(staff._id) : await Staff.findOne({ userId: user?._id });
    if (!staffDoc) {
      return res.status(404).json({
        success: false,
        error: { message: 'Staff record not found' },
      });
    }

    const reviewEmpId = review.employeeId?.toString?.() || String(review.employeeId);
    const staffIdStr = staffDoc._id?.toString?.() || String(staffDoc._id);
    if (reviewEmpId !== staffIdStr) {
      return res.status(403).json({
        success: false,
        error: { message: 'Access denied. You can only submit your own self-review.' },
      });
    }

    review.selfReview = {
      overallRating: Number(overallRating) || 0,
      strengths: Array.isArray(strengths) ? strengths : [],
      areasForImprovement: Array.isArray(areasForImprovement) ? areasForImprovement : [],
      achievements: Array.isArray(achievements) ? achievements : [],
      challenges: Array.isArray(challenges) ? challenges : [],
      goalsAchieved: Array.isArray(goalsAchieved) ? goalsAchieved : [],
      comments: comments || '',
      submittedAt: new Date(),
    };
    review.status = 'self-review-submitted';
    await review.save();

    res.json({
      success: true,
      data: { review },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to submit self-review' },
    });
  }
};

/**
 * Create a self-assessment (employee-initiated). Unlike submitSelfReview (which fills a
 * review a manager/HR already created), this lets an employee start their own self review
 * for a chosen cycle. Creates a PerformanceReview owned by the employee with the self
 * review embedded and status 'self-review-submitted'.
 */
const createSelfAssessment = async (req, res) => {
  try {
    const user = req.user;
    const staff = req.staff;
    const staffDoc = staff?._id ? await Staff.findById(staff._id) : await Staff.findOne({ userId: user?._id });
    if (!staffDoc) {
      return res.status(404).json({
        success: false,
        error: { message: 'Staff record not found' },
      });
    }

    const {
      reviewCycle,
      reviewType = 'Custom',
      reviewPeriod,
      overallRating,
      strengths,
      areasForImprovement,
      achievements,
      challenges,
      goalsAchieved,
      comments,
    } = req.body;

    if (!reviewCycle || !String(reviewCycle).trim()) {
      return res.status(400).json({
        success: false,
        error: { message: 'reviewCycle is required' },
      });
    }
    const startDate = reviewPeriod?.startDate;
    const endDate = reviewPeriod?.endDate;
    if (!startDate || !endDate) {
      return res.status(400).json({
        success: false,
        error: { message: 'reviewPeriod.startDate and reviewPeriod.endDate are required' },
      });
    }

    const businessId = staffDoc.businessId
      || (mongoose.Types.ObjectId.isValid(user?.companyId) ? new mongoose.Types.ObjectId(user.companyId) : undefined);
    if (!businessId) {
      return res.status(400).json({
        success: false,
        error: { message: 'Unable to resolve business for this employee' },
      });
    }

    // Avoid duplicate self-assessment for the same cycle.
    const existing = await PerformanceReview.findOne({
      employeeId: staffDoc._id,
      reviewCycle: String(reviewCycle).trim(),
    });
    if (existing) {
      return res.status(409).json({
        success: false,
        error: { message: 'A review already exists for this cycle. Open it from My Reviews to update your self review.' },
      });
    }

    const review = await PerformanceReview.create({
      employeeId: staffDoc._id,
      reviewCycle: String(reviewCycle).trim(),
      reviewPeriod: { startDate: new Date(startDate), endDate: new Date(endDate) },
      reviewType,
      status: 'self-review-submitted',
      selfReview: {
        overallRating: Number(overallRating) || 0,
        strengths: Array.isArray(strengths) ? strengths : [],
        areasForImprovement: Array.isArray(areasForImprovement) ? areasForImprovement : [],
        achievements: Array.isArray(achievements) ? achievements : [],
        challenges: Array.isArray(challenges) ? challenges : [],
        goalsAchieved: Array.isArray(goalsAchieved) ? goalsAchieved : [],
        comments: comments || '',
        submittedAt: new Date(),
      },
      businessId,
      createdBy: user?._id || staffDoc.userId,
    });

    res.status(201).json({
      success: true,
      data: { review },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to create self-assessment' },
    });
  }
};

/**
 * Get employee performance summary (for My Performance overview)
 */
const getEmployeePerformanceSummary = async (req, res) => {
  try {
    const user = req.user;
    const staff = req.staff;
    const staffDoc = staff?._id ? await Staff.findById(staff._id) : await Staff.findOne({ userId: user?._id });

    if (!staffDoc) {
      return res.status(404).json({
        success: false,
        error: { message: 'Staff record not found' },
      });
    }

    const reviews = await PerformanceReview.find({ employeeId: staffDoc._id })
      .populate('managerId', 'name employeeId designation')
      .sort({ createdAt: -1 })
      .lean();

    const latestReview = reviews[0] || null;
    const completedReviews = reviews.filter((r) => r.status === 'completed' && r.finalRating);
    const avgRating =
      completedReviews.length > 0
        ? completedReviews.reduce((sum, r) => sum + (r.finalRating || 0), 0) / completedReviews.length
        : 0;

    const currentDate = new Date();
    const currentGoals = await Goal.countDocuments({
      employeeId: staffDoc._id,
      status: { $in: ['approved', 'pending'] },
      startDate: { $lte: currentDate },
      endDate: { $gte: currentDate },
    });

    res.json({
      success: true,
      data: {
        employee: {
          name: staffDoc.name,
          employeeId: staffDoc.employeeId,
          designation: staffDoc.designation,
          department: staffDoc.department,
        },
        latestReview,
        averageRating: Math.round(avgRating * 100) / 100,
        totalReviews: reviews.length,
        completedReviews: completedReviews.length,
        currentGoals,
        recentReviews: reviews.slice(0, 5),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch performance summary' },
    });
  }
};

module.exports = {
  getPerformanceReviews,
  getPerformanceReviewById,
  submitSelfReview,
  createSelfAssessment,
  getEmployeePerformanceSummary,
};
