// Admin GEO: one employee's day timeline — punch in, task start, field in / out, exits and
// punch out, the tracked movement between them on a map, the task on hand and the day's tasks.
// Location records of a segment load on demand.
// HRMSbackend GET /api/admin/hrms-geo/tracking/timeline/:staffId?date= and
// GET /api/admin/hrms-geo/tracking/timeline/:staffId/locations?from&to.

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import '../../../widgets/travelled_route_style.dart';
import 'geo_admin_ui.dart';

class AdminGeoTimelineScreen extends StatefulWidget {
  const AdminGeoTimelineScreen({super.key, required this.staffId, this.staffName, this.initialDay});

  final String staffId;
  final String? staffName;
  final DateTime? initialDay;

  @override
  State<AdminGeoTimelineScreen> createState() => _AdminGeoTimelineScreenState();
}

class _AdminGeoTimelineScreenState extends State<AdminGeoTimelineScreen> {
  late DateTime _day;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final d = widget.initialDay ?? now;
    _day = DateTime(d.year, d.month, d.day);
    _load();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await AdminGeoService.instance.getTimeline(widget.staffId, AdminGeoService.dayKey(_day));
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
      _fitAll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic> get _activity =>
      _data?['activity'] is Map ? Map<String, dynamic>.from(_data!['activity'] as Map) : <String, dynamic>{};

  List<Map<String, dynamic>> _listOf(dynamic v) =>
      v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get _events => _listOf(_activity['events']);
  List<Map<String, dynamic>> get _segments => _listOf(_activity['segments']);

  List<LatLng> _segPoints(Map<String, dynamic> seg) {
    final display = _listOf(seg['displayPath']);
    final raw = display.isNotEmpty ? display : _listOf(seg['path']);
    return [
      for (final p in raw)
        if (p['lat'] is num && p['lng'] is num) LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
    ];
  }

  LatLng? _eventPos(Map<String, dynamic> e) =>
      e['latitude'] is num && e['longitude'] is num && !(e['latitude'] == 0 && e['longitude'] == 0)
          ? LatLng((e['latitude'] as num).toDouble(), (e['longitude'] as num).toDouble())
          : null;

  Set<Polyline> get _polylines {
    final out = <Polyline>{};
    var i = 0;
    for (final s in _segments) {
      final pts = _segPoints(s);
      if (pts.length < 2) continue;
      if (s['kind'] == 'on_site') {
        out.add(Polyline(polylineId: PolylineId('seg${i++}'), points: pts, color: GeoUi.accent, width: 4, zIndex: 1));
      } else {
        out.add(TravelledRouteStyle.polyline('seg${i++}', pts));
      }
    }
    return out;
  }

  double _hue(String type) => switch (type) {
        'punch_in' => BitmapDescriptor.hueGreen,
        'punch_out' => BitmapDescriptor.hueRed,
        'field_in' => BitmapDescriptor.hueAzure,
        'field_out' => BitmapDescriptor.hueViolet,
        'task_exit' => BitmapDescriptor.hueRose,
        _ => BitmapDescriptor.hueOrange,
      };

