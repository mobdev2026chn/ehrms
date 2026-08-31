import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// Shrinks attendance punch selfies before upload to reduce send time and timeouts.
///
/// All base64 encode/decode runs on a background isolate via [compute] so the
/// punch spinner never freezes the UI on a multi-MB selfie. The native
/// [FlutterImageCompress] call already runs off the Dart isolate.
class AttendanceSelfieCompress {
  static const int _maxSide = 200;
  static const int _quality = 20;
  static const int _skipBelowBytes = 2000;

  /// Hard ceiling: base64 payload must stay under this. If it doesn't, we
  /// re-compress at rock-bottom quality. 100 KB b64 ≈ 75 KB raw JPEG.
  static const int _maxBase64Length = 100000;

  /// Builds a COMPRESSED jpeg data URL from raw camera bytes.
  ///
  /// Pipeline:
  /// 1. Native platform compress (handles raw camera formats reliably)
  /// 2. Dart image lib resize + re-encode (handles EXIF + exact pixel size)
  /// 3. Hard-cap check — if still too big, crush at quality 5
  static Future<String> compressRawBytesToDataUrl(Uint8List rawBytes) async {
    debugPrint('[SelfieCompress] input: ${rawBytes.length} bytes (${(rawBytes.length / 1024).toStringAsFixed(1)} KB)');

    // ── Step 1: Native platform JPEG compress FIRST ──
    // FlutterImageCompress handles raw camera formats (YUV, HEIF, etc.) that
    // the Dart `image` package may fail on, returning the original multi-MB
    // bytes. By running native compress first we guarantee a small JPEG.
    var processed = await _nativeCompress(rawBytes, maxSide: _maxSide, quality: _quality);
    debugPrint('[SelfieCompress] after native compress: ${processed.length} bytes');

    // ── Step 2: Dart image lib — bake EXIF orientation + exact resize ──
    processed = await compute<Uint8List, Uint8List>(_bakeOrientationSync, processed);
    debugPrint('[SelfieCompress] after bakeOrientation: ${processed.length} bytes');

    // ── Step 3: Encode to base64 ──
    var b64 = await compute<List<int>, String>(base64Encode, processed);

    // ── Step 4: Hard cap — if STILL too large, crush aggressively ──
    if (b64.length > _maxBase64Length) {
      debugPrint('[SelfieCompress] STILL too large (${b64.length} b64 chars), crushing at quality 5 / 120px...');
      processed = await _nativeCompress(processed, maxSide: 120, quality: 5);
      b64 = await compute<List<int>, String>(base64Encode, processed);
    }

    debugPrint('[SelfieCompress] FINAL: ${processed.length} bytes (~${(b64.length / 1024).toStringAsFixed(1)} KB b64)');
    return 'data:image/jpeg;base64,$b64';
  }

  /// Returns a JPEG data URL, or [dataUrl] if compression fails or is not worthwhile.
  static Future<String?> compressDataUrlForPunch(String? dataUrl) async {
    if (dataUrl == null || dataUrl.isEmpty) return dataUrl;
    try {
      final comma = dataUrl.indexOf(',');
      final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
      final raw = await compute<String, Uint8List>(base64Decode, b64);
      if (raw.length < _skipBelowBytes && raw.length <= 50000) return dataUrl;
      final compressed = await _nativeCompress(raw, maxSide: _maxSide, quality: _quality);
      final oriented = await compute<Uint8List, Uint8List>(_bakeOrientationSync, compressed);
      final encoded = await compute<List<int>, String>(base64Encode, oriented);
      return 'data:image/jpeg;base64,$encoded';
    } catch (_) {
      return dataUrl;
    }
  }

  /// Bakes the EXIF orientation into the pixels and re-encodes as a small JPEG.
  /// If decoding fails, returns the input unchanged (the native step already
  /// produced a valid JPEG, so this is safe).
  static Uint8List _bakeOrientationSync(Uint8List raw) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      var processed = decoded;
      final orientation = decoded.exif.imageIfd.orientation;
      if (orientation != null && orientation != 1) {
        processed = img.bakeOrientation(decoded);
      }
      if (processed.width > _maxSide || processed.height > _maxSide) {
        processed = img.copyResize(
          processed,
          width: processed.width >= processed.height ? _maxSide : null,
          height: processed.height > processed.width ? _maxSide : null,
        );
      }
      return Uint8List.fromList(img.encodeJpg(processed, quality: _quality));
    } catch (_) {
      // Already a valid JPEG from native compress — safe to return as-is.
      return raw;
    }
  }

  /// Native platform JPEG compression. This is the PRIMARY size reducer.
  /// Unlike the Dart `image` package, FlutterImageCompress handles raw
  /// camera formats (HEIF, YUV, etc.) reliably on Android/iOS.
  static Future<Uint8List> _nativeCompress(Uint8List raw, {required int maxSide, required int quality}) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: maxSide,
        minHeight: maxSide,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (compressed.isNotEmpty) {
        return compressed;
      }
      return raw;
    } catch (e) {
      debugPrint('[SelfieCompress] native compress failed: $e');
      return raw;
    }
  }
}
