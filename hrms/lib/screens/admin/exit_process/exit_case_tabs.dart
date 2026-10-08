// Exit detail tabs, part 1: Employment (timeline), Credentials, Asset Handover, KT Handover.
// Each tab reads as values until Edit, works on a draft, and replaces the exit with the one the
// server returns after a successful save. A failed save keeps the draft so it can be retried.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/admin_exit_process_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../salary/admin_salary_ui.dart';
import 'exit_process_common.dart';

typedef ExitCaseCallback = void Function(Map<String, dynamic> exitCase);

Map<String, dynamic> _mapOf(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _listOf(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
String _s(dynamic v) => v?.toString() ?? '';

// ═══════════════════════════════ Employment ═══════════════════════════════

class ExitEmploymentTab extends StatefulWidget {
  final Map<String, dynamic> exitCase;
  final Map<String, dynamic> settings;
  final String sectionStatus;
  final ExitCaseCallback onCaseUpdated;
  const ExitEmploymentTab({
    super.key,
    required this.exitCase,
    required this.settings,
    required this.sectionStatus,
    required this.onCaseUpdated,
  });

  @override
  State<ExitEmploymentTab> createState() => _ExitEmploymentTabState();
}

class _ExitEmploymentTabState extends State<ExitEmploymentTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _draft;
  bool _saving = false;
  final _description = TextEditingController();
  final _leaveNote = TextEditingController();
  final _terminatedBy = TextEditingController();
  final _approvedBy = TextEditingController();
  final _noticeDays = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _description.dispose();
    _leaveNote.dispose();
    _terminatedBy.dispose();
    _approvedBy.dispose();
    _noticeDays.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _saved => {
        'exitType': _s(widget.exitCase['exitType']).isEmpty ? 'Resignation' : _s(widget.exitCase['exitType']),
        ..._mapOf(widget.exitCase['timeline']),
      };

  bool get _autoNotice => widget.settings['autoCalculateNoticeDates'] == true;

  void _startEdit() {
    final d = Map<String, dynamic>.from(_saved);
    _description.text = _s(d['description']);
    _leaveNote.text = _s(d['leaveNote']);
    _terminatedBy.text = _s(d['terminatedBy']);
    _approvedBy.text = _s(d['terminationApprovedBy']);
    _noticeDays.text = '${(d['noticePeriodDays'] as num?)?.toInt() ?? 0}';
    setState(() => _draft = d);
  }

  /// Applies a change the way the web form does: for a resignation with auto notice dates on,
  /// the notice window and last working day follow the resignation date and notice period.
  void _set(Map<String, dynamic> patch) {
    setState(() {
      final prev = _draft!;
      final next = {...prev, ...patch};
      final fields = ExitUi.fieldsFor(_s(next['exitType']));
      final resignation = _s(next['resignationDate']);
      if (fields.contains('noticeFrom') &&
          _autoNotice &&
          (patch.containsKey('resignationDate') || patch.containsKey('noticePeriodDays')) &&
          resignation.isNotEmpty) {
        next['noticeFrom'] = resignation;
        next['noticeTo'] = ExitUi.addDays(resignation, (next['noticePeriodDays'] as num?)?.toInt() ?? 0);
        next['lastWorkingDay'] = next['noticeTo'];
      } else if (!fields.contains('noticeFrom') &&
          patch.containsKey('resignationDate') &&
          resignation.isNotEmpty &&
          _s(prev['lastWorkingDay']).isEmpty) {
        next['lastWorkingDay'] = resignation;
      }
      _draft = next;
    });
  }

  bool _before(String a, String b) => a.isNotEmpty && b.isNotEmpty && (ExitUi.daysBetween(a, b) ?? 0) < 0;

  Future<void> _save() async {
    final d = _draft!;
    final fields = ExitUi.fieldsFor(_s(d['exitType']));
    if ((fields.contains('approvalDate') && _before(_s(d['resignationDate']), _s(d['approvalDate']))) ||
        (fields.contains('noticeTo') && _before(_s(d['noticeFrom']), _s(d['noticeTo']))) ||
        (fields.contains('resignationDate') && _before(_s(d['resignationDate']), _s(d['lastWorkingDay'])))) {
      SnackBarUtils.showSnackBar(context, 'Dates are out of order: approval, notice end and last working day cannot be before the exit date.',
          isError: true);
      return;
    }
    final body = {
      'exitType': d['exitType'],
      'resignationDate': _s(d['resignationDate']),
      'approvalDate': _s(d['approvalDate']),
      'noticePeriodDays': (d['noticePeriodDays'] as num?)?.toInt() ?? 0,
      'noticeFrom': _s(d['noticeFrom']),
      'noticeTo': _s(d['noticeTo']),
      'lastWorkingDay': _s(d['lastWorkingDay']),
      'extendByApprovedLeave': d['extendByApprovedLeave'] == true,
      'description': _description.text.trim(),
      'leaveNote': _leaveNote.text.trim(),
      'terminatedBy': _terminatedBy.text.trim(),
      'terminationApprovedBy': _approvedBy.text.trim(),
      'terminationReason': _s(d['terminationReason']).trim(),
    };
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.saveTimeline(_s(widget.exitCase['id']), body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(() => _draft = null);
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'Exit timeline saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save the exit timeline.', isError: true);
    }
  }

  String _tenure(String joining, String end) {
    final a = AdminUi.parseYmd(joining);
    final b = AdminUi.parseYmd(end);
    if (a == null || b == null || b.isBefore(a)) return '-';
    var months = (b.year - a.year) * 12 + (b.month - a.month);
    if (b.day < a.day) months -= 1;
    if (months < 0) months = 0;
    return '${months ~/ 12}y ${months % 12}m';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final staff = _mapOf(widget.exitCase['staff']);
    final t = _draft ?? _saved;
    final editing = _draft != null;
    final type = _s(t['exitType']);
    final fields = ExitUi.fieldsFor(type);
    bool shows(String f) => fields.contains(f);
    final ext = _mapOf(widget.exitCase['leaveExtension']);
    final extDays = (ext['extensionDays'] as num?)?.toInt() ?? 0;
    final today = AdminUi.ymd(DateTime.now());
    final savedLwd = _s(_saved['lastWorkingDay']);
    final tenureEnd = savedLwd.isNotEmpty && savedLwd.compareTo(today) < 0 ? savedLwd : today;

    final reasons = (widget.settings['terminationReasons'] is List)
        ? (widget.settings['terminationReasons'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final currentReason = _s(t['terminationReason']);
    if (currentReason.isNotEmpty && !reasons.contains(currentReason)) reasons.add(currentReason);
    final approverNames = _listOf(widget.settings['terminationApprovers']).map((p) => _s(p['name'])).where((n) => n.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Staff record', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink)),
            const SizedBox(height: 6),
            ExitKv('Status', _s(staff['status'])),
            ExitKv('Date of joining', AdminUi.date(staff['joiningDate'])),
            ExitKv('Tenure', _tenure(_s(staff['joiningDate']), tenureEnd)),
            ExitKv('Reporting manager', _s(staff['reportingManager'])),
            ExitKv('Employment type', _s(staff['employmentType'])),
            ExitKv('UAN', _s(staff['uanNumber'])),
            ExitKv('PF number', _s(staff['pfNumber'])),
            ExitKv('ESI number', _s(staff['esiNumber'])),
            ExitKv('PAN', _s(staff['panNumber'])),
            ExitKv('Aadhaar', _s(staff['aadhaarNumber'])),
          ]),
        ),
        const SizedBox(height: 12),
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExitEditBar(
              title: 'Exit timeline',
              status: widget.sectionStatus,
              editing: editing,
              saving: _saving,
              onEdit: _startEdit,
              onCancel: () => setState(() => _draft = null),
              onSave: _save,
            ),
            if (!editing) ...[
              ExitKv('Exit type', type),
              if (shows('resignationDate')) ExitKv(ExitUi.exitDateLabel(type), AdminUi.date(t['resignationDate'])),
              if (shows('approvalDate')) ExitKv('Approval date', AdminUi.date(t['approvalDate'])),
              if (shows('terminatedBy')) ExitKv('Terminated by', _s(t['terminatedBy'])),
              if (shows('terminationApprovedBy')) ExitKv('Approved by', _s(t['terminationApprovedBy'])),
              if (shows('terminationReason')) ExitKv('Termination reason', _s(t['terminationReason'])),
              if (shows('noticePeriodDays'))
                ExitKv('Notice period',
                    '${extDays > 0 ? ext['noticePeriodDays'] : t['noticePeriodDays'] ?? 0} days${extDays > 0 ? ' (base ${t['noticePeriodDays']} + $extDays for leave)' : ''}'),
              if (shows('noticeFrom')) ExitKv('Notice from', AdminUi.date(t['noticeFrom'])),
              if (shows('noticeTo'))
                ExitKv('Notice to',
                    extDays > 0 ? '${AdminUi.date(ext['noticeTo'])} (base ${AdminUi.date(t['noticeTo'])})' : AdminUi.date(t['noticeTo'])),
              ExitKv('Last working day',
                  extDays > 0 ? '${AdminUi.date(ext['lastWorkingDay'])} (base ${AdminUi.date(t['lastWorkingDay'])})' : AdminUi.date(t['lastWorkingDay'])),
              if (shows('extendByApprovedLeave'))
                ExitKv('Extend by approved leave', t['extendByApprovedLeave'] == true ? 'Yes' : 'No'),
              if (extDays > 0) ExitKv('Leave in notice', '${ext['leaveDays']} day(s)'),
              if (shows('leaveNote')) ExitKv('Leave note', _s(t['leaveNote'])),
              ExitKv('Description', _s(t['description'])),
            ] else
              ..._editFields(t, type, shows, reasons, approverNames),
          ]),
        ),
      ],
    );
  }

  List<Widget> _editFields(
    Map<String, dynamic> t,
    String type,
    bool Function(String) shows,
    List<String> reasons,
    List<String> approverNames,
  ) {
    const gap = SizedBox(height: 12);
    return [
      DropdownButtonFormField<String>(
        initialValue: ExitUi.exitTypes.contains(type) ? type : null,
        decoration: AdminUi.input('Exit type'),
        items: ExitUi.exitTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => _set({'exitType': v ?? 'Resignation'}),
      ),
      gap,
      if (shows('resignationDate')) ...[
        ExitDateField(
            label: ExitUi.exitDateLabel(type), value: _s(t['resignationDate']), onChanged: (v) => _set({'resignationDate': v})),
        gap,
      ],
      if (shows('approvalDate')) ...[
        ExitDateField(
          label: 'Approval date',
          value: _s(t['approvalDate']),
          firstDate: _s(t['resignationDate']).isEmpty ? null : _s(t['resignationDate']),
          onChanged: (v) => _set({'approvalDate': v}),
        ),
        gap,
      ],
      if (shows('terminatedBy')) ...[
        TextField(controller: _terminatedBy, maxLength: 120, decoration: AdminUi.input('Terminated by')),
        gap,
      ],
      if (shows('terminationApprovedBy')) ...[
        TextField(controller: _approvedBy, maxLength: 120, decoration: AdminUi.input('Approved by')),
        if (approverNames.isNotEmpty)
          Wrap(
            spacing: 6,
            children: approverNames
                .map((n) => ActionChip(
                      label: Text(n, style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => _approvedBy.text = n),
                    ))
                .toList(),
          ),
        gap,
      ],
      if (shows('terminationReason')) ...[
        DropdownButtonFormField<String>(
          initialValue: _s(t['terminationReason']).isEmpty ? null : _s(t['terminationReason']),
          isExpanded: true,
          decoration: AdminUi.input('Termination reason',
              helper: reasons.isEmpty ? 'Add termination reasons in Exit Process → Settings.' : null),
          items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => _set({'terminationReason': v ?? ''}),
        ),
        gap,
      ],
      if (shows('noticePeriodDays')) ...[
        TextField(
          controller: _noticeDays,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: AdminUi.input('Notice period (days)', helper: '0 to 365'),
          onChanged: (v) => _set({'noticePeriodDays': (int.tryParse(v) ?? 0).clamp(0, 365)}),
        ),
        gap,
      ],
      if (shows('noticeFrom')) ...[
        ExitDateField(
          label: 'Notice period from${_autoNotice ? ' (auto)' : ''}',
          value: _s(t['noticeFrom']),
          onChanged: (v) => _set({'noticeFrom': v}),
        ),
        gap,
      ],
      if (shows('noticeTo')) ...[
        ExitDateField(
          label: 'Notice period to${_autoNotice ? ' (auto)' : ''}',
          value: _s(t['noticeTo']),
          firstDate: _s(t['noticeFrom']).isEmpty ? null : _s(t['noticeFrom']),
          onChanged: (v) => _set({'noticeTo': v}),
        ),
        gap,
      ],
      ExitDateField(
        label: 'Last working day',
        value: _s(t['lastWorkingDay']),
        firstDate: shows('resignationDate') && _s(t['resignationDate']).isNotEmpty ? _s(t['resignationDate']) : null,
        onChanged: (v) => _set({'lastWorkingDay': v}),
      ),
      gap,
      if (shows('extendByApprovedLeave'))
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: t['extendByApprovedLeave'] == true,
          title: const Text('Extend by approved leave', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
          subtitle: const Text('Approved leave inside the notice period pushes the last working day.',
              style: TextStyle(fontSize: 12.5, color: AdminUi.muted)),
          onChanged: (v) => _set({'extendByApprovedLeave': v}),
        ),
      if (shows('leaveNote')) ...[
        TextField(controller: _leaveNote, maxLength: 500, maxLines: 2, decoration: AdminUi.input('Leave note')),
        gap,
      ],
      TextField(controller: _description, maxLength: 2000, maxLines: 4, decoration: AdminUi.input('Description')),
    ];
  }
}

