// Task Completion detailed view with timeline and route map.
// Fetches data from DB (tasks + trackings). Timeline + map side-by-side.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/screens/dashboard/dashboard_screen.dart';
import 'package:hrms/screens/geo/my_tasks_screen.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/services/geo/route_snapping_service.dart';
import 'package:hrms/widgets/oriented_image.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/widgets/app_tab_loader.dart';
import 'package:hrms/widgets/bottom_navigation_bar.dart';

class CompletedTaskDetailScreen extends StatefulWidget {
  final Task task;

  const CompletedTaskDetailScreen({super.key, required this.task});

  @override
  State<CompletedTaskDetailScreen> createState() =>
      _CompletedTaskDetailScreenState();
}

class _CompletedTaskDetailScreenState extends State<CompletedTaskDetailScreen> {
  TaskCompletionReport? _report;
  bool _loading = true;
  String? _error;

  /// Road-snapped travelled route (the "exact" path along roads). Null until
  /// snapping completes; the map falls back to cleaned raw points meanwhile.
  List<LatLng>? _snappedRoute;

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  /// Snap the raw tracking points to the road network so the map shows the
  /// exact path travelled (not corner-cutting straight lines).
  Future<void> _computeSnappedRoute(List<RoutePoint> routePoints) async {
    if (routePoints.length < 2) return;
    final snapped = await RouteSnappingService.buildExactRoute(routePoints);
    if (mounted && snapped.length > 1) {
      setState(() => _snappedRoute = snapped);
    }
  }

