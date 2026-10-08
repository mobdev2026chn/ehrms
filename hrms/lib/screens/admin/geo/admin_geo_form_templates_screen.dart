// Admin GEO form templates: the task form fields for the internal and external layouts — add,
// edit, activate / deactivate, and delete the ones that are not predefined. Each change saves
// the layout's whole field list. HRMSbackend GET /api/admin/hrms-geo/settings/form-templates,
// PUT /api/admin/hrms-geo/settings/form-templates/:id { fields }.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'geo_admin_ui.dart';

class AdminGeoFormTemplatesScreen extends StatefulWidget {
  const AdminGeoFormTemplatesScreen({super.key});

  @override
  State<AdminGeoFormTemplatesScreen> createState() => _AdminGeoFormTemplatesScreenState();
}

class _AdminGeoFormTemplatesScreenState extends State<AdminGeoFormTemplatesScreen> {
  static const fieldTypes = [
    'Text Input', 'Text Area', 'Numeric Input', 'Date-Time Picker', 'GPS Tracker',
    'Camera Capture', 'Signature Canvas', 'Dropdown Select', 'Image File', 'Button',
  ];
  static const responseTypes = [
    'String text', 'Paragraph Text', 'Integer', 'Float (decimal)', 'Timestamp', 'GeoJSON Point', 'Image File', 'Action',
  ];

  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  String? _error;
  String _layout = 'internal';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final t = await AdminGeoService.instance.getFormTemplates();
      if (!mounted) return;
      setState(() {
        _templates = t;
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

  Map<String, dynamic>? get _template {
    for (final t in _templates) {
      if (t['layoutType'] == _layout) return t;
    }
    return null;
  }

  List<Map<String, dynamic>> get _fields {
    final f = _template?['fields'];
    return f is List ? [for (final e in f) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];
  }

  String _fid(Map<String, dynamic> f) => GeoUi.s(f['_id'] ?? f['id']);

  Map<String, dynamic> _clean(Map<String, dynamic> f) => {
        if (GeoUi.s(f['_id']).isNotEmpty) '_id': f['_id'],
        'name': GeoUi.s(f['name']),
        'type': GeoUi.s(f['type']),
        'response': GeoUi.s(f['response']),
        'active': f['active'] != false,
        'predefined': f['predefined'] == true,
      };

  Future<void> _save(List<Map<String, dynamic>> fields, String done) async {
    final t = _template;
    if (t == null) return;
    setState(() => _saving = true);
    try {
      final updated = await AdminGeoService.instance.updateFormTemplate(GeoUi.s(t['_id']), fields.map(_clean).toList());
      if (!mounted) return;
      setState(() {
        final i = _templates.indexWhere((x) => x['layoutType'] == _layout);
        if (i >= 0 && updated.isNotEmpty) _templates[i] = updated;
        _saving = false;
      });
      GeoUi.ok(context, done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      GeoUi.fail(context, e);
    }
  }

  Future<void> _edit([Map<String, dynamic>? field]) async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _FieldDialog(field: field));
    if (result == null) return;
    final fields = _fields;
    if (field == null) {
      fields.add({...result, 'predefined': false});
    } else {
      final i = fields.indexWhere((f) => _fid(f) == _fid(field));
      if (i >= 0) fields[i] = {...fields[i], ...result};
    }
    await _save(fields, field == null ? 'Field added.' : 'Field updated.');
  }

  Future<void> _toggle(Map<String, dynamic> field) async {
    final fields = [
      for (final f in _fields) _fid(f) == _fid(field) ? {...f, 'active': f['active'] == false} : f,
    ];
    await _save(fields, field['active'] == false ? 'Field activated.' : 'Field deactivated.');
  }

  Future<void> _delete(Map<String, dynamic> field) async {
    if (!await GeoUi.confirm(context, 'Delete field', 'Delete "${GeoUi.s(field['name'])}" from the $_layout form?',
        action: 'Delete', destructive: true)) {
      return;
    }
    await _save(_fields.where((f) => _fid(f) != _fid(field)).toList(), 'Field deleted.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Form Templates', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _template == null || _saving ? null : () => _edit(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add field', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: GeoUi.choiceChips<String>(
            values: const ['internal', 'external'],
            selected: _layout,
            label: (l) => l == 'internal' ? 'Internal layout' : 'External layout',
            onSelected: (l) => setState(() => _layout = l),
          ),
        ),
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _loading
              ? GeoUi.loading
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _error != null
                      ? GeoUi.error(_error!, _load)
                      : _template == null
                          ? GeoUi.message(Icons.dynamic_form_outlined, 'No template', 'The $_layout template was not found.', onRetry: _load)
                          : _fields.isEmpty
                              ? GeoUi.message(Icons.dynamic_form_outlined, 'No fields', 'Add a field to this layout.')
                              : ListView(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                                  children: _fields.map(_card).toList(),
                                ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> f) {
    final active = f['active'] != false;
    final predefined = f['predefined'] == true;
    return GeoUi.card(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      child: Row(children: [
        GeoUi.iconTile(Icons.dynamic_form_outlined, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(GeoUi.s(f['name']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink))),
              const SizedBox(width: 6),
              active
                  ? GeoUi.pill('ACTIVE', AppColors.successBg, AppColors.success)
                  : GeoUi.pill('INACTIVE', AppColors.inputFill, AppColors.textSecondary),
              if (predefined) ...[const SizedBox(width: 4), GeoUi.pill('DEFAULT', const Color(0xFFE0F2FE), const Color(0xFF0369A1))],
            ]),
            const SizedBox(height: 4),
            Text('${GeoUi.s(f['type'])} → ${GeoUi.s(f['response'])}', style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: 'Field actions',
          enabled: !_saving,
          onSelected: (v) {
            if (v == 'edit') _edit(f);
            if (v == 'toggle') _toggle(f);
            if (v == 'delete') _delete(f);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'toggle', child: Text(active ? 'Deactivate' : 'Activate')),
            if (!predefined) const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
          ],
        ),
      ]),
    );
  }
}

class _FieldDialog extends StatefulWidget {
  const _FieldDialog({this.field});
  final Map<String, dynamic>? field;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  late final _name = TextEditingController(text: GeoUi.s(widget.field?['name']));
  late String _type = GeoUi.s(widget.field?['type'], 'Text Input');
  late String _response = GeoUi.s(widget.field?['response'], 'String text');
  late bool _active = widget.field?['active'] != false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep a stored value that is not in the standard list selectable.
    final types = {..._AdminGeoFormTemplatesScreenState.fieldTypes, _type}.toList();
    final responses = {..._AdminGeoFormTemplatesScreenState.responseTypes, _response}.toList();
    return AlertDialog(
      title: Text(widget.field == null ? 'Add field' : 'Edit field'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: GeoUi.input('Field name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: types.contains(_type) ? _type : types.first,
            isExpanded: true,
            decoration: GeoUi.input('Field type'),
            items: [for (final t in types) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: responses.contains(_response) ? _response : responses.first,
            isExpanded: true,
            decoration: GeoUi.input('Response type'),
            items: [for (final t in responses) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _response = v ?? _response),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              GeoUi.fail(context, 'Enter a field name.');
              return;
            }
            Navigator.pop(context, {'name': name, 'type': _type, 'response': _response, 'active': _active});
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
