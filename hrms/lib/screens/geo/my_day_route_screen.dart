// "My Route" — the staff member's field day on a map (HRMSbackend
// GET /staff/geo-task/day-route): flags for Punch In, each Field In / Field Out
// and Punch Out, the travelled path of every leg as the dashed green line, and
// each leg's km (Punch In → Field In 1, Field Out 1 → Field In 2, … → Punch Out).
// Distances are measured by the backend from the GPS trail and are only shown
// when tracking is enabled for the employee.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../services/task_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/travelled_route_style.dart';

class MyDayRouteScreen extends StatefulWidget {
  const MyDayRouteScreen({super.key, this.initialDay});

  final DateTime? initialDay;

  @override
  State<MyDayRouteScreen> createState() => _MyDayRouteScreenState();
}

class _Flag {
  _Flag(this.seq, this.type, this.at, this.pos, this.title, this.address);
  final int seq;
  final String type; // punch_in | field_in | field_out | punch_out
  final DateTime at;
  final LatLng? pos;
  final String title;
  final String address;
}

class _Leg {
  _Leg(this.index, this.fromLabel, this.toLabel, this.fromAt, this.toAt, this.km, this.path);
  final int index;
  final String fromLabel;
  final String toLabel;
  final DateTime fromAt;
  final DateTime toAt;
  final double? km;
  final List<LatLng> path;
}

