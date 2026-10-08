// Admin GEO: one customer — contact, address, geofence, custom fields and the employees assigned
// to visit it — with edit and delete.
// HRMSbackend GET / DELETE /api/admin/hrms-geo/customer/:id and
// GET /api/admin/hrms-geo/settings/employee-access (to name the assigned staff).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'admin_geo_customer_form_screen.dart';
import 'geo_admin_ui.dart';

class AdminGeoCustomerDetailScreen extends StatefulWidget {
  const AdminGeoCustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  State<AdminGeoCustomerDetailScreen> createState() => _AdminGeoCustomerDetailScreenState();
}

class _AdminGeoCustomerDetailScreenState extends State<AdminGeoCustomerDetailScreen> {
  Map<String, dynamic>? _c;
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([
        AdminGeoService.instance.getCustomer(widget.customerId),
        AdminGeoService.instance.getEmployeeAccess(),
      ]);
      if (!mounted) return;
      setState(() {
        _c = r[0] as Map<String, dynamic>;
        _staff = r[1] as List<Map<String, dynamic>>;
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

  Future<void> _edit() async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => AdminGeoCustomerFormScreen(customer: _c)));
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _delete() async {
    if (!await GeoUi.confirm(context, 'Delete customer', 'Delete ${GeoUi.s(_c?['companyName'], 'this customer')}? This cannot be undone.',
        action: 'Delete', destructive: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await AdminGeoService.instance.deleteCustomer(widget.customerId);
      if (!mounted) return;
      GeoUi.ok(context, 'Customer deleted.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: GeoUi.bg,
        appBar: GeoUi.appBar('Customer', actions: [
          if (_c != null) ...[
            IconButton(onPressed: _busy ? null : _edit, icon: const Icon(Icons.edit_outlined), tooltip: 'Edit'),
            IconButton(onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Delete'),
          ],
        ]),
        body: _loading
            ? GeoUi.loading
            : RefreshIndicator(onRefresh: _load, child: _error != null ? GeoUi.error(_error!, _load) : _body()),
      ),
    );
  }

  Widget _body() {
    final c = _c!;
    final ids = c['assignedEmployees'] is List ? [for (final e in c['assignedEmployees'] as List) e.toString()] : <String>[];
    final assigned = [
      for (final id in ids)
        _staff.firstWhere((s) => GeoUi.s(s['id']) == id || GeoUi.s(s['employeeId']) == id,
            orElse: () => {'name': 'Unknown employee', 'employeeId': id}),
    ];
    final custom = c['customFields'] is List
        ? [for (final f in c['customFields'] as List) if (f is Map) Map<String, dynamic>.from(f)]
        : <Map<String, dynamic>>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        GeoUi.card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GeoUi.iconTile(Icons.storefront_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text(GeoUi.s(c['companyName'], 'Customer'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GeoUi.ink))),
              const SizedBox(width: 8),
              if (GeoUi.s(c['status']).isNotEmpty) GeoUi.statusPill(GeoUi.s(c['status'])),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            GeoUi.kv('Contact', GeoUi.s(c['name'])),
            GeoUi.kv('Mobile', GeoUi.s(c['mobile'])),
            GeoUi.kv('Email', GeoUi.s(c['email'])),
            GeoUi.kv('Address', GeoUi.s(c['address'])),
            GeoUi.kv('City / State', '${GeoUi.s(c['city'])}, ${GeoUi.s(c['state'])}'),
            GeoUi.kv('PIN code', GeoUi.s(c['pinCode'])),
            GeoUi.kv('Geofence', c['latitude'] is num ? '${c['latitude']}, ${c['longitude']} · ${GeoUi.n(c['radius'])} m' : ''),
            GeoUi.kv('Created', GeoUi.date(c['createdDate'])),
          ]),
        ),
        if (custom.isNotEmpty)
          GeoUi.card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GeoUi.sectionTitle('Additional details'),
              for (final f in custom) GeoUi.kv(GeoUi.s(f['label']), GeoUi.s(f['value'])),
            ]),
          ),
        GeoUi.card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GeoUi.sectionTitle('Assigned staff (${assigned.length})'),
            if (assigned.isEmpty)
              const Text('No employees are assigned to this customer.', style: TextStyle(fontSize: 13, color: GeoUi.muted))
            else
              for (final s in assigned)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.brandLight,
                    child: Text(GeoUi.s(s['name'], '?')[0].toUpperCase(), style: const TextStyle(color: AppColors.brandDark, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(GeoUi.s(s['name']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
                  subtitle: Text([GeoUi.s(s['employeeId']), GeoUi.s(s['department']), GeoUi.s(s['type'])].where((e) => e.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 12, color: GeoUi.muted)),
                ),
          ]),
        ),
      ],
    );
  }
}
