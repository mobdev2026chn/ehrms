/// Comprehensive Salary Structure Calculation Utility
/// All calculations are done dynamically - NO values are stored except base inputs
library;

/// Statutory PF on basic when Basic+DA is under 15k — matches web
/// `backend/src/utils/salaryStructureCalculation.util.ts` (`EMPLOYEE_PF_RATE`).
/// Staff `employerPFRate` / `employeePFRate` in JSON are **not** used for this rupee amount.
const double kWebStatutoryPfPercentOnBasic = 12.0;

class SalaryStructureInputs {
  // Fixed Salary Components (Monthly)
  final double basicSalary;
  final double dearnessAllowance;
  final double houseRentAllowance;
  final double specialAllowance;

  // Employer Contribution Rates (%)
  final double employerPFRate; // % of Basic
  final double employerESIRate; // % of Basic+DA+HRA (web TS `baseGross`)

  // Variable Pay Rate (%)
  final double incentiveRate; // % of Annual Gross Salary

  // Benefits Rates and Fixed Values
  final double gratuityRate; // % of Basic
  final double statutoryBonusRate; // % of Basic
  final double medicalInsuranceAmount; // Fixed yearly value

  // Allowances
  final double mobileAllowance;
  final String mobileAllowanceType; // 'monthly' or 'yearly'

  // Employee Deduction Rates (%)
  final double employeePFRate; // % of Basic
  final double employeeESIRate; // % of Basic+DA+HRA (web TS `baseGross`)

  SalaryStructureInputs({
    required this.basicSalary,
    this.dearnessAllowance = 0,
    this.houseRentAllowance = 0,
    this.specialAllowance = 0,
    this.employerPFRate = 0,
    this.employerESIRate = 0,
    this.incentiveRate = 0,
    this.gratuityRate = 0,
    this.statutoryBonusRate = 0,
    this.medicalInsuranceAmount = 0,
    this.mobileAllowance = 0,
    this.mobileAllowanceType = 'monthly',
    this.employeePFRate = 0,
    this.employeeESIRate = 0,
  });

  /// Web payroll preview: scale fixed components by payableDays/baseDays, then [calculateSalaryStructure].
  SalaryStructureInputs scaledByProrationFactor(double factor) {
    final f = factor;
    if (f <= 0 || f == 1.0) return this;
    return SalaryStructureInputs(
      basicSalary: basicSalary * f,
      dearnessAllowance: dearnessAllowance * f,
      houseRentAllowance: houseRentAllowance * f,
      specialAllowance: specialAllowance * f,
      employerPFRate: employerPFRate,
      employerESIRate: employerESIRate,
      incentiveRate: incentiveRate,
      gratuityRate: gratuityRate,
      statutoryBonusRate: statutoryBonusRate,
      medicalInsuranceAmount: medicalInsuranceAmount,
      mobileAllowance: mobileAllowance,
      mobileAllowanceType: mobileAllowanceType,
      employeePFRate: employeePFRate,
      employeeESIRate: employeeESIRate,
    );
  }

  factory SalaryStructureInputs.fromMap(Map<String, dynamic> salary) {
    final basicSalary = (salary['basicSalary'] ?? 0).toDouble();
    final dearnessAllowance = (salary['dearnessAllowance'] ?? 0).toDouble();
    final houseRentAllowance = (salary['houseRentAllowance'] ?? 0).toDouble();

    return SalaryStructureInputs(
      basicSalary: basicSalary,
      dearnessAllowance: dearnessAllowance,
      houseRentAllowance: houseRentAllowance,
      specialAllowance: (salary['specialAllowance'] ?? 0).toDouble(),
      employerPFRate: (salary['employerPFRate'] ?? 0).toDouble(),
      employerESIRate: (salary['employerESIRate'] ?? 0).toDouble(),
      incentiveRate: (salary['incentiveRate'] ?? 0).toDouble(),
      gratuityRate: (salary['gratuityRate'] ?? 0).toDouble(),
      statutoryBonusRate: (salary['statutoryBonusRate'] ?? 0).toDouble(),
      medicalInsuranceAmount: (salary['medicalInsuranceAmount'] ?? 0)
          .toDouble(),
      mobileAllowance: (salary['mobileAllowance'] ?? 0).toDouble(),
      mobileAllowanceType: salary['mobileAllowanceType'] ?? 'monthly',
      employeePFRate: (salary['employeePFRate'] ?? 0).toDouble(),
      employeeESIRate: (salary['employeeESIRate'] ?? 0).toDouble(),
    );
  }
}

