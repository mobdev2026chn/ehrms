import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../services/salary_service.dart';
import '../../utils/mongo_date_parse.dart';
import '../../utils/salary_ctc_helpers.dart';
import 'salary_revision_detail_screen.dart';

/// Full revision list + line chart of revised yearly CTC over time.
class SalaryRevisionOverviewScreen extends StatelessWidget {
  const SalaryRevisionOverviewScreen({super.key, required this.bundle});

  final StaffSalaryBundle bundle;

  List<_RevisionPoint> _points() {
    final pts = <_RevisionPoint>[];
    for (final e in bundle.revisionHistory.where(isActualSalaryRevision)) {
      final d = parseMongoJsonDate(e['effectiveFrom']);
      final rev = e['revisedSalary'];
      if (d == null || rev is! Map) continue;
      final ctc = yearlyCtcFromSalaryMap(Map<String, dynamic>.from(rev));
      if (ctc == null) continue;
      pts.add(_RevisionPoint(d, ctc));
    }
    pts.sort((a, b) => a.date.compareTo(b.date));

    final cur = yearlyCtcFromSalaryMap(bundle.salary);
    if (cur != null) {
      pts.add(_RevisionPoint(DateTime.now(), cur));
    }

    if (pts.length == 1) {
      final only = pts.first;
      pts.insert(
        0,
        _RevisionPoint(only.date.subtract(const Duration(days: 45)), only.ctc),
      );
    }
    return pts;
  }

  List<Map<String, dynamic>> _historyDesc() {
    final list =
        bundle.revisionHistory.where(isActualSalaryRevision).toList();
    int ts(Map<String, dynamic> e) {
      final d = parseMongoJsonDate(e['effectiveFrom']);
      return d?.millisecondsSinceEpoch ?? 0;
    }

    list.sort((a, c) => ts(c).compareTo(ts(a)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final pts = _points();
    final historyDesc = _historyDesc();
    final name = bundle.employeeName ?? 'Employee';
    final empId = bundle.employeeId ?? '';
    final staffType = bundle.staffType ?? '';
    final phone = bundle.phone;
    final curCtc = yearlyCtcFromSalaryMap(bundle.salary);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Salary Revision History'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _EmployeeHeader(
            name: name,
            subtitle: [
              if (empId.isNotEmpty) 'ID $empId',
              if (staffType.isNotEmpty) staffType,
            ].join(' | '),
            phone: phone,
            salaryText: curCtc != null ? currency.format(curCtc) : '—',
          ),
          const SizedBox(height: 12),
          if (pts.length >= 2)
            _ChartCard(points: pts)
          else
            AppCard(
              border: Border.all(color: const Color(0xFFECEEF1)),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.show_chart_rounded,
                        size: 20, color: AppColors.primaryText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      pts.isEmpty
                          ? 'Not enough revision data to plot a trend.'
                          : 'Add another revision to see a trend line.',
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
                ],
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
          for (final e in historyDesc) ...[
            _RevisionListTile(
              entry: e,
              currency: currency,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SalaryRevisionDetailScreen(
                      entry: e,
                      employeeName: name,
                      employeeId: empId.isNotEmpty ? empId : null,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _RevisionPoint {
  _RevisionPoint(this.date, this.ctc);

  final DateTime date;
  final double ctc;
}

class _EmployeeHeader extends StatelessWidget {
  const _EmployeeHeader({
    required this.name,
    required this.subtitle,
    required this.salaryText,
    this.phone,
  });

  final String name;
  final String subtitle;
  final String? phone;
  final String salaryText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.16),
            AppColors.primary.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primary,
            child: Icon(Icons.person_rounded,
                color: AppColors.onPrimary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.headingSmall,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall,
                  ),
                ],
                if (phone != null && phone!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Mobile No: $phone',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Salary: $salaryText',
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w600,
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

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.points});

  final List<_RevisionPoint> points;

  @override
  Widget build(BuildContext context) {
    final minC = points.map((p) => p.ctc).reduce((a, b) => a < b ? a : b);
    final maxC = points.map((p) => p.ctc).reduce((a, b) => a > b ? a : b);
    final pad = (maxC - minC) * 0.15;
    var minY = minC - pad;
    var maxY = maxC + pad;
    if ((maxY - minY) < 1) {
      minY = 0;
      maxY = maxC + 1;
    }

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].ctc),
    ];

    return Container(
      height: 272,
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEEF1)),
        boxShadow: kSoftCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12, right: 8),
            child: Text(
              'Salary Revision Overview',
              style: AppTextStyles.headingSmall,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 12, right: 8, top: 4),
            child: Text(
              'Revised yearly CTC at each effective date',
              style: AppTextStyles.bodySmall,
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY) > 0 ? (maxY - minY) / 4 : 1,
                  getDrawingHorizontalLine: (v) => const FlLine(
                    color: Color(0xFFECEEF1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, m) {
                        final lakhs = v / 100000.0;
                        final t = lakhs >= 1
                            ? '${lakhs.toStringAsFixed(1)}L'
                            : NumberFormat.compact().format(v);
                        return Text(
                          t,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final i = v.round();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('MMM\nyyyy').format(points[i].date),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: AppColors.surface,
                        strokeWidth: 2.5,
                        strokeColor: AppColors.primary,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.28),
                          AppColors.primary.withValues(alpha: 0.02),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevisionListTile extends StatelessWidget {
  const _RevisionListTile({
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
          child: Row(
            children: [
              Expanded(
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
                            child: _mini(
                              'Previous CTC',
                              pCtc != null ? currency.format(pCtc) : '—',
                            ),
                          ),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 16, color: AppColors.textCaption),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _mini(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
