import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
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
    for (final e in bundle.revisionHistory) {
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
    final list = List<Map<String, dynamic>>.from(bundle.revisionHistory);
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
        title: const Text(
          'Salary Revision History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 16),
          if (pts.length >= 2)
            _ChartCard(points: pts)
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                pts.isEmpty
                    ? 'Not enough revision data to plot a trend.'
                    : 'Add another revision to see a trend line.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Salary Revision Details',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          for (final e in historyDesc) ...[
            _RevisionListTile(
              entry: e,
              currency: currency,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SalaryRevisionDetailScreen(entry: e),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.secondary,
            child: const Icon(Icons.person, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ],
                if (phone != null && phone!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Mobile No: $phone',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Salary: $salaryText',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
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
      height: 260,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, right: 8),
            child: Text(
              'Salary Revision Overview',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
            child: Text(
              'Revised yearly CTC at each effective date',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY) > 0 ? (maxY - minY) / 4 : 1,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey.shade200,
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
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey.shade700,
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
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade700,
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
                    color: AppColors.success,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.success.withOpacity(0.35),
                          AppColors.success.withOpacity(0.02),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _mini(
                            'Previous CTC',
                            pCtc != null ? currency.format(pCtc) : '—',
                          ),
                        ),
                        Expanded(
                          child: _mini(
                            'Revised CTC',
                            rCtc != null ? currency.format(rCtc) : '—',
                          ),
                        ),
                      ],
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
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    );
  }
}