class MonthlySalaryStructure {
  final double basicSalary;
  final double dearnessAllowance;
  final double houseRentAllowance;
  final double specialAllowance;
  final double grossFixedSalary; // basicSalary + DA + HRA + specialAllowance
  final double employerPF; // basic × [kWebStatutoryPfPercentOnBasic] when PF applies (web)
  final double employerESI; // (Basic+DA+HRA) × employerESIRate / 100
  final double pfStaticAmount; // ₹1800 in gross when Basic+DA ≥ 15000 (web)
  final double grossSalary; // grossFixedSalary + employerPF + employerESI + pfStaticAmount
  final double employeePF; // basicSalary × employeePFRate / 100
  /// Employee ESI: % of Basic+DA+HRA only (`baseGross`), same as web TS.
  final double employeeESI;
  /// Payslip total: employee PF + employee ESI only (web `totalMonthlyDeductions`).
  final double totalMonthlyDeductions;
  /// Take-home: `basic+DA+HRA − employeePF − employeeESI` (web TS; excludes special from this net base).
  final double netMonthlySalary;

  MonthlySalaryStructure({
    required this.basicSalary,
    required this.dearnessAllowance,
    required this.houseRentAllowance,
    required this.specialAllowance,
    required this.grossFixedSalary,
    required this.employerPF,
    required this.employerESI,
    required this.pfStaticAmount,
    required this.grossSalary,
    required this.employeePF,
    required this.employeeESI,
    required this.totalMonthlyDeductions,
    required this.netMonthlySalary,
  });
}

class YearlySalaryStructure {
  final double annualGrossSalary; // grossSalary × 12
  final double annualIncentive; // annualGrossSalary × incentiveRate / 100
  final double annualGratuity; // basicSalary × 12 × gratuityRate / 100
  final double
  annualStatutoryBonus; // basicSalary × 12 × statutoryBonusRate / 100
  final double medicalInsuranceAmount; // Fixed yearly medical insurance
  final double
  totalAnnualBenefits; // annualGratuity + annualStatutoryBonus + medicalInsuranceAmount
  final double
  annualMobileAllowance; // mobileAllowance × 12 (if monthly) or mobileAllowance (if yearly)
  final double annualNetSalary; // netMonthlySalary × 12

  YearlySalaryStructure({
    required this.annualGrossSalary,
    required this.annualIncentive,
    required this.annualGratuity,
    required this.annualStatutoryBonus,
    required this.medicalInsuranceAmount,
    required this.totalAnnualBenefits,
    required this.annualMobileAllowance,
    required this.annualNetSalary,
  });
}

class CalculatedSalaryStructure {
  final MonthlySalaryStructure monthly;
  final YearlySalaryStructure yearly;
  final double
  totalCTC; // annualGrossSalary + annualIncentive + totalAnnualBenefits + annualMobileAllowance

  CalculatedSalaryStructure({
    required this.monthly,
    required this.yearly,
    required this.totalCTC,
  });
}

