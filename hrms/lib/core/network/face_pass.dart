// core/network/face_pass.dart
// One-time pass HRMSbackend issues when the live face check matches
// (POST /staff/face/verify → `facePass`). The punch / break that follows must present it
// as `X-Face-Pass`, so the face check cannot be skipped by calling the punch API directly.

import 'package:dio/dio.dart';

class FacePassStore {
  FacePassStore._();

  // Server keeps a pass for 3 minutes; drop ours a little earlier.
  static const _validFor = Duration(seconds: 170);
  static String? _pass;
  static DateTime? _issuedAt;

  /// Called by AuthService.verifyFace with the pass from a match.
  static void save(String? pass) {
    if (pass == null || pass.isEmpty) return;
    _pass = pass;
    _issuedAt = DateTime.now();
  }

  /// The latest unexpired pass. Not cleared on use: the server consumes it, and a request
  /// that never reached the punch (e.g. too large, retried smaller) can still use it.
  static String? get current {
    final at = _issuedAt;
    if (_pass == null || at == null) return null;
    if (DateTime.now().difference(at) > _validFor) {
      _pass = null;
      _issuedAt = null;
      return null;
    }
    return _pass;
  }
}

/// Attaches the face pass to punch-in / punch-out / break start / break end requests.
class FacePassInterceptor extends Interceptor {
  static final _facePassPaths = RegExp(r'/staff/attendance/(punch-in|punch-out|break/start|break/end)$');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_facePassPaths.hasMatch(options.path)) {
      final pass = FacePassStore.current;
      if (pass != null) options.headers['X-Face-Pass'] = pass;
    }
    handler.next(options);
  }
}