// ═══════════════════════════════ Credentials ═══════════════════════════════

class _Account {
  final String id;
  final String kind;
  final TextEditingController label;
  final TextEditingController login;
  final TextEditingController password;
  bool show = false;
  _Account({required this.id, required this.kind, String label = '', String login = '', String password = ''})
      : label = TextEditingController(text: label),
        login = TextEditingController(text: login),
        password = TextEditingController(text: password);
  void dispose() {
    label.dispose();
    login.dispose();
    password.dispose();
  }
}

class ExitCredentialsTab extends StatefulWidget {
  final String caseId;
  final String sectionStatus;
  final ExitCaseCallback onCaseUpdated;
  const ExitCredentialsTab({super.key, required this.caseId, required this.sectionStatus, required this.onCaseUpdated});

  @override
  State<ExitCredentialsTab> createState() => _ExitCredentialsTabState();
}

class _ExitCredentialsTabState extends State<ExitCredentialsTab> with AutomaticKeepAliveClientMixin {
  static const _fixed = {'gmail': 'Gmail', 'zoho': 'Zoho mail', 'crm': 'CRM / Jira'};

  bool _loading = true;
  String? _error;
  bool _editing = false;
  bool _saving = false;
  bool _laptop = false;
  bool _mobile = false;
  List<_Account> _accounts = [];
  Map<String, dynamic> _saved = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final a in _accounts) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AdminExitProcessService.instance.getCredentials(widget.caseId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _saved = _mapOf(r['data']);
        _reset();
      } else {
        _error = r['message']?.toString() ?? 'Could not load credentials.';
      }
    });
  }

  /// Rebuilds the form from the saved credentials: the three fixed accounts, then custom ones.
  void _reset() {
    for (final a in _accounts) {
      a.dispose();
    }
    final saved = _listOf(_saved['accounts']);
    _laptop = _saved['laptopPasswordCollected'] == true;
    _mobile = _saved['mobilePasswordCollected'] == true;
    _accounts = [
      for (final kind in _fixed.keys)
        () {
          final a = saved.firstWhere((x) => x['kind'] == kind, orElse: () => const {});
          return _Account(id: _s(a['id']), kind: kind, login: _s(a['login']), password: _s(a['password']));
        }(),
      for (final a in saved.where((x) => x['kind'] == 'custom'))
        _Account(id: _s(a['id']), kind: 'custom', label: _s(a['label']), login: _s(a['login']), password: _s(a['password'])),
    ];
    _editing = false;
  }

  Future<void> _save() async {
    for (final a in _accounts) {
      final login = a.login.text.trim();
      if ((a.kind == 'gmail' || a.kind == 'zoho') && login.isNotEmpty && !ExitUi.isEmail(login)) {
        SnackBarUtils.showSnackBar(context, '${_fixed[a.kind]} needs a valid email address.', isError: true);
        return;
      }
      if (a.kind == 'custom' && a.label.text.trim().isEmpty && (login.isNotEmpty || a.password.text.isNotEmpty)) {
        SnackBarUtils.showSnackBar(context, 'Name every custom credential field.', isError: true);
        return;
      }
    }
    final body = {
      'laptopPasswordCollected': _laptop,
      'mobilePasswordCollected': _mobile,
      'accounts': _accounts
          .map((a) => {
                if (a.id.isNotEmpty) 'id': a.id,
                'kind': a.kind,
                'label': a.kind == 'custom' ? a.label.text.trim() : '',
                'login': a.login.text.trim(),
                'password': a.password.text,
              })
          .toList(),
    };
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.saveCredentials(widget.caseId, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      final data = _mapOf(r['data']);
      setState(() {
        _saved = _mapOf(data['credentials']);
        _reset();
      });
      widget.onCaseUpdated(_mapOf(data['case']));
      SnackBarUtils.showSnackBar(context, 'Credentials saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save credentials.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const AdminLoading();
    if (_error != null) return AdminErrorView(message: _error!, onRetry: _load);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExitEditBar(
              title: 'Credentials',
              status: widget.sectionStatus,
              editing: _editing,
              saving: _saving,
              onEdit: () => setState(() => _editing = true),
              onCancel: () => setState(_reset),
              onSave: _save,
            ),
            const Text('Passwords are encrypted by the server before they are stored.',
                style: TextStyle(fontSize: 12, color: AdminUi.muted)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _laptop,
              title: const Text('Laptop password collected', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
              onChanged: _editing ? (v) => setState(() => _laptop = v == true) : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _mobile,
              title: const Text('Mobile password collected', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
              onChanged: _editing ? (v) => setState(() => _mobile = v == true) : null,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        ..._accounts.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _accountCard(e.key, e.value))),
        if (_editing)
          OutlinedButton.icon(
            onPressed: () => setState(() => _accounts.add(_Account(id: '', kind: 'custom'))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add custom field'),
          ),
      ],
    );
  }

  Widget _accountCard(int index, _Account a) {
    final isCustom = a.kind == 'custom';
    final title = isCustom ? (a.label.text.trim().isEmpty ? 'Custom field' : a.label.text.trim()) : _fixed[a.kind]!;
    final halfFilled = a.login.text.trim().isNotEmpty != a.password.text.isNotEmpty;
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink))),
          if (halfFilled) const AdminPill('Incomplete', fg: AdminUi.amber, bg: AdminUi.amberBg),
          if (_editing && isCustom)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AdminUi.red),
              onPressed: () => setState(() => _accounts.removeAt(index).dispose()),
            ),
        ]),
        const SizedBox(height: 8),
        if (_editing && isCustom) ...[
          TextField(
            controller: a.label,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
            decoration: AdminUi.input('Field name', hint: 'e.g. VPN, GitHub'),
          ),
          const SizedBox(height: 4),
        ],
        TextField(
          controller: a.login,
          enabled: _editing,
          keyboardType: a.kind == 'gmail' || a.kind == 'zoho' ? TextInputType.emailAddress : TextInputType.text,
          onChanged: (_) => setState(() {}),
          decoration: AdminUi.input(a.kind == 'gmail' || a.kind == 'zoho' ? 'Email' : 'Login'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: a.password,
          enabled: true,
          readOnly: !_editing,
          obscureText: !a.show,
          onChanged: (_) => setState(() {}),
          decoration: AdminUi.input('Password').copyWith(
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: a.show ? 'Hide' : 'Show',
                icon: Icon(a.show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                onPressed: () => setState(() => a.show = !a.show),
              ),
              if (a.password.text.isNotEmpty)
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: a.password.text));
                    if (mounted) SnackBarUtils.showSnackBar(context, 'Password copied.');
                  },
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════ Asset Handover ═══════════════════════════════

