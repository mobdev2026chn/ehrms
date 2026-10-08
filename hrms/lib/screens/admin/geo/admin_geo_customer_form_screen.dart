// Admin GEO: add or edit a customer — contact, address, geofence, the employees allowed to visit
// it and the customer custom fields.
// HRMSbackend POST /api/admin/hrms-geo/customer, PUT /api/admin/hrms-geo/customer/:id.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'geo_admin_ui.dart';

class AdminGeoCustomerFormScreen extends StatefulWidget {
  const AdminGeoCustomerFormScreen({super.key, this.customer});

  /// The customer to edit (shape of GET /customer/:id); null to create.
  final Map<String, dynamic>? customer;

  @override
  State<AdminGeoCustomerFormScreen> createState() => _AdminGeoCustomerFormScreenState();
}

class _AdminGeoCustomerFormScreenState extends State<AdminGeoCustomerFormScreen> {
  static const _statuses = ['Assigned', 'In Progress', 'Completed', 'Hold', 'Reopened', 'Exited'];

  final _customKey = GlobalKey<GeoCustomFieldsFormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController(text: '+91 ');
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _pin = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _address = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _radius = TextEditingController(text: '10');

  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _fieldDefs = [];
  final Set<String> _assigned = {};
  String _status = 'Assigned';
  String _staffQuery = '';
  bool _loading = true;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    if (c != null) {
      _name.text = GeoUi.s(c['name']);
      _mobile.text = GeoUi.s(c['mobile']);
      _email.text = GeoUi.s(c['email']);
      _company.text = GeoUi.s(c['companyName']);
      _pin.text = GeoUi.s(c['pinCode']);
      _city.text = GeoUi.s(c['city']);
      _state.text = GeoUi.s(c['state']);
      _address.text = GeoUi.s(c['address']);
      _lat.text = c['latitude'] is num ? '${c['latitude']}' : '';
      _lng.text = c['longitude'] is num ? '${c['longitude']}' : '';
      _radius.text = c['radius'] is num ? '${c['radius']}' : '10';
      if (_statuses.contains(c['status'])) _status = c['status'] as String;
      if (c['assignedEmployees'] is List) _assigned.addAll([for (final e in c['assignedEmployees'] as List) e.toString()]);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _mobile, _email, _company, _pin, _city, _state, _address, _lat, _lng, _radius]) {
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
      final r = await Future.wait([AdminGeoService.instance.getEmployeeAccess(), AdminGeoService.instance.getCustomFields()]);
      if (!mounted) return;
      setState(() {
        _staff = r[0];
        _fieldDefs = r[1].where((f) => f['category'] == 'customer').toList();
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

  Map<String, String> get _initialCustom {
    final list = widget.customer?['customFields'];
    if (list is! List) return const {};
    return {for (final f in list) if (f is Map) GeoUi.s(f['fieldId']): GeoUi.s(f['value'])};
  }

  num? _num(String v) => v.trim().isEmpty ? null : num.tryParse(v.trim());

  Future<void> _save() async {
    String? err;
    final required = {
      'Contact name': _name,
      'Mobile': _mobile,
      'Email': _email,
      'Company name': _company,
      'PIN code': _pin,
      'City': _city,
      'State': _state,
      'Address': _address,
    };
    for (final e in required.entries) {
      if (e.value.text.trim().isEmpty || (e.key == 'Mobile' && e.value.text.trim().length < 6)) {
        err = '${e.key} is required.';
        break;
      }
    }
    if (err == null && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) err = 'Enter a valid email.';
    if (err == null &&
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

    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'mobile': _mobile.text.trim(),
      'email': _email.text.trim(),
      'companyName': _company.text.trim(),
      'pinCode': _pin.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'address': _address.text.trim(),
      'assignedEmployees': _assigned.toList(),
      'status': _status,
      'latitude': ?_num(_lat.text),
      'longitude': ?_num(_lng.text),
      'radius': _num(_radius.text) ?? 10,
      if (_customKey.currentState != null) 'customFields': _customKey.currentState!.values,
    };

    setState(() => _saving = true);
    try {
      if (_editing) {
        await AdminGeoService.instance.updateCustomer(GeoUi.s(widget.customer!['id']), body);
      } else {
        await AdminGeoService.instance.createCustomer(body);
      }
      if (!mounted) return;
      GeoUi.ok(context, _editing ? 'Customer updated.' : 'Customer added.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar(_editing ? 'Edit customer' : 'Add customer'),
      body: _loading
          ? GeoUi.loading
          : _error != null
              ? GeoUi.error(_error!, _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    GeoUi.card(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _field(_company, 'Company name *'),
                        _field(_name, 'Contact name *'),
                        _field(_mobile, 'Mobile (with country code) *', kb: TextInputType.phone),
                        _field(_email, 'Email *', kb: TextInputType.emailAddress),
                      ]),
                    ),
                    GeoUi.card(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _field(_address, 'Address *', lines: 2),
                        Row(children: [
                          Expanded(child: _field(_city, 'City *')),
                          const SizedBox(width: 12),
                          Expanded(child: _field(_state, 'State *')),
                        ]),
                        _field(_pin, 'PIN code *', kb: TextInputType.number),
                        Row(children: [
                          Expanded(child: _field(_lat, 'Latitude', kb: const TextInputType.numberWithOptions(decimal: true, signed: true))),
                          const SizedBox(width: 12),
                          Expanded(child: _field(_lng, 'Longitude', kb: const TextInputType.numberWithOptions(decimal: true, signed: true))),
                        ]),
                        _field(_radius, 'Geofence radius (m)', kb: TextInputType.number),
                        if (_editing)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              initialValue: _status,
                              decoration: GeoUi.input('Status'),
                              items: [for (final s in _statuses) DropdownMenuItem(value: s, child: Text(s))],
                              onChanged: (v) => setState(() => _status = v ?? _status),
                            ),
                          ),
                      ]),
                    ),
                    if (_fieldDefs.isNotEmpty)
                      GeoUi.card(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: GeoCustomFieldsForm(key: _customKey, defs: _fieldDefs, initial: _initialCustom),
                      ),
                    _staffPicker(),
                    const SizedBox(height: 8),
                    GeoUi.primaryButton(_editing ? 'Save changes' : 'Add customer', _save, busy: _saving),
                  ],
                ),
    );
  }

  Widget _field(TextEditingController c, String label, {TextInputType? kb, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, keyboardType: kb, maxLines: lines, decoration: GeoUi.input(label)),
      );

  Widget _staffPicker() {
    final q = _staffQuery.toLowerCase();
    final list = _staff
        .where((s) => q.isEmpty || GeoUi.s(s['name']).toLowerCase().contains(q) || GeoUi.s(s['employeeId']).toLowerCase().contains(q))
        .toList();
    return GeoUi.card(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Employees who can visit (${_assigned.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
        const SizedBox(height: 12),
        TextField(
          decoration: GeoUi.input('Search employees', suffix: const Icon(Icons.search_rounded, size: 20)),
          onChanged: (v) => setState(() => _staffQuery = v.trim()),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('No employees found.', style: TextStyle(fontSize: 13, color: GeoUi.muted)))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in list)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primary,
                    value: _assigned.contains(GeoUi.s(s['id'])),
                    onChanged: (v) => setState(() => v == true ? _assigned.add(GeoUi.s(s['id'])) : _assigned.remove(GeoUi.s(s['id']))),
                    title: Text(GeoUi.s(s['name']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: GeoUi.ink)),
                    subtitle: Text('${GeoUi.s(s['employeeId'])} · ${GeoUi.s(s['department'])}${s['type'] != null ? ' · ${s['type']}' : ''}'),
                  ),
              ],
            ),
          ),
      ]),
    );
  }
}
