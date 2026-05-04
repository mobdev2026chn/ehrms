import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Shrinks attendance punch selfies before upload to reduce send time and timeouts.
class AttendanceSelfieCompress {
  static const int _maxSide = 1280;
  static const int _quality = 76;
  static const int _skipBelowBytes = 8000;

  /// Returns a JPEG data URL, or [dataUrl] if compression fails or is not worthwhile.
  static Future<String?> compressDataUrlForPunch(String? dataUrl) async {
    if (dataUrl == null || dataUrl.isEmpty) return dataUrl;
    try {
      final comma = dataUrl.indexOf(',');
      final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
      final raw = base64Decode(b64);
      if (raw.length < _skipBelowBytes) return dataUrl;
      final compressed = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(raw),
        minWidth: _maxSide,
        minHeight: _maxSide,
        quality: _quality,
        format: CompressFormat.jpeg,
      );
      if (compressed.isEmpty) return dataUrl;
      if (compressed.length >= raw.length) return dataUrl;
      return 'data:image/jpeg;base64,${base64Encode(compressed)}';
    } catch (_) {
      return dataUrl;
    }
  }
}
