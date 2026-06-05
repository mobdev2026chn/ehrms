import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Shrinks attendance punch selfies before upload to reduce send time and timeouts.
///
/// All base64 encode/decode runs on a background isolate via [compute] so the
/// punch spinner never freezes the UI on a multi-MB selfie. The native
/// [FlutterImageCompress] call already runs off the Dart isolate.
class AttendanceSelfieCompress {
  static const int _maxSide = 1280;
  static const int _quality = 76;
  static const int _skipBelowBytes = 8000;

  /// Builds a COMPRESSED jpeg data URL from raw camera bytes, doing the base64
  /// encode off the UI isolate. Use the returned payload for BOTH face
  /// verification and the punch upload so the selfie is compressed once and the
  /// (large) verify request is sent at the reduced size.
  static Future<String> compressRawBytesToDataUrl(Uint8List rawBytes) async {
    final bytes = await _compressBytesOrSame(rawBytes);
    final b64 = await compute<List<int>, String>(base64Encode, bytes);
    return 'data:image/jpeg;base64,$b64';
  }

  /// Returns a JPEG data URL, or [dataUrl] if compression fails or is not worthwhile.
  static Future<String?> compressDataUrlForPunch(String? dataUrl) async {
    if (dataUrl == null || dataUrl.isEmpty) return dataUrl;
    try {
      final comma = dataUrl.indexOf(',');
      final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
      final raw = await compute<String, Uint8List>(base64Decode, b64);
      if (raw.length < _skipBelowBytes) return dataUrl;
      final compressed = await _compressBytesOrSame(raw);
      if (identical(compressed, raw)) return dataUrl;
      final encoded = await compute<List<int>, String>(base64Encode, compressed);
      return 'data:image/jpeg;base64,$encoded';
    } catch (_) {
      return dataUrl;
    }
  }

  /// Native (off-Dart-thread) jpeg compression. Returns the SAME [raw] instance
  /// when compression is skipped or not worthwhile, so callers can detect a no-op
  /// with [identical].
  static Future<Uint8List> _compressBytesOrSame(Uint8List raw) async {
    if (raw.length < _skipBelowBytes) return raw;
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: _maxSide,
        minHeight: _maxSide,
        quality: _quality,
        format: CompressFormat.jpeg,
      );
      if (compressed.isEmpty || compressed.length >= raw.length) return raw;
      return compressed;
    } catch (_) {
      return raw;
    }
  }
}
