// Arrived screen – trip summary, "You've Arrived!", Within Geo-Fence, Next Steps.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:hrms/widgets/app_card.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/screens/geo/exit_ride_bottom_sheet.dart';
import 'package:hrms/screens/geo/field_out_form_screen.dart';
import 'package:hrms/screens/geo/my_tasks_screen.dart';
import 'package:hrms/screens/geo/task_completed_screen.dart';
import 'package:hrms/screens/geo/task_history_screen.dart';
import 'package:hrms/services/auth_service.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/services/presence_tracking_service.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/task_movement_summary_util.dart';
import 'package:hrms/utils/snackbar_utils.dart';
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
  final List<dynamic>? travelledRoute;

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
    this.travelledRoute,
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
  final TextEditingController _descriptionController = TextEditingController();

  /// Physical arrival point (Trip Details "Destination" row).
  String? _arrivalDisplayAddress;
  double? _arrivalDisplayLat;
  double? _arrivalDisplayLng;

  Task? get task => _task;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

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

  /// Admin Field-Out form fields for this task (HRMSbackend `requirements`); the web's
  /// defaults when the task carries none.
  List<TaskRequirement> get _fieldOutRequirements {
    final reqs = (_task ?? widget.task)?.requirements ?? const <TaskRequirement>[];
    return reqs.isNotEmpty ? reqs : TaskRequirement.webDefaults;
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
    if (_task?.fieldOutNotes != null && _task!.fieldOutNotes!.trim().isNotEmpty) {
      _descriptionController.text = _task!.fieldOutNotes!.trim();
    }
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
    await _loadFormTemplatesAndResponses(staffId);
  }

  /// HRMSbackend has no /forms routes: the Field-Out form arrives on the task itself as
  /// `requirements` (see [_fieldOutRequirements]), so there is nothing to fetch here.
  Future<void> _loadFormTemplatesAndResponses(String staffId) async {}

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
          if (_descriptionController.text.trim().isEmpty &&
              t.fieldOutNotes != null &&
              t.fieldOutNotes!.trim().isNotEmpty) {
            _descriptionController.text = t.fieldOutNotes!.trim();
          }
          if (widget.arrivalAtLat == null) _syncArrivalDisplayFromState();
        });
      }
      final staffId = _staffId ?? t.assignedTo;
      if (staffId.isNotEmpty) {
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
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Exit ride',
            onPressed: _onExitRide,
          ),
          title: const Text('Arrived'),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Task info card – same bg as dashboard Recent Leaves card
                  if ((task ?? widget.task) != null)
                    Builder(
                      builder: (context) {
                        final t = task ?? widget.task!;
                        return Container(
                          padding: const EdgeInsets.all(20),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryDark,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.taskTitle,
                                style: AppTextStyles.headingSmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'ID: ${t.taskId}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.onPrimary.withValues(alpha: 0.85),
                                ),
                              ),
                              if (t.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  t.description,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.onPrimary.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  // Arrival confirmation card
                  AppCard(
                    padding: const EdgeInsets.all(24),
                    border: Border.all(color: const Color(0xFFECEEF1)),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: AppColors.successBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: AppColors.success,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "You've Arrived!",
                          style: AppTextStyles.headingLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Great job! You reached the customer location.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (widget.isWithinGeofence) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.success,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Within Geo-Fence',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            // The server checked the real radius (task / customer / branch) at Arrived.
                            "You're at the task location",
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Trip details card - all trip info
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    border: Border.all(color: const Color(0xFFECEEF1)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trip Details',
                          style: AppTextStyles.headingSmall,
                        ),
                        const SizedBox(height: 12),
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
                        if ((task ?? widget.task)?.arrivalLocation
                                ?.overridencustomerlocation ==
                            true)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Arrival differs from customer location (>50m).',
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        if ((task ?? widget.task)?.arrivalLocation
                                ?.overridendestinationlocation ==
                            true)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Arrival differs from destination (>50m).',
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Next Steps card – all steps, then Continue to Form (→ OTP if required).
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    border: Border.all(color: const Color(0xFFECEEF1)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Next Steps',
                          style: AppTextStyles.headingSmall,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Complete these requirements to finish the task:',
                          style: AppTextStyles.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        _nextStepRow(
                          icon: Icons.location_on_rounded,
                          label: 'Reached location',
                          done: true,
                        ),
                        // Field-Out requirements come from the admin's form template
                        // (task.requirements); they are filled in on the Field Out form.
                        for (final r in _fieldOutRequirements)
                          _nextStepRow(
                            icon: r.isImage
                                ? Icons.camera_alt_rounded
                                : (r.isEmail || r.isOtp)
                                    ? Icons.pin_rounded
                                    : Icons.edit_note_rounded,
                            label: r.name,
                            done: false,
                          ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient:
                                    !_submittingComplete
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
                                    !_submittingComplete
                                    ? null
                                    : AppColors.inputFill,
                              ),
                              child: ElevatedButton.icon(
                                onPressed:
                                    !_submittingComplete
                                    ? () async {
                                        if (_submittingComplete) return;
                                        final t = task ?? widget.task;
                                        // Admin Field-Out form (same fields/rules as the web).
                                        final answers = await FieldOutFormScreen.open(
                                          context,
                                          requirements: _fieldOutRequirements,
                                          title: 'Field Out',
                                          subtitle: t != null
                                              ? 'Task #${t.taskId} - ${t.taskTitle}'
                                              : null,
                                          prefillEmail: t?.customer?.effectiveEmail,
                                        );
                                        if (answers == null || !mounted) return;
                                        setState(
                                          () => _submittingComplete = true,
                                        );
                                        final startedAt = widget.arrivalTime
                                            .subtract(widget.totalDuration);
                                        final otpVerified = answers.keys.any(
                                          (k) => _fieldOutRequirements.any(
                                            (r) => r.name == k && (r.isOtp || r.isEmail),
                                          ),
                                        );
                                        Task? refreshed = task ?? t;
                                        // Field Out is checked against the destination geofence
                                        // with the CURRENT position, not the arrival point.
                                        double? outLat = widget.arrivalAtLat;
                                        double? outLng = widget.arrivalAtLng;
                                        try {
                                          final pos = await Geolocator.getCurrentPosition(
                                            locationSettings: const LocationSettings(
                                              accuracy: LocationAccuracy.high,
                                            ),
                                          ).timeout(const Duration(seconds: 12));
                                          outLat = pos.latitude;
                                          outLng = pos.longitude;
                                        } catch (_) {}
                                        String? answerFor(bool Function(TaskRequirement) test) {
                                          for (final r in _fieldOutRequirements) {
                                            if (test(r) && answers[r.name] != null) return answers[r.name];
                                          }
                                          return null;
                                        }
                                        final desc = answerFor((r) => r.isTextArea) ?? 'Completed';
                                        if (widget.taskMongoId != null &&
                                            widget.taskMongoId!.isNotEmpty) {
                                          try {
                                            refreshed = await TaskService()
                                                .endTask(
                                                  widget.taskMongoId!,
                                                  lat: outLat,
                                                  lng: outLng,
                                                  fieldOutNotes: desc,
                                                  fieldOutImage: answerFor((r) => r.isImage),
                                                  fieldOutOtp: answerFor((r) => r.isOtp),
                                                  answers: answers,
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
                                              final msg = ErrorMessageUtils.toUserFriendlyMessage(e);
                                              SnackBarUtils.showSnackBar(
                                                context,
                                                msg,
                                                isError: true,
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
                                                    formSubmitted: answers.isNotEmpty,
                                                    photoProof: answerFor((r) => r.isImage) != null,
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
                                  foregroundColor: AppColors.onPrimary,
                                  disabledBackgroundColor: Colors.transparent,
                                  disabledForegroundColor: AppColors.textSecondary,
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
                                          color: AppColors.textSecondary,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.check_circle_rounded,
                                        size: 20,
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
    final mongoId = widget.taskMongoId ?? task?.id ?? task?.taskId ?? widget.taskId;
    if (mongoId.isEmpty) return;
    final exitLocation = await _resolveExitLocation();
    // Errors propagate to ExitRideBottomSheet, which shows them and stays open.
    await TaskService().exitRide(
      mongoId,
      reason,
      exitType: exitType,
      lat: exitLocation.lat,
      lng: exitLocation.lng,
      fullAddress: exitLocation.address,
      pincode: exitLocation.pincode,
      tripDistanceKm: widget.totalDistanceKm,
      tripDurationSeconds: widget.totalDuration.inSeconds,
      travelledRoute: widget.travelledRoute,
    );
    unawaited(PresenceTrackingService().resumePresenceTracking());
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
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
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
                color: title == 'Source' ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '—',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textCaption,
            ),
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
              color: AppColors.textSecondary,
              // color: title == 'Source' ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          hasAddress
              ? address
              : (hasCoords
                    ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
                    : '—'),
          style: AppTextStyles.bodySmall,
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
    final Color tint = done ? AppColors.success : AppColors.textSecondary;
    final content = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: done ? AppColors.successBg.withValues(alpha: 0.5) : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? AppColors.success.withValues(alpha: 0.2)
              : const Color(0xFFECEEF1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? Icons.check_circle_rounded : icon,
              color: tint,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.label.copyWith(
                color: done ? AppColors.success : AppColors.textPrimary,
              ),
            ),
          ),
          if (onTap != null && !done)
            const Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: onTap != null && !done
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: content,
            )
          : content,
    );
  }
}
