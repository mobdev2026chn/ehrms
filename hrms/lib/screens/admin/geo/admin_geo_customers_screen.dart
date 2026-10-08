// Admin GEO: customers (sites for external tasks), searchable and filterable by status, with add
// and a tap-through to details. HRMSbackend GET /api/admin/hrms-geo/customer.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'admin_geo_customer_detail_screen.dart';
import 'admin_geo_customer_form_screen.dart';
import 'geo_admin_ui.dart';

class AdminGeoCustomersScreen extends StatefulWidget {
  const AdminGeoCustomersScreen({super.key});

  @override
  State<AdminGeoCustomersScreen> createState() => _AdminGeoCustomersScreenState();
}

class _AdminGeoCustomersScreenState extends State<AdminGeoCustomersScreen> {
  static const _statuses = ['All', 'Assigned', 'In Progress', 'Completed', 'Hold', 'Reopened', 'Exited'];

  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _status = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await AdminGeoService.instance.getCustomers();
      if (!mounted) return;
      setState(() {
        _all = list;
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

  List<Map<String, dynamic>> get _visible {
    final q = _query.toLowerCase();
    return _all.where((c) {
      if (_status != 'All' && GeoUi.s(c['status']) != _status) return false;
      if (q.isEmpty) return true;
      return [c['name'], c['companyName'], c['mobile'], c['email'], c['city']]
          .any((v) => GeoUi.s(v).toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AdminGeoCustomerFormScreen()));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Customers', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Add customer', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            TextField(
              decoration: GeoUi.input('Search name, company, phone, city', suffix: const Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 12),
            GeoUi.choiceChips<String>(values: _statuses, selected: _status, label: (s) => s, onSelected: (s) => setState(() => _status = s)),
          ]),
        ),
        Expanded(
          child: _loading
              ? GeoUi.loading
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _error != null
                      ? GeoUi.error(_error!, _load)
                      : _visible.isEmpty
                          ? GeoUi.message(Icons.storefront_outlined, 'No customers', _all.isEmpty ? 'Add your first customer.' : 'Nothing matches the filters.')
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                              children: _visible.map(_card).toList(),
                            ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final assigned = c['assignedEmployees'] is List ? (c['assignedEmployees'] as List).length : 0;
    return GeoUi.card(
      onTap: () async {
        final changed = await Navigator.of(context)
            .push<bool>(MaterialPageRoute(builder: (_) => AdminGeoCustomerDetailScreen(customerId: GeoUi.s(c['id']))));
        if (changed == true) _load();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GeoUi.iconTile(Icons.storefront_outlined, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(GeoUi.s(c['companyName'], 'Customer'), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          ),
          const SizedBox(width: 8),
          if (GeoUi.s(c['status']).isNotEmpty) GeoUi.statusPill(GeoUi.s(c['status'])),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.person_outline_rounded, size: 16, color: GeoUi.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${GeoUi.s(c['name'])}  ·  ${GeoUi.s(c['mobile'])}',
                style: const TextStyle(fontSize: 13, color: GeoUi.ink)),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.place_outlined, size: 16, color: GeoUi.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${GeoUi.s(c['city'])}, ${GeoUi.s(c['state'])}  ·  $assigned staff assigned',
                style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
          ),
        ]),
      ]),
    );
  }
}