/// Calculate complete salary structure from inputs
/// All values are calculated dynamically - no stored totals
///
/// Web parity (`backend/src/utils/salaryStructureCalculation.util.ts`):
///
/// 1. Fixed Gross = Basic + DA + HRA + Special Allowance
/// 2. `baseGross` = Basic + DA + HRA (excludes special)
/// 3. Gross Salary = Fixed Gross + Employer PF + Employer ESI + pfStaticAmount
///    - Employer PF & employee PF **amounts** = [kWebStatutoryPfPercentOnBasic]% of Basic when Basic+DA < 15000
///      (web TS `EMPLOYEE_PF_RATE`; staff `employerPFRate` / `employeePFRate` are template labels only).
///    - Employer ESI = % of `baseGross` when Basic+DA+HRA < 21000
/// 4. Employee PF / ESI on thresholds; ESI uses `baseGross`, not full gross
/// 5. `totalMonthlyDeductions` = Employee PF + Employee ESI only
/// 6. `netMonthlySalary` = `baseGross` − (Employee PF + Employee ESI)
/// 7. Annual Gross = Monthly Gross × 12
/// 8. Incentive = % of Annual Basic Salary (Basic × 12)
/// 9. Benefits = Gratuity + Statutory Bonus + Medical Insurance
///    - Gratuity = % of (Basic × 12)
///    - Statutory Bonus = % of (Basic × 12)
/// 10. CTC = Annual Gross + Incentive + Benefits + Allowances
///    NOTE: Employee deductions are NOT part of CTC
CalculatedSalaryStructure calculateSalaryStructure(
  SalaryStructureInputs inputs,
) {
  // ============================================
  // STEP 1: Fixed Monthly Components
  // ============================================
  final basicSalary = inputs.basicSalary;
  final dearnessAllowance = inputs.dearnessAllowance;
  final houseRentAllowance = inputs.houseRentAllowance;
  final specialAllowance = inputs.specialAllowance;

  // Gross Fixed Salary (Before Employer Contributions)
  final grossFixedSalary =
      basicSalary + dearnessAllowance + houseRentAllowance + specialAllowance;

  // ============================================
  // STEP 2: Employer Contributions (Part of Gross Salary & CTC)
  // ============================================
  // Web component rules:
  // PF not applicable when Basic+DA > 15000.
  // ESI not applicable when Basic+DA+HRA > 21000.
  final basicPlusDA = basicSalary + dearnessAllowance;
  final basicPlusDAPlusHRA = basicSalary + dearnessAllowance + houseRentAllowance;
  final isPFApplicable = basicPlusDA < 15000;
  final isESIApplicable = basicPlusDAPlusHRA < 21000;
  final baseGross = basicPlusDAPlusHRA;

  final effectiveEmployerESIRate = isESIApplicable ? inputs.employerESIRate : 0.0;
  final effectiveEmployeeESIRate = isESIApplicable ? inputs.employeeESIRate : 0.0;

  final statutoryPfOnBasic =
      isPFApplicable ? kWebStatutoryPfPercentOnBasic : 0.0;

  // Employer PF (rupees): web hardcodes 12% of Basic (same as employee PF line).
  final employerPF = statutoryPfOnBasic > 0
      ? (basicSalary * statutoryPfOnBasic / 100)
      : 0;

  // Employer ESI = % of Basic+DA+HRA (web TS), not full fixed gross
  final employerESI = effectiveEmployerESIRate > 0
      ? (baseGross * effectiveEmployerESIRate / 100)
      : 0;

  // When PF is not applicable, web logic adds a static 1800 to gross
  final pfStaticAmount = isPFApplicable ? 0.0 : 1800.0;

  // Gross Salary (Monthly) = Fixed Gross + Employer Contributions + static PF amount
  final grossSalary = grossFixedSalary + employerPF + employerESI + pfStaticAmount;

  // ============================================
  // STEP 3: Employee Deductions (NOT part of CTC)
  // ============================================
  // Employee PF = same statutory % of Basic as web; otherwise static PF amount
  final employeePF = isPFApplicable
      ? (basicSalary * statutoryPfOnBasic / 100)
      : pfStaticAmount;

  // Employee ESI = % of baseGross (Basic+DA+HRA), same as employer ESI base (web TS)
  final employeeESI = effectiveEmployeeESIRate > 0
      ? (baseGross * effectiveEmployeeESIRate / 100)
      : 0;

  final totalMonthlyDeductions = employeePF + employeeESI;

  // ============================================
  // STEP 4: Net Salary (Take-Home Pay)
  // ============================================
  final netMonthlySalary = baseGross - totalMonthlyDeductions;

  // ============================================
  // STEP 5: Yearly Calculations
  // ============================================
  // Annual Gross Salary = Monthly Gross × 12
  final annualGrossSalary = grossSalary * 12;

  // Web component logic: Incentive = % of Annual Basic Salary
  final annualBasicSalary = basicSalary * 12;
  final annualIncentive = inputs.incentiveRate > 0
      ? (annualBasicSalary * inputs.incentiveRate / 100)
      : 0;

  // Benefits (Yearly - Employer Cost)
  // Gratuity = % of (Basic × 12)
  final annualGratuity = inputs.gratuityRate > 0
      ? (basicSalary * 12 * inputs.gratuityRate / 100)
      : 0;

  // Statutory Bonus = % of (Basic × 12)
  final annualStatutoryBonus = inputs.statutoryBonusRate > 0
      ? (basicSalary * 12 * inputs.statutoryBonusRate / 100)
      : 0;

  // Medical Insurance (Fixed yearly amount)
  final medicalInsuranceAmount = inputs.medicalInsuranceAmount;

  // Total Annual Benefits
  final totalAnnualBenefits =
      annualGratuity + annualStatutoryBonus + medicalInsuranceAmount;

  // Mobile Allowance (Annual)
  final annualMobileAllowance = inputs.mobileAllowance > 0
      ? (inputs.mobileAllowanceType == 'yearly'
            ? inputs.mobileAllowance
            : inputs.mobileAllowance * 12)
      : 0;

  // Annual Net Salary = Monthly Net × 12
  final annualNetSalary = netMonthlySalary * 12;

  // ============================================
  // STEP 6: Total CTC (Cost to Company)
  // ============================================
  // CTC = Annual Gross + Incentive + Benefits + Allowances
  // IMPORTANT: Employee deductions are NOT included in CTC
  final totalCTC =
      annualGrossSalary +
      annualIncentive +
      totalAnnualBenefits +
      annualMobileAllowance;

  return CalculatedSalaryStructure(
    monthly: MonthlySalaryStructure(
      basicSalary: basicSalary.toDouble(),
      dearnessAllowance: dearnessAllowance.toDouble(),
      houseRentAllowance: houseRentAllowance.toDouble(),
      specialAllowance: specialAllowance.toDouble(),
      grossFixedSalary: grossFixedSalary.toDouble(),
      employerPF: employerPF.toDouble(),
      employerESI: employerESI.toDouble(),
      pfStaticAmount: pfStaticAmount.toDouble(),
      grossSalary: grossSalary.toDouble(),
      employeePF: employeePF.toDouble(),
      employeeESI: employeeESI.toDouble(),
      totalMonthlyDeductions: totalMonthlyDeductions.toDouble(),
      netMonthlySalary: netMonthlySalary.toDouble(),
    ),
    yearly: YearlySalaryStructure(
      annualGrossSalary: annualGrossSalary.toDouble(),
      annualIncentive: annualIncentive.toDouble(),
      annualGratuity: annualGratuity.toDouble(),
      annualStatutoryBonus: annualStatutoryBonus.toDouble(),
      medicalInsuranceAmount: medicalInsuranceAmount.toDouble(),
      totalAnnualBenefits: totalAnnualBenefits.toDouble(),
      annualMobileAllowance: annualMobileAllowance.toDouble(),
      annualNetSalary: annualNetSalary.toDouble(),
    ),
    totalCTC: totalCTC.toDouble(),
  );
}

