import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

/// Result of face detection on an image.
class FaceDetectionResult {
  final bool valid;
  final int faceCount;
  final String? message;

  /// Roll angle (headEulerAngleZ, degrees) of the detected face. ~0 = upright,
  /// ~±180 = upside-down. Null when no face was found. Kept as a fallback signal
  /// for the flip decision when landmark geometry is unavailable.
  final double? rollZ;

  /// Definitive upside-down verdict for the largest detected face. Derived from
  /// landmark GEOMETRY (eyes vs mouth vertical position) when landmarks are
  /// present, falling back to [rollZ]. Null when no face was found.
  ///
  /// Geometry is used in preference to [rollZ] because ML Kit can detect an
  /// upside-down face yet NORMALIZE the reported roll back toward ~0°, which made
  /// the old "abs(rollZ) > 90" test silently miss flipped captures and leave the
  /// saved selfie upside down.
  final bool? upsideDown;

  /// Whether the eyes are open on the largest face, from ML Kit classification
  /// (both eye-open probabilities ≥ 0.4). Null when classification produced no
  /// estimate. A cheap liveness-lite signal: rejects closed-eye shots and many
  /// printed/screen photos.
  final bool? eyesOpen;

  /// Head yaw (headEulerAngleY, degrees) of the largest face. ~0 = facing the
  /// camera; large magnitude = turned away. Null when no face was found.
  final double? headYaw;

  const FaceDetectionResult({
    required this.valid,
    required this.faceCount,
    this.message,
    this.rollZ,
    this.upsideDown,
    this.eyesOpen,
    this.headYaw,
  });

  /// True when a face is present and clearly upside-down.
  bool get isUpsideDown => upsideDown ?? false;

  /// Click-time selfie-quality verdict (used when the user taps Capture). Returns
  /// a user-facing reason the shot is NOT acceptable, or null when it passes. This
  /// is image validation only — NOT identity matching — so it never depends on a
  /// stored reference and can't lock anyone out.
  ///
  /// [relaxed] is used by face ENROLLMENT only: it keeps the single-face guard but
  /// drops the eyes-open (liveness-lite) and frontal-yaw checks so a clear, well-lit
  /// enrollment photo is accepted even if the person blinked or sits slightly off
  /// straight. Punch/break leave [relaxed] false, so their strict gate is unchanged.
  String? qualityIssue({bool relaxed = false}) {
    if (faceCount == 0) {
      return 'No face detected. Center your face in the circle and try again.';
    }
    if (faceCount > 1) {
      return 'Multiple faces detected. Keep only your face in frame.';
    }
    if (relaxed) return null;
    if (eyesOpen == false) {
      return 'Keep your eyes open and look at the camera.';
    }
    if (headYaw != null && headYaw!.abs() > 30) {
      return 'Look straight at the camera and try again.';
    }
    return null;
  }
}

/// Live primary-face geometry from a camera frame, for the guided-capture overlay.
/// All values are ratios of the rotation-corrected frame (0..1).
class LivePrimaryFace {
  /// Total faces detected in the frame.
  final int count;

  /// Largest face's size as sqrt(area ratio) — ~linear scale of how big the face
  /// is in frame. 0 when no face / unknown.
  final double sizeRatio;

  /// Largest face's bounding-box center, as a fraction of the frame (0.5 = centered).
  final double centerX;
  final double centerY;

  const LivePrimaryFace({
    required this.count,
    this.sizeRatio = 0,
    this.centerX = 0.5,
    this.centerY = 0.5,
  });
}

/// Helper for on-device face detection using ML Kit.
/// Use [detectFromFile] to validate that an image contains exactly one face.
class FaceDetectionHelper {
  static FaceDetector? _detector;

