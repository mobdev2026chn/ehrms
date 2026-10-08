// One employee's salary structure: the structure in effect, its revision history, and
// Add / Revise Salary.
//   GET  /admin/staff/:id                              - joining date and assigned template
//   GET  /admin/staff/salary-structures/staff/:staffId - { structure, history }
//   GET  /admin/staff/salary-templates                 - templates to apply
//   POST /admin/staff/salary-structures                - saves a new revision

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_salary_service.dart';
import '../../../utils/snackbar_utils.dart';
import 'admin_salary_ui.dart';

class AdminSalaryStructureDetailScreen extends StatefulWidget {
  final String staffId;
  final String staffName;
  const AdminSalaryStructureDetailScreen({super.key, required this.staffId, required this.staffName});

  @override
  State<AdminSalaryStructureDetailScreen> createState() => _AdminSalaryStructureDetailScreenState();
}

class _AdminSalaryStructureDetailScreenState extends State<AdminSalaryStructureDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _staff = {};
  Map<String, dynamic>? _structure;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _templates = [];
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final svc = AdminSalaryService.instance;
    final results = await Future.wait([
      svc.getStaffDetail(widget.staffId),
      svc.getSalaryStructure(widget.staffId),
      svc.getSalaryTemplates(),
    ]);
    if (!mounted) return;
    final failed = results.firstWhere((r) => r['success'] != true, orElse: () => const {});
    setState(() {
      _loading = false;
      if (failed.isNotEmpty) {
        _error = failed['message']?.toString() ?? 'Could not load the salary structure.';
        return;
      }
      _error = null;
      _staff = Map<String, dynamic>.from(results[0]['data'] as Map);
      final s = Map<String, dynamic>.from(results[1]['data'] as Map);
      _structure = s['structure'] is Map ? Map<String, dynamic>.from(s['structure'] as Map) : null;
      _history = (s['history'] is List)
          ? (s['history'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
      _templates = List<Map<String, dynamic>>.from(results[2]['data'] as List);
    });
  }

  String get _assignedTemplateId {
    final t = _staff['salaryTemplate'];
    if (t is Map) return (t['_id'] ?? '').toString();
    return (t ?? '').toString();
  }

  Map<String, dynamic>? get _assignedTemplate {
    final id = _assignedTemplateId;
    if (id.isEmpty) return null;
    for (final t in _templates) {
      if (t['_id'] == id || t['title'] == id) return t;
    }
    return null;
  }

  /// Joining date, or the intern start date standing in for one.
  String get _joiningDate => (_staff['joiningDate'] ?? _staff['internStartDate'] ?? '').toString();

  double get _currentBasic {
    final b = _structure?['basicSalary'];
    if (b is Map) return AdminUi.toDouble(b['month']);
    return AdminUi.toDouble(b);
  }

  /// The structure the Structure tab shows: the one in effect, else the earliest still to come.
  Map<String, dynamic>? get _shown => _structure ?? (_history.isNotEmpty ? _history.last : null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.bg,
      appBar: AdminUi.appBar(widget.staffName, actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
      ]),
      body: _loading
          ? const AdminLoading()
          : _error != null
              ? AdminErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => _load(showLoader: false),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: _body(),
                  ),
                ),
    );
  }

  List<Widget> _body() {
    final tpl = _assignedTemplate;
    if (tpl == null) {
      return [
        _headerCard(null),
        const SizedBox(height: 16),
        const AdminEmptyView(
          icon: Icons.description_outlined,
          title: 'No salary template assigned',
          subtitle:
              'Assign a salary template to this employee under Profile > Policy & Template Configurations to add their salary.',
        ),
      ];
    }
    return [
      _headerCard(tpl),
      const SizedBox(height: 16),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('Structure'), icon: Icon(Icons.account_tree_outlined, size: 16)),
          ButtonSegment(value: 1, label: Text('Revision History'), icon: Icon(Icons.history_rounded, size: 16)),
        ],
        selected: {_tab},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: AppColors.onPrimary,
          backgroundColor: AppColors.surface,
          foregroundColor: AdminUi.muted,
          side: const BorderSide(color: Color(0xFFE2E5EA)),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onSelectionChanged: (s) => setState(() => _tab = s.first),
      ),
      const SizedBox(height: 16),
      if (_tab == 0) ..._structureView() else ..._historyView(),
    ];
  }

  Widget _headerCard(Map<String, dynamic>? tpl) {
    final hasSalary = _currentBasic > 0;
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AdminAvatar(widget.staffName, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.staffName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AdminUi.ink)),
              const SizedBox(height: 2),
              Text(
                [_staff['employeeId'], _staff['designation'], _staff['department']]
                    .where((v) => v != null && v.toString().isNotEmpty)
                    .join(' • '),
                style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        if (tpl != null)
          InkWell(
            onTap: () => _showTemplate(tpl),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.description_outlined, size: 16, color: AppColors.primaryText),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Template: ${tpl['title'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primaryText)),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primaryText),
              ]),
            ),
          )
        else
          const AdminPill('No Salary Template Assigned', fg: AdminUi.amber, bg: AdminUi.amberBg),
        if (tpl != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: AdminUi.primaryButton(),
              onPressed: _openRevise,
              icon: Icon(hasSalary ? Icons.edit_note_rounded : Icons.add_rounded, size: 18),
              label: Text(hasSalary ? 'Revise Salary' : 'Add Salary'),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Structure ─────────────────────────────────────────────────────────

  List<Widget> _structureView() {
    final s = _shown;
    if (s == null) {
      return const [
        AdminEmptyView(
          icon: Icons.account_balance_wallet_outlined,
          title: 'No salary structure defined',
          subtitle: 'Use Add Salary to set this employee’s salary.',
        ),
      ];
    }
    final upcoming = _structure == null;
    return [
      if (upcoming)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AdminPill('Takes effect in a future month', fg: AdminUi.blue, bg: AdminUi.blueBg),
          ),
        ),
      _summaryCard(s),
      const SizedBox(height: 16),
      ..._componentCards(s),
    ];
  }

  static double _monthOf(dynamic v) => v is Map ? AdminUi.toDouble(v['month']) : AdminUi.toDouble(v);
  static double _yearOf(dynamic v) => v is Map ? AdminUi.toDouble(v['year']) : AdminUi.toDouble(v) * 12;

  Widget _summaryCard(Map<String, dynamic> s) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.event_outlined, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('Effective from ${AdminUi.date(s['effectiveFrom'])}',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 16),
          const Text('Annual CTC', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(AdminUi.money(AdminUi.toDouble(s['totalCTC'])),
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: 14),
          Row(children: [
            _darkFigure('Basic / month', AdminUi.money(_monthOf(s['basicSalary']))),
            _darkFigure('Gross / month', AdminUi.money(_monthOf(s['grossSalary']))),
            _darkFigure('Net / month', AdminUi.money(_monthOf(s['netSalary']))),
          ]),
        ]),
      );

  Widget _darkFigure(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ]),
      );

  List<Widget> _componentCards(Map<String, dynamic> s) {
    final sections = <(String, String)>[
      ('Earnings', 'Earnings'),
      ('Allowances', 'Allowances'),
      ('Variables', 'Variables'),
      ('Benefits', 'Benefits'),
      ('Deductions', 'deductions'),
    ];
    final out = <Widget>[];
    for (final (title, key) in sections) {
      final m = s[key];
      if (m is! Map || m.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink)),
            const SizedBox(height: 12),
            const Row(children: [
              Expanded(
                  flex: 5,
                  child: Text('Component',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: AdminUi.muted))),
              Expanded(
                  flex: 3,
                  child: Text('Monthly',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: AdminUi.muted))),
              Expanded(
                  flex: 3,
                  child: Text('Yearly',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: AdminUi.muted))),
            ]),
            const Divider(height: 20),
            ...m.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                        flex: 5, child: Text(e.key.toString(), style: const TextStyle(fontSize: 13.5, color: AdminUi.ink))),
                    Expanded(
                        flex: 3,
                        child: Text(AdminUi.money(_monthOf(e.value)),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: key == 'deductions' ? AdminUi.red : AdminUi.ink))),
                    Expanded(
                        flex: 3,
                        child: Text(AdminUi.money(_yearOf(e.value)),
                            textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: AdminUi.muted))),
                  ]),
                )),
          ]),
        ),
      ));
    }
    return out;
  }

  // ── History ───────────────────────────────────────────────────────────

  List<Widget> _historyView() {
    final all = [if (_structure != null) _structure!, ..._history];
    if (all.isEmpty) {
      return const [AdminEmptyView(icon: Icons.history_rounded, title: 'No revisions yet')];
    }
    return all.map((s) {
      final active = identical(s, _structure);
      final prev = AdminUi.toDouble(s['previousSalary']);
      final basic = _monthOf(s['basicSalary']);
      final revisedBy = s['revisedBy'] is Map ? (s['revisedBy']['name'] ?? '').toString() : '';
      final change = prev > 0 ? ((basic - prev) / prev * 100) : null;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AdminCard(
          padding: EdgeInsets.zero,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              iconColor: AdminUi.muted,
              collapsedIconColor: AdminUi.muted,
              leading: AdminIconTile(Icons.history_rounded, color: active ? AdminUi.green : null),
              title: Row(children: [
                Expanded(
                  child: Text('From ${AdminUi.date(s['effectiveFrom'])}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: AdminUi.ink)),
                ),
                if (active) const AdminPill('Active', fg: AdminUi.green, bg: AdminUi.greenBg),
              ]),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Basic ${AdminUi.money(basic)}'
                  '${prev > 0 ? '  (was ${AdminUi.money(prev)}${change != null ? ', ${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%' : ''})' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                ),
              ),
              children: [
                _kv('Gross / month', AdminUi.money(_monthOf(s['grossSalary']))),
                _kv('Net / month', AdminUi.money(_monthOf(s['netSalary']))),
                _kv('Annual CTC', AdminUi.money(AdminUi.toDouble(s['totalCTC']))),
                if ((s['note'] ?? '').toString().isNotEmpty) _kv('Note', s['note'].toString()),
                if (revisedBy.isNotEmpty) _kv('Revised by', revisedBy),
                _kv('Revised on', AdminUi.date(s['revisedAt'] ?? s['createdAt'])),
                const SizedBox(height: 8),
                ..._componentCards(s),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontSize: 12.5, color: AdminUi.muted))),
          Expanded(
              child: Text(v, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.ink))),
        ]),
      );

  // ── Template breakdown ────────────────────────────────────────────────

  void _showTemplate(Map<String, dynamic> t) {
    String fmt(Map c) => c['type'] == 'Percentage' ? '${c['amount']}%' : AdminUi.money(AdminUi.toDouble(c['amount']));
    final pd = t['payableDays'];
    final rule = pd is Map ? (pd['name'] ?? pd['type'] ?? 'Standard calendar').toString() : 'Standard calendar';
    Widget group(String title, dynamic items) {
      final list = items is List ? items.whereType<Map>().toList() : <Map>[];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: AdminUi.ink)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AdminUi.bg, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('None', style: TextStyle(fontSize: 13, color: AdminUi.muted)),
                )
              else
                ...list.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Expanded(
                            child: Text((c['name'] ?? '').toString(),
                                style: const TextStyle(fontSize: 13.5, color: AdminUi.ink))),
                        Text(fmt(c),
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.ink)),
                      ]),
                    )),
            ]),
          ),
        ]),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: const Color(0xFFE2E5EA), borderRadius: BorderRadius.circular(999)),
              ),
            ),
            Text((t['title'] ?? '').toString(),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
            const SizedBox(height: 4),
            Text('Payable days: $rule', style: const TextStyle(fontSize: 13, color: AdminUi.muted)),
            const SizedBox(height: 20),
            group('Earnings', t['earnings']),
            group('Variables', t['variables']),
            group('Benefits', t['benefits']),
            group('Allowances', t['allowances']),
          ],
        ),
      ),
    );
  }

  // ── Add / Revise ──────────────────────────────────────────────────────

  Future<void> _openRevise() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ReviseSalarySheet(
        staffId: widget.staffId,
        currentBasic: _currentBasic,
        joiningDate: _joiningDate,
        templates: _templates,
        assignedTemplateId: _assignedTemplate?['_id']?.toString() ?? '',
      ),
    );
    if (saved == true && mounted) _load(showLoader: false);
  }
}

