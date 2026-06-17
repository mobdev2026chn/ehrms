import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../config/app_colors.dart';
import '../../utils/face_detection_helper.dart';

/// Sentinel returned when camera init fails; caller should use image_picker fallback.
const Object useImagePickerFallback = Object();

/// The front camera (camerawesome) writes pixels rotated 180° while reporting EXIF
/// orientation = 1 on our target devices, so the saved file is upside-down and the
/// EXIF-orientation bake at upload time is a no-op. Bake a 180° rotation into the
/// pixels here, at capture time, so the stored/uploaded image is upright EVERYWHERE
/// (review screen, server, profile avatar, server-side face match) — not just where
/// the app applies a display-time flip. Runs in a background isolate via [compute].
/// Returns the SAME [raw] instance if decoding fails, so the caller can skip a write.
// Crop to the on-screen guide box (widthFactor 0.82 × heightFactor 0.90) so the saved
// selfie is just what was framed — not the full camera frame.
img.Image _cropToFrame(img.Image im) {
  final w = im.width, h = im.height;
  final cw = (w * 0.82).round();
  final ch = (h * 0.90).round();
  final x = ((w - cw) / 2).round();
  final y = ((h - ch) / 2).round();
  return img.copyCrop(im, x: x, y: y, width: cw, height: ch);
}

/// Inverted capture (front camera wrote pixels upside-down): rotate 180° then crop.
Uint8List bakeSelfieUpright180(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    final cropped = _cropToFrame(img.copyRotate(decoded, angle: 180));
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
  } catch (_) {
    return raw;
  }
}

/// Upright capture: crop only (no rotation).
Uint8List cropSelfieOnly(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    final cropped = _cropToFrame(decoded);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
  } catch (_) {
    return raw;
  }
}

/// In-app selfie camera with face-scan overlay UI.
/// Returns [File] on capture, null if cancelled, or [useImagePickerFallback] if init failed.
class SelfieCameraScreen extends StatefulWidget {
  final String? locationText;
  final Future<String?> Function()? onRefreshLocation;
  final String title;
  final bool loadLocationOnOpen;

  /// Optional info line shown as a pill under the status badge (e.g. remaining
  /// break balance). Displayed immediately when provided.
  final String? infoText;

  /// Optional async source for [infoText]; resolves while the camera initializes
  /// and updates the pill when ready (e.g. a fresh break-balance fetch).
  final Future<String?>? infoTextFuture;

  const SelfieCameraScreen({
    super.key,
    this.locationText,
    this.onRefreshLocation,
    this.title = 'Mark Attendance',
    this.loadLocationOnOpen = false,
    this.infoText,
    this.infoTextFuture,
  });

  static Future<Object?> captureSelfie(
    BuildContext context, {
    String? location,
    Future<String?> Function()? onRefreshLocation,
    String title = 'Mark Attendance',
    bool loadLocationOnOpen = false,
    String? infoText,
    Future<String?>? infoTextFuture,
  }) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (context) => SelfieCameraScreen(
          locationText: location,
          onRefreshLocation: onRefreshLocation,
          title: title,
          loadLocationOnOpen: loadLocationOnOpen,
          infoText: infoText,
          infoTextFuture: infoTextFuture,
        ),
      ),
    );
    return result;
  }

  @override
  State<SelfieCameraScreen> createState() => _SelfieCameraScreenState();
}

