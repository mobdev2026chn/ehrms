require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const Staff = require('../models/Staff');
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

    // STEP 5: Yearly Calculations
    const annualGrossSalary = grossSalary * 12;
    const annualIncentive = incentiveRate > 0 ? (annualGrossSalary * incentiveRate / 100) : 0;
    const annualGratuity = gratuityRate > 0 ? (basicSalary * 12 * gratuityRate / 100) : 0;
    const annualStatutoryBonus = statutoryBonusRate > 0 ? (basicSalary * 12 * statutoryBonusRate / 100) : 0;
    const totalAnnualBenefits = annualGratuity + annualStatutoryBonus + medicalInsuranceAmount;
    const annualMobileAllowance = mobileAllowance > 0 
        ? (mobileAllowanceType === 'yearly' ? mobileAllowance : mobileAllowance * 12) 
        : 0;
    const annualNetSalary = netMonthlySalary * 12;

    // STEP 6: Total CTC
    const totalCTC = annualGrossSalary + annualIncentive + totalAnnualBenefits + annualMobileAllowance;

    return {
        inputs: {
            basicSalary,
            dearnessAllowance,
            houseRentAllowance,
            specialAllowance,
            employerPFRate,
            employerESIRate,
            incentiveRate,
            gratuityRate,
            statutoryBonusRate,
            medicalInsuranceAmount,
            mobileAllowance,
            mobileAllowanceType,
            employeePFRate,
            employeeESIRate
        },
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
        yearly: {
            annualGrossSalary,
            annualIncentive,
            annualGratuity,
            annualStatutoryBonus,
            medicalInsuranceAmount,
            totalAnnualBenefits,
            annualMobileAllowance,
            annualNetSalary
        },
        totalCTC
    };
}

/**
 * Format currency
 */
