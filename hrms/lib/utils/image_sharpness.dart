import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Blur check for punch / break / enrollment selfies.
///
/// Measures the variance of the Laplacian (edge detail) over the centre of the
/// photo, where the face is, after scaling it to a fixed 160x160 grayscale so one
/// threshold works for any camera resolution. A sharp face has strong edges
/// (eyes, nose, hairline); motion blur or an out-of-focus shot flattens them.
/// Same measure and scale the server's face engine uses (FACE_BLUR_MIN_VAR).
class ImageSharpness {
  ImageSharpness._();

  /// Below this the photo is too blurry to identify the person. Every value is
  /// logged as `[Selfie] sharpness=...` so it can be tuned on real devices.
  static const double minVariance = 45;

  static const String blurryMessage =
      'Photo is blurry. Hold the phone steady in good light and try again.';

  /// Laplacian variance of the photo's centre, or null if it can't be decoded
  /// (never blocks a capture on a decoding problem).
  static Future<double?> centerVariance(Uint8List jpegBytes) =>
      compute(_centerVariance, jpegBytes);

  static double? _centerVariance(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width < 20 || decoded.height < 20) return null;
      // Centre 60% — where the guide places the face.
      final cw = (decoded.width * 0.6).round();
      final ch = (decoded.height * 0.6).round();
      var face = img.copyCrop(
        decoded,
        x: (decoded.width - cw) ~/ 2,
        y: (decoded.height - ch) ~/ 2,
        width: cw,
        height: ch,
      );
      face = img.grayscale(img.copyResize(face, width: 160, height: 160));

      double lum(int x, int y) => face.getPixel(x, y).r.toDouble();
      var sum = 0.0;
      var sumSq = 0.0;
      var n = 0;
      for (var y = 1; y < 159; y++) {
        for (var x = 1; x < 159; x++) {
          final lap = 4 * lum(x, y) -
              lum(x - 1, y) -
              lum(x + 1, y) -
              lum(x, y - 1) -
              lum(x, y + 1);
          sum += lap;
          sumSq += lap * lap;
          n++;
        }
      }
      final mean = sum / n;
      return sumSq / n - mean * mean;
    } catch (_) {
      return null;
    }
  }
}