class _SelfieCameraScreenState extends State<SelfieCameraScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _initTimeout = Duration(seconds: 12);
  Timer? _timeoutTimer;
  bool _showTimeoutOverlay = false;
  String? _locationText;
  bool _isRefreshingLocation = false;
  bool _isHandlingBack = false;
  String? _capturedFilePath;
  CameraState? _cameraState;
  String? _infoText;

  @override
  void initState() {
    super.initState();
    _locationText = widget.locationText;
    _infoText = widget.infoText;
    if (widget.loadLocationOnOpen && widget.onRefreshLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLocation());
    }
    // Resolve the live info text (e.g. break balance) without blocking camera init.
    widget.infoTextFuture?.then((value) {
      if (mounted && value != null && value.trim().isNotEmpty) {
        setState(() => _infoText = value);
      }
    });
    _timeoutTimer = Timer(_initTimeout, () {
      // Timeout overlay disabled; code kept for future use.
    });
  }

  Future<void> _refreshLocation() async {
    final callback = widget.onRefreshLocation;
    if (callback == null || _isRefreshingLocation) return;
    setState(() => _isRefreshingLocation = true);
    try {
      final updated = await callback();
      if (mounted && updated != null) setState(() => _locationText = updated);
    } finally {
      if (mounted) setState(() => _isRefreshingLocation = false);
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _useSystemCamera() => Navigator.of(context).pop(useImagePickerFallback);

  void _handleBackPressed() {
    if (_isHandlingBack || !mounted) return;
    if (_capturedFilePath != null) {
      setState(() => _capturedFilePath = null);
      return;
    }
    _isHandlingBack = true;
    Navigator.of(context).pop();
  }

  void _retry() {
    setState(() => _showTimeoutOverlay = false);
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_initTimeout, () {
      if (mounted) setState(() => _showTimeoutOverlay = true);
    });
  }

  /// Auto-detect orientation and crop the captured selfie, then show the review
  /// screen. ML Kit runs on the as-captured file: if it finds NO face the front
  /// camera wrote the pixels upside-down, so rotate 180°; otherwise keep upright.
  /// Either way crop to the guide box. Heavy work runs off the UI isolate; on
  /// failure the original file is kept.
  Future<void> _finalizeCapture(String path) async {
    try {
      final file = File(path);
      bool inverted = false;
      try {
        final det = await FaceDetectionHelper.detectFromFile(file);
        // No face as-captured ⇒ image is upside-down for this device.
        inverted = det.faceCount == 0;
      } catch (_) {
        // If detection fails, assume upright (crop only).
      }
      final raw = await file.readAsBytes();
      final processed =
          await compute(inverted ? bakeSelfieUpright180 : cropSelfieOnly, raw);
      if (!identical(processed, raw)) {
        await file.writeAsBytes(processed, flush: true);
      }
    } catch (_) {
      // Keep the original capture if processing fails.
    }
    if (mounted) setState(() => _capturedFilePath = path);
  }

  void _takePhoto() {
    _cameraState?.when(
      onPhotoMode: (photoState) => photoState.takePhoto(),
      onPreparingCamera: (_) {},
      onVideoMode: (_) {},
      onVideoRecordingMode: (_) {},
      onPreviewMode: (_) {},
      onAnalysisOnlyMode: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
        // Review screen is light (per Figma); camera stays black.
        backgroundColor: _capturedFilePath != null
            ? AppColors.background
            : Colors.black,
        appBar: _capturedFilePath != null
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                leading: Center(
                  child: GestureDetector(
                    onTap: _handleBackPressed,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
        body: _capturedFilePath != null
            ? _buildPreviewBody()
            : Stack(
                fit: StackFit.expand,
                children: [
                  CameraAwesomeBuilder.awesome(
                    topActionsBuilder: (_) => const SizedBox.shrink(),
                    bottomActionsBuilder: (state) {
                      _cameraState = state;
                      return const SizedBox.shrink();
                    },
                    progressIndicator: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.orange),
                          SizedBox(height: 16),
                          Text(
                            'Opening camera…',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    saveConfig: SaveConfig.photo(
                      pathBuilder: (sensors) async {
                        final dir = await getTemporaryDirectory();
                        final path =
                            '${dir.path}/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
                        return SingleCaptureRequest(path, sensors.first);
                      },
                      mirrorFrontCamera: true,
                    ),
                    sensorConfig: SensorConfig.single(
                      sensor: Sensor.position(SensorPosition.front),
                      aspectRatio: CameraAspectRatios.ratio_4_3,
                    ),
                    // `contain` keeps the full sensor frame centered, so the
                    // subject the user lines up in the oval is exactly what gets
                    // captured. `cover` over-scales the front 4:3 frame and
                    // anchors the crop off-center, pushing the face to a corner.
                    previewFit: CameraPreviewFit.contain,
                    previewAlignment: Alignment.center,
                    availableFilters: const [],
                    onMediaCaptureEvent: (MediaCapture event) {
                      if (event.status == MediaCaptureStatus.success &&
                          event.isPicture &&
                          !event.isVideo) {
                        event.captureRequest.when(
                          single: (single) {
                            final path = single.file?.path;
                            if (path != null && context.mounted) {
                              _finalizeCapture(path);
                            }
                          },
                          multiple: (_) {},
                        );
                      }
                    },
                  ),
                  _buildCameraOverlay(),
                  if (_showTimeoutOverlay) _buildTimeoutOverlay(),
                ],
              ),
      ),
    );
  }

  // ── Camera overlay: badge + scan frame + capture button ───────────────────

  Widget _buildCameraOverlay() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Center(child: _buildStatusBadge()),
        if (_infoText != null && _infoText!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(child: _buildInfoPill(_infoText!)),
        ],
        Expanded(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.82,
              heightFactor: 0.90,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _ScanFramePainter()),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: CustomPaint(painter: _FaceOutlinePainter()),
                  ),
                  // Capture mode: no scan-line animation — the user positions their
                  // face and taps the shutter to capture.
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: _buildCaptureButton(),
        ),
      ],
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.60),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'TAP TO CAPTURE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.coffee_rounded, color: Colors.white, size: 14),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _takePhoto,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  // ── Preview (after capture) ───────────────────────────────────────────────

  Widget _buildPreviewBody() {
    final path = _capturedFilePath!;
    final timeStr = TimeOfDay.now().format(context);
    final location = _locationText;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            // Captured selfie with time + location overlays (Figma "Review").
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(path), fit: BoxFit.cover),
                    // FACE MATCHED badge (top-left) — per Figma.
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'FACE MATCHED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Time badge (top-right) — light pill per Figma.
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          timeStr,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (location != null && location.trim().isNotEmpty)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'CURRENT LOCATION',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                        color: AppColors.textCaption,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
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
            const SizedBox(height: 18),
            Text(
              'Review your selfie',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ensure your face is clearly visible and well-lit.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _capturedFilePath = null),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Retake'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      backgroundColor: AppColors.inputFill,
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(File(path)),
                    icon: const Icon(Icons.check),
                    label: const Text('Submit Punch'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Timeout overlay ───────────────────────────────────────────────────────

  Widget _buildTimeoutOverlay() {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 48,
                  color: Colors.white54,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Camera is taking too long',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can use your device camera instead to take the selfie.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(onPressed: _retry, child: const Text('Retry')),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: _useSystemCamera,
                      child: const Text('Use system camera'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Custom painters ──────────────────────────────────────────────────────────

/// Draws corner-bracket markers and a dashed border for the face scan frame.
class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cl = 28; // corner arm length
    const double sw = 2.5;

    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = sw
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawLine(const Offset(0, cl), Offset.zero, cornerPaint);
    canvas.drawLine(Offset.zero, const Offset(cl, 0), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(w - cl, 0), Offset(w, 0), cornerPaint);
    canvas.drawLine(Offset(w, 0), Offset(w, cl), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - cl), Offset(0, h), cornerPaint);
    canvas.drawLine(Offset(0, h), Offset(cl, h), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(w - cl, h), Offset(w, h), cornerPaint);
    canvas.drawLine(Offset(w, h), Offset(w, h - cl), cornerPaint);

    // Dashed border
    final dashPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    _dashedLine(canvas, Offset.zero, Offset(w, 0), dashPaint);
    _dashedLine(canvas, Offset(w, 0), Offset(w, h), dashPaint);
    _dashedLine(canvas, Offset(w, h), Offset(0, h), dashPaint);
    _dashedLine(canvas, Offset(0, h), Offset.zero, dashPaint);
  }

  void _dashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const double dash = 8;
    const double gap = 7;
    final bool horiz = (end.dy - start.dy).abs() < 1.0;
    final double total = horiz
        ? (end.dx - start.dx).abs()
        : (end.dy - start.dy).abs();
    final double sign = horiz
        ? (end.dx >= start.dx ? 1.0 : -1.0)
        : (end.dy >= start.dy ? 1.0 : -1.0);
    var drawn = 0.0;
    while (drawn < total) {
      final segEnd = (drawn + dash).clamp(0.0, total);
      if (horiz) {
        canvas.drawLine(
          Offset(start.dx + sign * drawn, start.dy),
          Offset(start.dx + sign * segEnd, start.dy),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(start.dx, start.dy + sign * drawn),
          Offset(start.dx, start.dy + sign * segEnd),
          paint,
        );
      }
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Clean face-capture guide: a minimal head-and-shoulders silhouette outline
/// (no facial features) used to align the subject — the professional look used
/// in KYC / ID photo apps.
class _FaceOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Soft halo behind the guide for contrast against any background.
    final glowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // === HEAD (clean portrait oval) ===
    final headCY = h * 0.32;
    final headRX = w * 0.265;
    final headRY = h * 0.235;
    final headRect = Rect.fromCenter(
      center: Offset(cx, headCY),
      width: headRX * 2,
      height: headRY * 2,
    );

    // === SHOULDERS / bust (top half of a wide ellipse near the bottom) ===
    final bustRect = Rect.fromCenter(
      center: Offset(cx, h * 0.98),
      width: w * 0.92,
      height: h * 0.66,
    );

    for (final p in [glowPaint, paint]) {
      canvas.drawOval(headRect, p);
      // Top half dome → shoulders rising toward the neck.
      canvas.drawArc(bustRect, -math.pi, math.pi, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
