// Admin-defined extra fields (HRMS GEO → Settings → Custom Fields) for the
// Add Task / Add Customer forms. HRMSbackend refuses a create that leaves a
// required one empty ("<Label> is required."), so the forms collect them here
// and send `customFields: { fieldId: value }`.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';

class CustomFieldDef {
  CustomFieldDef({required this.id, required this.label, required this.type, required this.required});
  final String id;
  final String label;

  /// 'text' | 'number' | 'date'
  final String type;
  final bool required;

  factory CustomFieldDef.fromJson(Map j) => CustomFieldDef(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        type: (j['type'] ?? 'text').toString(),
        required: j['required'] == true,
      );
}

/// Loads the field list: `category` = 'task' → GET /staff/geo-task/task-fields,
/// 'customer' → GET /staff/geo-task/customer-fields. Empty on an older backend.
Future<List<CustomFieldDef>> loadCustomFieldDefs(String category) async {
  try {
    final res = await ApiClient().dio.get<dynamic>(
          category == 'customer' ? '/staff/geo-task/customer-fields' : '/staff/geo-task/task-fields',
        );
    final data = res.data is Map ? (res.data as Map)['data'] : null;
    if (data is! List) return const [];
    return [
      for (final f in data)
        if (f is Map && (f['_id'] ?? f['id']) != null) CustomFieldDef.fromJson(f),
    ];
  } catch (_) {
    return const [];
  }
}

/// Renders the fields and keeps their values. Read with [CustomFieldsFormState.values]
/// and check with [CustomFieldsFormState.validate] before submitting.
class CustomFieldsForm extends StatefulWidget {
  const CustomFieldsForm({super.key, required this.category});

  /// 'task' or 'customer'.
  final String category;

  @override
  State<CustomFieldsForm> createState() => CustomFieldsFormState();
}

class CustomFieldsFormState extends State<CustomFieldsForm> {
  List<CustomFieldDef> _defs = const [];
  bool _loading = true;
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    loadCustomFieldDefs(widget.category).then((defs) {
      if (!mounted) return;
      setState(() {
        _defs = defs;
        _loading = false;
        for (final d in defs) {
          _ctrls[d.id] = TextEditingController();
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// `{ fieldId: value }` for non-empty values (dates as yyyy-MM-dd).
  Map<String, String> get values => {
        for (final d in _defs)
          if ((_ctrls[d.id]?.text.trim() ?? '').isNotEmpty) d.id: _ctrls[d.id]!.text.trim(),
      };

  /// First problem as a message, or null when everything is fine.
  String? validate() {
    for (final d in _defs) {
      final v = _ctrls[d.id]?.text.trim() ?? '';
      if (v.isEmpty) {
        if (d.required) return '${d.label} is required.';
        continue;
      }
      if (d.type == 'number' && double.tryParse(v) == null) return '${d.label} must be a number.';
    }
    return null;
  }

  Future<void> _pickDate(CustomFieldDef d) async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_ctrls[d.id]!.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _ctrls[d.id]!.text = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_defs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Additional Details',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          ),
        ),
        for (final d in _defs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _ctrls[d.id],
              readOnly: d.type == 'date',
              onTap: d.type == 'date' ? () => _pickDate(d) : null,
              keyboardType: d.type == 'number'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: d.required ? '${d.label} *' : d.label,
                hintText: d.type == 'date' ? 'Select date' : null,
                suffixIcon: d.type == 'date' ? const Icon(Icons.calendar_today_rounded, size: 18) : null,
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
