import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../utils/salary_structure_calculator.dart';
import '../../services/salary_service.dart';
import '../../widgets/app_tab_loader.dart';

class SalaryStructureDetailScreen extends StatefulWidget {
  const SalaryStructureDetailScreen({super.key});

  @override
  State<SalaryStructureDetailScreen> createState() =>
      _SalaryStructureDetailScreenState();
}

class _SalaryStructureDetailScreenState
    extends State<SalaryStructureDetailScreen> {
  final SalaryService _salaryService = SalaryService();
  bool _isLoading = true;
  CalculatedSalaryStructure? _salaryStructure;
  SalaryStructureInputs? _salaryInputs;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchAndCalculateSalary();
  }

  Future<void> _fetchAndCalculateSalary() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final salaryData = await _salaryService.getStaffSalaryDetails();
      if (salaryData == null) {
        setState(() {
          _error = 'Salary details not found';
          _isLoading = false;
        });
        return;
      }

      final inputs = SalaryStructureInputs.fromMap(salaryData);
      final calculated = calculateSalaryStructure(inputs);

      setState(() {
        _salaryInputs = inputs;
        _salaryStructure = calculated;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Salary Structure Details',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: $_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchAndCalculateSalary,
                    child: Text('Retry'),
                  ),
                ],
              ),
            )
          : _salaryStructure == null
          ? const Center(child: Text('No salary structure data available'))
          : RefreshIndicator(
              onRefresh: _fetchAndCalculateSalary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with title and subtitle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Salary Structure Overview',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Current salary structure configuration and calculated values',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Main table container with header and all sections
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Table Header (shown once at top)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                              border: Border(
                                bottom: BorderSide(
                                  color: AppColors.primary.withOpacity(0.2),
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'Component',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Per Month',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Per Year',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Fixed Components Section
                          _buildSectionCard(
                            '(A) Fixed Components',
                            [
                              _buildTableRow(
                                'Basic',
                                _salaryStructure!.monthly.basicSalary,
                                _salaryStructure!.monthly.basicSalary * 12,
                                currencyFormat,
                              ),
                              _buildTableRow(
                                'DA (Dearness Allowance)',
                                _salaryStructure!.monthly.dearnessAllowance,
                                _salaryStructure!.monthly.dearnessAllowance *
                                    12,
                                currencyFormat,
                              ),
                              _buildTableRow(
                                'HRA (House Rent Allowance)',
                                _salaryStructure!.monthly.houseRentAllowance,
                                _salaryStructure!.monthly.houseRentAllowance *
                                    12,
                                currencyFormat,
                              ),
                              _buildTableRow(
                                'Special Allowances',
                                _salaryStructure!.monthly.specialAllowance,
                                _salaryStructure!.monthly.specialAllowance * 12,
                                currencyFormat,
                              ),
                              _buildTableRow(
                                'ESI (Employer) ${_salaryInputs?.employerESIRate.toStringAsFixed(2) ?? '0.00'}%',
                                _salaryStructure!.monthly.employerESI,
                                _salaryStructure!.monthly.employerESI * 12,
                                currencyFormat,
                              ),
                              _buildTableRow(
                                'PF (Employer) ${_salaryInputs?.employerPFRate.toStringAsFixed(0) ?? '0'}%',
                                _salaryStructure!.monthly.employerPF,
                                _salaryStructure!.monthly.employerPF * 12,
                                currencyFormat,
                              ),
                            ],
                            _buildTableRow(
                              'Gross Salary',
                              _salaryStructure!.monthly.grossSalary,
                              _salaryStructure!.yearly.annualGrossSalary,
                              currencyFormat,
                              isTotal: true,
                              backgroundColor: Colors.blue.shade50,
                            ),
                          ),
                          // Variables Section
                          _buildSectionCard('(B) Variables (Performance based)', [
                            _buildTableRow(
                              '*Incentive (${_salaryInputs?.incentiveRate.toStringAsFixed(0) ?? '0'}%)',
                              0,
                              _salaryStructure!.yearly.annualIncentive,
                              currencyFormat,
                              showDash: true,
                            ),
                          ], null),
                          // Benefits Section
                          _buildSectionCard(
                            '(C) Benefits (Yearly)',
                            [
                              _buildTableRow(
                                'Medical Insurance',
                                0,
                                _salaryStructure!.yearly.medicalInsuranceAmount,
                                currencyFormat,
                                showDash: true,
                              ),
                              _buildTableRow(
                                'Gratuity (${_salaryInputs?.gratuityRate.toStringAsFixed(2) ?? '0.00'}%)',
                                0,
                                _salaryStructure!.yearly.annualGratuity,
                                currencyFormat,
                                showDash: true,
                              ),
                              _buildTableRow(
                                'Statutory Bonus (${_salaryInputs?.statutoryBonusRate.toStringAsFixed(2) ?? '0.00'}%)',
                                0,
                                _salaryStructure!.yearly.annualStatutoryBonus,
                                currencyFormat,
                                showDash: true,
                              ),
                            ],
                            _buildTableRow(
                              'Total Benefits (C)',
                              0,
                              _salaryStructure!.yearly.totalAnnualBenefits,
                              currencyFormat,
                              isTotal: true,
                              backgroundColor: Colors.blue.shade50,
                              showDash: true,
                            ),
                          ),
                          // Allowances Section
                          _buildSectionCard('(D) Allowances', [
                            _buildTableRow(
                              'Mobile Allowances',
                              _salaryInputs?.mobileAllowanceType == 'monthly'
                                  ? (_salaryStructure!
                                            .yearly
                                            .annualMobileAllowance /
                                        12)
                                  : 0,
                              _salaryStructure!.yearly.annualMobileAllowance,
                              currencyFormat,
                              showDash:
                                  _salaryInputs?.mobileAllowanceType ==
                                  'yearly',
                            ),
                          ], null),
                          // Deductions (web payslip: employer PF/ESI shown here; net = gross − this total)
                          _buildSectionCard(
                            'Deductions',
                            [
                              _buildTableRow(
                                'Employer contribution to PF (${_salaryInputs?.employerPFRate.toStringAsFixed(0) ?? '0'}%)',
                                _salaryStructure!.monthly.employerPF,
                                _salaryStructure!.monthly.employerPF * 12,
                                currencyFormat,
                              ),
                              _buildTableRow(
                                'Employer contribution to ESI (${_salaryInputs?.employerESIRate.toStringAsFixed(2) ?? '0.00'}%)',
                                _salaryStructure!.monthly.employerESI,
                                _salaryStructure!.monthly.employerESI * 12,
                                currencyFormat,
                              ),
                              _buildTableRow(
                                'Employee contribution to PF (${_salaryInputs?.employeePFRate.toStringAsFixed(0) ?? '0'}%)',
                                _salaryStructure!.monthly.employeePF,
                                _salaryStructure!.monthly.employeePF * 12,
                                currencyFormat,
                              ),
                              _buildTableRow(
                                'Employee contribution to ESI (${_salaryInputs?.employeeESIRate.toStringAsFixed(2) ?? '0.00'}%)',
                                _salaryStructure!.monthly.employeeESI,
                                _salaryStructure!.monthly.employeeESI * 12,
                                currencyFormat,
                              ),
                            ],
                            _buildTableRow(
                              'Total Deductions',
                              _salaryStructure!.monthly.totalMonthlyDeductions,
                              _salaryStructure!.monthly.totalMonthlyDeductions *
                                  12,
                              currencyFormat,
                              isTotal: true,
                              backgroundColor: Colors.red.shade50,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Net Salary Section
                    _buildNetSalaryCard(
                      _salaryStructure!.monthly.netMonthlySalary,
                      _salaryStructure!.yearly.annualNetSalary,
                      currencyFormat,
                    ),
                    const SizedBox(height: 12),
                    // Total CTC Section
                    _buildCTCCard(_salaryStructure!.totalCTC, currencyFormat),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: 2),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> rows, Widget? totalRow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08)),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: rows),
        ),
        if (totalRow != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: totalRow,
          ),
      ],
    );
  }

  Widget _buildTableRow(
    String label,
    double monthlyAmount,
    double yearlyAmount,
    NumberFormat format, {
    bool isTotal = false,
    Color? backgroundColor,
    bool showDash = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isTotal ? 13 : 12,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              showDash && monthlyAmount == 0
                  ? '-'
                  : format.format(monthlyAmount),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: isTotal ? 13 : 12,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              showDash && yearlyAmount == 0 ? '-' : format.format(yearlyAmount),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: isTotal ? 13 : 12,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetSalaryCard(
    double monthlyNet,
    double yearlyNet,
    NumberFormat format,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(color: Colors.grey.shade100),
            child: Text(
              'Net Salary',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Container(
            color: Colors.green.shade50,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      'Net Salary per month',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      format.format(monthlyNet),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      format.format(yearlyNet),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCTCCard(double ctc, NumberFormat format) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(color: Colors.grey.shade100),
            child: Text(
              'Total CTC (A+B+C+D)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Container(
            color: Colors.blue.shade100,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      'Total CTC (A+B+C+D)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      format.format(ctc),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
