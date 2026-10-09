// "My Route" — the staff member's field day on a map (HRMSbackend
// GET /staff/geo-task/day-route): flags for Punch In, each Field In / Field Out
// and Punch Out, the travelled path of every leg as the dashed green line, and
// each leg's km (Punch In → Field In 1, Field Out 1 → Field In 2, … → Punch Out).
// Distances are measured by the backend from the GPS trail and are only shown
// when tracking is enabled for the employee.

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:permission_handler/permission_handler.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../services/geo/route_snapping_service.dart';
import '../../services/geo/tracking_health_service.dart';
import '../../services/geo/tracking_incident_log_service.dart';
import '../../services/presence_tracking_service.dart';
import '../../services/task_service.dart';
import '../../services/admin_geo_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/flag_marker_icon.dart';
import '../../widgets/travelled_route_style.dart';

class MyDayRouteScreen extends StatefulWidget {
  const MyDayRouteScreen({super.key, this.initialDay, this.staffId, this.staffName});

  final DateTime? initialDay;

  /// Admin view: when set, shows this staff member's route (admin endpoint) instead
  /// of the signed-in employee's own.
  final String? staffId;
  final String? staffName;

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
  _Leg(this.index, this.fromLabel, this.toLabel, this.fromAt, this.toAt, this.km, this.path, {this.rawPoints = const []});
  final int index;
  final String fromLabel;
  final String toLabel;
  final DateTime fromAt;
  final DateTime toAt;
  final double? km;
  final List<LatLng> path;
  final List<Map<String, dynamic>> rawPoints;

  /// [path] snapped to the roads (continuous line); falls back to [path].
  List<LatLng> display = const [];
  Color color = TravelledRouteStyle.color;
  String fromCode = '';
  String toCode = '';

  List<LatLng> get line => display.length >= 2 ? display : path;
}

/// One piece of the day's continuous route, between two consecutive flags:
/// a travel leg (IN→F1, F1 out→F2, …, last out→OUT) or time at a client
/// (F1 → F1 out). Consecutive pieces share their end points, so the route is
/// one unbroken line from Punch In to Punch Out.
class _Seg {
  _Seg(this.key, this.legIndex, this.color, this.points);
  final String key;

  /// Leg number for travel pieces; null for time at a client.
  final int? legIndex;
  final Color color;

  /// Anchored at both ends (flag positions / neighbour's end).
  final List<LatLng> points;

  /// [points] snapped to the roads, with the same two end points.
  List<LatLng> display = const [];

  /// Snapped earlier part + raw new points (the growing last piece); a full
  /// re-snap is due later.
  bool provisional = false;
  List<LatLng> get line => display.length >= 2 ? display : points;
}

class _MyDayRouteScreenState extends State<MyDayRouteScreen> {
  late DateTime _day;
  bool _loading = true;
  String? _error;
  bool _trackingOn = false;
  double? _totalKm;
  double? _trailKm;
  /// The whole tracked day (punch-in → punch-out / now), including time at clients.
  bool _punchedOut = false;
  List<_Flag> _flags = [];
  List<_Leg> _legs = [];
  Map<String, dynamic>? _rawRouteData;
  int? _selectedLeg;
  GoogleMapController? _map;

  static const _ink = AppColors.textPrimary;
  static const _muted = AppColors.textSecondary;

  Timer? _refresh;