/// Web EmployeeSalaryOverview legacy branch: staff.salary has `gross` (and optional `net` / `ctcYearly`) but no usable `basicSalary`.
CalculatedSalaryStructure calculatedSalaryFromLegacyStaffMap(
  Map<String, dynamic> salary,
) {
  final gross = (salary['gross'] as num?)?.toDouble() ?? 0.0;
  final netRaw = salary['net'];
  final net = (netRaw is num && netRaw > 0)
      ? netRaw.toDouble()
      : gross * 0.8;
  final ctcRaw = salary['ctcYearly'];
  final totalCTC = (ctcRaw is num && ctcRaw > 0)
      ? ctcRaw.toDouble()
      : gross * 12;
  final totalMonthlyDeductions = gross - net;

  final monthly = MonthlySalaryStructure(
    basicSalary: gross * 0.5,
    dearnessAllowance: 0,
    houseRentAllowance: 0,
    specialAllowance: 0,
    grossFixedSalary: gross * 0.8,
    employerPF: 0,
    employerESI: 0,
    pfStaticAmount: 0,
    grossSalary: gross,
    employeePF: 0,
    employeeESI: 0,
    totalMonthlyDeductions: totalMonthlyDeductions,
    netMonthlySalary: net,
  );
  final yearly = YearlySalaryStructure(
    annualGrossSalary: gross * 12,
    annualIncentive: 0,
    annualGratuity: 0,
    annualStatutoryBonus: 0,
    medicalInsuranceAmount: 0,
    totalAnnualBenefits: 0,
    annualMobileAllowance: 0,
    annualNetSalary: net * 12,
  );
  return CalculatedSalaryStructure(
    monthly: monthly,
    yearly: yearly,
    totalCTC: totalCTC,
  );
}

/// Calculate prorated salary based on working days and attendance
class ProratedSalary {
  final double proratedGrossSalary;
  final double proratedDeductions;
  final double fineAmount; // Late login/early exit fines (NOT prorated)
  final double totalDeductions; // proratedDeductions + fineAmount
  final double proratedNetSalary;
  final double attendancePercentage;

