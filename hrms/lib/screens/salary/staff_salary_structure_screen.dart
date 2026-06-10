import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../services/salary_service.dart';
import '../../utils/mongo_date_parse.dart';
import '../../utils/salary_ctc_helpers.dart';
import '../../widgets/app_tab_loader.dart';
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
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Access Restricted'),
          ],
        ),
        content: const Text(
          'Salary details are not enabled for your account. Please contact HR.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _sortedHistoryDesc(StaffSalaryBundle b) {
    final list = List<Map<String, dynamic>>.from(b.revisionHistory);
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
    for (final e in b.revisionHistory) {
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
        title: const Text(
          'Salary Structure',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
        elevation: 0,
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
                    Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('okk')),
                  ],
                ),
              ),
            )
          : _bundle == null
          ? const Center(child: Text('No data'))
          : RefreshIndicator(
              onRefresh: _load,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (futureEff != null) ...[
          _RevisionNoticeCard(
            effective: futureEff,
            onViewHistory: _openRevisionOverview,
            isInformationalOnly: false,
          ),
          const SizedBox(height: 12),
        ] else if (b.revisionHistory.isNotEmpty) ...[
          _RevisionNoticeCard(
            isInformationalOnly: true,
            onViewHistory: _openRevisionOverview,
          ),
          const SizedBox(height: 12),
        ],
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 1,
          shadowColor: Colors.black12,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'CTC Details',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ctcMini(
                          'Monthly Gross',
                          monthlyGross != null
                              ? currency.format(monthlyGross)
                              : '—',
                        ),
                      ),
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
                  if (monthlyCtc != null && yearlyCtc != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Full CTC (incl. benefits): ${currency.format(monthlyCtc)} / mo · ${currency.format(yearlyCtc)} / yr',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Salary Revision Details',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        if (historyDesc.isEmpty)
          Text(
            'No salary revisions on record.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          )
        else ...[
          for (final e in previewOnHome) ...[
            _RevisionSummaryTile(
              entry: e,
              currency: currency,
              onTap: () => _openRevisionDetail(e),
            ),
            const SizedBox(height: 10),
          ],
          Center(
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.secondary.withOpacity(0.12),
                foregroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _openRevisionOverview,
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
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.textPrimary,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isInformationalOnly
                      ? 'Your salary revision history is available below.'
                      : 'Salary is revised and will be effective from $dateStr.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onViewHistory,
                  child: Text(
                    'View Revision History',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary,
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ctcMini2(
                      'Previous CTC',
                      pCtc != null ? currency.format(pCtc) : '—',
                    ),
                  ),
                  Expanded(
                    child: _ctcMini2(
                      'Revised CTC',
                      rCtc != null ? currency.format(rCtc) : '—',
                    ),
                  ),
                ],
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
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