  /// Latest saved position today and its time (server `lastPoint`) - shown as the live
  /// "last location" marker while still punched in.
  (LatLng, DateTime)? _lastPoint;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDay ?? DateTime.now();
    _day = DateTime(d.year, d.month, d.day);
    _load();
    // Today, still punched in: keep the route current without resetting the map
    // (every 30 s - the phone saves a point at most every 30 s).
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
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
    if (widget.staffId == null) {
      unawaited(PresenceTrackingService().flushPendingPresenceQueue());
      unawaited(TaskService.syncOfflineQueueBatch());
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _selectedLeg = null;
        _segs = [];
      });
    }
    try {
      final data = widget.staffId != null
          ? await AdminGeoService.instance.getStaffDayRoute(widget.staffId!, _day)
          : await TaskService().getDayRoute(_day);
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
          rawPoints: [
            for (final p in (raw['path'] as List? ?? const []))
              if (p is Map) Map<String, dynamic>.from(p),
          ],
        ));
      }
      // Whole-day points with their times, so the route can be cut at each flag.
      final trailT = <(LatLng, DateTime)>[
        for (final p in (data['trail'] as List? ?? const []))
          if (p is Map && p['lat'] is num && p['lng'] is num)
            (
              LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
              _parseAt(p['t']),
            ),
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
        _rawRouteData = data;
        _trackingOn = data['trackingEnabled'] == true;
        _totalKm = (data['totalKm'] as num?)?.toDouble();
        _trailKm = (data['trailKm'] as num?)?.toDouble();
        _punchedOut = flags.any((f) => f.type == 'punch_out');
        final lp = data['lastPoint'];
        _lastPoint = (lp is Map && lp['lat'] is num && lp['lng'] is num)
            ? (LatLng((lp['lat'] as num).toDouble(), (lp['lng'] as num).toDouble()), _parseAt(lp['t']))
            : null;
        _flags = flags;
        _legs = legs;
        final segs = _buildSegments(flags, legs, trailT);
        // Periodic refresh: keep the road-snapped line of pieces that haven't
        // changed. The growing last piece (still punched in) keeps its snapped
        // part and just extends with the new points, so the route follows the
        // person without a Roads API call every minute (re-snapped every 5 min).
        for (var i = 0; i < segs.length; i++) {
          final s = segs[i];
          final isOpen = !_punchedOut && i == segs.length - 1;
          for (final old in _segs) {
            if (old.display.length < 2) continue;
            if (old.key == s.key) {
              s.display = old.display;
            } else if (isOpen &&
                old.key.split('-').first == s.key.split('-').first &&
                s.points.length > old.points.length) {
              s.display = [...old.display, ...s.points.sublist(old.points.length)];
              s.provisional = true;
            }
          }
        }
        _segs = segs;
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

  /// Distinct leg colours so L1, L2, … are easy to tell apart on the map —
  /// chosen to never clash with the green/red Punch flags or the blue/orange
  /// Field In/Out dots.
  static const List<Color> _legPalette = [
    Color(0xFF7C3AED), // violet
    Color(0xFF0D9488), // teal
    Color(0xFFDB2777), // pink
    AppColors.brandDark, // amber / brown
    Color(0xFF4F46E5), // indigo
    Color(0xFF0891B2), // cyan
  ];

  /// When the growing last piece was last snapped (throttles Roads API calls).
  DateTime? _openSnapAt;

  /// The day's route as connected pieces (see [_Seg]).
  List<_Seg> _segs = [];

  /// Grey for time at a client, between two coloured legs.
  static const Color _siteColor = Color(0xFF64748B);

  /// Rendered flag icons, keyed by type + visit.
  final Map<String, BitmapDescriptor> _icons = {};

  String get _dayKey => DateFormat('yyyyMMdd').format(_day);

  /// Cuts the whole-day GPS trail at every flag (Punch In, Field In, Field Out,
  /// Punch Out): IN→F1 = L1, F1→F1 out = at site, F1 out→F2 = L2, … Each piece
  /// starts exactly where the previous one ended (the flag's position, or the
  /// neighbour's last point when a flag has no location), so the route never
  /// breaks. While still punched in, the last piece runs to the latest point.
  List<_Seg> _buildSegments(List<_Flag> flags, List<_Leg> legs, List<(LatLng, DateTime)> trail) {
    if (trail.isEmpty) return [];
    final marks = flags.where((f) => f.type != '').toList()..sort((a, b) => a.at.compareTo(b.at));
    if (marks.isEmpty) return [];

    _Leg? legFrom(_Flag f) {
      for (final l in legs) {
        if (l.fromAt.difference(f.at).inSeconds.abs() <= 1) return l;
      }
      return null;
    }

    final segs = <_Seg>[];
    LatLng? carry = marks.first.pos; // the previous piece's end
    for (var i = 0; i < marks.length; i++) {
      final from = marks[i];
      final to = i + 1 < marks.length ? marks[i + 1] : null;
      if (to == null && _punchedOut) break; // day closed at the last flag
      final end = to?.at ?? DateTime.now();
      final inside = [
        for (final p in trail)
          if (p.$2.isAfter(from.at) && p.$2.isBefore(end)) p.$1,
      ];
      final start = from.pos ?? carry ?? (inside.isNotEmpty ? inside.first : null);
      final finish = to?.pos ?? (inside.isNotEmpty ? inside.last : start);
      if (start == null || finish == null) continue;
      final pts = <LatLng>[start, ...inside, if (finish != (inside.isNotEmpty ? inside.last : start)) finish];
      // Skip a zero-length piece (nothing moved, both ends the same spot).
      carry = pts.last;
      if (pts.length < 2) continue;

      final isTravel = from.type == 'punch_in' || from.type == 'field_out';
      final leg = isTravel ? legFrom(from) : null;
      segs.add(_Seg(
        '${isTravel ? 'L' : 'S'}${leg?.index ?? i}-${pts.length}',
        leg?.index,
        leg?.color ?? (isTravel ? _legPalette[segs.length % _legPalette.length] : _siteColor),
        pts,
      ));
    }
    return segs;
  }

  /// Flag icons, then road-snapped pieces. Each snapped piece is re-pinned to
  /// its original two end points, so snapping can't reopen a gap at a flag.
  /// Snaps are cached on the phone per piece + point count.
  Future<void> _buildMapGraphics() async {
    final segs = List<_Seg>.from(_segs);

    for (final f in _flags) {
      if (f.pos == null) continue;
      final key = _flagKey(f);
      if (_icons.containsKey(key)) continue;
      try {
        if (_isVisit(f)) {
          // "F1 in" (blue, tag on the right) / "F1 out" (orange, tag on the left).
          final dot = await dotLabelMarkerIcon(
            context,
            f.type == 'field_in' ? kFieldInDotColor : kFieldOutDotColor,
            _visitLabel(f),
            labelLeft: f.type == 'field_out',
          );
          _icons[key] = dot.icon;
          _dotAnchors[key] = dot.anchor;
        } else {
          // Punch In / Punch Out: plain green / red flag, pole standing on the point.
          final flag = await plainFlagMarkerIcon(context, _flagColor(f.type));
          _icons[key] = flag.icon;
          _dotAnchors[key] = flag.anchor;
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});

    for (final s in segs) {
      // Even a 2-point piece is drawn along the roads (the gap is routed, not straight).
      if (s.points.length < 2) continue;
      if (s.display.length >= 2) {
        // Already snapped; the growing piece is re-snapped at most every 2 min.
        final due = _openSnapAt == null || DateTime.now().difference(_openSnapAt!) >= const Duration(minutes: 2);
        if (!s.provisional || !due) continue;
      }
      if (s.provisional || (!_punchedOut && identical(s, segs.last))) _openSnapAt = DateTime.now();
      try {
        final snapped = await RouteSnappingService.buildDisplayRouteFromLatLng('myday-$_dayKey-${s.key}', s.points);
        if (snapped.length >= 2) {
          s.display = [
            s.points.first,
            if (snapped.first != s.points.first) snapped.first,
            ...snapped.sublist(1, snapped.length - 1),
            if (snapped.last != s.points.last) snapped.last,
            s.points.last,
          ];
          s.provisional = false;
        }
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  Color _flagColor(String type) => switch (type) {
        'punch_in' => const Color(0xFF16A34A),
        'field_in' => const Color(0xFF0284C7),
        'field_out' => AppColors.brandDark,
        'punch_out' => const Color(0xFFDC2626),
        _ => _muted,
      };

  /// Field In / Field Out are drawn as labelled dots; Punch In / Out as flags.
  bool _isVisit(_Flag f) => f.type == 'field_in' || f.type == 'field_out';

  /// "F1 in" / "F1 out" (codes are "F1" / "F1 out").
  String _visitLabel(_Flag f) => f.type == 'field_in' ? '${f.code} in' : f.code;

  String _flagKey(_Flag f) => 'mk|${f.type}|${_isVisit(f) ? f.code : ''}';

  /// Anchor for each dot icon (centres the dot, not the label).
  final Map<String, Offset> _dotAnchors = {};

  Set<Marker> get _markers => {
        for (final f in _flags)
          if (f.pos != null)
            Marker(
              markerId: MarkerId('flag-${f.seq}'),
              position: f.pos!,
              icon: _icons[_flagKey(f)] ?? BitmapDescriptor.defaultMarkerWithHue(_hueFor(f.type)),
              anchor: _dotAnchors[_flagKey(f)] ?? const Offset(0.5, 0.5),
              infoWindow: InfoWindow(
                title: switch (f.type) {
                  'punch_in' => 'Punch In',
                  'punch_out' => 'Punch Out',
                  'field_out' => '${_visitLabel(f)} · ${f.title.replaceFirst('Field Out · ', '')}',
                  _ => '${_visitLabel(f)} · ${f.title.replaceFirst('Field In · ', '')}',
                },
                snippet: [
                  DateFormat('hh:mm a').format(f.at),
                  if (f.address.isNotEmpty) f.address,
                ].join(' · '),
              ),
              zIndexInt: _isVisit(f) ? 2 : 3, // flags above dots
            ),
        // Live: where the staff member is now (today, still punched in).
        if (_lastPoint != null && _isToday && !_punchedOut)
          Marker(
            markerId: const MarkerId('last-location'),
            position: _lastPoint!.$1,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            infoWindow: InfoWindow(
              title: 'Last location',
              snippet: DateFormat('hh:mm a').format(_lastPoint!.$2),
            ),
            zIndexInt: 4,
          ),
      };

  /// One continuous route: the pieces in order, each in its leg colour (grey
  /// while at a client). Tap a leg to highlight it.
  Set<Polyline> get _polylines {
    final out = <Polyline>{};
    for (var i = 0; i < _segs.length; i++) {
      final s = _segs[i];
      final pts = s.line;
      if (pts.length < 2) continue;
      final faded = _selectedLeg != null && s.legIndex != _selectedLeg;
      out.add(Polyline(
        polylineId: PolylineId('seg-$i'),
        points: pts,
        color: faded ? s.color.withValues(alpha: 0.3) : s.color,
        width: s.legIndex == null ? 5 : 6,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: faded ? 1 : 2,
        consumeTapEvents: s.legIndex != null,
        onTap: s.legIndex == null
            ? null
            : () => setState(() => _selectedLeg = _selectedLeg == s.legIndex ? null : s.legIndex),
      ));
    }
    return out;
  }

  Future<void> _fitTo(_Leg? leg) async {
    final map = _map;
    if (map == null) return;
    final pts = <LatLng>[
      if (leg != null) ...[for (final s in _segs) if (s.legIndex == leg.index) ...s.line],
      if (leg != null && !_segs.any((s) => s.legIndex == leg.index)) ...leg.path,
      if (leg == null) ...[for (final f in _flags) if (f.pos != null) f.pos!],
      if (leg == null) ...[for (final s in _segs) ...s.line],
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.staffName != null ? '${widget.staffName}’s Route' : 'My Route'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _showRouteLogsSheet,
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: 'Tracking Logs & Diagnostics',
          ),
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
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous day',
          ),
          Expanded(
            child: Material(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _pickDay,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primaryText),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _isToday ? 'Today, ${DateFormat('d MMM yyyy').format(_day)}' : DateFormat('EEE, d MMM yyyy').format(_day),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _isToday ? null : () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next day',
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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 28),
              ),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _summary(),
          const SizedBox(height: 12),
          _legend(),
          const SizedBox(height: 16),
          if (_flags.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.flag_outlined, size: 28, color: AppColors.primaryText),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No punch or field activity on this day.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            )
          else ...[
            const Text('Timeline', style: AppTextStyles.headingSmall),
            const SizedBox(height: 12),
            ..._timeline(),
          ],
        ],
      ),
    );
  }

  Widget _summary() {
    final km = _totalKm;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _trackingOn ? AppColors.successBg.withValues(alpha: 0.5) : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _trackingOn ? AppColors.success.withValues(alpha: 0.25) : const Color(0xFFECEEF1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (_trackingOn ? AppColors.success : _muted).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _trackingOn ? Icons.route_rounded : Icons.location_off_outlined,
              size: 22,
              color: _trackingOn ? AppColors.success : _muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _trackingOn ? 'Distance travelled' : 'Tracking is off',
                  style: AppTextStyles.caption.copyWith(color: _muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _trackingOn
                      ? '${(km ?? 0).toStringAsFixed(1)} km · ${_legs.length} leg${_legs.length == 1 ? '' : 's'}'
                      : 'Distance is not recorded for this employee',
                  style: TextStyle(
                    fontSize: _trackingOn ? 20 : 13,
                    fontWeight: _trackingOn ? FontWeight.w700 : FontWeight.w600,
                    color: _trackingOn ? AppColors.success : _ink,
                  ),
                ),
                if (_trackingOn && _trailKm != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Whole day tracked: ${_trailKm!.toStringAsFixed(1)} km (incl. movement at clients)',
                    style: AppTextStyles.caption.copyWith(color: _muted),
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
            Text(label, style: AppTextStyles.caption.copyWith(color: _muted)),
          ],
        );
    Widget visitDot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 2)],
              ),
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        dot(_flagColor('punch_in'), 'Punch In'),
        visitDot(kFieldInDotColor, 'F1 in = Field In'),
        visitDot(kFieldOutDotColor, 'F1 out = Field Out'),
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
            Container(width: 16, height: 5, color: _siteColor),
            const SizedBox(width: 4),
            const Text('At client (Field In → Field Out)', style: TextStyle(fontSize: 11.5, color: _muted)),
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
      _ => '${f.code} in · ${f.title.replaceFirst('Field In · ', '')}',
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
                  // Punch In / Out: plain green / red flag. Field In: blue dot.
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: f.type == 'field_in'
                          ? Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: kFieldInDotColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
                              ),
                            )
                          : Icon(Icons.flag_rounded, size: 26, color: color),
                    ),
                  ),
                  if (!isLast)
                    Expanded(child: Container(width: 2, color: AppColors.divider)),
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
                            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          out != null ? '${time.format(f.at)} – ${time.format(out.at)}' : time.format(f.at),
                          style: AppTextStyles.caption.copyWith(color: _muted, fontWeight: FontWeight.w600),
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
                          style: AppTextStyles.caption.copyWith(color: _muted),
                        ),
                      ),
                    if (f.type == 'field_in')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          out != null ? 'At site ${_durationLabel(out.at.difference(f.at))}' : 'At site now',
                          style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (f.pos == null)
                      Text('Location not recorded', style: AppTextStyles.caption.copyWith(color: _muted)),
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
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: l.color.withValues(alpha: selected ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: l.color.withValues(alpha: selected ? 0.9 : 0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        'L${l.index}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
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
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: l.color),
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

  Future<void> _showRouteLogsSheet() async {
    gl.ServiceStatus? gpsStatus;
    try {
      final enabled = await gl.Geolocator.isLocationServiceEnabled();
      gpsStatus = enabled ? gl.ServiceStatus.enabled : gl.ServiceStatus.disabled;
    } catch (_) {}

    PermissionStatus? locAlways;
    PermissionStatus? locWhenInUse;
    try {
      locAlways = await Permission.locationAlways.status;
      locWhenInUse = await Permission.locationWhenInUse.status;
    } catch (_) {}

    int pendingOfflinePoints = 0;
    try {
      final presenceCount = await PresenceTrackingService().getPendingPresenceCount();
      final taskCount = await TaskService.getOfflineQueueCount();
      pendingOfflinePoints = presenceCount + taskCount;
    } catch (_) {}

    final issues = TrackingHealthService.instance.issues.value;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RouteLogsBottomSheet(
        day: _day,
        staffName: widget.staffName,
        trackingOn: _trackingOn,
        totalKm: _totalKm,
        trailKm: _trailKm,
        flags: _flags,
        legs: _legs,
        rawRouteData: _rawRouteData,
        gpsStatus: gpsStatus,
        locAlways: locAlways,
        locWhenInUse: locWhenInUse,
        pendingOfflineCount: pendingOfflinePoints,
        healthIssues: issues,
      ),
    );
  }
}

