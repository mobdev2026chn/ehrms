import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../config/app_colors.dart';
import '../../utils/face_detection_helper.dart';
import '../../widgets/face_guide_overlay.dart';
import '../../utils/snackbar_utils.dart';

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

/// Crop the (already downscaled + correctly-rotated) selfie to the guide frame.
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

/// Rotate 180° (deterministic raw-pixel flip) then crop — for captures the front
/// camera writes upside-down. Done in the Dart image package so it doesn't depend
/// on EXIF or the native rotate semantics.
Uint8List rotate180AndCrop(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    final cropped = _cropToFrame(img.copyRotate(decoded, angle: 180));
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
  } catch (_) {
    return raw;
  }
}

/// Pure 180° flip (no crop) — used by the manual "Rotate" button on the review
/// screen when auto-orientation guessed wrong.
Uint8List flip180Only(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    return Uint8List.fromList(
        img.encodeJpg(img.copyRotate(decoded, angle: 180), quality: 92));
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

  /// Optional post-capture validator. Runs on the captured file RIGHT AFTER the
  /// scan (before the review screen) — used by punch/break to do the face-match +
  /// buddy-punch identity check at scan time. Return an error message to REJECT
  /// (it's shown on the camera and the live scan re-arms), or null to accept.
  final Future<String?> Function(File capturedFile)? onCaptured;

  /// Relaxed capture mode for face ENROLLMENT. When true the click-time quality
  /// gate keeps only the single-face guard (drops eyes-open + frontal-yaw) and the
  /// live-scan proximity/centering thresholds widen so a clear, well-lit photo
  /// auto-captures easily. Punch/break leave this false, so their strict scan and
  /// gate are completely unaffected.
  final bool enrollMode;

  const SelfieCameraScreen({
    super.key,
    this.locationText,
    this.onRefreshLocation,
    this.title = 'Mark Attendance',
    this.loadLocationOnOpen = false,
    this.infoText,
    this.infoTextFuture,
    this.onCaptured,
    this.enrollMode = false,
  });

  static Future<Object?> captureSelfie(
    BuildContext context, {
    String? location,
    Future<String?> Function()? onRefreshLocation,
    String title = 'Mark Attendance',
    bool loadLocationOnOpen = false,
    String? infoText,
    Future<String?>? infoTextFuture,
    Future<String?> Function(File capturedFile)? onCaptured,
    bool enrollMode = false,
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
          onCaptured: onCaptured,
          enrollMode: enrollMode,
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
  // Live face count from the camera stream (-1 = not yet analysed). Drives the
  // on-frame "Multiple faces" warning and gates the shutter so the validation
  // shows WHILE framing — before capture/submit.
  int _liveFaceCount = -1;
  bool _analyzingFrame = false;
  // Bumped after a manual rotate so the review Image rebuilds from disk (FileImage
  // caches by path, and the path is unchanged after we overwrite the bytes).
  int _reviewRev = 0;
  bool _rotatingReview = false;

  // ── Guided-scan state (new-app FaceGuideOverlay UX) ──────────────────────────
  // The oval ring + guidance text are driven live by on-device ML Kit geometry
  // (single-face + centering + proximity). When a good face holds for a couple of
  // frames we auto-capture; the manual shutter remains as a fallback. The captured
  // selfie still goes through the existing verify/submit flow unchanged.
  Color _ovalColor = AppColors.primary;
  String _guidanceText = 'Align Face Inside Guide';
  bool _faceReady = false;
  int _goodFrames = 0;
  bool _capturing = false;
  // True while the post-capture validator (onCaptured: face-match + identity guard)
  // is running, so we can show a "Verifying…" overlay between scan and review.
  bool _validating = false;

  // Guidance thresholds (ratios of the rotation-corrected frame). Generous, since
  // a handheld selfie fills more of the frame than a fixed kiosk; the authoritative
  // guards + anti-spoof still run server-side in embedLive at verify/enroll time.
  // Enrollment widens them further (and auto-captures after a single good frame) so
  // a clear photo is accepted without fussy alignment — punch/break keep the tighter
  // base values via [widget.enrollMode] == false.
  double get _kFaceTooFar => widget.enrollMode ? 0.12 : 0.18;
  double get _kFaceTooClose => widget.enrollMode ? 0.85 : 0.66;
  double get _kCenterTolX => widget.enrollMode ? 0.34 : 0.22;
  double get _kCenterTolY => widget.enrollMode ? 0.36 : 0.24;
  int get _kGoodFramesToCapture => widget.enrollMode ? 1 : 2;

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
      // Retake from the review screen — re-arm the guided live scan.
      setState(() {
        _capturedFilePath = null;
        _resetLiveScan();
      });
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
  ///
  /// The same ML Kit pass gates the capture: if more than one face is present we
  /// surface the validation message right here and return to the live camera for
  /// a retake — so the user never reaches the Submit Punch button with an invalid
  /// selfie (previously the multi-face error only appeared after submitting).
  Future<void> _finalizeCapture(String path) async {
    String? validationError;
    try {
      final file = File(path);

      // Downscale NATIVELY (fast) — avoids decoding the full-res JPEG in Dart
      // (~1-2s). Keep EXIF auto-correction (default) so the small image matches
      // what ML Kit saw. All orientation probing + the deterministic 180° flip
      // run on this small image, so no reliance on native rotate semantics.
      final small = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: 1280,
        minHeight: 1280,
        quality: 90,
      );
      final working = (small != null && small.isNotEmpty)
          ? small
          : await file.readAsBytes();

      // Two-pass orientation resolution. A single ML Kit pass is unreliable: this
      // device writes the front camera upside-down, and ML Kit may either fail to
      // detect the inverted face OR detect it while normalizing the roll angle
      // back toward 0° — both of which made the old roll-only test keep the photo
      // upside-down (→ server face-match then fails). Instead, detect the image
      // AS-IS and ROTATED 180°, and keep whichever orientation yields an actually
      // upright face (eyes above mouth, via landmark geometry in the detector).
      bool inverted = false;
      // The detection taken on the orientation we actually SAVE — drives both the
      // flip decision and the click-time quality gate below.
      FaceDetectionResult? chosen;
      try {
        final asis = await FaceDetectionHelper.detectFromBytes(working);
        if (asis.faceCount > 0 && !asis.isUpsideDown) {
          // As-captured already shows an upright face → no flip needed.
          inverted = false;
          chosen = asis;
        } else {
          final rotated = await compute(flip180Only, working);
          final flipped = await FaceDetectionHelper.detectFromBytes(rotated);
          if (flipped.faceCount > 0 && !flipped.isUpsideDown) {
            // Rotating 180° produced an upright face → the capture was flipped.
            inverted = true;
            chosen = flipped;
          } else if (asis.faceCount > 0 && asis.isUpsideDown) {
            // Geometry already said the as-is face is upside-down; trust it.
            inverted = true;
            chosen = asis;
          } else {
            // No clearly-upright face either way. This device captures flipped,
            // so default to inverted; the manual "Flip" button is the safety net.
            inverted = true;
            chosen = flipped.faceCount > 0 ? flipped : asis;
          }
        }
        debugPrint('[Selfie][orient] asisFaces=${asis.faceCount} '
            'asisUpsideDown=${asis.isUpsideDown} inverted=$inverted '
            'faceCount=${chosen.faceCount} eyesOpen=${chosen.eyesOpen} '
            'yaw=${chosen.headYaw?.toStringAsFixed(1)}');
      } catch (_) {
        // If detection fails entirely, assume upright (crop only).
      }

      final processed =
          await compute(inverted ? rotate180AndCrop : cropSelfieOnly, working);
      await file.writeAsBytes(processed, flush: true);

      // Click-time selfie-quality gate (image validation, NOT identity matching):
      // exactly one face, eyes open, facing the camera. On failure we bounce back
      // to the live camera so the user can retake. Skipped when detection failed
      // entirely (chosen == null) so a detector hiccup never hard-blocks a punch.
      // Enrollment relaxes the gate to single-face-only so a clear photo is accepted.
      validationError = chosen?.qualityIssue(relaxed: widget.enrollMode);
    } catch (_) {
      // Keep the original capture if processing fails.
    }
    if (!mounted) return;
    if (validationError != null) {
      _showCaptureError(validationError);
      // Discard this capture; stay on the live camera so the user can retake.
      // Re-arm the guided scan so auto-capture can fire again on the next good face.
      setState(() {
        _capturedFilePath = null;
        _resetLiveScan();
      });
      return;
    }

    // Post-capture validator (punch/break face-match + buddy-punch identity guard).
    // Runs RIGHT AFTER the scan, BEFORE the review screen — so a wrong/other face is
    // rejected here (error shown on camera + scan re-armed), not after submitting.
    final validator = widget.onCaptured;
    if (validator != null) {
      setState(() => _validating = true);
      String? hookError;
      try {
        hookError = await validator(File(path));
      } catch (_) {
        hookError = 'Could not verify your face. Please try again.';
      }
      if (!mounted) return;
      setState(() => _validating = false);
      if (hookError != null) {
        _showCaptureError(hookError);
        setState(() {
          _capturedFilePath = null;
          _resetLiveScan();
        });
        return;
      }
    }
    setState(() => _capturedFilePath = path);
  }

  /// Manual 180° flip from the review screen — the guaranteed fix when the
  /// auto-orientation guessed wrong. Rotates the captured file in place and
  /// rebuilds the preview from disk.
  Future<void> _rotateReview() async {
    final path = _capturedFilePath;
    if (path == null || _rotatingReview) return;
    setState(() => _rotatingReview = true);
    try {
      final raw = await File(path).readAsBytes();
      final flipped = await compute(flip180Only, raw);
      await File(path).writeAsBytes(flipped, flush: true);
      await FileImage(File(path)).evict(); // drop the cached (old-orientation) image
    } catch (_) {
      // Keep the current image if the flip fails.
    }
    if (mounted) {
      setState(() {
        _rotatingReview = false;
        _reviewRev++;
      });
    }
  }

  /// Shows a transient validation error over the live camera (e.g. multiple
  /// faces) without leaving the capture screen.
  void _showCaptureError(String message) {
    if (!mounted) return;
    SnackBarUtils.showSnackBar(
      context,
      message,
      isError: true,
      duration: const Duration(seconds: 3),
    );
  }

  bool get _multipleFacesLive => _liveFaceCount > 1;

  /// Analyses live camera frames with ML Kit (one in-flight at a time) to drive the
  /// new-app guided UX: it updates the oval color + guidance text from the primary
  /// face's centering/proximity/count WHILE the user frames the shot, and once a
  /// well-framed single face holds for a couple of frames it AUTO-CAPTURES. The
  /// multiple-face warning still appears here too. Guidance strings mirror the face
  /// app's scanner (_applyErrorGuidance).
  Future<void> _analyzeLiveFrame(AnalysisImage image) async {
    if (_analyzingFrame || !mounted || _capturedFilePath != null || _capturing) {
      return;
    }
    _analyzingFrame = true;
    try {
      final face = await FaceDetectionHelper.detectPrimaryFaceFromCamera(image);
      if (face == null || !mounted) return; // unanalysable frame — ignore it

      String guidance;
      Color color;
      var ready = false;
      if (face.count == 0) {
        guidance = 'Align Face Inside Guide';
        color = AppColors.primary;
      } else if (face.count > 1) {
        guidance = 'Ensure Only 1 Face Visible';
        color = AppColors.error;
      } else if (face.sizeRatio < _kFaceTooFar) {
        guidance = 'Come Closer';
        color = AppColors.error;
      } else if (face.sizeRatio > _kFaceTooClose) {
        guidance = 'Move Back a Little';
        color = AppColors.error;
      } else if ((face.centerX - 0.5).abs() > _kCenterTolX ||
          (face.centerY - 0.5).abs() > _kCenterTolY) {
        guidance = 'Center Your Face';
        color = AppColors.error;
      } else {
        guidance = 'Hold Still…';
        color = AppColors.success;
        ready = true;
      }

      _goodFrames = ready ? _goodFrames + 1 : 0;

      if (mounted &&
          (guidance != _guidanceText ||
              color != _ovalColor ||
              ready != _faceReady ||
              face.count != _liveFaceCount)) {
        setState(() {
          _guidanceText = guidance;
          _ovalColor = color;
          _faceReady = ready;
          _liveFaceCount = face.count;
        });
      }

      // Auto-capture once a well-framed single face has held for a couple frames.
      if (ready &&
          _goodFrames >= _kGoodFramesToCapture &&
          !_capturing &&
          _capturedFilePath == null &&
          mounted) {
        _takePhoto();
      }
    } finally {
      _analyzingFrame = false;
    }
  }

  void _takePhoto() {
    if (_capturing || _capturedFilePath != null) return;
    // Block capture while more than one face is in frame — the live warning is
    // already shown; reinforce it if the user taps anyway.
    if (_multipleFacesLive) {
      _showCaptureError(
          'Multiple faces detected. Please take a selfie with only your face in frame.');
      return;
    }
    final state = _cameraState;
    if (state == null) return;
    state.when(
      // Latch _capturing only once the shutter actually fires, so a stuck flag
      // can't permanently block the manual button / auto-capture.
      onPhotoMode: (photoState) {
        setState(() => _capturing = true);
        photoState.takePhoto();
      },
      onPreparingCamera: (_) {},
      onVideoMode: (_) {},
      onVideoRecordingMode: (_) {},
      onPreviewMode: (_) {},
      onAnalysisOnlyMode: (_) {},
    );
  }

  /// Reset the live-scan guidance so auto-capture can re-arm (after a bounce-back
  /// from the quality gate, or when the user retakes from the review screen).
  void _resetLiveScan() {
    _capturing = false;
    _goodFrames = 0;
    _faceReady = false;
    _ovalColor = AppColors.primary;
    _guidanceText = 'Align Face Inside Guide';
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
                    // Live face detection on the camera stream so the
                    // "Multiple faces" validation shows while framing, before
                    // capture. Throttled + downscaled to stay light.
                    imageAnalysisConfig: AnalysisConfig(
                      androidOptions:
                          const AndroidAnalysisOptions.nv21(width: 350),
                      cupertinoOptions:
                          const CupertinoAnalysisOptions.bgra8888(),
                      autoStart: true,
                      maxFramesPerSecond: 4,
                    ),
                    onImageForAnalysis: _analyzeLiveFrame,
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
                  if (_validating) _buildValidatingOverlay(),
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
        Center(child: _buildReadyPill()),
        if (_infoText != null && _infoText!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(child: _buildInfoPill(_infoText!)),
        ],
        const Spacer(),
        // Live, color-coded guidance (mirrors the face app's scanner): green when
        // the face is well-framed, red while it needs adjusting.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _guidanceText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ovalColor,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // The new-app guided oval: ring color tracks framing state; success badge
        // flashes the moment the shot is taken.
        FaceGuideOverlay(color: _ovalColor, showSuccessTick: _capturing),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: _buildCaptureButton(),
        ),
      ],
    );
  }

  // Shown between the auto-capture and the review screen while the onCaptured
  // validator (face-match + identity guard) runs, so the user sees "Verifying…".
  Widget _buildValidatingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Verifying your face…',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadyPill() {
    final warn = _multipleFacesLive;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: warn
            ? Colors.red.shade700.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          warn
              ? const Icon(Icons.error_outline, color: Colors.white, size: 16)
              : Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              warn ? 'Keep only your face in frame' : 'READY TO SCAN',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
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
              color: Colors.black.withValues(alpha: 0.25),
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
              // Dimmed while the shutter is blocked (multiple faces in frame).
              color: _multipleFacesLive
                  ? Colors.grey.shade400
                  : AppColors.primary,
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
                    Image.file(File(path),
                        key: ValueKey(_reviewRev), fit: BoxFit.cover),
                    // Manual flip — guaranteed fix if auto-orientation was wrong.
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Flip if upside down',
                          icon: _rotatingReview
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.screen_rotation,
                                  color: Colors.white, size: 20),
                          onPressed: _rotatingReview ? null : _rotateReview,
                        ),
                      ),
                    ),
                    // Capture-confirmation badge (top-left). The selfie only reaches
                    // this review screen AFTER passing the on-device quality gate
                    // (one face, eyes open, facing camera), so an honest "captured"
                    // status — not the old "FACE MATCHED", which implied an identity
                    // match that no longer runs.
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
                              Icons.check_circle_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'FACE CAPTURED',
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
                    // Retake: re-arm the guided live scan from scratch so it
                    // doesn't resume stuck on the previous scan's frozen state
                    // (green oval / "Hold Still…" / _capturing latched true).
                    onPressed: () => setState(() {
                      _capturedFilePath = null;
                      _resetLiveScan();
                    }),
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
                    label: const Text('Confirm & Submit'),
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