class _ReviseSalarySheet extends StatefulWidget {
  final String staffId;
  final double currentBasic;
  final String joiningDate;
  final List<Map<String, dynamic>> templates;
  final String assignedTemplateId;

  const _ReviseSalarySheet({
    required this.staffId,
    required this.currentBasic,
    required this.joiningDate,
    required this.templates,
    required this.assignedTemplateId,
  });

  @override
  State<_ReviseSalarySheet> createState() => _ReviseSalarySheetState();
}

class _ReviseSalarySheetState extends State<_ReviseSalarySheet> {
  late final TextEditingController _basic;
  final _notes = TextEditingController();
  late String _templateId;
  DateTime? _effectiveMonth;
  bool _pf = true;
  bool _esi = true;
  bool _saving = false;

  bool get _isAdd => widget.currentBasic <= 0;

  /// The joining month: salary cannot take effect before it.
  DateTime? get _minMonth {
    final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(widget.joiningDate);
    if (m != null) return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), 1);
    final d = DateTime.tryParse(widget.joiningDate);
    return d == null ? null : DateTime(d.year, d.month, 1);
  }

  @override
  void initState() {
    super.initState();
    _basic = TextEditingController(text: _isAdd ? '' : widget.currentBasic.round().toString());
    _templateId = widget.assignedTemplateId.isNotEmpty
        ? widget.assignedTemplateId
        : (widget.templates.isNotEmpty ? (widget.templates.first['_id'] ?? '').toString() : '');
    _effectiveMonth = _minMonth;
  }

  @override
  void dispose() {
    _basic.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final first = _minMonth ?? DateTime(now.year - 5, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveMonth != null && !_effectiveMonth!.isBefore(first) ? _effectiveMonth! : first,
      firstDate: first,
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Effective month (any day in it)',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _effectiveMonth = DateTime(picked.year, picked.month, 1));
  }

  Future<void> _submit() async {
    final basic = double.tryParse(_basic.text.trim());
    String? problem;
    if (_templateId.isEmpty) {
      problem = 'A salary template is required to save the salary structure.';
    } else if (basic == null) {
      problem = 'Basic Salary is required.';
    } else if (basic <= 0) {
      problem = 'Basic Salary must be greater than 0.';
    } else if (!_isAdd && _effectiveMonth == null) {
      problem = 'Effective Month is required.';
    } else if (_effectiveMonth != null && _minMonth != null && _effectiveMonth!.isBefore(_minMonth!)) {
      problem = 'Effective Month cannot be before the joining month (${AdminUi.monthLabel(_minMonth!)}).';
    } else if (!_isAdd && _notes.text.trim().isEmpty) {
      problem = 'Notes are required.';
    }
    if (problem != null) {
      SnackBarUtils.showSnackBar(context, problem, isError: true);
      return;
    }

    // A first structure runs from the joining date itself; a revision from the month picked.
    String effectiveFrom;
    if (!_isAdd) {
      effectiveFrom = DateTime.utc(_effectiveMonth!.year, _effectiveMonth!.month, 1).toIso8601String();
    } else {
      final joined = DateTime.tryParse(widget.joiningDate);
      effectiveFrom = (joined ?? DateTime.now()).toUtc().toIso8601String();
    }

    setState(() => _saving = true);
    final r = await AdminSalaryService.instance.saveSalaryStructure({
      'staffId': widget.staffId,
      'basicSalary': basic,
      'salaryTemplateId': _templateId,
      'effectiveFrom': effectiveFrom,
      'note': _notes.text.trim().isEmpty ? 'Initial salary structure' : _notes.text.trim(),
      'hasPF': _pf,
      'hasESI': _esi,
      'overrides': <String, dynamic>{},
      'previousSalary': widget.currentBasic,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, _isAdd ? 'Salary added successfully.' : 'Salary revised successfully.');
      Navigator.pop(context, true);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Failed to save salary structure.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: const Color(0xFFE2E5EA), borderRadius: BorderRadius.circular(999)),
              ),
            ),
            Text(_isAdd ? 'Add Salary' : 'Revise Salary',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
            if (!_isAdd) ...[
              const SizedBox(height: 4),
              Text('Current basic: ${AdminUi.money(widget.currentBasic)} / month',
                  style: const TextStyle(fontSize: 13, color: AdminUi.muted)),
            ],
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: widget.templates.any((t) => t['_id'] == _templateId) ? _templateId : null,
              isExpanded: true,
              decoration: AdminUi.input('Salary template',
                  helper: _templateId != widget.assignedTemplateId && widget.assignedTemplateId.isNotEmpty
                      ? 'Differs from the template assigned on the staff profile.'
                      : null),
              items: widget.templates
                  .map((t) => DropdownMenuItem(
                        value: (t['_id'] ?? '').toString(),
                        child: Text((t['title'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _templateId = v ?? ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _basic,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              decoration: AdminUi.input('Basic Salary (monthly)', prefix: '₹ ', hint: 'e.g. 60000'),
            ),
            if (!_isAdd) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickMonth,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: AdminUi.input('Effective Month',
                      helper: _minMonth != null ? 'From ${AdminUi.monthLabel(_minMonth!)} onwards (joining month)' : null),
                  child: Row(children: [
                    Expanded(child: Text(_effectiveMonth != null ? AdminUi.monthLabel(_effectiveMonth!) : 'Select month')),
                    const Icon(Icons.calendar_month_outlined, size: 20, color: AdminUi.muted),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: AdminUi.input(_isAdd ? 'Notes (optional)' : 'Notes', hint: 'Reason for this change'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: AdminUi.bg, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _pf,
                  title: const Text('Provident Fund (PF)',
                      style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: AdminUi.ink)),
                  onChanged: (v) => setState(() => _pf = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _esi,
                  title: const Text('Employees’ State Insurance (ESI)',
                      style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: AdminUi.ink)),
                  onChanged: (v) => setState(() => _esi = v),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : Text(_isAdd ? 'Add Salary' : 'Save Revision'),
            ),
          ]),
        ),
      ),
    );
  }
}
