//dashboard logics
const Attendance = require('../models/Attendance');
const Leave = require('../models/Leave');
const Staff = require('../models/Staff');
const Loan = require('../models/Loan');
const Payroll = require('../models/Payroll');
const Company = require('../models/Company');
const HolidayTemplate = require('../models/HolidayTemplate');
const Announcement = require('../models/Announcement');
const { audienceFilter, dateFilter, statusFilter } = require('./announcementController');
const { calculateAttendanceStats } = require('./payrollController');

/** Get month/day for comparison (birthday/anniversary). */
function getMonthDay(d) {
    return [d.getMonth(), d.getDate()];
}

/** Next occurrence of month/day in or after refDate (for upcoming). */
function nextOccurrence(refDate, month, day) {
    const thisYear = new Date(refDate.getFullYear(), month, day);
    if (thisYear >= refDate) return thisYear;
    return new Date(refDate.getFullYear() + 1, month, day);
}

// @desc    Get Dashboard Stats for generic use (kept for compatibility)
const getDashboardStats = async (req, res) => {
    try {
        const staffId = req.staff?._id || req.user?._id;
        const today = new Date();
        const startOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 0, 0, 0, 0);
        const endOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59, 999);

        const todayAttendance = await Attendance.findOne({
            $or: [{ employeeId: staffId }, { user: staffId }],
            date: { $gte: startOfDay, $lte: endOfDay }
        });

        const pendingLeaves = await Leave.countDocuments({
            employeeId: staffId,
            status: 'Pending'
        });

        res.json({
            attendance: todayAttendance ? {
                status: todayAttendance.status,
                punchIn: todayAttendance.punchIn,
                punchOut: todayAttendance.punchOut,
                workHours: todayAttendance.workHours
            } : null,
            leaves: {
                pending: pendingLeaves
            },
            user: {
                name: req.user.name || req.staff?.name || 'User',
                role: req.user.role || 'Employee'
            }
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ message: 'Server Error' });
    }
};

