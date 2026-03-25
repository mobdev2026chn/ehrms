import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import 'dart:async';

class SnackBarUtils {
  static OverlayEntry? _currentEntry;
  static Timer? _timer;

  /// [duration] optional; if null, defaults to 3 seconds.
  static void showSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    bool isError = false,
    Duration? duration,
  }) {
    // Attempt to find the top-level overlay
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;

    // Remove existing snackbar immediately
    _removeCurrentSnackBarSync();

    _currentEntry = OverlayEntry(
      builder: (context) => _TopSnackBarWidget(
        message: message,
        backgroundColor: isError
            ? const Color(0xFF9CA3AF) // light grey for failure
            : (backgroundColor ?? AppColors.primary), // primary for success
        isError: isError,
        onDismissed: () => _removeCurrentSnackBarSync(),
      ),
    );

    overlay.insert(_currentEntry!);

    // Auto-dismiss after [duration] or default 3 seconds
    _timer = Timer(duration ?? const Duration(milliseconds: 3000), () {
      _removeCurrentSnackBarSync();
    });
  }

  /// Dismisses the currently shown snackbar (e.g. when location is captured).
  static void dismiss() => _removeCurrentSnackBarSync();

  static void _removeCurrentSnackBarSync() {
    _timer?.cancel();
    _timer = null;
    if (_currentEntry != null) {
      try {
        if (_currentEntry!.mounted) {
          _currentEntry?.remove();
        }
      } catch (e) {
        // Already removed or other issue
      }
      _currentEntry = null;
    }
  }
}

class _TopSnackBarWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final bool isError;
  final VoidCallback onDismissed;

  const _TopSnackBarWidget({
    required this.message,
    required this.backgroundColor,
    required this.isError,
    required this.onDismissed,
  });

  @override
  State<_TopSnackBarWidget> createState() => _TopSnackBarWidgetState();
}

class _TopSnackBarWidgetState extends State<_TopSnackBarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: SlideTransition(
            position: _offsetAnimation,
            child: Dismissible(
              key: UniqueKey(),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismissed(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.backgroundColor,
                      widget.backgroundColor.withOpacity(0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: widget.backgroundColor.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isError
                            ? Icons.error_outline
                            : (widget.message.toLowerCase().contains('waiting')
                                  ? Icons.timer_outlined
                                  : Icons.check_circle_outline),
                        color: widget.isError ? const Color(0xFF374151) : Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.left,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.isError ? const Color(0xFF374151) : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
