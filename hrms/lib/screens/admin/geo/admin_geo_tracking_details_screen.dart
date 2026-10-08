// Admin GEO: one employee's tracking details for a date range — punch times, battery, distance,
// the route of completed visits and each task's tracked line on a map, every task in the range,
// and the reimbursement calculation per day with approve / revise / reject.
// HRMSbackend GET /api/admin/hrms-geo/tracking/:id?startDate&endDate and
// /api/admin/hrms-geo/travel-allowance/{approve,revise,/}.

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import '../../../widgets/travelled_route_style.dart';
import 'admin_geo_timeline_screen.dart';
import 'geo_admin_ui.dart';
import 'geo_ta_actions.dart';

class AdminGeoTrackingDetailsScreen extends StatefulWidget {
  const AdminGeoTrackingDetailsScreen({super.key, required this.staffId, this.staffName, this.startDate, this.endDate});

  final String staffId;
  final String? staffName;
  final DateTime? startDate;
  final DateTime? endDate;

  @override
  State<AdminGeoTrackingDetailsScreen> createState() => _AdminGeoTrackingDetailsScreenState();
}

class _AdminGeoTrackingDetailsScreenState extends State<AdminGeoTrackingDetailsScreen> {
  late DateTime _start;
  late DateTime _end;
  Map<String, dynamic>? _rec;
  bool _loading = true;
  String? _error;
  int _tab = 0; // 0 tasks, 1 allowance
  Map<String, dynamic>? _selectedTask;
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _start = widget.startDate ?? today;
    _end = widget.endDate ?? _start;
    _load();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rec == null;
      _error = null;
    });
    try {
      final r = await AdminGeoService.instance.getTrackingDetails(widget.staffId,
          startDate: AdminGeoService.dayKey(_start), endDate: AdminGeoService.dayKey(_end));
      if (!mounted) return;
      setState(() {
        _rec = r;
        _selectedTask = null;
        _loading = false;
      });
      _fit(_routePoints);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      // Already showing an earlier range: keep it and say the refresh failed.
      if (_rec != null) GeoUi.fail(context, e);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (r == null) return;
    _start = DateTime(r.start.year, r.start.month, r.start.day);
    _end = DateTime(r.end.year, r.end.month, r.end.day);
    _rec = null; // a different range: never show the previous one under the new dates
    _load();
  }

  List<Map<String, dynamic>> _listOf(dynamic v) =>
      v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

  LatLng? _ll(dynamic lat, dynamic lng) {
    if (lat is! num || lng is! num || (lat == 0 && lng == 0)) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  List<LatLng> get _routePoints => [
        for (final p in _listOf(_rec?['route'])) ?_ll(p['lat'], p['lng']),
      ];

  List<LatLng> _taskLine(Map<String, dynamic> t) {
    final md = t['mapData'] is Map ? Map<String, dynamic>.from(t['mapData'] as Map) : <String, dynamic>{};
    return [for (final p in _listOf(md['trackingPoints'])) ?_ll(p['lat'] ?? p['latitude'], p['lng'] ?? p['longitude'])];
  }

  Set<Marker> get _markers {
    final out = <Marker>{};
    final t = _selectedTask;
    if (t != null) {
      final md = t['mapData'] is Map ? Map<String, dynamic>.from(t['mapData'] as Map) : <String, dynamic>{};
      final sp = md['startPoint'] is Map ? md['startPoint'] as Map : const {};
      final tl = md['taskLocation'] is Map ? md['taskLocation'] as Map : const {};
      final s = _ll(sp['latitude'], sp['longitude']);
      final d = _ll(tl['latitude'], tl['longitude']);
      if (s != null) {
        out.add(Marker(
          markerId: const MarkerId('start'),
          position: s,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Start', snippet: GeoUi.s(sp['address'])),
        ));
      }
      if (d != null) {
        out.add(Marker(
          markerId: const MarkerId('dest'),
          position: d,
          infoWindow: InfoWindow(title: GeoUi.s(t['businessName'], 'Destination'), snippet: GeoUi.s(tl['address'])),
        ));
      }
      return out;
    }
    var i = 0;
    for (final v in _listOf(_rec?['visits'])) {
      final p = _ll(v['lat'], v['lng']);
      if (p == null) continue;
      i++;
      out.add(Marker(
        markerId: MarkerId('v$i'),
        position: p,
        infoWindow: InfoWindow(title: '$i. ${GeoUi.s(v['businessName'], 'Visit')}', snippet: GeoUi.s(v['timeOut'])),
      ));
    }
    return out;
  }

  Set<Polyline> get _polylines {
    final t = _selectedTask;
    if (t != null) {
      final line = _taskLine(t);
      return line.length >= 2 ? {TravelledRouteStyle.polyline('task', line)} : {};
    }
    final r = _routePoints;
    return r.length >= 2
        ? {Polyline(polylineId: const PolylineId('route'), points: r, color: GeoUi.accent, width: 3, patterns: [PatternItem.dash(14), PatternItem.gap(8)])}
        : {};
  }

  void _fit(List<LatLng> pts) {
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

  void _select(Map<String, dynamic>? t) {
    setState(() => _selectedTask = t);
    _fit(t == null ? _routePoints : [..._taskLine(t), ..._markers.map((m) => m.position)]);
  }

  String get _rangeLabel {
    final f = DateFormat('d MMM yyyy');
    return _start == _end ? f.format(_start) : '${f.format(_start)} – ${f.format(_end)}';
  }

  @override
  Widget build(BuildContext context) {
    final name = GeoUi.s(_rec?['name'], widget.staffName ?? 'Employee');
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar(name, actions: [
        IconButton(
          tooltip: 'Timeline',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AdminGeoTimelineScreen(staffId: widget.staffId, staffName: name, initialDay: _end))),
          icon: const Icon(Icons.timeline_rounded),
        ),
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: GeoUi.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: InkWell(
            onTap: _pickRange,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.date_range_rounded, size: 18, color: AppColors.brandDark),
                const SizedBox(width: 8),
                Text(_rangeLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
                const Icon(Icons.arrow_drop_down_rounded, color: GeoUi.muted),
              ]),
            ),
          ),
        ),
        if (_loading)
          const Expanded(child: GeoUi.loading)
        else if (_error != null && _rec == null)
          Expanded(child: GeoUi.error(_error!, _load))
        else ...[
          SizedBox(
            height: 230,
            child: Stack(children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                    target: _routePoints.isNotEmpty ? _routePoints.first : const LatLng(20.5937, 78.9629),
                    zoom: _routePoints.isNotEmpty ? 13 : 4),
                markers: _markers,
                polylines: _polylines,
                onMapCreated: (c) {
                  _map = c;
                  _fit(_routePoints);
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
              if (_selectedTask != null)
                Positioned(
                  left: 10,
                  top: 10,
                  child: ActionChip(
                    avatar: const Icon(Icons.close_rounded, size: 16),
                    label: Text('Showing ${GeoUi.s(_selectedTask!['title'], 'task')}', overflow: TextOverflow.ellipsis),
                    onPressed: () => _select(null),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _stats(),
                  const SizedBox(height: 16),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: 0, label: Text('Tasks (${_listOf(_rec?['tasks']).length})')),
                      ButtonSegment(value: 1, label: Text('Allowance (${_listOf(_rec?['travelAllowances']).length})')),
                    ],
                    selected: {_tab},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == 0) ..._tasks() else ..._allowances(),
                ],
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _stats() {
    final r = _rec ?? {};
    Widget cell(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GeoUi.ink)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: GeoUi.muted)),
          ]),
        );
    final battery = r['battery'];
    return GeoUi.card(
      margin: EdgeInsets.zero,
      child: Column(children: [
        Text('${GeoUi.s(r['id'])}  ·  ${GeoUi.s(r['type'])}', style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Row(children: [
          cell('Punch in', GeoUi.s(r['punchIn'], '—')),
          cell('Punch out', GeoUi.s(r['punchOut'], '—')),
          cell('Battery', battery is num ? '${battery.toInt()}%' : '—'),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          cell('Distance', '${GeoUi.n(r['totalDistance'])} km'),
          cell('Visits', '${GeoUi.n(r['numLocations']).toInt()}'),
          cell('Tasks', '${_listOf(r['tasks']).length}'),
        ]),
      ]),
    );
  }

  List<Widget> _tasks() {
    final tasks = _listOf(_rec?['tasks']);
    if (tasks.isEmpty) {
      return [const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No tasks in this period.', style: TextStyle(fontSize: 13, color: GeoUi.muted))))];
    }
    return [
      for (final t in tasks)
        GeoUi.card(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          onTap: () => _taskSheet(t),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(GeoUi.s(t['title'], GeoUi.s(t['businessName'], 'Task')), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
              ),
              const SizedBox(width: 8),
              GeoUi.statusPill(GeoUi.s(t['status'])),
            ]),
            const SizedBox(height: 4),
            Text('${GeoUi.s(t['id'])}  ·  ${GeoUi.s(t['taskType'])}  ·  ${GeoUi.s(t['businessName'])}',
                style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
            Text('${GeoUi.date(t['date'])}  ·  In ${GeoUi.s(t['timeIn'], '—')}  ·  Out ${GeoUi.s(t['timeOut'], '—')}  ·  ${GeoUi.s(t['distanceFromPrev'])}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: GeoUi.ink)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _select(t),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text('Show on map (${_taskLine(t).length} pts)', style: const TextStyle(fontSize: 13)),
              ),
            ),
          ]),
        ),
    ];
  }

  void _taskSheet(Map<String, dynamic> t) {
    final proof = GeoUi.s(t['proofImg']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, c) => ListView(controller: c, padding: const EdgeInsets.fromLTRB(20, 20, 20, 24), children: [
          Text(GeoUi.s(t['title'], 'Task'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GeoUi.ink)),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          GeoUi.kv('Task ID', GeoUi.s(t['id'])),
          GeoUi.kv('Type', GeoUi.s(t['taskType'])),
          GeoUi.kv('Status', GeoUi.s(t['status'])),
          GeoUi.kv('Location', GeoUi.s(t['businessName'])),
          GeoUi.kv('Address', GeoUi.s(t['address'])),
          GeoUi.kv('Start address', GeoUi.s(t['startAddress'])),
          GeoUi.kv('Contact', '${GeoUi.s(t['contactPerson'])} ${GeoUi.s(t['contactNumber'])}'.trim()),
          GeoUi.kv('Date', GeoUi.date(t['date'])),
          GeoUi.kv('Time in', GeoUi.s(t['timeIn'])),
          GeoUi.kv('Field in', GeoUi.s(t['actualFieldInTime'])),
          GeoUi.kv('Time out', GeoUi.s(t['timeOut'])),
          GeoUi.kv('Distance', GeoUi.s(t['distanceFromPrev'])),
          GeoUi.kv('Description', GeoUi.s(t['description'])),
          if (proof.startsWith('http')) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(proof, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Text('Proof image could not be loaded.', style: TextStyle(fontSize: 13, color: GeoUi.muted))),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _select(t);
            },
            icon: const Icon(Icons.map_outlined),
            label: const Text('Show route on map'),
          ),
        ]),
      ),
    );
  }

  List<Widget> _allowances() {
    final r = _rec ?? {};
    final transport = r['assignedTransport'] is Map ? Map<String, dynamic>.from(r['assignedTransport'] as Map) : <String, dynamic>{};
    final claims = _listOf(r['travelAllowances']);
    return [
      GeoUi.card(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          GeoUi.iconTile(Icons.two_wheeler_rounded, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: transport['error'] != null
                ? Text(GeoUi.s(transport['error']), style: const TextStyle(color: AppColors.error, fontSize: 12.5))
                : Text('${GeoUi.s(transport['name'], 'Transport')} · ₹${GeoUi.n(transport['rate'])}/km',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          ),
        ]),
      ),
      if (claims.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No travel-allowance claims in this period.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: GeoUi.muted))),
        )
      else
        ...claims.map((c) => _claimCard(c, transport)),
    ];
  }

  Widget _claimCard(Map<String, dynamic> c, Map<String, dynamic> transport) {
    final status = GeoUi.s(c['status'], 'Pending');
    final date = GeoUi.s(c['date']);
    final rate = GeoUi.n(c['ratePerKm'] ?? c['transportRate'] ?? transport['rate']).toDouble();
    final dist = GeoUi.n(c['totalDistanceKm']).toDouble();
    final generated = c['generatedAmount'] is num ? (c['generatedAmount'] as num).toDouble() : dist * rate;
    final revised = c['revisedAmount'] is num ? (c['revisedAmount'] as num).toDouble() : null;
    final payable = revised ?? generated;
    final payout = c['payoutInfo'] is Map ? Map<String, dynamic>.from(c['payoutInfo'] as Map) : <String, dynamic>{};
    final immediate = payout['paymentRoute'] == 'Immediate';
    final canRevise = status != 'Rejected' && !(taIsApproved(status) && immediate);
    final staffName = GeoUi.s(_rec?['name'], widget.staffName ?? 'Employee');

    Future<void> after(bool done) async {
      if (done) await _load();
    }

    return GeoUi.card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(GeoUi.date(date), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink))),
          const SizedBox(width: 8),
          GeoUi.statusPill(status),
        ]),
        const SizedBox(height: 8),
        GeoUi.kv('Transport', GeoUi.s(c['transportName'], GeoUi.s(transport['name'], '—'))),
        GeoUi.kv('Distance', '${dist.toStringAsFixed(1)} km · ${GeoUi.n(c['tasksCount']).toInt()} tasks'),
        GeoUi.kv('Rate', '₹${rate.toStringAsFixed(2)} / km'),
        GeoUi.kv('Generated', GeoUi.money(generated)),
        if (revised != null) GeoUi.kv('Revised', GeoUi.money(revised)),
        GeoUi.kv('Payable', GeoUi.money(payable)),
        if (GeoUi.s(payout['description']).isNotEmpty) GeoUi.kv('Reason', GeoUi.s(payout['description'])),
        if (GeoUi.s(payout['paymentRoute']).isNotEmpty)
          GeoUi.kv('Paid via', [
            GeoUi.s(payout['paymentRoute']),
            GeoUi.s(payout['payrollMonth']),
            GeoUi.s(payout['upiId']),
            GeoUi.s(payout['accountNo']),
          ].where((e) => e.isNotEmpty).join(' · ')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (taIsPending(status))
            ElevatedButton.icon(
              onPressed: () async => after(await showTaApproveSheet(context,
                  staffId: widget.staffId, date: date, amount: payable, staffName: staffName, payout: _rec)),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Approve'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
            ),
          if (canRevise)
            OutlinedButton.icon(
              onPressed: () async => after(await showTaReviseDialog(context,
                  staffId: widget.staffId,
                  date: date,
                  rate: rate,
                  distance: dist,
                  amount: payable,
                  description: GeoUi.s(payout['description']))),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(revised != null ? 'Revise again' : 'Revise'),
            ),
          if (taIsPending(status))
            TextButton.icon(
              onPressed: () async => after(await showTaRejectDialog(context, staffId: widget.staffId, date: date)),
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.error),
              label: const Text('Reject', style: TextStyle(color: AppColors.error)),
            ),
        ]),
      ]),
    );
  }
}
