import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/auth_service.dart';
import '../../utils/attendance_selfie_compress.dart';
import '../../utils/snackbar_utils.dart';
import '../attendance/selfie_camera_screen.dart';

/// Single-click face enrollment (like the face app's older flow): open the camera,
/// capture ONE selfie, and it's registered immediately. That selfie also becomes the
/// user's profile photo, and every future punch matches against it.
class FaceEnrollScreen extends StatefulWidget {
  const FaceEnrollScreen({super.key});

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  final AuthService _authService = AuthService();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Single click: launch the camera as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureAndEnroll());
  }

  Future<void> _captureAndEnroll() async {
    if (_busy) return;
    final result = await SelfieCameraScreen.captureSelfie(
      context,
      title: 'Register Face',
      // Enrollment only: accept a clear photo without the strict eyes-open /
      // frontal-yaw gate and with wider framing tolerance. Punch/break stay strict.
      enrollMode: true,
    );
    if (!mounted) return;
    if (result is! File) {
      // User backed out of the camera without capturing.
      setState(() => _error = 'Capture cancelled. Tap below to register your face.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await result.readAsBytes();
      final dataUrl =
          await AttendanceSelfieCompress.compressRawBytesToDataUrl(bytes);
      final res = await _authService.enrollFace([dataUrl]);
      if (!mounted) return;
      final ok = res['success'] == true;
      SnackBarUtils.showSnackBar(
        context,
        res['message']?.toString() ??
            (ok ? 'Face registered.' : 'Registration failed.'),
        isError: !ok,
      );
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _error = res['message']?.toString() ?? 'Registration failed. Try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Registration failed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Register Your Face')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.face_retouching_natural,
                    size: 72, color: AppColors.primary),
                const SizedBox(height: 20),
                Text(
                  _busy ? 'Registering your face…' : 'Register your face',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Line your face up inside the oval guide in good light — it '
                  'captures automatically. This becomes your profile photo and the '
                  'face every future punch is verified against.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                  ),
                ],
                const SizedBox(height: 28),
                if (_busy)
                  const CircularProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _captureAndEnroll,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(_error == null
                          ? 'Capture & Register'
                          : 'Try Again'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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
}
