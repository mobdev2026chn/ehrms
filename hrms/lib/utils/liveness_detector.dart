import 'package:camerawesome/camerawesome_plugin.dart';
// google_mlkit_face_detection re-exports google_mlkit_commons (InputImage,
// InputImageMetadata, InputImageFormat, InputImageRotation), so one import covers both.
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Active-liveness check: confirms a *live* person is in front of the camera by
/// requiring a natural blink (eyes open → closed → open). A printed photo or a
/// static image on a phone screen cannot blink, so this defeats the most common
/// presentation-attack (held-up photo) without any extra hardware.
///
/// Feed live preview frames in via [processFrame]; read [blinkDetected].
/// Fail-open safety net: if frames are flowing but classification never yields
/// eye probabilities, the caller can decide to degrade gracefully (see
/// [framesProcessed]).
class LivenessDetector {
  LivenessDetector();

  // ML Kit detector WITH classification so we get eye-open probabilities.
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableClassification: true,
      enableTracking: false,
      minFaceSize: 0.15,
    ),
  );

  // Eye-open thresholds for the open→closed→open transition.
  static const double _openThreshold = 0.55;
  static const double _closedThreshold = 0.25;

  bool _eyesWereOpen = false;
  bool _sawClosed = false;

  /// True once a full blink has been observed. Latches until [reset].
  bool blinkDetected = false;

  /// How many frames ML Kit successfully ran on (regardless of result). Lets the
  /// UI tell "pipeline not working" (0) from "working but no blink yet" (>0).
  int framesProcessed = 0;

  bool _busy = false;

  /// Process one live preview frame. Safe to call on every analysis frame —
  /// frames are dropped while a previous one is still being processed.
  Future<void> processFrame(AnalysisImage image) async {
    if (_busy || blinkDetected) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      framesProcessed++;
      if (faces.isEmpty) return;
      final face = faces.first;
      final left = face.leftEyeOpenProbability;
      final right = face.rightEyeOpenProbability;
      if (left == null || right == null) return;
      final avg = (left + right) / 2.0;
      _advance(avg);
    } catch (_) {
      // Ignore a bad frame; the next one will retry.
    } finally {
      _busy = false;
    }
  }

  /// Drive the open → closed → open state machine from an averaged eye-open prob.
  void _advance(double eyeOpenProb) {
    if (eyeOpenProb >= _openThreshold) {
      if (_eyesWereOpen && _sawClosed) {
        // open → closed → open completed = one blink.
        blinkDetected = true;
        return;
      }
      _eyesWereOpen = true;
    } else if (eyeOpenProb <= _closedThreshold) {
      if (_eyesWereOpen) _sawClosed = true;
    }
  }

  /// Clear state so a fresh blink is required (e.g. on retake).
  void reset() {
    _eyesWereOpen = false;
    _sawClosed = false;
    blinkDetected = false;
    framesProcessed = 0;
  }

  Future<void> dispose() async {
    await _detector.close();
  }

  // ── camerawesome AnalysisImage → ML Kit InputImage ────────────────────────
  // Android delivers NV21, iOS delivers BGRA8888. Mirrors camerawesome's own
  // ML Kit example; other formats are not used by the face analysis config.
  InputImage? _toInputImage(AnalysisImage image) {
    return image.when(
      nv21: (Nv21Image nv21) {
        return InputImage.fromBytes(
          bytes: nv21.bytes,
          metadata: InputImageMetadata(
            rotation: _rotation(nv21.rotation),
            format: InputImageFormat.nv21,
            size: nv21.size,
            bytesPerRow: nv21.planes.first.bytesPerRow,
          ),
        );
      },
      bgra8888: (Bgra8888Image bgra) {
        return InputImage.fromBytes(
          bytes: bgra.bytes,
          metadata: InputImageMetadata(
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.bgra8888,
            size: bgra.size,
            bytesPerRow: bgra.planes.first.bytesPerRow,
          ),
        );
      },
    );
  }

  InputImageRotation _rotation(InputAnalysisImageRotation r) {
    switch (r) {
      case InputAnalysisImageRotation.rotation0deg:
        return InputImageRotation.rotation0deg;
      case InputAnalysisImageRotation.rotation90deg:
        return InputImageRotation.rotation90deg;
      case InputAnalysisImageRotation.rotation180deg:
        return InputImageRotation.rotation180deg;
      case InputAnalysisImageRotation.rotation270deg:
        return InputImageRotation.rotation270deg;
    }
  }
}
