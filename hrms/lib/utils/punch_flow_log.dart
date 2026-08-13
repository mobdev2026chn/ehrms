// Punch / attendance tracing: uses print so lines always show in `flutter run`
// (debugPrint is throttled; kDebugMode is false in profile/release).
// ignore_for_file: avoid_print

void punchFlowLog(String message) {
  print(message);
}
