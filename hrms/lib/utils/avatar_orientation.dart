import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'face_detection_helper.dart';

/// Decides whether a stored avatar/selfie image needs a 180° display flip by
/// DETECTING the face's actual orientation instead of guessing from a capture
/// timestamp.
///
/// Background: front-camera selfies on some devices were stored upside-down (the
/// camera wrote rotated pixels with EXIF orientation = 1, so the upload-time bake
/// was a no-op). The old heuristic flipped every image captured before a fixed
/// cutoff date — but a timestamp can't tell which images are actually affected,
/// so it both wrongly flips upright photos (showing them upside-down) and misses
/// genuinely-inverted ones. Running the on-device face detector on the image is
/// authoritative.
///
/// The decision is cached per-URL (memory + SharedPreferences) so detection runs
/// at most once per image. Returns null when orientation can't be determined
/// (no face found, or download/detection failed) so callers can keep whatever
/// fallback they were already using.
class AvatarOrientation {
  AvatarOrientation._();

  static const String _prefsPrefix = 'avatar_needs_flip_v1:';
  static final Map<String, bool> _memCache = {};

  /// The cached decision for [url] if already known (memory or prefs), else null.
  static Future<bool?> cachedDecision(String url) async {
    final key = url.trim();
    if (key.isEmpty) return null;
    if (_memCache.containsKey(key)) return _memCache[key];
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('$_prefsPrefix$key');
      if (v != null) _memCache[key] = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Resolve (and cache) whether the image at [url] is stored upside-down and so
  /// needs a 180° display flip. Returns the cached decision immediately when
  /// available; otherwise downloads the image once, runs face detection, caches
  /// the result and returns it. Returns null when it can't be determined (the
  /// result is NOT cached in that case, so a later load can retry).
  static Future<bool?> resolveNeedsFlip(String url) async {
    final key = url.trim();
    if (key.isEmpty || !key.startsWith('http')) return null;

    final existing = await cachedDecision(key);
    if (existing != null) return existing;

    File? temp;
    try {
      final dir = await getTemporaryDirectory();
      temp = File('${dir.path}/avatar_orient_${key.hashCode}.jpg');
      final resp = await Dio().get<List<int>>(
        key,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) return null;
      await temp.writeAsBytes(bytes, flush: true);

      final det = await FaceDetectionHelper.detectFromFile(temp);
      // No face detected → we can't tell orientation; let the caller keep its
      // fallback and retry on a future load.
      if (det.rollZ == null) return null;

      final needsFlip = det.isUpsideDown;
      _memCache[key] = needsFlip;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('$_prefsPrefix$key', needsFlip);
      } catch (_) {}
      return needsFlip;
    } catch (_) {
      return null;
    } finally {
      try {
        await temp?.delete();
      } catch (_) {}
    }
  }
}
