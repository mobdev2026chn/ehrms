import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Result of face detection on an image.
class FaceDetectionResult {
  final bool valid;
  final int faceCount;
  final String? message;

  /// Roll angle (headEulerAngleZ, degrees) of the detected face. ~0 = upright,
  /// ~±180 = upside-down. Null when no face was found. Used to decide whether a
  /// front-camera capture needs a 180° flip (ML Kit detects upside-down faces, so
  /// face-count alone can't tell orientation).
  final double? rollZ;

  const FaceDetectionResult({
    required this.valid,
    required this.faceCount,
    this.message,
    this.rollZ,
  });

  /// True when a face is present and clearly upside-down.
  bool get isUpsideDown => rollZ != null && rollZ!.abs() > 90;
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
        enableLandmarks: false,
        enableContours: false,
        enableClassification: false,
        enableTracking: false,
      ),
    );
    return _detector!;
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

      if (faces.length > 1) {
        return FaceDetectionResult(
          valid: false,
          faceCount: faces.length,
          message: 'Multiple faces detected. Please take a selfie with only your face in frame.',
          rollZ: rollZ,
        );
      }

      return FaceDetectionResult(
        valid: true,
        faceCount: 1,
        rollZ: rollZ,
      );
    } catch (e) {
      return FaceDetectionResult(
        valid: false,
        faceCount: 0,
        message: 'Face detection failed. Please try again.',
      );
    }
  }

  /// Release the detector when done (e.g. app lifecycle).
  /// Optional; detector is reused otherwise.
  static Future<void> close() async {
    await _detector?.close();
    _detector = null;
  }
}