  Set<Marker> get _markers {
    final out = <Marker>{};
    for (final e in _events) {
      final pos = _eventPos(e);
      if (pos == null) continue;
      out.add(Marker(
        markerId: MarkerId('ev${e['seq']}'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(_hue(GeoUi.s(e['type']))),
        infoWindow: InfoWindow(title: _eventTitle(e), snippet: GeoUi.time(e['at'])),
      ));
    }
    final last = _activity['lastPoint'];
    if (_isToday && last is Map && last['lat'] is num && last['lng'] is num) {
      out.add(Marker(
        markerId: const MarkerId('last'),
        position: LatLng((last['lat'] as num).toDouble(), (last['lng'] as num).toDouble()),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: InfoWindow(title: 'Latest position', snippet: GeoUi.time(last['t'])),
      ));
    }
    return out;
  }

  List<LatLng> get _allPoints => [
        for (final m in _markers) m.position,
        for (final s in _segments) ..._segPoints(s),
      ];

  void _fitAll() => _fitTo(_allPoints);

  void _fitTo(List<LatLng> pts) {
    if (_map == null || pts.isEmpty) return;
    if (pts.length == 1) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    var s = pts.first.latitude, n = s, w = pts.first.longitude, e = w;
    for (final p in pts) {
      if (p.latitude < s) s = p.latitude;
      if (p.latitude > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    Future.delayed(const Duration(milliseconds: 250), () {
      _map?.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)), 48));
    });
  }

  String _eventTitle(Map<String, dynamic> e) {
    final task = GeoUi.s(e['taskTitle']);
    final num = GeoUi.s(e['taskNumber']);
    final t = task.isEmpty ? '' : ' · $task${num.isNotEmpty ? ' ($num)' : ''}';
    return switch (GeoUi.s(e['type'])) {
      'punch_in' => 'Punch In',
      'punch_out' => 'Punch Out',
      'task_start' => 'Task started$t',
      'field_in' => 'Field In$t',
      'field_out' => 'Field Out$t',
      'task_exit' => 'Task exited$t',
      _ => GeoUi.s(e['type'])
    };
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _day = DateTime(picked.year, picked.month, picked.day);
      _load();
    }
  }

  void _shift(int delta) {
    final next = _day.add(Duration(days: delta));
    final n = DateTime.now();
    if (next.isAfter(DateTime(n.year, n.month, n.day))) return;
    _day = next;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final staff = _data?['staff'] is Map ? Map<String, dynamic>.from(_data!['staff'] as Map) : <String, dynamic>{};
    final name = GeoUi.s(staff['name'], widget.staffName ?? 'Employee');
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('$name · Timeline', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        _dayBar(),
        if (_loading)
          const Expanded(child: GeoUi.loading)
        else if (_error != null)
          Expanded(child: GeoUi.error(_error!, _load))
        else ...[
          Expanded(
            flex: 5,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                  target: _allPoints.isNotEmpty ? _allPoints.first : const LatLng(20.5937, 78.9629),
                  zoom: _allPoints.isNotEmpty ? 13 : 4),
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (c) {
                _map = c;
                _fitAll();
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          Expanded(flex: 6, child: _panel(staff)),
        ],
      ]),
    );
  }

  Widget _dayBar() => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: GeoUi.line)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(children: [
          IconButton(tooltip: 'Previous day', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: InkWell(
              onTap: _pickDay,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.brandDark),
                  const SizedBox(width: 8),
                  Text(
                    _isToday ? 'Today, ${DateFormat('d MMM yyyy').format(_day)}' : DateFormat('EEE, d MMM yyyy').format(_day),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink),
                  ),
                ]),
              ),
            ),
          ),
          IconButton(tooltip: 'Next day', onPressed: _isToday ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      );

  Widget _panel(Map<String, dynamic> staff) {
    final active = _data?['activeTask'] is Map ? Map<String, dynamic>.from(_data!['activeTask'] as Map) : null;
    final tasks = _listOf(_data?['tasks']);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: GeoUi.line)),
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              [GeoUi.s(staff['employeeId']), GeoUi.s(staff['type']), GeoUi.s(staff['phone'])].where((e) => e.isNotEmpty).join('  ·  '),
              style: const TextStyle(fontSize: 12.5, color: GeoUi.muted),
            ),
            const SizedBox(height: 4),
            Text('${GeoUi.n(_activity['totalKm'])} km tracked · ${_events.length} events',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GeoUi.ink)),
            if (active != null) ...[
              const SizedBox(height: 12),
              _taskCard(active, live: true),
            ],
            const SizedBox(height: 16),
            GeoUi.sectionTitle('Activity'),
            if (_events.isEmpty)
              const Text('No activity recorded for this day.', style: TextStyle(fontSize: 13, color: GeoUi.muted))
            else
              ..._timelineRows(),
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              GeoUi.sectionTitle('Tasks (${tasks.length})'),
              ...tasks.map((t) => _taskCard(t)),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _timelineRows() {
    final rows = <Widget>[];
    final segByFrom = <int, Map<String, dynamic>>{};
    for (final s in _segments) {
      final f = s['fromSeq'];
      if (f is num) segByFrom[f.toInt()] = s;
    }
    for (final e in _events) {
      final pos = _eventPos(e);
      rows.add(ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.brandLight,
          child: Text('${e['seq'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandDark)),
        ),
        title: Text(_eventTitle(e), style: const TextStyle(fontWeight: FontWeight.w600, color: GeoUi.ink, fontSize: 14)),
        subtitle: GeoUi.s(e['address']).isEmpty
            ? null
            : Text(GeoUi.s(e['address']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: GeoUi.muted)),
        trailing: Text(GeoUi.time(e['at']), style: const TextStyle(fontSize: 12, color: GeoUi.muted)),
        onTap: pos == null ? null : () => _map?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16)),
      ));
      final seg = e['seq'] is num ? segByFrom[(e['seq'] as num).toInt()] : null;
      if (seg != null) rows.add(_segmentRow(seg));
    }
    return rows;
  }

  Widget _segmentRow(Map<String, dynamic> seg) {
    final start = DateTime.tryParse(GeoUi.s(seg['startAt']));
    final end = DateTime.tryParse(GeoUi.s(seg['endAt']));
    final mins = start != null && end != null ? end.difference(start).inMinutes : null;
    final onSite = seg['kind'] == 'on_site';
    final canLoad = start != null && end != null && end.isAfter(start);
    return Container(
      margin: const EdgeInsets.only(left: 13, bottom: 4),
      padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: onSite ? GeoUi.accent : TravelledRouteStyle.color, width: 2))),
      child: Row(children: [
        Icon(onSite ? Icons.store_mall_directory_outlined : Icons.directions_rounded, size: 16, color: GeoUi.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${onSite ? 'On site' : 'Travel'} · ${GeoUi.n(seg['distanceKm'])} km${mins != null ? ' · $mins min' : ''}${seg['toSeq'] == null ? ' · ongoing' : ''}',
            style: const TextStyle(fontSize: 12, color: GeoUi.muted),
          ),
        ),
        TextButton(
          onPressed: canLoad
              ? () {
                  final pts = _segPoints(seg);
                  if (pts.isNotEmpty) _fitTo(pts);
                  _showLocations(start.toUtc().toIso8601String(), end.toUtc().toIso8601String());
                }
              : null,
          child: const Text('Locations', style: TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }

  Future<void> _showLocations(String from, String to) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, controller) => _LocationsSheet(staffId: widget.staffId, from: from, to: to, controller: controller),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> t, {bool live = false}) {
    final status = GeoUi.s(t['status']);
    return GeoUi.card(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (live) ...[GeoUi.pill('NOW', AppColors.successBg, AppColors.success), const SizedBox(width: 6)],
          Expanded(
            child: Text(GeoUi.s(t['title'], 'Task'), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          ),
          if (status.isNotEmpty) ...[const SizedBox(width: 8), GeoUi.statusPill(status)],
        ]),
        const SizedBox(height: 6),
        Text(
          [
            GeoUi.s(t['taskIdStr']),
            GeoUi.s(t['taskType']),
            GeoUi.s(t['locationName']),
          ].where((e) => e.isNotEmpty).join('  ·  '),
          style: const TextStyle(fontSize: 12.5, color: GeoUi.muted),
        ),
        Text(
          '${GeoUi.s(t['startTime'], '—')} → ${GeoUi.s(t['endTime'], '—')}  ·  ${GeoUi.n(t['distanceKm'])} km',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: GeoUi.ink),
        ),
        if (GeoUi.s(t['address']).isNotEmpty)
          Text(GeoUi.s(t['address']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
      ]),
    );
  }
}

