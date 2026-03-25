// Arrived screen – trip summary, "You've Arrived!", Within Geo-Fence, Next Steps.
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/constants.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/screens/geo/exit_ride_bottom_sheet.dart';
import 'package:hrms/screens/geo/form_fill_screen.dart';
import 'package:hrms/screens/geo/my_tasks_screen.dart';
import 'package:hrms/screens/geo/otp_verification_screen.dart';
import 'package:hrms/screens/geo/photo_proof_screen.dart';
import 'package:hrms/screens/geo/task_completed_screen.dart';
import 'package:hrms/screens/geo/task_history_screen.dart';
import 'package:hrms/services/auth_service.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/services/presence_tracking_service.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/task_movement_summary_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ArrivedScreen extends StatefulWidget {
  final String? taskMongoId;
  final String taskId;
  final Task? task;
  final Duration totalDuration;
  final double totalDistanceKm;
  final bool isWithinGeofence;
  final DateTime arrivalTime;

  /// Source (pickup) location - lat, lng, address.
  final double? sourceLat;
  final double? sourceLng;
  final String? sourceAddress;

  /// Task map destination (exit-ride fallback only). Not shown in Trip Details "Destination".
  final double? destLat;
  final double? destLng;
  final String? destAddress;

  /// Where staff tapped Arrived (GPS + address). Shown as Destination in Trip Details.
  final double? arrivalAtLat;
  final double? arrivalAtLng;
  final String? arrivalAtAddress;

  /// Optional: driving duration/distance if available from tracking.
  final Duration? drivingDuration;
  final double? drivingDistanceKm;
  final Duration? walkingDuration;
  final double? walkingDistanceKm;
  final Duration? stopDuration;

  const ArrivedScreen({
    super.key,
    this.taskMongoId,
    required this.taskId,
    this.task,
    required this.totalDuration,
    required this.totalDistanceKm,
    required this.isWithinGeofence,
    required this.arrivalTime,
    this.sourceLat,
    this.sourceLng,
    this.sourceAddress,
    this.destLat,
    this.destLng,
    this.destAddress,
    this.arrivalAtLat,
    this.arrivalAtLng,
    this.arrivalAtAddress,
    this.drivingDuration,
    this.drivingDistanceKm,
    this.walkingDuration,
    this.walkingDistanceKm,
    this.stopDuration,
  });

  @override
  State<ArrivedScreen> createState() => _ArrivedScreenState();
}

class _ArrivedScreenState extends State<ArrivedScreen> {
  Task? _task;
  bool _photoProofDone = false;
  bool _storedOtpRequired = false;
  bool _submittingComplete = false;
  List<Map<String, dynamic>> _assignedTemplates = [];
  List<Map<String, dynamic>> _formResponsesForTask = [];
  String? _staffId;
  bool _formLoading = false;
  TaskMovementSummary? _movementSummary;
  double? _routeDistanceKm;

  /// Physical arrival point (Trip Details "Destination" row).
  String? _arrivalDisplayAddress;
  double? _arrivalDisplayLat;
  double? _arrivalDisplayLng;

  Task? get task => _task;

  void _syncArrivalDisplayFromState() {
    if (widget.arrivalAtLat != null && widget.arrivalAtLng != null) {
      _arrivalDisplayLat = widget.arrivalAtLat;
      _arrivalDisplayLng = widget.arrivalAtLng;
      _arrivalDisplayAddress = widget.arrivalAtAddress;
      return;
    }
    final a = _task?.arrivalLocation ?? widget.task?.arrivalLocation;
    if (a != null && (a.lat != 0 || a.lng != 0)) {
      _arrivalDisplayLat = a.lat;
      _arrivalDisplayLng = a.lng;
      _arrivalDisplayAddress = a.displayAddress;
    }
  }

  /// Form is required when staff has assigned templates. Shown only when > 0.
  bool get _hasFormAssigned => _assignedTemplates.isNotEmpty;

  /// All assigned forms filled for this task.
  bool get _formFilled {
    if (_assignedTemplates.isEmpty) return true; // N/A
    if (_formResponsesForTask.isEmpty) return false;
    final filledTemplateIds = _formResponsesForTask
        .map((r) => _templateIdFromResponse(r))
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    return _assignedTemplates.every((t) {
      final id = (t['_id'] ?? t['id'])?.toString();
      return id != null && filledTemplateIds.contains(id);
    });
  }

