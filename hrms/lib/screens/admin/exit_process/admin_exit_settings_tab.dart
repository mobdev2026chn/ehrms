// Exit Process → Settings: one set of rules for every exit in the company.
//   GET  /admin/exit-process/settings          GET /admin/exit-process/settings/people
//   PUT  /admin/exit-process/settings          POST /admin/exit-process/settings/reset
// People travel as { userId, userType }; feedback questions keep their fieldId.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_exit_process_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../salary/admin_salary_ui.dart';

class AdminExitSettingsTab extends StatefulWidget {
  const AdminExitSettingsTab({super.key});
  @override
  State<AdminExitSettingsTab> createState() => _AdminExitSettingsTabState();
}

class _Question {
  String fieldId;
  final TextEditingController label;
  String type;
  bool required;
  final TextEditingController options; // one per line
  _Question({required this.fieldId, required String label, required this.type, required this.required, required List<String> options})
      : label = TextEditingController(text: label),
        options = TextEditingController(text: options.join('\n'));
  void dispose() {
    label.dispose();
    options.dispose();
  }
}

class _AdminExitSettingsTabState extends State<AdminExitSettingsTab> with AutomaticKeepAliveClientMixin {
  static const _types = {
    'text': 'Short text',
    'textarea': 'Paragraph',
    'select': 'Dropdown',
    'radio': 'Single choice',
    'checkbox': 'Multiple choice',
    'date': 'Date',
  };
  static const _choiceTypes = {'select', 'radio', 'checkbox'};

  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _resetting = false;
  bool _dirty = false;

  bool _reminders = false;
  int _reminderDays = 0;
  int _salaryDays = 0;
  int _salaryReminderDays = 0;
  bool _autoNotice = false;
  bool _autoExtend = false;
  List<String> _notify = []; // "Staff:<id>" / "Admin:<id>"
  List<String> _approvers = [];
  List<String> _reasons = [];
  bool _autoDeactivate = false;
  String _deactivateTime = '18:00';
  bool _feedbackForm = false;
  List<_Question> _questions = [];
  String? _updatedAt;

