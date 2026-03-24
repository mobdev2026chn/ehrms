const Payroll = require('../models/Payroll');
const Staff = require('../models/Staff');
const Attendance = require('../models/Attendance');
const Leave = require('../models/Leave');
const Company = require('../models/Company');
const mongoose = require('mongoose');
const { getEffectiveFineConfig } = require('../utils/fineCalculationHelper');
const { calculateFineAmount } = require('../utils/fineCalculationHelper');
const { getShiftTimings } = require('../utils/leaveAttendanceHelper');
const { calculateWorkHoursFromShift } = require('../utils/leaveAttendanceHelper');
const { getHolidayTemplateForStaff, getHolidaysForMonth } = require('../utils/holidayTemplateHelper');

/**
 * Get fine amount for a single attendance record.
 * Uses record.fineAmount when set; otherwise computes from record.lateMinutes or record.fineHours
 * (e.g. Excel-imported records that have fineHours but no fineAmount).
 * @param {Object} record - Attendance document
 * @param {number} dailySalary - Net daily salary for shift-based formula
 * @param {number} shiftHours - Shift duration in hours
 * @param {Object} fineConfig - From getEffectiveFineConfig(company)
 * @returns {number} Fine amount (>= 0)
 */
function getRecordFineAmount(record, dailySalary, shiftHours, fineConfig) {
    const existing = Number(record.fineAmount);
    if (existing > 0) return existing;
    const minutes = Number(record.lateMinutes) || Number(record.fineHours) || 0;
    if (minutes <= 0) return 0;
    if (!fineConfig || !fineConfig.enabled || !dailySalary || dailySalary <= 0 || !shiftHours || shiftHours <= 0) {
        return 0;
    }
    return calculateFineAmount(minutes, 'lateArrival', fineConfig, dailySalary, shiftHours);
}

/**
 * Full-month salary from staff.salary (same thresholds as web salaryStructureCalculation + Flutter).
 * Estimated MTD in app/web: proratedGross = grossSalary * (presentDays / fullMonthWorkingDays),
 * proratedDeductions = totalMonthlyDeductions * same factor, net MTD = proratedGross - proratedDeductions - fines.
 */
function computeMonthlySalaryFromStaffSalary(s) {
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
    const grossFixedSalary = basicSalary + dearnessAllowance + houseRentAllowance + specialAllowance;
    const employerPF = employerPFRate / 100 * basicSalary;
    const employerESI = employerESIRate / 100 * grossFixedSalary;
    const grossSalary = grossFixedSalary + employerPF + employerESI + pfStaticAmount;
    const employeePF = employeePFRate > 0 ? (employeePFRate / 100 * basicSalary) : pfStaticAmount;
    const employeeESI = employeeESIRate / 100 * grossSalary;
    const totalMonthlyDeductions = employeePF + employeeESI;
    const netSalary = grossSalary - totalMonthlyDeductions;
    return {
        basicSalary,
        dearnessAllowance,
        houseRentAllowance,
        specialAllowance,
        grossFixedSalary,
        employerPF,
        employerESI,
        pfStaticAmount,
        grossSalary,
        employeePF,
        employeeESI,
        totalMonthlyDeductions,
        netSalary
    };
}

