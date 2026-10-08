// Salary Structure tab of the admin Staff Detail screen
// (web: salary/structure/pages/Detailstructure.tsx and its components).
// Shows the structure in effect, lets the admin apply a salary template, add or
// revise the structure, and lists the revision history.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../config/app_colors.dart';
import '../../../../../config/app_text_styles.dart';
import '../../../../../services/admin_staff_detail_service.dart';
import '../staff_detail_common.dart';

class StaffSalaryStructureTab extends StatefulWidget {
  const StaffSalaryStructureTab({super.key, required this.staff, required this.onStaffUpdated});

  final Map<String, dynamic> staff;
  final ValueChanged<Map<String, dynamic>> onStaffUpdated;

  @override
  State<StaffSalaryStructureTab> createState() => _StaffSalaryStructureTabState();
}

class _StaffSalaryStructureTabState extends State<StaffSalaryStructureTab> {
  final _service = AdminStaffDetailService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _structure;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _templates = [];
  bool _showHistory = false;
  bool _busy = false;

  String get _staffId => sdId(widget.staff);
  String get _templateId => sdId(widget.staff['salaryTemplate']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getSalaryStructure(_staffId),
        _service.getSalaryTemplates(),
      ]);
      if (!mounted) return;
      final data = results[0] as Map<String, dynamic>;
      setState(() {
        _structure = data['structure'] is Map ? Map<String, dynamic>.from(data['structure']) : null;
        _history = ((data['history'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _templates = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sdErrorText(e);
        _loading = false;
      });
    }
  }

  String _templateTitle(String id) {
    final t = _templates.firstWhere((t) => sdId(t) == id, orElse: () => const {});
    return sdStr(t['title'] ?? t['name']);
  }

  /// The structure to display: the one in effect, else the latest future-dated one.
  Map<String, dynamic>? get _shown => _structure ?? (_history.isNotEmpty ? _history.first : null);

  Future<void> _applyTemplate() async {
    if (_templates.isEmpty) {
      sdShowError(context, StaffDetailApiException('No salary templates found. Create one in Salary settings.'));
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Apply Salary Template', style: AppTextStyles.headingMedium),
            ),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final t in _templates)
                ListTile(
                  title: Text(sdStr(t['title'] ?? t['name'], 'Template'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('${sdNum(t['assignedStaff']).toInt()} staff assigned',
                      style: AppTextStyles.caption.copyWith(color: kSdMuted)),
                  trailing: sdId(t) == _templateId ? const Icon(Icons.check_circle_rounded, color: AppColors.success) : null,
                  onTap: () => Navigator.pop(ctx, sdId(t)),
                ),
            ]),
          ),
        ]),
      ),
    );
    if (chosen == null || chosen == _templateId) return;
    setState(() => _busy = true);
    try {
      final updated = await _service.updateStaff(_staffId, {'salaryTemplate': chosen});
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onStaffUpdated(updated.isEmpty ? {'salaryTemplate': chosen} : updated);
      sdShowSuccess(context, 'Salary template applied.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      sdShowError(context, e);
    }
  }

  Future<void> _openEditor() async {
    final isAdd = _shown == null;
    if (_templateId.isEmpty) {
      sdShowError(context, StaffDetailApiException('Assign a salary template before creating a salary structure.'));
      return;
    }
    final joining = sdDate(widget.staff['joiningDate']) ?? sdDate(widget.staff['startDate']);
    final current = _shown;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _StructureEditor(
        staffId: _staffId,
        isAdd: isAdd,
        templateId: _templateId,
        templateTitle: _templateTitle(_templateId),
        joining: joining,
        currentBasic: current == null ? 0 : _monthly(current['basicSalary']),
      ),
    );
    if (saved == true) _load();
  }

  double _monthly(dynamic v) => v is Map ? sdNum(v['month'] ?? v['monthly']) : sdNum(v);
  double _yearly(dynamic v) => v is Map ? sdNum(v['year'] ?? v['yearly']) : sdNum(v) * 12;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_loading)
            const SdLoading()
          else if (_error != null)
            SdErrorView(message: _error!, onRetry: _load)
          else ...[
            _buildTemplateCard(),
            if (_shown == null)
              const SdEmptyView(
                message: 'No Salary Structure Defined',
                detail: 'Add a salary structure to start payroll for this staff member.',
                icon: Icons.account_balance_wallet_outlined,
              )
            else
              ..._buildStructure(_shown!),
            const SizedBox(height: 4),
            _buildHistory(),
          ],
        ],
      ),
    );
  }

  Widget _buildTemplateCard() {
    final title = _templateTitle(_templateId);
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SdSectionTitle('Salary Template', icon: Icons.description_outlined),
          Text(
            _templateId.isEmpty ? 'No salary template assigned' : (title.isEmpty ? 'Assigned template' : title),
            style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _applyTemplate,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(_templateId.isEmpty ? 'Apply Template' : 'Change Template'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _openEditor,
                icon: Icon(_shown == null ? Icons.add_rounded : Icons.edit_outlined, size: 18),
                label: Text(_shown == null ? 'Add Salary' : 'Revise Salary'),
                style: sdPrimaryButton(),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  List<Widget> _buildStructure(Map<String, dynamic> s) {
    final effective = sdDate(s['effectiveFrom']);
    final isFuture = _structure == null;
    Widget group(String title, dynamic map) {
      if (map is! Map || map.isEmpty) return const SizedBox.shrink();
      final entries = map.entries.where((e) => e.value is Map).toList();
      if (entries.isEmpty) return const SizedBox.shrink();
      return SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SdSectionTitle(title),
            const Row(children: [
              Expanded(child: Text('Component', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: kSdMuted))),
              SizedBox(width: 95, child: Text('Monthly', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: kSdMuted))),
              SizedBox(width: 95, child: Text('Yearly', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: kSdMuted))),
            ]),
            for (final e in entries) _row(_label(e.key.toString()), _monthly(e.value), _yearly(e.value)),
          ],
        ),
      );
    }

    return [
      SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SdSectionTitle('Salary Structure',
                icon: Icons.payments_outlined,
                trailing: isFuture
                    ? const SdPill('Upcoming', color: AppColors.info, bg: AppColors.infoBg)
                    : const SdPill('Active', color: AppColors.success, bg: AppColors.successBg)),
            SdKeyValue('Effective From', effective == null ? '-' : DateFormat('MMM yyyy').format(effective)),
            SdKeyValue('Basic Salary', '${sdMoney(_monthly(s['basicSalary']))} / month'),
            SdKeyValue('Gross Salary', '${sdMoney(_monthly(s['grossSalary']))} / month'),
            SdKeyValue('Net Salary', '${sdMoney(_monthly(s['netSalary']))} / month'),
            SdKeyValue('Total CTC', '${sdMoney(s['totalCTC'])} / year'),
            if (sdStr(s['note']).isNotEmpty) SdKeyValue('Note', sdStr(s['note'])),
          ],
        ),
      ),
      group('Earnings', s['Earnings']),
      group('Allowances', s['Allowances']),
      group('Variables', s['Variables']),
      group('Benefits', s['Benefits']),
      group('Deductions', s['deductions']),
    ];
  }

  String _label(String key) {
    final spaced = key.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}').replaceAll('_', ' ');
    return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
  }

  Widget _row(String label, double m, double y) {
    const st = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: kSdInk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: st)),
        SizedBox(width: 95, child: Text(sdMoney(m), textAlign: TextAlign.right, style: st)),
        SizedBox(width: 95, child: Text(sdMoney(y), textAlign: TextAlign.right, style: st)),
      ]),
    );
  }

  Widget _buildHistory() {
    final all = [if (_structure != null) _structure!, ..._history];
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showHistory = !_showHistory),
            child: SdSectionTitle('Revision History (${all.length})',
                icon: Icons.history_rounded,
                trailing: Icon(_showHistory ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: kSdMuted)),
          ),
          if (_showHistory) ...[
            if (all.isEmpty) const Text('No revisions yet', style: AppTextStyles.bodySmall),
            for (final h in all)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSdBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kSdHairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('Effective ${sdFmtDate(h['effectiveFrom'], 'MMM yyyy')}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kSdInk)),
                      ),
                      if (identical(h, _structure)) const SdPill('Current', color: AppColors.success, bg: AppColors.successBg),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Basic ${sdMoney(_monthly(h['basicSalary']))}  ·  Previous ${sdMoney(h['previousSalary'])}',
                      style: AppTextStyles.caption.copyWith(color: kSdMuted),
                    ),
                    if (sdStr(h['note']).isNotEmpty)
                      Text(sdStr(h['note']), style: const TextStyle(fontSize: 12, color: kSdInk)),
                    Text(
                      'Revised ${sdFmtDate(h['revisedAt'])}${h['revisedBy'] is Map && sdStr((h['revisedBy'] as Map)['name']).isNotEmpty ? ' by ${(h['revisedBy'] as Map)['name']}' : ''}',
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5, color: kSdSubtle),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StructureEditor extends StatefulWidget {
  const _StructureEditor({
    required this.staffId,
    required this.isAdd,
    required this.templateId,
    required this.templateTitle,
    required this.joining,
    required this.currentBasic,
  });

  final String staffId;
  final bool isAdd;
  final String templateId;
  final String templateTitle;
  final DateTime? joining;
  final double currentBasic;

  @override
  State<_StructureEditor> createState() => _StructureEditorState();
}

