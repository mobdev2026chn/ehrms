// Admin GEO custom fields: the extra fields on the customer and task forms (label, type
// text / number / date / dropdown, required, dropdown options) — add, edit and delete.
// HRMSbackend /api/admin/hrms-geo/settings/custom-fields[/:id].

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'geo_admin_ui.dart';

class AdminGeoCustomFieldsScreen extends StatefulWidget {
  const AdminGeoCustomFieldsScreen({super.key});

  @override
  State<AdminGeoCustomFieldsScreen> createState() => _AdminGeoCustomFieldsScreenState();
}

class _AdminGeoCustomFieldsScreenState extends State<AdminGeoCustomFieldsScreen> {
  List<Map<String, dynamic>> _fields = [];
  bool _loading = true;
  String? _error;
  String _category = 'customer';
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final f = await AdminGeoService.instance.getCustomFields();
      if (!mounted) return;
      setState(() {
        _fields = f;
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

  List<Map<String, dynamic>> get _visible => _fields.where((f) => f['category'] == _category).toList();

  Future<void> _edit([Map<String, dynamic>? field]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FieldDialog(category: _category, field: field),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    if (!await GeoUi.confirm(context, 'Delete field', 'Delete "${GeoUi.s(f['label'])}"? Values already saved stay on existing records.',
        action: 'Delete', destructive: true)) {
      return;
    }
    final id = GeoUi.s(f['_id']);
    setState(() => _busyId = id);
    try {
      await AdminGeoService.instance.deleteCustomField(id);
      if (!mounted) return;
      setState(() {
        _fields.removeWhere((x) => GeoUi.s(x['_id']) == id);
        _busyId = null;
      });
      GeoUi.ok(context, 'Field deleted.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Custom Fields', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _error != null ? null : () => _edit(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: Text('Add ${_category == 'customer' ? 'customer' : 'task'} field', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: GeoUi.choiceChips<String>(
            values: const ['customer', 'task'],
            selected: _category,
            label: (c) => c == 'customer' ? 'Customer fields' : 'Task fields',
            onSelected: (c) => setState(() => _category = c),
          ),
        ),
        Expanded(
          child: _loading
              ? GeoUi.loading
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _error != null
                      ? GeoUi.error(_error!, _load)
                      : _visible.isEmpty
                          ? GeoUi.message(Icons.dashboard_customize_outlined, 'No fields', 'Add a field to collect extra details.')
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                              children: _visible.map(_card).toList(),
                            ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> f) {
    final id = GeoUi.s(f['_id']);
    final options = f['options'] is List ? (f['options'] as List).join(', ') : '';
    return GeoUi.card(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(children: [
        GeoUi.iconTile(Icons.text_fields_rounded, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(GeoUi.s(f['label']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink))),
              if (f['required'] == true) ...[
                const SizedBox(width: 6),
                GeoUi.pill('REQUIRED', AppColors.errorBg, AppColors.error),
              ],
            ]),
            const SizedBox(height: 4),
            Text(
              '${GeoUi.s(f['type'])}${options.isNotEmpty ? ' · $options' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: GeoUi.muted),
            ),
          ]),
        ),
        if (_busyId == id)
          const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
        else ...[
          IconButton(tooltip: 'Edit', onPressed: () => _edit(f), icon: const Icon(Icons.edit_outlined, size: 20, color: GeoUi.muted)),
          IconButton(tooltip: 'Delete', onPressed: () => _delete(f), icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error)),
        ],
      ]),
    );
  }
}

class _FieldDialog extends StatefulWidget {
  const _FieldDialog({required this.category, this.field});
  final String category;
  final Map<String, dynamic>? field;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  static const _types = ['text', 'number', 'date', 'dropdown'];
  late final _label = TextEditingController(text: GeoUi.s(widget.field?['label']));
  late final _options = TextEditingController(
      text: widget.field?['options'] is List ? (widget.field!['options'] as List).join('\n') : '');
  late String _type = _types.contains(widget.field?['type']) ? widget.field!['type'] as String : 'text';
  late bool _required = widget.field?['required'] == true;
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final options = [for (final o in _options.text.split(RegExp(r'[\n,]'))) if (o.trim().isNotEmpty) o.trim()];
    if (label.isEmpty) {
      GeoUi.fail(context, 'Enter a label.');
      return;
    }
    if (_type == 'dropdown' && options.isEmpty) {
      GeoUi.fail(context, 'Add at least one option for a dropdown field.');
      return;
    }
    setState(() => _busy = true);
    try {
      final svc = AdminGeoService.instance;
      final opts = _type == 'dropdown' ? options : <String>[];
      if (widget.field == null) {
        await svc.createCustomField(category: widget.category, label: label, type: _type, required: _required, options: opts);
      } else {
        await svc.updateCustomField(GeoUi.s(widget.field!['_id']), label: label, type: _type, required: _required, options: opts);
      }
      if (!mounted) return;
      GeoUi.ok(context, widget.field == null ? 'Field added.' : 'Field updated.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.field == null ? 'Add ${widget.category} field' : 'Edit field'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _label, decoration: GeoUi.input('Label')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: GeoUi.input('Type'),
            items: [for (final t in _types) DropdownMenuItem(value: t, child: Text(t[0].toUpperCase() + t.substring(1)))],
            onChanged: (v) => setState(() => _type = v ?? 'text'),
          ),
          if (_type == 'dropdown') ...[
            const SizedBox(height: 12),
            TextField(controller: _options, maxLines: 4, decoration: GeoUi.input('Options', hint: 'One per line')),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Required', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            value: _required,
            onChanged: (v) => setState(() => _required = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
              : const Text('Save'),
        ),
      ],
    );
  }
}