  static String? _templateIdFromResponse(Map<String, dynamic> r) {
    final tid = r['templateId'];
    if (tid is String) return tid;
    if (tid is Map) return (tid['_id'] ?? tid['id'])?.toString();
    return null;
  }

  /// First template that still needs to be filled.
  Map<String, dynamic>? get _firstUnfilledTemplate {
    if (_assignedTemplates.isEmpty) return null;
    final filledIds = _formResponsesForTask
        .map(_templateIdFromResponse)
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    for (final t in _assignedTemplates) {
      final id = (t['_id'] ?? t['id'])?.toString();
      if (id != null && !filledIds.contains(id)) return t;
    }
    return null;
  }

  /// OTP requirement: from task API (mergeTaskSettings, matched by staff businessId)
  /// or fallback to stored settings from login. Prefer API value when task is loaded.
  bool get _isOtpRequiredFromSettings =>
      _task?.isOtpRequired ?? widget.task?.isOtpRequired ?? _storedOtpRequired;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _photoProofDone = widget.task?.photoProof == true;
    _syncArrivalDisplayFromState();
    _loadStoredTaskSettings();
    _loadStaffIdAndForms();
    _refreshTask();
    _loadMovementSummary();
  }

  Future<void> _loadStaffIdAndForms() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString('user');
    String? staffId;
    if (userStr != null) {
      try {
        final userData = jsonDecode(userStr) as Map<String, dynamic>?;
        final sid = userData?['staffId'] ?? userData?['_id'] ?? userData?['id'];
        staffId = sid?.toString();
      } catch (_) {}
    }
    staffId ??= (widget.task ?? _task)?.assignedTo;
    if (staffId == null || staffId.isEmpty) return;
    if (mounted) setState(() => _staffId = staffId);
    await _loadFormTemplatesAndResponses(staffId!);
  }

  Future<void> _loadFormTemplatesAndResponses(String staffId) async {
    if (mounted) setState(() => _formLoading = true);
    try {
      final templates = await TaskService().getFormTemplatesForStaff(staffId);
      List<Map<String, dynamic>> responses = [];
      if (widget.taskMongoId != null && widget.taskMongoId!.isNotEmpty) {
        responses = await TaskService().getFormResponsesForTask(
          taskId: widget.taskMongoId!,
          staffId: staffId,
        );
      }
      if (mounted) {
        setState(() {
          _assignedTemplates = templates;
          _formResponsesForTask = responses;
          _formLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _formLoading = false);
    }
  }

  Future<void> _loadStoredTaskSettings() async {
    final otpRequired = await AuthService.isOtpRequiredFromStoredSettings();
    if (mounted) setState(() => _storedOtpRequired = otpRequired);
  }

  bool _canOpenOtpScreen() {
    final mongoId = widget.taskMongoId ?? task?.id;
    return task != null &&
        mongoId != null &&
        mongoId.isNotEmpty &&
        task?.isOtpVerified != true;
  }

  /// Fetches task from API with TaskSettings merged (isOtpRequired from enableOtpVerification).
  Future<void> _refreshTask() async {
    if (widget.taskMongoId == null || widget.taskMongoId!.isEmpty) return;
    try {
      final t = await TaskService().getTaskById(widget.taskMongoId!);
      if (mounted) {
        setState(() {
          _task = t;
          _photoProofDone = t.photoProof == true;
          if (widget.arrivalAtLat == null) _syncArrivalDisplayFromState();
        });
      }
      final staffId = _staffId ?? t.assignedTo;
      if (staffId != null && staffId.isNotEmpty) {
        if (_staffId == null && mounted) setState(() => _staffId = staffId);
        await _loadFormTemplatesAndResponses(staffId);
      }
      await _loadMovementSummary();
    } catch (_) {}
  }

  Future<void> _loadMovementSummary() async {
    final taskId = widget.taskMongoId ?? task?.id;
    if (taskId == null || taskId.isEmpty) return;
    try {
      final report = await TaskService().getTaskCompletionReport(taskId);
      final summary = TaskMovementSummary.fromRoutePoints(
        report.routePoints,
        endTime: _travelEndTime ?? widget.arrivalTime,
      );
      if (mounted) {
        setState(() {
          _movementSummary = summary.hasData ? summary : null;
          _routeDistanceKm = computeRouteDistanceKm(
            report.routePoints,
            endTime: _travelEndTime ?? widget.arrivalTime,
          );
        });
      }
    } catch (_) {}
  }

  static String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)} mins';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes} mins ${d.inSeconds.remainder(60)} secs';
    }
    return '${d.inSeconds} secs';
  }

  DateTime? get _travelStartTime => task?.startTime ?? widget.task?.startTime;

  DateTime? get _travelEndTime =>
      task?.arrivalTime ?? widget.task?.arrivalTime ?? widget.arrivalTime;

  Duration get _travelDuration {
    final secs = task?.tripDurationSeconds ?? widget.task?.tripDurationSeconds;
    if (secs != null && secs > 0) {
      return Duration(seconds: secs);
    }
    final start = _travelStartTime;
    final end = _travelEndTime;
    if (start != null && end != null && !end.isBefore(start)) {
      return end.difference(start);
    }
    return widget.totalDuration;
  }

  String? get _sourceDisplayAddress =>
      task?.sourceLocation?.displayAddress ??
      widget.task?.sourceLocation?.displayAddress ??
      widget.sourceAddress;

  double? get _sourceDisplayLat =>
      task?.sourceLocation?.lat ??
      widget.task?.sourceLocation?.lat ??
      widget.sourceLat;

  double? get _sourceDisplayLng =>
      task?.sourceLocation?.lng ??
      widget.task?.sourceLocation?.lng ??
      widget.sourceLng;

  String? get _destinationDisplayAddress =>
      _arrivalDisplayAddress ??
      task?.arrivalLocation?.displayAddress ??
      widget.task?.arrivalLocation?.displayAddress ??
      widget.arrivalAtAddress;

  double? get _destinationDisplayLat =>
      _arrivalDisplayLat ??
      task?.arrivalLocation?.lat ??
      widget.task?.arrivalLocation?.lat ??
      widget.arrivalAtLat;

  double? get _destinationDisplayLng =>
      _arrivalDisplayLng ??
      task?.arrivalLocation?.lng ??
      widget.task?.arrivalLocation?.lng ??
      widget.arrivalAtLng;

  double get _displayDistanceKm {
    final taskDistance = task?.tripDistanceKm;
    if (taskDistance != null && taskDistance > 0) return taskDistance;
    final widgetTaskDistance = widget.task?.tripDistanceKm;
    if (widgetTaskDistance != null && widgetTaskDistance > 0) {
      return widgetTaskDistance;
    }
    if (_routeDistanceKm != null && _routeDistanceKm! > 0) return _routeDistanceKm!;
    return widget.totalDistanceKm;
  }

  TaskMovementSummary? get _displayMovementSummary {
    final stored = task?.travelActivityDuration ?? widget.task?.travelActivityDuration;
    if (stored != null) {
      final summary = TaskMovementSummary.fromDurations(
        drivingDuration: Duration(seconds: stored.driveDuration),
        walkingDuration: Duration(seconds: stored.walkDuration),
        stopDuration: Duration(seconds: stored.stopDuration),
      );
      if (summary.hasData) return summary;
    }
    if (_movementSummary?.hasData == true) return _movementSummary;
    final fallback = TaskMovementSummary.fromDurations(
      drivingDuration: widget.drivingDuration,
      walkingDuration: widget.walkingDuration,
      stopDuration: widget.stopDuration,
    );
    return fallback.hasData ? fallback : null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onExitRide();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _onExitRide,
          ),
          title: const Text(
            'Arrived',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
          actions: [
            if (task != null)
              IconButton(
                icon: const Icon(Icons.history_rounded),
                tooltip: 'Task history',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TaskHistoryScreen(task: task!),
                    ),
                  );
                },
              ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshTask,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Task info card – same bg as dashboard Recent Leaves card
                  if ((task ?? widget.task) != null)
                    Builder(
                      builder: (context) {
                        final t = task ?? widget.task!;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryDark,
                              ],
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
                              Text(
                                t.taskTitle,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'ID: ${t.taskId}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.95),
                                ),
                              ),
                              if (t.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  t.description,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.95),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  // Arrival confirmation card
                  Container(
                    padding: const EdgeInsets.all(24),
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
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "You've Arrived!",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Great job! You reached the customer location.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (widget.isWithinGeofence) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Within Geo-Fence',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "You're inside the 500m radius",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Trip details card - all trip info
                  Container(
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
                          'Trip Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _row(
                          'Total Distance',
                          '${_displayDistanceKm.toStringAsFixed(2)} km',
                        ),
                        _row(
                          'Travel Start Time',
                          DateDisplayUtil.formatTime(_travelStartTime),
                        ),
                        _row(
                          'Travel End Time',
                          DateDisplayUtil.formatTime(_travelEndTime),
                        ),
                        _row(
                          'Total Travel Duration',
                          _formatDuration(_travelDuration),
                        ),
                        if (_displayMovementSummary != null) ...[
                          _row(
                            'Drive Duration',
                            _formatDuration(
                              _displayMovementSummary!.drivingDuration,
                            ),
                          ),
                          _row(
                            'Walk Duration',
                            _formatDuration(
                              _displayMovementSummary!.walkingDuration,
                            ),
                          ),
                          _row(
                            'Stop Duration',
                            _formatDuration(
                              _displayMovementSummary!.stopDuration,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        _locationSection(
                          'Source',
                          _sourceDisplayAddress,
                          _sourceDisplayLat,
                          _sourceDisplayLng,
                        ),
                        const SizedBox(height: 12),
                        _locationSection(
                          'Destination',
                          _destinationDisplayAddress,
                          _destinationDisplayLat,
                          _destinationDisplayLng,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Next Steps card – all steps, then Continue to Form (→ OTP if required).
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border(
                        left: BorderSide(color: AppColors.primary, width: 4),
                      ),
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
                          'Next Steps',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Complete these requirements to finish the task:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _nextStepRow(
                          icon: Icons.location_on_rounded,
                          label: 'Reached location',
                          done: true,
                        ),
                        _nextStepRow(
                          icon: Icons.camera_alt_rounded,
                          label: 'Take photo proof',
                          done: _photoProofDone,
                          onTap: task != null && widget.taskMongoId != null
                              ? () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => PhotoProofScreen(
                                        task: task!,
                                        taskMongoId: widget.taskMongoId,
                                        onPhotoUploaded: () => _refreshTask(),
                                      ),
                                    ),
                                  );
                                  await _refreshTask();
                                }
                              : null,
                        ),
                        // OTP step: only when TaskSettings.enableOtpVerification is true
                        if (_isOtpRequiredFromSettings)
                          _nextStepRow(
                            icon: Icons.pin_rounded,
                            label: 'Get OTP from customer',
                            done: (task ?? widget.task)?.isOtpVerified == true,
                            onTap: _canOpenOtpScreen()
                                ? () async {
                                    final mongoId =
                                        widget.taskMongoId ?? task?.id ?? '';
                                    final t = task;
                                    if (t == null || mongoId.isEmpty) return;
                                    final verified = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            OtpVerificationScreen(
                                              task: t,
                                              taskMongoId: mongoId,
                                              arrivalTime: widget.arrivalTime,
                                              totalDuration:
                                                  widget.totalDuration,
                                              totalDistanceKm:
                                                  widget.totalDistanceKm,
                                              autoSendOtp: true,
                                            ),
                                      ),
                                    );
                                    if (context.mounted) {
                                      if (verified == true) {
                                        setState(() {
                                          _task = _task?.copyWith(
                                            isOtpVerified: true,
                                          );
                                        });
                                      }
                                      await _refreshTask();
                                    }
                                  }
                                : null,
                          ),
                        // Form step: only when form template is assigned to staff
                        if (_hasFormAssigned)
                          _nextStepRow(
                            icon: Icons.description_rounded,
                            label: 'Fill required form',
                            done: _formFilled,
                            onTap:
                                (_staffId != null &&
                                    widget.taskMongoId != null &&
                                    _firstUnfilledTemplate != null)
                                ? () async {
                                    final template = _firstUnfilledTemplate!;
                                    final filled = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (ctx) => FormFillScreen(
                                          template: template,
                                          taskMongoId: widget.taskMongoId!,
                                          staffId: _staffId!,
                                          onFormSubmitted: () => _refreshTask(),
                                        ),
                                      ),
                                    );
                                    if (context.mounted && filled == true) {
                                      await _refreshTask();
                                    }
                                  }
                                : null,
                          ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient:
                                    !_submittingComplete &&
                                        (!_isOtpRequiredFromSettings ||
                                            (task ?? widget.task)
                                                    ?.isOtpVerified ==
                                                true) &&
                                        (!_hasFormAssigned || _formFilled)
                                    ? LinearGradient(
                                        colors: [
                                          AppColors.primary,
                                          AppColors.primaryDark,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color:
                                    !_submittingComplete &&
                                        (!_isOtpRequiredFromSettings ||
                                            (task ?? widget.task)
                                                    ?.isOtpVerified ==
                                                true) &&
                                        (!_hasFormAssigned || _formFilled)
                                    ? null
                                    : Colors.grey.shade300,
                              ),
                              child: ElevatedButton.icon(
                                onPressed:
                                    !_submittingComplete &&
                                        (!_isOtpRequiredFromSettings ||
                                            (task ?? widget.task)
                                                    ?.isOtpVerified ==
                                                true) &&
                                        (!_hasFormAssigned || _formFilled)
                                    ? () async {
                                        if (_submittingComplete) return;
                                        setState(
                                          () => _submittingComplete = true,
                                        );
                                        final t = task ?? widget.task;
                                        final startedAt = widget.arrivalTime
                                            .subtract(widget.totalDuration);
                                        final otpVerified =
                                            (task ?? widget.task)
                                                ?.isOtpVerified ==
                                            true;
                                        Task? refreshed = task ?? t;
                                        if (widget.taskMongoId != null &&
                                            widget.taskMongoId!.isNotEmpty) {
                                          try {
                                            refreshed = await TaskService()
                                                .endTask(
                                                  widget.taskMongoId!,
                                                  travelActivityDuration:
                                                      _displayMovementSummary ==
                                                          null
                                                      ? null
                                                      : {
                                                          'driveDuration':
                                                              _displayMovementSummary!
                                                                  .drivingDuration
                                                                  .inSeconds,
                                                          'walkDuration':
                                                              _displayMovementSummary!
                                                                  .walkingDuration
                                                                  .inSeconds,
                                                          'stopDuration':
                                                              _displayMovementSummary!
                                                                  .stopDuration
                                                                  .inSeconds,
                                                        },
                                                );
                                            await PresenceTrackingService()
                                                .resumePresenceTracking();
                                          } catch (e) {
                                            if (mounted) {
                                              setState(
                                                () =>
                                                    _submittingComplete = false,
                                              );
                                              String msg =
                                                  'Failed to complete task';
                                              if (e is DioException &&
                                                  e.response?.data != null) {
                                                final d = e.response!.data;
                                                if (d is Map) {
                                                  msg =
                                                      (d['message'] ??
                                                              d['error'])
                                                          ?.toString() ??
                                                      msg;
                                                }
                                              } else {
                                                msg = '$msg: ${e.toString()}';
                                              }
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(content: Text(msg)),
                                              );
                                            }
                                            return;
                                          }
                                        }
                                        if (mounted) {
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  TaskCompletedScreen(
                                                    task:
                                                        refreshed ?? task ?? t,
                                                    taskMongoId:
                                                        widget.taskMongoId,
                                                    taskId: widget.taskId,
                                                    startedAt: startedAt,
                                                    completedAt: DateTime.now(),
                                                    totalDuration:
                                                        widget.totalDuration,
                                                    totalDistanceKm:
                                                        widget.totalDistanceKm,
                                                    otpVerified: otpVerified,
                                                    geoFence:
                                                        widget.isWithinGeofence,
                                                    formSubmitted:
                                                        _hasFormAssigned &&
                                                        _formFilled,
                                                    photoProof: _photoProofDone,
                                                    arrivalTime:
                                                        widget.arrivalTime,
                                                    otpVerifiedAt:
                                                        (refreshed ?? task ?? t)
                                                            ?.otpVerifiedAt,
                                                    verifiedOtp: null,
                                                    drivingDuration:
                                                        _displayMovementSummary
                                                            ?.drivingDuration,
                                                    walkingDuration:
                                                        _displayMovementSummary
                                                            ?.walkingDuration,
                                                    stopDuration:
                                                        _displayMovementSummary
                                                            ?.stopDuration,
                                                  ),
                                            ),
                                          );
                                        }
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  surfaceTintColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.transparent,
                                  disabledForegroundColor: Colors.grey.shade600,
                                  minimumSize: const Size.fromHeight(52),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: _submittingComplete
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.check_circle_rounded,
                                        size: 22,
                                      ),
                                label: Text(
                                  _submittingComplete
                                      ? 'Completing...'
                                      : 'Complete Task',
                                ),
                              ),
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
    );
  }

  /// Exit Ride: open bottom sheet with reason form (same as live tracking).
  /// Calls exitRide API with current GPS, then pops.
  Future<void> _onExitRide() async {
    final exited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ExitRideBottomSheet(onSubmit: _submitExitRide),
    );
    if (exited != true || !mounted) return;
    // Do not only [Navigator.pop]: Arrived may be the sole route (e.g. Splash→Live→Arrived
    // via pushReplacement), so pop would leave an empty stack → black screen. Match
    // LiveTrackingScreen exit: land on Tasks list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MyTasksScreen()),
        (route) => false,
      );
    });
  }

  Future<void> _submitExitRide(String exitType, String reason) async {
    final mongoId = widget.taskMongoId ?? task?.id;
    if (mongoId == null || mongoId.isEmpty) return;
    try {
      final exitLocation = await _resolveExitLocation();
      await TaskService().exitRide(
        mongoId,
        reason,
        exitType: exitType,
        lat: exitLocation.lat,
        lng: exitLocation.lng,
        fullAddress: exitLocation.address,
        pincode: exitLocation.pincode,
      );
      unawaited(PresenceTrackingService().resumePresenceTracking());
    } catch (e) {
      if (e is DioException && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map) {
          throw Exception(
            (data['message'] ?? data['error'])?.toString() ??
                'Failed to exit ride',
          );
        }
        if (data is String && data.isNotEmpty) {
          throw Exception(data);
        }
      }
      throw Exception(ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  Future<({double? lat, double? lng, String? address, String? pincode})>
  _resolveExitLocation() async {
    double? lat =
        widget.arrivalAtLat ??
        _task?.arrivalLocation?.lat ??
        widget.destLat ??
        task?.destinationLocation?.lat;
    double? lng =
        widget.arrivalAtLng ??
        _task?.arrivalLocation?.lng ??
        widget.destLng ??
        task?.destinationLocation?.lng;
    final address = _arrivalDisplayAddress;
    final pincode = _extractPincodeFromAddress(address);

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      lat ??= lastKnown?.latitude;
      lng ??= lastKnown?.longitude;
    } catch (_) {}

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 3),
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    return (lat: lat, lng: lng, address: address, pincode: pincode);
  }

  String? _extractPincodeFromAddress(String? address) {
    if (address == null || address.isEmpty) return null;
    final match = RegExp(r'\b\d{6}\b').firstMatch(address);
    return match?.group(0);
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationSection(
    String title,
    String? address,
    double? lat,
    double? lng,
  ) {
    final hasAddress = address != null && address.isNotEmpty;
    final hasCoords = lat != null && lng != null && (lat != 0 || lng != 0);
    if (!hasAddress && !hasCoords) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                title == 'Source'
                    ? Icons.gps_fixed_rounded
                    : Icons.location_on_rounded,
                size: 18,
                color: title == 'Source' ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '—',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              title == 'Source'
                  ? Icons.gps_fixed_rounded
                  : Icons.location_on_rounded,
              size: 18,
              // color: title == 'Source' ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          hasAddress
              ? address!
              : (hasCoords
                    ? '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
                    : '—'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _nextStepRow({
    required IconData icon,
    required String label,
    required bool done,
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: done
            ? AppColors.primary.withOpacity(0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : icon,
            color: done ? AppColors.primary : Colors.grey.shade600,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: done ? AppColors.primary : Colors.grey.shade800,
              ),
            ),
          ),
          if (onTap != null && !done)
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: onTap != null && !done
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: content,
            )
          : content,
    );
  }
}
