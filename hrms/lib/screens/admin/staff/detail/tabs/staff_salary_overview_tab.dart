// Salary Overview tab of the admin Staff Detail screen
// (web: salary/overview/pages/overviewDetails.tsx).
// One salary month at a time: attendance figures, earnings and deductions,
// manual breakdown edits and payroll generation.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../config/app_colors.dart';
import '../../../../../config/app_text_styles.dart';
import '../../../../../services/admin_staff_detail_service.dart';
import '../staff_detail_common.dart';

class StaffSalaryOverviewTab extends StatefulWidget {
  const StaffSalaryOverviewTab({super.key, required this.staff});

  final Map<String, dynamic> staff;

  @override
  State<StaffSalaryOverviewTab> createState() => _StaffSalaryOverviewTabState();
}

class _StaffSalaryOverviewTabState extends State<StaffSalaryOverviewTab> {
  final _service = AdminStaffDetailService();

  late List<String> _months;
  late String _month;
  bool _loading = true;
  String? _error;
  bool _noStructure = false;
  Map<String, dynamic> _detail = {};

  bool _editing = false;
  bool _saving = false;
  bool _generating = false;
  final List<(String, double, TextEditingController)> _earnEdits = [];
  final List<(TextEditingController, TextEditingController)> _dedEdits = [];

  String get _staffId => sdId(widget.staff);

  @override
  void initState() {
    super.initState();
    _months = _monthLabels();
    _month = _months.first;
    _load();
  }

  @override
  void dispose() {
    _clearEdits();
    super.dispose();
  }

