import 'dart:async';

/// Global lightweight event bus for notifying screens when data changes.
///
/// Example:
///   AppEventBus.emit(AppEventType.attendanceChanged);
///   AppEventBus.on(AppEventType.attendanceChanged).listen((_) => _refreshData());

enum AppEventType {
  attendanceChanged,
  salaryChanged,
  dashboardChanged,
}

class AppEvent {
  final AppEventType type;
  const AppEvent(this.type);
}

class AppEventBus {
  AppEventBus._internal();
  static final AppEventBus _instance = AppEventBus._internal();
  factory AppEventBus() => _instance;

  final StreamController<AppEvent> _controller =
      StreamController<AppEvent>.broadcast();

  Stream<AppEvent> get stream => _controller.stream;

  void emit(AppEvent event) {
    _controller.add(event);
  }

  /// Convenience helpers
  static void emitEvent(AppEventType type) {
    AppEventBus().emit(AppEvent(type));
  }

  static Stream<AppEvent> on(AppEventType type) {
    return AppEventBus()
        .stream
        .where((event) => event.type == type);
  }
}

