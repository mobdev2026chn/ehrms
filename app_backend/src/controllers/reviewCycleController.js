const mongoose = require('mongoose');
const ReviewCycle = require('../models/ReviewCycle');
const KRA = require('../models/KRA');
const Staff = require('../models/Staff');

/** Get review cycles for filter dropdown */
exports.getReviewCycles = async (req, res) => {
  try {
    const { status, type, page = 1, limit = 100 } = req.query;
    const user = req.user;
    const staff = req.staff;

    const query = {};

    if (user?.companyId && mongoose.Types.ObjectId.isValid(user.companyId)) {
      query.businessId = new mongoose.Types.ObjectId(user.companyId);
    } else if (staff?.businessId && mongoose.Types.ObjectId.isValid(staff.businessId)) {
      query.businessId = new mongoose.Types.ObjectId(staff.businessId);
    }

    if (status) query.status = status;
    if (type) query.type = type;

    const skip = (Number(page) - 1) * Number(limit);

    const cycles = await ReviewCycle.find(query)
      .populate('createdBy', 'name email')
      .skip(skip)
      .limit(Number(limit))
      .sort({ startDate: -1 })
      .lean();

    const total = await ReviewCycle.countDocuments(query);

    res.json({
      success: true,
      data: {
        cycles,
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total,
          pages: Math.ceil(total / Number(limit)) || 1,
        },
      },
    });
  } catch (error) {
    console.error('[ReviewCycle] getReviewCycles error:', error.message);
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch review cycles' },
    });
  }
};

/** Get KRAs for Link to KRA dropdown in create goal form */
exports.getKRAs = async (req, res) => {
  try {
    const { employeeId, status, timeframe, page = 1, limit = 1000 } = req.query;
    const user = req.user;
    const staff = req.staff;

    const query = {};

    if (user?.companyId && mongoose.Types.ObjectId.isValid(user.companyId)) {
      query.businessId = new mongoose.Types.ObjectId(user.companyId);
    } else if (staff?.businessId && mongoose.Types.ObjectId.isValid(staff.businessId)) {
      query.businessId = new mongoose.Types.ObjectId(staff.businessId);
    }

    if (user?.role === 'Employee' || user?.role === 'EmployeeAdmin') {
      const foundStaff = staff || await Staff.findOne({ userId: user._id });
      if (foundStaff) query.employeeId = foundStaff._id;
    } else if (employeeId) {
      query.employeeId = employeeId;
    }

    if (status) query.status = status;
    if (timeframe) query.timeframe = timeframe;

    const skip = (Number(page) - 1) * Number(limit);

    const kras = await KRA.find(query)
      .populate('employeeId', 'name employeeId designation department')
      .skip(skip)
      .limit(Number(limit))
      .sort({ createdAt: -1 })
      .lean();

    const total = await KRA.countDocuments(query);

    res.json({
      success: true,
      data: {
        kras,
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total,
          pages: Math.ceil(total / Number(limit)) || 1,
        },
      },
    });
  } catch (error) {
    console.error('[Performance] getKRAs error:', error.message);
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch KRAs' },
    });
  }
};
