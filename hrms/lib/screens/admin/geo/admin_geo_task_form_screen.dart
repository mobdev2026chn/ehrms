// Admin GEO: create an internal task (branch + internal field employee) or an external task
// (customer + one of the customer's assigned employees, with the visit's address / geofence),
// with the task custom fields; or edit an existing task.
// HRMSbackend POST /api/admin/hrms-geo/task, PUT /api/admin/hrms-geo/task/:id.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'geo_admin_ui.dart';

class AdminGeoTaskFormScreen extends StatefulWidget {
  const AdminGeoTaskFormScreen({super.key, required this.taskType, this.task});

  /// 'Internal' or 'External'.
  final String taskType;

  /// The task to edit (shape of GET /task/:id); null to create.
  final Map<String, dynamic>? task;

  @override
  State<AdminGeoTaskFormScreen> createState() => _AdminGeoTaskFormScreenState();
}

class _AdminGeoTaskFormScreenState extends State<AdminGeoTaskFormScreen> {
  final _customKey = GlobalKey<GeoCustomFieldsFormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _address = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _radius = TextEditingController(text: '10');

  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _places = []; // branches or customers
  List<Map<String, dynamic>> _fieldDefs = [];
  String? _placeId;
  String? _staffId;
  DateTime? _start;
  DateTime? _end;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  bool get _internal => widget.taskType == 'Internal';
  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      _title.text = GeoUi.s(t['title']);
      _desc.text = GeoUi.s(t['description']);
      _address.text = GeoUi.s(t['customerAddress']);
      _lat.text = t['latitude'] is num ? '${t['latitude']}' : '';
      _lng.text = t['longitude'] is num ? '${t['longitude']}' : '';
      _radius.text = t['radius'] is num ? '${t['radius']}' : '10';
      _start = DateTime.tryParse(GeoUi.s(t['startDate']));
      _end = DateTime.tryParse(GeoUi.s(t['endDate']));
      _placeId = GeoUi.s(_internal ? t['branchId'] : t['customerId']);
      if (_placeId!.isEmpty) _placeId = null;
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _desc, _address, _lat, _lng, _radius]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = AdminGeoService.instance;
      final results = await Future.wait([
        svc.getEmployeeAccess(),
        _internal ? svc.getBranches() : svc.getCustomers(),
        if (!_editing) svc.getCustomFields(),
      ]);
      if (!mounted) return;
      setState(() {
        _staff = results[0];
        _places = results[1];
        if (!_editing) _fieldDefs = results[2].where((f) => f['category'] == 'task').toList();
        if (_placeId != null && !_places.any((p) => _placeKey(p) == _placeId)) _placeId = null;
        final t = widget.task;
        if (t != null) {
          // The list returns the employee ID (or the staff _id when there is none).
          final sid = GeoUi.s(t['staffId']);
          final match = _staff.where((s) => GeoUi.s(s['employeeId']) == sid || GeoUi.s(s['id']) == sid);
          _staffId = match.isNotEmpty ? GeoUi.s(match.first['id']) : null;
        }
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

  String _placeKey(Map<String, dynamic> p) => GeoUi.s(_internal ? p['_id'] : p['id']);
  String _placeName(Map<String, dynamic> p) =>
      _internal ? GeoUi.s(p['branchName'], 'Branch') : '${GeoUi.s(p['companyName'], 'Customer')} · ${GeoUi.s(p['name'])}';

  Map<String, dynamic>? get _place {
    for (final p in _places) {
      if (_placeKey(p) == _placeId) return p;
    }
    return null;
  }

  /// Internal: internal field employees. External: the employees assigned to the customer.
  List<Map<String, dynamic>> get _staffOptions {
    if (_internal) return _staff.where((s) => s['type'] == 'Internal' || GeoUi.s(s['id']) == _staffId).toList();
    final c = _place;
    if (c == null) return [];
    final assigned = c['assignedEmployees'] is List ? [for (final e in c['assignedEmployees'] as List) e.toString()] : <String>[];
    return _staff
        .where((s) => assigned.contains(GeoUi.s(s['id'])) || assigned.contains(GeoUi.s(s['employeeId'])) || GeoUi.s(s['id']) == _staffId)
        .toList();
  }

  void _onPlace(String? id) {
    setState(() {
      _placeId = id;
      if (!_internal) {
        if (!_staffOptions.any((s) => GeoUi.s(s['id']) == _staffId)) _staffId = null;
        final c = _place;
        if (c != null) {
          _address.text = GeoUi.s(c['address']);
          _lat.text = c['latitude'] is num ? '${c['latitude']}' : '';
          _lng.text = c['longitude'] is num ? '${c['longitude']}' : '';
          _radius.text = c['radius'] is num ? '${c['radius']}' : '10';
        }
      }
    });
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final init = (start ? _start : _end) ?? _start ?? now;
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 3));
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        if (_end != null && _end!.isBefore(d)) _end = d;
      } else {
        _end = d;
      }
    });
  }

  num? _num(String v) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  Future<void> _save() async {
    String? err;
    if (_placeId == null) {
      err = _internal ? 'Choose a branch.' : 'Choose a customer.';
    } else if (_staffId == null) {
      err = 'Choose a staff member.';
    } else if (_title.text.trim().isEmpty) {
      err = 'Enter a title.';
    } else if (_desc.text.trim().isEmpty) {
      err = 'Enter a description.';
    } else if (_start == null || _end == null) {
      err = 'Choose the start and end dates.';
    } else if (_end!.isBefore(_start!)) {
      err = 'The end date cannot be before the start date.';
    } else if (!_internal &&
        ((_lat.text.trim().isNotEmpty && _num(_lat.text) == null) ||
            (_lng.text.trim().isNotEmpty && _num(_lng.text) == null) ||
            (_radius.text.trim().isNotEmpty && _num(_radius.text) == null))) {
      err = 'Latitude, longitude and radius must be numbers.';
    }
    err ??= _customKey.currentState?.validate();
    if (err != null) {
      GeoUi.fail(context, err);
      return;
    }

    final fmt = DateFormat('yyyy-MM-dd');
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'startDate': fmt.format(_start!),
      'endDate': fmt.format(_end!),
      'staffId': _staffId,
      if (_internal) 'branchId': _placeId else 'customerId': _placeId,
      if (!_internal) ...{
        'customerAddress': _address.text.trim(),
        'latitude': ?_num(_lat.text),
        'longitude': ?_num(_lng.text),
        'radius': _num(_radius.text) ?? 10,
      },
    };

    setState(() => _saving = true);
    try {
      final svc = AdminGeoService.instance;
      if (_editing) {
        await svc.updateTask(GeoUi.s(widget.task!['_id'], GeoUi.s(widget.task!['id'])), body);
      } else {
        await svc.createTask({
          ...body,
          'type': widget.taskType,
          'assignedBy': 'Admin',
          'status': 'Assigned',
          'customFields': _customKey.currentState?.values ?? <String, String>{},
        });
      }
      if (!mounted) return;
      GeoUi.ok(context, _editing ? 'Task updated.' : 'Task created.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_editing ? 'Edit' : 'New'} ${_internal ? 'internal' : 'external'} task';
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar(title),
      body: _loading
          ? GeoUi.loading
          : _error != null
              ? GeoUi.error(_error!, _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    GeoUi.card(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        DropdownButtonFormField<String>(
                          initialValue: _placeId,
                          isExpanded: true,
                          decoration: GeoUi.input(_internal ? 'Branch *' : 'Customer *'),
                          items: [
                            for (final p in _places)
                              DropdownMenuItem(value: _placeKey(p), child: Text(_placeName(p), overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: _onPlace,
                        ),
                        if (_places.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_internal ? 'No branches are set up yet.' : 'No customers yet. Add one under Customers.',
                                style: const TextStyle(fontSize: 12.5, color: AppColors.brandDark)),
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey('staff-$_placeId'),
                          initialValue: _staffOptions.any((s) => GeoUi.s(s['id']) == _staffId) ? _staffId : null,
                          isExpanded: true,
                          decoration: GeoUi.input('Staff *'),
                          items: [
                            for (final s in _staffOptions)
                              DropdownMenuItem(
                                value: GeoUi.s(s['id']),
                                child: Text('${GeoUi.s(s['name'])} (${GeoUi.s(s['employeeId'])})', overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() => _staffId = v),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _internal
                                ? 'Only internal field employees (Settings → Employee Access) are listed.'
                                : 'Only employees assigned to the selected customer are listed.',
                            style: const TextStyle(fontSize: 12.5, color: GeoUi.muted),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: _title, decoration: GeoUi.input('Title *')),
                        const SizedBox(height: 12),
                        TextField(controller: _desc, maxLines: 3, decoration: GeoUi.input('Description *')),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _dateField('Start date *', _start, () => _pickDate(true))),
                          const SizedBox(width: 12),
                          Expanded(child: _dateField('End date *', _end, () => _pickDate(false))),
                        ]),
                      ]),
                    ),
                    if (!_internal)
                      GeoUi.card(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text('Visit location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
                        const Padding(
                          padding: EdgeInsets.only(top: 2, bottom: 12),
                          child: Text('Filled from the customer; changes are saved on this task only.',
                              style: TextStyle(fontSize: 12.5, color: GeoUi.muted)),
                        ),
                        TextField(controller: _address, maxLines: 2, decoration: GeoUi.input('Address')),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: TextField(controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: GeoUi.input('Latitude'))),
                          const SizedBox(width: 12),
                          Expanded(child: TextField(controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: GeoUi.input('Longitude'))),
                        ]),
                        const SizedBox(height: 12),
                        TextField(controller: _radius, keyboardType: TextInputType.number, decoration: GeoUi.input('Geofence radius (m)')),
                        ]),
                      ),
                    if (!_editing && _fieldDefs.isNotEmpty)
                      GeoUi.card(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: GeoCustomFieldsForm(key: _customKey, defs: _fieldDefs),
                      ),
                    const SizedBox(height: 8),
                    GeoUi.primaryButton(_editing ? 'Save changes' : 'Create task', _save, busy: _saving),
                  ],
                ),
    );
  }

  Widget _dateField(String label, DateTime? d, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: GeoUi.input(label, suffix: const Icon(Icons.calendar_today_rounded, size: 18)),
          child: Text(d == null ? 'Select' : DateFormat('d MMM yyyy').format(d)),
        ),
      );
}