class _AssetRow {
  final String id;
  final TextEditingController tag;
  final TextEditingController name;
  final TextEditingController category;
  final TextEditingController remarks;
  String assignedDate;
  String handoverDate;
  String condition;
  String status;
  _AssetRow(Map<String, dynamic> a)
      : id = _s(a['id']),
        tag = TextEditingController(text: _s(a['assetTag'])),
        name = TextEditingController(text: _s(a['name'])),
        category = TextEditingController(text: _s(a['category'])),
        remarks = TextEditingController(text: _s(a['remarks'])),
        assignedDate = _s(a['assignedDate']),
        handoverDate = _s(a['handoverDate']),
        condition = ExitUi.assetConditions.contains(a['condition']) ? a['condition'].toString() : 'Good',
        status = ExitUi.assetStatuses.contains(a['status']) ? a['status'].toString() : 'Pending';
  void dispose() {
    tag.dispose();
    name.dispose();
    category.dispose();
    remarks.dispose();
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'assetTag': tag.text.trim(),
        'name': name.text.trim(),
        'category': category.text.trim(),
        'assignedDate': assignedDate,
        'condition': condition,
        'status': status,
        'handoverDate': handoverDate,
        'remarks': remarks.text.trim(),
      };
}

class ExitAssetsTab extends StatefulWidget {
  final Map<String, dynamic> exitCase;
  final String sectionStatus;
  final ExitCaseCallback onCaseUpdated;
  const ExitAssetsTab({super.key, required this.exitCase, required this.sectionStatus, required this.onCaseUpdated});

