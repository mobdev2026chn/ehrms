const Leave = require('../models/Leave');
const Loan = require('../models/Loan');
const Expense = require('../models/Expense');
const PayslipRequest = require('../models/PayslipRequest');
const Payroll = require('../models/Payroll');
const Staff = require('../models/Staff');
const User = require('../models/User');
const Company = require('../models/Company');
const payslipGeneratorService = require('../services/payslipGeneratorService');
const { calculateAttendanceStats } = require('./payrollController');

// Normalize ref to raw ObjectId (handles both ObjectId and populated { _id, name } so lookup works)
const toId = (v) => (v != null && typeof v === 'object' && v._id != null ? v._id : v) || null;

// Helper function to generate payroll dynamically for payslip requests
// ALWAYS recalculates from scratch - does not use existing payroll records
const _generatePayrollForPayslip = async (employeeId, month, year, businessId) => {
    console.log(`[_generatePayrollForPayslip] ========== FUNCTION CALLED ==========`);
    console.log(`[_generatePayrollForPayslip] Employee ID: ${employeeId}`);
    console.log(`[_generatePayrollForPayslip] Month: ${month}, Year: ${year}`);
    console.log(`[_generatePayrollForPayslip] Business ID: ${businessId}`);
    
    // Always recalculate from scratch - don't use existing payroll
    // This ensures we use the correct calculation method based on current attendance data

    // Get staff with salary structure
    console.log(`[_generatePayrollForPayslip] Fetching staff record for employee ID: ${employeeId}`);
    const staff = await Staff.findById(employeeId);
    if (!staff) {
        console.error(`[_generatePayrollForPayslip] Staff not found for employee ID: ${employeeId}`);
        throw new Error('Employee not found');
    }
    console.log(`[_generatePayrollForPayslip] Staff found: ${staff.name} (${staff.employeeId})`);
    
    if (!staff.salary || !staff.salary.basicSalary) {
        console.error(`[_generatePayrollForPayslip] Salary structure not configured for staff: ${staff.name}`);
        throw new Error('Employee salary structure not configured');
    }
    console.log(`[_generatePayrollForPayslip] Salary structure found - Basic: ${staff.salary.basicSalary}`);

    // Get businessId from staff if not provided
    const finalBusinessId = businessId || staff.businessId;
    console.log(`[_generatePayrollForPayslip] Using Business ID: ${finalBusinessId}`);

    // Single source of truth: same attendance stats as dashboard and salary overview
    const Attendance = require('../models/Attendance');
    const startOfMonth = new Date(year, month - 1, 1);
    const endOfMonth = new Date(year, month, 0, 23, 59, 59, 999);

    const attendanceStats = await calculateAttendanceStats(employeeId, month, year);
    const totalWorkingDays = attendanceStats.workingDays || 0;
    const thisMonthWorkingDays = attendanceStats.workingDaysFullMonth ?? totalWorkingDays;
    const presentDays = attendanceStats.presentDays || 0;
    const paidLeaveDays = attendanceStats.paidLeaveDays || 0;
    const effectivePaidDays = presentDays + paidLeaveDays;
    const absentDays = attendanceStats.absentDays ?? Math.max(0, totalWorkingDays - effectivePaidDays);

    console.log(`[_generatePayrollForPayslip] Attendance (same as salary overview/payroll): thisMonthWD=${thisMonthWorkingDays}, presentDays=${presentDays}, absentDays=${absentDays}`);

    const monthAttendance = await Attendance.find({
        $or: [
            { employeeId: employeeId },
            { user: employeeId }
        ],
        date: { $gte: startOfMonth, $lte: endOfMonth }
    });
    if (monthAttendance.length > 0) {
        console.log(`[_generatePayrollForPayslip] Attendance Records: ${monthAttendance.length}`);
    }
    
    const s = staff.salary;
    const basicSalary = s.basicSalary || 0;
    const dearnessAllowance = s.dearnessAllowance || 0;
    const houseRentAllowance = s.houseRentAllowance || 0;
    const specialAllowance = s.specialAllowance || 0;
    const basicPlusDA = basicSalary + dearnessAllowance;
    const basicPlusDAPlusHRA = basicSalary + dearnessAllowance + houseRentAllowance;
    const isPFApplicable = basicPlusDA < 15000;
    const isESIApplicable = basicPlusDAPlusHRA < 21000;
    const employerPFRate = isPFApplicable ? (s.employerPFRate || 0) : 0;
    const employerESIRate = isESIApplicable ? (s.employerESIRate || 0) : 0;
    const employeePFRate = isPFApplicable ? (s.employeePFRate || 0) : 0;
    const employeeESIRate = isESIApplicable ? (s.employeeESIRate || 0) : 0;
    const pfStaticAmount = isPFApplicable ? 0 : 1800;
    
    // Gross Fixed Salary (Before Employer Contributions)
    const grossFixedSalary = basicSalary + dearnessAllowance + houseRentAllowance + specialAllowance;
    
    // Employer Contributions (Part of Gross Salary & CTC)
    const employerPF = employerPFRate / 100 * basicSalary;
    const employerESI = employerESIRate / 100 * grossFixedSalary;
    
    // Gross Salary (Monthly) = Fixed Gross + Employer Contributions
    const grossSalary = grossFixedSalary + employerPF + employerESI + pfStaticAmount;
    
    // Employee Deductions (NOT part of CTC)
    const employeePF = employeePFRate > 0 ? (employeePFRate / 100 * basicSalary) : pfStaticAmount;
    const employeeESI = employeeESIRate / 100 * grossSalary;
    const totalDeductions = employeePF + employeeESI;
    
    // Net Salary = Gross Salary - Employee Deductions
    const netSalary = grossSalary - totalDeductions;
    
    // Same as salary overview & payroll: proration = (presentDays + paidLeaveDays) / this month WD
    const prorationFactor = thisMonthWorkingDays > 0 ? effectivePaidDays / thisMonthWorkingDays : 0;
    
    // STEP 1: Prorate Gross Fixed Components
    const proratedBasicSalary = basicSalary * prorationFactor;
    const proratedDA = dearnessAllowance * prorationFactor;
    const proratedHRA = houseRentAllowance * prorationFactor;
    const proratedSpecialAllowance = specialAllowance * prorationFactor;
    const proratedGrossFixed = proratedBasicSalary + proratedDA + proratedHRA + proratedSpecialAllowance;
    
    // STEP 2: Recalculate Employer Contributions on PRORATED amounts
    const proratedEmployerPF = employerPFRate / 100 * proratedBasicSalary;
    const proratedEmployerESI = employerESIRate / 100 * proratedGrossFixed;
    
    // STEP 3: Calculate Prorated Gross Salary
    const proratedGrossSalary = proratedGrossFixed + proratedEmployerPF + proratedEmployerESI + pfStaticAmount;
    
    // Fine amount from Present, Approved, or Half Day (late login fine applies to half day too)
    const totalFineAmount = monthAttendance
        .filter(r => {
            const s = (r.status || '').trim().toLowerCase();
            const lt = (r.leaveType || '').trim().toLowerCase();
            return s === 'present' || s === 'approved' || s === 'half day' || lt === 'half day';
        })
        .reduce((sum, record) => sum + (record.fineAmount || 0), 0);
    
    console.log(`[_generatePayrollForPayslip] Fine Amount: ${totalFineAmount}`);
    
    // STEP 4: Recalculate Employee Deductions on PRORATED gross
    const proratedEmployeePF = employeePFRate > 0
        ? (employeePFRate / 100 * proratedBasicSalary)
        : pfStaticAmount;
    const proratedEmployeeESI = employeeESIRate / 100 * proratedGrossSalary;
    const proratedDeductions = proratedEmployeePF + proratedEmployeeESI;
    
    // STEP 5: Calculate Prorated Net Salary (fines are NOT prorated)
    const proratedNetPay = proratedGrossSalary - proratedDeductions - totalFineAmount;
    
    // Build components array
    const components = [];
    
    // Earnings - Always include all components (even if 0, for payslip completeness)
    components.push({ 
        name: 'Basic Salary', 
        amount: Math.round(proratedBasicSalary * 100) / 100, 
        type: 'earning' 
    });
    components.push({ 
        name: 'Dearness Allowance', 
        amount: Math.round(proratedDA * 100) / 100, 
        type: 'earning' 
    });
    components.push({ 
        name: 'House Rent Allowance', 
        amount: Math.round(proratedHRA * 100) / 100, 
        type: 'earning' 
    });
    if (proratedSpecialAllowance > 0) {
        components.push({ 
            name: 'Special Allowance', 
            amount: Math.round(proratedSpecialAllowance * 100) / 100, 
            type: 'earning' 
        });
    }
    components.push({ 
        name: 'Employer PF', 
        amount: Math.round(proratedEmployerPF * 100) / 100, 
        type: 'earning' 
    });
    components.push({ 
        name: 'Employer ESI', 
        amount: Math.round(proratedEmployerESI * 100) / 100, 
        type: 'earning' 
    });
    
    // Deductions - Always include all components
    components.push({ 
        name: 'Employee PF', 
        amount: Math.round(proratedEmployeePF * 100) / 100, 
        type: 'deduction' 
    });
    components.push({ 
        name: 'Employee ESI', 
        amount: Math.round(proratedEmployeeESI * 100) / 100, 
        type: 'deduction' 
    });
    if (totalFineAmount > 0) {
        components.push({ 
            name: 'Late Login Fine', 
            amount: Math.round(totalFineAmount * 100) / 100, 
            type: 'deduction' 
        });
    }
    
    // Delete existing payroll record if it exists (to ensure fresh calculation)
    console.log(`[_generatePayrollForPayslip] Deleting existing payroll records for employee ${employeeId}, month ${month}, year ${year}`);
    const deleteResult = await Payroll.deleteMany({ employeeId, month, year });
    console.log(`[_generatePayrollForPayslip] Deleted ${deleteResult.deletedCount} existing payroll record(s)`);
    
    // Create new payroll record with fresh calculation
    console.log(`[_generatePayrollForPayslip] Creating new payroll record with calculated values:`);
    console.log(`[_generatePayrollForPayslip]   - Gross Salary: ${proratedGrossSalary.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Deductions: ${(proratedDeductions + totalFineAmount).toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Net Pay: ${proratedNetPay.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Components: ${components.length}`);
    
    const payroll = await Payroll.create({
        employeeId,
        month,
        year,
        grossSalary: Math.round(proratedGrossSalary * 100) / 100,
        deductions: Math.round((proratedDeductions + totalFineAmount) * 100) / 100,
        netPay: Math.round(proratedNetPay * 100) / 100,
        components,
        status: 'Pending',
        businessId: finalBusinessId
    });
    
    console.log(`[_generatePayrollForPayslip] ========== PAYROLL GENERATION SUMMARY ==========`);
    console.log(`[_generatePayrollForPayslip] Employee: ${staff.name} (${staff.employeeId})`);
    console.log(`[_generatePayrollForPayslip] Period: ${month}/${year}`);
    console.log(`[_generatePayrollForPayslip] Working Days: ${totalWorkingDays}`);
    console.log(`[_generatePayrollForPayslip] Present Days: ${presentDays}, Paid Leave: ${paidLeaveDays}`);
    console.log(`[_generatePayrollForPayslip] Absent Days: ${absentDays}`);
    console.log(`[_generatePayrollForPayslip] Proration Factor: ${prorationFactor.toFixed(6)} (effectivePaidDays=${effectivePaidDays} / thisMonthWD=${thisMonthWorkingDays})`);
    console.log(`[_generatePayrollForPayslip] Fine Amount: ${totalFineAmount.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip] Base Salary Structure:`);
    console.log(`[_generatePayrollForPayslip]   - Basic Salary: ${basicSalary}`);
    console.log(`[_generatePayrollForPayslip]   - DA: ${dearnessAllowance}`);
    console.log(`[_generatePayrollForPayslip]   - HRA: ${houseRentAllowance}`);
    console.log(`[_generatePayrollForPayslip]   - Special Allowance: ${specialAllowance}`);
    console.log(`[_generatePayrollForPayslip]   - Gross Fixed: ${grossFixedSalary}`);
    console.log(`[_generatePayrollForPayslip]   - Full Month Gross: ${grossSalary}`);
    console.log(`[_generatePayrollForPayslip] Prorated Values:`);
    console.log(`[_generatePayrollForPayslip]   - Prorated Basic: ${proratedBasicSalary.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated DA: ${proratedDA.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated HRA: ${proratedHRA.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated Gross Fixed: ${proratedGrossFixed.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated Employer PF: ${proratedEmployerPF.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated Employer ESI: ${proratedEmployerESI.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated Gross Salary: ${proratedGrossSalary.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated Employee PF: ${proratedEmployeePF.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated Employee ESI: ${proratedEmployeeESI.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Prorated Deductions: ${proratedDeductions.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip] Final Values:`);
    console.log(`[_generatePayrollForPayslip]   - Gross Salary: ${proratedGrossSalary.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Deductions: ${(proratedDeductions + totalFineAmount).toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip]   - Net Pay: ${proratedNetPay.toFixed(2)}`);
    console.log(`[_generatePayrollForPayslip] Components Count: ${components.length} (${components.filter(c => c.type === 'earning').length} earnings, ${components.filter(c => c.type === 'deduction').length} deductions)`);
    console.log(`[_generatePayrollForPayslip] Components Details:`);
    components.forEach((comp, idx) => {
        console.log(`[_generatePayrollForPayslip]   ${idx + 1}. ${comp.name} (${comp.type}): ${comp.amount.toFixed(2)}`);
    });
    console.log(`[_generatePayrollForPayslip] Successfully generated payroll ${payroll._id}`);
    console.log(`[_generatePayrollForPayslip] ================================================`);
    
    return payroll;
};

