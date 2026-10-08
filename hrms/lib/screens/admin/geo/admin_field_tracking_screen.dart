// Admin GEO dashboard: today's field figures and task status, a live map of the staff who are
// punched in, the list of staff out now, the day's recent activity and shortcuts to the rest of
// HRMS GEO. Data from HRMSbackend /api/admin/hrms-geo/tracking/{dashboard,live} (admins only).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../widgets/app_card.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import '../../geo/my_day_route_screen.dart';
import 'admin_geo_customers_screen.dart';
import 'admin_geo_settings_screen.dart';
import 'admin_geo_tasks_screen.dart';
import 'admin_geo_timeline_screen.dart';
import 'admin_geo_tracking_details_screen.dart';
import 'admin_geo_tracking_summary_screen.dart';
import 'admin_travel_allowance_screen.dart';
import 'geo_admin_ui.dart';

class AdminFieldTrackingScreen extends StatefulWidget {
  const AdminFieldTrackingScreen({super.key});

  @override
  State<AdminFieldTrackingScreen> createState() => _AdminFieldTrackingScreenState();
}

class _AdminFieldTrackingScreenState extends State<AdminFieldTrackingScreen> {
  static const _accent = GeoUi.accent;
  static const _ink = GeoUi.ink;
  static const _muted = GeoUi.muted;

