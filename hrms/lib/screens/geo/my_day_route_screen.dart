// "My Route" — the staff member's field day on a map (HRMSbackend
// GET /staff/geo-task/day-route): flags for Punch In, each Field In / Field Out
// and Punch Out, the travelled path of every leg as the dashed green line, and
// each leg's km (Punch In → Field In 1, Field Out 1 → Field In 2, … → Punch Out).
// Distances are measured by the backend from the GPS trail and are only shown
// when tracking is enabled for the employee.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../services/geo/route_snapping_service.dart';
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
  _Flag(this.seq, this.type, this.at, this.pos, this.title, this.address, this.taskId);
  final int seq;
  final String type; // punch_in | field_in | field_out | punch_out
  final DateTime at;
  final LatLng? pos;
  final String title;
  final String address;
  final String taskId;

  /// Short map label: IN, F1, F1 out, F2, …, OUT (visits numbered in order).
  String code = '';
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

  /// [path] snapped to the roads (continuous line); falls back to [path].
  List<LatLng> display = const [];
  Color color = TravelledRouteStyle.color;
  String fromCode = '';
  String toCode = '';

  List<LatLng> get line => display.length >= 2 ? display : path;
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
        _trailDisplay = const [];
        _lastTrailSnapAt = null;
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
          raw['taskId']?.toString() ?? '',
        ));
      }
      // Visits numbered in order: Field In of the n-th visit = Fn, its Field Out = "Fn out".
      final visitNo = <String, int>{};
      for (final f in flags) {
        switch (f.type) {
          case 'punch_in':
            f.code = 'IN';
          case 'punch_out':
            f.code = 'OUT';
          case 'field_in':
            final n = visitNo.putIfAbsent(f.taskId.isEmpty ? 'seq${f.seq}' : f.taskId, () => visitNo.length + 1);
            f.code = 'F$n';
          case 'field_out':
            final n = visitNo.putIfAbsent(f.taskId.isEmpty ? 'seq${f.seq}' : f.taskId, () => visitNo.length + 1);
            f.code = 'F$n out';
        }
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
      // Leg colours + the flag codes at each end (IN → F1, F1 out → F2, …).
      for (var i = 0; i < legs.length; i++) {
        final l = legs[i];
        l.color = _legPalette[i % _legPalette.length];
        _Flag? near(DateTime at, bool departure) {
          for (final f in flags) {
            final isDep = f.type == 'punch_in' || f.type == 'field_out';
            if (isDep == departure && f.at.difference(at).inSeconds.abs() <= 1) return f;
          }
          return null;
        }

        l.fromCode = near(l.fromAt, true)?.code ?? '';
        l.toCode = near(l.toAt, false)?.code ?? '';
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _trackingOn = data['trackingEnabled'] == true;
        _totalKm = (data['totalKm'] as num?)?.toDouble();
        _trailKm = (data['trailKm'] as num?)?.toDouble();
        _trail = trail;
        _punchedOut = flags.any((f) => f.type == 'punch_out');
        _flags = flags;
        // Periodic refresh: keep the road-snapped line of legs that haven't changed.
        for (final l in legs) {
          for (final old in _legs) {
            if (old.index == l.index && old.path.length == l.path.length && old.display.length >= 2) {
              l.display = old.display;
            }
          }
        }
        _legs = legs;
      });
      if (!silent) WidgetsBinding.instance.addPostFrameCallback((_) => _fitTo(null));
      unawaited(_buildMapGraphics());
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

  /// Distinct leg colours so L1, L2, … are easy to tell apart on the map.
  static const List<Color> _legPalette = [
    Color(0xFF2E7D32), // green
    Color(0xFF1565C0), // blue
    Color(0xFF6A1B9A), // purple
    Color(0xFFEF6C00), // orange
    Color(0xFF00838F), // teal
    Color(0xFFC2185B), // pink
  ];

  /// Whole-day trail snapped to the roads (falls back to the raw trail).
  List<LatLng> _trailDisplay = const [];

  /// Rendered label pins ("IN", "F1", "L1 · 3.4 km", …), keyed by text+colour.
  final Map<String, BitmapDescriptor> _icons = {};

  String get _dayKey => DateFormat('yyyyMMdd').format(_day);

  /// Road-snapped lines for every leg and the whole day (cached on the phone
  /// per day + point count, so each route is snapped once), and the label pins.
  Future<void> _buildMapGraphics() async {
    final legs = List<_Leg>.from(_legs);
    final trail = List<LatLng>.from(_trail);

    // Flag icons first (cheap), so the flags show right away.
    for (final f in _flags) {
      if (f.pos == null || !_isMapFlag(f)) continue;
      final key = _flagKey(f);
      if (_icons.containsKey(key)) continue;
      try {
        _icons[key] = await _flagIcon(_flagColor(f.type), f.type == 'field_in' ? f.code.replaceFirst('F', '') : null);
      } catch (_) {}
    }
    if (mounted) setState(() {});

    // Then snap each leg and the whole day to the roads.
    for (final l in legs) {
      if (l.path.length < 2 || l.display.length >= 2) continue;
      try {
        l.display = await RouteSnappingService.buildDisplayRouteFromLatLng(
          'myday-$_dayKey-leg${l.index}',
          l.path,
        );
      } catch (_) {}
      if (mounted) setState(() {});
    }
    // The whole-day line grows while punched in: re-snap it at most every 5 min
    // (each new point count is a Roads API call), keeping the previous line meanwhile.
    final dueAt = _lastTrailSnapAt?.add(const Duration(minutes: 5));
    if (trail.length >= 2 && (dueAt == null || DateTime.now().isAfter(dueAt))) {
      _lastTrailSnapAt = DateTime.now();
      try {
        final snapped = await RouteSnappingService.buildDisplayRouteFromLatLng('myday-$_dayKey-trail', trail);
        if (mounted) setState(() => _trailDisplay = snapped);
      } catch (_) {}
    }
  }

  DateTime? _lastTrailSnapAt;

  Color _flagColor(String type) => switch (type) {
        'punch_in' => const Color(0xFF16A34A),
        'field_in' => const Color(0xFF0284C7),
        'field_out' => const Color(0xFFEA580C),
        'punch_out' => const Color(0xFFDC2626),
        _ => _muted,
      };

  /// Only Punch In, Field In and Punch Out get a flag on the map.
  bool _isMapFlag(_Flag f) => f.type == 'punch_in' || f.type == 'field_in' || f.type == 'punch_out';

  String _flagKey(_Flag f) => 'flag|${f.type}|${f.type == 'field_in' ? f.code : ''}';

  /// Small, clear flag icon: a white-ringed coloured circle with a white flag,
  /// plus a tiny visit number (1, 2, …) for Field In. ~26 dp, drawn crisp.
  Future<BitmapDescriptor> _flagIcon(Color color, String? number) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final d = 26 * dpr; // circle diameter
    final badge = number == null ? 0.0 : 14 * dpr;
    final w = d + badge * 0.55;
    final h = d + badge * 0.35;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(d / 2, h - d / 2);

    canvas.drawCircle(c.translate(0, dpr), d / 2 - dpr, Paint()..color = const Color(0x33000000));
    canvas.drawCircle(c, d / 2 - dpr, Paint()..color = Colors.white);
    canvas.drawCircle(c, d / 2 - 3 * dpr, Paint()..color = color);

    final icon = Icons.flag_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontSize: 15 * dpr, fontFamily: icon.fontFamily, package: icon.fontPackage, color: Colors.white),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));

    if (number != null) {
      final bc = Offset(w - badge / 2, badge / 2);
      canvas.drawCircle(bc, badge / 2, Paint()..color = Colors.white);
      canvas.drawCircle(bc, badge / 2 - 1.5 * dpr, Paint()..color = const Color(0xFF0F172A));
      final np = TextPainter(
        text: TextSpan(
          text: number,
          style: TextStyle(fontSize: 8.5 * dpr, fontWeight: FontWeight.w900, color: Colors.white),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      np.paint(canvas, bc - Offset(np.width / 2, np.height / 2));
    }

    final img = await recorder.endRecording().toImage(w.ceil(), h.ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: dpr);
  }

  Set<Marker> get _markers => {
        for (final f in _flags)
          if (f.pos != null && _isMapFlag(f))
            Marker(
              markerId: MarkerId('flag-${f.seq}'),
              position: f.pos!,
              icon: _icons[_flagKey(f)] ?? BitmapDescriptor.defaultMarkerWithHue(_hueFor(f.type)),
              anchor: const Offset(0.5, 0.5),
              infoWindow: InfoWindow(
                title: switch (f.type) {
                  'punch_in' => 'Punch In',
                  'punch_out' => 'Punch Out',
                  _ => '${f.code} · ${f.title.replaceFirst('Field In · ', '')}',
                },
                snippet: [
                  DateFormat('hh:mm a').format(f.at),
                  if (f.address.isNotEmpty) f.address,
                ].join(' · '),
              ),
              zIndexInt: 3,
            ),
      };

  Set<Polyline> get _polylines {
    final whole = _trailDisplay.length >= 2 ? _trailDisplay : _trail;
    final out = <Polyline>{
      // Complete route punch-in → punch-out underneath (incl. movement at
      // clients), road-snapped; the coloured legs are drawn on top of it.
      if (whole.length >= 2)
        Polyline(
          polylineId: const PolylineId('whole-day'),
          points: whole,
          color: const Color(0xFF94A3B8).withValues(alpha: 0.55),
          width: 7,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 1,
        ),
    };
    for (final l in _legs) {
      final pts = l.line;
      if (pts.length < 2) continue;
      final faded = _selectedLeg != null && _selectedLeg != l.index;
      out.add(Polyline(
        polylineId: PolylineId('leg-${l.index}'),
        points: pts,
        color: faded ? l.color.withValues(alpha: 0.25) : l.color,
        width: 5,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: faded ? 2 : 3,
        consumeTapEvents: true,
        onTap: () => setState(() => _selectedLeg = faded ? l.index : null),
      ));
    }
    return out;
  }

  Future<void> _fitTo(_Leg? leg) async {
    final map = _map;
    if (map == null) return;
    final pts = <LatLng>[
      if (leg != null) ...leg.line,
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
            const Text('Timeline', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 10),
            ..._timeline(),
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
            Icon(Icons.flag_rounded, size: 16, color: c),
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        dot(_flagColor('punch_in'), 'Punch In'),
        dot(_flagColor('field_in'), 'Field In (F1, F2…)'),
        dot(_flagColor('punch_out'), 'Punch Out'),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in _legPalette.take(3))
              Container(width: 8, height: 4, margin: const EdgeInsets.only(right: 2), color: c),
            const SizedBox(width: 4),
            const Text('Legs L1, L2…', style: TextStyle(fontSize: 11.5, color: _muted)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 16, height: 5, color: const Color(0xFF94A3B8).withValues(alpha: 0.55)),
            const SizedBox(width: 4),
            const Text('Complete route (punch in → out)', style: TextStyle(fontSize: 11.5, color: _muted)),
          ],
        ),
      ],
    );
  }

  // ── Timeline: flag → leg → flag … (Punch In, each Field In, Punch Out) ──

  /// The Field Out that closed the visit of [fieldIn] (same task), if any.
  _Flag? _fieldOutFor(_Flag fieldIn) {
    for (final f in _flags) {
      if (f.type == 'field_out' && f.taskId.isNotEmpty && f.taskId == fieldIn.taskId) return f;
    }
    return null;
  }

  /// The leg that ends at [arrival] (a Field In or Punch Out).
  _Leg? _legInto(_Flag arrival) {
    for (final l in _legs) {
      if (l.toAt.difference(arrival.at).inSeconds.abs() <= 1) return l;
    }
    return null;
  }

  List<Widget> _timeline() {
    final shown = _flags.where((f) => f.type != 'field_out').toList();
    final rows = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      final f = shown[i];
      if (f.type != 'punch_in') {
        final leg = _legInto(f);
        if (leg != null) rows.add(_legRow(leg));
      }
      rows.add(_flagRow(f, isLast: i == shown.length - 1));
    }
    return rows;
  }

  Widget _flagRow(_Flag f, {required bool isLast}) {
    final color = _flagColor(f.type);
    final out = f.type == 'field_in' ? _fieldOutFor(f) : null;
    final time = DateFormat('hh:mm a');
    final title = switch (f.type) {
      'punch_in' => 'Punch In',
      'punch_out' => 'Punch Out',
      _ => '${f.code} · ${f.title.replaceFirst('Field In · ', '')}',
    };
    return InkWell(
      onTap: f.pos == null ? null : () => _map?.animateCamera(CameraUpdate.newLatLngZoom(f.pos!, 16)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)],
                    ),
                    child: const Icon(Icons.flag_rounded, size: 16, color: Colors.white),
                  ),
                  if (!isLast)
                    Expanded(child: Container(width: 2, color: const Color(0xFFE2E8F0))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _ink),
                          ),
                        ),
                        Text(
                          out != null ? '${time.format(f.at)} – ${time.format(out.at)}' : time.format(f.at),
                          style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    if (f.address.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          f.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: _muted),
                        ),
                      ),
                    if (f.type == 'field_in')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          out != null ? 'At site ${_durationLabel(out.at.difference(f.at))}' : 'At site now',
                          style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (f.pos == null)
                      const Text('Location not recorded', style: TextStyle(fontSize: 11.5, color: _muted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legRow(_Leg l) {
    final selected = _selectedLeg == l.index;
    final time = DateFormat('hh:mm a');
    return InkWell(
      onTap: () {
        setState(() => _selectedLeg = selected ? null : l.index);
        _fitTo(selected ? null : l);
      },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The leg drawn as a thick segment of the rail, in its map colour.
            SizedBox(
              width: 36,
              child: Center(
                child: Container(
                  width: selected ? 6 : 4,
                  decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: l.color.withValues(alpha: selected ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: l.color.withValues(alpha: selected ? 0.9 : 0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        'L${l.index}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l.fromCode.isNotEmpty ? l.fromCode : 'Start'} → ${l.toCode.isNotEmpty ? l.toCode : 'End'}'
                        '  ·  ${time.format(l.fromAt)} – ${time.format(l.toAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: _muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l.km == null ? '—' : '${l.km!.toStringAsFixed(1)} km',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: l.color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _durationLabel(Duration d) {
    if (d.inMinutes < 1) return '< 1 min';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