// @desc    Apply for Leave
// @route   POST /api/requests/leave
// @access  Private
const applyLeave = async (req, res) => {
    try {
        const { leaveType, startDate, endDate, days, reason } = req.body;

        if (!leaveType || !startDate || !endDate || !days) {
            return res.status(400).json({ message: 'Please fill in all required fields' });
        }

        const employeeId = req.staff?._id || req.user?._id;
        const businessId = req.staff?.businessId || req.user?.businessId || req.companyId;

        if (!employeeId) {
            return res.status(400).json({ message: 'Employee context required' });
        }

        const leave = await Leave.create({
            employeeId,
            businessId,
            leaveType,
            startDate,
            endDate,
            days,
            reason
        });

        res.status(201).json(leave);
    } catch (error) {
        console.error('Apply Leave Error:', error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Get My Leave Requests
// @route   GET /api/requests/leave
// @access  Private
// Resolves approvedBy name from Staff collection first, then User (same pattern as loan details).
const getLeaveRequests = async (req, res) => {
    try {
        const { status, startDate, endDate } = req.query;
        const employeeId = req.staff?._id || req.user?._id;

        if (!employeeId) {
            return res.status(400).json({ message: 'Employee context required' });
        }

        let query = { employeeId };

        if (status && status !== 'All Status') {
            query.status = status;
        }

        // Filter by from-to date range: leave overlaps [startDate, endDate]
        if (startDate || endDate) {
            query.$and = query.$and || [];
            if (startDate) {
                query.$and.push({ endDate: { $gte: new Date(startDate) } });
            }
            if (endDate) {
                query.$and.push({ startDate: { $lte: new Date(endDate) } });
            }
        }

        const leaves = await Leave.find(query)
            .sort({ createdAt: -1 })
            .lean();

        // Resolve approvedBy and rejectedBy: match _id in Staff first, then User (same as Approved By)
        const approvedByIds = [...new Set(leaves.map(l => toId(l.approvedBy)).filter(Boolean))];
        const rejectedByIds = [...new Set(leaves.map(l => toId(l.rejectedBy)).filter(Boolean))];
        const allIds = [...new Set([...approvedByIds, ...rejectedByIds])];
        const resolvedMap = {};
        for (const id of allIds) {
            const key = id.toString();
            const staff = await Staff.findById(id).select('name email').lean();
            if (staff) {
                resolvedMap[key] = { name: staff.name, email: staff.email || null };
            } else {
                const user = await User.findById(id).select('name email').lean();
                if (user) {
                    resolvedMap[key] = { name: user.name, email: user.email || null };
                }
            }
        }
        leaves.forEach(l => {
            const aid = toId(l.approvedBy);
            const rid = toId(l.rejectedBy);
            if (aid) l.approvedBy = resolvedMap[aid.toString()] || null;
            if (rid) l.rejectedBy = resolvedMap[rid.toString()] || null;
        });

        res.json(leaves);
    } catch (error) {
        console.error('Get Leave Requests Error:', error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Request Loan
// @route   POST /api/requests/loan
// @access  Private
const applyLoan = async (req, res) => {
    try {
        const { loanType, amount, tenureMonths, interestRate, purpose } = req.body;

        if (!loanType || !amount || !tenureMonths) {
            return res.status(400).json({ message: 'Please fill in all required fields' });
        }

        const employeeId = req.staff?._id || req.user?._id;
        const businessId = req.staff?.businessId || req.user?.businessId || req.companyId;

        if (!employeeId) {
            return res.status(400).json({ message: 'Employee context required' });
        }

        let emi = 0;
        if (interestRate > 0) {
            const r = interestRate / 12 / 100;
            emi = (amount * r * Math.pow(1 + r, tenureMonths)) / (Math.pow(1 + r, tenureMonths) - 1);
        } else {
            emi = amount / tenureMonths;
        }

        const loan = await Loan.create({
            employeeId,
            businessId,
            loanType,
            amount,
            tenureMonths,
            interestRate,
            emi: parseFloat(emi.toFixed(2)),
            purpose
        });

        res.status(201).json(loan);
    } catch (error) {
        console.error('Apply Loan Error:', error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Get My Loan Requests
// @route   GET /api/requests/loan
// @access  Private
// Resolves approvedBy name from User first (Loan ref), then Staff if needed.
const getLoanRequests = async (req, res) => {
    try {
        const { status, startDate, endDate } = req.query;
        const employeeId = req.staff?._id || req.user?._id;

        if (!employeeId) {
            return res.status(400).json({ message: 'Employee context required' });
        }

        let query = { employeeId };

        if (status && status !== 'All Status') {
            query.status = status;
        }

        if (startDate || endDate) {
            query.createdAt = {};
            if (startDate) query.createdAt.$gte = new Date(startDate);
            if (endDate) query.createdAt.$lte = new Date(endDate);
        }

        const loans = await Loan.find(query).sort({ createdAt: -1 }).lean();

        // Resolve approvedBy and rejectedBy: Loan refs User first, then Staff (same as Approved By)
        const approvedByIds = [...new Set(loans.map(l => toId(l.approvedBy)).filter(Boolean))];
        const rejectedByIds = [...new Set(loans.map(l => toId(l.rejectedBy)).filter(Boolean))];
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
        loans.forEach(l => {
            const aid = toId(l.approvedBy);
            const rid = toId(l.rejectedBy);
            if (aid) l.approvedBy = resolvedMap[aid.toString()] || null;
            if (rid) l.rejectedBy = resolvedMap[rid.toString()] || null;
        });

        res.json(loans);
    } catch (error) {
        console.error('Get Loan Requests Error:', error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Apply for Expense
// @route   POST /api/requests/expense
// @access  Private
const applyExpense = async (req, res) => {
    try {
        const { expenseType, amount, date, description } = req.body;

        if (!expenseType || !amount || !date) {
            return res.status(400).json({ message: 'Please fill in required fields' });
        }

        const employeeId = req.staff?._id || req.user?._id;
        const businessId = req.staff?.businessId || req.user?.businessId || req.companyId;

        if (!employeeId) {
            return res.status(400).json({ message: 'Employee context required' });
        }

        const expense = await Expense.create({
            employeeId,
            businessId,
            expenseType,
            amount,
            date,
            description
        });

        res.status(201).json(expense);
    } catch (error) {
        console.error('Apply Expense Error:', error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Get My Expense Requests
// @route   GET /api/requests/expense
// @access  Private
const getExpenseRequests = async (req, res) => {
    try {
        const { status, startDate, endDate } = req.query;
        const employeeId = req.staff?._id || req.user?._id;

        if (!employeeId) {
            return res.status(400).json({ message: 'Employee context required' });
        }

        let query = { employeeId };

        if (status && status !== 'All Status') {
            query.status = status;
        }

        if (startDate || endDate) {
            query.date = {};
            if (startDate) query.date.$gte = new Date(startDate);
            if (endDate) query.date.$lte = new Date(endDate);
        }

        const expenses = await Expense.find(query).sort({ createdAt: -1 }).lean();
        // Resolve approvedBy and rejectedBy: Expense refs Staff first, then User (same as Approved By)
        const approvedByIds = [...new Set(expenses.map(e => toId(e.approvedBy)).filter(Boolean))];
        const rejectedByIds = [...new Set(expenses.map(e => toId(e.rejectedBy)).filter(Boolean))];
        const allIds = [...new Set([...approvedByIds, ...rejectedByIds])];
        const resolvedMap = {};
        for (const id of allIds) {
            const key = id.toString();
            const staff = await Staff.findById(id).select('name email').lean();
            if (staff) {
                resolvedMap[key] = { name: staff.name, email: staff.email || null };
            } else {
                const user = await User.findById(id).select('name email').lean();
                if (user) {
                    resolvedMap[key] = { name: user.name, email: user.email || null };
                }
            }
        }
        expenses.forEach(e => {
            const aid = toId(e.approvedBy);
            const rid = toId(e.rejectedBy);
            if (aid) e.approvedBy = resolvedMap[aid.toString()] || null;
            if (rid) e.rejectedBy = resolvedMap[rid.toString()] || null;
        });
        res.json(expenses);
    } catch (error) {
        console.error('Get Expense Requests Error:', error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Request Payslip
// @route   POST /api/requests/payslip
// @access  Private
const requestPayslip = async (req, res) => {
    try {
        const { month, year, reason, months } = req.body; // months for bulk request

        // Handle bulk request
        if (months && Array.isArray(months) && months.length > 0) {
            return await requestBulkPayslip(req, res, months, year, reason);
        }

        // Single request
        if (!month || !year) {
            return res.status(400).json({ 
                success: false,
                error: { message: 'Please select month and year' } 
            });
        }

        // Determine employeeId and businessId
        let employeeId, businessId;
        if (req.staff && req.staff._id) {
            employeeId = req.staff._id;
            businessId = req.staff.businessId;
        } else if (req.user && req.user.role === 'Employee') {
            // If user is Employee, find their staff record
            const Staff = require('../models/Staff');
            const staff = await Staff.findOne({ userId: req.user._id });
            if (staff) {
                employeeId = staff._id;
                businessId = staff.businessId;
            }
        }

        if (!employeeId) {
            return res.status(400).json({
                success: false,
                error: { message: 'Employee context required' }
            });
        }

        // Ensure businessId is set - fetch from staff if not available
        if (!businessId) {
            const Staff = require('../models/Staff');
            const staff = await Staff.findById(employeeId).select('businessId');
            if (staff && staff.businessId) {
                businessId = staff.businessId;
            }
        }

        // Convert month to number (handle month names like "January", "February", etc.)
        let monthNumber;
        if (typeof month === 'number') {
            monthNumber = month;
        } else if (typeof month === 'string') {
            // Try to parse as number first
            monthNumber = parseInt(month, 10);
            
            // If not a number, try to match month name
            if (isNaN(monthNumber)) {
                const monthNames = ['january', 'february', 'march', 'april', 'may', 'june', 
                                   'july', 'august', 'september', 'october', 'november', 'december'];
                const monthIndex = monthNames.indexOf(month.toLowerCase());
                if (monthIndex !== -1) {
                    monthNumber = monthIndex + 1; // January = 1, December = 12
                }
            }
        } else {
            monthNumber = Number(month);
        }
        
        const yearNumber = typeof year === 'string' ? parseInt(year, 10) : Number(year);

        // Validate month (1-12)
        if (isNaN(monthNumber) || monthNumber < 1 || monthNumber > 12) {
            return res.status(400).json({
                success: false,
                error: { message: 'Invalid month. Month must be between 1 and 12 or a valid month name' }
            });
        }

        // Validate year
        if (isNaN(yearNumber) || yearNumber < 2000 || yearNumber > 2100) {
            return res.status(400).json({
                success: false,
                error: { message: 'Invalid year' }
            });
        }

        // Check for existing request for the same month and year
        const existingRequest = await PayslipRequest.findOne({
            employeeId,
            month: monthNumber,
            year: yearNumber,
            status: { $in: ['Pending', 'Approved'] }
        });

        if (existingRequest) {
            return res.status(400).json({
                success: false,
                error: { message: 'A payslip request for this month and year already exists' }
            });
        }

        // Create payslip request with all required fields
        const payslip = await PayslipRequest.create({
            employeeId,
            businessId: businessId || undefined,
            month: monthNumber,
            year: yearNumber,
            reason: reason || '',
            status: 'Pending'
        });

        res.status(201).json({
            success: true,
            data: payslip
        });
    } catch (error) {
        console.error('Request Payslip Error:', error);
        res.status(500).json({ 
            success: false,
            error: { message: error.message || 'Server Error' } 
        });
    }
};

// @desc    Request Bulk Payslip
// @route   POST /api/requests/payslip (with months array)
// @access  Private
const requestBulkPayslip = async (req, res, months, year, reason) => {
    try {
        if (!year) {
            return res.status(400).json({ 
                success: false,
                error: { message: 'Please select year' } 
            });
        }

        // Determine employeeId and businessId
        let employeeId, businessId;
        if (req.staff && req.staff._id) {
            employeeId = req.staff._id;
            businessId = req.staff.businessId;
        } else if (req.user && req.user.role === 'Employee') {
            // If user is Employee, find their staff record
            const staff = await Staff.findOne({ userId: req.user._id });
            if (staff) {
                employeeId = staff._id;
                businessId = staff.businessId;
            }
        }

        if (!employeeId) {
            return res.status(400).json({
                success: false,
                error: { message: 'Employee context required' }
            });
        }

        // Ensure businessId is set - fetch from staff if not available
        if (!businessId) {
            const staff = await Staff.findById(employeeId).select('businessId');
            if (staff && staff.businessId) {
                businessId = staff.businessId;
            }
        }

        const yearNumber = typeof year === 'string' ? parseInt(year, 10) : Number(year);
        
        // Validate year
        if (isNaN(yearNumber) || yearNumber < 2000 || yearNumber > 2100) {
            return res.status(400).json({
                success: false,
                error: { message: 'Invalid year' }
            });
        }

        const createdRequests = [];
        const errors = [];

        for (const month of months) {
            try {
                // Convert month to number (handle month names like "January", "February", etc.)
                let monthNumber;
                if (typeof month === 'number') {
                    monthNumber = month;
                } else if (typeof month === 'string') {
                    // Try to parse as number first
                    monthNumber = parseInt(month, 10);
                    
                    // If not a number, try to match month name
                    if (isNaN(monthNumber)) {
                        const monthNames = ['january', 'february', 'march', 'april', 'may', 'june', 
                                           'july', 'august', 'september', 'october', 'november', 'december'];
                        const monthIndex = monthNames.indexOf(month.toLowerCase());
                        if (monthIndex !== -1) {
                            monthNumber = monthIndex + 1; // January = 1, December = 12
                        }
                    }
                } else {
                    monthNumber = Number(month);
                }
                
                // Validate month (1-12)
                if (isNaN(monthNumber) || monthNumber < 1 || monthNumber > 12) {
                    errors.push(`Invalid month: ${month}`);
                    continue;
                }

                // Check for existing request
                const existingRequest = await PayslipRequest.findOne({
                    employeeId,
                    month: monthNumber,
                    year: yearNumber,
                    status: { $in: ['Pending', 'Approved'] }
                });

                if (existingRequest) {
                    errors.push(`Request for month ${monthNumber}, year ${yearNumber} already exists`);
                    continue;
                }

                const payslip = await PayslipRequest.create({
                    employeeId,
                    businessId: businessId || undefined,
                    month: monthNumber,
                    year: yearNumber,
                    reason: reason || '',
                    status: 'Pending'
                });

                createdRequests.push(payslip);
            } catch (error) {
                errors.push(`Failed to create request for month ${monthNumber}, year ${yearNumber}: ${error.message}`);
            }
        }

        res.status(201).json({
            success: true,
            data: {
                created: createdRequests,
                errors: errors.length > 0 ? errors : undefined
            },
            message: `Created ${createdRequests.length} payslip request(s)${errors.length > 0 ? `, ${errors.length} failed` : ''}`
        });
    } catch (error) {
        console.error('Request Bulk Payslip Error:', error);
        res.status(500).json({ 
            success: false,
            error: { message: error.message || 'Server Error' } 
        });
    }
};

// @desc    Get My Payslip Requests
// @route   GET /api/requests/payslip
// @access  Private
const getPayslipRequests = async (req, res) => {
    try {
        console.log('DEBUG: getPayslipRequests called');
        console.log('DEBUG: req.user:', req.user);
        console.log('DEBUG: req.staff:', req.staff);

        const { status, search, startDate, endDate } = req.query;

        // Determine employeeId similar to payrollController logic
        let employeeId;
        if (req.staff && req.staff._id) {
            employeeId = req.staff._id;
        } else if (req.user && req.user._id) {
            employeeId = req.user._id;
        }

        if (!employeeId) {
            console.error('DEBUG: No employeeId found in request');
            return res.status(400).json({
                success: false,
                error: { message: 'Employee context required' }
            });
        }

        console.log('DEBUG: Using employeeId:', employeeId);
        let query = { employeeId: employeeId };

        if (status && status !== 'All Status') {
            query.status = status;
        }

        if (search) {
            // Search in reason, or try to match month number
            const searchNum = parseInt(search, 10);
            if (!isNaN(searchNum) && searchNum >= 1 && searchNum <= 12) {
                query.$or = [
                    { reason: { $regex: search, $options: 'i' } },
                    { month: searchNum }
                ];
            } else {
                query.$or = [
                    { reason: { $regex: search, $options: 'i' } }
                ];
            }
        }

        if (startDate || endDate) {
            query.createdAt = {};
            if (startDate) query.createdAt.$gte = new Date(startDate);
            if (endDate) query.createdAt.$lte = new Date(endDate);
        }

        const pageNum = Number(req.query.page) || 1;
        const limitNum = Number(req.query.limit) || 10;
        const skip = (pageNum - 1) * limitNum;

        const requests = await PayslipRequest.find(query)
            .populate('approvedBy', 'name email')
            .populate('rejectedBy', 'name email')
            .populate('payrollId', 'month year netPay grossSalary payslipUrl')
            .sort({ createdAt: -1 })
            .skip(skip)
            .limit(limitNum)
            .lean();

        // If request is Approved/Generated but has no payrollId or payroll has no payslipUrl,
        // look up Payroll by employeeId+month+year and attach so app can show View/Download
        for (const req of requests) {
            if ((req.status === 'Approved' || req.status === 'Generated') &&
                (!req.payrollId || !(req.payrollId.payslipUrl || req.payrollId.payslip_url))) {
                const payroll = await Payroll.findOne({
                    employeeId: req.employeeId,
                    month: req.month,
                    year: req.year
                })
                    .select('month year netPay grossSalary payslipUrl')
                    .lean();
                if (payroll && (payroll.payslipUrl || payroll.payslip_url)) {
                    req.payrollId = {
                        _id: payroll._id,
                        month: payroll.month,
                        year: payroll.year,
                        netPay: payroll.netPay,
                        grossSalary: payroll.grossSalary,
                        payslipUrl: payroll.payslipUrl || payroll.payslip_url
                    };
                }
            }
        }

        const total = await PayslipRequest.countDocuments(query);

        res.json({
            success: true,
            data: {
                requests,
                pagination: {
                    page: pageNum,
                    limit: limitNum,
                    total,
                    pages: Math.ceil(total / limitNum)
                }
            }
        });
    } catch (error) {
        console.error('Get Payslip Requests Error:', error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    View Payslip for Approved Request
// @route   GET /api/requests/payslip/:id/view
// @access  Private
// Uses payroll.payslipUrl when available (no salary calculation or PDF generation).
const viewPayslipRequest = async (req, res) => {
    try {
        const { id } = req.params;

        if (!id) {
            return res.status(400).json({
                success: false,
                error: { message: 'Request ID is required' }
            });
        }

        const request = await PayslipRequest.findById(id)
            .populate('employeeId', 'name employeeId')
            .populate('payrollId', 'month year payslipUrl');

        if (!request) {
            return res.status(404).json({
                success: false,
                error: { message: 'Payslip request not found' }
            });
        }

        if (request.status !== 'Approved' && request.status !== 'Generated') {
            return res.status(400).json({
                success: false,
                error: { message: 'Payslip request is not approved yet' }
            });
        }

        const payroll = request.payrollId;
        let payslipUrl = payroll && (payroll.payslipUrl || payroll.payslip_url);
        if (!payslipUrl && request.month != null && request.year != null) {
            const employeeId = request.employeeId?._id || request.employeeId;
            const lookup = await Payroll.findOne({
                employeeId,
                month: request.month,
                year: request.year
            }).select('payslipUrl').lean();
            payslipUrl = lookup && (lookup.payslipUrl || lookup.payslip_url);
        }
        if (payslipUrl && typeof payslipUrl === 'string' && payslipUrl.trim()) {
            return res.json({ success: true, payslipUrl: payslipUrl.trim() });
        }

        return res.status(400).json({
            success: false,
            error: { message: 'Approved – wait for generation. Payslip will be available once generated.' }
        });
    } catch (error) {
        console.error('View Payslip Request Error:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to view payslip' }
        });
    }
};

// @desc    Download Payslip for Approved Request
// @route   GET /api/requests/payslip/:id/download
// @access  Private
// Uses payroll.payslipUrl when available (no salary calculation or PDF generation).
const downloadPayslipRequest = async (req, res) => {
    try {
        const { id } = req.params;

        if (!id) {
            return res.status(400).json({
                success: false,
                error: { message: 'Request ID is required' }
            });
        }

        const request = await PayslipRequest.findById(id)
            .populate('employeeId', 'name employeeId')
            .populate('payrollId', 'month year payslipUrl');

        if (!request) {
            return res.status(404).json({
                success: false,
                error: { message: 'Payslip request not found' }
            });
        }

        if (request.status !== 'Approved' && request.status !== 'Generated') {
            return res.status(400).json({
                success: false,
                error: { message: 'Payslip request is not approved yet' }
            });
        }

        const payroll = request.payrollId;
        let payslipUrl = payroll && (payroll.payslipUrl || payroll.payslip_url);
        if (!payslipUrl && request.month != null && request.year != null) {
            const employeeId = request.employeeId?._id || request.employeeId;
            const lookup = await Payroll.findOne({
                employeeId,
                month: request.month,
                year: request.year
            }).select('payslipUrl').lean();
            payslipUrl = lookup && (lookup.payslipUrl || lookup.payslip_url);
        }
        if (payslipUrl && typeof payslipUrl === 'string' && payslipUrl.trim()) {
            return res.json({ success: true, payslipUrl: payslipUrl.trim() });
        }

        return res.status(400).json({
            success: false,
            error: { message: 'Approved – wait for generation. Payslip will be available once generated.' }
        });
    } catch (error) {
        console.error('Download Payslip Request Error:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to download payslip' }
        });
    }
};

module.exports = {
    applyLeave,
    getLeaveRequests,
    applyLoan,
    getLoanRequests,
    applyExpense,
    getExpenseRequests,
    requestPayslip,
    getPayslipRequests,
    viewPayslipRequest,
    downloadPayslipRequest
};