  ProratedSalary({
    required this.proratedGrossSalary,
    required this.proratedDeductions,
    this.fineAmount = 0,
    required this.totalDeductions,
    required this.proratedNetSalary,
    required this.attendancePercentage,
  });
}

/// Web / app_backend payroll preview: scale Basic/DA/HRA/Special by payable/base days,
/// then run full PF/ESI ladder (thresholds apply to MTD fixed pay).
ProratedSalary calculateWebStyleMtdProratedSalary(
  SalaryStructureInputs fullMonthInputs,
  int payableBaseDays,
  num payableDays, [
  double fineAmount = 0,
]) {
  if (payableBaseDays <= 0) {
    return ProratedSalary(
      proratedGrossSalary: 0,
      proratedDeductions: 0,
      fineAmount: fineAmount,
      totalDeductions: fineAmount,
      proratedNetSalary: -fineAmount,
      attendancePercentage: 0,
    );
  }
  final f = payableDays / payableBaseDays;
  final scaled = fullMonthInputs.scaledByProrationFactor(f);
  final m = calculateSalaryStructure(scaled).monthly;
  final attendancePercentage = (payableDays / payableBaseDays) * 100;
  final totalDeductions = m.totalMonthlyDeductions + fineAmount;
  return ProratedSalary(
    proratedGrossSalary: m.grossSalary,
    proratedDeductions: m.totalMonthlyDeductions,
    fineAmount: fineAmount,
    totalDeductions: totalDeductions,
    proratedNetSalary: m.netMonthlySalary - fineAmount,
    attendancePercentage: attendancePercentage,
  );
}

/// Legacy linear: gross×factor and deductions×factor. Prefer [calculateWebStyleMtdProratedSalary].
ProratedSalary calculateProratedSalary(
  CalculatedSalaryStructure calculatedSalary,
  int workingDaysForProration,
  num presentDays, [
  double fineAmount = 0,
]) {
  if (workingDaysForProration == 0) {
    return ProratedSalary(
      proratedGrossSalary: 0,
      proratedDeductions: 0,
      fineAmount: fineAmount,
      totalDeductions: fineAmount,
      proratedNetSalary: 0 - fineAmount, // Negative if fines exceed 0
      attendancePercentage: 0,
    );
  }

  final attendancePercentage = (presentDays / workingDaysForProration) * 100;
  final prorationFactor = presentDays / workingDaysForProration;

  final proratedGrossSalary =
      calculatedSalary.monthly.grossSalary * prorationFactor;
  final proratedDeductions =
      calculatedSalary.monthly.totalMonthlyDeductions * prorationFactor;

  final totalDeductions = proratedDeductions + fineAmount;

  // Align with net = baseGross − employee deductions; scaling gross×f − ded×f is not equal when gross includes employer pieces + special.
  final proratedNetSalary =
      calculatedSalary.monthly.netMonthlySalary * prorationFactor - fineAmount;

  return ProratedSalary(
    proratedGrossSalary: proratedGrossSalary.toDouble(),
    proratedDeductions: proratedDeductions.toDouble(),
    fineAmount: fineAmount.toDouble(),
    totalDeductions: totalDeductions.toDouble(),
    proratedNetSalary: proratedNetSalary.toDouble(),
    attendancePercentage: attendancePercentage,
  );
}

/// Calculate working days in a month (excluding weekends and holidays)
///
/// [year] - Year
/// [month] - Month (1-12, not 0-indexed)
/// [holidays] - List of holiday dates
/// [weeklyOffPattern] - 'standard' or 'oddEvenSaturday'
/// [weeklyHolidays] - List of day numbers (0=Sunday, 1=Monday, ..., 6=Saturday) that are weekly off
///                    Only used when weeklyOffPattern is 'standard'
class WorkingDaysInfo {
  final int totalDays;
  final int workingDays;
  final int weekends;
  final int holidayCount;
  /// Full month working days (for display as "This month working days"). When null, [workingDays] is used.
  final int? workingDaysFullMonth;

  WorkingDaysInfo({
    required this.totalDays,
    required this.workingDays,
    required this.weekends,
    required this.holidayCount,
    this.workingDaysFullMonth,
  });
}

