// Full ride history: exits, restarts, destination changes – fetched from task_details.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/widgets/app_tab_loader.dart';

class TaskHistoryScreen extends StatefulWidget {
  final Task task;

  const TaskHistoryScreen({super.key, required this.task});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  Task? _task;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchTaskDetails();
  }

  Future<void> _fetchTaskDetails() async {
    if (widget.task.id == null || widget.task.id!.isEmpty) {
      setState(() {
        _task = widget.task;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await TaskService().getTaskById(widget.task.id!);
      if (mounted) {
        setState(() {
          _task = t;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _task = widget.task;
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Task get _displayTask => _task ?? widget.task;

  @override
  Widget build(BuildContext context) {
    final exits = _displayTask.tasksExit;
    final restarts = _displayTask.tasksRestarted;
    final destinations = _displayTask.destinations;
    final hasTimeline =
        _displayTask.startTime != null ||
        _displayTask.arrivalTime != null ||
        _displayTask.photoProofUploadedAt != null ||
        (_displayTask.formFilled == true) ||
        _displayTask.otpVerifiedAt != null ||
        exits.isNotEmpty ||
        restarts.isNotEmpty ||
        destinations.isNotEmpty ||
        _displayTask.completedDate != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Full Ride History'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: _fetchTaskDetails,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Using cached data. $_error',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    if (hasTimeline) ...[
                      if (_displayTask.startTime != null) ...[
                        _sectionTitle(
                          'Started',
                          Icons.play_circle_filled_rounded,
                          Colors.green,
                        ),
                        const SizedBox(height: 8),
                        _timelineTile(
                          icon: Icons.play_circle_filled_rounded,
                          color: Colors.green,
                          label: 'Task started',
                          time: _displayTask.startTime!,
                          address:
                              _displayTask.sourceLocation?.address ??
                              _displayTask.sourceLocation?.fullAddress,
                          lat: _displayTask.sourceLocation?.lat,
                          lng: _displayTask.sourceLocation?.lng,
                          batteryPercent: _displayTask.startBatteryPercent,
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_displayTask.arrivalTime != null) ...[
                        _sectionTitle(
                          'Arrived',
                          Icons.location_on_rounded,
                          Colors.pink,
                        ),
                        const SizedBox(height: 8),
                        _timelineTile(
                          icon: Icons.location_on_rounded,
                          color: Colors.pink,
                          label: 'Arrived at destination',
                          time: _displayTask.arrivalTime!,
                          address: null,
                          lat: null,
                          lng: null,
                          batteryPercent: _displayTask.arrivalBatteryPercent,
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (exits.isNotEmpty) ...[
                        _sectionTitle(
                          'Exits',
                          Icons.exit_to_app_rounded,
                          Colors.orange,
                        ),
                        const SizedBox(height: 8),
                        ...exits.asMap().entries.map(
                          (e) => _exitTile(e.value, e.key + 1),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (restarts.isNotEmpty) ...[
                        _sectionTitle(
                          'Resumed (Restarted)',
                          Icons.replay_rounded,
                          Colors.green,
                        ),
                        const SizedBox(height: 8),
                        ...restarts.asMap().entries.map(
                          (e) => _restartTile(e.value, e.key + 1),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_displayTask.photoProofUploadedAt != null) ...[
                        _sectionTitle(
                          'Photo Proof',
                          Icons.photo_camera_rounded,
                          Colors.purple,
                        ),
                        const SizedBox(height: 8),
                        _photoProofTile(
                          time: _displayTask.photoProofUploadedAt!,
                          address: _displayTask.photoProofAddress,
                          photoUrl: _displayTask.photoProofUrl,
                          batteryPercent: _displayTask.photoProofBatteryPercent,
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_displayTask.formFilled == true) ...[
                        _sectionTitle(
                          'Form Submitted',
                          Icons.description_rounded,
                          Colors.teal,
                        ),
                        const SizedBox(height: 8),
                        _formSubmittedTile(
                          task: _displayTask,
                          time:
                              _displayTask.arrivalTime ??
                              _displayTask.completedDate ??
                              DateTime.now(),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_displayTask.otpVerifiedAt != null) ...[
                        _sectionTitle(
                          'OTP Verified',
                          Icons.pin_rounded,
                          Colors.indigo,
                        ),
                        const SizedBox(height: 8),
                        _timelineTile(
                          icon: Icons.pin_rounded,
                          color: Colors.indigo,
                          label: 'OTP verified',
                          time: _displayTask.otpVerifiedAt!,
                          address: _displayTask.otpVerifiedAddress,
                          lat: null,
                          lng: null,
                          batteryPercent:
                              _displayTask.otpVerifiedBatteryPercent,
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (destinations.length > 1) ...[
                        _sectionTitle(
                          'Destination Changes',
                          Icons.edit_location_rounded,
                          AppColors.primary,
                        ),
                        const SizedBox(height: 8),
                        ...destinations
                            .asMap()
                            .entries
                            .skip(1)
                            .map((e) => _destinationTile(e.value, e.key + 1)),
                        const SizedBox(height: 24),
                      ],
                      if (_displayTask.completedDate != null) ...[
                        _sectionTitle(
                          'Completed',
                          Icons.check_circle_rounded,
                          AppColors.primary,
                        ),
                        const SizedBox(height: 8),
                        _timelineTile(
                          icon: Icons.check_circle_rounded,
                          color: AppColors.primary,
                          label: 'Task completed',
                          time: _displayTask.completedDate!,
                          address: null,
                          lat: null,
                          lng: null,
                          batteryPercent: _displayTask.completedBatteryPercent,
                        ),
                      ],
                    ] else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No history yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Exits, restarts, arrival, photo proof, OTP verification, and destination changes will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _formSubmittedTile({required Task task, required DateTime time}) {
    return InkWell(
      onTap: () => _showFormDetailsBottomSheet(context, task),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.description_rounded,
                size: 26,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Form submitted',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateDisplayUtil.formatTimeline(time),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap to view form details',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.teal.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFormDetailsBottomSheet(
    BuildContext context,
    Task task,
  ) async {
    if (task.id == null || task.id!.isEmpty || task.assignedTo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load form details')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FormDetailsSheet(
        taskId: task.id!,
        staffId: task.assignedTo,
        taskTitle: task.taskTitle,
      ),
    );
  }

  Widget _photoProofTile({
    required DateTime time,
    String? address,
    String? photoUrl,
    int? batteryPercent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.photo_camera_rounded,
              size: 26,
              color: Colors.purple,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Photo proof uploaded',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateDisplayUtil.formatTimeline(time),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (batteryPercent != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.battery_std_rounded,
                        size: 14,
                        color: _batteryColor(batteryPercent),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Battery: $batteryPercent%',
                        style: TextStyle(
                          fontSize: 12,
                          color: _batteryColor(batteryPercent),
                        ),
                      ),
                    ],
                  ),
                ],
                if (address != null && address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (photoUrl != null && photoUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _showNetworkImage(context, photoUrl),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.visibility_rounded,
                            size: 16,
                            color: Colors.purple,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Proof uploaded',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.purple,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.purple.shade300,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineTile({
    required IconData icon,
    required Color color,
    required String label,
    required DateTime time,
    String? address,
    double? lat,
    double? lng,
    int? batteryPercent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 26, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateDisplayUtil.formatTimeline(time),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (batteryPercent != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.battery_std_rounded,
                        size: 14,
                        color: _batteryColor(batteryPercent),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Battery: $batteryPercent%',
                        style: TextStyle(
                          fontSize: 12,
                          color: _batteryColor(batteryPercent),
                        ),
                      ),
                    ],
                  ),
                ],
                if (address != null && address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (lat != null && lng != null)
                  Text(
                    '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Blue if battery >= 10 or null; red if battery < 10.
  Color _batteryColor(int? percent) =>
      (percent != null && percent < 10) ? Colors.red : Colors.blue;

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: valueColor ?? Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exitTile(TaskExitRecord e, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.exit_to_app_rounded,
              size: 26,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exit #$index',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                if (e.exitedAt != null)
                  _detailRow(
                    'Date & Time',
                    DateDisplayUtil.formatDateTime(e.exitedAt!),
                  ),
                if (e.batteryPercent != null)
                  _detailRow(
                    'Battery',
                    '${e.batteryPercent}%',
                    valueColor: _batteryColor(e.batteryPercent),
                  ),
                _detailRow(
                  'Reason',
                  e.exitReason.isNotEmpty ? e.exitReason : '—',
                ),
                if (e.address != null && e.address!.isNotEmpty)
                  _detailRow('Location', e.address!),
                if (e.pincode != null && e.pincode!.isNotEmpty)
                  _detailRow('Pincode', e.pincode!),
                if (e.lat != 0 || e.lng != 0)
                  _detailRow(
                    'Coordinates',
                    '${e.lat.toStringAsFixed(5)}, ${e.lng.toStringAsFixed(5)}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _restartTile(TaskRestartRecord r, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.replay_rounded,
              size: 26,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumed #$index',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                if (r.resumedAt != null)
                  _detailRow(
                    'Date & Time',
                    DateDisplayUtil.formatDateTime(r.resumedAt!),
                  ),
                if (r.batteryPercent != null)
                  _detailRow(
                    'Battery',
                    '${r.batteryPercent}%',
                    valueColor: _batteryColor(r.batteryPercent),
                  ),
                if (r.address != null && r.address!.isNotEmpty)
                  _detailRow('Location', r.address!),
                if (r.pincode != null && r.pincode!.isNotEmpty)
                  _detailRow('Pincode', r.pincode!),
                if (r.lat != 0 || r.lng != 0)
                  _detailRow(
                    'Coordinates',
                    '${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _destinationTile(TaskDestinationRecord d, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.edit_location_rounded,
              size: 26,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destination change #$index',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                if (d.changedAt != null)
                  _detailRow(
                    'Date & Time',
                    DateDisplayUtil.formatDateTime(d.changedAt!),
                  ),
                if (d.address != null && d.address!.isNotEmpty)
                  _detailRow('Location', d.address!),
                _detailRow(
                  'Coordinates',
                  '${d.lat.toStringAsFixed(5)}, ${d.lng.toStringAsFixed(5)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNetworkImage(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            size: 40,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Unable to load image',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that shows filled form details with photos.
class _FormDetailsSheet extends StatefulWidget {
  final String taskId;
  final String staffId;
  final String taskTitle;

  const _FormDetailsSheet({
    required this.taskId,
    required this.staffId,
    required this.taskTitle,
  });

  @override
  State<_FormDetailsSheet> createState() => _FormDetailsSheetState();
}

class _FormDetailsSheetState extends State<_FormDetailsSheet> {
  List<FormResponseData> _forms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchFormResponses();
  }

  Future<void> _fetchFormResponses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await TaskService().getFormResponsesForTask(
        taskId: widget.taskId,
        staffId: widget.staffId,
      );
      if (mounted) {
        setState(() {
          _forms = raw.map((r) => FormResponseData.fromJson(r)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_rounded,
                    color: Colors.teal,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Form Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          widget.taskTitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: AppTabLoader())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _forms.isEmpty
                  ? Center(
                      child: Text(
                        'No form data found',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchFormResponses,
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        itemCount: _forms.length,
                        itemBuilder: (context, i) {
                          return _buildFormCard(_forms[i]);
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFormCard(FormResponseData form) {
    final templateName = form.templateName ?? 'Form';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
            templateName,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...form.responses.entries.map((e) {
            final key = e.key;
            final val = e.value;
            if (val is String && val.startsWith('data:image')) {
              try {
                final base64 = val.split(',').last;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _formRow(key, null),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: GestureDetector(
                        onTap: () => _showFullImage(context, base64),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            base64Decode(base64),
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              } catch (_) {
                return _formRow(key, '—');
              }
            }
            return _formRow(key, val?.toString() ?? '—');
          }),
        ],
      ),
    );
  }

  Widget _formRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
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
                style: const TextStyle(fontSize: 13, color: Colors.black),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, String base64) {
    try {
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(base64),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

}
