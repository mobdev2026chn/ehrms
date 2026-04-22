import 'salary_structure_calculator.dart';

/// Full structure from staff `salary` (same rules as web `salaryStructureCalculation`).
CalculatedSalaryStructure? calculatedSalaryFromStaffSalaryMap(
  Map<String, dynamic>? salary,
) {
  if (salary == null || !salaryMapHasNumericComponents(salary)) return null;
  try {
    if (salary['gross'] != null && salary['basicSalary'] == null) {
      return calculatedSalaryFromLegacyStaffMap(salary);
    }
    return calculateSalaryStructure(SalaryStructureInputs.fromMap(salary));
  } catch (_) {
    return null;
  }
}

/// Yearly CTC from a staff `salary` map, or null if not computable.
double? yearlyCtcFromSalaryMap(Map<String, dynamic>? salary) {
  final c = calculatedSalaryFromStaffSalaryMap(salary);
  return c?.totalCTC;
}

/// Monthly gross (Basic+DA+HRA+Special + employer PF/ESI + PF static) — web "Template earnings" total.
double? monthlyGrossSalaryFromSalaryMap(Map<String, dynamic>? salary) {
  final c = calculatedSalaryFromStaffSalaryMap(salary);
  return c?.monthly.grossSalary;
}

/// Yearly gross = monthly gross × 12.
double? yearlyGrossSalaryFromSalaryMap(Map<String, dynamic>? salary) {
  final m = monthlyGrossSalaryFromSalaryMap(salary);
  if (m == null) return null;
  return m * 12;
}

/// Monthly figure: yearly CTC ÷ 12 (includes benefits where applicable).
double? monthlyCtcFromSalaryMap(Map<String, dynamic>? salary) {
  final y = yearlyCtcFromSalaryMap(salary);
  if (y == null) return null;
  return y / 12.0;
}

bool salaryMapHasNumericComponents(Map<String, dynamic>? m) {
  if (m == null || m.isEmpty) return false;
  return m.containsKey('basicSalary') ||
      m['gross'] != null ||
      m.containsKey('dearnessAllowance') ||
      m.containsKey('houseRentAllowance');
}
