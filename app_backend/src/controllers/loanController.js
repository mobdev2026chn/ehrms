const Loan = require('../models/Loan');
const Staff = require('../models/Staff');
const User = require('../models/User');
const mongoose = require('mongoose');

// Helper to calculate EMI
const calculateEMI = (principal, tenure, rate) => {
    if (rate === 0) return principal / tenure;
    const monthlyRate = rate / 12 / 100;
    const emi = (principal * monthlyRate * Math.pow(1 + monthlyRate, tenure)) /
        (Math.pow(1 + monthlyRate, tenure) - 1);
    return Math.round(emi);
};

// @desc    Get Loans
// @route   GET /api/loans
// @access  Private (Employee sees own, Admin sees Company's)
const getLoans = async (req, res) => {
    try {
        const { status, search, page = 1, limit = 10, startDate, endDate } = req.query;
        const query = {};

        // If 'req.staff' is present (meaning logged in as Employee), filter by employeeId
        if (req.staff) {
            query.employeeId = req.staff._id;
        } else if (req.user && req.user.role === 'Employee') {
            // Fallback if req.staff middleware logic changes
            const staff = await Staff.findOne({ userId: req.user._id });
            if (staff) query.employeeId = staff._id;
            else return res.json({ success: true, data: { loans: [], pagination: { page, limit, total: 0, pages: 0 } } });
        }

        // Company Scope
        if (req.user && req.user.role !== 'Super Admin' && req.user.companyId) {
            query.businessId = req.user.companyId;
        } else if (req.staff && req.staff.businessId) {
            query.businessId = req.staff.businessId;
        }

        // Filters
        if (status && status !== 'all' && status !== 'All Status') {
            query.status = status;
        }

        if (startDate || endDate) {
            query.createdAt = {};
            if (startDate) query.createdAt.$gte = new Date(startDate);
            if (endDate) query.createdAt.$lte = new Date(endDate);
        }

        // Search
        if (search) {
            query.$or = [
                { purpose: { $regex: search, $options: 'i' } },
                { loanType: { $regex: search, $options: 'i' } }
            ];
        }

        const skip = (Number(page) - 1) * Number(limit);

        const loans = await Loan.find(query)
            .populate('employeeId', 'name employeeId designation')
            .sort({ createdAt: -1 })
            .skip(skip)
            .limit(Number(limit))
            .lean();

        const total = await Loan.countDocuments(query);

        // Resolve approvedBy and rejectedBy: Loan refs User; check User first, then Staff (same as Approved By)
        const toId = (v) => (v != null && typeof v === 'object' && v._id != null ? v._id : v) || null;
        const approvedByIds = [...new Set(loans.map((l) => toId(l.approvedBy)).filter(Boolean))];
        const rejectedByIds = [...new Set(loans.map((l) => toId(l.rejectedBy)).filter(Boolean))];
        const allIds = [...new Set([...approvedByIds, ...rejectedByIds])];
        const resolvedMap = {};
        for (const id of allIds) {
            const key = id.toString();
            const user = await User.findById(id).select('name email').lean();
            if (user) {
                resolvedMap[key] = { name: user.name, email: user.email || null };
            } else {
                const staff = await Staff.findById(id).select('name email').lean();
                if (staff) {
                    resolvedMap[key] = { name: staff.name, email: staff.email || null };
                }
            }
        }
        loans.forEach((l) => {
            const aid = toId(l.approvedBy);
            const rid = toId(l.rejectedBy);
            if (aid) l.approvedBy = resolvedMap[aid.toString()] || null;
            if (rid) l.rejectedBy = resolvedMap[rid.toString()] || null;
        });

        res.json({
            success: true,
            data: {
                loans,
                pagination: {
                    page: Number(page),
                    limit: Number(limit),
                    total,
                    pages: Math.ceil(total / Number(limit))
                }
            }
        });

    } catch (error) {
        console.error('getLoans Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

// @desc    Get loan stats for the logged-in employee (all-time, ignores pagination/filters)
// @route   GET /api/requests/loan/summary
// @access  Private (Employee)
const getLoanSummary = async (req, res) => {
    try {
        let employeeId;
        if (req.staff) {
            employeeId = req.staff._id;
        } else if (req.user) {
            const staff = await Staff.findOne({ userId: req.user._id });
            employeeId = staff?._id;
        }

        if (!employeeId) {
            return res.json({
                success: true,
                data: { activeCount: 0, pendingCount: 0, totalOutstanding: 0 }
            });
        }

        const results = await Loan.aggregate([
            { $match: { employeeId: new mongoose.Types.ObjectId(employeeId) } },
            {
                $group: {
                    _id: '$status',
                    count: { $sum: 1 },
                    remaining: { $sum: '$remainingAmount' }
                }
            }
        ]);

        let activeCount = 0;
        let pendingCount = 0;
        let totalOutstanding = 0;
        for (const r of results) {
            if (r._id === 'Active' || r._id === 'Approved') {
                activeCount += r.count;
                totalOutstanding += r.remaining;
            } else if (r._id === 'Pending') {
                pendingCount += r.count;
            }
        }

        res.json({
            success: true,
            data: { activeCount, pendingCount, totalOutstanding }
        });
    } catch (error) {
        console.error('getLoanSummary Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

// @desc    Create Loan Request
// @route   POST /api/loans
// @access  Private (Employee)
const createLoan = async (req, res) => {
    try {
        const { amount, tenure, purpose, loanType, interestRate = 0 } = req.body;

        if (!amount || !tenure || !purpose || !loanType) {
            return res.status(400).json({ success: false, error: { message: 'Please provide all required fields' } });
        }

        const emi = calculateEMI(amount, tenure, interestRate);

        // Identify Staff
        let staffId;
        let businessId;

        if (req.staff) {
            staffId = req.staff._id;
            businessId = req.staff.businessId;
        } else {
            // Fallback
            const staff = await Staff.findOne({ userId: req.user._id });
            if (!staff) return res.status(404).json({ success: false, error: { message: 'Staff profile not found' } });
            staffId = staff._id;
            businessId = staff.businessId;
        }

        const loan = await Loan.create({
            employeeId: staffId,
            loanType,
            amount,
            purpose,
            interestRate,
            tenure,
            emi,
            remainingAmount: amount,
            businessId,
            status: 'Pending'
        });

        res.status(201).json({
            success: true,
            data: { loan }
        });

    } catch (error) {
        console.error('createLoan Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

module.exports = { getLoans, createLoan, getLoanSummary };
