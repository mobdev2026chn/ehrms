// core/network/device_id.dart
// Per-install device id, sent as `X-Device-Id` so HRMSbackend can tie an account's
// punches to the phone its face is registered on (device binding).

import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceId {
  DeviceId._();

  static const _key = 'device_install_id';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static String? _cached;
  static Future<String?>? _pending;

  /// Random 128-bit id created on first use and kept in secure storage. It is NOT
  /// cleared on logout: it identifies the phone, not the user. Reinstalling the app
  /// on Android creates a new id, which then needs an admin face reset.
  static Future<String?> get() {
    if (_cached != null) return Future.value(_cached);
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  static Future<String?> _load() async {
    try {
      var id = await _storage.read(key: _key);
      if (id == null || id.isEmpty) {
        final rnd = Random.secure();
        id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        await _storage.write(key: _key, value: id);
      }
      _cached = id;
      return id;
    } catch (e) {
      // No header is sent then; the backend lets such requests through.
      debugPrint('[DeviceId] unavailable: $e');
      return null;
    }
  }
}

/// Adds `X-Device-Id` to every request (mobile only; web has no stable install).
class DeviceIdInterceptor extends Interceptor {
  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!kIsWeb) {
      final id = await DeviceId.get();
      if (id != null) options.headers['X-Device-Id'] = id;
    }
    handler.next(options);
  }
}