  Map<String, dynamic>? _dash;
  List<Map<String, dynamic>> _live = [];
  String? _dashError;
  String? _liveError;
  bool _loading = true;
  Timer? _timer;
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    _load();
    // Positions move; refresh the live list every minute while the screen is open.
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _loadLive());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([_loadDash(), _loadLive()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadDash() async {
    try {
      final d = await AdminGeoService.instance.getDashboard();
      if (!mounted) return;
      setState(() {
        _dash = d;
        _dashError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _dashError = e.toString());
    }
  }

  Future<void> _loadLive() async {
    try {
      final r = await AdminGeoService.instance.getLive();
      if (!mounted) return;
      setState(() {
        _live = r.items;
        _liveError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _liveError = e.toString());
    }
  }

  num _n(dynamic v) => GeoUi.n(v);

  List<Map<String, dynamic>> get _located =>
      _live.where((d) => d['latitude'] is num && d['longitude'] is num).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Field Tracking', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: _loading
          ? GeoUi.loading
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_dashError != null && _dash == null)
                    _errorBox(_dashError!)
                  else
                    _summary(),
                  const SizedBox(height: 16),
                  _shortcuts(),
                  const SizedBox(height: 16),
                  GeoUi.sectionTitle('Live map', trailing: Text('${_located.length} located', style: const TextStyle(fontSize: 12, color: _muted))),
                  _liveMap(),
                  const SizedBox(height: 20),
                  Row(children: [
                    const Text('Out now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
                    const SizedBox(width: 8),
                    GeoUi.pill('${_live.length}', AppColors.brandLight, AppColors.brandDark),
                  ]),
                  const SizedBox(height: 12),
                  if (_liveError != null && _live.isEmpty)
                    _errorBox(_liveError!)
                  else if (_live.isEmpty)
                    _emptyBox(Icons.location_off_outlined, 'No field staff out', 'Nobody is punched in right now.')
                  else
                    ..._live.map(_liveCard),
                  const SizedBox(height: 16),
                  _activities(),
                ],
              ),
            ),
    );
  }

  Widget _summary() {
    final d = _dash ?? {};
    final ts = d['taskStatus'] is Map ? Map<String, dynamic>.from(d['taskStatus'] as Map) : <String, dynamic>{};
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceDark, AppColors.ink],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.public_rounded, size: 18, color: _accent),
            ),
            const SizedBox(width: 10),
            const Text('Field overview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            const Spacer(),
            Text('Today', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _tile('Field staff', '${_n(d['totalFieldEmployees'])}', Icons.groups_outlined),
            _vline(),
            _tile('Tasks', '${_n(d['totalTasksToday'])}', Icons.assignment_outlined),
            _vline(),
            _tile('Distance', '${_n(d['totalDistanceKm'])}', Icons.route_outlined, unit: 'km'),
            _vline(),
            _tile('Claims', '${_n(d['pendingClaims'])}', Icons.currency_rupee_rounded),
          ]),
          const SizedBox(height: 14),
          Text('Task status · ${_n(d['pendingTasks'])} pending',
              style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip('Assigned', ts['assigned'], const Color(0xFF60A5FA)),
            _chip('In progress', ts['inProgress'], _accent),
            _chip('Hold', ts['hold'], const Color(0xFF94A3B8)),
            _chip('Completed', ts['completed'], const Color(0xFF34D399)),
            _chip('Exited', ts['exited'], const Color(0xFFF87171)),
          ]),
        ],
      ),
    );
  }

  Widget _vline() => Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.08));

  Widget _tile(String label, String value, IconData icon, {String? unit}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(icon, size: 16, color: _accent),
          const SizedBox(height: 7),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              text: value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
              children: unit != null
                  ? [TextSpan(text: ' $unit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.6)))]
                  : null,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65))),
        ]),
      );

  Widget _chip(String label, dynamic value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label ${_n(value).toInt()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  Widget _shortcuts() {
    final items = <(IconData, String, Widget Function())>[
      (Icons.badge_outlined, 'Employees', () => const AdminGeoTrackingSummaryScreen()),
      (Icons.task_alt_rounded, 'Tasks', () => const AdminGeoTasksScreen()),
      (Icons.storefront_outlined, 'Customers', () => const AdminGeoCustomersScreen()),
      (Icons.currency_rupee_rounded, 'Allowance', () => const AdminTravelAllowanceScreen()),
      (Icons.tune_rounded, 'Settings', () => const AdminGeoSettingsScreen()),
    ];
    return Row(
      children: [
        for (final it in items)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => it.$3())).then((_) => _load()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: GeoUi.line),
                      boxShadow: kSoftCardShadow,
                    ),
                    child: Icon(it.$1, size: 22, color: AppColors.brandDark),
                  ),
                  const SizedBox(height: 6),
                  Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ink)),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _liveMap() {
    final pts = _located;
    if (pts.isEmpty) {
      return GeoUi.card(
        child: const SizedBox(
          height: 80,
          child: Center(child: Text('No live locations yet today.', style: TextStyle(color: _muted))),
        ),
      );
    }
    final markers = <Marker>{
      for (final d in pts)
        Marker(
          markerId: MarkerId(GeoUi.s(d['staffId'])),
          position: LatLng((d['latitude'] as num).toDouble(), (d['longitude'] as num).toDouble()),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              d['isLive'] == true ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: GeoUi.s(d['staffName'], 'Staff'),
            snippet: [
              if (GeoUi.s(d['taskTitle']).isNotEmpty) GeoUi.s(d['taskTitle']),
              'Seen ${GeoUi.time(d['timestamp'])}',
            ].join(' · '),
            onTap: () => _openStaff(d),
          ),
        ),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 240,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: markers.first.position, zoom: 12),
          markers: markers,
          onMapCreated: (c) {
            _map = c;
            _fit(markers.map((m) => m.position).toList());
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
        ),
      ),
    );
  }

  void _fit(List<LatLng> pts) {
    if (_map == null || pts.length < 2) return;
    var s = pts.first.latitude, n = s, w = pts.first.longitude, e = w;
    for (final p in pts) {
      if (p.latitude < s) s = p.latitude;
      if (p.latitude > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    Future.delayed(const Duration(milliseconds: 300), () {
      _map?.animateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)), 40));
    });
  }

  void _openStaff(Map<String, dynamic> d) {
    final staffId = GeoUi.s(d['staffId']);
    final name = GeoUi.s(d['staffName'], 'Staff');
    if (staffId.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _ink))),
          ListTile(
            leading: GeoUi.iconTile(Icons.timeline_rounded, size: 40),
            title: const Text('Timeline'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminGeoTimelineScreen(staffId: staffId, staffName: name)));
            },
          ),
          ListTile(
            leading: GeoUi.iconTile(Icons.route_rounded, size: 40),
            title: const Text('Day route'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyDayRouteScreen(staffId: staffId, staffName: name)));
            },
          ),
          ListTile(
            leading: GeoUi.iconTile(Icons.analytics_outlined, size: 40),
            title: const Text('Tracking details & allowance'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminGeoTrackingDetailsScreen(staffId: staffId, staffName: name)));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _liveCard(Map<String, dynamic> d) {
    final name = GeoUi.s(d['staffName'], 'Staff');
    final empId = GeoUi.s(d['employeeId']);
    final source = GeoUi.s(d['locationSource']); // live | punch_in | none
    final status = GeoUi.s(d['movementType'] ?? d['status']);
    final taskTitle = GeoUi.s(d['taskTitle']);
    final taskStatus = GeoUi.s(d['taskStatus']);
    final lastSeen = d['timestamp'] != null ? GeoUi.dateTime(d['timestamp']) : '';
    final isLive = d['isLive'] == true;
    final battery = d['batteryPercent'];
    final (pillText, pillBg, pillFg) = isLive
        ? ('LIVE', AppColors.successBg, AppColors.success)
        : source == 'none'
            ? ('NO LOCATION', AppColors.inputFill, AppColors.textSecondary)
            : source == 'punch_in'
                ? ('PUNCHED IN', AppColors.warningBg, AppColors.warning)
                : ('LAST SEEN', AppColors.inputFill, AppColors.textSecondary);

    return GeoUi.card(
      padding: const EdgeInsets.all(14),
      onTap: () => _openStaff(d),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.brandLight, shape: BoxShape.circle),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.brandDark)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink))),
              const SizedBox(width: 8),
              GeoUi.pill(pillText, pillBg, pillFg),
            ]),
            const SizedBox(height: 2),
            Text(
              [
                if (empId.isNotEmpty) empId,
                if (status.isNotEmpty) status,
                if (battery is num) '${battery.toInt()}% battery',
                if (GeoUi.s(d['punchInTime']).isNotEmpty) 'In ${GeoUi.s(d['punchInTime'])}',
              ].join('  ·  '),
              style: const TextStyle(fontSize: 12.5, color: _muted),
            ),
            if (taskTitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Task: $taskTitle${taskStatus.isNotEmpty ? ' ($taskStatus)' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _ink)),
              ),
            if (GeoUi.s(d['address']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(GeoUi.s(d['address']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
              ),
            if (lastSeen.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Last seen $lastSeen', style: const TextStyle(fontSize: 12, color: _muted)),
              ),
          ]),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
      ]),
    );
  }

  Widget _activities() {
    final list = _dash?['activities'] is List
        ? [for (final a in _dash!['activities'] as List) if (a is Map) Map<String, dynamic>.from(a)]
        : <Map<String, dynamic>>[];
    IconData icon(String t) => switch (t) {
          'punch_in' => Icons.login_rounded,
          'punch_out' => Icons.logout_rounded,
          'field_in' => Icons.flag_rounded,
          'field_out' => Icons.outlined_flag_rounded,
          'task_exit' => Icons.exit_to_app_rounded,
          _ => Icons.circle_outlined,
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GeoUi.sectionTitle('Recent activity'),
      if (list.isEmpty)
        GeoUi.card(child: const Text('No activity yet today.', style: TextStyle(color: _muted)))
      else
        GeoUi.card(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final a in list)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon(GeoUi.s(a['type'])), color: AppColors.brandDark, size: 20),
                title: Text(GeoUi.s(a['text']), style: const TextStyle(fontSize: 13.5, color: _ink, fontWeight: FontWeight.w500)),
                trailing: Text(GeoUi.time(a['at']), style: const TextStyle(fontSize: 12.5, color: _muted)),
              ),
          ]),
        ),
    ]);
  }

  Widget _errorBox(String msg) => _emptyBox(Icons.wifi_off_rounded, 'Could not load', msg);

  Widget _emptyBox(IconData icon, String title, String msg) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        alignment: Alignment.center,
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: _accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 28, color: AppColors.brandDark),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
          const SizedBox(height: 4),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: _muted)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
}
