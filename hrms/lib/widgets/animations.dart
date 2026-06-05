import 'dart:async';
import 'package:flutter/material.dart';

/// Subtle entrance animation: fades a child in while it slides up a few px.
///
/// Use [delay] to stagger a column/list of items, or the [FadeSlideIn.staggered]
/// helper to wrap a list of children automatically. The animation runs once when
/// the widget is first mounted; rebuilds (e.g. from `setState`) do not replay it.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 400),
    this.offsetY = 16,
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Initial downward offset (px) the child animates up from.
  final double offsetY;
  final Curve curve;

  /// Wraps each of [children] in a [FadeSlideIn] with an incremental [stepDelay],
  /// producing a staggered cascade. [maxStagger] caps the total delay so long
  /// lists don't feel sluggish.
  static List<Widget> staggered(
    List<Widget> children, {
    Duration stepDelay = const Duration(milliseconds: 60),
    Duration maxStagger = const Duration(milliseconds: 480),
    Duration duration = const Duration(milliseconds: 400),
    double offsetY = 16,
  }) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final ms = (stepDelay.inMilliseconds * i).clamp(0, maxStagger.inMilliseconds);
      out.add(
        FadeSlideIn(
          delay: Duration(milliseconds: ms),
          duration: duration,
          offsetY: offsetY,
          child: children[i],
        ),
      );
    }
    return out;
  }

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        return Opacity(
          opacity: _curved.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _curved.value) * widget.offsetY),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// App-wide route transition: a gentle fade combined with a small upward slide.
///
/// Wired into `ThemeData.pageTransitionsTheme` so every `MaterialPageRoute`
/// across the app gets the same smooth transition with no call-site changes.
/// Implemented with built-in transitions only (version-independent).
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