  /// Salary months from the joining month (intern start for interns) to now, newest first.
  List<String> _monthLabels() {
    final now = DateTime.now();
    final start = sdDate(widget.staff['joiningDate']) ?? sdDate(widget.staff['startDate']) ?? now;
    var cursor = DateTime(now.year, now.month);
    final first = DateTime(start.year, start.month);
    final out = <String>[];
    while (!cursor.isBefore(first) && out.length < 60) {
      out.add(DateFormat('MMMM yyyy').format(cursor));
      cursor = DateTime(cursor.year, cursor.month - 1);
    }
    if (out.isEmpty) out.add(DateFormat('MMMM yyyy').format(now));
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _noStructure = false;
      _editing = false;
    });
    try {
      final d = await _service.getSalaryOverview(_staffId, _month);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } on StaffDetailApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.statusCode == 404) {
          _noStructure = true;
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = sdErrorText(e);
      });
    }
  }

  List<Map<String, dynamic>> _rows(String key) =>
      ((_detail[key] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  void _clearEdits() {
    for (final e in _earnEdits) {
      e.$3.dispose();
    }
    for (final d in _dedEdits) {
      d.$1.dispose();
      d.$2.dispose();
    }
    _earnEdits.clear();
    _dedEdits.clear();
  }

  void _startEdit() {
    _clearEdits();
    for (final r in _rows('earningsBreakdown')) {
      _earnEdits.add((sdStr(r['label']), sdNum(r['fixed']), TextEditingController(text: _plain(r['earned']))));
    }
    for (final r in _rows('deductionsBreakdown')) {
      _dedEdits.add((TextEditingController(text: sdStr(r['label'])), TextEditingController(text: _plain(r['value']))));
    }
    setState(() => _editing = true);
  }

  String _plain(dynamic v) {
    final n = sdNum(v);
    return n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2);
  }

  Future<void> _save() async {
    final earnings = _earnEdits
        .map((e) => {'label': e.$1, 'fixed': e.$2, 'earned': double.tryParse(e.$3.text.trim()) ?? 0})
        .toList();
    final deductions = <Map<String, dynamic>>[];
    for (final d in _dedEdits) {
      final label = d.$1.text.trim();
      if (label.isEmpty) {
        sdShowError(context, StaffDetailApiException('Every deduction needs a label.'));
        return;
      }
      deductions.add({'label': label, 'value': double.tryParse(d.$2.text.trim()) ?? 0});
    }
    final gross = earnings.fold<double>(0, (s, e) => s + (e['earned'] as double));
    final totalDed = deductions.fold<double>(0, (s, d) => s + (d['value'] as double));
    final net = (gross - totalDed).clamp(0, double.infinity);

    setState(() => _saving = true);
    try {
      final updated = await _service.updateSalaryOverview(_staffId, _month, {
        'earningsBreakdown': earnings,
        'deductionsBreakdown': deductions,
        'gross': gross,
        'net': net,
        'deductions': totalDed,
        'dueAmount': net,
      });
      if (!mounted) return;
      setState(() {
        _detail = {..._detail, ...updated};
        _saving = false;
        _editing = false;
      });
      sdShowSuccess(context, 'Salary breakdown for $_month saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      sdShowError(context, e);
    }
  }

  Future<void> _generate() async {
    final ok = await sdConfirm(context,
        title: 'Generate Payroll',
        message: 'Generate payroll for $_month from this salary overview?',
        confirmText: 'Generate');
    if (!ok) return;
    setState(() => _generating = true);
    try {
      final res = await _service.generatePayroll(_staffId, _month);
      if (!mounted) return;
      setState(() => _generating = false);
      sdShowSuccess(context, sdStr(res['message'], 'Payroll generated for $_month.'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      sdShowError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SdCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _month,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: _months
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text(m, style: AppTextStyles.headingSmall.copyWith(fontSize: 15))))
                    .toList(),
                onChanged: (m) {
                  if (m == null || m == _month) return;
                  setState(() => _month = m);
                  _load();
                },
              ),
            ),
          ),
          if (_loading)
            const SdLoading()
          else if (_error != null)
            SdErrorView(message: _error!, onRetry: _load)
          else if (_noStructure)
            const SdEmptyView(
              message: 'No Salary Structure',
              detail: 'Create a salary structure for this staff member to see the salary overview.',
              icon: Icons.account_balance_wallet_outlined,
            )
          else
            ..._buildDetail(),
        ],
      ),
    );
  }

  List<Widget> _buildDetail() {
    final d = _detail;
    final generated = d['isGenerated'] == true;
    final earnings = _rows('earningsBreakdown');
    final deductions = _rows('deductionsBreakdown');
    final fixedTotal = earnings.fold<double>(0, (s, e) => s + sdNum(e['fixed']));

    return [
      SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SdSectionTitle('Attendance · ${sdStr(d['duration'], _month)}',
                icon: Icons.event_available_outlined,
                trailing: generated
                    ? const SdPill('Payroll Generated', color: AppColors.success, bg: AppColors.successBg)
                    : null),
            SdKeyValue('Payable Days', _plain(d['payableDays'])),
            SdKeyValue('Present Days', _plain(d['presentDays'])),
            SdKeyValue('Half Days', _plain(d['halfDays'])),
            SdKeyValue('Absent Days', _plain(d['absentDays'])),
            SdKeyValue('Leaves', _plain(d['leaves'])),
            SdKeyValue('Hours Worked', sdStr(d['hoursWorked'], '0')),
            SdKeyValue('OT Hours', sdStr(d['otHours'], '0')),
            SdKeyValue('Fine Hours', sdStr(d['totalFineHours'], '0')),
          ],
        ),
      ),
      SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SdSectionTitle(
              'Earnings',
              icon: Icons.trending_up_rounded,
              trailing: _editing || generated
                  ? null
                  : TextButton.icon(
                      onPressed: _startEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit Breakdown'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primaryText, visualDensity: VisualDensity.compact),
                    ),
            ),
            if (!_editing) ...[
              const Row(children: [
                Expanded(child: Text('Component', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: kSdMuted))),
                SizedBox(width: 90, child: Text('Fixed', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: kSdMuted))),
                SizedBox(width: 90, child: Text('Earned', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: kSdMuted))),
              ]),
              const SizedBox(height: 4),
              if (earnings.isEmpty) const Text('No earnings', style: AppTextStyles.bodySmall),
              for (final e in earnings) _row3(sdStr(e['label']), sdMoney(e['fixed']), sdMoney(e['earned'])),
              const Divider(),
              _row3('Total', sdMoney(fixedTotal), sdMoney(d['gross']), bold: true),
            ] else
              for (final e in _earnEdits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: e.$3,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: sdInput('${e.$1} (fixed ${sdMoney(e.$2)})'),
                  ),
                ),
          ],
        ),
      ),
      SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SdSectionTitle(
              'Deductions',
              icon: Icons.trending_down_rounded,
              trailing: _editing
                  ? TextButton.icon(
                      onPressed: () => setState(() => _dedEdits.add((TextEditingController(), TextEditingController(text: '0')))),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add'),
                    )
                  : null,
            ),
            if (!_editing) ...[
              if (deductions.isEmpty) const Text('No deductions', style: AppTextStyles.bodySmall),
              for (final r in deductions) _row2(sdStr(r['label']), sdMoney(r['value'])),
              const Divider(),
              _row2('Total Deductions', sdMoney(d['deductions']), bold: true),
            ] else ...[
              for (var i = 0; i < _dedEdits.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(flex: 3, child: TextField(controller: _dedEdits[i].$1, decoration: sdInput('Label'))),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _dedEdits[i].$2,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: sdInput('Amount'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                      onPressed: () => setState(() {
                        final r = _dedEdits.removeAt(i);
                        r.$1.dispose();
                        r.$2.dispose();
                      }),
                    ),
                  ]),
                ),
              const Text('Loan EMI lines are recalculated by the server on save.',
                  style: TextStyle(fontSize: 12, color: kSdMuted)),
            ],
          ],
        ),
      ),
      if (_editing)
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: sdPrimaryButton(),
              child: _saving
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : const Text('Save Breakdown'),
            ),
          ),
        ])
      else ...[
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.account_balance_wallet_outlined, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Net Payable',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xB3FFFFFF))),
            ),
            Text(sdMoney(d['net']),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        ),
        if (!generated)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generate,
              style: sdPrimaryButton(),
              icon: _generating
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : const Icon(Icons.play_circle_outline_rounded, size: 20),
              label: const Text('Generate Payroll'),
            ),
          ),
      ],
    ];
  }

  Widget _row3(String a, String b, String c, {bool bold = false}) {
    final st = TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: kSdInk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(a, style: st)),
        SizedBox(width: 90, child: Text(b, textAlign: TextAlign.right, style: st)),
        SizedBox(width: 90, child: Text(c, textAlign: TextAlign.right, style: st)),
      ]),
    );
  }

  Widget _row2(String a, String b, {bool bold = false}) {
    final st = TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: kSdInk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [Expanded(child: Text(a, style: st)), Text(b, style: st)]),
    );
  }
}