class _RouteLogsBottomSheet extends StatefulWidget {
  const _RouteLogsBottomSheet({
    required this.day,
    this.staffName,
    required this.trackingOn,
    this.totalKm,
    this.trailKm,
    required this.flags,
    required this.legs,
    this.rawRouteData,
    this.gpsStatus,
    this.locAlways,
    this.locWhenInUse,
    required this.pendingOfflineCount,
    required this.healthIssues,
  });

  final DateTime day;
  final String? staffName;
  final bool trackingOn;
  final double? totalKm;
  final double? trailKm;
  final List<_Flag> flags;
  final List<_Leg> legs;
  final Map<String, dynamic>? rawRouteData;
  final gl.ServiceStatus? gpsStatus;
  final PermissionStatus? locAlways;
  final PermissionStatus? locWhenInUse;
  final int pendingOfflineCount;
  final List<TrackingIssue> healthIssues;

  @override
  State<_RouteLogsBottomSheet> createState() => _RouteLogsBottomSheetState();
}

enum _LogFilter {
  all,
  gps,
  network,
  permission,
  rawTrail,
}

class _RouteLogsBottomSheetState extends State<_RouteLogsBottomSheet> {
  _LogFilter _activeFilter = _LogFilter.all;
  bool _showMilestones = false;
  bool _loadingIncidents = true;
  bool _syncingNow = false;
  late int _currentPendingCount;
  List<TrackingIncident> _incidents = [];

