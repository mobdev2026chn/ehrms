require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const Staff = require('../models/Staff');
const Attendance = require('../models/Attendance');
const Company = require('../models/Company');
const HolidayTemplate = require('../models/HolidayTemplate');
const fs = require('fs');
const path = require('path');

/**
 * Calculate Salary Structure (matching Flutter calculator logic)
 */
function calculateSalaryStructure(salary) {
    // Extract inputs
    const basicSalary = salary.basicSalary || 0;
    const existingDA = salary.dearnessAllowance || 0;
    const existingHRA = salary.houseRentAllowance || 0;
    
    // Auto-calculate DA and HRA if not set (50% and 20% of basic)
    const dearnessAllowance = existingDA > 0 
        ? existingDA 
        : (basicSalary > 0 ? basicSalary * 0.5 : 0);
    
    const houseRentAllowance = existingHRA > 0 
        ? existingHRA 
        : (basicSalary > 0 ? basicSalary * 0.2 : 0);
    
    const specialAllowance = salary.specialAllowance || 0;
    const employerPFRate = salary.employerPFRate || 0;
    const employerESIRate = salary.employerESIRate || 0;
    const incentiveRate = salary.incentiveRate || 0;
    const gratuityRate = salary.gratuityRate || 0;
    const statutoryBonusRate = salary.statutoryBonusRate || 0;
    const medicalInsuranceAmount = salary.medicalInsuranceAmount || 0;
    const mobileAllowance = salary.mobileAllowance || 0;
    const mobileAllowanceType = salary.mobileAllowanceType || 'monthly';
    const employeePFRate = salary.employeePFRate || 0;
    const employeeESIRate = salary.employeeESIRate || 0;

    // STEP 1: Fixed Monthly Components
    const grossFixedSalary = basicSalary + dearnessAllowance + houseRentAllowance + specialAllowance;

    // STEP 2: Employer Contributions
    const employerPF = employerPFRate > 0 ? (basicSalary * employerPFRate / 100) : 0;
    const employerESI = employerESIRate > 0 ? (grossFixedSalary * employerESIRate / 100) : 0;
    const grossSalary = grossFixedSalary + employerPF + employerESI;

    // STEP 3: Employee Deductions
    const employeePF = employeePFRate > 0 ? (basicSalary * employeePFRate / 100) : 0;
    const employeeESI = employeeESIRate > 0 ? (grossSalary * employeeESIRate / 100) : 0;
    const totalMonthlyDeductions = employeePF + employeeESI;

    // STEP 4: Net Salary
    const netMonthlySalary = grossSalary - totalMonthlyDeductions;

    return {
        monthly: {
            basicSalary,
            dearnessAllowance,
            houseRentAllowance,
            specialAllowance,
            grossFixedSalary,
            employerPF,
            employerESI,
            grossSalary,
            employeePF,
            employeeESI,
            totalMonthlyDeductions,
            netMonthlySalary
        }
    };
}

/**
 * Calculate working days for January 2026
 */
function calculateWorkingDays(year, month, holidays, weeklyOffPattern, weeklyHolidays) {
    const daysInMonth = new Date(year, month, 0).getDate();
    const holidayDayNumbers = new Set(holidays.map(h => {
        const d = new Date(h.date);
        return d.getDate();
    }));

    let workingDays = 0;
    let weeklyOffDays = 0;
    let holidaysCount = 0;

    for (let day = 1; day <= daysInMonth; day++) {
        const currentDate = new Date(year, month - 1, day);
        const dayOfWeek = currentDate.getDay(); // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
        const isHoliday = holidayDayNumbers.has(day);
        
        if (isHoliday) {
            holidaysCount++;
        } else {
            let isWeeklyOff = false;
            
            if (weeklyOffPattern === 'oddEvenSaturday') {
                if (dayOfWeek === 0) {
                    isWeeklyOff = true; // All Sundays are weekly off
                } else if (dayOfWeek === 6) {
                    // Calculate which Saturday of the month this is
                    let saturdayOrdinal = 0;
                    for (let d = 1; d <= day; d++) {
                        if (new Date(year, month - 1, d).getDay() === 6) {
                            saturdayOrdinal++;
                        }
                    }
                    if (saturdayOrdinal % 2 === 0) {
                        isWeeklyOff = true; // Even Saturdays (2nd, 4th, 6th) are weekly off
                    }
                }
            } else {
                isWeeklyOff = weeklyHolidays.some(h => h.day === dayOfWeek);
            }
            
            if (isWeeklyOff) {
                weeklyOffDays++;
            } else {
                workingDays++;
            }
        }
    }

    return { workingDays, weeklyOffDays, holidaysCount, totalDays: daysInMonth };
}

