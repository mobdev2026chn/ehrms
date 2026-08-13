// Placeholder screen after "Arrived" – shows Next Steps (logic to be implemented later).
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/services/presence_tracking_service.dart';
import 'package:hrms/screens/geo/end_task_screen.dart';
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text(
          'Next Steps',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_rounded, color: AppColors.primary),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.person_rounded, color: AppColors.primary),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Complete these requirements to finish the task:',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              _stepRow(
                icon: Icons.location_on_rounded,
                label: 'Reached location',
                done: true,
              ),
              _stepRow(
                icon: Icons.camera_alt_rounded,
                label: 'Take photo proof',
                done: false,
              ),
              _stepRow(
                icon: Icons.description_rounded,
                label: 'Fill required form',
                done: false,
              ),
              _stepRow(
                icon: Icons.pin_rounded,
                label: 'Get OTP from customer',
                done: false,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _completeTask(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Complete Task',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
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
    );
  }
}