// @desc    Get Payrolls (Payslips)
// @route   GET /api/payrolls
// @access  Private
const getPayrolls = async (req, res) => {
    try {
        const { month, year, status, search, page = 1, limit = 10 } = req.query;
        const query = {};

        // Scope to current employee if logged in as staff
        if (req.staff) {
            query.employeeId = req.staff._id;
        } else if (req.user && req.user.role === 'Employee') {
            const staff = await Staff.findOne({ userId: req.user._id });
            if (staff) query.employeeId = staff._id;
            else return res.json({ success: true, data: { payrolls: [], pagination: { page, limit, total: 0, pages: 0 } } });
        }

        // Filters
        if (month) query.month = Number(month);
        if (year) query.year = Number(year);
        if (status && status !== 'all') query.status = status;

        const skip = (Number(page) - 1) * Number(limit);

        const payrolls = await Payroll.find(query)
            .populate('employeeId', 'name employeeId designation department')
            .sort({ year: -1, month: -1 })
            .skip(skip)
            .limit(Number(limit));

        const total = await Payroll.countDocuments(query);

        res.json({
            success: true,
            data: {
                payrolls,
                pagination: {
                    page: Number(page),
                    limit: Number(limit),
                    total,
                    pages: Math.ceil(total / Number(limit))
                }
            }
        });

    } catch (error) {
        console.error('getPayrolls Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

// @desc    Get Payroll By ID
// @route   GET /api/payrolls/:id
// @access  Private
const getPayrollById = async (req, res) => {
    try {
        const payroll = await Payroll.findById(req.params.id)
            .populate('employeeId', 'name employeeId designation department');

        if (!payroll) {
            return res.status(404).json({ success: false, error: { message: 'Payroll not found' } });
        }

        // Security check: ensure staff can only see their own
        if (req.staff && payroll.employeeId && payroll.employeeId._id.toString() !== req.staff._id.toString()) {
            return res.status(403).json({ success: false, error: { message: 'Not authorized to view this payslip' } });
        }

        res.json({
            success: true,
            data: { payroll }
        });
    } catch (error) {
        console.error('getPayrollById Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

// @desc    Get Payroll Stats (For Dashboard/Overview)
// @route   GET /api/payrolls/stats
// @access  Private
const getPayrollStats = async (req, res) => {
    try {
        const staffIdForLog = req.staff?._id || req.user?._id;
        console.log(`[getPayrollStats] API called for staff/user: ${staffIdForLog}`);
        const { month, year } = req.query;
        const currentMonth = month ? Number(month) : new Date().getMonth() + 1;
        const currentYear = year ? Number(year) : new Date().getFullYear();

        let staffId;
        if (req.staff) {
            staffId = req.staff._id;
        } else if (req.user && req.user.role === 'Employee') {
            const staff = await Staff.findOne({ userId: req.user._id });
            if (staff) staffId = staff._id;
        }

        if (!staffId) {
            return res.status(400).json({ success: false, error: { message: 'Staff context required' } });
        }

        // 1. Try to find existing payroll
        const payroll = await Payroll.findOne({
            employeeId: staffId,
            month: currentMonth,
            year: currentYear
        });

        if (payroll) {
            // If exists, return processed stats
            const attendanceStats = await calculateAttendanceStats(staffId, currentMonth, currentYear);
            
            // Use THIS MONTH working days for proration (so This Month Gross = presentDays * dailySalary, dailySalary = monthly/thisMonthWorkingDays)
            const workingDays = attendanceStats.workingDays || 0;
            const thisMonthWorkingDays = attendanceStats.workingDaysFullMonth ?? workingDays;
            const presentDays = attendanceStats.presentDays || 0;
            const paidLeaveDays = attendanceStats.paidLeaveDays || 0;
            // Match web EmployeeSalaryOverview + Flutter: prorate on present days only (not paid leave).
            const prorationFactor = thisMonthWorkingDays > 0 ? presentDays / thisMonthWorkingDays : 1;
            console.log(`[getPayrollStats] Payroll exists path: thisMonthWorkingDays=${thisMonthWorkingDays}, workingDaysTillToday=${workingDays}, presentDays=${presentDays}, paidLeaveDays=${paidLeaveDays}, prorationFactor=${prorationFactor}`);
            
            // Get fine amount from attendance records
            const Attendance = require('../models/Attendance');
            const startOfMonth = new Date(currentYear, currentMonth - 1, 1);
            const endOfMonth = new Date(currentYear, currentMonth, 0, 23, 59, 59, 999);
            const attendanceRecords = await Attendance.find({
                $or: [
                    { employeeId: staffId },
                    { user: staffId }
                ],
                date: { $gte: startOfMonth, $lte: endOfMonth }
            });

            // Get staff salary structure for correct proration and for fine fallback (must select +salary)
            let thisMonthGross = 0;
            let thisMonthNet = 0;

            const staffForProration = await Staff.findById(staffId).select('+salary');
            console.log(`[getPayrollStats] staffForProration found: ${!!staffForProration}, has salary: ${!!(staffForProration && staffForProration.salary)}`);

            // Total fine: use record.fineAmount when set; for records with fineHours/lateMinutes but no fineAmount (e.g. Excel import), compute from fine config
            const staffRef = staffForProration || await Staff.findById(staffId);
            const company = await Company.findById(staffRef?.businessId).lean();
            const fineConfig = company ? getEffectiveFineConfig(company) : null;
            const shiftTimings = company && staffRef ? getShiftTimings(company, staffRef) : {};
            const shiftHours = Math.max(0, calculateWorkHoursFromShift(shiftTimings.startTime || '09:30', shiftTimings.endTime || '18:30') || 9);
            const dailySalaryForFine = thisMonthWorkingDays > 0
                ? (staffForProration?.salary
                    ? (() => {
                        const s = staffForProration.salary;
                        const basic = (s.basicSalary || 0);
                        const da = (s.dearnessAllowance || 0);
                        const hra = (s.houseRentAllowance || 0);
                        const sa = (s.specialAllowance || 0);
                        const basicPlusDA = basic + da;
                        const basicPlusDAPlusHRA = basic + da + hra;
                        const isPFApplicable = basicPlusDA < 15000;
                        const isESIApplicable = basicPlusDAPlusHRA < 21000;
                        const employerPFRate = isPFApplicable ? (s.employerPFRate || 0) : 0;
                        const employerESIRate = isESIApplicable ? (s.employerESIRate || 0) : 0;
                        const employeePFRate = isPFApplicable ? (s.employeePFRate || 0) : 0;
                        const employeeESIRate = isESIApplicable ? (s.employeeESIRate || 0) : 0;
                        const pfStaticAmount = isPFApplicable ? 0 : 1800;
                        const gf = basic + da + hra + sa;
                        const epf = employerPFRate / 100 * basic;
                        const eesi = employerESIRate / 100 * gf;
                        const gross = gf + epf + eesi + pfStaticAmount;
                        const empPF = employeePFRate > 0 ? (employeePFRate / 100 * basic) : pfStaticAmount;
                        const empESI = employeeESIRate / 100 * gross;
                        return (gross - empPF - empESI) / thisMonthWorkingDays;
                    })()
                    : (Number(payroll.netPay) / thisMonthWorkingDays))
                : 0;

            const totalFineAmount = attendanceRecords
                .filter(r => {
                    const s = (r.status || '').trim().toLowerCase();
                    const lt = (r.leaveType || '').trim().toLowerCase();
                    return s === 'present' || s === 'approved' || s === 'half day' || lt === 'half day';
                })
                .reduce((sum, record) => sum + getRecordFineAmount(record, dailySalaryForFine, shiftHours, fineConfig), 0);

            if (staffForProration && staffForProration.salary) {
                console.log(`[getPayrollStats] Using salary structure for proration (linear MTD, web/Flutter parity)`);
                const m = computeMonthlySalaryFromStaffSalary(staffForProration.salary);
                thisMonthGross = m.grossSalary * prorationFactor;
                const proratedDeductions = m.totalMonthlyDeductions * prorationFactor;
                thisMonthNet = thisMonthGross - proratedDeductions - totalFineAmount;
                const oneDaySalary = thisMonthWorkingDays > 0 ? (m.netSalary / thisMonthWorkingDays).toFixed(2) : null;
                console.log(`[getPayrollStats] Calculated from salary structure: thisMonthGross=${thisMonthGross}, thisMonthNet=${thisMonthNet}, proratedDeductions=${proratedDeductions}, totalFineAmount=${totalFineAmount}`);
                if (oneDaySalary) console.log(`[getPayrollStats] 1 day salary = Monthly NET / this month WD = ${oneDaySalary} (same as salary overview)`);
            } else {
                // Fallback to simple proration if salary structure not available
                console.log(`[getPayrollStats] FALLBACK: Using payroll.netPay=${payroll.netPay} * prorationFactor=${prorationFactor}`);
                thisMonthGross = payroll.grossSalary * prorationFactor;
                thisMonthNet = (payroll.netPay * prorationFactor) - totalFineAmount;
                console.log(`[getPayrollStats] Fallback result: thisMonthGross=${thisMonthGross}, thisMonthNet=${thisMonthNet}`);
            }

            // Calculate CTC from payroll components if available, otherwise estimate
            const earnings = payroll.components.filter(c => c.type === 'earning');
            const annualGrossSalary = payroll.grossSalary * 12;
            
            // Try to calculate benefits from staff salary if available
            let annualBenefits = 0;
            if (staffForProration && staffForProration.salary) {
                const s = staffForProration.salary;
                const basicSalary = s.basicSalary || 0;
                const annualGratuity = (s.gratuityRate || 0) / 100 * (basicSalary * 12);
                const annualStatutoryBonus = (s.statutoryBonusRate || 0) / 100 * (basicSalary * 12);
                const medicalInsuranceAmount = s.medicalInsuranceAmount || 0;
                annualBenefits = annualGratuity + annualStatutoryBonus + medicalInsuranceAmount;
            }
            
            const totalCTC = annualGrossSalary + annualBenefits;

            return res.json({
                success: true,
                data: {
                    month: currentMonth,
                    year: currentYear,
                    isProcessed: true,
                    stats: {
                        grossSalary: payroll.grossSalary,
                        netSalary: payroll.netPay,
                        thisMonthGross: thisMonthGross,
                        thisMonthNet: thisMonthNet,
                        deductions: payroll.deductions,
                        attendance: attendanceStats,
                        earnings: earnings,
                        deductionComponents: [
                            ...payroll.components.filter(c => c.type === 'deduction'),
                            ...(totalFineAmount > 0 ? [{ name: 'Late Login Fine', amount: totalFineAmount }] : [])
                        ],
                        ctc: totalCTC,
                        annualGrossSalary: annualGrossSalary,
                        annualBenefits: annualBenefits
                    }
                }
            });
        }

        // 2. If no payroll, calculate estimated (Pro-rata)
        console.log(`[getPayrollStats] No payroll found - using estimated pro-rata path`);
        const staff = await Staff.findById(staffId).select('+salary');
        if (!staff || !staff.salary) {
            console.log(`[getPayrollStats] EARLY RETURN: staff found=${!!staff}, staff.salary found=${!!(staff?.salary)}`);
            return res.json({
                success: true,
                data: {
                    month: currentMonth,
                    year: currentYear,
                    isProcessed: false,
                    message: "Salary details not found",
                    stats: null
                }
            });
        }

        const attendanceStats = await calculateAttendanceStats(staffId, currentMonth, currentYear);
        const s = staff.salary;
        const m = computeMonthlySalaryFromStaffSalary(s);

        const workingDays = attendanceStats.workingDays || 0;
        const thisMonthWorkingDays = attendanceStats.workingDaysFullMonth ?? workingDays;
        const presentDays = attendanceStats.presentDays || 0;
        const paidLeaveDays = attendanceStats.paidLeaveDays || 0;
        const prorationFactor = thisMonthWorkingDays > 0 ? presentDays / thisMonthWorkingDays : 0;
        console.log(`[getPayrollStats] No-payroll path (linear MTD, present-only factor): thisMonthWorkingDays=${thisMonthWorkingDays}, workingDaysTillToday=${workingDays}, presentDays=${presentDays}, paidLeaveDays=${paidLeaveDays}, prorationFactor=${prorationFactor}`);

        const Attendance = require('../models/Attendance');
        const startOfMonth = new Date(currentYear, currentMonth - 1, 1);
        const endOfMonth = new Date(currentYear, currentMonth, 0, 23, 59, 59, 999);
        const attendanceRecords = await Attendance.find({
            $or: [
                { employeeId: staffId },
                { user: staffId }
            ],
            date: { $gte: startOfMonth, $lte: endOfMonth }
        });
        const companyNoPayroll = await Company.findById(staff.businessId).lean();
        const fineConfigNoPayroll = companyNoPayroll ? getEffectiveFineConfig(companyNoPayroll) : null;
        const shiftTimingsNoPayroll = companyNoPayroll && staff ? getShiftTimings(companyNoPayroll, staff) : {};
        const shiftHoursNoPayroll = Math.max(0, calculateWorkHoursFromShift(shiftTimingsNoPayroll.startTime || '09:30', shiftTimingsNoPayroll.endTime || '18:30') || 9);
        const dailySalaryNoPayrollForFine = thisMonthWorkingDays > 0 ? (m.netSalary / thisMonthWorkingDays) : 0;
        const totalFineAmount = attendanceRecords
            .filter(r => {
                const st = (r.status || '').trim().toLowerCase();
                const lt = (r.leaveType || '').trim().toLowerCase();
                return st === 'present' || st === 'approved' || st === 'half day' || lt === 'half day';
            })
            .reduce((sum, record) => sum + getRecordFineAmount(record, dailySalaryNoPayrollForFine, shiftHoursNoPayroll, fineConfigNoPayroll), 0);

        const thisMonthGross = m.grossSalary * prorationFactor;
        const proratedDeductions = m.totalMonthlyDeductions * prorationFactor;
        const thisMonthNet = thisMonthGross - proratedDeductions - totalFineAmount;
        const oneDaySalaryNoPayroll = thisMonthWorkingDays > 0 ? (m.netSalary / thisMonthWorkingDays).toFixed(2) : null;
        console.log(`[getPayrollStats] No-payroll path: thisMonthGross=${thisMonthGross?.toFixed?.(2)}, thisMonthNet=${thisMonthNet?.toFixed?.(2)}, proratedDeductions=${proratedDeductions?.toFixed?.(2)}`);
        if (oneDaySalaryNoPayroll) console.log(`[getPayrollStats] 1 day salary = Monthly NET / this month WD = ${oneDaySalaryNoPayroll} (same as salary overview)`);

        // Calculate Annual Benefits for CTC
        const annualGrossSalary = m.grossSalary * 12;
        const annualGratuity = (s.gratuityRate || 0) / 100 * (m.basicSalary * 12);
        const annualStatutoryBonus = (s.statutoryBonusRate || 0) / 100 * (m.basicSalary * 12);
        const medicalInsuranceAmount = s.medicalInsuranceAmount || 0;
        const totalAnnualBenefits = annualGratuity + annualStatutoryBonus + medicalInsuranceAmount;
        
        // Annual Incentive (same component rule as web): % of annual basic
        const annualIncentive = (s.incentiveRate || 0) / 100 * (m.basicSalary * 12);
        
        // Mobile Allowance (Annual)
        const mobileAllowance = s.mobileAllowance || 0;
        const annualMobileAllowance = s.mobileAllowanceType === 'yearly' ? mobileAllowance : (mobileAllowance * 12);
        
        // Total CTC = Annual Gross + Incentive + Benefits + Allowances
        const totalCTC = annualGrossSalary + annualIncentive + totalAnnualBenefits + annualMobileAllowance;

        res.json({
            success: true,
            data: {
                month: currentMonth,
                year: currentYear,
                isProcessed: false,
                stats: {
                    grossSalary: m.grossSalary,
                    netSalary: m.netSalary,
                    thisMonthGross: thisMonthGross,
                    thisMonthNet: thisMonthNet,
                    deductions: m.totalMonthlyDeductions,
                    attendance: attendanceStats,
                    earnings: [
                        { name: 'Basic Salary', amount: m.basicSalary },
                        { name: 'DA', amount: m.dearnessAllowance },
                        { name: 'HRA', amount: m.houseRentAllowance },
                        { name: 'Employer PF', amount: m.employerPF },
                        { name: 'Employer ESI', amount: m.employerESI },
                        ...(m.pfStaticAmount > 0 ? [{ name: 'Statutory PF (Fixed)', amount: m.pfStaticAmount }] : [])
                    ],
                    deductionComponents: [
                        { name: 'Employee PF', amount: m.employeePF * prorationFactor },
                        { name: 'Employee ESI', amount: m.employeeESI * prorationFactor },
                        ...(totalFineAmount > 0 ? [{ name: 'Late Login Fine', amount: totalFineAmount }] : [])
                    ],
                    ctc: totalCTC,
                    annualGrossSalary: annualGrossSalary,
                    annualBenefits: totalAnnualBenefits
                }
            }
        });

    } catch (error) {
        console.error('getPayrollStats Error:', error);
        console.error('getPayrollStats Error Stack:', error.stack);
        res.status(500).json({ success: false, error: { message: error.message || 'Internal server error' } });
    }
};

/**
 * POST /api/payrolls/preview — MTD estimate for employee (matches web payroll preview semantics).
 * Proration: (presentDays + paidLeaveDays) / fullMonthWorkingDays; fines subtracted from net.
 */
const previewPayrollEmployee = async (req, res) => {
    try {
        const { month, year, employeeId } = req.body || {};

        let staffId;
        if (req.staff && req.staff._id) {
            staffId = req.staff._id;
        }
        if (!staffId && req.user && req.user.role === 'Employee') {
            const st = await Staff.findOne({ userId: req.user._id });
            if (st) staffId = st._id;
        }
        if (!staffId) {
            return res.status(400).json({ success: false, error: { message: 'Staff context required' } });
        }

        let targetStaffId = staffId;
        if (employeeId && mongoose.Types.ObjectId.isValid(employeeId)) {
            const requested = new mongoose.Types.ObjectId(employeeId);
            if (requested.toString() !== staffId.toString()) {
                return res.status(403).json({ success: false, error: { message: 'Not authorized to preview other employees' } });
            }
            targetStaffId = requested;
        }

        const currentMonth = month ? Number(month) : new Date().getMonth() + 1;
        const currentYear = year ? Number(year) : new Date().getFullYear();

        const existingPayroll = await Payroll.findOne({
            employeeId: targetStaffId,
            month: currentMonth,
            year: currentYear
        });
        if (existingPayroll) {
            return res.json({
                success: true,
                data: { preview: null, hasPayroll: true }
            });
        }

        const staff = await Staff.findById(targetStaffId).select('+salary');
        if (!staff || !staff.salary) {
            return res.json({ success: false, error: { message: 'Salary details not found' } });
        }

        const attendanceStats = await calculateAttendanceStats(targetStaffId, currentMonth, currentYear);
        const m = computeMonthlySalaryFromStaffSalary(staff.salary);
        const workingDaysTill = attendanceStats.workingDays || 0;
        const thisMonthWorkingDays = attendanceStats.workingDaysFullMonth || workingDaysTill || 1;
        const presentDays = attendanceStats.presentDays || 0;
        const paidLeaveDays = attendanceStats.paidLeaveDays || 0;
        const effectivePaidDays = presentDays + paidLeaveDays;
        const prorationFactor = thisMonthWorkingDays > 0 ? effectivePaidDays / thisMonthWorkingDays : 0;

        const startOfMonth = new Date(currentYear, currentMonth - 1, 1);
        const endOfMonth = new Date(currentYear, currentMonth, 0, 23, 59, 59, 999);
        const attendanceRecords = await Attendance.find({
            $or: [{ employeeId: targetStaffId }, { user: targetStaffId }],
            date: { $gte: startOfMonth, $lte: endOfMonth }
        });
        const companyNoPayroll = await Company.findById(staff.businessId).lean();
        const fineConfigNoPayroll = companyNoPayroll ? getEffectiveFineConfig(companyNoPayroll) : null;
        const shiftTimingsNoPayroll = companyNoPayroll && staff ? getShiftTimings(companyNoPayroll, staff) : {};
        const shiftHoursNoPayroll = Math.max(0, calculateWorkHoursFromShift(shiftTimingsNoPayroll.startTime || '09:30', shiftTimingsNoPayroll.endTime || '18:30') || 9);
        const dailySalaryNoPayrollForFine = thisMonthWorkingDays > 0 ? (m.netSalary / thisMonthWorkingDays) : 0;
        const totalFineAmount = attendanceRecords
            .filter(r => {
                const st = (r.status || '').trim().toLowerCase();
                const lt = (r.leaveType || '').trim().toLowerCase();
                return st === 'present' || st === 'approved' || st === 'half day' || lt === 'half day';
            })
            .reduce((sum, record) => sum + getRecordFineAmount(record, dailySalaryNoPayrollForFine, shiftHoursNoPayroll, fineConfigNoPayroll), 0);

        const thisMonthGross = m.grossSalary * prorationFactor;
        const proratedDeductions = m.totalMonthlyDeductions * prorationFactor;
        const thisMonthNet = Math.max(0, thisMonthGross - proratedDeductions - totalFineAmount);

        const pf = (name, amt, type) => ({
            name,
            amount: Math.round(amt * 100) / 100,
            type
        });
        const earnings = [
            pf('Basic Salary', m.basicSalary * prorationFactor, 'earning'),
            pf('DA', m.dearnessAllowance * prorationFactor, 'earning'),
            pf('HRA', m.houseRentAllowance * prorationFactor, 'earning'),
        ];
        if ((m.specialAllowance || 0) * prorationFactor > 0.005) {
            earnings.push(pf('Special Allowance', m.specialAllowance * prorationFactor, 'earning'));
        }
        earnings.push(
            pf('Employer PF', m.employerPF * prorationFactor, 'earning'),
            pf('Employer ESI', m.employerESI * prorationFactor, 'earning')
        );
        if (m.pfStaticAmount > 0) {
            earnings.push(pf('Statutory PF (Fixed)', m.pfStaticAmount * prorationFactor, 'earning'));
        }

        const deductions = [
            pf('Employee PF', m.employeePF * prorationFactor, 'deduction'),
            pf('Employee ESI', m.employeeESI * prorationFactor, 'deduction'),
        ];
        if (totalFineAmount > 0) {
            deductions.push(pf('Late Login Fine', totalFineAmount, 'deduction'));
        }

        const attendancePercentage = workingDaysTill > 0 ? (effectivePaidDays / workingDaysTill) * 100 : 0;

        return res.json({
            success: true,
            data: {
                preview: {
                    grossSalary: Math.round(thisMonthGross * 100) / 100,
                    netPay: Math.round(thisMonthNet * 100) / 100,
                    deductions: Math.round((proratedDeductions + totalFineAmount) * 100) / 100,
                    components: [...earnings, ...deductions],
                    attendance: {
                        presentDays: effectivePaidDays,
                        workingDays: thisMonthWorkingDays,
                        workingDaysTillCurrentDate: workingDaysTill,
                        attendancePercentage: Math.round(attendancePercentage * 100) / 100
                    }
                }
            }
        });
    } catch (error) {
        console.error('previewPayrollEmployee Error:', error);
        res.status(500).json({ success: false, error: { message: error.message || 'Internal server error' } });
    }
};

const calculateAttendanceStats = async (employeeId, month, year) => {
    const startDate = new Date(year, month - 1, 1);
    const endDate = new Date(year, month, 0, 23, 59, 59);

    const attendanceRecords = await Attendance.find({
        $or: [
            { employeeId: employeeId },
            { user: employeeId }
        ],
        date: { $gte: startDate, $lte: endDate }
    });

    const staff = await Staff.findById(employeeId).populate('branchId').populate('weeklyHolidayTemplateId');

    // Week-off: staff's WeeklyHolidayTemplate when assigned, else business (Company.settings.business)
    let weeklyOffPattern = 'standard';
    let weeklyHolidays = [{ day: 0, name: 'Sunday' }];
    if (staff && staff.businessId) {
        const Company = require('../models/Company');
        const business = await Company.findById(staff.businessId);
        const { getWeekOffConfigForStaff } = require('../utils/weekOffHelper');
        const weekOffConfig = await getWeekOffConfigForStaff(staff, business || undefined);
        weeklyOffPattern = weekOffConfig.weeklyOffPattern;
        weeklyHolidays = weekOffConfig.weeklyHolidays;
    }

    console.log(`[calculateAttendanceStats] Weekly Off Pattern: ${weeklyOffPattern}`);
    console.log(`[calculateAttendanceStats] Weekly Holidays: ${JSON.stringify(weeklyHolidays)}`);
    
    // Get holiday dates for the month - store as day numbers (1-31) for comparison
    // Use same date parsing logic as dashboard (local time, not UTC)
    const holidayDayNumbers = new Set();
    if (staff && staff.businessId) {
        const holidayTemplate = await getHolidayTemplateForStaff(staff);
        const holidays = getHolidaysForMonth(holidayTemplate, year, month);

        holidays.forEach(h => {
            const d = new Date(h.date);
            const holidayDay = d.getDate();
            holidayDayNumbers.add(holidayDay);
            console.log(`[calculateAttendanceStats] Found holiday: Day ${holidayDay}, Month ${month}, Year ${year}`);
        });
    }
    
    // Count days in month
    const daysInMonth = endDate.getDate();
    let weeklyOffDays = 0; // Days that are weekly off (not holidays) in range
    let holidays = 0;

    // Cap at today: don't count future days. For dashboard/salary/payroll, working days and absent
    // should only consider dates up to and including today.
    const now = new Date();
    const currentYear = now.getFullYear();
    const currentMonth = now.getMonth() + 1; // 1-12
    const currentDay = now.getDate();
    let lastDayToCount = daysInMonth;
    if (year > currentYear || (year === currentYear && month > currentMonth)) {
        lastDayToCount = 0; // Future month: no days to count
    } else if (year === currentYear && month === currentMonth) {
        lastDayToCount = currentDay; // Current month: only up to today
    }
    console.log(`[calculateAttendanceStats] Cap at today: lastDayToCount=${lastDayToCount} (current: ${currentYear}-${currentMonth}-${currentDay})`);

    // Count weekly off days and holidays only for days 1..lastDayToCount
    // Working days = days in range - Weekly Off Days - Holidays (so future days are not counted as absent)
    for (let day = 1; day <= lastDayToCount; day++) {
        const currentDate = new Date(year, month - 1, day);
        currentDate.setHours(0, 0, 0, 0);
        const dayOfWeek = currentDate.getDay(); // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
        const isHoliday = holidayDayNumbers.has(day);
        
        if (isHoliday) {
            // Count as holiday (even if it falls on weekly off day)
            holidays++;
            console.log(`[calculateAttendanceStats] Day ${day} is a holiday (Day of week: ${dayOfWeek})`);
        } else {
            // Check if this day is a weekly off day
            let isWeeklyOff = false;
            
            if (weeklyOffPattern === 'oddEvenSaturday') {
                // oddEvenSaturday pattern: Don't check weeklyHolidays
                // Odd Saturdays (1st, 3rd, 5th, etc.) are WORKING DAYS
                // Even Saturdays (2nd, 4th, 6th, etc.) are WEEKLY OFF
                // All Sundays are WEEKLY OFF
                if (dayOfWeek === 0) {
                    // Sunday - always weekly off
                    isWeeklyOff = true;
                } else if (dayOfWeek === 6) {
                    // Saturday - check if even (weekly off) or odd (working)
                    if (day % 2 === 0) {
                        // Even Saturday - weekly off
                        isWeeklyOff = true;
                        console.log(`[calculateAttendanceStats] Day ${day} is Even Saturday (weekly off)`);
                    } else {
                        // Odd Saturday - working day
                        console.log(`[calculateAttendanceStats] Day ${day} is Odd Saturday (working day)`);
                    }
                }
            } else {
                // Standard pattern: Check weeklyHolidays array (same logic as dashboard)
                // dayOfWeek: 0=Sunday, 1=Monday, ..., 6=Saturday
                // Dashboard uses: isWeekOff = weeklyHolidays.some(h => h.day === dayOfWeek)
                // Keep same logic - weeklyHolidays is array of objects with 'day' property
                if (weeklyHolidays.some(h => h.day === dayOfWeek)) {
                    isWeeklyOff = true;
                }
            }
            
            if (isWeeklyOff) {
                weeklyOffDays++;
            }
        }
    }
    
    // Working days = days in range (1..lastDayToCount) - Weekly Off Days - Holidays
    const workingDays = lastDayToCount - weeklyOffDays - holidays;

    // Full month working days (for display: "This month working days" in dashboard/salary/payroll)
    let weeklyOffDaysFull = 0;
    let holidaysFull = 0;
    for (let day = 1; day <= daysInMonth; day++) {
        const currentDate = new Date(year, month - 1, day);
        currentDate.setHours(0, 0, 0, 0);
        const dayOfWeek = currentDate.getDay();
        const isHoliday = holidayDayNumbers.has(day);
        if (isHoliday) {
            holidaysFull++;
        } else {
            let isWeeklyOff = false;
            if (weeklyOffPattern === 'oddEvenSaturday') {
                if (dayOfWeek === 0) isWeeklyOff = true;
                else if (dayOfWeek === 6 && day % 2 === 0) isWeeklyOff = true;
            } else {
                isWeeklyOff = weeklyHolidays.some(h => h.day === dayOfWeek);
            }
            if (isWeeklyOff) weeklyOffDaysFull++;
        }
    }
    const workingDaysFullMonth = daysInMonth - weeklyOffDaysFull - holidaysFull;
    
    // Debug logging
    console.log(`[calculateAttendanceStats] ========== CALCULATION DEBUG ==========`);
    console.log(`[calculateAttendanceStats] Month: ${month}, Year: ${year}`);
    console.log(`[calculateAttendanceStats] Weekly Off Pattern: ${weeklyOffPattern}`);
    console.log(`[calculateAttendanceStats] Weekly Holidays (days of week): ${weeklyHolidays.map(h => h.day).join(', ')}`);
    console.log(`[calculateAttendanceStats] Total days in month: ${daysInMonth}`);
    console.log(`[calculateAttendanceStats] Weekly Off Days (non-holiday): ${weeklyOffDays}`);
    console.log(`[calculateAttendanceStats] Holidays: ${holidays}`);
    console.log(`[calculateAttendanceStats] Holiday day numbers: ${Array.from(holidayDayNumbers).sort((a, b) => a - b).join(', ')}`);
    console.log(`[calculateAttendanceStats] Working days calculation: lastDayToCount=${lastDayToCount}, ${lastDayToCount} - ${weeklyOffDays} - ${holidays} = ${workingDays}`);
    console.log(`[calculateAttendanceStats] ======================================`);

    // Calculate Present Days with specific Half Day logic
    // Rule: Check both Attendance and Leave collections for Half Day
    // Filter leaves by date range to avoid including leaves from other months
    const leaveRecords = await Leave.find({
        employeeId: employeeId,
        status: { $regex: /^approved$/i },
        $or: [
            { startDate: { $gte: startDate, $lte: endDate } },
            { endDate: { $gte: startDate, $lte: endDate } },
            { startDate: { $lte: startDate }, endDate: { $gte: endDate } }
        ]
    }).lean();

    const dateMap = {};

    // 1. Process Attendance Records
    attendanceRecords.forEach(a => {
        if (!a.date) return;
        const d = new Date(a.date).toISOString().split('T')[0];
        const status = (a.status || '').trim().toLowerCase();
        const leaveType = (a.leaveType || '').trim().toLowerCase();
        const isPaidLeave = a.isPaidLeave === true;
        const compensationType = (a.compensationType || '').trim().toLowerCase();
        dateMap[d] = {
            attendanceStatus: status,
            attendanceLeaveType: leaveType,
            isPaidLeave,
            compensationType
        };
    });

    // 2. Process Leave Records for Half Day and build leave-date set (for leave count)
    // leaveDateToHalfDay: dateStr -> true if that date is half-day leave
    const leaveDateToHalfDay = {};
    leaveRecords.forEach(l => {
        const isHalfDayLeave = l.isHalfDay === true || (l.leaveType || '').trim().toLowerCase() === 'half day';
        const start = new Date(Math.max(new Date(l.startDate), startDate));
        const end = new Date(Math.min(new Date(l.endDate), endDate));
        let curr = new Date(start);
        while (curr <= end) {
            const d = curr.toISOString().split('T')[0];
            if (!dateMap[d]) dateMap[d] = {};
            if (isHalfDayLeave) {
                dateMap[d].hasHalfDayLeave = true;
                leaveDateToHalfDay[d] = true;
            } else {
                leaveDateToHalfDay[d] = false;
            }
            curr.setDate(curr.getDate() + 1);
        }
    });

    // 3. Calculate Weighted Present Days (only for dates up to today; future dates not counted)
    // ONLY status "Present" or "Approved" (case insensitive) are counted
    // If leaveType is "half day" -> 0.5, otherwise -> 1.0
    // All other statuses (Absent, Pending, etc.) -> 0.0
    const todayStr = `${currentYear}-${String(currentMonth).padStart(2, '0')}-${String(currentDay).padStart(2, '0')}`;
    console.log(`[calculateAttendanceStats] ======== PRESENT DAYS CALCULATION (dates <= ${todayStr}) ========`);
    const presentDays = Object.entries(dateMap).reduce((sum, [date, data]) => {
        if (date > todayStr) return sum; // Don't count future dates as present
        const status = data.attendanceStatus || '';
        const attLeaveType = data.attendanceLeaveType || '';
        
        let dayValue = 0;
        let reason = '';
        
        // Present, Approved, or Half day status only (paid leave counted separately)
        // Half day = 0.5, full day = 1.0
        if (status === 'present' || status === 'approved' || status === 'half day') {
            // Check if it's half day via status, leaveType, or Leave collection
            const isHalfDay = status === 'half day' || attLeaveType === 'half day' || data.hasHalfDayLeave === true;

            if (isHalfDay) {
                dayValue = 0.5;
                reason = `Half Day (status="${status}", leaveType="${attLeaveType}", hasHalfDayLeave=${data.hasHalfDayLeave})`;
            } else {
                dayValue = 1;
                reason = `Full Day (status="${status}")`;
            }
        } else {
            dayValue = 0;
            reason = `Not Counted (status="${status}", leaveType="${attLeaveType}")`;
        }
        
        console.log(`[calculateAttendanceStats] ${date}: ${reason} = ${dayValue} day(s)`);
        return sum + dayValue;
    }, 0);
    console.log(`[calculateAttendanceStats] ==========================================`);
    
    console.log(`[calculateAttendanceStats] Attendance Records Found: ${attendanceRecords.length}`);
    console.log(`[calculateAttendanceStats] Leave Records Found: ${leaveRecords.length}`);
    console.log(`[calculateAttendanceStats] Calculated Weighted Present Days: ${presentDays}`);

    // Half day paid leave: dates <= today where attendance is present/approved and (half day)
    let halfDayPaidLeaveCount = 0;
    Object.entries(dateMap).forEach(([date, data]) => {
        if (date > todayStr) return;
        const status = (data.attendanceStatus || '').trim().toLowerCase();
        const attLeaveType = (data.attendanceLeaveType || '').trim().toLowerCase();
        const isHalfDay = attLeaveType === 'half day' || data.hasHalfDayLeave === true;
        if ((status === 'present' || status === 'approved') && isHalfDay) {
            halfDayPaidLeaveCount += 1;
        }
    });

    // Leave (approved leave but NOT present in attendance for that date): day-equivalent, only up to today
    let leaveDays = 0;
    Object.entries(leaveDateToHalfDay).forEach(([date, isHalfDay]) => {
        if (date > todayStr) return;
        const data = dateMap[date];
        const status = data ? (data.attendanceStatus || '').trim().toLowerCase() : '';
        const isPresent = status === 'present' || status === 'approved';
        if (!isPresent) {
            leaveDays += isHalfDay ? 0.5 : 1;
        }
    });

    // Paid leave days (On Leave with isPaidLeave, excl weekOff/compOff) - separate from present
    const paidLeaveDays = Object.entries(dateMap).reduce((sum, [date, data]) => {
        if (date > todayStr) return sum;
        const s = (data.attendanceStatus || '').trim().toLowerCase();
        const isPaid = data.isPaidLeave === true;
        const comp = (data.compensationType || '').trim().toLowerCase();
        if (s === 'on leave' && isPaid && comp !== 'weekoff' && comp !== 'compoff') return sum + 1;
        return sum;
    }, 0);

    // For salary proration: use (presentDays + paidLeaveDays)
    const effectivePaidDays = presentDays + paidLeaveDays;
    const absentDays = Math.max(0, workingDays - effectivePaidDays);

    const result = {
        workingDays,
        workingDaysFullMonth,
        presentDays,
        paidLeaveDays,
        absentDays,
        holidays,
        halfDayPaidLeaveCount,
        leaveDays,
        attendancePercentage: workingDays > 0 ? (effectivePaidDays / workingDays) * 100 : 0
    };
    
    // Additional debug logging
    console.log(`[calculateAttendanceStats] RETURNING: ${JSON.stringify(result)}`);
    
    return result;
};

const createPayroll = async (req, res) => {
    // Basic implementation
    res.status(501).json({ message: 'Not implemented yet' });
};

const exportPayroll = async (req, res) => {
    res.json({ success: true, message: "Export functionality" });
};

const generatePayroll = async (req, res) => {
    res.json({ success: true, message: "Generate functionality" });
};

const bulkGeneratePayroll = async (req, res) => {
    res.json({ success: true, message: "Bulk Generate functionality" });
};

const generatePayslip = async (req, res) => {
    res.json({ success: true, message: "Generate Payslip functionality" });
};

const markPayrollAsPaid = async (req, res) => {
    res.json({ success: true, message: "Mark Paid functionality" });
};

const updatePayroll = async (req, res) => {
    res.json({ success: true, message: "Update functionality" });
};

const processPayroll = async (req, res) => {
    res.json({ success: true, message: "Process functionality" });
};

module.exports = {
    getPayrolls,
    getPayrollById,
    getPayrollStats,
    previewPayrollEmployee,
    createPayroll,
    exportPayroll,
    generatePayroll,
    bulkGeneratePayroll,
    generatePayslip,
    markPayrollAsPaid,
    updatePayroll,
    processPayroll,
    calculateAttendanceStats,
    getRecordFineAmount
};
