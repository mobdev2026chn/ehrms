// hrms/lib/utils/request_guard.dart
// Prevents multiple API calls from build(), rapid taps, or polling.

import 'dart:async';

/// Guards a single logical action (e.g. "submit login", "check-in") so it
/// cannot run again within [cooldown]. Use for button taps and one-off actions.
class RequestGuard {
  RequestGuard({this.cooldown = const Duration(milliseconds: 1500)});

  final Duration cooldown;
  DateTime? _lastCall;

  /// Returns true if the call is allowed and records the call; false if still in cooldown.
  bool get allow {
    final now = DateTime.now();
    if (_lastCall != null && now.difference(_lastCall!) < cooldown) {
      return false;
    }
    _lastCall = now;
    return true;
  }

  void reset() {
    _lastCall = null;
  }
}

/// Debounces repeated calls so only the last one runs after [duration] of no new calls.
/// Use for search boxes or "refresh" that can be triggered many times quickly.
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 400)});

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    cancel();
  }
}
