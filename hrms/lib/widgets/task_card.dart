import 'package:flutter/material.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/utils/date_display_util.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onStartTask;

  const TaskCard({super.key, required this.task, required this.onStartTask});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Color statusColor;
    String statusText;
    switch (task.status) {
      case TaskStatus.assigned:
        statusColor = Colors.green;
        statusText = 'Assigned';
        break;
      case TaskStatus.pending:
        statusColor = Colors.orange;
        statusText = 'Pending';
        break;
      case TaskStatus.scheduled:
        statusColor = Colors.blue;
        statusText = 'Scheduled';
        break;
      case TaskStatus.approved:
      case TaskStatus.staffapproved:
        statusColor = Colors.teal;
        statusText = 'Approved';
        break;
      case TaskStatus.inProgress:
        statusColor = Colors.blue;
        statusText = 'In Progress';
        break;
      case TaskStatus.arrived:
        statusColor = Colors.indigo;
        statusText = 'Arrived';
        break;
      case TaskStatus.exited:
        statusColor = Colors.amber;
        statusText = 'Exited';
        break;
      case TaskStatus.exitedOnArrival:
        statusColor = Colors.orange;
        statusText = 'Exited on Arrival';
        break;
      case TaskStatus.holdOnArrival:
        statusColor = Colors.amber;
        statusText = 'Hold on Arrival';
        break;
      case TaskStatus.reopenedOnArrival:
        statusColor = Colors.teal;
        statusText = 'Reopened on Arrival';
        break;
      case TaskStatus.waitingForApproval:
        statusColor = Colors.amber;
        statusText = 'Waiting for Approval';
        break;
      case TaskStatus.completed:
        statusColor = Colors.green;
        statusText = 'Completed';
        break;
      case TaskStatus.rejected:
        statusColor = Colors.red;
        statusText = 'Rejected';
        break;
      case TaskStatus.cancelled:
        statusColor = Colors.grey;
        statusText = 'Cancelled';
        break;
      case TaskStatus.reopened:
        statusColor = Colors.teal;
        statusText = 'Reopened';
        break;
      case TaskStatus.hold:
        statusColor = Colors.amber;
        statusText = 'Hold';
        break;
      case TaskStatus.onlineReady:
        statusColor = Colors.grey;
        statusText = 'Ready';
        break;
    }

    bool isTaskActionable =
        task.status == TaskStatus.assigned ||
        task.status == TaskStatus.pending ||
        task.status == TaskStatus.approved ||
        task.status == TaskStatus.staffapproved;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isTaskActionable
            ? BorderSide(color: Theme.of(context).primaryColor, width: 1.5)
            : BorderSide.none,
      ),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('🆔', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      'Task #${task.taskId}',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Chip(
                  label: Text(
                    statusText,
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  backgroundColor: statusColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 0,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📄', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Description',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.taskTitle,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (task.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            task.description,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.sourceLocation?.displayAddress ??
                            'Current location',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.destinationLocation?.displayAddress ??
                            (task.customer != null
                                ? '${task.customer!.address}, ${task.customer!.city}, ${task.customer!.pincode}'
                                : '—'),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('🕒', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  _formatCompletionDate(task.expectedCompletionDate),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (task.isOtpRequired)
                  _buildRequirementChip(
                    'OTP',
                    Colors.blue.shade100,
                    Colors.blue.shade800,
                  ),
                if (task.isGeoFenceRequired)
                  _buildRequirementChip(
                    'Geo',
                    Colors.green.shade100,
                    Colors.green.shade800,
                  ),
                if (task.isPhotoRequired)
                  _buildRequirementChip(
                    'Photo',
                    Colors.purple.shade100,
                    Colors.purple.shade800,
                  ),
                if (task.isFormRequired)
                  _buildRequirementChip(
                    'Form',
                    Colors.orange.shade100,
                    Colors.orange.shade800,
                  ),
              ],
            ),
            if (task.completedDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Completed: ${DateDisplayUtil.formatDateOnly(task.completedDate!)}',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            if (isTaskActionable)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onStartTask,
                  icon: Icon(
                    Icons.rocket_launch,
                    color: colorScheme.onPrimary,
                    size: 18,
                  ),
                  label: Text(
                    'Start Task',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementChip(
    String label,
    Color backgroundColor,
    Color textColor,
  ) {
    return Chip(
      label: Text(label, style: TextStyle(color: textColor, fontSize: 10)),
      backgroundColor: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _formatCompletionDate(DateTime date) {
    final local = date.isUtc ? date.toLocal() : date;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day) {
      return 'Today, ${DateDisplayUtil.formatTime(local)}';
    }
    if (local.year == tomorrow.year &&
        local.month == tomorrow.month &&
        local.day == tomorrow.day) {
      return 'Tomorrow, ${DateDisplayUtil.formatTime(local)}';
    }
    return DateDisplayUtil.formatDateTime(local);
  }
}
