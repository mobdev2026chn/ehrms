import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../screens/profile/face_enroll_screen.dart';
import '../services/auth_service.dart';

/// Gate that ensures a user has registered their face ONCE before the face check on
/// punch in / punch out / break. If not enrolled, it prompts and opens the enrollment
/// screen; the action only continues after enrollment.
class FaceEnrollmentGate {
  static final AuthService _auth = AuthService();

  /// Returns true if the user may proceed (already enrolled or just enrolled).
  /// Prompts for registration whenever the face is not registered yet.
  static Future<bool> ensureEnrolled(
    BuildContext context, {
    String actionLabel = 'punch in/out',
  }) async {
    final status = await _auth.faceEnrollStatus();
    // If the server confirms the user has already enrolled their face in MongoDB, proceed
    if (status['ok'] == true && status['enrolled'] == true) return true;
    if (!context.mounted) return false;

    // Face is not registered yet -> ask for registration
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.face_retouching_natural, color: AppColors.primary, size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Register Your Face',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'Your face is not registered yet. Please register your face once before $actionLabel so your attendance can be verified.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Register Face'),
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
