/**
 * Full salary breakdown for one staff user (same formulas as Flutter salary_structure_calculator
 * + backend payrollController computeMonthlySalaryFromStaffSalary, calculateAttendanceStats,
 * preview proration, fines).
 *
 * Usage (from app_backend): node src/scripts/salaryBreakdownByEmail.js [email] [month] [year]
 * Example: node src/scripts/salaryBreakdownByEmail.js check123@gmail.com 3 2025
 *
 * Output: salary_breakdown_<email>_<yyyy-mm>.txt in app_backend/
 */
require('dotenv').config();
const path = require('path');
const fs = require('fs');
const mongoose = require('mongoose');
const connectDB = require('../config/db');
// Register refs used by payrollController.calculateAttendanceStats → Staff.populate(...)
require('../models/Branch');
require('../models/WeeklyHolidayTemplate');
const User = require('../models/User');
const Staff = require('../models/Staff');
const Payroll = require('../models/Payroll');
const Attendance = require('../models/Attendance');
const Company = require('../models/Company');
const {
    calculateAttendanceStats,
    getRecordFineAmount
} = require('../controllers/payrollController');
const { getEffectiveFineConfig } = require('../utils/fineCalculationHelper');
const { getShiftTimings } = require('../utils/leaveAttendanceHelper');
const { calculateWorkHoursFromShift } = require('../utils/leaveAttendanceHelper');

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
        netSalary,
        flags: { isPFApplicable, isESIApplicable }
    };
}

/** Flutter calculateProratedSalary: factor = presentOnly / workingDaysFullMonth */
function flutterStyleProrated(m, workingDaysFullMonth, presentOnly, fineAmount) {
    const wdm = workingDaysFullMonth || 0;
    if (wdm <= 0) {
        return {
            factor: 0,
            proratedGross: 0,
            proratedDeductions: 0,
            proratedNet: 0 - fineAmount,
            attendancePctFullMonth: 0
        };
    }
    const factor = presentOnly / wdm;
    const proratedGross = m.grossSalary * factor;
    const proratedDeductions = m.totalMonthlyDeductions * factor;
    const proratedNet = proratedGross - proratedDeductions - fineAmount;
    return {
        factor,
        proratedGross,
        proratedDeductions,
        proratedNet,
        attendancePctFullMonth: (presentOnly / wdm) * 100
    };
}

function money(n) {
    const x = Number(n) || 0;
    return `₹${x.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 4 })}`;
}

