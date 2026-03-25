import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

/// Converts technical/backend errors to user-understandable messages for snackbars.
/// Never exposes raw exceptions, stack traces, or backend internals.
class ErrorMessageUtils {
  ErrorMessageUtils._();

  static const String _genericMessage =
      'Something went wrong. Please try again.';

  /// Returns a user-friendly message for any error. Use for snackbars/toasts.
  static String toUserFriendlyMessage(dynamic error) {
    if (error == null) return _genericMessage;

    if (error is PlatformException) {
      final code = error.code;
      final message = error.message ?? '';
      // firebase_messaging/unknown - IOException, ExecutionException
      if (code == 'unknown' ||
          code.contains('firebase_messaging') ||
          message.contains('IOException') ||
          message.contains('ExecutionException')) {
        return 'Notification setup failed. You can still use the app. Try again later or check your connection.';
      }
      return _genericMessage;
    }

    if (error is SocketException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('failed host lookup') ||
          msg.contains('name resolution') ||
          msg.contains('nodename nor servname')) {
        return 'Unable to reach server. Please check your internet connection.';
      }
      if (msg.contains('connection refused') || msg.contains('connection reset')) {
        return 'Server is not responding. Please try again in a moment.';
      }
      return 'Connection error. Please check your internet and try again.';
    }

    if (error is TimeoutException) {
      return 'Request timed out. Please try again.';
    }

    if (error is FormatException) {
      return 'Server error. Please try again later.';
    }

    if (error is DioException) {
      final code = error.response?.statusCode;
      final data = error.response?.data;
      String? backendMsg = _extractBackendMessage(data);
      if (backendMsg != null && !_isTechnical(backendMsg)) {
        return backendMsg;
      }
      if (code != null && code >= 500) {
        return 'Server error. Please try again later.';
      }
      if (code == 429) {
        return 'Too many requests. Please try again later.';
      }
      if (code == 401) return 'Session expired. Please log in again.';
      if (code == 403) return 'You don\'t have permission for this action.';
      if (code != null && code >= 400) {
        return backendMsg ?? 'Request failed. Please try again.';
      }
      return _genericMessage;
    }

    final msg = error.toString();
    if (_isTechnical(msg)) return _genericMessage;
    // Short, clean backend messages (e.g. "Invalid OTP") can pass through
    if (msg.length < 80 && !msg.contains('Exception') && !msg.contains('Error:')) {
      final cleaned = msg
          .replaceFirst(RegExp(r'^Exception:\s*'), '')
          .replaceFirst(RegExp(r'^Error:\s*'), '');
      if (cleaned.length < 60) return cleaned;
    }
    return _genericMessage;
  }

  static String? _extractBackendMessage(dynamic data) {
    return messageFromResponseData(data);
  }

  /// Parses API error from Dio [response.data]. Safe when `error` is a String
  /// (e.g. `{ "error": "Unauthorized" }`) — avoids String[int] index crashes.
  static String? messageFromResponseData(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      final t = data.trim();
      if (t.isNotEmpty && t.length < 500) return t;
      return null;
    }
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
      final error = data['error'];
      if (error is String && error.isNotEmpty) return error;
      if (error is Map) {
        final m = error['message'];
        if (m is String && m.isNotEmpty) return m;
        if (m != null) return m.toString();
      }
      if (message != null) return message.toString();
    }
    return null;
  }

  /// User-visible message from a failed Dio call (429 + body parsing).
  static String messageFromDioException(
    DioException e, {
    String fallback = 'Request failed',
  }) {
    if (e.response?.statusCode == 429) {
      return 'Too many requests. Please wait a moment.';
    }
    return messageFromResponseData(e.response?.data) ?? fallback;
  }

  /// True if string looks like a technical error – don't show to user.
  static bool isTechnicalMessage(String s) {
    return _isTechnical(s);
  }

  /// Use when showing a backend message (e.g. result['message']). Returns
  /// the message if user-friendly, otherwise [fallback].
  static String sanitizeForDisplay(String? message,
      {String fallback = 'Something went wrong. Please try again.'}) {
    if (message == null || message.trim().isEmpty) return fallback;
    return _isTechnical(message) ? fallback : message;
  }

  static bool _isTechnical(String s) {
    final lower = s.toLowerCase();
    return lower.contains('exception') ||
        lower.contains('stack trace') ||
        lower.contains('at ') && lower.contains('(') ||
        lower.contains('ioexception') ||
        lower.contains('executionexception') ||
        lower.contains('firebase_messaging') ||
        s.contains('java.') ||
        s.contains('dart:');
  }
}
