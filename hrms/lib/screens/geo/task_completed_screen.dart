// Task Completed screen – success confirmation, task details, track timeline.
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/screens/geo/completed_task_detail_screen.dart';
import 'package:hrms/screens/geo/my_tasks_screen.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:hrms/utils/task_movement_summary_util.dart';
import 'package:hrms/widgets/notification_reaction_overlay.dart';

/// One event in the task track timeline.
class _TimelineEvent {
  final DateTime time;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;

  const _TimelineEvent({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });
}

class TaskCompletedScreen extends StatefulWidget {
  final Task? task;
  final String? taskMongoId;
  final String taskId;
  final DateTime startedAt;
  final DateTime completedAt;
  final Duration totalDuration;
  final double totalDistanceKm;
  final bool otpVerified;
  final bool geoFence;
  final bool formSubmitted;
  final bool photoProof;
  final DateTime? arrivalTime;
  final DateTime? otpVerifiedAt;
  final String? verifiedOtp;
  final DateTime? formSubmittedAt;
  final Duration? drivingDuration;
  final double? drivingDistanceKm;
  final Duration? walkingDuration;
  final double? walkingDistanceKm;
  final Duration? stopDuration;

  const TaskCompletedScreen({
    super.key,
    this.task,
    this.taskMongoId,
    required this.taskId,
    required this.startedAt,
    required this.completedAt,
    required this.totalDuration,
    required this.totalDistanceKm,
    required this.otpVerified,
    required this.geoFence,
    required this.formSubmitted,
    required this.photoProof,
    this.arrivalTime,
    this.otpVerifiedAt,
    this.verifiedOtp,
    this.formSubmittedAt,
    this.drivingDuration,
    this.drivingDistanceKm,
    this.walkingDuration,
    this.walkingDistanceKm,
    this.stopDuration,
  });

  @override
  State<TaskCompletedScreen> createState() => _TaskCompletedScreenState();
}

class _TaskCompletedScreenState extends State<TaskCompletedScreen> {
  Task? _fetchedTask;
  TaskMovementSummary? _movementSummary;
  bool _loading = true;
  bool _didShowCompletionFeedback = false;

  @override
  void initState() {
    super.initState();
    _fetchTask();
  }