function formatCurrency(amount) {
    return `₹${amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/**
 * Generate detailed salary structure report
 */
function generateSalaryReport(staff, calculated) {
    const report = [];
    
    report.push('='.repeat(80));
    report.push(`SALARY STRUCTURE CALCULATION FOR: ${staff.name} (${staff.email})`);
    report.push('='.repeat(80));
    report.push('');
    report.push(`Employee ID: ${staff.employeeId}`);
    report.push(`Designation: ${staff.designation || 'N/A'}`);
    report.push(`Department: ${staff.department || 'N/A'}`);
    report.push('');
    report.push('='.repeat(80));
    report.push('INPUT PARAMETERS');
    report.push('='.repeat(80));
    report.push(`Basic Salary:              ${formatCurrency(calculated.inputs.basicSalary)}`);
    report.push(`Dearness Allowance (DA):    ${formatCurrency(calculated.inputs.dearnessAllowance)} ${calculated.inputs.dearnessAllowance === calculated.inputs.basicSalary * 0.5 ? '(Auto-calculated: 50% of Basic)' : '(From DB)'}`);
    report.push(`House Rent Allowance (HRA): ${formatCurrency(calculated.inputs.houseRentAllowance)} ${calculated.inputs.houseRentAllowance === calculated.inputs.basicSalary * 0.2 ? '(Auto-calculated: 20% of Basic)' : '(From DB)'}`);
    report.push(`Special Allowance:          ${formatCurrency(calculated.inputs.specialAllowance)}`);
    report.push(`Employer PF Rate:           ${calculated.inputs.employerPFRate}%`);
    report.push(`Employer ESI Rate:          ${calculated.inputs.employerESIRate}%`);
    report.push(`Incentive Rate:             ${calculated.inputs.incentiveRate}%`);
    report.push(`Gratuity Rate:              ${calculated.inputs.gratuityRate}%`);
    report.push(`Statutory Bonus Rate:       ${calculated.inputs.statutoryBonusRate}%`);
    report.push(`Medical Insurance:          ${formatCurrency(calculated.inputs.medicalInsuranceAmount)}`);
    report.push(`Mobile Allowance:           ${formatCurrency(calculated.inputs.mobileAllowance)} (${calculated.inputs.mobileAllowanceType})`);
    report.push(`Employee PF Rate:           ${calculated.inputs.employeePFRate}%`);
    report.push(`Employee ESI Rate:           ${calculated.inputs.employeeESIRate}%`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('MONTHLY CALCULATIONS');
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
    report.push(`  Employer PF (${calculated.inputs.employerPFRate}% of Basic):        ${formatCurrency(calculated.monthly.employerPF)}`);
    report.push(`  Employer ESI (${calculated.inputs.employerESIRate}% of Gross Fixed):  ${formatCurrency(calculated.monthly.employerESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Gross Salary (Monthly):            ${formatCurrency(calculated.monthly.grossSalary)}`);
    report.push('');
    report.push('Employee Deductions:');
    report.push(`  Employee PF (${calculated.inputs.employeePFRate}% of Basic):         ${formatCurrency(calculated.monthly.employeePF)}`);
    report.push(`  Employee ESI (${calculated.inputs.employeeESIRate}% of Gross):      ${formatCurrency(calculated.monthly.employeeESI)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Total Deductions:                 ${formatCurrency(calculated.monthly.totalMonthlyDeductions)}`);
    report.push('');
    report.push(`  Net Monthly Salary (Take-Home):   ${formatCurrency(calculated.monthly.netMonthlySalary)}`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('YEARLY CALCULATIONS');
    report.push('='.repeat(80));
    report.push('');
    report.push(`Annual Gross Salary:                ${formatCurrency(calculated.yearly.annualGrossSalary)} (${formatCurrency(calculated.monthly.grossSalary)} × 12)`);
    report.push(`Annual Incentive (${calculated.inputs.incentiveRate}%):              ${formatCurrency(calculated.yearly.annualIncentive)}`);
    report.push('');
    report.push('Benefits (Yearly):');
    report.push(`  Gratuity (${calculated.inputs.gratuityRate}% of Basic × 12):        ${formatCurrency(calculated.yearly.annualGratuity)}`);
    report.push(`  Statutory Bonus (${calculated.inputs.statutoryBonusRate}% of Basic × 12): ${formatCurrency(calculated.yearly.annualStatutoryBonus)}`);
    report.push(`  Medical Insurance:                 ${formatCurrency(calculated.yearly.medicalInsuranceAmount)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  Total Annual Benefits:             ${formatCurrency(calculated.yearly.totalAnnualBenefits)}`);
    report.push('');
    report.push(`Annual Mobile Allowance:             ${formatCurrency(calculated.yearly.annualMobileAllowance)}`);
    report.push(`Annual Net Salary:                   ${formatCurrency(calculated.yearly.annualNetSalary)} (${formatCurrency(calculated.monthly.netMonthlySalary)} × 12)`);
    report.push('');
    
    report.push('='.repeat(80));
    report.push('TOTAL CTC (COST TO COMPANY)');
    report.push('='.repeat(80));
    report.push(`  Annual Gross Salary:              ${formatCurrency(calculated.yearly.annualGrossSalary)}`);
    report.push(`  Annual Incentive:                 ${formatCurrency(calculated.yearly.annualIncentive)}`);
    report.push(`  Total Annual Benefits:             ${formatCurrency(calculated.yearly.totalAnnualBenefits)}`);
    report.push(`  Annual Mobile Allowance:           ${formatCurrency(calculated.yearly.annualMobileAllowance)}`);
    report.push(`  ─────────────────────────────────────────────────────────────`);
    report.push(`  TOTAL CTC:                         ${formatCurrency(calculated.totalCTC)}`);
    report.push('');
    report.push('NOTE: Employee deductions (PF, ESI) are NOT included in CTC');
    report.push('='.repeat(80));
    
    return report.join('\n');
}

const calculateSalaryForEmployee = async () => {
    try {
        console.log("Connecting to DB...");
        await connectDB();
        console.log("Connected.");

        const email = 'emp@gmail.com';
        
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

        // Calculate salary structure
        const calculated = calculateSalaryStructure(staff.salary);

        // Generate report
        const report = generateSalaryReport(staff, calculated);
        
        // Save to file
        const outputPath = path.join(__dirname, `SALARY_CALCULATION_${staff.email.replace('@', '_at_')}.txt`);
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

calculateSalaryForEmployee();