  @override
  void initState() {
    super.initState();
    _currentPendingCount = widget.pendingOfflineCount;
    _loadIncidents();
  }

  Future<void> _manualSyncOffline() async {
    if (_syncingNow) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    setState(() => _syncingNow = true);
    try {
      await PresenceTrackingService().flushPendingPresenceQueue();
      await TaskService.syncOfflineQueueBatch();
      final p = await PresenceTrackingService().getPendingPresenceCount();
      final t = await TaskService.getOfflineQueueCount();
      if (!mounted) return;
      setState(() {
        _currentPendingCount = p + t;
      });
      await _loadIncidents();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            _currentPendingCount == 0
                ? 'All offline tracking points synced successfully!'
                : 'Sync completed: $_currentPendingCount points remaining in queue.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Offline sync failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }

  Future<void> _loadIncidents() async {
    final list = await TrackingIncidentLogService.getIncidentsForDay(widget.day);
    final merged = <TrackingIncident>[...list];

    // Synthesize gap incidents from legs if straight lines occurred
    for (final s in _straightLineLegs) {
      final exists = merged.any(
        (i) => i.type == 'gap' && i.at.difference(s.leg.fromAt).inMinutes.abs() < 5,
      );
      if (!exists) {
        merged.add(TrackingIncident(
          id: 'gap_leg_${s.leg.index}',
          type: 'gap',
          title: 'Straight-Line Gap: Leg ${s.leg.index} (${s.km.toStringAsFixed(1)} km)',
          description: s.reason,
          at: s.leg.fromAt,
          severity: 'critical',
        ));
      }
    }

    // If day is today, reflect current sensor status if not already logged
    final isToday = DateTime.now().year == widget.day.year &&
        DateTime.now().month == widget.day.month &&
        DateTime.now().day == widget.day.day;

    if (isToday) {
      if (widget.gpsStatus == gl.ServiceStatus.disabled &&
          !merged.any((i) => i.type == 'gps_off' && DateTime.now().difference(i.at).inMinutes < 60)) {
        merged.add(TrackingIncident(
          id: 'current_gps_off',
          type: 'gps_off',
          title: 'GPS Hardware Disabled',
          description: 'Device location services are currently turned off.',
          at: DateTime.now(),
          severity: 'critical',
        ));
      }

      if (widget.locAlways != PermissionStatus.granted &&
          !merged.any((i) => i.type == 'permission_blocked' && DateTime.now().difference(i.at).inMinutes < 60)) {
        merged.add(TrackingIncident(
          id: 'current_perm_blocked',
          type: 'permission_blocked',
          title: 'Background Location Permission Blocked',
          description: widget.locWhenInUse == PermissionStatus.granted
              ? 'Permission is set to "While in use" instead of "Allow all the time". Android restricts GPS background updates when the phone is locked or in pocket.'
              : 'Location permission is denied on this device.',
          at: DateTime.now(),
          severity: 'critical',
        ));
      }

      if (widget.pendingOfflineCount > 0 &&
          !merged.any((i) => i.type == 'offline_queue' && DateTime.now().difference(i.at).inMinutes < 30)) {
        merged.add(TrackingIncident(
          id: 'current_offline_queue',
          type: 'offline_queue',
          title: '${widget.pendingOfflineCount} Coordinates Queued Offline',
          description: 'Network offline. Coordinates are stored in local phone storage awaiting connection.',
          at: DateTime.now(),
          severity: 'warning',
        ));
      }
    }

    // Sort chronologically (oldest to newest)
    merged.sort((a, b) => a.at.compareTo(b.at));

    if (mounted) {
      setState(() {
        _incidents = merged;
        _loadingIncidents = false;
      });
    }
  }

  List<Map<String, dynamic>> get _rawTrail {
    final list = widget.rawRouteData?['trail'];
    if (list is List) {
      return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return const [];
  }

  List<({_Leg leg, String reason, Duration duration, double km, int points})> get _straightLineLegs {
    final list = <({_Leg leg, String reason, Duration duration, double km, int points})>[];
    for (final l in widget.legs) {
      final km = l.km ?? 0;
      final pts = l.path.length;
      final dur = l.toAt.difference(l.fromAt);
      if (pts <= 2 && km > 1.5) {
        final timeFmt = DateFormat('hh:mm a');
        list.add((
          leg: l,
          reason: 'Distance (${km.toStringAsFixed(1)} km) exceeds the 1.5 km road-snap limit. No intermediate GPS coordinates were captured between ${timeFmt.format(l.fromAt)} and ${timeFmt.format(l.toAt)} (${dur.inHours}h ${dur.inMinutes % 60}m).',
          duration: dur,
          km: km,
          points: pts,
        ));
      }
    }
    return list;
  }

  int get _gpsCount => _incidents.where((i) => i.isGps).length;
  int get _networkCount => _incidents.where((i) => i.isNetwork).length;
  int get _permissionCount => _incidents.where((i) => i.isPermission).length;

  List<TrackingIncident> get _filteredIncidents {
    switch (_activeFilter) {
      case _LogFilter.all:
        return _incidents;
      case _LogFilter.gps:
        return _incidents.where((i) => i.isGps).toList();
      case _LogFilter.network:
        return _incidents.where((i) => i.isNetwork).toList();
      case _LogFilter.permission:
        return _incidents.where((i) => i.isPermission).toList();
      case _LogFilter.rawTrail:
        return const [];
    }
  }

  void _copyDiagnostics(BuildContext context) {
    final timeFmt = DateFormat('hh:mm:ss a');
    final dateFmt = DateFormat('EEE, d MMM yyyy');
    final buf = StringBuffer();
    buf.writeln('=== EktaHR Route Tracking Diagnostic Report ===');
    buf.writeln('Date: ${dateFmt.format(widget.day)}');
    if (widget.staffName != null) buf.writeln('Staff: ${widget.staffName}');
    buf.writeln('Tracking Enabled: ${widget.trackingOn ? "Yes" : "No"}');
    buf.writeln('Total Distance: ${(widget.totalKm ?? 0).toStringAsFixed(1)} km (${widget.legs.length} legs)');
    if (widget.trailKm != null) buf.writeln('Whole Day Tracked: ${widget.trailKm!.toStringAsFixed(1)} km');
    buf.writeln('Total GPS Points Captured: ${_rawTrail.length}');
    buf.writeln('Pending Offline Points: ${widget.pendingOfflineCount}');
    buf.writeln('GPS Service Hardware: ${widget.gpsStatus == gl.ServiceStatus.enabled ? "Enabled" : "Disabled/Unknown"}');
    buf.writeln('Location Permission: ${widget.locAlways == PermissionStatus.granted ? "Allow all the time" : (widget.locWhenInUse == PermissionStatus.granted ? "Only while using app (Limited)" : "Denied")}');
    if (widget.healthIssues.isNotEmpty) {
      buf.writeln('Active Health Issues: ${widget.healthIssues.map((e) => e.title).join(", ")}');
    }

    buf.writeln('\n--- Incident Log Summary ---');
    buf.writeln('Total Events Logged: ${_incidents.length}');
    buf.writeln('GPS Disconnections/Gaps: $_gpsCount');
    buf.writeln('Network Outages/Queue: $_networkCount');
    buf.writeln('Permission/Battery Blocks: $_permissionCount');

    buf.writeln('\n--- Chronological Incident Log ---');
    if (_incidents.isEmpty) {
      buf.writeln('No incidents or disconnections logged for this day.');
    } else {
      for (var i = 0; i < _incidents.length; i++) {
        final inc = _incidents[i];
        buf.writeln('#${i + 1} [${timeFmt.format(inc.at)}] [${inc.type.toUpperCase()}] ${inc.title}');
        buf.writeln('   ${inc.description}');
      }
    }

    buf.writeln('\n--- Flags Timeline ---');
    for (final f in widget.flags) {
      final lat = f.pos?.latitude.toStringAsFixed(5) ?? '—';
      final lng = f.pos?.longitude.toStringAsFixed(5) ?? '—';
      buf.writeln('${f.code} [${f.type.toUpperCase()}] ${timeFmt.format(f.at)} · ($lat, $lng) · ${f.title} ${f.address}');
    }

    buf.writeln('\n--- Legs Detail ---');
    for (final l in widget.legs) {
      final dur = l.toAt.difference(l.fromAt);
      final kmStr = l.km?.toStringAsFixed(1) ?? '—';
      buf.writeln('Leg ${l.index} (${l.fromCode} -> ${l.toCode}): ${timeFmt.format(l.fromAt)} – ${timeFmt.format(l.toAt)} (${dur.inHours}h ${dur.inMinutes % 60}m) · $kmStr km · ${l.path.length} points');
    }

    if (_straightLineLegs.isNotEmpty) {
      buf.writeln('\n--- Tracking Gap / Straight-Line Analysis ---');
      for (final s in _straightLineLegs) {
        buf.writeln('⚠️ Leg ${s.leg.index}: ${s.reason}');
        buf.writeln('Likely causes:');
        buf.writeln('- Android Doze Mode / battery saver killed GPS while phone was in pocket/locked.');
        buf.writeln('- Location permission was not "Allow all the time".');
        buf.writeln('- Phone was stationary until arrival; GPS fix woke only upon tapping Field In.');
      }
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostic report copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('hh:mm a');
    final dateFmt = DateFormat('EEE, d MMM yyyy');
    final straightGaps = _straightLineLegs;
    final trail = _rawTrail;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 10, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Route Tracking Logs',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        dateFmt.format(widget.day),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy Diagnostic Report',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () => _copyDiagnostics(context),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFECEEF1)),

          // Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // 1. Diagnostic Alert (Root cause of straight lines)
                if (straightGaps.isNotEmpty) ...[
                  for (final gap in straightGaps)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Straight Line Detected (Leg ${gap.leg.index})',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            gap.reason,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF78350F), height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'What caused this during tracking:',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '• Android Doze / Battery Saver: Phone in pocket paused GPS background updates.\n'
                            '• Permission: Background location was not set to "Allow all the time".\n'
                            '• Threshold rule: Roads API does not guess driving routes for gaps > 1.5 km.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.45),
                          ),
                        ],
                      ),
                    ),
                ],

                // 2. Phone & Tracking Diagnostics Grid
                Row(
                  children: [
                    Expanded(
                      child: _diagTile(
                        icon: Icons.gps_fixed_rounded,
                        label: 'GPS Hardware',
                        value: widget.gpsStatus == gl.ServiceStatus.enabled ? 'Enabled' : 'Disabled',
                        subtext: '$_gpsCount issue(s)',
                        isGood: widget.gpsStatus == gl.ServiceStatus.enabled,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _diagTile(
                        icon: Icons.near_me_rounded,
                        label: 'Permission',
                        value: widget.locAlways == PermissionStatus.granted
                            ? 'Always Allow'
                            : (widget.locWhenInUse == PermissionStatus.granted ? 'While in use ⚠️' : 'Denied ❌'),
                        subtext: '$_permissionCount block(s)',
                        isGood: widget.locAlways == PermissionStatus.granted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _diagTile(
                        icon: Icons.sync_rounded,
                        label: 'Offline Queue',
                        value: _currentPendingCount == 0
                            ? 'All Synced'
                            : '$_currentPendingCount Pending',
                        subtext: '$_networkCount outage(s)',
                        isGood: _currentPendingCount == 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _diagTile(
                        icon: Icons.scatter_plot_rounded,
                        label: 'GPS Coordinates',
                        value: '${trail.length} Points',
                        subtext: '${widget.legs.length} Leg(s)',
                        isGood: trail.isNotEmpty,
                      ),
                    ),
                  ],
                ),
                if (_currentPendingCount > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_upload_rounded, color: Color(0xFF2563EB), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_currentPendingCount offline points queued',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              const Text(
                                'Auto-syncs automatically when network is active.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF3B82F6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _syncingNow ? null : _manualSyncOffline,
                          icon: _syncingNow
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.sync_rounded, size: 16),
                          label: Text(_syncingNow ? 'Syncing...' : 'Sync Now'),
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // 3. Filter Pills Bar
                const Text(
                  'Event Log Timeline',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChipWidget(
                        filter: _LogFilter.all,
                        label: 'All Logs',
                        count: _incidents.length,
                        activeColor: const Color(0xFF1E293B),
                        icon: Icons.format_list_bulleted_rounded,
                      ),
                      const SizedBox(width: 8),
                      _filterChipWidget(
                        filter: _LogFilter.gps,
                        label: 'GPS Off / Gaps',
                        count: _gpsCount,
                        activeColor: const Color(0xFFDC2626),
                        icon: Icons.location_off_rounded,
                      ),
                      const SizedBox(width: 8),
                      _filterChipWidget(
                        filter: _LogFilter.network,
                        label: 'Network Issues',
                        count: _networkCount,
                        activeColor: const Color(0xFFD97706),
                        icon: Icons.wifi_off_rounded,
                      ),
                      const SizedBox(width: 8),
                      _filterChipWidget(
                        filter: _LogFilter.permission,
                        label: 'Permission Blocks',
                        count: _permissionCount,
                        activeColor: const Color(0xFF7C3AED),
                        icon: Icons.security_rounded,
                      ),
                      const SizedBox(width: 8),
                      _filterChipWidget(
                        filter: _LogFilter.rawTrail,
                        label: 'GPS Fixes',
                        count: trail.length,
                        activeColor: const Color(0xFF0D9488),
                        icon: Icons.scatter_plot_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Content based on active filter
                if (_loadingIncidents)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                else if (_activeFilter == _LogFilter.rawTrail) ...[
                  if (trail.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: Text(
                          'No intermediate GPS points stored in database for this date.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: trail.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F6)),
                        itemBuilder: (ctx, idx) {
                          final p = trail[idx];
                          final lat = (p['lat'] as num?)?.toDouble().toStringAsFixed(5) ?? '—';
                          final lng = (p['lng'] as num?)?.toDouble().toStringAsFixed(5) ?? '—';
                          final tStr = p['t']?.toString() ?? '';
                          final dt = DateTime.tryParse(tStr)?.toLocal();
                          final timeStr = dt != null ? timeFmt.format(dt) : tStr;
                          final status = p['s']?.toString() ?? 'gps';
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            child: Row(
                              children: [
                                Text('#${idx + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                                const SizedBox(width: 8),
                                Text(timeStr, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                const Spacer(),
                                Text('$lat, $lng', style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontFamily: 'monospace')),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: Text(status, style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ] else if (_filteredIncidents.isEmpty) ...[
                  _emptyIncidentsView(),
                ] else ...[
                  for (final inc in _filteredIncidents) _incidentCard(inc, timeFmt),
                ],
                const SizedBox(height: 16),

                // 5. Milestones & Legs Accordion
                InkWell(
                  onTap: () => setState(() => _showMilestones = !_showMilestones),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.alt_route_rounded, size: 20, color: AppColors.textPrimary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Milestones & Travel Legs (${widget.legs.length} legs, ${widget.flags.length} stops)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ),
                        Icon(
                          _showMilestones ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showMilestones) ...[
                  const SizedBox(height: 8),
                  if (widget.flags.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('No flags recorded for this day', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ),
                    )
                  else ...[
                    for (var i = 0; i < widget.flags.length; i++) ...[
                      _flagRow(widget.flags[i], timeFmt),
                      if (i < widget.legs.length) _legRow(widget.legs[i], timeFmt),
                    ],
                  ],
                ],
                const SizedBox(height: 20),

                // 6. Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _copyDiagnostics(context),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy Report'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => openAppSettings(),
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: const Text('Phone Settings'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => gl.Geolocator.openLocationSettings(),
                        icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                        label: const Text('GPS Settings'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Permission.ignoreBatteryOptimizations.request(),
                        icon: const Icon(Icons.battery_charging_full_rounded, size: 18),
                        label: const Text('Battery Saver'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChipWidget({
    required _LogFilter filter,
    required String label,
    required int count,
    required Color activeColor,
    required IconData icon,
  }) {
    final isSelected = _activeFilter == filter;
    return InkWell(
      onTap: () => setState(() => _activeFilter = filter),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : const Color(0xFFCBD5E1).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyIncidentsView() {
    String msg;
    IconData icon;
    Color color;

    switch (_activeFilter) {
      case _LogFilter.gps:
        msg = 'No GPS disconnections or outages recorded for this day.';
        icon = Icons.gps_fixed_rounded;
        color = const Color(0xFF16A34A);
      case _LogFilter.network:
        msg = 'No network interruptions recorded. All points uploaded in real-time.';
        icon = Icons.wifi_rounded;
        color = const Color(0xFF16A34A);
      case _LogFilter.permission:
        msg = 'No permission or battery restrictions detected. Background tracking was permitted.';
        icon = Icons.verified_user_rounded;
        color = const Color(0xFF16A34A);
      default:
        msg = 'No tracking interruptions or disconnections logged for this day.';
        icon = Icons.check_circle_outline_rounded;
        color = const Color(0xFF16A34A);
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _incidentCard(TrackingIncident inc, DateFormat timeFmt) {
    Color col;
    Color bg;
    IconData icon;
    String badge;

    switch (inc.type) {
      case 'gps_off':
        col = const Color(0xFFDC2626);
        bg = const Color(0xFFFEF2F2);
        icon = Icons.location_off_rounded;
        badge = 'GPS DISCONNECTED';
      case 'gps_on':
        col = const Color(0xFF16A34A);
        bg = const Color(0xFFF0FDF4);
        icon = Icons.location_on_rounded;
        badge = 'GPS RESTORED';
      case 'gap':
        col = const Color(0xFFB91C1C);
        bg = const Color(0xFFFFF1F2);
        icon = Icons.straighten_rounded;
        badge = 'TRACKING GAP';
      case 'no_network':
        col = const Color(0xFFD97706);
        bg = const Color(0xFFFFFBEB);
        icon = Icons.wifi_off_rounded;
        badge = 'NETWORK OFFLINE';
      case 'network_on':
        col = const Color(0xFF16A34A);
        bg = const Color(0xFFF0FDF4);
        icon = Icons.wifi_rounded;
        badge = 'NETWORK RESTORED';
      case 'offline_queue':
        col = const Color(0xFFD97706);
        bg = const Color(0xFFFFFBEB);
        icon = Icons.cloud_queue_rounded;
        badge = 'OFFLINE BUFFER';
      case 'sync':
        col = const Color(0xFF2563EB);
        bg = const Color(0xFFEFF6FF);
        icon = Icons.cloud_done_rounded;
        badge = 'SYNCED TO SERVER';
      case 'permission_blocked':
        col = const Color(0xFF7C3AED);
        bg = const Color(0xFFF5F3FF);
        icon = Icons.security_rounded;
        badge = 'PERMISSION BLOCK';
      case 'permission_ok':
        col = const Color(0xFF16A34A);
        bg = const Color(0xFFF0FDF4);
        icon = Icons.verified_user_rounded;
        badge = 'PERMISSION GRANTED';
      case 'battery_restricted':
        col = const Color(0xFFD97706);
        bg = const Color(0xFFFFFBEB);
        icon = Icons.battery_alert_rounded;
        badge = 'BATTERY RESTRICTED';
      case 'battery_ok':
        col = const Color(0xFF16A34A);
        bg = const Color(0xFFF0FDF4);
        icon = Icons.battery_charging_full_rounded;
        badge = 'BATTERY UNRESTRICTED';
      default:
        col = const Color(0xFF4B5563);
        bg = const Color(0xFFF9FAFB);
        icon = Icons.info_outline_rounded;
        badge = 'INCIDENT';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: col),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: col.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: col),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          timeFmt.format(inc.at),
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      inc.title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              inc.description,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563), height: 1.35),
            ),
          ),
          if (inc.type == 'permission_blocked' || inc.type == 'battery_restricted') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings_outlined, size: 14),
                label: const Text('Open App Settings', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  foregroundColor: col,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ] else if (inc.type == 'gps_off') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => gl.Geolocator.openLocationSettings(),
                icon: const Icon(Icons.location_on_outlined, size: 14),
                label: const Text('Open GPS Settings', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  foregroundColor: col,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _diagTile({
    required IconData icon,
    required String label,
    required String value,
    required String subtext,
    required bool isGood,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isGood ? AppColors.success : const Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isGood ? AppColors.textPrimary : const Color(0xFFD97706),
                  ),
                ),
                Text(
                  subtext,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flagRow(_Flag f, DateFormat timeFmt) {
    Color col;
    switch (f.type) {
      case 'punch_in':
        col = const Color(0xFF16A34A);
      case 'punch_out':
        col = const Color(0xFFDC2626);
      case 'field_in':
        col = const Color(0xFF2563EB);
      case 'field_out':
        col = const Color(0xFFD97706);
      default:
        col = const Color(0xFF6B7280);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              f.code,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: col),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                if (f.address.isNotEmpty)
                  Text(
                    f.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Text(
            timeFmt.format(f.at),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _legRow(_Leg l, DateFormat timeFmt) {
    final dur = l.toAt.difference(l.fromAt);
    final isStraight = l.path.length <= 2 && (l.km ?? 0) > 1.5;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: l.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: l.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isStraight ? Icons.straighten_rounded : Icons.alt_route_rounded,
            size: 16,
            color: l.color,
          ),
          const SizedBox(width: 6),
          Text(
            'Leg ${l.index}: ${l.km?.toStringAsFixed(1) ?? '—'} km',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: l.color),
          ),
          const SizedBox(width: 6),
          Text(
            '(${dur.inHours > 0 ? '${dur.inHours}h ' : ''}${dur.inMinutes % 60}m)',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: isStraight ? const Color(0xFFFEF3C7) : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isStraight ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1)),
            ),
            child: Text(
              isStraight ? 'Straight line (${l.path.length} pts)' : '${l.path.length} GPS pts',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isStraight ? const Color(0xFFB45309) : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

