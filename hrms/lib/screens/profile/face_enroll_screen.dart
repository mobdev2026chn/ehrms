import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/auth_service.dart';
import '../../utils/attendance_selfie_compress.dart';
import '../attendance/selfie_camera_screen.dart';

/// One-time face enrollment. The user captures a few selfie samples (via the same
/// capture-button camera used for punches, so the on-device quality gate applies),
/// and they are sent to `/auth/enroll-face`. Every future punch then matches against
/// these FIXED enrolled samples — the reliable path (same approach as the face app).
class FaceEnrollScreen extends StatefulWidget {
  const FaceEnrollScreen({super.key});

  /// Recommended number of samples (more samples = more robust matching).
  static const int targetSamples = 3;

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  final AuthService _authService = AuthService();
  final List<File> _samples = [];
  bool _submitting = false;

  Future<void> _captureSample() async {
    if (_samples.length >= FaceEnrollScreen.targetSamples) return;
    final result = await SelfieCameraScreen.captureSelfie(
      context,
      title: 'Register Face',
    );
    if (!mounted) return;
    if (result is File) {
      setState(() => _samples.add(result));
    }
  }

  Future<void> _submit() async {
    if (_samples.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      // Compress each sample to a data URL off the UI isolate.
      final payloads = <String>[];
      for (final f in _samples) {
        final bytes = await f.readAsBytes();
        payloads.add(
          await AttendanceSelfieCompress.compressRawBytesToDataUrl(bytes),
        );
      }
      final res = await _authService.enrollFace(payloads);
      if (!mounted) return;
      final ok = res['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ??
              (ok ? 'Face enrolled.' : 'Enrollment failed.')),
          backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (ok) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final captured = _samples.length;
    final canSubmit = captured > 0 && !_submitting;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Register Your Face')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Register your face once',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Capture ${FaceEnrollScreen.targetSamples} clear selfies in good light. '
                'Your punches will be matched against these.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              // Sample slots
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(FaceEnrollScreen.targetSamples, (i) {
                  final has = i < _samples.length;
                  return Container(
                    width: 88,
                    height: 110,
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: has ? AppColors.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: has
                        ? Image.file(_samples[i], fit: BoxFit.cover)
                        : Icon(Icons.person_outline,
                            color: AppColors.textCaption, size: 34),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Text(
                '$captured / ${FaceEnrollScreen.targetSamples} captured',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: captured >= FaceEnrollScreen.targetSamples || _submitting
                    ? null
                    : _captureSample,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(captured == 0 ? 'Capture Face Sample' : 'Capture Another'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enroll Face'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
