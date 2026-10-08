// Admin GEO: every employee with their completed-task distance and visit count, with links to
// their tracking details (date range, route, allowance) and day timeline.
// HRMSbackend GET /api/admin/hrms-geo/tracking/summary.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'admin_geo_timeline_screen.dart';
import 'admin_geo_tracking_details_screen.dart';
import 'geo_admin_ui.dart';

class AdminGeoTrackingSummaryScreen extends StatefulWidget {
  const AdminGeoTrackingSummaryScreen({super.key});

  @override
  State<AdminGeoTrackingSummaryScreen> createState() => _AdminGeoTrackingSummaryScreenState();
}

class _AdminGeoTrackingSummaryScreenState extends State<AdminGeoTrackingSummaryScreen> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _type = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await AdminGeoService.instance.getTrackingSummary();
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

  List<String> get _types => ['All', ...{for (final s in _all) GeoUi.s(s['type'], 'In Office')}];

  List<Map<String, dynamic>> get _visible {
    final q = _query.toLowerCase();
    return _all.where((s) {
      if (_type != 'All' && GeoUi.s(s['type'], 'In Office') != _type) return false;
      if (q.isEmpty) return true;
      return GeoUi.s(s['name']).toLowerCase().contains(q) || GeoUi.s(s['id']).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Employee Tracking', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            TextField(
              decoration: GeoUi.input('Search name or employee ID', suffix: const Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            if (_types.length > 2) ...[
              const SizedBox(height: 12),
              GeoUi.choiceChips<String>(values: _types, selected: _type, label: (t) => t, onSelected: (t) => setState(() => _type = t)),
            ],
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
                          ? GeoUi.message(Icons.person_search_outlined, 'No employees', 'Nothing matches the filters.')
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                              children: _visible.map(_card).toList(),
                            ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> s) {
    final name = GeoUi.s(s['name'], 'Employee');
    final staffId = GeoUi.s(s['_id']);
    final timeline = s['timelineTracking'] == true;
    return GeoUi.card(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminGeoTrackingDetailsScreen(staffId: staffId, staffName: name))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.brandLight,
            child: Text(name[0].toUpperCase(),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.brandDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          ),
          const SizedBox(width: 8),
          GeoUi.pill(GeoUi.s(s['type'], 'In Office').toUpperCase(), AppColors.inputFill, AppColors.textSecondary),
        ]),
        const SizedBox(height: 8),
        Text('${GeoUi.s(s['id'])}  ·  ${GeoUi.n(s['totalDistance'])} km  ·  ${GeoUi.n(s['numLocations']).toInt()} visits',
            style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
        const SizedBox(height: 4),
        const Divider(height: 16),
        Row(children: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AdminGeoTrackingDetailsScreen(staffId: staffId, staffName: name))),
            icon: const Icon(Icons.analytics_outlined, size: 18),
            label: const Text('Details'),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: timeline
                ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AdminGeoTimelineScreen(staffId: staffId, staffName: name)))
                : null,
            icon: const Icon(Icons.timeline_rounded, size: 18),
            label: Text(timeline ? 'Timeline' : 'Timeline off'),
          ),
        ]),
      ]),
    );
  }
}