// @desc    Get Employee Dashboard Stats
// @route   GET /api/dashboard/employee
const getEmployeeDashboardStats = async (req, res) => {
    try {
        console.log(`[getEmployeeDashboardStats] API called for staff: ${req.staff?._id}`);
        if (!req.staff) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }

        const staffId = req.staff._id;
        const now = new Date();
        const year = now.getFullYear();
        const month = now.getMonth() + 1; // 1-12

        const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);

        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
        const endOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);

        // 1. Staff Info
        const staff = await Staff.findById(staffId).select('name employeeId designation department joiningDate businessId holidayTemplateId salary');

        // 2. Attendance Metrics
        const attendanceToday = await Attendance.findOne({
            $or: [{ employeeId: staffId }, { user: staffId }],
            date: { $gte: startOfToday, $lte: endOfToday }
        });

        const monthAttendance = await Attendance.find({
            $or: [{ employeeId: staffId }, { user: staffId }],
            date: { $gte: startOfMonth, $lte: endOfMonth }
        });

        // Use same attendance stats as payslip and salary overview (single source of truth)
        const attendanceStats = await calculateAttendanceStats(staffId, month, year);
        const totalWorkingDays = attendanceStats.workingDays || 0;
        const thisMonthWorkingDays = attendanceStats.workingDaysFullMonth ?? totalWorkingDays;
        const presentDays = attendanceStats.presentDays || 0;
        const paidLeaveDays = attendanceStats.paidLeaveDays || 0;
        const effectivePaidDays = presentDays + paidLeaveDays;
        const absentDays = attendanceStats.absentDays ?? Math.max(0, totalWorkingDays - effectivePaidDays);

        // appPerDayNetSalary / appPerdayGrossSalary: updated by mobile app from web payroll preview
        // (PUT /auth/profile with salaryBasis ÷ fullMonth WD). Do not overwrite here — attendance WD
        // divisor can differ from template preview (24 vs 26) and would break fine parity.

        console.log(`[getEmployeeDashboardStats] attendanceStats (same as payslip/salary): thisMonthWD=${thisMonthWorkingDays}, workingDaysTillToday=${totalWorkingDays}, presentDays=${presentDays}, paidLeaveDays=${paidLeaveDays}, absentDays=${absentDays}`);

        // 3. Leave Metrics
        const pendingLeavesCount = await Leave.countDocuments({
            employeeId: staffId,
            status: { $regex: /^pending$/i }
        });

        const approvedLeavesThisMonth = await Leave.countDocuments({
            employeeId: staffId,
            status: { $regex: /^approved$/i },
            startDate: { $gte: startOfMonth, $lte: endOfMonth }
        });

        const recentLeaves = await Leave.find({ employeeId: staffId })
            .sort({ createdAt: -1 })
            .limit(5);

        // 4. Loan Metrics
        const pendingLoans = await Loan.countDocuments({
            employeeId: staffId,
            status: 'Pending'
        });

        const activeLoansList = await Loan.find({
            employeeId: staffId,
            status: 'Active'
        }).select('loanType amount purpose emi remainingAmount startDate endDate createdAt').sort({ createdAt: -1 });

        const activeLoans = activeLoansList.length;

        // 4b. Today's announcements (web: audienceType/targetStaffIds/publishDate/status published; legacy: assignedTo/effectiveDate/Active)
        let todayAnnouncements = [];
        if (staff && staff.businessId) {
            const announcementDateFilter = dateFilter(now, startOfToday, true);
            const announcementAudienceFilter = audienceFilter(staffId);
            todayAnnouncements = await Announcement.find({
                businessId: staff.businessId,
                status: statusFilter,
                $and: [announcementDateFilter, announcementAudienceFilter],
            })
                .sort({ publishDate: -1, effectiveDate: -1, createdAt: -1 })
                .limit(20)
                .select('title subject description fromName coverImage publishDate effectiveDate endDate expiryDate createdAt')
                .lean();
            console.log('[Dashboard] todayAnnouncements: staffId=%s, staffName=%s, businessId=%s, count=%d, titles=%s', staffId, staff?.name, staff.businessId, todayAnnouncements.length, todayAnnouncements.map(a => a.title).join(', ') || '(none)');
        }

        // 4c. Today's and upcoming celebrations (birthdays, work anniversaries) – same business
        const todayCelebrations = [];
        const upcomingCelebrations = [];
        const todayMonth = now.getMonth();
        const todayDay = now.getDate();
        const upcomingDays = 30;

        if (staff && staff.businessId) {
            const allStaff = await Staff.find({
                businessId: staff.businessId,
                status: 'Active',
                $or: [{ dob: { $ne: null, $exists: true } }, { joiningDate: { $ne: null, $exists: true } }],
            })
                .select('name avatar dob joiningDate')
                .lean();

            for (const s of allStaff) {
                if (s.dob) {
                    const d = new Date(s.dob);
                    const bMonth = d.getMonth();
                    const bDay = d.getDate();
                    const nextBday = nextOccurrence(now, bMonth, bDay);
                    const daysLeft = Math.ceil((nextBday - now) / (24 * 60 * 60 * 1000));
                    const isToday = bMonth === todayMonth && bDay === todayDay;
                    // Age the person turns on this (upcoming/today) birthday.
                    const turningAge = nextBday.getFullYear() - d.getFullYear();
                    const item = {
                        type: 'birthday',
                        name: s.name,
                        date: s.dob,
                        displayDate: `${bDay} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][bMonth]}`,
                        daysLeft: isToday ? 0 : daysLeft,
                        avatar: s.avatar,
                        turningAge,
                    };
                    if (isToday) todayCelebrations.push(item);
                    else if (daysLeft > 0 && daysLeft <= upcomingDays) upcomingCelebrations.push(item);
                }
                if (s.joiningDate) {
                    const d = new Date(s.joiningDate);
                    const jMonth = d.getMonth();
                    const jDay = d.getDate();
                    const nextAnniv = nextOccurrence(now, jMonth, jDay);
                    const yearsOfService = nextAnniv.getFullYear() - d.getFullYear();
                    // Only show work anniversary after completing at least 1 full year from joining date.
                    // E.g. joining 27 Feb 2026 → 1st anniversary on 27 Feb 2027 (must be on or after 27 Feb 2027).
                    const oneYearAfterJoining = new Date(d.getFullYear() + 1, jMonth, jDay);
                    const hasCompletedOneYear = now >= oneYearAfterJoining;
                    if (!hasCompletedOneYear || yearsOfService < 1) {
                        // console.log('[Dashboard] Anniversary skipped: name=%s joiningDate=%s oneYearAfter=%s hasCompletedOneYear=%s yearsOfService=%d', s.name, d.toISOString().slice(0, 10), oneYearAfterJoining.toISOString().slice(0, 10), hasCompletedOneYear, yearsOfService);
                        continue;
                    }
                    const daysLeft = Math.ceil((nextAnniv - now) / (24 * 60 * 60 * 1000));
                    const isToday = jMonth === todayMonth && jDay === todayDay;
                    const item = {
                        type: 'anniversary',
                        name: s.name,
                        date: s.joiningDate,
                        displayDate: `${jDay} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][jMonth]}`,
                        daysLeft: isToday ? 0 : daysLeft,
                        avatar: s.avatar,
                        yearsOfService,
                    };
                    if (isToday) todayCelebrations.push(item);
                    else if (daysLeft > 0 && daysLeft <= upcomingDays) upcomingCelebrations.push(item);
                }
            }
            upcomingCelebrations.sort((a, b) => a.daysLeft - b.daysLeft);
            console.log('[Dashboard] Celebrations: today=%d, upcoming=%d', todayCelebrations.length, upcomingCelebrations.length);
            todayCelebrations.forEach((c, i) => console.log('[Dashboard]   today[%d]: name=%s type=%s yearsOfService=%s displayDate=%s', i, c.name, c.type, c.yearsOfService ?? 'n/a', c.displayDate));
            upcomingCelebrations.forEach((c, i) => console.log('[Dashboard]   upcoming[%d]: name=%s type=%s yearsOfService=%s daysLeft=%s displayDate=%s', i, c.name, c.type, c.yearsOfService ?? 'n/a', c.daysLeft, c.displayDate));
        }

        // 5. Payroll info - Use same calculation logic as salary module (till present)
        const payroll = await Payroll.findOne({
            employeeId: staffId,
            month: now.getMonth() + 1,
            year: now.getFullYear()
        });

        console.log(`[getEmployeeDashboardStats] payroll exists: ${!!payroll}, staff.salary exists: ${!!(staff?.salary)}`);
        if (staff?.salary) {
            console.log(`[getEmployeeDashboardStats] staff.salary.basicSalary: ${staff.salary.basicSalary}`);
        }

        // Fine amount from Present, Approved, or Half Day (late login fine applies to half day too)
        const totalFineAmount = monthAttendance
            .filter(r => {
                const s = (r.status || '').trim().toLowerCase();
                const lt = (r.leaveType || '').trim().toLowerCase();
                return s === 'present' || s === 'approved' || s === 'half day' || lt === 'half day';
            })
            .reduce((sum, record) => sum + (record.fineAmount || 0), 0);

        let currentMonthSalary = 0;
        let payrollStatus = 'Pending';

        // Use the same calculation logic as salary overview & payroll: proration = (presentDays + paidLeaveDays) / this month WD
        if (payroll) {
            const prorationFactor = thisMonthWorkingDays > 0 ? effectivePaidDays / thisMonthWorkingDays : 1;
            
            // Get staff salary structure for correct proration
            if (staff && staff.salary) {
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
                
                // STEP 4: Recalculate Employee Deductions on PRORATED gross
                const proratedEmployeePF = employeePFRate > 0
                    ? (employeePFRate / 100 * proratedBasicSalary)
                    : pfStaticAmount;
                const proratedEmployeeESI = employeeESIRate / 100 * proratedGrossSalary;
                const proratedDeductions = proratedEmployeePF + proratedEmployeeESI;
                
                // STEP 5: Calculate Prorated Net Salary (fines are NOT prorated)
                currentMonthSalary = proratedGrossSalary - proratedDeductions - totalFineAmount;
            } else {
                // Fallback to simple proration if salary structure not available
                currentMonthSalary = payroll.netPay ? (payroll.netPay * prorationFactor) - totalFineAmount : 0;
            }
            payrollStatus = payroll.status || 'Pending';
        } else if (staff && staff.salary) {
            // Calculate estimated prorated salary using same logic as payrollController
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
            
            // Same as salary overview: proration = (presentDays + paidLeaveDays) / this month working days
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
            
            // STEP 4: Recalculate Employee Deductions on PRORATED gross
            const proratedEmployeePF = employeePFRate > 0
                ? (employeePFRate / 100 * proratedBasicSalary)
                : pfStaticAmount;
            const proratedEmployeeESI = employeeESIRate / 100 * proratedGrossSalary;
            const proratedDeductions = proratedEmployeePF + proratedEmployeeESI;
            
            // STEP 5: Calculate Prorated Net Salary (fines are NOT prorated)
            currentMonthSalary = proratedGrossSalary - proratedDeductions - totalFineAmount;
        }

        const prorationFactor = thisMonthWorkingDays > 0 ? effectivePaidDays / thisMonthWorkingDays : 0;
        console.log(`[getEmployeeDashboardStats] prorationFactor: ${prorationFactor} (presentDays=${presentDays} + paidLeaveDays=${paidLeaveDays} / thisMonthWD=${thisMonthWorkingDays})`);
        console.log(`[getEmployeeDashboardStats] currentMonthSalary: ${currentMonthSalary}`);
        console.log(`[getEmployeeDashboardStats] ========================================`);

        res.json({
            success: true,
            data: {
                staff: staff ? {
                    name: staff.name,
                    employeeId: staff.employeeId,
                    designation: staff.designation,
                    department: staff.department
                } : null,
                stats: {
                    pendingLeaves: pendingLeavesCount,
                    approvedLeavesThisMonth: approvedLeavesThisMonth,
                    pendingLoans: pendingLoans,
                    activeLoans: activeLoans,
                    activeLoansList: activeLoansList,
                    attendanceToday: attendanceToday ? {
                        status: attendanceToday.status,
                        punchIn: attendanceToday.punchIn,
                        punchOut: attendanceToday.punchOut
                    } : null,
                    attendanceSummary: {
                        totalDays: totalWorkingDays,
                        thisMonthWorkingDays: thisMonthWorkingDays,
                        presentDays: presentDays,
                        paidLeaveDays: paidLeaveDays,
                        absentDays: absentDays,
                        halfDayPaidLeaveCount: attendanceStats.halfDayPaidLeaveCount ?? 0,
                        leaveDays: attendanceStats.leaveDays ?? 0
                    },
                    currentMonthSalary: currentMonthSalary,
                    payrollStatus: payrollStatus
                },
                recentLeaves: recentLeaves,
                upcomingTasks: [],
                todayAnnouncements: todayAnnouncements,
                todayCelebrations: todayCelebrations,
                upcomingCelebrations: upcomingCelebrations,
            }
        });

    } catch (error) {
        console.error('[Dashboard Controller Error]', error);
        res.status(500).json({ success: false, message: 'Server Error' });
    }
};

module.exports = { getDashboardStats, getEmployeeDashboardStats };