  Future<void> _fetchReport() async {
    _snappedRoute = null;
    if (widget.task.id == null || widget.task.id!.isEmpty) {
      setState(() {
        _report = TaskCompletionReport(
          task: widget.task,
          timeline: _buildFallbackTimeline(),
          routePoints: [],
        );
        _loading = false;
      });
      return;
    }
    try {
      final report = await TaskService().getTaskCompletionReport(
        widget.task.id!,
      );
      if (mounted) {
        setState(() {
          _report = report;
          _loading = false;
        });
        _computeSnappedRoute(report.routePoints);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _report = TaskCompletionReport(
            task: widget.task,
            timeline: _buildFallbackTimeline(),
            routePoints: [],
          );
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<TimelineEvent> _buildFallbackTimeline() {
    final t = widget.task;
    final events = <TimelineEvent>[];
    if (t.startTime != null) {
      events.add(
        TimelineEvent(
          type: 'start',
          label: 'Start',
          time: t.startTime,
          address: t.sourceLocation?.displayAddress,
          lat: t.sourceLocation?.lat,
          lng: t.sourceLocation?.lng,
        ),
      );
    }
    if (t.arrivalTime != null) {
      events.add(
        TimelineEvent(
          type: 'arrived',
          label: 'Arrived',
          time: t.arrivalTime,
          address: null,
          lat: t.destinationLocation?.lat,
          lng: t.destinationLocation?.lng,
        ),
      );
    }
    if (t.completedDate != null) {
      events.add(
        TimelineEvent(
          type: 'completed',
          label: 'Completed',
          time: t.completedDate,
          address: null,
          lat: t.destinationLocation?.lat,
          lng: t.destinationLocation?.lng,
        ),
      );
    }
    return events;
  }

  void _goToMyTasks(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MyTasksScreen()),
      (route) => false,
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'start':
        return Icons.play_circle_filled_rounded;
      case 'movement':
        return Icons.directions_rounded;
      case 'exit':
        return Icons.power_off_rounded;
      case 'restart':
        return Icons.replay_rounded;
      case 'arrived':
        return Icons.location_on_rounded;
      case 'photo':
        return Icons.photo_camera_rounded;
      case 'otp':
        return Icons.pin_rounded;
      case 'completed':
        return Icons.check_circle_rounded;
      default:
        return Icons.circle_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'start':
        return Colors.green;
      case 'movement':
        return Colors.blue;
      case 'exit':
        return Colors.orange;
      case 'restart':
        return Colors.teal;
      case 'arrived':
        return Colors.pink;
      case 'photo':
        return Colors.purple;
      case 'otp':
        return Colors.indigo;
      case 'completed':
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final task = report?.task ?? widget.task;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goToMyTasks(context);
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _goToMyTasks(context),
          ),
          title: const Text(
            'Task Completion Report',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: _loading
            ? const Center(child: AppTabLoader())
            : RefreshIndicator(
                onRefresh: _fetchReport,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Using cached data. $_error',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      _buildTaskInfoCard(task),
                      const SizedBox(height: 10),
                      _buildAddressCard(task),
                      const SizedBox(height: 10),
                      _buildTimingsCard(task),
                      const SizedBox(height: 10),
                      _buildProofsCard(task),
                      if (report?.formResponses.isNotEmpty == true) ...[
                        const SizedBox(height: 10),
                        _buildFormsCard(report!),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'Activity Timeline & Route',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 600;
                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: _buildMapSection(report),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 1,
                                  child: _buildTimelineSection(report),
                                ),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildMapSection(report),
                              const SizedBox(height: 10),
                              _buildTimelineSection(report),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _goToMyTasks(context),
                          icon: const Icon(Icons.list_rounded, size: 22),
                          label: const Text('Return to Tasks'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        bottomNavigationBar: AppBottomNavigationBar(
          currentIndex: -1,
          onTap: (index) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) =>
                    DashboardScreen(initialIndex: index.clamp(0, 4)),
              ),
              (route) => false,
            );
          },
        ),
      ),
    );
  }

  Widget _buildTaskInfoCard(Task task) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🆔', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Task #${task.taskId}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            task.taskTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              task.description,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Status: Completed',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(Task task) {
    final source = task.sourceLocation?.displayAddress ?? '—';
    final dest =
        task.destinationLocation?.displayAddress ??
        (task.customer != null
            ? '${task.customer!.address}, ${task.customer!.city}, ${task.customer!.pincode}'
            : '—');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
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
          Text(
            'Source & Destination',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📍', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Source',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      source,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎯', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Destination',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dest,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimingsCard(Task task) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            children: [
              const Text('🕒', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                'Timings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _timingRow('Start', task.startTime),
          _timingRow('Arrived', task.arrivalTime),
          _timingRow('Completed', task.completedDate),
          if (task.tripDurationSeconds != null && task.tripDurationSeconds! > 0)
            _timingRow(
              'Duration',
              null,
              suffix: '${(task.tripDurationSeconds! / 60).round()} mins',
            ),
          if (task.tripDistanceKm != null && task.tripDistanceKm! > 0)
            _timingRow(
              'Distance',
              null,
              suffix: '${task.tripDistanceKm!.toStringAsFixed(1)} km',
            ),
        ],
      ),
    );
  }

  Widget _timingRow(String label, DateTime? time, {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          Text(
            time != null
                ? DateDisplayUtil.formatDateTime(time)
                : (suffix ?? '—'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  Widget _buildProofsCard(Task task) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
            'Verification',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          _proofRow(
            'OTP Status',
            task.isOtpVerified == true ? 'Verified' : '—',
          ),
          _proofRow(
            'Photo Proof',
            task.photoProofUrl != null ? 'Uploaded' : '—',
          ),
          if (task.photoProofAddress != null &&
              task.photoProofAddress!.isNotEmpty)
            _proofRow('Photo Address', task.photoProofAddress!),
          if (task.otpVerifiedAddress != null &&
              task.otpVerifiedAddress!.isNotEmpty)
            _proofRow('OTP Verified At', task.otpVerifiedAddress!),
          if (task.photoProofUrl != null && task.photoProofUrl!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: OrientedImage.network(
                task.photoProofUrl!,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.grey.shade200,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey.shade600),
                      const SizedBox(height: 8),
                      Text(
                        'Image not found',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else if (task.photoProofUrl == null || task.photoProofUrl!.isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.grey.shade600),
                  const SizedBox(height: 8),
                  Text(
                    'Image not found',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormsCard(TaskCompletionReport report) {
    final forms = report.formResponses;
    if (forms.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            children: [
              const Text('📋', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                'Filled Forms',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...forms.map((form) {
            final templateName = form.templateName ?? 'Form';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  templateName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                ...form.responses.entries.map((e) {
                  final key = e.key;
                  final val = e.value;
                  if (val is String && val.startsWith('data:image')) {
                    try {
                      final base64 = val.split(',').last;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _proofRow(key, null),
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: OrientedImage.memory(
                                base64Decode(base64),
                                height: 100,
                                width: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                      );
                    } catch (_) {
                      return _proofRow(key, '—');
                    }
                  }
                  return _proofRow(key, val?.toString() ?? '—');
                }),
                if (forms.indexOf(form) < forms.length - 1)
                  const SizedBox(height: 12),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _proofRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                style: TextStyle(fontSize: 12, color: Colors.black),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapSection(TaskCompletionReport? report) {
    final task = report?.task ?? widget.task;
    List<LatLng> routePoints = (report?.routePoints ?? [])
        .map((p) => LatLng(p.lat, p.lng))
        .toList();
    if (routePoints.isEmpty) {
      if (task.sourceLocation != null &&
          (task.sourceLocation!.lat != 0 || task.sourceLocation!.lng != 0)) {
        routePoints.add(
          LatLng(task.sourceLocation!.lat, task.sourceLocation!.lng),
        );
      }
      if (task.destinationLocation != null &&
          (task.destinationLocation!.lat != 0 ||
              task.destinationLocation!.lng != 0)) {
        routePoints.add(
          LatLng(task.destinationLocation!.lat, task.destinationLocation!.lng),
        );
      }
    }

    if (routePoints.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No location data',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    // Prefer the road-snapped route (exact path along roads) once available;
    // fall back to the raw tracking points until snapping completes.
    final displayRoute = (_snappedRoute != null && _snappedRoute!.length > 1)
        ? _snappedRoute!
        : routePoints;

    final bounds = _computeBounds(displayRoute);
    final center = LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );

    final markers = <Marker>{};
    if (displayRoute.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: displayRoute.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Start'),
        ),
      );
      if (displayRoute.length > 1) {
        markers.add(
          Marker(
            markerId: const MarkerId('end'),
            position: displayRoute.last,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: const InfoWindow(title: 'Completed'),
          ),
        );
      }
    }

    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 14),
          onMapCreated: (controller) {
            if (displayRoute.length > 1) {
              Future.delayed(const Duration(milliseconds: 300), () {
                controller.animateCamera(
                  CameraUpdate.newLatLngBounds(_computeBounds(displayRoute), 40),
                );
              });
            }
          },
          polylines: displayRoute.length > 1
              ? {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: displayRoute,
                    color: AppColors.primary,
                    width: 5,
                    geodesic: true,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    jointType: JointType.round,
                  ),
                }
              : {},
          markers: markers,
          mapToolbarEnabled: false,
          zoomControlsEnabled: true,
          myLocationButtonEnabled: false,
        ),
      ),
    );
  }

  LatLngBounds _computeBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(0, 0),
        northeast: const LatLng(0, 0),
      );
    }
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    const pad = 0.005;
    return LatLngBounds(
      southwest: LatLng(minLat - pad, minLng - pad),
      northeast: LatLng(maxLat + pad, maxLng + pad),
    );
  }

  /// Removes consecutive duplicate events with the same type (e.g. two "arrived" in a row).
  List<TimelineEvent> _deduplicateTimelineByType(List<TimelineEvent> timeline) {
    if (timeline.isEmpty) return timeline;
    final result = <TimelineEvent>[];
    for (final e in timeline) {
      if (result.isEmpty || result.last.type != e.type) result.add(e);
    }
    return result;
  }

  Widget _buildTimelineSection(TaskCompletionReport? report) {
    final raw = report?.timeline ?? _buildFallbackTimeline();
    final timeline = _deduplicateTimelineByType(raw);
    if (timeline.isEmpty) {
      return Container(
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
          'No timeline data available for this task.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < timeline.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _colorForType(timeline[i].type),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _colorForType(
                              timeline[i].type,
                            ).withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        _iconForType(timeline[i].type),
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    if (i < timeline.length - 1)
                      Container(
                        width: 2,
                        height: 36,
                        color: Colors.grey.shade300,
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              timeline[i].time != null
                                  ? DateDisplayUtil.formatTime(
                                      timeline[i].time!,
                                    )
                                  : '—',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (timeline[i].batteryPercent != null) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.battery_std_rounded,
                                size: 16,
                                color: timeline[i].batteryPercent! < 10
                                    ? Colors.red
                                    : Colors.blue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${timeline[i].batteryPercent}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: timeline[i].batteryPercent! < 10
                                      ? Colors.red
                                      : Colors.blue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeline[i].label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        if (timeline[i].address != null &&
                            timeline[i].address!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            timeline[i].address!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (timeline[i].exitReason != null &&
                            timeline[i].exitReason!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Reason: ${timeline[i].exitReason}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
