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
        },
        rates: {
            employerPFRate,
            employerESIRate,
            employeePFRate,
            employeeESIRate
        }
    };
}

/**
 * Calculate CORRECT prorated salary
 * Step 1: Prorate Gross Fixed components (Basic, DA, HRA, Special)
 * Step 2: Recalculate Employer PF and ESI on prorated amounts
 * Step 3: Recalculate Employee PF and ESI on prorated gross
 * Step 4: Subtract deductions and fines
 */
function calculateCorrectProratedSalary(calculatedSalary, workingDays, presentDays, fineAmount = 0) {
    if (workingDays === 0) {
        return {
            proratedGrossFixedSalary: 0,
            proratedBasicSalary: 0,
            proratedDA: 0,
            proratedHRA: 0,
            proratedSpecialAllowance: 0,
            proratedEmployerPF: 0,
            proratedEmployerESI: 0,
            proratedGrossSalary: 0,
            proratedEmployeePF: 0,
            proratedEmployeeESI: 0,
            proratedDeductions: 0,
            fineAmount: fineAmount,
            totalDeductions: fineAmount,
            proratedNetSalary: 0 - fineAmount,
            attendancePercentage: 0
        };
    }

    const attendancePercentage = (presentDays / workingDays) * 100;
    const prorationFactor = presentDays / workingDays;

    // STEP 1: Prorate Gross Fixed components
    const proratedBasicSalary = calculatedSalary.monthly.basicSalary * prorationFactor;
    const proratedDA = calculatedSalary.monthly.dearnessAllowance * prorationFactor;
    const proratedHRA = calculatedSalary.monthly.houseRentAllowance * prorationFactor;
    const proratedSpecialAllowance = calculatedSalary.monthly.specialAllowance * prorationFactor;
    const proratedGrossFixedSalary = proratedBasicSalary + proratedDA + proratedHRA + proratedSpecialAllowance;

    // STEP 2: Recalculate Employer Contributions on PRORATED amounts
    const proratedEmployerPF = calculatedSalary.rates.employerPFRate > 0 
        ? (proratedBasicSalary * calculatedSalary.rates.employerPFRate / 100) 
        : 0;
    const proratedEmployerESI = calculatedSalary.rates.employerESIRate > 0 
        ? (proratedGrossFixedSalary * calculatedSalary.rates.employerESIRate / 100) 
        : 0;
    const proratedGrossSalary = proratedGrossFixedSalary + proratedEmployerPF + proratedEmployerESI;

    // STEP 3: Recalculate Employee Deductions on PRORATED gross salary
    const proratedEmployeePF = calculatedSalary.rates.employeePFRate > 0 
        ? (proratedBasicSalary * calculatedSalary.rates.employeePFRate / 100) 
        : 0;
    const proratedEmployeeESI = calculatedSalary.rates.employeeESIRate > 0 
        ? (proratedGrossSalary * calculatedSalary.rates.employeeESIRate / 100) 
        : 0;
    const proratedDeductions = proratedEmployeePF + proratedEmployeeESI;

    // STEP 4: Fine amount is NOT prorated - it's the actual total from attendance records
    const totalDeductions = proratedDeductions + fineAmount;

    // STEP 5: Prorated net salary = Prorated Gross - Total Deductions
    const proratedNetSalary = proratedGrossSalary - totalDeductions;

    return {
        proratedGrossFixedSalary,
        proratedBasicSalary,
        proratedDA,
        proratedHRA,
        proratedSpecialAllowance,
        proratedEmployerPF,
        proratedEmployerESI,
        proratedGrossSalary,
        proratedEmployeePF,
        proratedEmployeeESI,
        proratedDeductions,
        fineAmount,
        totalDeductions,
        proratedNetSalary,
        attendancePercentage
    };
}

/**
 * Format currency
 */