/**
 * Format currency
 */
function formatCurrency(amount) {
    return `₹${amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/**
 * Calculate prorated salary
 */
function calculateProratedSalary(calculatedSalary, workingDays, presentDays, fineAmount = 0) {
    if (workingDays === 0) {
        return {
            proratedGrossSalary: 0,
            proratedDeductions: 0,
            proratedNetSalary: 0,
            attendancePercentage: 0,
            fineAmount: 0
        };
    }

    const attendancePercentage = (presentDays / workingDays) * 100;
    const prorationFactor = presentDays / workingDays;

    const proratedGrossSalary = calculatedSalary.monthly.grossSalary * prorationFactor;
    const proratedDeductions = calculatedSalary.monthly.totalMonthlyDeductions * prorationFactor;
    // Fine amount is NOT prorated - it's the actual total from attendance records
    const totalDeductions = proratedDeductions + fineAmount;
    const proratedNetSalary = proratedGrossSalary - totalDeductions;

    return {
        proratedGrossSalary,
        proratedDeductions,
        fineAmount,
        totalDeductions,
        proratedNetSalary,
        attendancePercentage
    };
}

/**
 * Generate detailed January salary report
 */
function generateJanuarySalaryReport(staff, calculated, prorated, attendanceStats) {
    const report = [];
    
    report.push('='.repeat(80));
    report.push(`JANUARY 2026 SALARY CALCULATION FOR: ${staff.name} (${staff.email})`);
    report.push('='.repeat(80));
    report.push('');
    report.push(`Employee ID: ${staff.employeeId}`);
    report.push(`Designation: ${staff.designation || 'N/A'}`);
    report.push(`Department: ${staff.department || 'N/A'}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('ATTENDANCE SUMMARY (JANUARY 2026)');
    report.push('='.repeat(80));
    report.push(`Total Days in Month:        ${attendanceStats.totalDays}`);
    report.push(`Working Days:                ${attendanceStats.workingDays}`);
    report.push(`Present Days:                ${attendanceStats.presentDays}`);
    report.push(`Absent Days:                 ${attendanceStats.absentDays}`);
    report.push(`Holidays:                    ${attendanceStats.holidaysCount}`);
    report.push(`Week Off Days:               ${attendanceStats.weeklyOffDays}`);
    report.push(`Attendance Percentage:      ${prorated.attendancePercentage.toFixed(2)}%`);
    if (attendanceStats.totalFineAmount > 0) {
        report.push(`Late Login Fine:              ${formatCurrency(attendanceStats.totalFineAmount)}`);
        report.push(`Late Days:                    ${attendanceStats.lateDays}`);
        report.push(`Total Late Minutes:           ${attendanceStats.totalLateMinutes}`);
    }
    report.push('');
    
    report.push('='.repeat(80));
    report.push('FULL MONTH SALARY STRUCTURE');
    report.push('='.repeat(80));
    report.push('');
    report.push('(A) Fixed Components:');
    report.push(`  Basic Salary:                    ${formatCurrency(calculated.monthly.basicSalary)}`);
    report.push(`  Dearness Allowance (DA):          ${formatCurrency(calculated.monthly.dearnessAllowance)}`);
    report.push(`  House Rent Allowance (HRA):       ${formatCurrency(calculated.monthly.houseRentAllowance)}`);
    report.push(`  Special Allowance:                ${formatCurrency(calculated.monthly.specialAllowance)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Gross Fixed Salary:               ${formatCurrency(calculated.monthly.grossFixedSalary)}`);
    report.push('');
    report.push('Employer Contributions:');
    report.push(`  Employer PF:                     ${formatCurrency(calculated.monthly.employerPF)}`);
    report.push(`  Employer ESI:                     ${formatCurrency(calculated.monthly.employerESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Gross Salary (Monthly):            ${formatCurrency(calculated.monthly.grossSalary)}`);
    report.push('');
    report.push('Employee Deductions:');
    report.push(`  Employee PF:                      ${formatCurrency(calculated.monthly.employeePF)}`);
    report.push(`  Employee ESI:                      ${formatCurrency(calculated.monthly.employeeESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Total Deductions:                 ${formatCurrency(calculated.monthly.totalMonthlyDeductions)}`);
    report.push('');
    report.push(`  Net Monthly Salary (Take-Home):   ${formatCurrency(calculated.monthly.netMonthlySalary)}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('PRORATED SALARY FOR JANUARY 2026 (BASED ON ATTENDANCE)');
    report.push('='.repeat(80));
    report.push('');
    report.push(`Proration Factor:                  ${(prorated.attendancePercentage / 100).toFixed(4)} (${attendanceStats.presentDays} / ${attendanceStats.workingDays})`);
    report.push('');
    report.push('Prorated Earnings:');
    report.push(`  Basic Salary:                    ${formatCurrency(calculated.monthly.basicSalary * (prorated.attendancePercentage / 100))}`);
    report.push(`  Dearness Allowance (DA):          ${formatCurrency(calculated.monthly.dearnessAllowance * (prorated.attendancePercentage / 100))}`);
    report.push(`  House Rent Allowance (HRA):       ${formatCurrency(calculated.monthly.houseRentAllowance * (prorated.attendancePercentage / 100))}`);
    report.push(`  Special Allowance:                ${formatCurrency(calculated.monthly.specialAllowance * (prorated.attendancePercentage / 100))}`);
    report.push(`  Employer PF:                     ${formatCurrency(calculated.monthly.employerPF * (prorated.attendancePercentage / 100))}`);
    report.push(`  Employer ESI:                     ${formatCurrency(calculated.monthly.employerESI * (prorated.attendancePercentage / 100))}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  This Month Gross Salary:          ${formatCurrency(prorated.proratedGrossSalary)}`);
    report.push('');
    report.push('Prorated Deductions:');
    report.push(`  Employee PF:                      ${formatCurrency(calculated.monthly.employeePF * (prorated.attendancePercentage / 100))}`);
    report.push(`  Employee ESI:                      ${formatCurrency(calculated.monthly.employeeESI * (prorated.attendancePercentage / 100))}`);
    if (prorated.fineAmount > 0) {
        report.push(`  Late Login Fine:                 ${formatCurrency(prorated.fineAmount)}`);
    }
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Total Deductions:                 ${formatCurrency(prorated.totalDeductions)}`);
    report.push('');
    report.push(`  This Month Net Salary (Take-Home): ${formatCurrency(prorated.proratedNetSalary)}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('SUMMARY');
    report.push('='.repeat(80));
    report.push(`Full Month Gross Salary:            ${formatCurrency(calculated.monthly.grossSalary)}`);
    report.push(`This Month Gross Salary:             ${formatCurrency(prorated.proratedGrossSalary)}`);
    report.push(`Full Month Net Salary:               ${formatCurrency(calculated.monthly.netMonthlySalary)}`);
    report.push(`This Month Net Salary:               ${formatCurrency(prorated.proratedNetSalary)}`);
    report.push('');
    report.push('='.repeat(80));
    
    return report.join('\n');
}

const calculateJanuarySalary = async () => {
    try {
        console.log("Connecting to DB...");
        await connectDB();
        console.log("Connected.");

        const email = 'emp@gmail.com';
        const year = 2026;
        const month = 1; // January
        
        // Find staff by email
        const staff = await Staff.findOne({ email: email });
        
        if (!staff) {
            console.error(`Staff not found with email: ${email}`);
            process.exit(1);
        }

        console.log(`Found staff: ${staff.name} (${staff.employeeId})`);
        
        if (!staff.salary || Object.keys(staff.salary).length === 0) {
            console.error('No salary structure found for this employee');
            process.exit(1);
        }

        // Get business settings
        const company = await Company.findById(staff.businessId);
        const businessSettings = company?.settings?.business || {};
        const weeklyOffPattern = businessSettings.weeklyOffPattern || 'standard';
        const weeklyHolidays = businessSettings.weeklyHolidays || [];

        // Get holidays for January 2026
        const holidayTemplate = await HolidayTemplate.findOne({
            businessId: staff.businessId,
            isActive: true
        });

        let holidays = [];
        if (holidayTemplate) {
            holidays = (holidayTemplate.holidays || []).filter(h => {
                const d = new Date(h.date);
                return d.getFullYear() === year && d.getMonth() + 1 === month;
            });
        }

        // Calculate working days
        const workingDaysInfo = calculateWorkingDays(year, month, holidays, weeklyOffPattern, weeklyHolidays);

        // Get attendance for January 2026
        const startOfMonth = new Date(year, month - 1, 1);
        const endOfMonth = new Date(year, month, 0, 23, 59, 59, 999);

        const attendanceRecords = await Attendance.find({
            $or: [
                { employeeId: staff._id },
                { user: staff._id }
            ],
            date: { $gte: startOfMonth, $lte: endOfMonth }
        });

        // Calculate Present Days with specific Half Day logic
        // Rule: Check both Attendance and Leave collections for Half Day
        const Leave = require('../models/Leave');
        const leaveRecords = await Leave.find({
            employeeId: staff._id,
            status: { $regex: /^approved$/i }
        });

        const dateMap = {};

        // 1. Process Attendance Records
        attendanceRecords.forEach(a => {
            if (!a.date) return;
            const d = new Date(a.date).toISOString().split('T')[0];
            const status = (a.status || '').trim().toLowerCase();
            const leaveType = (a.leaveType || '').trim().toLowerCase();
            dateMap[d] = { attendanceStatus: status, attendanceLeaveType: leaveType };
        });

        // 2. Process Leave Records for Half Day
        leaveRecords.forEach(l => {
            const isHalfDayLeave = l.isHalfDay === true || (l.leaveType || '').trim().toLowerCase() === 'half day';
            if (isHalfDayLeave) {
                const start = new Date(l.startDate);
                const end = new Date(l.endDate);
                let curr = new Date(start);
                while (curr <= end) {
                    const d = curr.toISOString().split('T')[0];
                    if (!dateMap[d]) dateMap[d] = {};
                    dateMap[d].hasHalfDayLeave = true;
                    curr.setDate(curr.getDate() + 1);
                }
            }
        });

        // 3. Calculate Weighted Present Days
        // Half day: status="half day" OR attendance.leaveType="half day" OR approved half-day leave -> 0.5
        const presentDays = Object.values(dateMap).reduce((sum, data) => {
            const status = data.attendanceStatus || '';
            const attLeaveType = data.attendanceLeaveType || '';
            const isHalfDay = status === 'half day' || attLeaveType === 'half day' || data.hasHalfDayLeave === true;
            if (isHalfDay) return sum + 0.5;
            if (status === 'present' || status === 'approved') return sum + 1;
            return sum;
        }, 0);

        const absentDays = Math.max(0, workingDaysInfo.workingDays - presentDays);

        // Calculate total fine amount - include Half Day (late login fine applies to half day too)
        const totalFineAmount = attendanceRecords
            .filter(r => {
                const s = (r.status || '').trim().toLowerCase();
                const lt = (r.leaveType || '').trim().toLowerCase();
                return s === 'present' || s === 'approved' || s === 'half day' || lt === 'half day';
            })
            .reduce((sum, record) => sum + (record.fineAmount || 0), 0);

        // Get late login details
        const lateLoginRecords = attendanceRecords.filter(a => (a.lateMinutes || 0) > 0);
        const totalLateMinutes = lateLoginRecords.reduce((sum, record) => sum + (record.lateMinutes || 0), 0);
        const lateDays = lateLoginRecords.length;

        const attendanceStats = {
            totalDays: workingDaysInfo.totalDays,
            workingDays: workingDaysInfo.workingDays,
            presentDays: presentDays,
            absentDays: absentDays,
            holidaysCount: workingDaysInfo.holidaysCount,
            weeklyOffDays: workingDaysInfo.weeklyOffDays,
            totalFineAmount: totalFineAmount,
            lateDays: lateDays,
            totalLateMinutes: totalLateMinutes
        };

        // Calculate salary structure
        const calculated = calculateSalaryStructure(staff.salary);

        // Calculate prorated salary (including fines)
        const prorated = calculateProratedSalary(
            calculated,
            workingDaysInfo.workingDays,
            presentDays,
            totalFineAmount
        );

        // Generate report
        const report = generateJanuarySalaryReport(staff, calculated, prorated, attendanceStats);
        
        // Save to file
        const outputPath = path.join(__dirname, `JANUARY_2026_SALARY_${staff.email.replace('@', '_at_')}.txt`);
        fs.writeFileSync(outputPath, report, 'utf8');
        
        console.log(report);
        console.log(`\nReport saved to: ${outputPath}`);

    } catch (error) {
        console.error('Script Error:', error);
    } finally {
        console.log("\nClosing connection...");
        await mongoose.connection.close();
        process.exit();
    }
};

calculateJanuarySalary();
