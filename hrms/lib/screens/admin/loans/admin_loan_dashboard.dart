// Loan Dashboard (GET /admin/loans/dashboard): the nine summary figures plus the four charts
// of the web LoanDashboard - loan type wise, department / branch wise, monthly recovery
// (expected vs recovered) and the outstanding trend.
//
// Note: the backend dashboard ignores query filters (loanDashboardController builds from every
// loan of the company), so no filters are offered here.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/loan_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import '../../loans/loan_widgets.dart';

final _compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);
String _short(num v) => v.abs() < 1000 ? loanMoney(v) : _compact.format(v);

class AdminLoanDashboard extends StatefulWidget {
  const AdminLoanDashboard({super.key, this.onOpenTab});

  /// Lets a stat tile jump to the requests (1) or loans (2) tab of the parent.
  final ValueChanged<int>? onOpenTab;

  @override
  State<AdminLoanDashboard> createState() => _AdminLoanDashboardState();
}

class _AdminLoanDashboardState extends State<AdminLoanDashboard> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _byBranch = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await LoanService().adminDashboard();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  List<Map<String, dynamic>> _rows(String key) => _data?[key] is List
      ? (_data![key] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  @override
  Widget build(BuildContext context) {
    if (_error != null && _data == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 30),
            ),
          ),
          const SizedBox(height: 16),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () {
                setState(() => _error = null);
                _load();
              },
              child: const Text('Retry')),
        ],
      );
    }
    final d = _data;
    if (d == null) return const Center(child: AppTabLoader());
    final t = d['totals'] is Map ? Map<String, dynamic>.from(d['totals']) : <String, dynamic>{};
    num n(String k) => (t[k] as num?) ?? 0;

    if (n('totalLoans') == 0 && n('pending') == 0 && n('rejected') == 0) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.account_balance_wallet_outlined, size: 30, color: AppColors.primaryText),
                ),
                const SizedBox(height: 16),
                const Text('No loans yet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                const Text('Once employees request loans or salary advances, the summary will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45)),
              ],
            ),
          ),
        ]),
      );
    }

    final tiles = <(String, String, Color?, int?)>[
      ('Total loans', '${n('totalLoans')}', null, 2),
      ('Pending', '${n('pending')}', AppColors.brandDark, 1),
      ('Approved', '${n('approved')}', AppColors.success, 2),
      ('Disbursed', '${n('disbursed')}', AppColors.info, 2),
      ('Recovered', _short(n('recoveredAmount')), AppColors.success, null),
      ('Outstanding', _short(n('outstandingAmount')), AppColors.indigo, null),
      ('Defaulted', '${n('defaulted')}', n('defaulted') > 0 ? AppColors.error : null, null),
      ('Overdue', '${n('overdue')}', n('overdue') > 0 ? AppColors.error : null, null),
      ('Rejected', '${n('rejected')}', null, 1),
      ('Overdue amount', _short(n('overdueAmount')), n('overdueAmount') > 0 ? AppColors.error : null, null),
      ('Interest earned', _short(n('interestEarned')), null, null),
      ('Active advances', '${n('activeAdvances')}', null, null),
    ];

    final byType = _rows('byType').map((e) => _Bar(e['label']?.toString() ?? '', (e['count'] as num?) ?? 0, (e['amount'] as num?) ?? 0)).toList();
    final breakdown = _rows(_byBranch ? 'byBranch' : 'byDepartment')
        .map((e) => _Bar(e['label']?.toString() ?? '', (e['count'] as num?) ?? 0, (e['outstanding'] as num?) ?? 0))
        .toList();
    final monthly = _rows('monthlyRecovery');
    final trend = _rows('outstandingTrend');

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: [
              for (final (label, value, color, tab) in tiles)
                LoanCard(
                  onTap: tab == null || widget.onOpenTab == null ? null : () => widget.onOpenTab!(tab),
                  child: LoanStat(label, value, color: color),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Loan type wise',
            subtitle: 'Amount lent per loan type',
            child: byType.isEmpty ? const _NoData('No loan types to show') : _BarList(items: byType),
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: _byBranch ? 'Branch wise' : 'Department wise',
            subtitle: 'Outstanding balance',
            trailing: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: false, label: Text('Dept', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: true, label: Text('Branch', style: TextStyle(fontSize: 12))),
              ],
              selected: {_byBranch},
              onSelectionChanged: (s) => setState(() => _byBranch = s.first),
            ),
            child: breakdown.isEmpty ? const _NoData('Nothing outstanding') : _BarList(items: breakdown),
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Monthly recovery',
            subtitle: 'Expected vs recovered, last 6 months',
            child: monthly.isEmpty ? const _NoData('No recovery data yet') : _MonthlyRecoveryChart(rows: monthly),
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Outstanding trend',
            subtitle: 'Balance owed at each month end',
            child: trend.isEmpty ? const _NoData('No outstanding history yet') : _TrendChart(rows: trend),
          ),
        ],
      ),
    );
  }
}