  static FaceDetector get _getDetector {
    _detector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
        // Landmarks give a rotation-robust upside-down test (eyes vs mouth Y),
        // which the roll angle alone can't provide. Only the still-image gate
        // uses this detector (once per capture), so the extra cost is fine.
        enableLandmarks: true,
        enableContours: false,
        // Classification gives eye-open probabilities for the click-time quality
        // gate (liveness-lite). Only the still-image capture check uses this
        // detector, so the extra cost is paid once per tap.
        enableClassification: true,
        enableTracking: false,
      ),
    );
    return _detector!;
  }

  /// Decides whether [face] is upside-down. Prefers landmark geometry — for an
  /// upright face the eyes sit ABOVE (smaller y) the mouth; flipped, they sit
  /// below. This is immune to ML Kit normalizing the reported roll angle toward
  /// ~0° on a genuinely inverted face. Falls back to the roll angle only when
  /// the eye/mouth landmarks aren't both available.
  static bool _isFaceUpsideDown(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final mouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position ??
        face.landmarks[FaceLandmarkType.noseBase]?.position;
    final eyes = [leftEye, rightEye].whereType<math.Point<int>>().toList();
    if (eyes.isNotEmpty && mouth != null) {
      final eyeY = eyes.map((p) => p.y).reduce((a, b) => a + b) / eyes.length;
      return eyeY > mouth.y;
    }
    final roll = face.headEulerAngleZ;
    return roll != null && roll.abs() > 90;
  }

  /// Eye-open verdict from ML Kit classification. Returns null when neither eye
  /// produced a probability (classification unavailable for this face), so the
  /// quality gate can skip the check rather than wrongly reject. Accepts when
  /// EITHER eye reads clearly open (≥ 0.4) to tolerate squints/asymmetric light.
  static bool? _areEyesOpen(Face face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null && right == null) return null;
    final best = math.max(left ?? 0, right ?? 0);
    return best >= 0.4;
  }

  /// Detects faces in [file]. Returns [FaceDetectionResult].
  /// [valid] is true only when exactly one face is found.
  static Future<FaceDetectionResult> detectFromFile(File file) async {
    if (!file.existsSync()) {
      return const FaceDetectionResult(
        valid: false,
        faceCount: 0,
        message: 'Image file not found',
      );
    }

    try {
      final inputImage = InputImage.fromFile(file);
      final faces = await _getDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return const FaceDetectionResult(
          valid: false,
          faceCount: 0,
          message: 'No face detected. Please ensure your face is clearly visible.',
        );
      }

      // Largest face drives the orientation decision.
      faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
          .compareTo(a.boundingBox.width * a.boundingBox.height));
      final rollZ = faces.first.headEulerAngleZ;
      final upsideDown = _isFaceUpsideDown(faces.first);
      final headYaw = faces.first.headEulerAngleY;
      final eyesOpen = _areEyesOpen(faces.first);

      if (faces.length > 1) {
        return FaceDetectionResult(
          valid: false,
          faceCount: faces.length,
          message: 'Multiple faces detected. Please take a selfie with only your face in frame.',
          rollZ: rollZ,
          upsideDown: upsideDown,
          eyesOpen: eyesOpen,
          headYaw: headYaw,
        );
      }

      return FaceDetectionResult(
        valid: true,
        faceCount: 1,
        rollZ: rollZ,
        upsideDown: upsideDown,
        eyesOpen: eyesOpen,
        headYaw: headYaw,
      );
    } catch (e) {
      return FaceDetectionResult(
        valid: false,
        faceCount: 0,
        message: 'Face detection failed. Please try again.',
      );
    }
  }

  /// Runs [detectFromFile] on in-memory JPEG [bytes] by staging them to a temp
  /// file (ML Kit's still-image detector needs a file/URI, not raw JPEG bytes).
  /// Used by the capture flow to probe BOTH orientations of the downscaled selfie
  /// when deciding whether the front camera wrote it upside-down.
  static Future<FaceDetectionResult> detectFromBytes(Uint8List bytes) async {
    File? temp;
    try {
      final dir = await getTemporaryDirectory();
      temp = File(
          '${dir.path}/orient_probe_${bytes.length}_${bytes.isEmpty ? 0 : bytes.first}.jpg');
      await temp.writeAsBytes(bytes, flush: true);
      return await detectFromFile(temp);
    } catch (e) {
      return const FaceDetectionResult(
        valid: false,
        faceCount: 0,
        message: 'Face detection failed. Please try again.',
      );
    } finally {
      try {
        await temp?.delete();
      } catch (_) {}
    }
  }

  // ── Live (camera-stream) detection ─────────────────────────────────────────

  /// Separate detector for the live camera stream. Tracking is enabled so the
  /// face count is stable frame-to-frame (less flicker between 1 and 0/2). Kept
  /// distinct from [_detector] so the still-image gate and the live preview can
  /// each reuse their own ML Kit instance.
  static FaceDetector? _liveDetector;

  static FaceDetector get _getLiveDetector {
    _liveDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
        enableLandmarks: false,
        enableContours: false,
        enableClassification: false,
        enableTracking: true,
      ),
    );
    return _liveDetector!;
  }

  /// Counts faces in a live camerawesome [AnalysisImage] frame so the UI can warn
  /// (e.g. "Multiple faces detected") WHILE the user frames the shot — before any
  /// capture or submit. Returns the number of faces, or -1 if the frame could not
  /// be analysed (unsupported format / detection error) so the caller can ignore
  /// that frame rather than treat it as "no face".
  static Future<int> detectFaceCountFromCamera(AnalysisImage image) async {
    final inputImage = _toInputImage(image);
    if (inputImage == null) return -1;
    try {
      final faces = await _getLiveDetector.processImage(inputImage);
      return faces.length;
    } catch (_) {
      return -1;
    }
  }

  /// Live primary-face geometry for the guided-capture overlay: the largest
  /// face's size and centering, as ratios of the (rotation-corrected) frame, plus
  /// the total face count. Drives the new-app-style guidance ("Come Closer",
  /// "Center Your Face", "Only 1 Face") and the auto-capture trigger. Returns null
  /// when the frame can't be analysed so the caller ignores it. Ratios are
  /// rotation-invariant: a centered face reads cx≈cy≈0.5 regardless of sensor
  /// orientation or front-camera mirroring.
  static Future<LivePrimaryFace?> detectPrimaryFaceFromCamera(AnalysisImage image) async {
    final inputImage = _toInputImage(image);
    if (inputImage == null) return null;
    try {
      final faces = await _getLiveDetector.processImage(inputImage);
      if (faces.isEmpty) return const LivePrimaryFace(count: 0);
      faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
          .compareTo(a.boundingBox.width * a.boundingBox.height));
      final bb = faces.first.boundingBox;
      final meta = inputImage.metadata;
      double iw = meta?.size.width ?? 0;
      double ih = meta?.size.height ?? 0;
      // ML Kit reports the box in the ROTATED image space; swap dims for 90/270.
      if (meta?.rotation == InputImageRotation.rotation90deg ||
          meta?.rotation == InputImageRotation.rotation270deg) {
        final t = iw;
        iw = ih;
        ih = t;
      }
      if (iw <= 0 || ih <= 0) return LivePrimaryFace(count: faces.length);
      final cx = (bb.center.dx / iw).clamp(0.0, 1.0);
      final cy = (bb.center.dy / ih).clamp(0.0, 1.0);
      final sizeRatio = math.sqrt((bb.width * bb.height) / (iw * ih)).clamp(0.0, 1.0);
      return LivePrimaryFace(
        count: faces.length,
        sizeRatio: sizeRatio.toDouble(),
        centerX: cx.toDouble(),
        centerY: cy.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Builds an ML Kit [InputImage] from a camerawesome analysis frame. Supports
  /// the recommended formats: nv21 (Android) and bgra8888 (iOS). Returns null for
  /// any other format. Only face COUNT is consumed downstream, which is robust to
  /// small rotation/metadata imperfections.
  static InputImage? _toInputImage(AnalysisImage image) {
    return image.when(
      nv21: (Nv21Image img) => InputImage.fromBytes(
        bytes: img.bytes,
        metadata: InputImageMetadata(
          rotation: _rotationOf(img.rotation),
          format: InputImageFormat.nv21,
          size: img.size,
          bytesPerRow: img.planes.first.bytesPerRow,
        ),
      ),
      bgra8888: (Bgra8888Image img) => InputImage.fromBytes(
        bytes: img.bytes,
        metadata: InputImageMetadata(
          rotation: _rotationOf(img.rotation),
          format: InputImageFormat.bgra8888,
          size: img.size,
          bytesPerRow: img.planes.first.bytesPerRow,
        ),
      ),
    );
  }

  static InputImageRotation _rotationOf(InputAnalysisImageRotation r) {
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

  /// Release the detector when done (e.g. app lifecycle).
  /// Optional; detector is reused otherwise.
  static Future<void> close() async {
    await _detector?.close();
    _detector = null;
    await _liveDetector?.close();
    _liveDetector = null;
  }
}
