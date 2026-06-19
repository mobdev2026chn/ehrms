import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/constants.dart';
import '../screens/profile/face_enroll_screen.dart';
import '../services/auth_service.dart';

/// Gate that ensures a user has registered their face ONCE before the face check on
/// punch in / punch out / break. If not enrolled, it prompts and opens the enrollment
/// screen; the action only continues after enrollment.
///
/// Fails OPEN: if face matching is disabled, or the status can't be determined
/// (offline/server error), it returns true so attendance is never bricked — the
/// server still validates at verify time.
class FaceEnrollmentGate {
  static final AuthService _auth = AuthService();

  /// Returns true if the user may proceed (already enrolled, just enrolled, gate
  /// disabled, or status undeterminable). Returns false only when enrollment is
  /// required and the user backed out without completing it.
  static Future<bool> ensureEnrolled(
    BuildContext context, {
    String actionLabel = 'punch',
  }) async {
    if (!AppConstants.enableAttendanceFaceMatching) return true;

    final status = await _auth.faceEnrollStatus();
    if (status['ok'] != true) return true; // couldn't determine → don't block
    if (status['enrolled'] == true) return true;
    if (!context.mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register your face'),
        content: Text(
          'Before your first $actionLabel, please register your face once. '
          'Your $actionLabel will be verified against it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Register'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return false;

    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FaceEnrollScreen()),
    );
    return done == true;
  }
}