  @override
  State<ExitAssetsTab> createState() => _ExitAssetsTabState();
}

class _ExitAssetsTabState extends State<ExitAssetsTab> with AutomaticKeepAliveClientMixin {
  List<_AssetRow>? _draft;
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final r in _draft ?? const <_AssetRow>[]) {
      r.dispose();
    }
    _draft = null;
  }

  List<Map<String, dynamic>> get _saved => _listOf(widget.exitCase['assets']);

  void _startEdit() => setState(() => _draft = _saved.map(_AssetRow.new).toList());

  Future<void> _persist(List<Map<String, dynamic>> assets) async {
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.saveAssets(_s(widget.exitCase['id']), assets);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(_clear);
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'Asset handover saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save assets.', isError: true);
    }
  }

  Future<void> _save() async {
    final rows = _draft!;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].tag.text.trim().isEmpty || rows[i].name.text.trim().isEmpty) {
        SnackBarUtils.showSnackBar(context, 'Asset ${i + 1} needs a tag and a name.', isError: true);
        return;
      }
    }
    await _persist(rows.map((r) => r.toJson()).toList());
  }

  /// Quick action from the read view: marks one asset returned today.
  Future<void> _markReturned(int index) async {
    final assets = _saved.map((a) {
      final row = _AssetRow(a);
      final json = row.toJson();
      row.dispose();
      return json;
    }).toList();
    assets[index]['status'] = 'Returned';
    if (_s(assets[index]['handoverDate']).isEmpty) assets[index]['handoverDate'] = AdminUi.ymd(DateTime.now());
    await _persist(assets);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final editing = _draft != null;
    final saved = _saved;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        ExitEditBar(
          title: 'Asset handover',
          status: widget.sectionStatus,
          editing: editing,
          saving: _saving,
          onEdit: _startEdit,
          onCancel: () => setState(_clear),
          onSave: _save,
        ),
        if (!editing && saved.isEmpty)
          const AdminEmptyView(icon: Icons.laptop_mac_rounded, title: 'No assets recorded', subtitle: 'Use Edit to add the assets to collect.'),
        if (!editing)
          ...saved.asMap().entries.map((e) {
            final a = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdminCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${a['name']}  ·  ${a['assetTag']}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
                    ),
                    AdminPill(_s(a['status'])),
                  ]),
                  const SizedBox(height: 6),
                  ExitKv('Category', _s(a['category'])),
                  ExitKv('Condition', _s(a['condition'])),
                  ExitKv('Assigned', AdminUi.date(a['assignedDate'])),
                  ExitKv('Handed over', AdminUi.date(a['handoverDate'])),
                  if (_s(a['remarks']).isNotEmpty) ExitKv('Remarks', _s(a['remarks'])),
                  if (a['status'] == 'Pending')
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _saving ? null : () => _markReturned(e.key),
                        icon: const Icon(Icons.assignment_turned_in_rounded, size: 18),
                        label: const Text('Mark returned'),
                      ),
                    ),
                ]),
              ),
            );
          }),
        if (editing) ...[
          ..._draft!.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _editCard(e.key, e.value))),
          OutlinedButton.icon(
            onPressed: () => setState(() => _draft!.add(_AssetRow(const {}))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add asset'),
          ),
        ],
      ],
    );
  }

  Widget _editCard(int index, _AssetRow r) => AdminCard(
        child: Column(children: [
          Row(children: [
            Expanded(child: Text('Asset ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AdminUi.red),
              onPressed: () => setState(() => _draft!.removeAt(index).dispose()),
            ),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: r.tag, decoration: AdminUi.input('Asset tag'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: r.name, decoration: AdminUi.input('Name'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: r.category, decoration: AdminUi.input('Category')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: r.condition,
                decoration: AdminUi.input('Condition'),
                items: ExitUi.assetConditions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => r.condition = v ?? 'Good'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: r.status,
                isExpanded: true,
                decoration: AdminUi.input('Status'),
                items: ExitUi.assetStatuses.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => r.status = v ?? 'Pending'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          ExitDateField(label: 'Assigned date', value: r.assignedDate, onChanged: (v) => setState(() => r.assignedDate = v)),
          const SizedBox(height: 12),
          ExitDateField(label: 'Handover date', value: r.handoverDate, onChanged: (v) => setState(() => r.handoverDate = v)),
          const SizedBox(height: 12),
          TextField(controller: r.remarks, maxLines: 2, decoration: AdminUi.input('Remarks')),
        ]),
      );
}

// ═══════════════════════════════ KT Handover ═══════════════════════════════

class _KTRow {
  final String id;
  final TextEditingController name;
  final TextEditingController proof;
  final TextEditingController handoverTo;
  bool ktGiven;
  _KTRow(Map<String, dynamic> p)
      : id = _s(p['id']),
        name = TextEditingController(text: _s(p['name'])),
        proof = TextEditingController(text: _s(p['proofLink'])),
        handoverTo = TextEditingController(text: _s(p['handoverTo'])),
        ktGiven = p['ktGiven'] == true;
  bool get blank => name.text.trim().isEmpty && !ktGiven && proof.text.trim().isEmpty && handoverTo.text.trim().isEmpty;
  void dispose() {
    name.dispose();
    proof.dispose();
    handoverTo.dispose();
  }
}

class ExitKTTab extends StatefulWidget {
  final Map<String, dynamic> exitCase;
  final String sectionStatus;
  final ExitCaseCallback onCaseUpdated;
  const ExitKTTab({super.key, required this.exitCase, required this.sectionStatus, required this.onCaseUpdated});

  @override
  State<ExitKTTab> createState() => _ExitKTTabState();
}

class _ExitKTTabState extends State<ExitKTTab> with AutomaticKeepAliveClientMixin {
  List<_KTRow>? _draft;
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final r in _draft ?? const <_KTRow>[]) {
      r.dispose();
    }
    _draft = null;
  }

  Future<void> _save() async {
    final rows = _draft!.where((r) => !r.blank).toList();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.name.text.trim().isEmpty) {
        SnackBarUtils.showSnackBar(context, 'KT project ${i + 1} needs a name.', isError: true);
        return;
      }
      if (r.ktGiven && r.proof.text.trim().isNotEmpty && !ExitUi.isLink(r.proof.text)) {
        SnackBarUtils.showSnackBar(context, 'The proof link for "${r.name.text.trim()}" must start with http:// or https://.',
            isError: true);
        return;
      }
    }
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.saveKT(
      _s(widget.exitCase['id']),
      rows
          .map((p) => {
                if (p.id.isNotEmpty) 'id': p.id,
                'name': p.name.text.trim(),
                'ktGiven': p.ktGiven,
                'proofLink': p.ktGiven ? p.proof.text.trim() : '',
                'handoverTo': p.handoverTo.text.trim(),
              })
          .toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(_clear);
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'KT handover saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save KT handover.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final saved = _listOf(widget.exitCase['ktProjects']);
    final editing = _draft != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        ExitEditBar(
          title: 'KT handover',
          status: widget.sectionStatus,
          editing: editing,
          saving: _saving,
          onEdit: () => setState(() => _draft = saved.map(_KTRow.new).toList()),
          onCancel: () => setState(_clear),
          onSave: _save,
        ),
        if (!editing && saved.isEmpty)
          const AdminEmptyView(icon: Icons.school_outlined, title: 'No projects recorded', subtitle: 'Use Edit to list the projects to hand over.'),
        if (!editing)
          ...saved.map((p) {
            final done = _s(p['name']).isNotEmpty && p['ktGiven'] == true && _s(p['proofLink']).isNotEmpty && _s(p['handoverTo']).isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdminCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_s(p['name']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink))),
                    AdminPill(done ? 'Completed' : 'Pending'),
                  ]),
                  const SizedBox(height: 6),
                  ExitKv('KT given', p['ktGiven'] == true ? 'Yes' : 'No'),
                  ExitKv('Proof link', _s(p['proofLink'])),
                  ExitKv('Handed over to', _s(p['handoverTo'])),
                ]),
              ),
            );
          }),
        if (editing) ...[
          ..._draft!.asMap().entries.map((e) {
            final r = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdminCard(
                child: Column(children: [
                  Row(children: [
                    Expanded(child: TextField(controller: r.name, decoration: AdminUi.input('Project name'))),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AdminUi.red),
                      onPressed: () => setState(() => _draft!.removeAt(e.key).dispose()),
                    ),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: r.ktGiven,
                    title: const Text('KT given', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
                    onChanged: (v) => setState(() => r.ktGiven = v),
                  ),
                  if (r.ktGiven) ...[
                    TextField(
                      controller: r.proof,
                      keyboardType: TextInputType.url,
                      decoration: AdminUi.input('Proof link', hint: 'https://... (recording or document)'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(controller: r.handoverTo, decoration: AdminUi.input('Handed over to', hint: 'Person or team')),
                ]),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () => setState(() => _draft!.add(_KTRow(const {}))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add project'),
          ),
        ],
      ],
    );
  }
}