class _Bar {
  const _Bar(this.label, this.count, this.value);
  final String label;
  final num count, value;
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.subtitle, required this.child, this.trailing});
  final String title, subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LoanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
}

class _NoData extends StatelessWidget {
  const _NoData(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.insert_chart_outlined_rounded, size: 28, color: AppColors.textCaption),
              const SizedBox(height: 8),
              Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
}

/// Horizontal bars, largest first (web BarList).
class _BarList extends StatelessWidget {
  const _BarList({required this.items});
  final List<_Bar> items;

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]..sort((a, b) => b.value.compareTo(a.value));
    final maxV = sorted.fold<num>(0, (m, e) => math.max(m, e.value));
    return Column(
      children: [
        for (final e in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Text('${e.count} · ${loanMoney(e.value)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: maxV <= 0 ? 0 : (e.value / maxV).toDouble(),
                    minHeight: 8,
                    backgroundColor: AppColors.inputFill,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Widget _legend(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      ],
    );

class _MonthlyRecoveryChart extends StatelessWidget {
  const _MonthlyRecoveryChart({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    double v(Map<String, dynamic> r, String k) => ((r[k] as num?) ?? 0).toDouble();
    final maxY = rows.fold<double>(0, (m, r) => math.max(m, math.max(v(r, 'expected'), v(r, 'recovered'))));
    return Column(
      children: [
        Row(children: [_legend(AppColors.textCaption, 'Expected'), const SizedBox(width: 14), _legend(AppColors.success, 'Recovered')]),
        const SizedBox(height: 10),
        SizedBox(
          height: 190,
          child: BarChart(
            BarChartData(
              maxY: maxY <= 0 ? 1 : maxY * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFECEEF1), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    '${ri == 0 ? 'Expected' : 'Recovered'}\n${loanMoney(rod.toY)}',
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) => Text(_short(value),
                        style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(rows[i]['month']?.toString() ?? '',
                            style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < rows.length; i++)
                  BarChartGroupData(x: i, barsSpace: 3, barRods: [
                    BarChartRodData(toY: v(rows[i], 'expected'), color: AppColors.textCaption, width: 9, borderRadius: BorderRadius.circular(2)),
                    BarChartRodData(toY: v(rows[i], 'recovered'), color: AppColors.success, width: 9, borderRadius: BorderRadius.circular(2)),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final values = [for (final r in rows) ((r['outstanding'] as num?) ?? 0).toDouble()];
    final maxY = values.fold<double>(0, math.max);
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFECEEF1), strokeWidth: 1),
              ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(loanMoney(s.y), const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) =>
                    Text(_short(value), style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= rows.length || value != i.toDouble()) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(rows[i]['month']?.toString() ?? '',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
              isCurved: true,
              preventCurveOverShooting: true,
              color: AppColors.indigo,
              barWidth: 2.5,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: AppColors.indigo.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }
}