  Future<void> _fetchTask() async {
    final fallbackSummary = TaskMovementSummary.fromDurations(
      drivingDuration: widget.drivingDuration,
      walkingDuration: widget.walkingDuration,
      stopDuration: widget.stopDuration,
    );
    if (widget.taskMongoId == null || widget.taskMongoId!.isEmpty) {
      setState(() {
        _fetchedTask = widget.task;
        _movementSummary = fallbackSummary.hasData ? fallbackSummary : null;
        _loading = false;
      });
      _showCompletionFeedbackIfNeeded();
      return;
    }
    try {
      final t = await TaskService().getTaskById(widget.taskMongoId!);
      TaskMovementSummary? summary;
      try {
        final report = await TaskService().getTaskCompletionReport(
          widget.taskMongoId!,
        );
        final computed = TaskMovementSummary.fromRoutePoints(
          report.routePoints,
          endTime: t.arrivalTime ?? widget.arrivalTime,
        );
        if (computed.hasData) summary = computed;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _fetchedTask = t;
          _movementSummary = summary ?? (fallbackSummary.hasData ? fallbackSummary : null);
          _loading = false;
        });
        _showCompletionFeedbackIfNeeded();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _fetchedTask = widget.task;
          _movementSummary = fallbackSummary.hasData ? fallbackSummary : null;
          _loading = false;
        });
        _showCompletionFeedbackIfNeeded();
      }
    }
  }

  Task? get _task => _fetchedTask ?? widget.task;

  bool get _isWaitingForApproval =>
      _task?.status == TaskStatus.waitingForApproval;

  double get _displayDistanceKm =>
      ((_task?.tripDistanceKm != null && _task!.tripDistanceKm! > 0)
              ? _task!.tripDistanceKm!
              : null) ??
      widget.totalDistanceKm;

  /// Travel duration: time from journey started to arrived, or (if exited) from resumed to arrived.
  Duration get _displayDuration {
    final secs = _task?.tripDurationSeconds;
    if (secs != null && secs > 0) {
      return Duration(seconds: secs);
    }
    return widget.totalDuration;
  }

  /// Total task duration: task start time to end time.
  Duration get _totalTaskDuration {
    final start = _task?.startTime ?? widget.startedAt;
    final end = _task?.completedDate ?? widget.completedAt;
    return end.difference(start);
  }

  bool get _displayOtpVerified => _task?.isOtpVerified ?? widget.otpVerified;

  bool get _displayPhotoProof => _task?.photoProof ?? widget.photoProof;

  Future<void> _showCompletionFeedbackIfNeeded() async {
    if (!mounted || _didShowCompletionFeedback) return;
    _didShowCompletionFeedback = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Wuhu! Task completed!');
      await NotificationReactionOverlay.show(
        context,
        emoji: '😎',
      );
    });
  }

  /// Only true when a form was actually submitted (had assigned forms and filled them).
  bool get _displayFormSubmitted {
    if (_task != null && _task!.formFilled != null) return _task!.formFilled!;
    return widget.formSubmitted;
  }

  TaskMovementSummary? get _displayMovementSummary {
    final stored = _task?.travelActivityDuration;
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
    if (remainderSecs > 0) return '${mins} min${mins == 1 ? '' : 's'} ${remainderSecs} secs';
    return mins == 1 ? '1 min' : '$mins mins';
  }

  static String _formatDistanceKm(double distanceKm) {
    final decimals = distanceKm < 1 ? 2 : 1;
    return '${distanceKm.toStringAsFixed(decimals)} km';
  }

  List<_TimelineEvent> _buildTimelineEvents() {
    final events = <_TimelineEvent>[];
    final arrival =
        widget.arrivalTime ?? widget.startedAt.add(widget.totalDuration);

    events.add(
      _TimelineEvent(
        time: widget.startedAt,
        title: 'Task Started',
        subtitle: 'Started journey',
        icon: Icons.play_circle_filled_rounded,
        iconColor: AppColors.secondary,
      ),
    );

    if (widget.drivingDuration != null &&
        widget.drivingDuration!.inSeconds > 0 &&
        widget.drivingDistanceKm != null) {
      events.add(
        _TimelineEvent(
          time: widget.startedAt,
          title: 'Driving (${_formatDuration(widget.drivingDuration!)})',
          subtitle:
              '${_formatDistanceKm(widget.drivingDistanceKm!)} covered',
          icon: Icons.directions_car_rounded,
          iconColor: Colors.red.shade400,
        ),
      );
    }
    if (widget.walkingDuration != null &&
        widget.walkingDuration!.inSeconds > 0 &&
        widget.walkingDistanceKm != null) {
      events.add(
        _TimelineEvent(
          time: arrival.subtract(widget.walkingDuration!),
          title: 'Walking (${_formatDuration(widget.walkingDuration!)})',
          subtitle:
              '${_formatDistanceKm(widget.walkingDistanceKm!)} covered',
          icon: Icons.directions_walk_rounded,
          iconColor: Colors.amber.shade700,
        ),
      );
    }
    if ((widget.drivingDuration == null ||
            widget.drivingDuration!.inSeconds == 0) &&
        (widget.walkingDuration == null ||
            widget.walkingDuration!.inSeconds == 0)) {
      events.add(
        _TimelineEvent(
          time: widget.startedAt,
          title: 'Travel (${_formatDuration(_displayDuration)})',
          subtitle: '${_formatDistanceKm(_displayDistanceKm)} covered',
          icon: Icons.route_rounded,
          iconColor: AppColors.secondary,
        ),
      );
    }

    events.add(
      _TimelineEvent(
        time: arrival,
        title: 'Arrived at Location',
        subtitle: 'Within geo-fence',
        icon: Icons.location_on_rounded,
        iconColor: Colors.pink.shade400,
      ),
    );

    if (_displayFormSubmitted &&
        (widget.formSubmittedAt != null || widget.otpVerifiedAt != null)) {
      events.add(
        _TimelineEvent(
          time: widget.formSubmittedAt ?? widget.otpVerifiedAt ?? arrival,
          title: 'Form Submitted',
          subtitle: 'Customer details captured',
          icon: Icons.description_rounded,
          iconColor: Colors.brown.shade400,
        ),
      );
    }

    if (_displayOtpVerified && widget.otpVerifiedAt != null) {
      events.add(
        _TimelineEvent(
          time: widget.otpVerifiedAt!,
          title: 'OTP Verified',
          subtitle: widget.verifiedOtp != null
              ? 'Customer confirmed (${widget.verifiedOtp})'
              : 'Customer confirmed',
          icon: Icons.verified_user_rounded,
          iconColor: AppColors.secondary,
        ),
      );
    }

    events.add(
      _TimelineEvent(
        time: widget.completedAt,
        title: 'Task Completed',
        subtitle: '',
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.primary,
      ),
    );

    return events;
  }

  void _goToMyTasks(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MyTasksScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerName = _task?.customer?.customerName ?? '—';
    final taskTitle = _task?.taskTitle ?? 'Customer Visit';

    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          title: const Text(
            'Task Completed',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goToMyTasks(context);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          leading: const SizedBox.shrink(),
          title: Text(
            _isWaitingForApproval ? 'Waiting for Approval' : 'Task Completed',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // Success icon
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isWaitingForApproval
                      ? 'Waiting for Approval'
                      : 'Task Completed!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isWaitingForApproval
                      ? 'Your task completion has been submitted. Awaiting admin approval.'
                      : 'Excellent work! The task has been successfully completed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 28),
                // Task details card
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
                        'Task #${widget.taskId}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$taskTitle - $customerName',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _detailRow(
                        'Started At',
                        DateDisplayUtil.formatTime(widget.startedAt),
                      ),
                      _divider(),
                      _detailRow(
                        'Completed At',
                        DateDisplayUtil.formatTime(widget.completedAt),
                      ),
                      _divider(),
                      _detailRow(
                        'Travel Duration',
                        _formatDuration(_displayDuration),
                      ),
                      _divider(),
                      if (_displayMovementSummary != null) ...[
                        _detailRow(
                          'Drive Duration',
                          _formatDuration(
                            _displayMovementSummary!.drivingDuration,
                          ),
                        ),
                        _divider(),
                        _detailRow(
                          'Walk Duration',
                          _formatDuration(
                            _displayMovementSummary!.walkingDuration,
                          ),
                        ),
                        _divider(),
                        _detailRow(
                          'Stop Duration',
                          _formatDuration(_displayMovementSummary!.stopDuration),
                        ),
                        _divider(),
                      ],
                      _detailRow(
                        'Total Task Duration',
                        _formatDuration(_totalTaskDuration),
                      ),
                      _divider(),
                      _detailRow(
                        'Distance Travelled',
                        '${_displayDistanceKm.toStringAsFixed(2)} km',
                      ),
                      _divider(),
                      _detailRow(
                        'Total Distance',
                        '${_displayDistanceKm.toStringAsFixed(2)} km',
                      ),
                      _divider(),
                      _verificationRow('OTP Verified', _displayOtpVerified),
                      _divider(),
                      _verificationRow('Form Submitted', _displayFormSubmitted),
                      _divider(),
                      _verificationRow(
                        'Photo Proof',
                        _displayPhotoProof,
                        value: _displayPhotoProof
                            ? (_task?.photoProofUrl != null
                                  ? 'Uploaded'
                                  : 'Yes')
                            : '—',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Track details timeline
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
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
                  child: _buildTimeline(context),
                ),
                const SizedBox(height: 24),
                // Bottom status
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            '8',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isWaitingForApproval
                            ? 'Awaiting Admin Approval'
                            : 'Task Completed Successfully',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_task != null && !_isWaitingForApproval)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) =>
                                CompletedTaskDetailScreen(task: _task!),
                          ),
                        );
                      },
                      icon: const Icon(Icons.timeline_rounded, size: 22),
                      label: const Text('View Full Report & Timeline'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _goToMyTasks(context),
                    icon: const Icon(Icons.home_rounded, size: 22),
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
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verificationRow(String label, bool done, {String? value}) {
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

  Widget _divider() {
    return Divider(height: 1, color: Colors.grey.shade200);
  }

  Widget _buildTimeline(BuildContext context) {
    final events = _buildTimelineEvents();
    return Row(
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
                Container(width: 2, height: 56, color: Colors.grey.shade300),
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
    );
  }
}
