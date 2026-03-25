import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/snackbar_utils.dart';

/// Full-screen overlay shown after check-in or check-out with animated emoji
/// plus snackbar message for the action result.
class AttendanceSuccessOverlay extends StatefulWidget {
  static String? _lastSnackbarMessage;
  static DateTime? _lastSnackbarShownAt;
  static const Duration _snackbarDedupWindow = Duration(seconds: 2);

  final bool isCheckIn;
  final String userName;
  final VoidCallback? onDismiss;
  /// When set and [isCheckIn] is true, overrides default 😊 for interactive check-in timing (early / on-time / grace).
  final String? checkInEmoji;
  /// When set and [isCheckIn] is true, overrides default check-in message.
  final String? checkInMessage;
  /// When set and ![isCheckIn], overrides default 👋 for checkout (e.g. happy emoji for late checkout success).
  final String? checkOutEmoji;
  /// When set and ![isCheckIn], overrides default checkout message (e.g. "Checkout success!").
  final String? checkOutMessage;
  /// When true, card uses primary gradient and white text (e.g. for checkout success with colors).
  final bool useColorfulCard;

  const AttendanceSuccessOverlay({
    super.key,
    required this.isCheckIn,
    required this.userName,
    this.onDismiss,
    this.checkInEmoji,
    this.checkInMessage,
    this.checkOutEmoji,
    this.checkOutMessage,
    this.useColorfulCard = false,
  });

  /// Shows only emoji at center (no card). Message content via [snackbarMessage] in snackbar.
  static Future<void> show(
    BuildContext context, {
    required bool isCheckIn,
    required String userName,
    Duration duration = const Duration(seconds: 3),
    String? checkInEmoji,
    String? checkInMessage,
    String? checkOutEmoji,
    String? checkOutMessage,
    bool useColorfulCard = false,
    String? snackbarMessage,
  }) async {
    final effectiveSnackbarMessage =
        (snackbarMessage != null && snackbarMessage.isNotEmpty)
        ? snackbarMessage
        : (isCheckIn ? 'You have checked in.' : 'Checkout success!');
    final now = DateTime.now();
    final isDuplicateSnackbar =
        _lastSnackbarMessage == effectiveSnackbarMessage &&
        _lastSnackbarShownAt != null &&
        now.difference(_lastSnackbarShownAt!) < _snackbarDedupWindow;
    if (!isDuplicateSnackbar) {
      _lastSnackbarMessage = effectiveSnackbarMessage;
      _lastSnackbarShownAt = now;
      SnackBarUtils.showSnackBar(context, effectiveSnackbarMessage);
    }
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;

    OverlayEntry? entry;
    void remove() {
      entry?.remove();
      entry = null;
    }

    entry = OverlayEntry(
      builder: (ctx) => AttendanceSuccessOverlay(
        isCheckIn: isCheckIn,
        userName: userName,
        onDismiss: () {
          remove();
        },
        checkInEmoji: checkInEmoji,
        checkInMessage: checkInMessage,
        checkOutEmoji: checkOutEmoji,
        checkOutMessage: checkOutMessage,
        useColorfulCard: useColorfulCard,
      ),
    );
    overlay.insert(entry!);

    await Future.delayed(duration);
    remove();
  }

  @override
  State<AttendanceSuccessOverlay> createState() => _AttendanceSuccessOverlayState();
}

class _AttendanceSuccessOverlayState extends State<AttendanceSuccessOverlay>
    with TickerProviderStateMixin {
  late AnimationController _emojiController;
  late Animation<double> _emojiBounce;
  late Animation<double> _emojiOpacity;

  @override
  void initState() {
    super.initState();
    _emojiController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _emojiBounce = Tween<double>(begin: 0.92, end: 1.14).animate(
      CurvedAnimation(parent: _emojiController, curve: Curves.easeInOutBack),
    );
    _emojiOpacity = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _emojiController, curve: Curves.easeInOut),
    );

    _emojiController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _emojiController.dispose();
    super.dispose();
  }

  String get _emoji {
    if (widget.isCheckIn && widget.checkInEmoji != null && widget.checkInEmoji!.isNotEmpty) {
      return widget.checkInEmoji!;
    }
    if (!widget.isCheckIn && widget.checkOutEmoji != null && widget.checkOutEmoji!.isNotEmpty) {
      return widget.checkOutEmoji!;
    }
    return widget.isCheckIn ? '😊' : '👋';
  }
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          widget.onDismiss?.call();
        },
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _emojiController,
              builder: (context, child) {
                return Opacity(
                  opacity: _emojiOpacity.value,
                  child: Transform.scale(
                    scale: _emojiBounce.value,
                    child: child,
                  ),
                );
              },
              child: Text(
                _emoji,
                style: const TextStyle(fontSize: 92),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
