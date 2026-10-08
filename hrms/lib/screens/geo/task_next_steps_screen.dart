// Placeholder screen after "Arrived" – shows Next Steps (logic to be implemented later).
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/services/presence_tracking_service.dart';
import 'package:hrms/screens/geo/end_task_screen.dart';
import 'package:hrms/widgets/app_card.dart';
import 'package:hrms/widgets/menu_icon_button.dart';

class TaskNextStepsScreen extends StatelessWidget {
  final String? taskMongoId;

  const TaskNextStepsScreen({super.key, this.taskMongoId});

  Future<void> _completeTask(BuildContext context) async {
    if (taskMongoId != null && taskMongoId!.isNotEmpty) {
      try {
        await TaskService().endTask(taskMongoId!);
        await PresenceTrackingService().resumePresenceTracking();
      } catch (_) {}
    }
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const EndTaskScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('Next Steps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Profile',
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Complete these requirements to finish the task:',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                border: Border.all(color: const Color(0xFFECEEF1)),
                child: Column(
                  children: [
                    _stepRow(
                      icon: Icons.location_on_rounded,
                      label: 'Reached location',
                      done: true,
                    ),
                    const Divider(height: 1, indent: 68),
                    _stepRow(
                      icon: Icons.camera_alt_rounded,
                      label: 'Take photo proof',
                      done: false,
                    ),
                    const Divider(height: 1, indent: 68),
                    _stepRow(
                      icon: Icons.description_rounded,
                      label: 'Fill required form',
                      done: false,
                    ),
                    const Divider(height: 1, indent: 68),
                    _stepRow(
                      icon: Icons.pin_rounded,
                      label: 'Get OTP from customer',
                      done: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _completeTask(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error, width: 1.2),
                  ),
                  child: const Text('Complete Task'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepRow({
    required IconData icon,
    required String label,
    required bool done,
  }) {
    final Color tint = done ? AppColors.success : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
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
                color: done ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
