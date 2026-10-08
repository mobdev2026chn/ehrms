import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/utils/date_display_util.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onStartTask;

  const TaskCard({super.key, required this.task, required this.onStartTask});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;
    switch (task.status) {
      case TaskStatus.assigned:
        statusColor = AppColors.success;
        statusText = 'Assigned';
        break;
      case TaskStatus.pending:
        statusColor = AppColors.brandDark;
        statusText = 'Pending';
        break;
      case TaskStatus.scheduled:
        statusColor = AppColors.info;
        statusText = 'Scheduled';
        break;
      case TaskStatus.approved:
      case TaskStatus.staffapproved:
        statusColor = const Color(0xFF0F766E);
        statusText = 'Approved';
        break;
      case TaskStatus.inProgress:
        statusColor = AppColors.info;
        statusText = 'In Progress';
        break;
      case TaskStatus.arrived:
        statusColor = AppColors.indigo;
        statusText = 'Arrived';
        break;
      case TaskStatus.exited:
        statusColor = AppColors.brandDark;
        statusText = 'Exited';
        break;
      case TaskStatus.exitedOnArrival:
        statusColor = AppColors.brandDark;
        statusText = 'Exited on Arrival';
        break;
      case TaskStatus.holdOnArrival:
        statusColor = AppColors.brandDark;
        statusText = 'Hold on Arrival';
        break;
      case TaskStatus.reopenedOnArrival:
        statusColor = const Color(0xFF0F766E);
        statusText = 'Reopened on Arrival';
        break;
      case TaskStatus.waitingForApproval:
        statusColor = AppColors.brandDark;
        statusText = 'Waiting for Approval';
        break;
      case TaskStatus.completed:
        statusColor = AppColors.success;
        statusText = 'Completed';
        break;
      case TaskStatus.rejected:
        statusColor = AppColors.error;
        statusText = 'Rejected';
        break;
      case TaskStatus.cancelled:
        statusColor = AppColors.textSecondary;
        statusText = 'Cancelled';
        break;
      case TaskStatus.reopened:
        statusColor = const Color(0xFF0F766E);
        statusText = 'Reopened';
        break;
      case TaskStatus.hold:
        statusColor = AppColors.brandDark;
        statusText = 'Hold';
        break;
      case TaskStatus.onlineReady:
        statusColor = AppColors.textSecondary;
        statusText = 'Ready';
        break;
      case TaskStatus.requested:
        statusColor = AppColors.brandDark;
        statusText = 'Requested';
        break;
      // Any status added later must not break the build (switch must be exhaustive).
      default:
        statusColor = AppColors.textSecondary;
        statusText = task.status.name;
    }

    bool isTaskActionable =
        task.status == TaskStatus.assigned ||
        task.status == TaskStatus.pending ||
        task.status == TaskStatus.approved ||
        task.status == TaskStatus.staffapproved;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTaskActionable
              ? AppColors.primary.withValues(alpha: 0.55)
              : const Color(0xFFECEEF1),
          width: isTaskActionable ? 1.4 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tag_rounded,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Task #${task.taskId}',
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Description',
              style: AppTextStyles.sectionLabel,
            ),
            const SizedBox(height: 4),
            Text(
              task.taskTitle,
              style: AppTextStyles.headingSmall,
            ),
            if (task.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.description,
                  style: AppTextStyles.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.trip_origin_rounded,
              color: AppColors.info,
              label: 'Source',
              value: task.sourceLocation?.displayAddress ??
                  'Current location',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.location_on_outlined,
              color: AppColors.error,
              label: 'Destination',
              value: task.destinationLocation?.displayAddress ??
                  (task.customer != null
                      ? '${task.customer!.address}, ${task.customer!.city}, ${task.customer!.pincode}'
                      : '—'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildIconTile(Icons.schedule_rounded, AppColors.brandDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatCompletionDate(task.expectedCompletionDate),
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (task.isOtpRequired)
                  _buildRequirementChip(
                    'OTP',
                    AppColors.infoBg,
                    AppColors.info,
                  ),
                if (task.isGeoFenceRequired)
                  _buildRequirementChip(
                    'Geo',
                    AppColors.successBg,
                    AppColors.success,
                  ),
                if (task.isPhotoRequired)
                  _buildRequirementChip(
                    'Photo',
                    const Color(0xFFEDE9FE),
                    const Color(0xFF7C3AED),
                  ),
                if (task.isFormRequired)
                  _buildRequirementChip(
                    'Form',
                    AppColors.brandLight,
                    AppColors.brandDark,
                  ),
              ],
            ),
            if (task.completedDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Completed: ${DateDisplayUtil.formatDateOnly(task.completedDate!)}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            if (isTaskActionable)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onStartTask,
                  icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                  label: const Text('Start Task'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconTile(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIconTile(icon, color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementChip(
    String label,
    Color backgroundColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
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