WorkingDaysInfo calculateWorkingDays(
  int year,
  int month, // 1-12 (not 0-indexed)
  List<DateTime> holidays, // List of holiday dates
  String weeklyOffPattern, [ // 'standard' or 'oddEvenSaturday'
  List<int>? weeklyHolidays, // Day numbers: 0=Sunday, 1=Monday, ..., 6=Saturday
  DateTime? endDate, // Optional: calculate only till this date for current month
]) {
  final weeklyHolidaysList = weeklyHolidays ?? const <int>[];
  // Create month boundaries
  final firstDay = DateTime(year, month, 1);
  final monthLastDay = DateTime(year, month + 1, 0);

  DateTime effectiveEnd = monthLastDay;
  if (endDate != null) {
    if (endDate.year == year && endDate.month == month) {
      effectiveEnd = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
        999,
      );
    } else {
      effectiveEnd = monthLastDay;
    }
  }

  final totalDays = effectiveEnd.day;

  int workingDays = 0;
  int weeklyOffDays = 0; // Days that are weekly off (not holidays)

  // Create a set of holiday date strings for quick lookup
  final holidayDateStrings = holidays.map((h) {
    return '${h.year}-${h.month.toString().padLeft(2, '0')}-${h.day.toString().padLeft(2, '0')}';
  }).toSet();

  for (int day = 1; day <= totalDays; day++) {
    final currentDate = DateTime(year, month, day);
    // Convert Dart weekday (1=Monday, 7=Sunday) to JavaScript format (0=Sunday, 6=Saturday)
    final dartWeekday = currentDate.weekday; // 1=Monday, 7=Sunday
    final jsWeekday = dartWeekday == 7
        ? 0
        : dartWeekday; // Convert to JS format: 0=Sunday, 1=Monday, ..., 6=Saturday
    final dateString =
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    // Check if it's a holiday first
    if (holidayDateStrings.contains(dateString)) {
      continue; // Skip holidays (they're counted separately)
    }

    // Check if this day is a weekly off day
    bool isWeeklyOff = false;

    if (weeklyOffPattern == 'oddEvenSaturday') {
      // oddEvenSaturday pattern: Don't check weeklyHolidays
      // Odd Saturdays (1st, 3rd, 5th, etc.) are WORKING DAYS
      // Even Saturdays (2nd, 4th, 6th, etc.) are WEEKLY OFF
      // All Sundays are WEEKLY OFF
      if (jsWeekday == 0) {
        // Sunday - always weekly off
        isWeeklyOff = true;
      } else if (jsWeekday == 6) {
        // Saturday - check if even (weekly off) or odd (working)
        // Calculate which Saturday of the month this is (1st, 2nd, etc.)
        int saturdayOrdinal = 0;
        for (int d = 1; d <= day; d++) {
          final tempDate = DateTime(year, month, d);
          final tempDartWeekday = tempDate.weekday;
          final tempJsWeekday = tempDartWeekday == 7 ? 0 : tempDartWeekday;
          if (tempJsWeekday == 6) {
            saturdayOrdinal++;
          }
        }
        
        if (saturdayOrdinal % 2 == 0) {
          // Even Saturday (2nd, 4th, 6th) - weekly off
          isWeeklyOff = true;
        } else {
          // Odd Saturday (1st, 3rd, 5th) - working day
          isWeeklyOff = false;
        }
      }
    } else {
      // Standard pattern — match web EmployeeSalaryOverview
      // (salaryCalculation.util.ts): if weeklyHolidays is empty, Sat+Sun are
      // week-offs; otherwise only listed days are off.
      // jsWeekday: 0=Sunday, 1=Monday, ..., 6=Saturday
      if (weeklyHolidaysList.isEmpty) {
        if (jsWeekday == 0 || jsWeekday == 6) {
          isWeeklyOff = true;
        }
      } else if (weeklyHolidaysList.contains(jsWeekday)) {
        isWeeklyOff = true;
      }
    }

    if (isWeeklyOff) {
      weeklyOffDays++;
    } else {
      workingDays++;
    }
  }

  final holidaysInRange = holidays.where((h) {
    final d = DateTime(h.year, h.month, h.day);
    return !d.isBefore(firstDay) && !d.isAfter(effectiveEnd);
  }).length;

  return WorkingDaysInfo(
    totalDays: totalDays,
    workingDays: workingDays,
    weekends:
        weeklyOffDays, // Store weekly off days in weekends field for compatibility
    holidayCount: holidaysInRange,
  );
}
