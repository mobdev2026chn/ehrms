const mongoose = require('mongoose');
const Goal = require('../models/Goal');
const Staff = require('../models/Staff');
const ReviewCycle = require('../models/ReviewCycle');
const KRA = require('../models/KRA');

/** Get goals - supports myGoals (employee's own), status, cycle filters */
exports.getGoals = async (req, res) => {
  try {
    const { employeeId, status, cycle, search, page = 1, limit = 20, myGoals: myGoalsParam } = req.query;
    const myGoals = String(myGoalsParam) === 'true';
    const user = req.user;
    const staff = req.staff;

    const query = {};

    if (user?.companyId && mongoose.Types.ObjectId.isValid(user.companyId)) {
      query.businessId = new mongoose.Types.ObjectId(user.companyId);
    } else if (staff?.businessId && mongoose.Types.ObjectId.isValid(staff.businessId)) {
      query.businessId = new mongoose.Types.ObjectId(staff.businessId);
    }

    if (myGoals) {
      if (!staff) {
        const foundStaff = await Staff.findOne({ userId: user?._id });
        if (!foundStaff) {
          return res.status(404).json({ success: false, error: { message: 'Staff record not found' } });
        }
        query.employeeId = foundStaff._id;
      } else {
        query.employeeId = staff._id;
      }
    } else if (employeeId) {
      query.employeeId = employeeId;
    }

    if (status) query.status = status;
    if (cycle) query.cycle = cycle;

    if (search && typeof search === 'string' && search.trim()) {
      const searchRegex = new RegExp(search.trim(), 'i');
      query.$or = [
        { title: searchRegex },
        { kpi: searchRegex },
        { type: searchRegex },
      ];
    }

    const skip = (Number(page) - 1) * Number(limit);

    const goals = await Goal.find(query)
      .populate('employeeId', 'name employeeId designation department')
      .populate('createdBy', 'name email')
      .populate('assignedBy', 'name email')
      .populate('kraId', 'title kpi target overallPercent status')
      .skip(skip)
      .limit(Number(limit))
      .sort({ createdAt: -1 })
      .lean();

    const total = await Goal.countDocuments(query);

    res.json({
      success: true,
      data: {
        goals,
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total,
          pages: Math.ceil(total / Number(limit)) || 1,
        },
      },
    });
  } catch (error) {
    console.error('[PMS] getGoals error:', error.message);
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch goals' },
    });
  }
};

/** Get single goal by ID */
exports.getGoalById = async (req, res) => {
  try {
    const goal = await Goal.findById(req.params.id)
      .populate('employeeId', 'name employeeId designation department')
      .populate('createdBy', 'name email')
      .populate('assignedBy', 'name email')
      .populate('kraId', 'title kpi target overallPercent status')
      .lean();

    if (!goal) {
      return res.status(404).json({
        success: false,
        error: { message: 'Goal not found' },
      });
    }

    res.json({
      success: true,
      data: { goal },
    });
  } catch (error) {
    console.error('[PMS] getGoalById error:', error.message);
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch goal' },
    });
  }
};

/** Create goal - employee creates own (pending), admin assigns (approved) */
exports.createGoal = async (req, res) => {
  try {
    const user = req.user;
    const staff = req.staff;
    const userRole = user?.role || 'Employee';

    let goalData = { ...req.body };

    if (userRole === 'Employee' || userRole === 'EmployeeAdmin') {
      const foundStaff = staff || await Staff.findOne({ userId: user._id });
      if (!foundStaff) {
        return res.status(404).json({
          success: false,
          error: { message: 'Staff record not found' },
        });
      }
      goalData.employeeId = foundStaff._id;
      goalData.status = 'pending';
    } else {
      if (!goalData.employeeId) {
        return res.status(400).json({
          success: false,
          error: { message: 'employeeId is required when assigning goals' },
        });
      }
      goalData.status = 'approved';
    }

    if (user?.companyId && mongoose.Types.ObjectId.isValid(user.companyId)) {
      goalData.businessId = new mongoose.Types.ObjectId(user.companyId);
    } else if (staff?.businessId && mongoose.Types.ObjectId.isValid(staff.businessId)) {
      goalData.businessId = new mongoose.Types.ObjectId(staff.businessId);
    }

    goalData.createdBy = user._id;
    if (userRole !== 'Employee' && userRole !== 'EmployeeAdmin') {
      goalData.assignedBy = user._id;
    }

    const goal = await Goal.create(goalData);

    if (goalData.kraId && mongoose.Types.ObjectId.isValid(goalData.kraId)) {
      try {
        await KRA.findByIdAndUpdate(goalData.kraId, {
          $addToSet: { goalIds: goal._id },
        });
      } catch (kraErr) {
        console.warn('[PMS] KRA link update failed:', kraErr.message);
      }
    }

    const populated = await Goal.findById(goal._id)
      .populate('employeeId', 'name employeeId designation department')
      .populate('createdBy', 'name email')
      .populate('assignedBy', 'name email')
      .lean();

    res.status(201).json({
      success: true,
      data: { goal: populated || goal },
    });
  } catch (error) {
    console.error('[PMS] createGoal error:', error.message);
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to create goal' },
    });
  }
};