class _StructureEditorState extends State<_StructureEditor> {
  final _service = AdminStaffDetailService();
  late final TextEditingController _basic;
  final _notes = TextEditingController();
  late DateTime _effective;
  bool _pf = true;
  bool _esi = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _basic = TextEditingController(text: widget.currentBasic > 0 ? widget.currentBasic.toStringAsFixed(0) : '');
    final now = DateTime.now();
    _effective = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _basic.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime? get _minMonth => widget.joining == null ? null : DateTime(widget.joining!.year, widget.joining!.month);

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = <DateTime>[];
    var c = DateTime(now.year, now.month + 12);
    final min = _minMonth ?? DateTime(now.year - 2, now.month);
    while (!c.isBefore(min)) {
      months.add(c);
      c = DateTime(c.year, c.month - 1);
    }
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final m in months)
            ListTile(
              title: Text(DateFormat('MMMM yyyy').format(m)),
              trailing: m == _effective ? const Icon(Icons.check_rounded, color: AppColors.success) : null,
              onTap: () => Navigator.pop(ctx, m),
            ),
        ]),
      ),
    );
    if (picked != null) setState(() => _effective = picked);
  }

  Future<void> _save() async {
    final basic = double.tryParse(_basic.text.trim());
    if (basic == null || basic <= 0) {
      sdShowError(context, StaffDetailApiException('Basic salary must be a number greater than 0.'));
      return;
    }
    if (!widget.isAdd && _notes.text.trim().isEmpty) {
      sdShowError(context, StaffDetailApiException('Notes are required.'));
      return;
    }
    final min = _minMonth;
    if (!widget.isAdd && min != null && _effective.isBefore(min)) {
      sdShowError(context,
          StaffDetailApiException('Effective Month cannot be before the joining month (${DateFormat('MMMM yyyy').format(min)}).'));
      return;
    }
    // A first structure runs from the joining date itself; a revision from the chosen month.
    final effectiveFrom = widget.isAdd
        ? (widget.joining ?? DateTime.now())
        : _effective;

    setState(() => _saving = true);
    try {
      await _service.saveSalaryStructure({
        'staffId': widget.staffId,
        'basicSalary': basic,
        'salaryTemplateId': widget.templateId,
        'effectiveFrom': effectiveFrom.toUtc().toIso8601String(),
        'note': _notes.text.trim().isEmpty ? 'Initial salary structure' : _notes.text.trim(),
        'hasPF': _pf,
        'hasESI': _esi,
        'overrides': <String, dynamic>{},
        'previousSalary': widget.currentBasic,
      });
      if (!mounted) return;
      sdShowSuccess(context, 'Salary structure updated successfully');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      sdShowError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.isAdd ? 'Add Salary Structure' : 'Revise Salary',
                  style: AppTextStyles.headingMedium),
              const SizedBox(height: 4),
              Text('Template: ${widget.templateTitle.isEmpty ? 'Assigned template' : widget.templateTitle}',
                  style: AppTextStyles.bodySmall),
              if (!widget.isAdd)
                Text('Current basic: ${sdMoney(widget.currentBasic)}',
                    style: AppTextStyles.bodySmall),
              const SizedBox(height: 16),
              TextField(
                controller: _basic,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: sdInput(widget.isAdd ? 'Basic Salary (monthly)' : 'New Basic Salary (monthly)'),
              ),
              const SizedBox(height: 12),
              if (!widget.isAdd) ...[
                InkWell(
                  onTap: _pickMonth,
                  child: InputDecorator(
                    decoration: sdInput('Effective Month'),
                    child: Text(DateFormat('MMMM yyyy').format(_effective), style: const TextStyle(fontSize: 13.5)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: sdInput(widget.isAdd ? 'Notes (optional)' : 'Notes (reason for revision)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _pf,
                onChanged: (v) => setState(() => _pf = v),
                title: const Text('Provident Fund (PF)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _esi,
                onChanged: (v) => setState(() => _esi = v),
                title: const Text('ESI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: sdPrimaryButton(),
                  child: _saving
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
