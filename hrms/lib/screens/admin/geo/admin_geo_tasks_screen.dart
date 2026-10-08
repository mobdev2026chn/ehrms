// Admin GEO: every field task, filtered by status, type and search, with create (internal or
// external), and a tap-through to the task's details. HRMSbackend GET /api/admin/hrms-geo/task.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'admin_geo_task_detail_screen.dart';
import 'admin_geo_task_form_screen.dart';
import 'geo_admin_ui.dart';

class AdminGeoTasksScreen extends StatefulWidget {
  const AdminGeoTasksScreen({super.key});

  @override
  State<AdminGeoTasksScreen> createState() => _AdminGeoTasksScreenState();
}

class _AdminGeoTasksScreenState extends State<AdminGeoTasksScreen> {
  static const _statuses = ['All', 'Assigned', 'Started', 'Pending', 'Requested', 'Completed', 'Hold', 'Exited', 'Expired'];
  static const _types = ['All', 'Internal', 'External'];

  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String? _error;
  String _status = 'All';
  String _type = 'All';
  String _search = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // "Expired" is derived from the end date (a stored Assigned / Pending / Requested task),
      // so it is filtered here rather than by the server.
      final list = await AdminGeoService.instance.getTasks(
        status: _status == 'Expired' ? null : _status,
        type: _type,
        search: _search,
      );
      if (!mounted) return;
      setState(() {
        _tasks = _status == 'All' ? list : list.where((t) => GeoUi.s(t['status']) == _status).toList();
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

  void _reload() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _create() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('New task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GeoUi.ink))),
          ListTile(
            leading: GeoUi.iconTile(Icons.apartment_rounded, size: 40),
            title: const Text('Internal task'),
            subtitle: const Text('Visit to a company branch'),
            onTap: () => Navigator.pop(ctx, 'Internal'),
          ),
          ListTile(
            leading: GeoUi.iconTile(Icons.storefront_outlined, size: 40),
            title: const Text('External task'),
            subtitle: const Text('Visit to a customer'),
            onTap: () => Navigator.pop(ctx, 'External'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (type == null || !mounted) return;
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AdminGeoTaskFormScreen(taskType: type)));
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Tasks', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh_rounded)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            TextField(
              decoration: GeoUi.input('Search ID, title, staff, customer, branch', suffix: const Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 450), () {
                  _search = v.trim();
                  _reload();
                });
              },
            ),
            const SizedBox(height: 10),
            GeoUi.choiceChips<String>(values: _types, selected: _type, label: (t) => t == 'All' ? 'All types' : t, onSelected: (t) {
              _type = t;
              _reload();
            }),
            const SizedBox(height: 10),
            GeoUi.choiceChips<String>(values: _statuses, selected: _status, label: (t) => t == 'All' ? 'All statuses' : t, onSelected: (t) {
              _status = t;
              _reload();
            }),
          ]),
        ),
        Expanded(
          child: _loading
              ? GeoUi.loading
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _error != null
                      ? GeoUi.error(_error!, _reload)
                      : _tasks.isEmpty
                          ? GeoUi.message(Icons.assignment_outlined, 'No tasks', 'Nothing matches the filters.')
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                              children: _tasks.map(_card).toList(),
                            ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> t) {
    final where = t['type'] == 'Internal' ? GeoUi.s(t['branch']) : GeoUi.s(t['customerName']);
    return GeoUi.card(
      onTap: () async {
        final changed = await Navigator.of(context)
            .push<bool>(MaterialPageRoute(builder: (_) => AdminGeoTaskDetailScreen(taskId: GeoUi.s(t['_id']))));
        if (changed == true) _reload();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(GeoUi.s(t['title'], 'Task'), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          ),
          const SizedBox(width: 8),
          GeoUi.statusPill(GeoUi.s(t['status'])),
        ]),
        const SizedBox(height: 4),
        Text(
          [GeoUi.s(t['id']), GeoUi.s(t['type']), if (t['autoGenerated'] == true) 'Auto branch visit'].where((e) => e.isNotEmpty).join('  ·  '),
          style: const TextStyle(fontSize: 12.5, color: GeoUi.muted),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.person_outline_rounded, size: 16, color: GeoUi.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(GeoUi.s(t['staffName'], '—'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: GeoUi.ink))),
          if (where.isNotEmpty) ...[
            Icon(t['type'] == 'Internal' ? Icons.apartment_rounded : Icons.storefront_outlined, size: 16, color: GeoUi.muted),
            const SizedBox(width: 6),
            Flexible(child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: GeoUi.ink))),
          ],
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.event_outlined, size: 16, color: GeoUi.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${GeoUi.date(t['startDate'])} → ${GeoUi.date(t['endDate'])}',
                style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
          ),
        ]),
      ]),
    );
  }
}