function formatCurrency(amount) {
    return `₹${amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/**
 * Calculate working days for a month
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
 * Generate detailed salary report with CORRECT calculation
 */
function generateCorrectSalaryReport(staff, calculated, prorated, attendanceStats) {
    const report = [];
    
    report.push('='.repeat(80));
    report.push(`CORRECT SALARY CALCULATION FOR: ${staff.name} (${staff.email})`);
    report.push('='.repeat(80));
    report.push('');
    report.push(`Employee ID: ${staff.employeeId}`);
    report.push(`Designation: ${staff.designation || 'N/A'}`);
    report.push(`Department: ${staff.department || 'N/A'}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('ATTENDANCE SUMMARY');
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
    report.push(`  Employer PF (${calculated.rates.employerPFRate}% of Basic):        ${formatCurrency(calculated.monthly.employerPF)}`);
    report.push(`  Employer ESI (${calculated.rates.employerESIRate}% of Gross Fixed):  ${formatCurrency(calculated.monthly.employerESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Gross Salary (Monthly):            ${formatCurrency(calculated.monthly.grossSalary)}`);
    report.push('');
    report.push('Employee Deductions:');
    report.push(`  Employee PF (${calculated.rates.employeePFRate}% of Basic):         ${formatCurrency(calculated.monthly.employeePF)}`);
    report.push(`  Employee ESI (${calculated.rates.employeeESIRate}% of Gross):      ${formatCurrency(calculated.monthly.employeeESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Total Deductions:                 ${formatCurrency(calculated.monthly.totalMonthlyDeductions)}`);
    report.push('');
    report.push(`  Net Monthly Salary (Take-Home):   ${formatCurrency(calculated.monthly.netMonthlySalary)}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('CORRECT PRORATED SALARY CALCULATION');
    report.push('='.repeat(80));
    report.push('');
    report.push(`Proration Factor:                  ${(prorated.attendancePercentage / 100).toFixed(4)} (${attendanceStats.presentDays} / ${attendanceStats.workingDays})`);
    report.push('');
    report.push('STEP 1: Prorate Gross Fixed Components:');
    report.push(`  Prorated Basic Salary:            ${formatCurrency(prorated.proratedBasicSalary)}`);
    report.push(`  Prorated DA:                      ${formatCurrency(prorated.proratedDA)}`);
    report.push(`  Prorated HRA:                     ${formatCurrency(prorated.proratedHRA)}`);
    report.push(`  Prorated Special Allowance:       ${formatCurrency(prorated.proratedSpecialAllowance)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Prorated Gross Fixed Salary:       ${formatCurrency(prorated.proratedGrossFixedSalary)}`);
    report.push('');
    report.push('STEP 2: Recalculate Employer Contributions on Prorated Amounts:');
    report.push(`  Prorated Employer PF (${calculated.rates.employerPFRate}% of Prorated Basic):  ${formatCurrency(prorated.proratedEmployerPF)}`);
    report.push(`  Prorated Employer ESI (${calculated.rates.employerESIRate}% of Prorated Gross Fixed): ${formatCurrency(prorated.proratedEmployerESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  This Month Gross Salary:           ${formatCurrency(prorated.proratedGrossSalary)}`);
    report.push('');
    report.push('STEP 3: Recalculate Employee Deductions on Prorated Gross:');
    report.push(`  Prorated Employee PF (${calculated.rates.employeePFRate}% of Prorated Basic):   ${formatCurrency(prorated.proratedEmployeePF)}`);
    report.push(`  Prorated Employee ESI (${calculated.rates.employeeESIRate}% of Prorated Gross): ${formatCurrency(prorated.proratedEmployeeESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Prorated Deductions:               ${formatCurrency(prorated.proratedDeductions)}`);
    if (prorated.fineAmount > 0) {
        report.push(`  Late Login Fine (NOT prorated):    ${formatCurrency(prorated.fineAmount)}`);
    }
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Total Deductions:                  ${formatCurrency(prorated.totalDeductions)}`);
    report.push('');
    report.push('STEP 4: Calculate Net Salary:');
    report.push(`  This Month Net Salary (Take-Home): ${formatCurrency(prorated.proratedNetSalary)}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('COMPARISON: WRONG vs CORRECT');
    report.push('='.repeat(80));
    report.push('');
    report.push('WRONG METHOD (Current):');
    report.push(`  This Month Gross = Full Gross × Proration = ${formatCurrency(calculated.monthly.grossSalary)} × ${(prorated.attendancePercentage / 100).toFixed(4)} = ${formatCurrency(calculated.monthly.grossSalary * (prorated.attendancePercentage / 100))}`);
    report.push(`  This Month Net = Full Net × Proration = ${formatCurrency(calculated.monthly.netMonthlySalary)} × ${(prorated.attendancePercentage / 100).toFixed(4)} = ${formatCurrency(calculated.monthly.netMonthlySalary * (prorated.attendancePercentage / 100))}`);
    report.push('');
    report.push('CORRECT METHOD (Fixed):');
    report.push(`  This Month Gross = ${formatCurrency(prorated.proratedGrossSalary)}`);
    report.push(`  This Month Net = ${formatCurrency(prorated.proratedNetSalary)}`);
    report.push('');
    report.push('='.repeat(80));
    
    return report.join('\n');
}

const calculateCorrectSalary = async () => {
    try {
        console.log("Connecting to DB...");
        await connectDB();
        console.log("Connected.");

        const email = 'stest1@gmail.com';
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

        console.log('\nSalary data from database:');
        console.log(JSON.stringify(staff.salary, null, 2));
        console.log('\n');

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

        // Calculate CORRECT prorated salary
        const prorated = calculateCorrectProratedSalary(
            calculated,
            workingDaysInfo.workingDays,
            presentDays,
            totalFineAmount
        );

        // Generate report
        const report = generateCorrectSalaryReport(staff, calculated, prorated, attendanceStats);
        
        // Save to file
        const outputPath = path.join(__dirname, `CORRECT_SALARY_${staff.email.replace('@', '_at_')}.txt`);
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

calculateCorrectSalary();
