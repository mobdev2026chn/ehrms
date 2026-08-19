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
 * Calculate Salary Structure
 */
function calculateSalaryStructure(salary) {
    const basicSalary = salary.basicSalary || 0;
    const dearnessAllowance = salary.dearnessAllowance || 0;
    const houseRentAllowance = salary.houseRentAllowance || 0;
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

    // STEP 1: Prorate Gross Fixed Components
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

    // STEP 4: Fine amount is NOT prorated
    const totalDeductions = proratedDeductions + fineAmount;

    // STEP 5: Prorated net salary
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
 * Generate verification report
 */
function generateVerificationReport(staff, calculated, prorated, attendanceStats, screenshotValues) {
    const report = [];
    
    report.push('='.repeat(80));
    report.push(`SALARY VERIFICATION FOR: ${staff.name} (${staff.email})`);
    report.push('='.repeat(80));
    report.push('');
    
    report.push('='.repeat(80));
    report.push('SCREENSHOT VALUES (From App)');
    report.push('='.repeat(80));
    report.push(`Monthly Gross:              ${formatCurrency(screenshotValues.monthlyGross)}`);
    report.push(`Monthly Net:                ${formatCurrency(screenshotValues.monthlyNet)}`);
    report.push(`This Month Gross:           ${formatCurrency(screenshotValues.thisMonthGross)}`);
    report.push(`This Month Net:             ${formatCurrency(screenshotValues.thisMonthNet)}`);
    report.push(`Working Days:               ${screenshotValues.workingDays}`);
    report.push(`Present Days:               ${screenshotValues.presentDays}`);
    report.push(`Absent Days:                ${screenshotValues.absentDays}`);
    report.push(`Holidays:                   ${screenshotValues.holidays}`);
    report.push(`Attendance %:               ${screenshotValues.attendancePercentage}%`);
    report.push(`Late Login Fine:            ${formatCurrency(screenshotValues.lateFine)}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('CALCULATED VALUES (From Database & Formula)');
    report.push('='.repeat(80));
    report.push('');
    report.push('FULL MONTH SALARY STRUCTURE:');
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
    report.push(`  Monthly Gross:                    ${formatCurrency(calculated.monthly.grossSalary)}`);
    report.push('');
    report.push('Employee Deductions:');
    report.push(`  Employee PF (${calculated.rates.employeePFRate}% of Basic):         ${formatCurrency(calculated.monthly.employeePF)}`);
    report.push(`  Employee ESI (${calculated.rates.employeeESIRate}% of Gross):      ${formatCurrency(calculated.monthly.employeeESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Total Deductions:                 ${formatCurrency(calculated.monthly.totalMonthlyDeductions)}`);
    report.push('');
    report.push(`  Monthly Net:                      ${formatCurrency(calculated.monthly.netMonthlySalary)}`);
    report.push('');
    
    report.push('PRORATED SALARY (Based on Attendance):');
    report.push(`  Proration Factor:                 ${(prorated.attendancePercentage / 100).toFixed(4)} (${attendanceStats.presentDays} / ${attendanceStats.workingDays})`);
    report.push('');
    report.push('STEP 1: Prorate Gross Fixed Components:');
    report.push(`  Prorated Basic Salary:            ${formatCurrency(prorated.proratedBasicSalary)}`);
    report.push(`  Prorated DA:                      ${formatCurrency(prorated.proratedDA)}`);
    report.push(`  Prorated HRA:                     ${formatCurrency(prorated.proratedHRA)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Prorated Gross Fixed:              ${formatCurrency(prorated.proratedGrossFixedSalary)}`);
    report.push('');
    report.push('STEP 2: Recalculate Employer Contributions:');
    report.push(`  Prorated Employer PF:             ${formatCurrency(prorated.proratedEmployerPF)}`);
    report.push(`  Prorated Employer ESI:             ${formatCurrency(prorated.proratedEmployerESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  This Month Gross:                  ${formatCurrency(prorated.proratedGrossSalary)}`);
    report.push('');
    report.push('STEP 3: Recalculate Employee Deductions:');
    report.push(`  Prorated Employee PF:             ${formatCurrency(prorated.proratedEmployeePF)}`);
    report.push(`  Prorated Employee ESI:             ${formatCurrency(prorated.proratedEmployeeESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Prorated Deductions:               ${formatCurrency(prorated.proratedDeductions)}`);
    report.push(`  Late Login Fine (NOT prorated):    ${formatCurrency(prorated.fineAmount)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Total Deductions:                  ${formatCurrency(prorated.totalDeductions)}`);
    report.push('');
    report.push(`  This Month Net:                    ${formatCurrency(prorated.proratedNetSalary)}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('VERIFICATION RESULTS');
    report.push('='.repeat(80));
    report.push('');
    
    // Compare values
    const monthlyGrossMatch = Math.abs(calculated.monthly.grossSalary - screenshotValues.monthlyGross) < 0.01;
    const monthlyNetMatch = Math.abs(calculated.monthly.netMonthlySalary - screenshotValues.monthlyNet) < 0.01;
    const thisMonthGrossMatch = Math.abs(prorated.proratedGrossSalary - screenshotValues.thisMonthGross) < 0.01;
    const thisMonthNetMatch = Math.abs(prorated.proratedNetSalary - screenshotValues.thisMonthNet) < 0.01;
    const attendanceMatch = Math.abs(prorated.attendancePercentage - screenshotValues.attendancePercentage) < 0.1;
    const fineMatch = Math.abs(prorated.fineAmount - screenshotValues.lateFine) < 0.01;
    
    report.push(`Monthly Gross:     ${monthlyGrossMatch ? '✅ MATCH' : '❌ MISMATCH'}`);
    report.push(`  Calculated: ${formatCurrency(calculated.monthly.grossSalary)}`);
    report.push(`  Screenshot: ${formatCurrency(screenshotValues.monthlyGross)}`);
    report.push(`  Difference: ${formatCurrency(Math.abs(calculated.monthly.grossSalary - screenshotValues.monthlyGross))}`);
    report.push('');
    
    report.push(`Monthly Net:       ${monthlyNetMatch ? '✅ MATCH' : '❌ MISMATCH'}`);
    report.push(`  Calculated: ${formatCurrency(calculated.monthly.netMonthlySalary)}`);
    report.push(`  Screenshot: ${formatCurrency(screenshotValues.monthlyNet)}`);
    report.push(`  Difference: ${formatCurrency(Math.abs(calculated.monthly.netMonthlySalary - screenshotValues.monthlyNet))}`);
    report.push('');
    
    report.push(`This Month Gross:  ${thisMonthGrossMatch ? '✅ MATCH' : '❌ MISMATCH'}`);
    report.push(`  Calculated: ${formatCurrency(prorated.proratedGrossSalary)}`);
    report.push(`  Screenshot: ${formatCurrency(screenshotValues.thisMonthGross)}`);
    report.push(`  Difference: ${formatCurrency(Math.abs(prorated.proratedGrossSalary - screenshotValues.thisMonthGross))}`);
    report.push('');
    
    report.push(`This Month Net:    ${thisMonthNetMatch ? '✅ MATCH' : '❌ MISMATCH'}`);
    report.push(`  Calculated: ${formatCurrency(prorated.proratedNetSalary)}`);
    report.push(`  Screenshot: ${formatCurrency(screenshotValues.thisMonthNet)}`);
    report.push(`  Difference: ${formatCurrency(Math.abs(prorated.proratedNetSalary - screenshotValues.thisMonthNet))}`);
    report.push('');
    
    report.push(`Attendance %:      ${attendanceMatch ? '✅ MATCH' : '❌ MISMATCH'}`);
    report.push(`  Calculated: ${prorated.attendancePercentage.toFixed(2)}%`);
    report.push(`  Screenshot: ${screenshotValues.attendancePercentage}%`);
    report.push('');
    
    report.push(`Late Login Fine:   ${fineMatch ? '✅ MATCH' : '❌ MISMATCH'}`);
    report.push(`  Calculated: ${formatCurrency(prorated.fineAmount)}`);
    report.push(`  Screenshot: ${formatCurrency(screenshotValues.lateFine)}`);
    report.push(`  Difference: ${formatCurrency(Math.abs(prorated.fineAmount - screenshotValues.lateFine))}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push(`OVERALL STATUS: ${(monthlyGrossMatch && monthlyNetMatch && thisMonthGrossMatch && thisMonthNetMatch && attendanceMatch && fineMatch) ? '✅ ALL CALCULATIONS CORRECT' : '❌ SOME MISMATCHES FOUND'}`);
    report.push('='.repeat(80));
    
    return report.join('\n');
}

const verifyDemomanSalary = async () => {
    try {
        console.log("Connecting to DB...");
        await connectDB();
        console.log("Connected.");

        const email = 'demoman@gmail.com';
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

        // Values from screenshot
        const screenshotValues = {
            monthlyGross: 15002.00,
            monthlyNet: 13929.49,
            thisMonthGross: 2727.64,
            thisMonthNet: 2456.86,
            workingDays: 22,
            presentDays: 4,
            absentDays: 18,
            holidays: 3,
            attendancePercentage: 18.2,
            lateFine: 75.77
        };

        // Calculate salary structure
        const calculated = calculateSalaryStructure(staff.salary);

        // Calculate prorated salary
        const prorated = calculateCorrectProratedSalary(
            calculated,
            screenshotValues.workingDays,
            screenshotValues.presentDays,
            screenshotValues.lateFine
        );

        const attendanceStats = {
            workingDays: screenshotValues.workingDays,
            presentDays: screenshotValues.presentDays,
            absentDays: screenshotValues.absentDays,
            holidaysCount: screenshotValues.holidays,
            totalFineAmount: screenshotValues.lateFine,
            lateDays: lateDays,
            totalLateMinutes: totalLateMinutes
        };

        // Generate report
        const report = generateVerificationReport(staff, calculated, prorated, attendanceStats, screenshotValues);
        
        // Save to file
        const outputPath = path.join(__dirname, `VERIFY_DEMOMAN_SALARY.txt`);
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

verifyDemomanSalary();
