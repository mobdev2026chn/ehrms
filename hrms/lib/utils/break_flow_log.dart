// Break API tracing. Prefer [developer.log] + [debugPrint] because plain [print]
// is easy to miss in IDE "Run" / Windows consoles and on Android logcat.
//
// Android: `adb logcat | findstr /i "flutter BreakFlow"` (Windows) or
// `adb logcat -s flutter` — lines also appear in the Flutter / Dart debug console.
//
// ignore_for_file: avoid_print

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Set to false to silence all [breakFlowLog] calls.
bool breakFlowLoggingEnabled = !kReleaseMode;

/// Enable to log each [parseApiDateTimeToLocal] call (noisy on rebuilds).
bool breakDateTimeParseLoggingEnabled = false;

void breakFlowLog(String message) {
  if (!breakFlowLoggingEnabled) return;
  final line = '[BreakFlow] $message';
  developer.log(line, name: 'BreakFlow');
  debugPrint(line, wrapWidth: 1024);
  print(line);
}
