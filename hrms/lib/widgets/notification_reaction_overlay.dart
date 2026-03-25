import 'dart:async';

import 'package:flutter/material.dart';

class NotificationReactionOverlay extends StatefulWidget {
  final String emoji;
  final VoidCallback? onDismiss;

  const NotificationReactionOverlay({
    super.key,
    required this.emoji,
    this.onDismiss,
  });

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static Future<void> show(
    BuildContext context, {
    required String emoji,
    Duration duration = const Duration(seconds: 3),
  }) async {
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;

    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    void remove() {
      _dismissTimer?.cancel();
      _dismissTimer = null;
      _currentEntry?.remove();
      _currentEntry = null;
    }

    final entry = OverlayEntry(
      builder: (_) => NotificationReactionOverlay(
        emoji: emoji,
        onDismiss: remove,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(duration, remove);
  }

  @override
  State<NotificationReactionOverlay> createState() =>
      _NotificationReactionOverlayState();
}

class _NotificationReactionOverlayState extends State<NotificationReactionOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _emojiController;
  late final Animation<double> _emojiScale;
  late final Animation<double> _emojiOpacity;

  @override
  void initState() {
    super.initState();
    _emojiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _emojiScale = Tween<double>(begin: 0.92, end: 1.14).animate(
      CurvedAnimation(parent: _emojiController, curve: Curves.easeInOutBack),
    );
    _emojiOpacity = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _emojiController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _emojiController,
              builder: (context, child) {
                return Opacity(
                  opacity: _emojiOpacity.value,
                  child: Transform.scale(
                    scale: _emojiScale.value,
                    child: child,
                  ),
                );
              },
              child: Text(
                widget.emoji,
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