class _LocationsSheet extends StatefulWidget {
  const _LocationsSheet({required this.staffId, required this.from, required this.to, required this.controller});
  final String staffId;
  final String from;
  final String to;
  final ScrollController controller;

  @override
  State<_LocationsSheet> createState() => _LocationsSheetState();
}

class _LocationsSheetState extends State<_LocationsSheet> {
  List<Map<String, dynamic>>? _points;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _points = null;
    });
    try {
      final p = await AdminGeoService.instance.getTimelineLocations(widget.staffId, from: widget.from, to: widget.to);
      if (!mounted) return;
      setState(() => _points = p);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return GeoUi.error(_error!, _load);
    if (_points == null) return GeoUi.loading;
    if (_points!.isEmpty) return GeoUi.message(Icons.location_off_outlined, 'No records', 'No location records in this period.');
    return ListView.separated(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _points!.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1, color: GeoUi.line),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${_points!.length} location records',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          );
        }
        final p = _points![i - 1];
        final speed = p['speed'];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(GeoUi.s(p['address'], '${p['lat']}, ${p['lng']}'),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: GeoUi.ink)),
          subtitle: Text(
            [
              GeoUi.s(p['movementType']),
              if (speed is num) '${speed.toStringAsFixed(1)} m/s',
              if (p['batteryPercent'] is num) '${(p['batteryPercent'] as num).toInt()}% battery',
              if (p['accuracy'] is num) '±${(p['accuracy'] as num).toInt()} m',
              GeoUi.s(p['taskNumber']),
            ].where((e) => e.isNotEmpty).join('  ·  '),
            style: const TextStyle(fontSize: 12, color: GeoUi.muted),
          ),
          trailing: Text(GeoUi.time(p['t']), style: const TextStyle(fontSize: 12, color: GeoUi.muted)),
        );
      },
    );
  }
}