/** Update goal progress */
exports.updateGoalProgress = async (req, res) => {
  try {
    const { progress, achievements, challenges } = req.body;
    const user = req.user;
    const staff = req.staff;

    const goal = await Goal.findById(req.params.id);
    if (!goal) {
      return res.status(404).json({
        success: false,
        error: { message: 'Goal not found' },
      });
    }

    if (user?.role === 'Employee' || user?.role === 'EmployeeAdmin') {
      const foundStaff = staff || await Staff.findOne({ userId: user._id });
      if (!foundStaff) {
        return res.status(404).json({
          success: false,
          error: { message: 'Staff record not found' },
        });
      }
      const goalEmpId = goal.employeeId?.toString?.() || goal.employeeId?._id?.toString?.();
      if (goalEmpId !== foundStaff._id.toString()) {
        return res.status(403).json({
          success: false,
          error: { message: 'Access denied. You can only update your own goals.' },
        });
      }
    }

    const updateData = {
      progress: Math.min(100, Math.max(0, Number(progress) ?? goal.progress)),
      ...(achievements !== undefined && { achievements }),
      ...(challenges !== undefined && { challenges }),
    };

    const updatedGoal = await Goal.findByIdAndUpdate(
      req.params.id,
      updateData,
      { new: true }
    )
      .populate('employeeId', 'name employeeId designation department')
      .populate('createdBy', 'name email')
      .populate('assignedBy', 'name email')
      .lean();

    if (updatedGoal?.kraId && mongoose.Types.ObjectId.isValid(updatedGoal.kraId)) {
      try {
        const KRA = require('../models/KRA');
        const kra = await KRA.findById(updatedGoal.kraId);
        if (kra && kra.goalIds?.length) {
          const goals = await Goal.find({
            _id: { $in: kra.goalIds },
            status: { $in: ['approved', 'completed'] },
          });
          const totalWeight = goals.reduce((s, g) => s + (g.weightage || 0), 0);
          const weightedProgress = totalWeight > 0
            ? goals.reduce((s, g) => s + (g.progress || 0) * (g.weightage || 0), 0) / totalWeight
            : 0;
          await KRA.findByIdAndUpdate(updatedGoal.kraId, {
            overallPercent: Math.min(100, Math.round(weightedProgress)),
          });
        }
      } catch (kraErr) {
        console.warn('[PMS] KRA progress update failed:', kraErr.message);
      }
    }

    res.json({
      success: true,
      data: { goal: updatedGoal },
    });
  } catch (error) {
    console.error('[PMS] updateGoalProgress error:', error.message);
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to update progress' },
    });
  }
};

/** Complete goal - employee marks as completed when progress 100% and status approved */
exports.completeGoal = async (req, res) => {
  try {
    const user = req.user;
    const staff = req.staff;
    const { completionNotes } = req.body || {};

    const goal = await Goal.findById(req.params.id);
    if (!goal) {
      return res.status(404).json({
        success: false,
        error: { message: 'Goal not found' },
      });
    }

    if (user?.role === 'Employee' || user?.role === 'EmployeeAdmin') {
      const foundStaff = staff || await Staff.findOne({ userId: user._id });
      if (!foundStaff) {
        return res.status(404).json({
          success: false,
          error: { message: 'Staff record not found' },
        });
      }
      const goalEmpId = goal.employeeId?.toString?.() || goal.employeeId?._id?.toString?.();
      if (goalEmpId !== foundStaff._id.toString()) {
        return res.status(403).json({
          success: false,
          error: { message: 'Access denied. You can only complete your own goals.' },
        });
      }
    }

    if (goal.status !== 'approved') {
      return res.status(400).json({
        success: false,
        error: { message: 'Only approved goals can be marked as completed' },
      });
    }

    if ((goal.progress || 0) < 100) {
      return res.status(400).json({
        success: false,
        error: { message: 'Goal progress must be 100% before marking as completed' },
      });
    }

    const updatedGoal = await Goal.findByIdAndUpdate(
      req.params.id,
      {
        status: 'completed',
        achievements: completionNotes || goal.achievements,
        completedAt: new Date(),
        completedBy: user._id,
      },
      { new: true }
    )
      .populate('employeeId', 'name employeeId designation department')
      .populate('createdBy', 'name email')
      .populate('assignedBy', 'name email')
      .lean();

    res.json({
      success: true,
      data: { goal: updatedGoal },
    });
  } catch (error) {
    console.error('[PMS] completeGoal error:', error.message);
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to complete goal' },
    });
  }
};
