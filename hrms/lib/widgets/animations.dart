import 'dart:async';
import 'dart:math' as math;
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

/// Looping "pop" pulse: springs the child up to [maxScale] and settles back,
/// then rests for the remainder of [period] before popping again. Handy for
/// celebratory emoji / badges that should feel alive without being distracting.
class PopPulse extends StatefulWidget {
  const PopPulse({
    super.key,
    required this.child,
    this.maxScale = 1.25,
    this.period = const Duration(milliseconds: 1600),
  });

  final Widget child;

  /// Peak scale reached at the top of each pop.
  final double maxScale;

  /// Full cycle length (pop + settle + rest).
  final Duration period;

  @override
  State<PopPulse> createState() => _PopPulseState();
}

class _PopPulseState extends State<PopPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  late final Animation<double> _scale = TweenSequence<double>([
    // Quick springy pop up.
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: widget.maxScale)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 22,
    ),
    // Settle back down.
    TweenSequenceItem(
      tween: Tween<double>(begin: widget.maxScale, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 22,
    ),
    // Rest before the next pop.
    TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 56),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Looping "pulse rings": concentric circles that continuously expand outward
/// from the centre while fading, like a soft radar ripple. Purely decorative —
/// wrap in [IgnorePointer]/overlay behind content. [count] rings are evenly
/// spaced across the [period] so there's always a ring mid-flight.
class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    this.color = Colors.white,
    this.count = 3,
    this.period = const Duration(milliseconds: 2600),
    this.maxRadius = 70,
    this.strokeWidth = 2,
  });

  final Color color;
  final int count;
  final Duration period;
  final double maxRadius;
  final double strokeWidth;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size.square(widget.maxRadius * 2),
              painter: _PulseRingsPainter(
                progress: _controller.value,
                color: widget.color,
                count: widget.count,
                maxRadius: widget.maxRadius,
                strokeWidth: widget.strokeWidth,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PulseRingsPainter extends CustomPainter {
  _PulseRingsPainter({
    required this.progress,
    required this.color,
    required this.count,
    required this.maxRadius,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final int count;
  final double maxRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (var i = 0; i < count; i++) {
      // Stagger each ring evenly across the timeline.
      final t = (progress + i / count) % 1.0;
      final radius = t * maxRadius;
      // Fade out as the ring grows.
      final opacity = (1 - t).clamp(0.0, 1.0);
      paint.color = color.withValues(alpha: opacity * 0.6);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulseRingsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Universe-style "ray light" backdrop: soft colourful beams of light slowly
/// sweep around the centre like a rotating galaxy, while a field of stars
/// orbits and twinkles. Purely decorative — overlay it behind content (it
/// ignores pointers) and clip to the parent's shape. Keep [opacity] modest so
/// foreground text stays readable.
class RayLights extends StatefulWidget {
  const RayLights({
    super.key,
    this.radius = 110,
    this.period = const Duration(seconds: 14),
    this.opacity = 0.7,
    this.starCount = 22,
    this.colors = const [
      Color(0xFF6D28D9), // violet
      Color(0xFF2563EB), // blue
      Color(0xFF0EA5E9), // sky
      Color(0xFFDB2777), // magenta
      Color(0xFFF59E0B), // amber
    ],
  });

  final double radius;
  final Duration period;
  final double opacity;

  /// Number of twinkling stars scattered across the field.
  final int starCount;
  final List<Color> colors;

  @override
  State<RayLights> createState() => _RayLightsState();
}

class _RayLightsState extends State<RayLights>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  // Deterministic star field (computed once) so it doesn't jump on rebuild.
  late final List<_Star> _stars = _buildStars();

  List<_Star> _buildStars() {
    final rnd = math.Random(42);
    return List.generate(widget.starCount, (i) {
      return _Star(
        angle: rnd.nextDouble() * 2 * math.pi,
        distance: (0.18 + rnd.nextDouble() * 0.82) * widget.radius,
        size: 0.7 + rnd.nextDouble() * 1.8,
        phase: rnd.nextDouble() * 2 * math.pi,
        twinkleSpeed: 2 + rnd.nextDouble() * 4,
        gold: rnd.nextDouble() < 0.5,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size.square(widget.radius * 2),
              painter: _UniversePainter(
                progress: _controller.value,
                colors: widget.colors,
                opacity: widget.opacity,
                stars: _stars,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Star {
  _Star({
    required this.angle,
    required this.distance,
    required this.size,
    required this.phase,
    required this.twinkleSpeed,
    required this.gold,
  });

  /// Base orbital angle (radians) and distance from the centre.
  final double angle;
  final double distance;
  final double size;

  /// Twinkle phase offset + speed so stars blink out of sync.
  final double phase;
  final double twinkleSpeed;

  /// Gold star vs cool-white star.
  final bool gold;
}

class _UniversePainter extends CustomPainter {
  _UniversePainter({
    required this.progress,
    required this.colors,
    required this.opacity,
    required this.stars,
  });

  final double progress;
  final List<Color> colors;
  final double opacity;
  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final angle = progress * 2 * math.pi;

    // 1. Rotating beams of light — a soft conic sweep, faded toward the rim.
    final stops = <Color>[];
    for (final c in colors) {
      stops.add(c.withValues(alpha: opacity));
      stops.add(Colors.transparent);
    }
    stops.add(colors.first.withValues(alpha: opacity));

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);
    final rayPaint = Paint()
      ..shader = RadialGradient(
        colors: const [Colors.white, Colors.white, Colors.transparent],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..blendMode = BlendMode.modulate;
    // Draw the conic beams, then soften toward the edge via the radial mask.
    final beams = Paint()
      ..shader = SweepGradient(colors: stops).createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.saveLayer(Rect.fromCircle(center: center, radius: radius), Paint());
    canvas.drawCircle(center, radius, beams);
    canvas.drawCircle(center, radius, rayPaint);
    canvas.restore();
    canvas.restore();

    // 2. Twinkling, slowly orbiting stars.
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (final s in stars) {
      // Orbit at ~40% of the beam rotation for a parallax feel.
      final a = s.angle + angle * 0.4;
      final pos = center + Offset(math.cos(a), math.sin(a)) * s.distance;
      // Twinkle 0..1 via a smooth sine.
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin(progress * s.twinkleSpeed * 2 * math.pi + s.phase));
      final color = s.gold ? const Color(0xFFFFB300) : const Color(0xFF5B6CFF);
      starPaint.color = color.withValues(alpha: (twinkle * opacity).clamp(0.0, 1.0));
      // Soft glow + crisp core.
      starPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      canvas.drawCircle(pos, s.size * (0.8 + twinkle * 0.6), starPaint);
      starPaint.maskFilter = null;
    }
  }

  @override
  bool shouldRepaint(_UniversePainter oldDelegate) =>
      oldDelegate.progress != progress;
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
