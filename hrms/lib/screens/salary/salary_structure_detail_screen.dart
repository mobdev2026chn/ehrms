import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/profile_app_bar_actions.dart';
import '../../utils/salary_structure_calculator.dart';
import '../../services/salary_service.dart';
import '../../widgets/app_tab_loader.dart';
import '../dashboard/dashboard_screen.dart';

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

  // Authoritative headline figures straight from the payroll controller
  // (GET /payroll/stats → computeMonthlySalaryFromStaffSalary). When present
  // they override the locally-calculated gross / net / CTC so the big numbers
  // are exactly what the backend returns.
  double? _ctrlGross;
  double? _ctrlNet;
  double? _ctrlCtc;

  static double? _numOrNull(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

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
      // Pull the exact per-user salary structure from the API. getStaffSalaryBundle
      // resolves the real salary (geo profile → web-HRMS fallback) and carries the
      // access flag, unlike the thin geo-only getStaffSalaryDetails().
      final bundle = await _salaryService.getStaffSalaryBundle();
      if (bundle == null) {
        setState(() {
          _error = 'Could not load salary details.';
          _isLoading = false;
        });
        _showErrorDialog(_error);
        return;
      }
      if (!bundle.salaryDetailsAccessEnabled) {
        setState(() {
          _error =
              'Salary details are not enabled for your account. Please contact HR.';
          _isLoading = false;
        });
        _showErrorDialog(_error);
        return;
      }

      final inputs = SalaryStructureInputs.fromMap(bundle.salary);
      final calculated = calculateSalaryStructure(inputs);

      // Pull the authoritative gross / net / CTC from the payroll controller.
      // getSalaryStats() hits GET /payroll/stats (web HRMS → geo fallback) which
      // computes them server-side from staff.salary.
      double? ctrlGross, ctrlNet, ctrlCtc;
      try {
        final statsEnv = await _salaryService.getSalaryStats();
        final data = statsEnv['data'];
        final stats = data is Map ? data['stats'] : null;
        if (stats is Map) {
          ctrlGross = _numOrNull(stats['grossSalary']);
          ctrlNet = _numOrNull(stats['netSalary']);
          ctrlCtc = _numOrNull(stats['ctc']);
        }
      } catch (_) {
        // Non-fatal: fall back to the locally-calculated figures.
      }

      setState(() {
        _salaryInputs = inputs;
        _salaryStructure = calculated;
        _ctrlGross = ctrlGross;
        _ctrlNet = ctrlNet;
        _ctrlCtc = ctrlCtc;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _showErrorDialog(_error);
    }
  }

  /// Surface a load failure in a modal dialog with OK (dismiss) and Retry
  /// (re-run the fetch) actions. The inline error state remains as a fallback
  /// behind the dialog.
  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // canPop:false routes the Android system back button through
      // onPopInvokedWithResult so it lands on the dashboard, exactly like OK,
      // instead of just dismissing the dialog onto the empty screen behind it.
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.of(dialogContext).pop();
          _goToDashboard();
        },
        child: AlertDialog(
          title: const Text('Unable to load salary'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _goToDashboard();
              },
              child: const Text('OK'),
            ),
            // FilledButton(
            //   onPressed: () {
            //     Navigator.of(dialogContext).pop();
            //     _fetchAndCalculateSalary();
            //   },
            //   child: const Text('Retry'),
            // ),
          ],
        ),
      ),
    );
  }

  /// Leave the (empty) salary screen and return to the dashboard.
  void _goToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Salary Structure',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: const [ProfileAppBarActions()],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _isLoading
            ? const Center(key: ValueKey('salary-loading'), child: AppTabLoader())
            : _error.isNotEmpty
                // Errors are surfaced via _showErrorDialog (OK → dashboard,
                // Retry → refetch); keep the background clean behind the modal.
                ? const SizedBox.shrink(key: ValueKey('salary-error'))
                : _salaryStructure == null
                    ? const Center(
                        child: Text('No salary structure data available'))
                    : RefreshIndicator(
                        onRefresh: _fetchAndCalculateSalary,
                        child: _buildContent(currencyFormat),
                      ),
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _buildContent(NumberFormat currencyFormat) {
    final monthly = _salaryStructure!.monthly;
    final yearly = _salaryStructure!.yearly;
    final inputs = _salaryInputs;

    // Prefer the payroll controller's exact figures for the headline cards.
    final heroGross = _ctrlGross ?? monthly.grossSalary;
    final netTakeHome = _ctrlNet ?? monthly.netMonthlySalary;
    final totalCtc = _ctrlCtc ?? _salaryStructure!.totalCTC;

    // Fixed earning components (web parity — same rows as before, restyled).
    final earnings = <_Component>[
      _Component(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Basic',
        subtitle: 'Fixed Component',
        amount: monthly.basicSalary,
      ),
      _Component(
        icon: Icons.trending_up_rounded,
        title: 'DA',
        subtitle: 'Dearness Allowance',
        amount: monthly.dearnessAllowance,
      ),
      _Component(
        icon: Icons.home_outlined,
        title: 'HRA',
        subtitle: 'House Rent Allowance',
        amount: monthly.houseRentAllowance,
      ),
      _Component(
        icon: Icons.star_outline_rounded,
        title: 'Special Allowances',
        subtitle: 'Performance Linked',
        amount: monthly.specialAllowance,
      ),
      _Component(
        icon: Icons.health_and_safety_outlined,
        title:
            'ESI (Employer) ${inputs?.employerESIRate.toStringAsFixed(2) ?? '0.00'}%',
        subtitle: 'Employer Contribution',
        amount: monthly.employerESI,
      ),
      _Component(
        icon: Icons.account_balance_outlined,
        title:
            'PF (Employer) ${kWebStatutoryPfPercentOnBasic.toStringAsFixed(0)}%',
        subtitle: 'Provident Fund',
        amount: monthly.employerPF,
      ),
    ];

    // Employee deductions (web payslip: employee PF + ESI only).
    final deductions = <_Component>[
      _Component(
        icon: Icons.account_balance_outlined,
        title:
            'Employee PF ${kWebStatutoryPfPercentOnBasic.toStringAsFixed(0)}%',
        subtitle: 'Provident Fund Contribution',
        amount: monthly.employeePF,
      ),
      _Component(
        icon: Icons.shield_outlined,
        title:
            'Employee ESI ${inputs?.employeeESIRate.toStringAsFixed(2) ?? '0.00'}%',
        subtitle: 'Insurance Contribution',
        amount: monthly.employeeESI,
      ),
    ];

    // Yearly benefits, variables and allowances (kept from original logic).
    final benefits = <_Component>[
      _Component(
        icon: Icons.emoji_events_outlined,
        title: '*Incentive (${inputs?.incentiveRate.toStringAsFixed(0) ?? '0'}%)',
        subtitle: 'Performance based',
        amount: yearly.annualIncentive,
      ),
      _Component(
        icon: Icons.medical_services_outlined,
        title: 'Medical Insurance',
        subtitle: 'Group Policy',
        amount: yearly.medicalInsuranceAmount,
      ),
      _Component(
        icon: Icons.card_giftcard_outlined,
        title: 'Gratuity (${inputs?.gratuityRate.toStringAsFixed(2) ?? '0.00'}%)',
        subtitle: 'Yearly Benefit',
        amount: yearly.annualGratuity,
      ),
      _Component(
        icon: Icons.redeem_outlined,
        title:
            'Statutory Bonus (${inputs?.statutoryBonusRate.toStringAsFixed(2) ?? '0.00'}%)',
        subtitle: 'Yearly Benefit',
        amount: yearly.annualStatutoryBonus,
      ),
      _Component(
        icon: Icons.smartphone_outlined,
        title: 'Mobile Allowances',
        subtitle: inputs?.mobileAllowanceType == 'yearly'
            ? 'Paid yearly'
            : 'Paid monthly',
        amount: yearly.annualMobileAllowance,
      ),
    ];

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero: gross monthly salary ──────────────────────────────────
          _buildHeroCard(heroGross, currencyFormat),
          const SizedBox(height: 22),

          // ── Earnings ────────────────────────────────────────────────────
          _sectionHeader('Earnings', trailing: 'COMPONENTS'),
          const SizedBox(height: 10),
          _buildComponentCard(earnings, currencyFormat),
          const SizedBox(height: 22),

          // ── Deductions ──────────────────────────────────────────────────
          _sectionHeader('Deductions'),
          const SizedBox(height: 10),
          _buildComponentCard(
            deductions,
            currencyFormat,
            isDeduction: true,
            totalLabel: 'Total Deductions',
            totalAmount: monthly.totalMonthlyDeductions,
          ),
          const SizedBox(height: 22),

          // ── Benefits & Allowances (yearly) ──────────────────────────────
          _sectionHeader('Benefits & Allowances', trailing: 'YEARLY'),
          const SizedBox(height: 10),
          _buildComponentCard(benefits, currencyFormat),
          const SizedBox(height: 22),

          // ── Net take home (dark hero) ───────────────────────────────────
          _buildNetSalaryCard(netTakeHome, currencyFormat),
          const SizedBox(height: 14),

          // ── Total CTC ───────────────────────────────────────────────────
          _buildCTCCard(totalCtc, currencyFormat),
          const SizedBox(height: 14),

          // ── Footer note ─────────────────────────────────────────────────
          _buildInfoNote(),
        ],
      ),
    );
  }

  Widget _buildHeroCard(double gross, NumberFormat format) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GROSS MONTHLY SALARY', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              format.format(gross),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up_rounded,
                        size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      'Per Month',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'System generated',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTextStyles.headingMedium),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComponentCard(
    List<_Component> items,
    NumberFormat format, {
    bool isDeduction = false,
    String? totalLabel,
    double? totalAmount,
  }) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++)
            _buildComponentRow(
              items[i],
              format,
              isDeduction: isDeduction,
              isLast: i == items.length - 1 && totalLabel == null,
            ),
          if (totalLabel != null && totalAmount != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      totalLabel,
                      style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
                    ),
                  ),
                  Text(
                    isDeduction
                        ? '−${format.format(totalAmount)}'
                        : format.format(totalAmount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDeduction
                          ? AppColors.error
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComponentRow(
    _Component item,
    NumberFormat format, {
    required bool isDeduction,
    required bool isLast,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppColors.divider.withValues(alpha: 0.7),
                ),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDeduction
                  ? AppColors.errorBg
                  : AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.icon,
              size: 22,
              color: isDeduction ? AppColors.error : AppColors.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: AppTextStyles.bodySmall
                      .copyWith(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isDeduction
                ? '−${format.format(item.amount)}'
                : format.format(item.amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDeduction ? AppColors.error : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Figma: dark "NET TAKE HOME" card.
  Widget _buildNetSalaryCard(double monthlyNet, NumberFormat format) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NET TAKE HOME',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    format.format(monthlyNet),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Payable per month after all deductions',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildCTCCard(double ctc, NumberFormat format) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.savings_outlined,
                size: 22, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total CTC',
                  style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Annual cost to company (A+B+C+D)',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                format.format(ctc),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.textCaption),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is a system-generated salary structure based on your current contract.',
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight view model for a single salary line (earning / deduction / benefit).
class _Component {
  const _Component({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double amount;
}
