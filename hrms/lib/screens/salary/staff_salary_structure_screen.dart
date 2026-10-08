import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../services/salary_service.dart';
import '../../utils/mongo_date_parse.dart';
import '../../utils/salary_ctc_helpers.dart';
import '../../widgets/app_tab_loader.dart';
import '../dashboard/dashboard_screen.dart';
import 'ctc_details_screen.dart';
import 'salary_revision_overview_screen.dart';
import 'salary_revision_detail_screen.dart';

/// Salary Structure home: CTC summary, revision notice, revision list, View All → graph.
class StaffSalaryStructureScreen extends StatefulWidget {
  const StaffSalaryStructureScreen({super.key});

  @override
  State<StaffSalaryStructureScreen> createState() =>
      _StaffSalaryStructureScreenState();
}

class _StaffSalaryStructureScreenState extends State<StaffSalaryStructureScreen> {
  final SalaryService _salaryService = SalaryService();
  StaffSalaryBundle? _bundle;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }
Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final b = await _salaryService.getStaffSalaryBundle();
      if (!mounted) return;
      if (b == null) {
        setState(() {
          _bundle = null;
          _error = 'Could not load salary details.';
          _loading = false;
        });
        return;
      }
      if (!b.salaryDetailsAccessEnabled) {
        setState(() {
          _bundle = null;
          _loading = false;
        });
        _showAccessDeniedDialog();  // <-- Show dialog instead of setting error
        return;
      }
      setState(() {
        _bundle = b;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showAccessDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      // canPop:false makes the Android system back button run the same
      // navigation as OK (land on the dashboard) rather than just dismissing
      // the dialog onto this empty screen.
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.of(dialogContext).pop();
          _goToDashboard();
        },
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.error),
              SizedBox(width: 8),
              Text('Access Restricted'),
            ],
          ),
          content: const Text(
            'Salary details are not enabled for your account. Please contact HR.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // close dialog
                _goToDashboard(); // leave salary screen, back to dashboard
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  /// Leave the (empty) salary screen and return to the dashboard.
  void _goToDashboard() {
    if (!mounted) return;
    DashboardScreen.goToTab(context, 0);
  }

  /// Only the entries that are genuine revisions — the initial salary
  /// assignment created at joining is excluded (see [isActualSalaryRevision]).
  List<Map<String, dynamic>> _actualRevisions(StaffSalaryBundle b) =>
      b.revisionHistory.where(isActualSalaryRevision).toList();

  List<Map<String, dynamic>> _sortedHistoryDesc(StaffSalaryBundle b) {
    final list = _actualRevisions(b);
    int ts(Map<String, dynamic> e) {
      final d = parseMongoJsonDate(e['effectiveFrom']);
      return d?.millisecondsSinceEpoch ?? 0;
    }

    list.sort((a, c) => ts(c).compareTo(ts(a)));
    return list;
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Next revision strictly after today (local) — for yellow banner.
  DateTime? _nextFutureEffective(StaffSalaryBundle b) {
    final today = _startOfDay(DateTime.now());
    DateTime? best;
    for (final e in _actualRevisions(b)) {
      final d = parseMongoJsonDate(e['effectiveFrom']);
      if (d == null) continue;
      final sd = _startOfDay(d);
      if (sd.isAfter(today) && (best == null || sd.isBefore(best))) {
        best = sd;
      }
    }
    return best;
  }

  void _openRevisionOverview() {
    final b = _bundle;
    if (b == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SalaryRevisionOverviewScreen(bundle: b),
      ),
    );
  }

  void _openRevisionDetail(Map<String, dynamic> entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SalaryRevisionDetailScreen(entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Salary Structure'),
      ),
      body: _loading
          ? const Center(child: AppTabLoader())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.errorBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.error_outline_rounded,
                          size: 32, color: AppColors.error),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: _load, child: const Text('okk')),
                  ],
                ),
              ),
            )
          : _bundle == null
          ? const Center(
              child: Text('No data', style: AppTextStyles.bodySmall))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _buildBody(context, currency, _bundle!),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NumberFormat currency,
    StaffSalaryBundle b,
  ) {
    final monthlyGross = monthlyGrossSalaryFromSalaryMap(b.salary);
    final yearlyGross = yearlyGrossSalaryFromSalaryMap(b.salary);
    final monthlyCtc = monthlyCtcFromSalaryMap(b.salary);
    final yearlyCtc = yearlyCtcFromSalaryMap(b.salary);
    final futureEff = _nextFutureEffective(b);
    final historyDesc = _sortedHistoryDesc(b);
    final previewOnHome = historyDesc.take(1).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (futureEff != null) ...[
          _RevisionNoticeCard(
            effective: futureEff,
            onViewHistory: _openRevisionOverview,
            isInformationalOnly: false,
          ),
          const SizedBox(height: 12),
        ] else if (historyDesc.isNotEmpty) ...[
          _RevisionNoticeCard(
            isInformationalOnly: true,
            onViewHistory: _openRevisionOverview,
          ),
          const SizedBox(height: 12),
        ],
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFECEEF1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CtcDetailsScreen(
                    salary: b.salary,
                    onViewRevisionHistory: _openRevisionOverview,
                    nextEffectiveDate: futureEff,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.account_balance_wallet_outlined,
                            size: 20, color: AppColors.primaryText),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'CTC Details',
                          style: AppTextStyles.headingSmall,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textCaption,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ctcMini(
                            'Monthly Gross',
                            monthlyGross != null
                                ? currency.format(monthlyGross)
                                : '—',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ctcMini(
                            'Yearly Gross',
                            yearlyGross != null
                                ? currency.format(yearlyGross)
                                : '—',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (monthlyCtc != null && yearlyCtc != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Full CTC (incl. benefits): ${currency.format(monthlyCtc)} / mo · ${currency.format(yearlyCtc)} / yr',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Salary Revision Details',
            style: AppTextStyles.headingSmall,
          ),
        ),
        const SizedBox(height: 12),
        if (historyDesc.isEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            border: Border.all(color: const Color(0xFFECEEF1)),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.history_rounded,
                      size: 30, color: AppColors.primaryText),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No salary revisions on record.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headingSmall,
                ),
              ],
            ),
          )
        else ...[
          for (final e in previewOnHome) ...[
            _RevisionSummaryTile(
              entry: e,
              currency: currency,
              onTap: () => _openRevisionDetail(e),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _openRevisionOverview,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                backgroundColor: AppColors.surface,
              ),
              child: const Text('View All'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ctcMini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _RevisionNoticeCard extends StatelessWidget {
  const _RevisionNoticeCard({
    this.effective,
    required this.onViewHistory,
    this.isInformationalOnly = false,
  });

  final DateTime? effective;
  final VoidCallback onViewHistory;
  final bool isInformationalOnly;

  @override
  Widget build(BuildContext context) {
    final dateStr =
        effective != null ? DateFormat('d MMM, y').format(effective!) : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.brandDark, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isInformationalOnly
                      ? 'Your salary revision history is available below.'
                      : 'Salary is revised and will be effective from $dateStr.',
                  style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onViewHistory,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Revision History',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.primaryText),
                    ],
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

class _RevisionSummaryTile extends StatelessWidget {
  const _RevisionSummaryTile({
    required this.entry,
    required this.currency,
    required this.onTap,
  });

  final Map<String, dynamic> entry;
  final NumberFormat currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eff = parseMongoJsonDate(entry['effectiveFrom']);
    final title = eff != null
        ? DateFormat('MMM yyyy').format(eff)
        : 'Revision';
    final prev = entry['previousSalary'];
    final rev = entry['revisedSalary'];
    final prevMap = prev is Map ? Map<String, dynamic>.from(prev) : null;
    final revMap = rev is Map ? Map<String, dynamic>.from(rev) : null;
    final pCtc = yearlyCtcFromSalaryMap(prevMap);
    final rCtc = yearlyCtcFromSalaryMap(revMap);

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFECEEF1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.trending_up_rounded,
                        size: 20, color: AppColors.primaryText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.headingSmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textCaption),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ctcMini2(
                        'Previous CTC',
                        pCtc != null ? currency.format(pCtc) : '—',
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 16, color: AppColors.textCaption),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ctcMini2(
                        'Revised CTC',
                        rCtc != null ? currency.format(rCtc) : '—',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ctcMini2(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
