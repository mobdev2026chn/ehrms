// Task Details / Start Task – UI matches reference (blue app bar, map card, customer card, fixed Start button)
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/screens/geo/arrived_screen.dart';
import 'package:hrms/screens/geo/live_tracking_screen.dart';
import 'package:hrms/screens/geo/task_history_screen.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/services/geo/route_snapping_service.dart';
import 'package:hrms/services/presence_tracking_service.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/task_movement_summary_util.dart';
import 'package:hrms/widgets/app_tab_loader.dart';

class TaskDetailScreen extends StatefulWidget {
  final Task task;

  /// When true, opened from ride screen; back/continue just pops to ride (no push to StartRideScreen).
  final bool fromRideScreen;

  const TaskDetailScreen({
    super.key,
    required this.task,
    this.fromRideScreen = false,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskTrackEvent {
  final DateTime? time;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;

  const _TaskTrackEvent({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Task task;

  Customer? _customer;
  bool _loadingCustomer = true;
  String? _customerError;

  Position? _currentPosition;
  LatLng? _destinationLatLng;
  double? _distanceKm;
  String? _durationText;
  bool _loadingMap = true;
  String? _mapError;

  Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  TaskMovementSummary? _movementSummary;
  double? _routeDistanceKm;

  @override
  void initState() {
    super.initState();
    task = widget.task;
    _loadTaskCustomerAndMap();
  }

  Future<void> _loadTaskCustomerAndMap() async {
    if (task.id != null && task.id!.isNotEmpty) {
      try {
        final refreshed = await TaskService().getTaskById(task.id!);
        if (mounted) {
          setState(() => task = refreshed);
          _loadMovementSummary();
          if (refreshed.status == TaskStatus.arrived) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => ArrivedScreen(
                    taskMongoId: refreshed.id,
                    taskId: refreshed.taskId,
                    task: refreshed,
                    totalDuration: Duration(
                      seconds: refreshed.tripDurationSeconds ?? 0,
                    ),
                    totalDistanceKm: refreshed.tripDistanceKm ?? 0.0,
                    isWithinGeofence: false,
                    arrivalTime: refreshed.arrivalTime ?? DateTime.now(),
                    sourceLat: refreshed.sourceLocation?.lat,
                    sourceLng: refreshed.sourceLocation?.lng,
                    sourceAddress: refreshed.sourceLocation?.address,
                    destLat: refreshed.destinationLocation?.lat,
                    destLng: refreshed.destinationLocation?.lng,
                    destAddress: refreshed.destinationLocation?.address,
                    arrivalAtLat: refreshed.arrivalLocation?.lat,
                    arrivalAtLng: refreshed.arrivalLocation?.lng,
                    arrivalAtAddress: refreshed.arrivalLocation?.displayAddress,
                  ),
                ),
              );
            });
            return;
          }
        }
      } catch (_) {}
    }
    _loadMovementSummary();
    if (task.customer != null) {
      setState(() {
        _customer = task.customer;
        _loadingCustomer = false;
      });
      await _initMapAndDirections();
      return;
    }
    if (task.customerId == null || task.customerId!.isEmpty) {
      setState(() {
        _loadingCustomer = false;
        _customerError = 'No customer linked';
      });
      return;
    }
    try {
      final c = await CustomerService().getCustomerById(task.customerId!);
      if (mounted) {
        setState(() {
          _customer = c;
          _loadingCustomer = false;
        });
        await _initMapAndDirections();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _customerError = 'Failed to load customer';
          _loadingCustomer = false;
        });
      }
    }
  }

  Future<void> _loadMovementSummary() async {
    final stored = task.travelActivityDuration;
    if (stored != null) {
      final summary = TaskMovementSummary.fromDurations(
        drivingDuration: Duration(seconds: stored.driveDuration),
        walkingDuration: Duration(seconds: stored.walkDuration),
        stopDuration: Duration(seconds: stored.stopDuration),
      );
      if (summary.hasData) {
        if (mounted) setState(() => _movementSummary = summary);
        return;
      }
    }
    final taskId = task.id;
    if (taskId == null || taskId.isEmpty) return;
    try {
      final report = await TaskService().getTaskCompletionReport(taskId);
      final summary = TaskMovementSummary.fromRoutePoints(
        report.routePoints,
        endTime: task.arrivalTime,
      );
      if (mounted) {
        setState(() {
          _movementSummary = summary.hasData ? summary : null;
          _routeDistanceKm = computeRouteDistanceKm(
            report.routePoints,
            endTime: task.arrivalTime,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _initMapAndDirections() async {
    setState(() {
      _loadingMap = true;
      _mapError = null;
    });

    Geolocator.getServiceStatusStream();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _loadingMap = false;
          _mapError = 'Location permission denied';
        });
      }
      return;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingMap = false;
          _mapError = 'Could not get current location';
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _currentPosition = position;
    });

    // Prefer stored task destination, then customer address
    LatLng? destLatLng;
    if (task.destinationLocation != null &&
        (task.destinationLocation!.lat != 0 ||
            task.destinationLocation!.lng != 0)) {
      destLatLng = LatLng(
        task.destinationLocation!.lat,
        task.destinationLocation!.lng,
      );
    }
    if (destLatLng == null && _customer != null) {
      final address =
          '${_customer!.address}, ${_customer!.city}, ${_customer!.pincode}';
      List<Location> locations = [];
      try {
        locations = await locationFromAddress(address);
      } catch (_) {}
      if (locations.isNotEmpty) {
        final dest = locations.first;
        destLatLng = LatLng(dest.latitude, dest.longitude);
      }
    }
    if (destLatLng == null) {
      if (mounted) {
        setState(() {
          _loadingMap = false;
          _mapError = _customer == null
              ? null
              : 'Could not find destination address';
          _distanceKm = null;
          _durationText = null;
        });
      }
      if (_customer == null) return;
      return;
    }

    // Use stored source for "current" marker when available, else use GPS
    if (task.sourceLocation != null &&
        (task.sourceLocation!.lat != 0 || task.sourceLocation!.lng != 0)) {
      position = Position(
        latitude: task.sourceLocation!.lat,
        longitude: task.sourceLocation!.lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      if (mounted) setState(() => _currentPosition = position);
    }

    setState(() {
      _destinationLatLng = destLatLng;
    });

    final currentPos = position;
    final dest = destLatLng;

    // Show only actual GPS path from Tracking collection (no directions route).
    if (task.id != null && task.id!.isNotEmpty) {
      final travelledMaps = await TaskService().getTravelledPathUntilArrived(
        task.id!,
        arrivalTime: task.arrivalTime,
      );
      if (travelledMaps.length >= 2) {
        final rawTravelledPts = travelledMaps
            .map((e) => LatLng(e['lat']!, e['lng']!))
            .toList();
        // Snap to roads so the line follows the actual path travelled, not
        // corner-cutting straight segments between sparse GPS samples.
        final snapped = await RouteSnappingService.buildExactRouteFromLatLng(
          rawTravelledPts,
        );
        final travelledPts = snapped.length >= 2 ? snapped : rawTravelledPts;
        if (!mounted) return;
        final pathStart = travelledPts.first;
        final pathEnd = travelledPts.last;
        final meters = Geolocator.distanceBetween(
          pathEnd.latitude,
          pathEnd.longitude,
          dest.latitude,
          dest.longitude,
        );
        final km = meters / 1000;
        final min = (km / 30 * 60).round().clamp(0, 999);
        final eta = min > 60 ? '~${min ~/ 60} h' : '~$min min';
        if (!mounted) return;
        setState(() {
          _distanceKm = km;
          _durationText = eta;
          _loadingMap = false;
          _markers = {
            Marker(
              markerId: const MarkerId('pathStart'),
              position: pathStart,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
              infoWindow: const InfoWindow(title: 'Trip start'),
            ),
            Marker(
              markerId: const MarkerId('pathEnd'),
              position: pathEnd,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
              infoWindow: const InfoWindow(title: 'Arrived here'),
            ),
          };
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('travelled'),
              points: travelledPts,
              color: AppColors.primary,
              width: 5,
              geodesic: true,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          );
        });
        return;
      }
    }
    final meters = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      dest.latitude,
      dest.longitude,
    );
    final km = meters / 1000;
    final min = (km / 30 * 60).round().clamp(0, 999);
    final eta = min > 60 ? '~${min ~/ 60} h' : '~$min min';
    if (!mounted) return;
    setState(() {
      _distanceKm = km;
      _durationText = eta;
      _loadingMap = false;
      _markers = {
        Marker(
          markerId: const MarkerId('current'),
          position: LatLng(currentPos.latitude, currentPos.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'My Location'),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: dest,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      };
      _polylines.clear();
    });
  }

  String _statusLabel(TaskStatus s) {
    switch (s) {
      case TaskStatus.assigned:
        return 'Assigned';
      case TaskStatus.approved:
        return 'Approved';
      case TaskStatus.staffapproved:
        return 'Staff Approved';
      case TaskStatus.pending:
        return 'Pending';
      case TaskStatus.scheduled:
        return 'Scheduled';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.arrived:
        return 'Arrived';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.exited:
        return 'Exited';
      case TaskStatus.exitedOnArrival:
        return 'Exited on Arrival';
      case TaskStatus.holdOnArrival:
        return 'Hold on Arrival';
      case TaskStatus.reopenedOnArrival:
        return 'Reopened on Arrival';
      case TaskStatus.waitingForApproval:
        return 'Waiting for Approval';
      case TaskStatus.rejected:
        return 'Rejected';
      case TaskStatus.reopened:
        return 'Reopened';
      case TaskStatus.hold:
        return 'Hold';
      case TaskStatus.cancelled:
        return 'Cancelled';
      default:
        return 'Ready';
    }
  }

  Future<void> _onCallCustomer() async {
    final number = _customer?.customerNumber?.trim();
    if (number == null || number.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Task Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Ride history',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TaskHistoryScreen(task: task),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMapCard(),
                  const SizedBox(height: 16),
                  _buildTaskSummaryCard(),
                  const SizedBox(height: 16),
                  _buildAssignedAndCompletionDates(),
                  const SizedBox(height: 16),
                  _buildCustomerCard(),
                  const SizedBox(height: 16),
                  _buildDestinationCard(),
                  const SizedBox(height: 16),
                  _buildTaskRequirements(),
                  _buildOtpVerificationStatus(),
                  if (_buildTrackEvents().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildTrackDetailsCard(),
                  ],
                  if (_hasCompletionDetails) ...[
                    const SizedBox(height: 16),
                    _buildCompletionDetailsCard(),
                  ],
                  if (!_showBackOnly) ...[
                    const SizedBox(height: 16),
                    _buildReadyToStartCard(),
                  ],
                ],
              ),
            ),
          ),
          _buildBottomButtons(),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    final initialPosition = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : (_destinationLatLng ?? const LatLng(11.0168, 76.9558));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        color: Colors.grey.shade100,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            if (_loadingMap && _markers.isEmpty)
              const Center(child: AppTabLoader())
            else if (_mapError != null && _markers.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _mapError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              )
            else
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: initialPosition,
                  zoom: 14,
                ),
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                minMaxZoomPreference: const MinMaxZoomPreference(2, 22),
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                // Map sits inside SingleChildScrollView — without this, scroll steals pinch/pan.
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                onMapCreated: (controller) {
                  if (_markers.isNotEmpty || _polylines.isNotEmpty) {
                    _fitBounds(controller);
                  }
                },
              ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: Colors.pink.shade400,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _distanceKm != null
                          ? '${_distanceKm!.toStringAsFixed(1)} km away'
                          : '—',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _durationText ?? '—',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
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

  void _fitBounds(GoogleMapController controller) {
    final List<LatLng> pts = [];
    for (final m in _markers) {
      pts.add(m.position);
    }
    for (final pl in _polylines) {
      pts.addAll(pl.points);
    }
    if (pts.isEmpty) {
      if (_destinationLatLng != null) {
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(_destinationLatLng!, 14),
        );
      }
      return;
    }
    if (pts.length == 1) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    var minLat = pts.first.latitude;
    var maxLat = pts.first.latitude;
    var minLng = pts.first.longitude;
    var maxLng = pts.first.longitude;
    for (var i = 1; i < pts.length; i++) {
      final e = pts[i];
      if (e.latitude < minLat) minLat = e.latitude;
      if (e.latitude > maxLat) maxLat = e.latitude;
      if (e.longitude < minLng) minLng = e.longitude;
      if (e.longitude > maxLng) maxLng = e.longitude;
    }
    const pad = 0.002;
    if ((maxLat - minLat).abs() < 1e-6 && (maxLng - minLng).abs() < 1e-6) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    if ((maxLat - minLat).abs() < pad) {
      minLat -= pad;
      maxLat += pad;
    }
    if ((maxLng - minLng).abs() < pad) {
      minLng -= pad;
      maxLng += pad;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
  }

  Widget _buildTaskSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.taskTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  _statusLabel(task.status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Task #${task.taskId}',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final parsed = _parseSourceDestination(task.description);
                final descText =
                    (parsed.source != null || parsed.destination != null) &&
                        parsed.body.isNotEmpty
                    ? parsed.body
                    : task.description;
                return Text(
                  descText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.4,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomerCard() {
    if (_loadingCustomer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: AppTabLoader(),
        ),
      );
    }
    if (_customerError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          _customerError!,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }
    if (_customer == null) {
      return const SizedBox.shrink();
    }

    final initial = _customer!.customerName.isNotEmpty
        ? _customer!.customerName[0].toUpperCase()
        : '?';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customer Information',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.secondary,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _customer!.customerName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _customer!.address.isNotEmpty
                          ? '${_customer!.address}, ${_customer!.city} ${_customer!.pincode}'
                                .trim()
                          : '${_customer!.city} ${_customer!.pincode}'.trim(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_customer!.customerNumber != null &&
              _customer!.customerNumber!.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: _onCallCustomer,
              child: Row(
                children: [
                  Icon(
                    Icons.phone_rounded,
                    size: 20,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _customer!.customerNumber!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_customer!.effectiveEmail != null &&
              _customer!.effectiveEmail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.email_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _customer!.effectiveEmail!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Parse "Source: X\nDestination: Y\n\n{body}" from description.
  ({String? source, String? destination, String body}) _parseSourceDestination(
    String? desc,
  ) {
    if (desc == null || desc.trim().isEmpty) {
      return (source: null, destination: null, body: desc ?? '');
    }
    String? source;
    String? destination;
    final lines = desc.split('\n');
    final bodyLines = <String>[];
    for (final line in lines) {
      if (line.startsWith('Source:')) {
        source = line.substring(7).trim();
      } else if (line.startsWith('Destination:')) {
        destination = line.substring(12).trim();
      } else if (line.trim().isNotEmpty || bodyLines.isNotEmpty) {
        bodyLines.add(line);
      }
    }
    return (
      source: source,
      destination: destination,
      body: bodyLines.join('\n').trim(),
    );
  }

  Widget _buildDestinationCard() {
    final parsed = _parseSourceDestination(task.description);
    final address = _customer != null
        ? '${_customer!.address}, ${_customer!.city}, ${_customer!.pincode}'
              .trim()
        : parsed.destination ?? '';

    if (_customer == null &&
        parsed.source == null &&
        parsed.destination == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parsed.source != null && parsed.source!.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.gps_fixed_rounded,
                  size: 20,
                  color: Colors.green.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  'Source:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              parsed.source!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 20,
                color: Colors.pink.shade400,
              ),
              const SizedBox(width: 8),
              Text(
                'Destination:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            parsed.destination?.isNotEmpty == true
                ? parsed.destination!
                : address,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
              height: 1.4,
            ),
          ),
          if (_distanceKm != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_distanceKm!.toStringAsFixed(1)} km away',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskRequirements() {
    final hasAny =
        task.isOtpRequired ||
        task.isGeoFenceRequired ||
        task.isPhotoRequired ||
        task.isFormRequired;
    if (!hasAny) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Task Requirements',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (task.isOtpRequired) _chip('✓ OTP Required', Colors.green),
            if (task.isGeoFenceRequired)
              _chip('📍 Geo-Fence (500m)', Colors.purple),
            if (task.isPhotoRequired) _chip('📷 Photo Required', Colors.orange),
            if (task.isFormRequired) _chip('📝 Fill Form', Colors.teal),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildAssignedAndCompletionDates() {
    final isCompleted = task.status == TaskStatus.completed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dates',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (task.assignedDate != null) ...[
            Row(
              children: [
                Icon(
                  Icons.assignment_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assigned date',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        DateDisplayUtil.formatFull(task.assignedDate!),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (!isCompleted) ...[
            Row(
              children: [
                Icon(
                  Icons.event_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Expected completion',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        DateDisplayUtil.formatFull(task.expectedCompletionDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (isCompleted && task.completedDate != null) ...[
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Completed on',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        DateDisplayUtil.formatFull(task.completedDate!),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOtpVerificationStatus() {
    if (!task.isOtpRequired) return const SizedBox.shrink();
    final verified = task.isOtpVerified == true;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.pending_rounded,
            size: 20,
            color: verified ? AppColors.primary : Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  if (verified)
                    TextSpan(
                      text: 'OTP Verified: Yes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final secs = d.inSeconds;
    if (secs < 60) return secs == 1 ? '1 sec' : '$secs secs';
    final mins = d.inMinutes;
    final remainderSecs = d.inSeconds.remainder(60);
    if (d.inHours > 0) {
      final h = d.inHours;
      final m = mins.remainder(60);
      if (remainderSecs > 0) return '${h}h ${m}m ${remainderSecs}s';
      return '${h}h ${m}m';
    }
    if (remainderSecs > 0) {
      return '$mins min${mins == 1 ? '' : 's'} $remainderSecs secs';
    }
    return mins == 1 ? '1 min' : '$mins mins';
  }

  static String _formatDistanceKm(double distanceKm) {
    final decimals = distanceKm < 1 ? 2 : 1;
    return '${distanceKm.toStringAsFixed(decimals)} km';
  }

  Duration get _travelDuration {
    final secs = task.tripDurationSeconds;
    if (secs != null && secs > 0) {
      return Duration(seconds: secs);
    }
    if (task.startTime != null &&
        task.arrivalTime != null &&
        !task.arrivalTime!.isBefore(task.startTime!)) {
      return task.arrivalTime!.difference(task.startTime!);
    }
    return Duration.zero;
  }

  Duration? get _totalTaskDuration {
    if (task.startTime != null &&
        task.completedDate != null &&
        !task.completedDate!.isBefore(task.startTime!)) {
      return task.completedDate!.difference(task.startTime!);
    }
    return null;
  }

  bool get _showOtpRow =>
      task.isOtpRequired || task.isOtpVerified != null || task.otpVerifiedAt != null;

  bool get _showFormRow => task.formFilled != null;

  bool get _showPhotoProofRow =>
      task.photoProof != null ||
      (task.photoProofUrl != null && task.photoProofUrl!.isNotEmpty);

  double? get _displayDistanceKm {
    final taskDistance = task.tripDistanceKm;
    if (taskDistance != null && taskDistance > 0) return taskDistance;
    if (_routeDistanceKm != null && _routeDistanceKm! > 0) return _routeDistanceKm;
    return null;
  }

  bool get _hasCompletionDetails {
    final distanceKm = _displayDistanceKm;
    return task.startTime != null ||
        task.completedDate != null ||
        _travelDuration.inSeconds > 0 ||
        (_totalTaskDuration?.inSeconds ?? 0) > 0 ||
        (distanceKm != null && distanceKm >= 0) ||
        _movementSummary?.hasData == true ||
        _showOtpRow ||
        _showFormRow ||
        _showPhotoProofRow;
  }

  List<_TaskTrackEvent> _buildTrackEvents() {
    final events = <_TaskTrackEvent>[];
    final start = task.startTime;
    final arrival = task.arrivalTime;
    final completed = task.completedDate;
    final duration = _travelDuration;
    final distanceKm = _displayDistanceKm;

    if (start != null) {
      events.add(
        _TaskTrackEvent(
          time: start,
          title: 'Task Started',
          subtitle: 'Started journey',
          icon: Icons.play_circle_filled_rounded,
          iconColor: AppColors.secondary,
        ),
      );
    }

    if (start != null &&
        (duration.inSeconds > 0 || (distanceKm != null && distanceKm > 0))) {
      final distanceText = distanceKm != null && distanceKm > 0
          ? '${_formatDistanceKm(distanceKm)} covered'
          : 'Travel in progress';
      events.add(
        _TaskTrackEvent(
          time: start,
          title: 'Travel (${_formatDuration(duration)})',
          subtitle: distanceText,
          icon: Icons.route_rounded,
          iconColor: AppColors.secondary,
        ),
      );
    }

    if (arrival != null) {
      events.add(
        _TaskTrackEvent(
          time: arrival,
          title: 'Arrived at Location',
          subtitle: task.arrivalLocation?.displayAddress?.isNotEmpty == true
              ? task.arrivalLocation!.displayAddress!
              : 'Destination reached',
          icon: Icons.location_on_rounded,
          iconColor: Colors.pink.shade400,
        ),
      );
    }

    if (task.formFilled == true) {
      events.add(
        _TaskTrackEvent(
          time: task.otpVerifiedAt ?? completed ?? arrival,
          title: 'Form Submitted',
          subtitle: 'Customer details captured',
          icon: Icons.description_rounded,
          iconColor: Colors.brown.shade400,
        ),
      );
    }

    if (task.isOtpVerified == true && task.otpVerifiedAt != null) {
      events.add(
        _TaskTrackEvent(
          time: task.otpVerifiedAt,
          title: 'OTP Verified',
          subtitle: 'Customer confirmed',
          icon: Icons.verified_user_rounded,
          iconColor: AppColors.secondary,
        ),
      );
    }

    if (completed != null) {
      events.add(
        _TaskTrackEvent(
          time: completed,
          title: 'Task Completed',
          subtitle: task.status == TaskStatus.waitingForApproval
              ? 'Awaiting admin approval'
              : '',
          icon: Icons.check_circle_rounded,
          iconColor: AppColors.primary,
        ),
      );
    }

    return events.where((e) => e.time != null).toList();
  }

  Widget _buildTrackDetailsCard() {
    final events = _buildTrackEvents();
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Track Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  for (int i = 0; i < events.length; i++) ...[
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: events[i].iconColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: events[i].iconColor.withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    if (i < events.length - 1)
                      Container(
                        width: 2,
                        height: 56,
                        color: Colors.grey.shade300,
                      ),
                  ],
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < events.length; i++) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              events[i].icon,
                              size: 22,
                              color: events[i].iconColor,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateDisplayUtil.formatTime(events[i].time),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    events[i].title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  if (events[i].subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      events[i].subtitle,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < events.length - 1) const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionDetailsCard() {
    final distanceKm = _displayDistanceKm;
    final totalTaskDuration = _totalTaskDuration;
    final showDistance = distanceKm != null && distanceKm >= 0;
    final otpVerified = task.isOtpVerified == true;
    final formSubmitted = task.formFilled == true;
    final photoProofDone = task.photoProof == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Task Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),
          if (task.startTime != null) ...[
            _summaryRow('Started At', DateDisplayUtil.formatTime(task.startTime)),
          ],
          if (task.completedDate != null) ...[
            if (task.startTime != null) _summaryDivider(),
            _summaryRow(
              'Completed At',
              DateDisplayUtil.formatTime(task.completedDate),
            ),
          ],
          if (_travelDuration.inSeconds > 0) ...[
            if (task.startTime != null || task.completedDate != null) _summaryDivider(),
            _summaryRow('Travel Duration', _formatDuration(_travelDuration)),
          ],
          if (_movementSummary?.hasData == true) ...[
            if (task.startTime != null ||
                task.completedDate != null ||
                _travelDuration.inSeconds > 0)
              _summaryDivider(),
            _summaryRow(
              'Drive Duration',
              _formatDuration(_movementSummary!.drivingDuration),
            ),
            _summaryDivider(),
            _summaryRow(
              'Walk Duration',
              _formatDuration(_movementSummary!.walkingDuration),
            ),
            _summaryDivider(),
            _summaryRow(
              'Stop Duration',
              _formatDuration(_movementSummary!.stopDuration),
            ),
          ],
          if (totalTaskDuration != null && totalTaskDuration.inSeconds > 0) ...[
            if (task.startTime != null ||
                task.completedDate != null ||
                _travelDuration.inSeconds > 0 ||
                _movementSummary?.hasData == true)
              _summaryDivider(),
            _summaryRow(
              'Total Task Duration',
              _formatDuration(totalTaskDuration),
            ),
          ],
          if (showDistance) ...[
            if (task.startTime != null ||
                task.completedDate != null ||
                _travelDuration.inSeconds > 0 ||
                (totalTaskDuration?.inSeconds ?? 0) > 0)
              _summaryDivider(),
            _summaryRow(
              'Distance Travelled',
              '${distanceKm.toStringAsFixed(2)} km',
            ),
          ],
          if (_showOtpRow) ...[
            if (task.startTime != null ||
                task.completedDate != null ||
                _travelDuration.inSeconds > 0 ||
                (totalTaskDuration?.inSeconds ?? 0) > 0 ||
                showDistance)
              _summaryDivider(),
            _summaryVerificationRow('OTP Verified', otpVerified),
          ],
          if (_showFormRow) ...[
            if (task.startTime != null ||
                task.completedDate != null ||
                _travelDuration.inSeconds > 0 ||
                (totalTaskDuration?.inSeconds ?? 0) > 0 ||
                showDistance ||
                _showOtpRow)
              _summaryDivider(),
            _summaryVerificationRow('Form Submitted', formSubmitted),
          ],
          if (_showPhotoProofRow) ...[
            if (task.startTime != null ||
                task.completedDate != null ||
                _travelDuration.inSeconds > 0 ||
                (totalTaskDuration?.inSeconds ?? 0) > 0 ||
                showDistance ||
                _showOtpRow ||
                _showFormRow)
              _summaryDivider(),
            _summaryVerificationRow(
              'Photo Proof',
              photoProofDone,
              value: photoProofDone
                  ? ((task.photoProofUrl != null && task.photoProofUrl!.isNotEmpty)
                        ? 'Uploaded'
                        : 'Yes')
                  : 'No',
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryVerificationRow(String label, bool done, {String? value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done)
                Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
              if (done) const SizedBox(width: 4),
              Text(
                value ?? (done ? 'Yes' : 'No'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: done ? AppColors.primary : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryDivider() {
    return Divider(height: 1, color: Colors.grey.shade200);
  }

  Widget _buildExitRestartHistoryCard() {
    final exits = task.tasksExit;
    final restarts = task.tasksRestarted;
    if (exits.isEmpty && restarts.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: Colors.orange.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exit & Restart History',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      'Past exits and restarts for this task',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TaskHistoryScreen(task: task),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text('View all'),
              ),
            ],
          ),
          if (exits.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...exits.asMap().entries.map(
              (e) => _historyTile(
                'Exit #${e.key + 1}',
                e.value.exitReason,
                e.value.exitedAt,
                e.value.address,
                e.value.pincode,
                Icons.exit_to_app_rounded,
                Colors.orange,
              ),
            ),
          ],
          if (restarts.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...restarts.asMap().entries.map(
              (e) => _historyTile(
                'Resumed #${e.key + 1}',
                null,
                e.value.resumedAt,
                e.value.address,
                e.value.pincode,
                Icons.replay_rounded,
                Colors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 11, color: Colors.black),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(
    String type,
    String? reason,
    DateTime? date,
    String? address,
    String? pincode,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  if (date != null)
                    _historyDetailRow(
                      'Date & Time',
                      DateDisplayUtil.formatDateTime(date),
                    ),
                  if (reason != null && reason.isNotEmpty)
                    _historyDetailRow('Reason', reason),
                  if (address != null && address.isNotEmpty)
                    _historyDetailRow('Location', address),
                  if (pincode != null && pincode.isNotEmpty)
                    _historyDetailRow('Pincode', pincode),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSettingsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Task settings',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _settingsRow('OTP verification required', task.isOtpRequired),
          const SizedBox(height: 6),
          _settingsRow(
            'Require approval on complete',
            task.requireApprovalOnComplete,
          ),
          const SizedBox(height: 6),
          _settingsRow('Auto approve', task.autoApprove),
        ],
      ),
    );
  }

  Widget _settingsRow(String label, bool value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        Text(
          value ? 'Yes' : 'No',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: value ? AppColors.primary : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildReadyToStartCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: AppColors.secondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to Start?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your location will be tracked during this task. Ensure GPS is enabled.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondary.withOpacity(0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _actionLoading = false;

  /// Show "Start Ride": autoApprove true → assigned/pending (direct start); autoApprove false → only when approved
  /// autoApprove false = manual approval required; autoApprove true = can start directly
  bool get _showStartRideButton =>
      task.id != null &&
      task.id!.isNotEmpty &&
      ((task.status == TaskStatus.assigned ||
                  task.status == TaskStatus.pending) &&
              task.autoApprove ||
          (!task.autoApprove &&
              (task.status == TaskStatus.approved ||
                  task.status == TaskStatus.staffapproved)));

  /// Show "Resume Ride" when task is on hold, holdOnArrival, reopenedOnArrival, exited with hold, or admin reopened.
  bool get _showResumeAfterExitButton =>
      task.id != null &&
      task.id!.isNotEmpty &&
      (task.status == TaskStatus.hold ||
          task.status == TaskStatus.holdOnArrival ||
          task.status == TaskStatus.reopenedOnArrival ||
          task.status == TaskStatus.exited &&
              (task.taskExitStatus == 'hold' || task.taskExitStatus == null) ||
          task.status == TaskStatus.reopened);

  /// Show "Resume Ride" when task is in progress.
  bool get _showResumeRideButton =>
      task.id != null &&
      task.id!.isNotEmpty &&
      task.status == TaskStatus.inProgress;

  /// Show only Back when completed, waiting_for_approval, or rejected.
  bool get _showBackOnly =>
      task.status == TaskStatus.completed ||
      task.status == TaskStatus.waitingForApproval ||
      task.status == TaskStatus.rejected;

  /// Show Approve/Reject when autoApprove is false (manual approval required) and task is assigned/pending.
  bool get _showApprovalButtons =>
      !task.autoApprove &&
      (task.status == TaskStatus.assigned ||
          task.status == TaskStatus.pending) &&
      task.id != null &&
      task.id!.isNotEmpty &&
      !_showResumeRideButton &&
      !_showResumeAfterExitButton &&
      !_showBackOnly;

  /// Staff can always approve; OTP verification applies only at arrival (arrived screen).
  bool get _canApprove => true;

  /// Resolve pickup (source) LatLng: task.sourceLocation > current GPS.
  LatLng? get _pickupLatLng {
    if (task.sourceLocation != null &&
        (task.sourceLocation!.lat != 0 || task.sourceLocation!.lng != 0)) {
      return LatLng(task.sourceLocation!.lat, task.sourceLocation!.lng);
    }
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    return null;
  }

  /// Resolve dropoff (destination) LatLng: task.destinationLocation > geocoded customer.
  LatLng? get _dropoffLatLng {
    if (task.destinationLocation != null &&
        (task.destinationLocation!.lat != 0 ||
            task.destinationLocation!.lng != 0)) {
      return LatLng(
        task.destinationLocation!.lat,
        task.destinationLocation!.lng,
      );
    }
    return _destinationLatLng;
  }

  Future<void> _onApprove() async {
    if (task.id == null || _actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      final updated = await TaskService().updateTask(
        task.id!,
        status: 'approved',
      );
      if (mounted) {
        setState(() {
          task = updated;
          _actionLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessageUtils.toUserFriendlyMessage(e))),
        );
      }
    }
  }

  Future<void> _onReject() async {
    if (task.id == null || _actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await TaskService().updateTask(task.id!, status: 'rejected');
      if (mounted) {
        setState(() => _actionLoading = false);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessageUtils.toUserFriendlyMessage(e))),
        );
      }
    }
  }

  Future<void> _onStartRide() async {
    if (task.id == null || _actionLoading) return;
    final pickup = _pickupLatLng;
    final dropoff = _dropoffLatLng;
    if (pickup == null || dropoff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Source and destination are required. Enable GPS and ensure destination is set.',
          ),
        ),
      );
      return;
    }
    setState(() => _actionLoading = true);
    try {
      final startLat = _currentPosition?.latitude ?? pickup.latitude;
      final startLng = _currentPosition?.longitude ?? pickup.longitude;
      late final Task updated;
      if (task.status == TaskStatus.exited ||
          task.status == TaskStatus.hold ||
          task.status == TaskStatus.holdOnArrival ||
          task.status == TaskStatus.reopenedOnArrival ||
          task.status == TaskStatus.reopened) {
        // Resume after exit/hold/reopened: use restart API
        await TaskService().restartTask(task.id!, lat: startLat, lng: startLng);
        updated = await TaskService().getTaskById(task.id!);
      } else {
        updated = await TaskService().updateTask(
          task.id!,
          status: 'in_progress',
          startTime: DateTime.now(),
          startLat: startLat,
          startLng: startLng,
        );
      }
      // Store initial point in Tracking collection (separate route).
      TaskService()
          .storeTracking(task.id!, startLat, startLng, movementType: 'stop')
          .catchError((_) {});
      PresenceTrackingService().pausePresenceTracking();
      if (mounted) {
        setState(() => _actionLoading = false);
        if (updated.status == TaskStatus.arrived) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ArrivedScreen(
                taskMongoId: updated.id,
                taskId: updated.taskId,
                task: updated,
                totalDuration: Duration(
                  seconds: updated.tripDurationSeconds ?? 0,
                ),
                totalDistanceKm: updated.tripDistanceKm ?? 0.0,
                isWithinGeofence: false,
                arrivalTime: updated.arrivalTime ?? DateTime.now(),
                sourceLat: updated.sourceLocation?.lat,
                sourceLng: updated.sourceLocation?.lng,
                sourceAddress: updated.sourceLocation?.address,
                destLat: updated.destinationLocation?.lat,
                destLng: updated.destinationLocation?.lng,
                destAddress: updated.destinationLocation?.address,
                arrivalAtLat: updated.arrivalLocation?.lat,
                arrivalAtLng: updated.arrivalLocation?.lng,
                arrivalAtAddress: updated.arrivalLocation?.displayAddress,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => LiveTrackingScreen(
                taskId: updated.taskId,
                taskMongoId: updated.id,
                pickupLocation: pickup,
                dropoffLocation: dropoff,
                task: updated,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessageUtils.toUserFriendlyMessage(e))),
        );
      }
    }
  }

  Future<void> _onResumeRide() async {
    if (task.id == null || _actionLoading) return;
    final pickup = _pickupLatLng;
    final dropoff = _dropoffLatLng;
    if (pickup == null || dropoff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Source and destination are required. Enable GPS and ensure destination is set.',
          ),
        ),
      );
      return;
    }
    setState(() => _actionLoading = true);
    try {
      // Refresh task to get latest state; do NOT update status or startTime.
      final refreshed = await TaskService().getTaskById(task.id!);
      PresenceTrackingService().pausePresenceTracking();
      if (mounted) {
        setState(() => _actionLoading = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => LiveTrackingScreen(
              taskId: refreshed.taskId,
              taskMongoId: refreshed.id,
              pickupLocation: pickup,
              dropoffLocation: dropoff,
              task: refreshed,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessageUtils.toUserFriendlyMessage(e))),
        );
      }
    }
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: widget.fromRideScreen
            ? SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    'Back to Ride',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showApprovalButtons) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _actionLoading
                                ? null
                                : () => _onReject(),
                            icon: const Icon(Icons.close_rounded, size: 20),
                            label: Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_actionLoading || !_canApprove)
                                ? null
                                : () => _onApprove(),
                            icon: _actionLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                            label: Text(
                              _actionLoading ? 'Approving...' : 'Approve',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_showStartRideButton ||
                        _showResumeRideButton ||
                        _showResumeAfterExitButton)
                      const SizedBox(height: 12),
                  ],
                  if (_showStartRideButton || _showResumeAfterExitButton)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _actionLoading ? null : _onStartRide,
                        icon: _actionLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _showResumeAfterExitButton
                                    ? Icons.play_arrow_rounded
                                    : Icons.directions_car_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                        label: Text(
                          _actionLoading
                              ? 'Starting...'
                              : (_showResumeAfterExitButton
                                    ? 'Resume Ride'
                                    : 'Start Ride'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  if (_showResumeRideButton)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _actionLoading ? null : _onResumeRide,
                        icon: _actionLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                        label: Text(
                          _actionLoading ? 'Resuming...' : 'Resume Ride',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  if ((task.status == TaskStatus.exited &&
                          task.taskExitStatus == 'exited') ||
                      task.status == TaskStatus.exitedOnArrival) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Task was fully exited. Only admin can reopen this task; then you can resume the ride.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                  if (!_showApprovalButtons &&
                      !_showStartRideButton &&
                      !_showResumeRideButton &&
                      !_showResumeAfterExitButton)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _actionLoading
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Back'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}
