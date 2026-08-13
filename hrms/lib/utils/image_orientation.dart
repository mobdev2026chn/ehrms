import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Normalises image orientation for display.
///
/// Flutter's image widgets (`Image.memory`, `Image.file`, `Image.network`) do
/// NOT honour the EXIF orientation tag, so a camera photo or scanned document
/// whose pixels are stored sideways/upside-down with an orientation tag renders
/// rotated on-device. The fix is to BAKE the EXIF orientation into the pixels
/// (rotating them upright and resetting the tag) before handing the bytes to a
/// Flutter image widget.
///
/// The selfie/punch pipeline already bakes orientation at upload time
/// (`AttendanceSelfieCompress`); this util is the display-side equivalent used
/// for every other photo the app shows (expense proofs, task photos, form
/// attachments, etc.).
class ImageOrientation {
  ImageOrientation._();

  /// Bakes the EXIF orientation of [bytes] into the pixels off the UI isolate.
  /// Returns the SAME instance when the image is already upright (or decoding
  /// fails), so callers can detect a no-op with [identical].
  static Future<Uint8List> bakeBytes(Uint8List bytes) {
    return compute<Uint8List, Uint8List>(bakeBytesSync, bytes);
  }

  /// Reads [file] and returns its bytes with EXIF orientation baked in.
  static Future<Uint8List> bakeFile(File file) async {
    final raw = await file.readAsBytes();
    return bakeBytes(raw);
  }

  /// Synchronous bake — top-level-safe so it can run under [compute].
  /// Decodes [raw], applies the EXIF orientation, and re-encodes as JPEG.
  /// Returns the SAME [raw] instance when the pixels are already upright (no
  /// orientation tag / orientation == 1) or when decoding fails, avoiding a
  /// needless re-encode.
  static Uint8List bakeBytesSync(Uint8List raw) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      final orientation = decoded.exif.imageIfd.orientation;
      if (orientation == null || orientation == 1) return raw;
      final baked = img.bakeOrientation(decoded);
      return Uint8List.fromList(img.encodeJpg(baked, quality: 90));
    } catch (_) {
      return raw;
    }
  }
}
