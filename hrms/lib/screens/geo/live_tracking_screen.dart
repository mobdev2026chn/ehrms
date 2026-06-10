import 'dart:async';
import 'dart:math' as math;
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/constants.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/location_data.dart';
import 'package:hrms/models/tracking_event.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/geo/accurate_location_helper.dart';
import 'package:hrms/services/geo/directions_service.dart';
import 'package:hrms/services/geo/location_service.dart'
    show LocationService, GeofenceEvent;
import 'package:hrms/screens/geo/pin_destination_map_screen.dart';
import 'package:hrms/screens/geo/my_tasks_screen.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/services/presence_tracking_service.dart';
import 'package:hrms/services/geo/live_tracking_service.dart';
import 'package:hrms/services/geo/movement_classification_service.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/screens/geo/arrived_screen.dart';
import 'package:hrms/screens/geo/exit_ride_bottom_sheet.dart';
import 'package:hrms/screens/geo/task_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:floating/floating.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String taskId;

  /// MongoDB task id for API calls (location, steps, end). Optional for backward compatibility.
  final String? taskMongoId;
  final LatLng pickupLocation;
  final LatLng dropoffLocation;

  /// Optional task (with customer) for Arrived → OTP → Task Completed flow.
  final Task? task;

  const LiveTrackingScreen({
    super.key,
    required this.taskId,
    this.taskMongoId,
    required this.pickupLocation,
    required this.dropoffLocation,
    this.task,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with WidgetsBindingObserver {
  GoogleMapController? mapController;
  Task? _taskState;

  Marker? _staffMarker;

  Marker? _pickupMarker;

  Marker? _dropoffMarker;

  /// Mutable destination – can change during task via search or pin drop.
  LatLng get _dropoffLatLng => _dropoffLatLngState ?? widget.dropoffLocation;
  LatLng? _dropoffLatLngState;
  String _dropoffAddress = '';
  bool _updatingDestination = false;

  Task? get _task => _taskState ?? widget.task;

  /// Path built ONLY from actual GPS coordinates (List<LatLng> from location stream).
  Polyline? _routePolyline;

  /// Road route from current/last position to destination (fetched from Directions API).
  Polyline? _shortestRoutePolyline;
  double _plannedTripDistanceKm = 0.0;
  double _remainingDistanceKm = 0.0;
  DateTime? _lastRouteFetchTime;
  static const _routeRefreshInterval = Duration(seconds: 60);
  String? _etaText;
  int _etaMinutes = 0;
  Timer? _etaUpdateTimer;

  StreamSubscription? _locationSubscription;

  StreamSubscription? _geofenceSubscription;

  final List<TrackingEvent> _trackingEvents = [];

  Location? _lastLocation;
  ResolvedAddress? _lastResolvedTrackingAddress;
  double? _lastResolvedTrackingLat;
  double? _lastResolvedTrackingLng;

  int _addressDetailScore(ResolvedAddress? address) {
    if (address == null) return -1;
    final text = address.formattedAddress.trim();
    if (text.isEmpty) return -1;

    var score = 0;
    if (address.area != null && address.area!.trim().isNotEmpty) score += 2;
    if (address.city != null && address.city!.trim().isNotEmpty) score += 1;
    if (address.pincode != null && address.pincode!.trim().isNotEmpty) {
      score += 1;
    }
    if (RegExp(r'\d').hasMatch(text)) score += 2;
    if (RegExp(
      r'\b(road|rd|street|st|lane|ln|nagar|main)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      score += 2;
    }
    score += ','.allMatches(text).length.clamp(0, 3);
    return score;
  }

  bool _hasDetailedTrackingAddress(ResolvedAddress? address) {
    return _addressDetailScore(address) >= 5;
  }

  Future<gl.Position> _captureTrackingPosition() {
    // Match attendance-style capture until we have a strong road-level address.
    if (_hasDetailedTrackingAddress(_lastResolvedTrackingAddress)) {
      return getPositionForTrackings(
        primaryTimeout: const Duration(seconds: 8),
        sampleWindow: const Duration(seconds: 2),
        stopEarlyWhenAccuracyMeters: 10,
        maxSamples: 8,
      );
    }
    return getAccuratePositionForUi();
  }

  String _currentActivity = "Standing";

  double _totalDistanceCovered = 0.0;

  /// Resolved after [LiveTrackingService.startTracking] (wall clock; not timer-based).
  DateTime? _tripStartUtc;

  Duration _drivingDuration = Duration.zero;
  Duration _walkingDuration = Duration.zero;
  Duration _stopDuration = Duration.zero;

  Timer? _timer;

  bool _isInsideGeofence = false;

  /// Geofence status for UX: null = inside/no message, else soft or warning message.
  String? _geofenceStatusMessage;

  /// Elapsed time for the trip — uses wall clock so it stays correct after sleep / app restart.
  Duration get _elapsedDuration {
    final start = _tripStartUtc;
    if (start == null) return Duration.zero;
    final d = DateTime.now().difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  // Step-based progress (Next Steps card).
  bool _reachedLocation = false;
  final bool _photoProof = false;
  final bool _formFilled = false;
  final bool _otpVerified = false;
  bool _updatingSteps = false;
  bool _submittingArrived = false;

  /// True once arrived has been successfully sent; keeps Arrived button disabled.
  bool _arrivedSent = false;
  Timer? _locationUploadTimer;

  final Floating _floating = Floating();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _taskState = widget.task;
    // Provisional; [_bootstrapTripClock] refines from prefs / API for accurate wall-clock elapsed.
    _tripStartUtc = widget.task?.startTime;
    if (_task?.status == TaskStatus.arrived) _arrivedSent = true;
    final initialDestination = _task?.destinationLocation;
    if (initialDestination != null &&
        (initialDestination.lat != 0 || initialDestination.lng != 0)) {
      _dropoffLatLngState = LatLng(
        initialDestination.lat,
        initialDestination.lng,
      );
    }
    _dropoffAddress =
        _task?.destinationLocation?.displayAddress ??
        (_task?.customer != null
            ? '${_task!.customer!.address}, ${_task!.customer!.city} ${_task!.customer!.pincode}'
            : 'Drop-off location');
    _initializeMarkers();

    LocationService().initLocationService(
      customerLocation: widget.dropoffLocation,
      context: context,
    );
    MovementClassificationService().start();

    _addTrackingEvent(
      TrackingEventType.punchIn,

      DateTime.now(),

      locationDescription: "Task Started at Pickup Location",
    );

    _listenToLocationUpdates();

    _listenToGeofenceUpdates();

    _startTimer();

    _updateRemainingEta();

    // Initial straight line; fetch road route from pickup to dropoff (replaces when ready)
    _shortestRoutePolyline = Polyline(
      polylineId: const PolylineId('roadRoute'),
      points: [widget.pickupLocation, _dropoffLatLng],
      color: Colors.green.withOpacity(0.8),
      width: 4,
      patterns: [PatternItem.dash(20), PatternItem.gap(12)],
      geodesic: true,
    );
    _fetchRoadRoute(
      widget.pickupLocation.latitude,
      widget.pickupLocation.longitude,
    );
    _fetchPlannedTripRoute();

    // Persist trip start + start GPS uploads after first frame (async; needs awaited startTracking).
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapTripClock());

    _enablePipOnMinimize();
  }

  /// Starts background tracking, restores wall-clock trip start from prefs / server, then timers.
  Future<void> _bootstrapTripClock() async {
    if (widget.taskMongoId == null || widget.taskMongoId!.isEmpty) {
      _tripStartUtc = widget.task?.startTime ?? DateTime.now();
      if (mounted) setState(() {});
      return;
    }
    await LiveTrackingService().startTracking(
      taskMongoId: widget.taskMongoId!,
      taskId: widget.taskId,
      pickupLat: widget.pickupLocation.latitude,
      pickupLng: widget.pickupLocation.longitude,
      dropoffLat: _dropoffLatLng.latitude,
      dropoffLng: _dropoffLatLng.longitude,
    );
    // Server startTime is authoritative if prefs were cleared on cold start (race) or mistaken sync.
    DateTime? serverStart;
    try {
      final t = await TaskService().getTaskById(widget.taskMongoId!);
      serverStart = t.startTime;
      if (mounted) _taskState = t;
    } catch (_) {}

    DateTime? resolved = serverStart ?? widget.task?.startTime;
    final ms = await LiveTrackingService().getTripStartMs();
    if (resolved == null && ms != null) {
      resolved = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (resolved == null) {
      resolved = DateTime.now();
    } else {
      await LiveTrackingService().persistTripStartMs(
        resolved.millisecondsSinceEpoch,
      );
    }
    _tripStartUtc = resolved;
    if (mounted) setState(() {});

    // Send first point after 2 sec, then periodically by configured capture interval.
    Future.delayed(const Duration(seconds: 2), () {
      _sendLocationToDb();
      _syncPendingDestinationIfAny();
    });
    final captureInterval = Duration(
      seconds: AppConstants.taskTrackingCaptureIntervalSeconds,
    );
    _locationUploadTimer = Timer.periodic(captureInterval, (_) {
      if (!mounted) return;
      _sendLocationToDb();
    });
  }

  Future<void> _enablePipOnMinimize() async {
    try {
      final available = await _floating.isPipAvailable;
      if (available && mounted) {
        await _floating.enable(OnLeavePiP(aspectRatio: Rational.landscape()));
      }
    } catch (e) {
      // PiP not available
    }
  }

  void _initializeMarkers() {
    _pickupMarker = Marker(
      markerId: const MarkerId('pickupLocation'),

      position: widget.pickupLocation,

      infoWindow: const InfoWindow(title: 'Pickup Location'),

      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    );

    _dropoffMarker = Marker(
      markerId: const MarkerId('dropoffLocation'),
      position: _dropoffLatLng,
      infoWindow: InfoWindow(
        title: _dropoffAddress.isNotEmpty
            ? _dropoffAddress
            : 'Drop-off Location',
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      draggable: true,
      onDragEnd: _onDropoffMarkerDragEnd,
    );

    _staffMarker = Marker(
      markerId: const MarkerId('staffLocation'),

      position: widget.pickupLocation, // Initial position, will be updated

      infoWindow: const InfoWindow(title: 'My Location'),

      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );
  }

  void _listenToLocationUpdates() {
    _locationSubscription = LocationService().locationStream.listen((
      Location location,
    ) {
      if (mounted) {
        setState(() {
          final newLatLng = LatLng(location.latitude!, location.longitude!);

          _staffMarker = _staffMarker?.copyWith(positionParam: newLatLng);

          mapController?.animateCamera(CameraUpdate.newLatLng(newLatLng));

          _updateRoutePolyline(newLatLng, accuracyM: location.accuracy);

          if (_lastLocation != null) {
            double distance = gl.Geolocator.distanceBetween(
              _lastLocation!.latitude!,
              _lastLocation!.longitude!,
              location.latitude!,
              location.longitude!,
            );
            _totalDistanceCovered += distance;
          }

          final movementType = MovementClassificationService()
              .addLocationAndClassify(
                lat: location.latitude!,
                lng: location.longitude!,
                time: DateTime.now(),
                accuracyM: location.accuracy,
                inBackground: false,
              );
          final newActivityType = _movementTypeToEventType(movementType);
          if (_currentActivity != movementType) {
            _addTrackingEvent(newActivityType, DateTime.now());
            _currentActivity = movementType;
          }

          _lastLocation = location;
          _updateRemainingEta();
        });
      }
    });
  }

  Future<void> _sendLocationToDb() async {
    if (widget.taskMongoId == null || widget.taskMongoId!.isEmpty) return;
    // Get FRESH position from GPS before sending – ensures correct lat/lng as you move.
    double lat;
    double lng;
    double? accuracyM;
    double? speedMps;
    try {
      final pos = await _captureTrackingPosition();
      lat = pos.latitude;
      lng = pos.longitude;
      accuracyM = pos.accuracy;
      speedMps = (pos.speed.isFinite && pos.speed >= 0) ? pos.speed : null;
    } catch (e) {
      final loc = _lastLocation;
      if (loc != null && loc.latitude != null && loc.longitude != null) {
        lat = loc.latitude!;
        lng = loc.longitude!;
        accuracyM = loc.accuracy;
        speedMps = (loc.speed != null && loc.speed!.isFinite && loc.speed! >= 0)
            ? loc.speed
            : null;
      } else {
        lat = widget.pickupLocation.latitude;
        lng = widget.pickupLocation.longitude;
      }
    }
    int? battery;
    try {
      battery = await Battery().batteryLevel;
    } catch (_) {}
    final resolvedAddress = await _resolveTrackingAddress(lat, lng);
    final movementClassifier = MovementClassificationService();
    final movementType = movementClassifier.addLocationAndClassify(
      lat: lat,
      lng: lng,
      time: DateTime.now(),
      accuracyM: accuracyM,
      inBackground: false,
    );
    final taskSvc = TaskService();
    taskSvc
        .updateLocation(
          widget.taskMongoId!,
          lat,
          lng,
          batteryPercent: battery,
          movementType: movementType,
          address: resolvedAddress?.formattedAddress,
          fullAddress: resolvedAddress?.formattedAddress,
          city: resolvedAddress?.city ?? resolvedAddress?.state,
          area: resolvedAddress?.area,
          pincode: resolvedAddress?.pincode,
        )
        .catchError((e) {});
    taskSvc
        .storeTracking(
          widget.taskMongoId!,
          lat,
          lng,
          batteryPercent: battery,
          movementType: movementType,
          accuracyM: accuracyM,
          speedMps: speedMps,
          consecutiveLowSpeed: movementClassifier.consecutiveLowSpeedCount,
          destinationLat: _dropoffLatLng.latitude,
          destinationLng: _dropoffLatLng.longitude,
          address: resolvedAddress?.formattedAddress,
          fullAddress: resolvedAddress?.formattedAddress,
          city: resolvedAddress?.city ?? resolvedAddress?.state,
          area: resolvedAddress?.area,
          pincode: resolvedAddress?.pincode,
        )
        .then((stored) {
          _syncPendingDestinationIfAny();
        })
        .catchError((e) {});
  }

  Future<ResolvedAddress?> _resolveTrackingAddress(
    double lat,
    double lng,
  ) async {
    final cached = _lastResolvedTrackingAddress;
    if (_lastResolvedTrackingAddress != null &&
        _lastResolvedTrackingLat != null &&
        _lastResolvedTrackingLng != null) {
      final distance = gl.Geolocator.distanceBetween(
        _lastResolvedTrackingLat!,
        _lastResolvedTrackingLng!,
        lat,
        lng,
      );
      if (distance <= 30 && _hasDetailedTrackingAddress(cached)) {
        return cached;
      }
    }

    final resolved = await AddressResolutionService.reverseGeocode(lat, lng);
    final resolvedScore = _addressDetailScore(resolved);
    final cachedScore = _addressDetailScore(cached);
    final bestResolved = cachedScore > resolvedScore && cached != null
        ? cached
        : resolved;

    if (bestResolved != null) {
      _lastResolvedTrackingAddress = bestResolved;
      _lastResolvedTrackingLat = lat;
      _lastResolvedTrackingLng = lng;
      await LiveTrackingService.persistResolvedAddress(
        lat,
        lng,
        address: bestResolved.formattedAddress,
        fullAddress: bestResolved.formattedAddress,
        city: bestResolved.city ?? bestResolved.state,
        area: bestResolved.area,
        pincode: bestResolved.pincode,
      );
    }
    return bestResolved;
  }

  TrackingEventType _movementTypeToEventType(String movementType) {
    switch (movementType) {
      case 'drive':
      case 'driving':
        return TrackingEventType.drive;
      case 'walk':
      case 'walking':
        return TrackingEventType.walk;
      case 'stop':
      default:
        return TrackingEventType.stop;
    }
  }

  String _getMovementDisplay() {
    switch (_currentActivity.toLowerCase()) {
      case 'drive':
      case 'driving':
        return 'Driving';
      case 'walk':
      case 'walking':
        return 'Walking';
      case 'stop':
      case 'standing':
      default:
        return 'Stopped';
    }
  }

  void _addTrackingEvent(
    TrackingEventType type,

    DateTime timestamp, {

    double? distance,

    Duration? duration,

    String? locationDescription,
  }) {
    _trackingEvents.add(
      TrackingEvent(
        type: type,

        timestamp: timestamp,

        distance: distance,

        duration: duration,

        locationDescription: locationDescription,
      ),
    );
  }

  /// Total trip distance (pickup to dropoff) in km, for progress bar denominator.
  double get _totalTripDistanceKm => _plannedTripDistanceKm;

  void _onDropoffMarkerDragEnd(LatLng newPosition) {
    _applyDestinationChange(
      newPosition,
      initialAddress: 'Dropped pin',
      resolveAddress: true,
    );
  }

  Future<String> _resolveDropoffAddress(double lat, double lng) async {
    try {
      final resolved = await AddressResolutionService.reverseGeocode(lat, lng);
      if (resolved != null && resolved.formattedAddress.trim().isNotEmpty) {
        return resolved.formattedAddress;
      }
    } catch (_) {
      // Fall back to coordinates below.
    }
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  void _updateDropoffMarker() {
    setState(() {
      _dropoffMarker = Marker(
        markerId: const MarkerId('dropoffLocation'),
        position: _dropoffLatLng,
        infoWindow: InfoWindow(
          title: _dropoffAddress.isNotEmpty
              ? _dropoffAddress
              : 'Drop-off Location',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        draggable: true,
        onDragEnd: _onDropoffMarkerDragEnd,
      );
    });
  }

  Future<void> _applyDestinationChange(
    LatLng newPosition, {
    required String initialAddress,
    required bool resolveAddress,
  }) async {
    setState(() {
      _dropoffLatLngState = newPosition;
      _dropoffAddress = initialAddress;
      _updatingDestination = true;
    });
    LocationService().updateGeofenceCenter(newPosition);
    await LiveTrackingService().updateDestination(
      dropoffLat: newPosition.latitude,
      dropoffLng: newPosition.longitude,
    );
    _lastRouteFetchTime = null;
    _plannedTripDistanceKm = 0.0;
    _updateDropoffMarker();
    _fetchPlannedTripRoute();
    _fetchRoadRoute(
      _lastLocation?.latitude ?? widget.pickupLocation.latitude,
      _lastLocation?.longitude ?? widget.pickupLocation.longitude,
    );

    final resolvedAddress = resolveAddress
        ? await _resolveDropoffAddress(
            newPosition.latitude,
            newPosition.longitude,
          )
        : initialAddress;
    if (!mounted) return;
    setState(() {
      _dropoffAddress = resolvedAddress;
    });
    _updateDropoffMarker();
    await _updateDestinationOnBackend(addressOverride: resolvedAddress);
  }

  void _applyUpdatedTask(Task updatedTask) {
    _taskState = updatedTask;
    final destination = updatedTask.destinationLocation;
    if (destination != null && (destination.lat != 0 || destination.lng != 0)) {
      _dropoffLatLngState = LatLng(destination.lat, destination.lng);
      if ((destination.displayAddress ?? '').trim().isNotEmpty) {
        _dropoffAddress = destination.displayAddress!.trim();
      }
    }
  }

  Future<void> _updateDestinationOnBackend({String? addressOverride}) async {
    if (widget.taskMongoId == null || widget.taskMongoId!.isEmpty) return;
    final payload = {
      'lat': _dropoffLatLng.latitude,
      'lng': _dropoffLatLng.longitude,
      'address': addressOverride ?? _dropoffAddress,
    };
    try {
      final updatedTask = await TaskService().updateTask(
        widget.taskMongoId!,
        destinationLocation: payload,
        destinationChanged: true,
      );
      await _clearPendingDestinationCache();
      if (mounted) {
        setState(() {
          _applyUpdatedTask(updatedTask);
          _updatingDestination = false;
        });
      }
    } catch (e) {
      await _cachePendingDestination(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Destination updated locally. Will sync when online.',
            ),
          ),
        );
        setState(() => _updatingDestination = false);
      }
    }
  }

  String get _pendingDestKey =>
      'pending_destination_${widget.taskMongoId ?? ""}';

  Future<void> _cachePendingDestination(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pendingDestKey,
        '${payload['lat']}|${payload['lng']}|${payload['address'] ?? ''}',
      );
    } catch (_) {}
  }

  Future<void> _clearPendingDestinationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingDestKey);
    } catch (_) {}
  }

  Future<void> _syncPendingDestinationIfAny() async {
    if (widget.taskMongoId == null || widget.taskMongoId!.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingDestKey);
      if (raw == null || raw.isEmpty) return;
      final parts = raw.split('|');
      if (parts.length < 2) return;
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      final address = parts.length > 2 ? parts[2] : '';
      if (lat == null || lng == null) return;
      await TaskService().updateTask(
        widget.taskMongoId!,
        destinationLocation: {'lat': lat, 'lng': lng, 'address': address},
        destinationChanged: true,
      );
      await _clearPendingDestinationCache();
    } catch (_) {}
  }

  void _onChangeDestinationTap() async {
    final result = await Navigator.of(context).push<PinDestinationResult>(
      MaterialPageRoute(
        builder: (context) => PinDestinationMapScreen(
          initialCenter: _lastLocation != null
              ? LatLng(_lastLocation!.latitude!, _lastLocation!.longitude!)
              : LatLng(
                  widget.pickupLocation.latitude,
                  widget.pickupLocation.longitude,
                ),
          initialPin: _dropoffLatLngState ?? widget.dropoffLocation,
        ),
      ),
    );
    if (result != null && mounted) {
      final newDest = LatLng(result.lat, result.lng);
      await _applyDestinationChange(
        newDest,
        initialAddress: result.address,
        resolveAddress: false,
      );
    }
  }

  Future<void> _fetchRoadRoute(double fromLat, double fromLng) async {
    final now = DateTime.now();
    if (_lastRouteFetchTime != null &&
        now.difference(_lastRouteFetchTime!) < _routeRefreshInterval) {
      return;
    }
    _lastRouteFetchTime = now;
    try {
      final result = await DirectionsService.getRouteBetweenCoordinates(
        originLat: fromLat,
        originLng: fromLng,
        destLat: _dropoffLatLng.latitude,
        destLng: _dropoffLatLng.longitude,
      );
      if (mounted && result.points.isNotEmpty) {
        setState(() {
          _shortestRoutePolyline = Polyline(
            polylineId: const PolylineId('roadRoute'),
            points: result.points,
            color: Colors.green.withOpacity(0.8),
            width: 4,
            patterns: [PatternItem.dash(20), PatternItem.gap(12)],
          );
          _remainingDistanceKm = result.distanceKm;
          if (result.durationText != null) {
            final match = RegExp(
              r'~?(\d+)\s*min',
            ).firstMatch(result.durationText!);
            if (match != null) {
              _etaMinutes = int.tryParse(match.group(1) ?? '0') ?? 0;
              _etaText = result.durationText;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _shortestRoutePolyline = Polyline(
            polylineId: const PolylineId('roadRoute'),
            points: [LatLng(fromLat, fromLng), _dropoffLatLng],
            color: Colors.green.withOpacity(0.8),
            width: 4,
            patterns: [PatternItem.dash(20), PatternItem.gap(12)],
            geodesic: true,
          );
        });
      }
    }
  }

  Future<void> _fetchPlannedTripRoute() async {
    try {
      final result = await DirectionsService.getRouteBetweenCoordinates(
        originLat: widget.pickupLocation.latitude,
        originLng: widget.pickupLocation.longitude,
        destLat: _dropoffLatLng.latitude,
        destLng: _dropoffLatLng.longitude,
      );
      if (mounted && result.distanceKm > 0) {
        setState(() {
          _plannedTripDistanceKm = result.distanceKm;
          if (_remainingDistanceKm <= 0) {
            _remainingDistanceKm = result.distanceKm;
          }
        });
      }
    } catch (_) {}
  }

  /// Minimum move before a new vertex is added to the traveled line (drops
  /// GPS jitter that would otherwise zig-zag the path while standing still).
  static const double _minTraveledMoveMeters = 6;

  void _updateRoutePolyline(LatLng newLatLng, {double? accuracyM}) {
    // Ignore low-accuracy fixes – they are the main source of route glitches.
    if (accuracyM != null && accuracyM > kMaxAccuracyM) {
      _updateRemainingEta();
      return;
    }

    if (_routePolyline == null) {
      _routePolyline = Polyline(
        polylineId: const PolylineId('traveled'),
        points: [widget.pickupLocation, newLatLng],
        color: Colors.blueAccent.withOpacity(0.7),
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        geodesic: true,
      );
    } else {
      final currentPoints = List<LatLng>.from(_routePolyline!.points);
      final last = currentPoints.isNotEmpty ? currentPoints.last : null;
      if (last != null) {
        final movedM = gl.Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          newLatLng.latitude,
          newLatLng.longitude,
        );
        // Skip near-duplicates / jitter; only extend on real movement.
        if (movedM < _minTraveledMoveMeters) {
          _updateRemainingEta();
          _fetchRoadRoute(newLatLng.latitude, newLatLng.longitude);
          return;
        }
      }
      currentPoints.add(newLatLng);
      _routePolyline = _routePolyline?.copyWith(pointsParam: currentPoints);
    }
    _updateRemainingEta();
    // Refresh road route periodically from current position
    _fetchRoadRoute(newLatLng.latitude, newLatLng.longitude);
  }

  void _updateRemainingEta() {
    if (_remainingDistanceKm > 0) return;

    // Use last known location, or pickup if no location yet
    final fromLat = _lastLocation?.latitude ?? widget.pickupLocation.latitude;
    final fromLng = _lastLocation?.longitude ?? widget.pickupLocation.longitude;
    final toDrop = gl.Geolocator.distanceBetween(
      fromLat,
      fromLng,
      _dropoffLatLng.latitude,
      _dropoffLatLng.longitude,
    );
    final km = toDrop / 1000;
    if (mounted) {
      setState(() {
        _remainingDistanceKm = km;
        // Shortest distance from live location to destination; ETA based on speed
        final normalized = _currentActivity.toLowerCase();
        final speedKmh = normalized == 'walk' || normalized == 'walking'
            ? 5.0
            : 30.0;
        final min = (km / speedKmh * 60).round().clamp(0, 999);
        _etaMinutes = min;
        _etaText = min > 60 ? '~${min ~/ 60} h' : '~$min min';
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // Elapsed uses [_elapsedDuration] (wall clock), not tick counting — survives background/sleep.
          switch (_currentActivity.toLowerCase()) {
            case 'drive':
            case 'driving':
              _drivingDuration += const Duration(seconds: 1);
              break;
            case 'walk':
            case 'walking':
              _walkingDuration += const Duration(seconds: 1);
              break;
            case 'stop':
            case 'standing':
            default:
              _stopDuration += const Duration(seconds: 1);
              break;
          }
        });
      }
    });
  }

  void _listenToGeofenceUpdates() {
    _geofenceSubscription = LocationService().geofenceStream.listen((event) {
      if (mounted) {
        setState(() {
          _isInsideGeofence = event == GeofenceEvent.enter;
          switch (event) {
            case GeofenceEvent.enter:
              _geofenceStatusMessage = null;
              break;
            case GeofenceEvent.exit:
              _geofenceStatusMessage =
                  '⚠️ You are outside the destination area';
              break;
            case GeofenceEvent.lowAccuracy:
              _geofenceStatusMessage = '📡 Waiting for accurate GPS signal…';
              break;
            default:
              _geofenceStatusMessage = null;
          }
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _lastRouteFetchTime = null;
      final fromLat = _lastLocation?.latitude ?? widget.pickupLocation.latitude;
      final fromLng =
          _lastLocation?.longitude ?? widget.pickupLocation.longitude;
      _fetchRoadRoute(fromLat, fromLng);
      setState(
        () {},
      ); // Refresh wall-clock elapsed immediately when returning from background.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _geofenceSubscription?.cancel();
    _timer?.cancel();
    _etaUpdateTimer?.cancel();
    _locationUploadTimer?.cancel();
    _floating.cancelOnLeavePiP();
    MovementClassificationService().stop();
    LocationService().dispose();
    super.dispose();
  }

  /// Exit Ride: open bottom sheet with reason form. Submit mandatory.
  /// Sends current GPS for address resolution. Stops tracking immediately.
  Future<void> _onExitRide() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ExitRideBottomSheet(),
    );
    if (result == null || !mounted) return;
    final exitType = result['exitType'];
    final reason = result['reason']?.trim();
    if (exitType == null ||
        exitType.isEmpty ||
        reason == null ||
        reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select exit type and provide a reason'),
        ),
      );
      return;
    }
    if (widget.taskMongoId != null && widget.taskMongoId!.isNotEmpty) {
      try {
        double? lat;
        double? lng;
        try {
          final pos = await gl.Geolocator.getCurrentPosition(
            desiredAccuracy: gl.LocationAccuracy.high,
          );
          lat = pos.latitude;
          lng = pos.longitude;
        } catch (_) {
          if (_lastLocation != null) {
            lat = _lastLocation!.latitude;
            lng = _lastLocation!.longitude;
          }
        }
        await TaskService().exitRide(
          widget.taskMongoId!,
          reason,
          exitType: exitType,
          lat: lat,
          lng: lng,
        );
        await LiveTrackingService().stopTracking();
        await PresenceTrackingService().resumePresenceTracking();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMessageUtils.toUserFriendlyMessage(e))),
          );
        }
        return;
      }
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MyTasksScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _markReachedLocation() async {
    if (_reachedLocation || _updatingSteps || widget.taskMongoId == null) {
      return;
    }
    setState(() => _updatingSteps = true);
    try {
      await TaskService().updateSteps(
        widget.taskMongoId!,
        reachedLocation: true,
      );
      if (mounted) {
        setState(() {
          _reachedLocation = true;
          _updatingSteps = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _updatingSteps = false);
    }
  }

  Future<void> _onArrived() async {
    if (_submittingArrived || _arrivedSent) return;
    final totalKm = _totalDistanceCovered / 1000;
    final arrival = DateTime.now();
    final durationSeconds = _elapsedDuration.inSeconds;
    Task? arrivedTask = _task;

    double? lat = _lastLocation?.latitude ?? widget.pickupLocation.latitude;
    double? lng = _lastLocation?.longitude ?? widget.pickupLocation.longitude;
    try {
      final pos = await gl.Geolocator.getCurrentPosition(
        desiredAccuracy: gl.LocationAccuracy.high,
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    if (widget.taskMongoId != null &&
        widget.taskMongoId!.isNotEmpty &&
        lat != null &&
        lng != null) {
      if (mounted) setState(() => _submittingArrived = true);
      try {
        // Arrival lat/lng = staff GPS here (above). Do not send destination as fullAddress —
        // DB arrival fields must describe this point; backend reverse-geocodes lat/lng.
        final sourceAddress =
            _task?.sourceLocation?.address ??
            (_task?.customer != null
                ? '${_task!.customer!.address}, ${_task!.customer!.city}'
                : null);
        await TaskService().arrivedRide(
          widget.taskMongoId!,
          lat: lat,
          lng: lng,
          sourceFullAddress: sourceAddress,
          tripDistanceKm: totalKm,
          tripDurationSeconds: durationSeconds,
          sourceLocation: {
            'lat': widget.pickupLocation.latitude,
            'lng': widget.pickupLocation.longitude,
            'address': sourceAddress,
            'fullAddress': sourceAddress,
          },
          travelActivityDuration: {
            'driveDuration': _drivingDuration.inSeconds,
            'walkDuration': _walkingDuration.inSeconds,
            'stopDuration': _stopDuration.inSeconds,
          },
        );
        try {
          arrivedTask = await TaskService().getTaskById(widget.taskMongoId!);
          _taskState = arrivedTask;
        } catch (_) {}
        if (mounted) {
          setState(() {
            _reachedLocation = true;
            _arrivedSent = true;
          });
        }
        await LiveTrackingService().stopTracking();
      } catch (_) {
        if (mounted) setState(() => _submittingArrived = false);
        return;
      }
      // _arrivedSent and _submittingArrived keep Arrived button disabled
    }
    if (!mounted) return;
    String? arrivalAddr;
    if (lat != null && lng != null) {
      try {
        arrivalAddr = (await AddressResolutionService.reverseGeocode(
          lat,
          lng,
        ))?.formattedAddress;
      } catch (_) {}
      arrivalAddr ??= '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ArrivedScreen(
          taskMongoId: widget.taskMongoId,
          taskId: widget.taskId,
          task: arrivedTask,
          totalDuration: Duration(
            seconds:
                arrivedTask?.tripDurationSeconds ?? _elapsedDuration.inSeconds,
          ),
          totalDistanceKm: arrivedTask?.tripDistanceKm ?? totalKm,
          isWithinGeofence: _isInsideGeofence,
          arrivalTime: arrival,
          sourceLat: widget.pickupLocation.latitude,
          sourceLng: widget.pickupLocation.longitude,
          sourceAddress: _task?.sourceLocation?.address,
          destLat: _dropoffLatLng.latitude,
          destLng: _dropoffLatLng.longitude,
          destAddress: _dropoffAddress.isNotEmpty
              ? _dropoffAddress
              : (_task?.destinationLocation?.displayAddress ??
                    (_task?.customer != null
                        ? '${_task!.customer!.address}, ${_task!.customer!.city} ${_task!.customer!.pincode}'
                        : null)),
          arrivalAtLat: lat,
          arrivalAtLng: lng,
          arrivalAtAddress: arrivalAddr,
          drivingDuration: _drivingDuration,
          walkingDuration: _walkingDuration,
          stopDuration: _stopDuration,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");

    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));

    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));

    return "${twoDigits(duration.inHours)}h ${twoDigitMinutes}m ${twoDigitSeconds}s";
  }

  Widget _buildBottomPanelContent() {
    final totalDistanceKm = _totalDistanceCovered / 1000;
    final etaArrivalTime = DateTime.now().add(Duration(minutes: _etaMinutes));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trip Progress',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _totalTripDistanceKm > 0
                ? (totalDistanceKm / _totalTripDistanceKm).clamp(0.0, 1.0)
                : 0.0,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              _buildTravelRow(
                Icons.route_rounded,
                'Total distance',
                '${totalDistanceKm.toStringAsFixed(2)} km',
              ),
              const SizedBox(height: 4),
              _buildTravelRow(
                Icons.near_me_rounded,
                'Shortest remaining',
                '${_remainingDistanceKm.toStringAsFixed(2)} km',
              ),
              const SizedBox(height: 4),
              _buildTravelRow(
                Icons.straighten_rounded,
                'Trip distance',
                '${_totalTripDistanceKm.toStringAsFixed(2)} km',
              ),
              const SizedBox(height: 4),
              _buildTravelRow(
                Icons.timer_outlined,
                'Elapsed',
                _formatDuration(_elapsedDuration),
              ),
              const SizedBox(height: 4),
              _buildTravelRow(
                Icons.schedule_rounded,
                'ETA',
                DateDisplayUtil.formatTime(etaArrivalTime),
              ),
            ],
          ),
        ),
        if (_geofenceStatusMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _geofenceStatusMessage!.startsWith('📡')
                  ? Colors.blue.shade50
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _geofenceStatusMessage!.startsWith('📡')
                    ? Colors.blue.shade200
                    : Colors.orange.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _geofenceStatusMessage!.startsWith('📡')
                      ? Icons.gps_fixed_rounded
                      : Icons.warning_amber_rounded,
                  size: 20,
                  color: _geofenceStatusMessage!.startsWith('📡')
                      ? Colors.blue.shade700
                      : Colors.orange.shade800,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _geofenceStatusMessage!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _geofenceStatusMessage!.startsWith('📡')
                          ? Colors.blue.shade800
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Walking / Driving details (below arrival time, above Arrived button).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getMovementDisplay(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: Colors.grey.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                _etaText ?? '—',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.straighten_rounded,
                size: 14,
                color: Colors.grey.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                '${_remainingDistanceKm.toStringAsFixed(1)} km left',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              if (_currentActivity.toLowerCase() == 'stop' ||
                  _currentActivity.toLowerCase() == 'standing') ...[
                const SizedBox(width: 12),
                if (_task?.customer?.customerNumber != null &&
                    _task!.customer!.customerNumber!.trim().isNotEmpty)
                  IconButton(
                    onPressed: () async {
                      final number = _task!.customer!.customerNumber!.trim();
                      final uri = Uri.parse('tel:$number');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cannot make call')),
                        );
                      }
                    },
                    icon: Icon(
                      Icons.call_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    tooltip: 'Call customer',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _updatingDestination ? null : _onChangeDestinationTap,
          icon: Icon(
            Icons.pin_drop_rounded,
            size: 18,
            color: _updatingDestination ? Colors.grey : AppColors.primary,
          ),
          label: Text(
            _updatingDestination ? 'Updating...' : 'Change / Pin destination',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _updatingDestination ? Colors.grey : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _onExitRide,
                icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                label: const Text(
                  'Exit Task',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: (_submittingArrived || _arrivedSent)
                    ? null
                    : _onArrived,
                icon: _submittingArrived
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _arrivedSent
                            ? Icons.check_circle_rounded
                            : Icons.location_on_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                label: Text(
                  _arrivedSent
                      ? 'Arrived'
                      : (_submittingArrived ? 'Submitting...' : 'Arrived'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.7),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPipView(Set<Polyline> allPolylines) {
    final center =
        _lastLocation != null &&
            _lastLocation!.latitude != null &&
            _lastLocation!.longitude != null
        ? LatLng(_lastLocation!.latitude!, _lastLocation!.longitude!)
        : widget.pickupLocation;
    final pipTitle = _dropoffAddress.isNotEmpty
        ? _dropoffAddress
        : 'Towards destination';
    final pipSubtitle = _etaText != null
        ? 'Arrive $_etaText'
        : '${_remainingDistanceKm.toStringAsFixed(1)} km';
    return Container(
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14.0),
            markers: {
              if (_staffMarker != null) _staffMarker!,
              if (_pickupMarker != null) _pickupMarker!,
              if (_dropoffMarker != null) _dropoffMarker!,
            },
            polylines: allPolylines,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ClipRect(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.navigation_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pipTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10.5),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    pipSubtitle,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allPolylines = <Polyline>{
      if (_routePolyline != null) _routePolyline!,
      if (_shortestRoutePolyline != null) _shortestRoutePolyline!,
    };

    return PiPSwitcher(
      childWhenDisabled: _buildFullScreen(allPolylines),
      childWhenEnabled: Builder(
        builder: (context) {
          // [PiPSwitcher] uses native isInPictureInPictureMode. That flag can be wrong
          // briefly after resume or on some devices while the window is still fullscreen,
          // which would show only the compact PiP map. Real PiP windows are much smaller
          // than a phone screen; use the short side to decide which layout to show.
          final size = MediaQuery.sizeOf(context);
          final minSide = math.min(size.width, size.height);
          if (minSide >= 300) {
            return _buildFullScreen(allPolylines);
          }
          return _buildPipView(allPolylines);
        },
      ),
    );
  }

  Widget _buildFullScreen(Set<Polyline> allPolylines) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onExitRide();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _onExitRide,
          ),
          title: const Text(
            'Live Tracking',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
          actions: [
            if (widget.task != null)
              IconButton(
                icon: Icon(Icons.assignment_rounded, color: AppColors.primary),
                tooltip: 'Task details',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TaskDetailScreen(
                        task: widget.task!,
                        fromRideScreen: true,
                      ),
                    ),
                  );
                },
              ),
            if (_task?.customer?.customerNumber != null &&
                _task!.customer!.customerNumber!.trim().isNotEmpty)
              IconButton(
                icon: Icon(Icons.call_rounded, color: AppColors.primary),
                tooltip: 'Call customer',
                onPressed: () async {
                  final number = _task!.customer!.customerNumber!.trim();
                  final uri = Uri.parse('tel:$number');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cannot make call')),
                    );
                  }
                },
              ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Map fills the screen
            GoogleMap(
              onMapCreated: (controller) {
                mapController = controller;
                if (_staffMarker != null) {
                  mapController?.animateCamera(
                    CameraUpdate.newLatLng(_staffMarker!.position),
                  );
                }
              },
              initialCameraPosition: CameraPosition(
                target: widget.pickupLocation,
                zoom: 14.0,
              ),
              markers: {
                if (_staffMarker != null) _staffMarker!,
                if (_pickupMarker != null) _pickupMarker!,
                if (_dropoffMarker != null) _dropoffMarker!,
              },
              polylines: allPolylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
            // Map overlays: back button + live distance card
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, top: 4),
                      child: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back_rounded, size: 22),
                        ),
                        onPressed: _onExitRide,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.near_me_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Shortest to destination: ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            '${_remainingDistanceKm.toStringAsFixed(2)} km',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Draggable bottom sheet - scrollable for clear map view
            DraggableScrollableSheet(
              initialChildSize: 0.35,
              minChildSize: 0.15,
              maxChildSize: 0.75,
              snap: true,
              snapSizes: const [0.2, 0.35, 0.55, 0.75],
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          child: _buildBottomPanelContent(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTravelRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStepRow({
    required bool done,
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: done
            ? AppColors.primary.withOpacity(0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (loading)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                else if (done)
                  Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primary,
                    size: 22,
                  )
                else
                  Icon(icon, color: Colors.grey.shade600, size: 22),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: done ? AppColors.textPrimary : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