async function main() {
    const emailArg = (process.argv[2] || 'check123@gmail.com').trim().toLowerCase();
    const now = new Date();
    const month = Number(process.argv[3]) || now.getMonth() + 1;
    const year = Number(process.argv[4]) || now.getFullYear();

    await connectDB();

    const user = await User.findOne({ email: new RegExp(`^${emailArg.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') }).lean();
    const staff = await Staff.findOne({
        $or: [{ email: new RegExp(`^${emailArg.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') }, ...(user ? [{ userId: user._id }] : [])]
    }).select('+salary').lean();

    const lines = [];
    const push = (s) => lines.push(s);

    push('='.repeat(88));
    push('HRMS SALARY BREAKDOWN (app parity: Salary Overview + backend payroll)');
    push(`Generated: ${new Date().toISOString()}`);
    push(`Target email: ${emailArg}`);
    push(`Period: ${year}-${String(month).padStart(2, '0')}`);
    push('='.repeat(88));
    push('');

    push('--- FORMULA REFERENCE (Flutter: lib/utils/salary_structure_calculator.dart) ---');
    push('1) grossFixedSalary = Basic + DA + HRA + Special Allowance');
    push('2) PF applicable if (Basic + DA) < 15000; ESI if (Basic + DA + HRA) < 21000');
    push('3) employerPF = employerPFRate% × Basic (if PF applicable, else 0)');
    push('4) employerESI = employerESIRate% × grossFixedSalary (if ESI applicable)');
    push('5) pfStaticAmount = 0 if PF applicable, else 1800 (added to gross)');
    push('6) grossSalary = grossFixedSalary + employerPF + employerESI + pfStaticAmount');
    push('7) employeePF = employeePFRate% × Basic if PF applicable, else pfStaticAmount (1800)');
    push('8) employeeESI = employeeESIRate% × grossSalary (if ESI applicable)');
    push('9) totalMonthlyDeductions = employeePF + employeeESI');
    push('10) netMonthlySalary = grossSalary - totalMonthlyDeductions');
    push('');
    push('MTD proration (Flutter client / getPayrollStats no-payroll path):');
    push('  prorationFactor = presentDays / workingDaysFullMonth');
    push('  proratedGross = monthlyGross × factor');
    push('  proratedDeductions = monthlyDeductions × factor');
    push('  MTD net = proratedGross - proratedDeductions - totalLateFines');
    push('  (presentDays = weighted present/approved/half-day from attendance; excludes paid-leave-only rows)');
    push('');
    push('Payroll PREVIEW API (POST /api/payrolls/preview) uses:');
    push('  prorationFactor = (presentDays + paidLeaveDays) / workingDaysFullMonth');
    push('  App MTD cards prefer preview gross/net when returned, else client prorated values.');
    push('');
    push('Daily salary for fines: netMonthlySalary / workingDaysFullMonth');
    push('='.repeat(88));
    push('');

    if (!staff) {
        push(`ERROR: No staff record found for "${emailArg}" (by staff.email or user link).`);
        const outPath = path.join(__dirname, '../../salary_breakdown_NOTFOUND.txt');
        fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
        console.log('Wrote', outPath);
        await mongoose.connection.close();
        process.exit(1);
    }

    push('--- USER / STAFF (from DB) ---');
    if (user) {
        push(`User._id: ${user._id}`);
        push(`User.name: ${user.name}`);
        push(`User.email: ${user.email}`);
        push(`User.role: ${user.role}`);
    } else {
        push('User: (no User doc matched email; staff may exist on staff.email only)');
    }
    push(`Staff._id: ${staff._id}`);
    push(`Staff.name: ${staff.name}`);
    push(`Staff.email: ${staff.email}`);
    push(`Staff.employeeId: ${staff.employeeId || '—'}`);
    push(`Staff.designation: ${staff.designation || '—'}`);
    push(`Staff.department: ${staff.department || '—'}`);
    push(`Staff.businessId: ${staff.businessId || '—'}`);
    push('');

    const salaryRaw = staff.salary;
    if (!salaryRaw || typeof salaryRaw !== 'object') {
        push('ERROR: staff.salary is missing. Cannot compute structure.');
        const safeName = emailArg.replace(/[^a-z0-9@._-]+/gi, '_');
        const outPath = path.join(__dirname, `../../salary_breakdown_${safeName}_${year}-${String(month).padStart(2, '0')}_NOSALARY.txt`);
        fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
        console.log('Wrote', outPath);
        await mongoose.connection.close();
        process.exit(1);
    }

    push('--- staff.salary (raw from DB) ---');
    push(JSON.stringify(salaryRaw, null, 2));
    push('');

    const m = computeMonthlySalaryFromStaffSalary(salaryRaw);
    push('--- FULL MONTH (computeMonthlySalaryFromStaffSalary / app calculator) ---');
    push(`PF applicable (Basic+DA < 15000): ${m.flags.isPFApplicable}`);
    push(`ESI applicable (Basic+DA+HRA < 21000): ${m.flags.isESIApplicable}`);
    push(`Basic:                    ${money(m.basicSalary)}`);
    push(`DA:                       ${money(m.dearnessAllowance)}`);
    push(`HRA:                      ${money(m.houseRentAllowance)}`);
    push(`Special Allowance:        ${money(m.specialAllowance)}`);
    push(`Gross fixed:              ${money(m.grossFixedSalary)}`);
    push(`Employer PF:              ${money(m.employerPF)}`);
    push(`Employer ESI:             ${money(m.employerESI)}`);
    push(`Statutory PF (fixed):     ${money(m.pfStaticAmount)}`);
    push(`Monthly GROSS:            ${money(m.grossSalary)}`);
    push(`Employee PF:              ${money(m.employeePF)}`);
    push(`Employee ESI:             ${money(m.employeeESI)}`);
    push(`Total monthly deductions: ${money(m.totalMonthlyDeductions)}`);
    push(`Monthly NET:              ${money(m.netSalary)}`);
    push('');

    const annualGrossSalary = m.grossSalary * 12;
    const annualIncentive = (salaryRaw.incentiveRate || 0) / 100 * (m.basicSalary * 12);
    const annualGratuity = (salaryRaw.gratuityRate || 0) / 100 * (m.basicSalary * 12);
    const annualStatutoryBonus = (salaryRaw.statutoryBonusRate || 0) / 100 * (m.basicSalary * 12);
    const medicalInsuranceAmount = salaryRaw.medicalInsuranceAmount || 0;
    const totalAnnualBenefits = annualGratuity + annualStatutoryBonus + medicalInsuranceAmount;
    const mobileAllowance = salaryRaw.mobileAllowance || 0;
    const annualMobileAllowance = salaryRaw.mobileAllowanceType === 'yearly' ? mobileAllowance : mobileAllowance * 12;
    const totalCTC = annualGrossSalary + annualIncentive + totalAnnualBenefits + annualMobileAllowance;
    push('--- CTC (same as getPayrollStats no-payroll path) ---');
    push(`Annual gross (gross×12):  ${money(annualGrossSalary)}`);
    push(`Annual incentive:         ${money(annualIncentive)} (incentiveRate% × annual basic)`);
    push(`Annual gratuity:          ${money(annualGratuity)}`);
    push(`Annual statutory bonus:   ${money(annualStatutoryBonus)}`);
    push(`Medical insurance (yr):   ${money(medicalInsuranceAmount)}`);
    push(`Annual mobile allowance:${money(annualMobileAllowance)}`);
    push(`Total CTC:                ${money(totalCTC)}`);
    push('');

    const stats = await calculateAttendanceStats(staff._id, month, year);
    push('--- ATTENDANCE STATS (calculateAttendanceStats) ---');
    push(JSON.stringify(stats, null, 2));
    push('');
    push(`workingDays (till today in month):     ${stats.workingDays}`);
    push(`workingDaysFullMonth:                  ${stats.workingDaysFullMonth}`);
    push(`presentDays (weighted):                ${stats.presentDays}`);
    push(`paidLeaveDays:                         ${stats.paidLeaveDays}`);
    push(`effectivePaidDays (present+paid):      ${stats.presentDays + stats.paidLeaveDays}`);
    push(`absentDays:                            ${stats.absentDays}`);
    push('');

    const startOfMonth = new Date(year, month - 1, 1);
    const endOfMonth = new Date(year, month, 0, 23, 59, 59, 999);
    const attendanceRecords = await Attendance.find({
        $or: [{ employeeId: staff._id }, { user: staff._id }],
        date: { $gte: startOfMonth, $lte: endOfMonth }
    }).lean();

    const company = staff.businessId ? await Company.findById(staff.businessId).lean() : null;
    const fineConfig = company ? getEffectiveFineConfig(company) : null;
    const shiftTimings = company && staff ? getShiftTimings(company, staff) : {};
    const shiftHours = Math.max(0, calculateWorkHoursFromShift(shiftTimings.startTime || '09:30', shiftTimings.endTime || '18:30') || 9);
    const thisMonthWorkingDays = stats.workingDaysFullMonth ?? stats.workingDays;
    const dailySalaryForFine = thisMonthWorkingDays > 0 ? m.netSalary / thisMonthWorkingDays : 0;

    let totalFineAmount = 0;
    const fineLines = [];
    for (const record of attendanceRecords) {
        const st = (record.status || '').trim().toLowerCase();
        const lt = (record.leaveType || '').trim().toLowerCase();
        if (!(st === 'present' || st === 'approved' || st === 'half day' || lt === 'half day')) continue;
        const fa = getRecordFineAmount(record, dailySalaryForFine, shiftHours, fineConfig);
        if (fa > 0) {
            totalFineAmount += fa;
            const d = record.date ? new Date(record.date).toISOString().split('T')[0] : '?';
            fineLines.push(`  ${d}  fine=${money(fa)}  lateMin=${record.lateMinutes ?? '—'} fineHours=${record.fineHours ?? '—'} fineAmount=${record.fineAmount ?? '—'}`);
        }
    }
    push('--- FINES (getRecordFineAmount; daily net = monthlyNet / workingDaysFullMonth) ---');
    push(`Shift hours (for formula): ${shiftHours}`);
    push(`Daily salary (net / full month WD): ${money(dailySalaryForFine)}`);
    push(`Total late / fine amount: ${money(totalFineAmount)}`);
    if (fineLines.length) push('Per-record (non-zero):');
    fineLines.forEach((l) => push(l));
    push('');

    const wdm = thisMonthWorkingDays || 1;
    const statsPath = thisMonthWorkingDays > 0 ? stats.presentDays / thisMonthWorkingDays : 0;
    const previewPath = thisMonthWorkingDays > 0 ? (stats.presentDays + stats.paidLeaveDays) / thisMonthWorkingDays : 0;

    const mtdStatsGross = m.grossSalary * statsPath;
    const mtdStatsDed = m.totalMonthlyDeductions * statsPath;
    const mtdStatsNet = mtdStatsGross - mtdStatsDed - totalFineAmount;

    const mtdPreviewGross = m.grossSalary * previewPath;
    const mtdPreviewDed = m.totalMonthlyDeductions * previewPath;
    const mtdPreviewNet = Math.max(0, mtdPreviewGross - mtdPreviewDed - totalFineAmount);

    const fl = flutterStyleProrated(m, thisMonthWorkingDays, stats.presentDays, totalFineAmount);

    push('--- MTD ESTIMATES ---');
    push(`Denominator (workingDaysFullMonth): ${thisMonthWorkingDays}`);
    push('');
    push('A) getPayrollStats / Flutter client proration (present ONLY):');
    push(`   factor = presentDays / WDM = ${stats.presentDays} / ${thisMonthWorkingDays} = ${statsPath.toFixed(6)}`);
    push(`   MTD gross = ${money(mtdStatsGross)}`);
    push(`   MTD emp deductions (prorated) = ${money(mtdStatsDed)}`);
    push(`   MTD net (before unpaid leave adj. in app) = ${money(mtdStatsNet)}`);
    push(`   (Flutter also subtracts unpaid leave × daily net after this — see salary_overview_screen.)`);
    push('');
    push('B) POST /api/payrolls/preview (present + paid leave):');
    push(`   factor = (${stats.presentDays} + ${stats.paidLeaveDays}) / ${thisMonthWorkingDays} = ${previewPath.toFixed(6)}`);
    push(`   MTD gross = ${money(mtdPreviewGross)}`);
    push(`   MTD deductions (prorated) = ${money(mtdPreviewDed)}`);
    push(`   MTD net (max 0) = ${money(mtdPreviewNet)}`);
    push('');
    push('C) Recheck Flutter calculateProratedSalary (same as A):');
    push(`   proratedGross=${money(fl.proratedGross)} proratedDed=${money(fl.proratedDeductions)} net=${money(fl.proratedNet)}`);

    const payroll = await Payroll.findOne({ employeeId: staff._id, month, year }).lean();
    push('');
    push('--- PAYROLL ROW (if any) ---');
    if (payroll) {
        push(`status: ${payroll.status}`);
        push(`grossSalary: ${money(payroll.grossSalary)}`);
        push(`netPay: ${money(payroll.netPay)}`);
        push(`deductions: ${money(payroll.deductions)}`);
        if (Array.isArray(payroll.components)) {
            push('components:');
            payroll.components.forEach((c) => push(`  - ${c.name}: ${money(c.amount)} (${c.type})`));
        }
    } else {
        push('No payroll document for this staff + month + year.');
    }

    push('');
    push('='.repeat(88));
    push('END');
    push('='.repeat(88));

    const safeName = emailArg.replace(/[^a-z0-9@._-]+/gi, '_');
    const outPath = path.join(__dirname, `../../salary_breakdown_${safeName}_${year}-${String(month).padStart(2, '0')}.txt`);
    fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
    console.log('Wrote', outPath);
    await mongoose.connection.close();
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
