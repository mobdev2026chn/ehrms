import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../utils/mongo_date_parse.dart';
import '../../utils/salary_ctc_helpers.dart';

/// Single revision: summary + per-component previous vs revised (annualized from monthly map values).
class SalaryRevisionDetailScreen extends StatelessWidget {
  const SalaryRevisionDetailScreen({super.key, required this.entry});

  final Map<String, dynamic> entry;

  static const _componentOrder = [
    'basicSalary',
    'dearnessAllowance',
    'houseRentAllowance',
    'specialAllowance',
    'mobileAllowance',
    'medicalInsuranceAmount',
  ];

  static const _labels = {
    'basicSalary': 'BASIC',
    'dearnessAllowance': 'DA',
    'houseRentAllowance': 'HRA',
    'specialAllowance': 'Special Allowance',
    'mobileAllowance': 'Mobile Allowance',
    'medicalInsuranceAmount': 'Medical Insurance',
    'employerPFRate': 'Employer PF %',
    'employerESIRate': 'Employer ESI %',
    'employeePFRate': 'Employee PF %',
    'employeeESIRate': 'Employee ESI %',
  };

  double? _monthly(Map<String, dynamic>? m, String key) {
    if (m == null) return null;
    final v = m[key];
    if (v is! num) return null;
    return v.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final prevRaw = entry['previousSalary'];
    final revRaw = entry['revisedSalary'];
    final prev = prevRaw is Map ? Map<String, dynamic>.from(prevRaw) : null;
    final rev = revRaw is Map ? Map<String, dynamic>.from(revRaw) : null;

    final prevCtc = yearlyCtcFromSalaryMap(prev);
    final revCtc = yearlyCtcFromSalaryMap(rev);
    final diffCtc = (prevCtc != null && revCtc != null) ? (revCtc - prevCtc) : null;
    final pctCtc = (prevCtc != null && prevCtc > 0 && diffCtc != null)
        ? (diffCtc / prevCtc) * 100
        : null;

    final eff = parseMongoJsonDate(entry['effectiveFrom']);
    final effStr = eff != null ? DateFormat('d MMM, y').format(eff) : '—';
    final payoutStr = eff != null ? DateFormat('MMM yyyy').format(eff) : '—';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Salary Revision History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Export',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download is not available in the app yet.')),
              );
            },
            icon: Icon(Icons.download_outlined, color: AppColors.secondary),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryGrid(
            currency: currency,
            prevCtc: prevCtc,
            revCtc: revCtc,
            diff: diffCtc,
            pct: pctCtc,
            effectiveStr: effStr,
            payoutStr: payoutStr,
          ),
          const SizedBox(height: 20),
          const Text(
            'Earnings & components',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          for (final key in _componentOrder) ...[
            if (_monthly(prev, key) != null || _monthly(rev, key) != null)
              _ComponentCompare(
                title: _labels[key] ?? key,
                currency: currency,
                prevAnnual: _annual(prev, key),
                revAnnual: _annual(rev, key),
              ),
          ],
        ],
      ),
    );
  }

  double? _annual(Map<String, dynamic>? m, String key) {
    final mo = _monthly(m, key);
    if (mo == null) return null;
    return mo * 12;
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.currency,
    required this.prevCtc,
    required this.revCtc,
    required this.diff,
    required this.pct,
    required this.effectiveStr,
    required this.payoutStr,
  });

  final NumberFormat currency;
  final double? prevCtc;
  final double? revCtc;
  final double? diff;
  final double? pct;
  final String effectiveStr;
  final String payoutStr;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _row2(
            'Previous CTC',
            prevCtc != null ? currency.format(prevCtc!) : '—',
            'Revised CTC',
            revCtc != null ? currency.format(revCtc!) : '—',
          ),
          const Divider(height: 20),
          _row2(
            'Difference',
            diff != null ? currency.format(diff!) : '—',
            'Change by',
            pct != null ? '${pct!.toStringAsFixed(2)}%' : '—',
            value2Color: pct != null && pct! >= 0 ? AppColors.success : AppColors.error,
            value2ArrowUp: pct != null && pct! > 0,
            value2ArrowDown: pct != null && pct! < 0,
          ),
          const Divider(height: 20),
          _row2(
            'Effective From',
            effectiveStr,
            'Payout Month',
            payoutStr,
          ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Status',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Approved',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row2(
    String l1,
    String v1,
    String l2,
    String v2, {
    Color? value2Color,
    bool value2ArrowUp = false,
    bool value2ArrowDown = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _cell(l1, v1)),
        Expanded(child: _cell(l2, v2, color: value2Color, up: value2ArrowUp, down: value2ArrowDown)),
      ],
    );
  }

  Widget _cell(String label, String value, {Color? color, bool up = false, bool down = false}) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (up)
                Icon(Icons.arrow_upward, size: 16, color: color ?? AppColors.textPrimary),
              if (down)
                Icon(Icons.arrow_downward, size: 16, color: color ?? AppColors.textPrimary),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color ?? AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComponentCompare extends StatelessWidget {
  const _ComponentCompare({
    required this.title,
    required this.currency,
    required this.prevAnnual,
    required this.revAnnual,
  });

  final String title;
  final NumberFormat currency;
  final double? prevAnnual;
  final double? revAnnual;

  @override
  Widget build(BuildContext context) {
    final p = prevAnnual ?? 0;
    final r = revAnnual ?? 0;
    final diff = r - p;
    final pct = p != 0 ? (diff / p) * 100 : (diff == 0 ? 0.0 : null);

    Color pctColor = AppColors.textPrimary;
    bool up = false;
    bool down = false;
    if (pct != null) {
      if (pct > 0) {
        pctColor = AppColors.success;
        up = true;
      } else if (pct < 0) {
        pctColor = AppColors.error;
        down = true;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _mini('Previous Amount', currency.format(p)),
              ),
              Expanded(
                child: _mini('Revised Amount', currency.format(r)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _miniPct(
                  'Changed by',
                  pct != null ? '${pct.toStringAsFixed(2)} %' : '—',
                  pctColor,
                  up,
                  down,
                ),
              ),
              Expanded(
                child: _mini('Difference', currency.format(diff)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _miniPct(
    String label,
    String value,
    Color color,
    bool up,
    bool down,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Row(
          children: [
            if (up) Icon(Icons.arrow_upward, size: 14, color: color),
            if (down) Icon(Icons.arrow_downward, size: 14, color: color),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