  /// Everyone who can be picked, plus anyone already picked who no longer can be.
  final Map<String, Map<String, dynamic>> _people = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  static String _key(Map p) => '${p['userType']}:${p['userId']}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final svc = AdminExitProcessService.instance;
    final results = await Future.wait([svc.getSettings(), svc.getSettingsPeople()]);
    if (!mounted) return;
    final failed = results.firstWhere((r) => r['success'] != true, orElse: () => const {});
    if (failed.isNotEmpty) {
      setState(() {
        _loading = false;
        _error = failed['message']?.toString() ?? 'Could not load exit settings.';
      });
      return;
    }
    _people.clear();
    for (final p in List<Map<String, dynamic>>.from(results[1]['data'] as List)) {
      _people[_key(p)] = p;
    }
    setState(() {
      _apply(Map<String, dynamic>.from(results[0]['data'] as Map));
      _loading = false;
    });
  }

  void _apply(Map<String, dynamic> s) {
    List<Map<String, dynamic>> persons(dynamic v) =>
        v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    final notify = persons(s['notifyAudience']);
    final approvers = persons(s['terminationApprovers']);
    for (final p in [...notify, ...approvers]) {
      _people.putIfAbsent(_key(p), () => p);
    }
    _reminders = s['reminderNotifications'] == true;
    _reminderDays = (s['reminderDaysBeforeLastDay'] as num?)?.toInt() ?? 0;
    _salaryDays = (s['salaryProcessDaysAfterRelieving'] as num?)?.toInt() ?? 0;
    _salaryReminderDays = (s['salaryReminderDaysBeforeProcess'] as num?)?.toInt() ?? 0;
    _autoNotice = s['autoCalculateNoticeDates'] == true;
    _autoExtend = s['autoExtendLastDayByLeaves'] == true;
    _notify = notify.map(_key).toList();
    _approvers = approvers.map(_key).toList();
    _reasons = (s['terminationReasons'] is List) ? (s['terminationReasons'] as List).map((e) => e.toString()).toList() : [];
    _autoDeactivate = s['autoDeactivateAfterCompletion'] == true;
    _deactivateTime = (s['autoDeactivateTime'] ?? '18:00').toString();
    _feedbackForm = s['exitFeedbackForm'] == true;
    for (final q in _questions) {
      q.dispose();
    }
    _questions = (s['feedbackFields'] is List)
        ? (s['feedbackFields'] as List)
            .whereType<Map>()
            .map((f) => _Question(
                  fieldId: (f['fieldId'] ?? '').toString(),
                  label: (f['label'] ?? '').toString(),
                  type: _types.containsKey(f['type']) ? f['type'].toString() : 'text',
                  required: f['required'] == true,
                  options: (f['options'] is List) ? (f['options'] as List).map((e) => e.toString()).toList() : [],
                ))
            .toList()
        : [];
    _updatedAt = s['updatedAt']?.toString();
    _dirty = false;
  }

  void _touch(VoidCallback fn) => setState(() {
        fn();
        _dirty = true;
      });

  Map<String, dynamic> _payload() {
    Map<String, String> ref(String k) {
      final i = k.indexOf(':');
      return {'userType': k.substring(0, i), 'userId': k.substring(i + 1)};
    }

    return {
      'reminderNotifications': _reminders,
      'reminderDaysBeforeLastDay': _reminderDays,
      'salaryProcessDaysAfterRelieving': _salaryDays,
      'salaryReminderDaysBeforeProcess': _salaryReminderDays,
      'autoCalculateNoticeDates': _autoNotice,
      'autoExtendLastDayByLeaves': _autoExtend,
      'notifyAudience': _notify.map(ref).toList(),
      'terminationApprovers': _approvers.map(ref).toList(),
      'terminationReasons': _reasons,
      'autoDeactivateAfterCompletion': _autoDeactivate,
      'autoDeactivateTime': _deactivateTime,
      'exitFeedbackForm': _feedbackForm,
      'feedbackFields': _questions
          .map((q) => {
                if (q.fieldId.isNotEmpty) 'fieldId': q.fieldId,
                'label': q.label.text.trim(),
                'type': q.type,
                'required': q.required,
                'options': _choiceTypes.contains(q.type)
                    ? q.options.text.split('\n').map((o) => o.trim()).where((o) => o.isNotEmpty).toList()
                    : <String>[],
              })
          .toList(),
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.updateSettings(_payload());
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r['success'] == true) _apply(Map<String, dynamic>.from(r['data'] as Map));
    });
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Exit settings saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save exit settings.', isError: true);
    }
  }

  Future<void> _reset() async {
    final ok = await adminConfirm(context,
        title: 'Reset exit settings?',
        message: 'Every exit setting goes back to its default, including feedback questions and termination reasons.',
        confirmLabel: 'Reset',
        destructive: true);
    if (!ok || !mounted) return;
    setState(() => _resetting = true);
    final r = await AdminExitProcessService.instance.resetSettings();
    if (!mounted) return;
    setState(() {
      _resetting = false;
      if (r['success'] == true) _apply(Map<String, dynamic>.from(r['data'] as Map));
    });
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Exit settings reset to defaults.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not reset exit settings.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const AdminLoading();
    if (_error != null) return AdminErrorView(message: _error!, onRetry: _load);
    final busy = _saving || _resetting;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _section('Reminders', [
              _switch('Reminder notifications', 'Remind the notify audience as the last working day approaches.', _reminders,
                  (v) => _touch(() => _reminders = v)),
              _stepper('Days before last working day', _reminderDays, 60, (v) => _touch(() => _reminderDays = v),
                  enabled: _reminders),
              _stepper('Salary process days after relieving', _salaryDays, 180, (v) => _touch(() => _salaryDays = v)),
              _stepper('Salary reminder days before process day', _salaryReminderDays, 60,
                  (v) => _touch(() => _salaryReminderDays = v)),
            ]),
            _section('Notice period', [
              _switch('Auto-calculate notice dates', 'Fill the notice window and last working day from the resignation date.',
                  _autoNotice, (v) => _touch(() => _autoNotice = v)),
              _switch('Auto-extend last working day by leaves', 'Approved leave inside the notice period pushes the last day.',
                  _autoExtend, (v) => _touch(() => _autoExtend = v)),
            ]),
            _section('People', [
              _peoplePicker('Notify audience', 'Who hears about exits and reminders.', _notify, (v) => _touch(() => _notify = v)),
              const SizedBox(height: 12),
              _peoplePicker('Termination approvers', 'Suggested for “Approved by” on a termination.', _approvers,
                  (v) => _touch(() => _approvers = v)),
            ]),
            _section('Termination reasons', [_reasonsEditor()]),
            _section('Deactivation', [
              _switch('Auto-deactivate after completion', 'Deactivate the employee once their exit is completed.',
                  _autoDeactivate, (v) => _touch(() => _autoDeactivate = v)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: _autoDeactivate,
                title: const Text('Deactivate at', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
                trailing: Text(_deactivateTime, style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () async {
                  final parts = _deactivateTime.split(':');
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 18, minute: int.tryParse(parts.last) ?? 0),
                  );
                  if (t != null) {
                    _touch(() => _deactivateTime =
                        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                  }
                },
              ),
            ]),
            _section('Exit feedback form', [
              _switch('Exit feedback form', 'Each exit gets a link the employee uses to answer these questions.',
                  _feedbackForm, (v) => _touch(() => _feedbackForm = v)),
              if (_feedbackForm) ..._questionsEditor(),
            ]),
            if (_updatedAt != null)
              Text('Last saved ${AdminUi.date(_updatedAt)}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AdminUi.border))),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : _reset,
                child: _resetting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Reset to defaults'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: AdminUi.primaryButton(),
                onPressed: busy || !_dirty ? null : _save,
                child: _saving
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                    : const Text('Save settings'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _switch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: AdminUi.ink)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AdminUi.muted, height: 1.35)),
        onChanged: onChanged,
      );

  Widget _stepper(String label, int value, int max, ValueChanged<int> onChanged, {bool enabled = true}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: enabled ? AdminUi.ink : AdminUi.faint)),
          ),
          IconButton(
            tooltip: 'Decrease',
            onPressed: enabled && value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          SizedBox(
            width: 34,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AdminUi.ink)),
          ),
          IconButton(
            tooltip: 'Increase',
            onPressed: enabled && value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ]),
      );

  Widget _peoplePicker(String title, String subtitle, List<String> selected, ValueChanged<List<String>> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
          ]),
        ),
        TextButton.icon(
          onPressed: () async {
            final picked = await _pickPeople(title, selected);
            if (picked != null) onChanged(picked);
          },
          icon: const Icon(Icons.person_add_alt_rounded, size: 18),
          label: const Text('Choose'),
        ),
      ]),
      const SizedBox(height: 4),
      if (selected.isEmpty)
        const Text('No one chosen.', style: TextStyle(fontSize: 12.5, color: AdminUi.faint))
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: selected.map((k) {
            final p = _people[k];
            final name = (p?['name'] ?? 'Unknown').toString();
            final gone = p?['deactivated'] == true;
            return InputChip(
              label: Text(gone ? '$name (deactivated)' : name, style: const TextStyle(fontSize: 12.5)),
              backgroundColor: gone ? AdminUi.redBg : AdminUi.greyBg,
              side: BorderSide.none,
              onDeleted: () => onChanged(selected.where((x) => x != k).toList()),
            );
          }).toList(),
        ),
    ]);
  }

  Future<List<String>?> _pickPeople(String title, List<String> current) async {
    final chosen = {...current};
    final search = TextEditingController();
    final r = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final q = search.text.trim().toLowerCase();
        final list = _people.entries
            .where((e) =>
                q.isEmpty ||
                [e.value['name'], e.value['email'], e.value['role'], e.value['employeeId']]
                    .any((v) => (v ?? '').toString().toLowerCase().contains(q)))
            .toList();
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (ctx, controller) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink))),
                ElevatedButton(
                  style: AdminUi.primaryButton(),
                  onPressed: () => Navigator.pop(ctx, chosen.toList()),
                  child: Text('Done (${chosen.length})'),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: AdminSearchField(controller: search, hint: 'Search people', onChanged: (_) => setS(() {})),
            ),
            Expanded(
              child: list.isEmpty
                  ? const AdminEmptyView(icon: Icons.people_outline_rounded, title: 'No one found')
                  : ListView.builder(
                      controller: controller,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        return CheckboxListTile(
                          value: chosen.contains(e.key),
                          onChanged: (v) => setS(() => v == true ? chosen.add(e.key) : chosen.remove(e.key)),
                          title: Text((e.value['name'] ?? '').toString(),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
                          subtitle: Text(
                            [e.value['role'], e.value['email'], if (e.value['deactivated'] == true) 'Deactivated']
                                .where((v) => v != null && v.toString().isNotEmpty)
                                .join(' • '),
                            style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        );
      }),
    );
    search.dispose();
    return r;
  }

  Widget _reasonsEditor() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_reasons.isEmpty)
          const Text('No reasons yet.', style: TextStyle(fontSize: 12.5, color: AdminUi.faint))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _reasons
                .map((r) => InputChip(
                      label: Text(r, style: const TextStyle(fontSize: 12.5)),
                      backgroundColor: AdminUi.greyBg,
                      side: BorderSide.none,
                      onDeleted: () => _touch(() => _reasons = _reasons.where((x) => x != r).toList()),
                    ))
                .toList(),
          ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _reasons.length >= 50
              ? null
              : () async {
                  final text = await _askText('Add termination reason', 'Reason', maxLength: 120);
                  if (text == null || text.isEmpty) return;
                  if (_reasons.any((x) => x.toLowerCase() == text.toLowerCase())) {
                    if (mounted) SnackBarUtils.showSnackBar(context, 'That reason is already listed.', isError: true);
                    return;
                  }
                  _touch(() => _reasons = [..._reasons, text]);
                },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add reason'),
        ),
      ]);

  Future<String?> _askText(String title, String label, {int maxLength = 200}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
        content: TextField(controller: c, autofocus: true, maxLength: maxLength, decoration: AdminUi.input(label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(style: AdminUi.primaryButton(), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  List<Widget> _questionsEditor() => [
        const SizedBox(height: 6),
        ..._questions.asMap().entries.map((e) {
          final q = e.value;
          return Container(
            key: ObjectKey(q),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AdminUi.bg, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: q.label,
                    onChanged: (_) => setState(() => _dirty = true),
                    decoration: AdminUi.input('Question ${e.key + 1}'),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AdminUi.red),
                  onPressed: () => _touch(() => _questions.removeAt(e.key).dispose()),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: q.type,
                    decoration: AdminUi.input('Answer type'),
                    items: _types.entries.map((t) => DropdownMenuItem(value: t.key, child: Text(t.value))).toList(),
                    onChanged: (v) => _touch(() => q.type = v ?? 'text'),
                  ),
                ),
                const SizedBox(width: 8),
                Column(children: [
                  const Text('Required', style: TextStyle(fontSize: 12, color: AdminUi.muted)),
                  Switch(
                    value: q.required,
                    onChanged: (v) => _touch(() => q.required = v),
                  ),
                ]),
              ]),
              if (_choiceTypes.contains(q.type)) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: q.options,
                  minLines: 2,
                  maxLines: 6,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: AdminUi.input('Options', helper: 'One option per line.'),
                ),
              ],
            ]),
          );
        }),
        TextButton.icon(
          onPressed: _questions.length >= 50
              ? null
              : () => _touch(() => _questions.add(_Question(fieldId: '', label: '', type: 'text', required: false, options: []))),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add question'),
        ),
      ];
}