class _MyDayRouteScreenState extends State<MyDayRouteScreen> {
  late DateTime _day;
  bool _loading = true;
  String? _error;
  bool _trackingOn = false;
  double? _totalKm;
  double? _trailKm;
  /// The whole tracked day (punch-in → punch-out / now), including time at clients.
  List<LatLng> _trail = [];
  LatLng? _lastPoint;
  DateTime? _lastPointAt;
  bool _punchedOut = false;
  List<_Flag> _flags = [];
  List<_Leg> _legs = [];
  int? _selectedLeg;
  GoogleMapController? _map;

  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);

  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDay ?? DateTime.now();
    _day = DateTime(d.year, d.month, d.day);
    _load();
    // Today, still punched in: keep the route current without resetting the map.
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && !_loading && _isToday && !_punchedOut) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'punch_in':
        return 'Punch In';
      case 'field_in':
        return 'Field In';
      case 'field_out':
        return 'Field Out';
      case 'punch_out':
        return 'Punch Out';
      default:
        return type;
    }
  }

  DateTime _parseAt(dynamic v) =>
      (DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now()).toLocal();

  /// [silent]: periodic refresh — keep the map, camera and selected leg as they are.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _selectedLeg = null;
      });
    }
    try {
      final data = await TaskService().getDayRoute(_day);
      final flags = <_Flag>[];
      for (final raw in (data['flags'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final lat = (raw['latitude'] as num?)?.toDouble();
        final lng = (raw['longitude'] as num?)?.toDouble();
        final type = raw['type']?.toString() ?? '';
        final task = (raw['taskTitle'] ?? raw['taskNumber'] ?? '').toString();
        flags.add(_Flag(
          (raw['seq'] as num?)?.toInt() ?? flags.length + 1,
          type,
          _parseAt(raw['at']),
          lat != null && lng != null ? LatLng(lat, lng) : null,
          task.isNotEmpty ? '${_typeLabel(type)} · $task' : _typeLabel(type),
          raw['address']?.toString() ?? '',
        ));
      }
      final legs = <_Leg>[];
      for (final raw in (data['legs'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final from = raw['from'] is Map ? raw['from'] as Map : const {};
        final to = raw['to'] is Map ? raw['to'] as Map : const {};
        String label(Map m) {
          final t = _typeLabel(m['type']?.toString() ?? '');
          final task = m['taskTitle']?.toString() ?? '';
          return task.isNotEmpty ? '$t ($task)' : t;
        }

        legs.add(_Leg(
          (raw['index'] as num?)?.toInt() ?? legs.length + 1,
          label(from),
          label(to),
          _parseAt(from['at']),
          _parseAt(to['at']),
          (raw['distanceKm'] as num?)?.toDouble(),
          [
            for (final p in (raw['path'] as List? ?? const []))
              if (p is Map && p['lat'] is num && p['lng'] is num)
                LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
          ],
        ));
      }
      final trail = <LatLng>[
        for (final p in (data['trail'] as List? ?? const []))
          if (p is Map && p['lat'] is num && p['lng'] is num)
            LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
      ];
      final lp = data['lastPoint'];
      if (!mounted) return;
      setState(() {
        _loading = false;
        _trackingOn = data['trackingEnabled'] == true;
        _totalKm = (data['totalKm'] as num?)?.toDouble();
        _trailKm = (data['trailKm'] as num?)?.toDouble();
        _trail = trail;
        _lastPoint = lp is Map && lp['lat'] is num && lp['lng'] is num
            ? LatLng((lp['lat'] as num).toDouble(), (lp['lng'] as num).toDouble())
            : null;
        _lastPointAt = lp is Map ? DateTime.tryParse(lp['t']?.toString() ?? '')?.toLocal() : null;
        _punchedOut = flags.any((f) => f.type == 'punch_out');
        _flags = flags;
        _legs = legs;
      });
      if (!silent) WidgetsBinding.instance.addPostFrameCallback((_) => _fitTo(null));
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = ErrorMessageUtils.toUserFriendlyMessage(e);
      });
    }
  }

  // ── Map ──

  double _hueFor(String type) {
    switch (type) {
      case 'punch_in':
        return BitmapDescriptor.hueGreen;
      case 'field_in':
        return BitmapDescriptor.hueAzure;
      case 'field_out':
        return BitmapDescriptor.hueOrange;
      case 'punch_out':
        return BitmapDescriptor.hueRed;
      default:
        return BitmapDescriptor.hueViolet;
    }
  }

  Set<Marker> get _markers => {
        // Latest position while the day is still running (today, not punched out).
        if (_lastPoint != null && _isToday && !_punchedOut)
          Marker(
            markerId: const MarkerId('now'),
            position: _lastPoint!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            infoWindow: InfoWindow(
              title: 'Latest position',
              snippet: _lastPointAt != null ? DateFormat('hh:mm a').format(_lastPointAt!) : null,
            ),
            zIndexInt: 4,
          ),
        for (final f in _flags)
          if (f.pos != null)
            Marker(
              markerId: MarkerId('flag-${f.seq}'),
              position: f.pos!,
              icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(f.type)),
              infoWindow: InfoWindow(
                title: '${f.seq}. ${f.title}',
                snippet: [
                  DateFormat('hh:mm a').format(f.at),
                  if (f.address.isNotEmpty) f.address,
                ].join(' · '),
              ),
              zIndexInt: 3,
            ),
      };

  Set<Polyline> get _polylines {
    final out = <Polyline>{
      // The whole day underneath (incl. movement at clients); legs drawn on top.
      if (_trail.length >= 2)
        Polyline(
          polylineId: const PolylineId('whole-day'),
          points: _trail,
          color: const Color(0xFF6366F1).withValues(alpha: 0.45),
          width: 4,
          jointType: JointType.round,
          zIndex: 1,
        ),
    };
    for (final l in _legs) {
      if (l.path.length < 2) continue;
      final selected = _selectedLeg == null || _selectedLeg == l.index;
      final line = TravelledRouteStyle.polyline('leg-${l.index}', l.path);
      out.add(selected ? line : line.copyWith(colorParam: TravelledRouteStyle.color.withValues(alpha: 0.25)));
    }
    return out;
  }

  Future<void> _fitTo(_Leg? leg) async {
    final map = _map;
    if (map == null) return;
    final pts = <LatLng>[
      if (leg != null) ...leg.path,
      if (leg == null) ...[for (final f in _flags) if (f.pos != null) f.pos!],
      if (leg == null) ...[for (final l in _legs) ...l.path],
      if (leg == null) ..._trail,
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      await map.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    var minLat = pts.first.latitude, maxLat = minLat, minLng = pts.first.longitude, maxLng = minLng;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    if ((maxLat - minLat).abs() < 0.0005 && (maxLng - minLng).abs() < 0.0005) {
      await map.animateCamera(CameraUpdate.newLatLngZoom(LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2), 16));
      return;
    }
    await map.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      48,
    ));
  }

  LatLng get _initialTarget {
    for (final f in _flags) {
      if (f.pos != null) return f.pos!;
    }
    for (final l in _legs) {
      if (l.path.isNotEmpty) return l.path.first;
    }
    return const LatLng(13.0827, 80.2707); // Chennai
  }

  // ── UI ──

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 40)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _day = DateTime(picked.year, picked.month, picked.day);
      _load();
    }
  }

  void _shiftDay(int delta) {
    final next = _day.add(Duration(days: delta));
    final today = DateTime.now();
    if (next.isAfter(DateTime(today.year, today.month, today.day))) return;
    _day = next;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: const Text('My Route', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
        ],
      ),
      body: Column(
        children: [
          _dayBar(),
          Expanded(
            flex: 5,
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                : GoogleMap(
                    initialCameraPosition: CameraPosition(target: _initialTarget, zoom: 13),
                    onMapCreated: (c) {
                      _map = c;
                      _fitTo(null);
                    },
                    markers: _markers,
                    polylines: _polylines,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                  ),
          ),
          Expanded(flex: 6, child: _panel()),
        ],
      ),
    );
  }

  Widget _dayBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          IconButton(onPressed: () => _shiftDay(-1), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: InkWell(
              onTap: _pickDay,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 15, color: _muted),
                    const SizedBox(width: 6),
                    Text(
                      _isToday ? 'Today, ${DateFormat('d MMM yyyy').format(_day)}' : DateFormat('EEE, d MMM yyyy').format(_day),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: _ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _isToday ? null : () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _panel() {
    if (_loading) return const SizedBox.shrink();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: _muted, size: 32),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _summary(),
          const SizedBox(height: 12),
          _legend(),
          const SizedBox(height: 14),
          if (_flags.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No punch or field activity on this day.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted),
              ),
            )
          else ...[
            if (_legs.isNotEmpty) ...[
              const Text('Legs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 8),
              for (final l in _legs) _legTile(l),
              const SizedBox(height: 14),
            ],
            const Text('Timeline', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 8),
            for (final f in _flags) _flagTile(f),
          ],
        ],
      ),
    );
  }

  Widget _summary() {
    final km = _totalKm;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _trackingOn ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _trackingOn ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            _trackingOn ? Icons.route_rounded : Icons.location_off_outlined,
            color: _trackingOn ? const Color(0xFF059669) : _muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _trackingOn ? 'Distance travelled' : 'Tracking is off',
                  style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _trackingOn
                      ? '${(km ?? 0).toStringAsFixed(1)} km · ${_legs.length} leg${_legs.length == 1 ? '' : 's'}'
                      : 'Distance is not recorded for this employee',
                  style: TextStyle(
                    fontSize: _trackingOn ? 18 : 13,
                    fontWeight: FontWeight.w900,
                    color: _trackingOn ? const Color(0xFF047857) : _ink,
                  ),
                ),
                if (_trackingOn && _trailKm != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Whole day tracked: ${_trailKm!.toStringAsFixed(1)} km (incl. movement at clients)',
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, size: 16, color: c),
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        dot(const Color(0xFF16A34A), 'Punch In'),
        dot(const Color(0xFF0EA5E9), 'Field In'),
        dot(const Color(0xFFF97316), 'Field Out'),
        dot(const Color(0xFFDC2626), 'Punch Out'),
        if (_isToday && !_punchedOut) dot(const Color(0xFF8B5CF6), 'Latest position'),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 16, height: 3, color: TravelledRouteStyle.color),
            const SizedBox(width: 4),
            const Text('Travel leg', style: TextStyle(fontSize: 11.5, color: _muted)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 16, height: 3, color: const Color(0xFF6366F1).withValues(alpha: 0.45)),
            const SizedBox(width: 4),
            const Text('Whole day', style: TextStyle(fontSize: 11.5, color: _muted)),
          ],
        ),
      ],
    );
  }

  Widget _legTile(_Leg l) {
    final selected = _selectedLeg == l.index;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() => _selectedLeg = selected ? null : l.index);
        _fitTo(selected ? null : l);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0FDF4) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: TravelledRouteStyle.color.withValues(alpha: 0.12),
              child: Text(
                '${l.index}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: TravelledRouteStyle.color),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l.fromLabel} → ${l.toLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('hh:mm a').format(l.fromAt)} – ${DateFormat('hh:mm a').format(l.toAt)}',
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l.km == null ? '—' : '${l.km!.toStringAsFixed(1)} km',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flagTile(_Flag f) {
    final color = switch (f.type) {
      'punch_in' => const Color(0xFF16A34A),
      'field_in' => const Color(0xFF0EA5E9),
      'field_out' => const Color(0xFFF97316),
      'punch_out' => const Color(0xFFDC2626),
      _ => _muted,
    };
    return InkWell(
      onTap: f.pos == null ? null : () => _map?.animateCamera(CameraUpdate.newLatLngZoom(f.pos!, 16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${f.seq}. ${f.title}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                  if (f.address.isNotEmpty)
                    Text(f.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _muted)),
                  if (f.pos == null)
                    const Text('Location not recorded', style: TextStyle(fontSize: 11.5, color: _muted)),
                ],
              ),
            ),
            Text(DateFormat('hh:mm a').format(f.at), style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
