import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight, dependency-free confetti animation.
///
/// Spawns a burst of colourful particles (squares, circles, thin rectangles)
/// that fall, drift sideways and spin, fading out near the end. The animation
/// plays once when the widget is first mounted and then rests invisibly, so it
/// is safe to overlay on top of any content with [IgnorePointer].
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.particleCount = 70,
    this.duration = const Duration(milliseconds: 2800),
    this.minSize = 6,
    this.maxSize = 14,
    this.repeat = false,
    this.colors = const [
      Color(0xFFEFAA1F), // amber gold (brand)
      Color(0xFF6366F1), // indigo
      Color(0xFF059669), // green
      Color(0xFFFF6F91), // pink
      Color(0xFF2563EB), // blue
      Color(0xFFF97316), // orange
    ],
  });

  /// Number of confetti particles to spawn.
  final int particleCount;

  /// Total time for a particle to travel from top to bottom. Larger = slower.
  final Duration duration;

  /// Smallest / largest particle side length in logical pixels.
  final double minSize;
  final double maxSize;

  /// When true the burst loops forever; otherwise it plays once and rests.
  final bool repeat;

  /// Palette the particles are randomly coloured from.
  final List<Color> colors;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final List<_Particle> _particles = _buildParticles();

  @override
  void initState() {
    super.initState();
    if (widget.repeat) {
      _controller.repeat();
    } else {
      _controller.forward();
    }
  }

  List<_Particle> _buildParticles() {
    final rnd = math.Random();
    return List.generate(widget.particleCount, (i) {
      return _Particle(
        startX: rnd.nextDouble(),
        startY: -0.15 - rnd.nextDouble() * 0.35,
        drift: (rnd.nextDouble() - 0.5) * 0.5,
        sway: 0.02 + rnd.nextDouble() * 0.05,
        swayFreq: 2 + rnd.nextDouble() * 3,
        fall: 0.9 + rnd.nextDouble() * 0.5,
        size: widget.minSize + rnd.nextDouble() * (widget.maxSize - widget.minSize),
        spin: (rnd.nextDouble() - 0.5) * 14,
        delay: rnd.nextDouble() * 0.25,
        color: widget.colors[i % widget.colors.length],
        shape: _ParticleShape.values[i % _ParticleShape.values.length],
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
              size: Size.infinite,
              painter: _ConfettiPainter(
                progress: _controller.value,
                particles: _particles,
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _ParticleShape { square, circle, strip }

class _Particle {
  _Particle({
    required this.startX,
    required this.startY,
    required this.drift,
    required this.sway,
    required this.swayFreq,
    required this.fall,
    required this.size,
    required this.spin,
    required this.delay,
    required this.color,
    required this.shape,
  });

  /// Normalised (0..1) horizontal start position.
  final double startX;

  /// Normalised vertical start (negative = above the canvas).
  final double startY;

  /// Net horizontal travel across the full fall (normalised).
  final double drift;

  /// Amplitude + frequency of the side-to-side sway.
  final double sway;
  final double swayFreq;

  /// How far down the particle falls (normalised, can exceed 1).
  final double fall;

  /// Side length in logical pixels.
  final double size;

  /// Rotations (turns) over the lifetime.
  final double spin;

  /// Fraction of the timeline before this particle starts moving.
  final double delay;

  final Color color;
  final _ParticleShape shape;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.particles});

  final double progress;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      // Re-time so each particle has its own start delay and runs to the end.
      final local = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;

      final eased = Curves.easeIn.transform(local);
      final y = (p.startY + p.fall * eased) * size.height;
      final swayOffset =
          math.sin(local * p.swayFreq * math.pi * 2) * p.sway * size.width;
      final x = (p.startX + p.drift * local) * size.width + swayOffset;

      // Fade in quickly, hold, then fade out over the last 25%.
      final opacity = local < 0.1
          ? local / 0.1
          : (local > 0.75 ? (1 - (local - 0.75) / 0.25) : 1.0);

      paint.color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local * math.pi * 2);

      switch (p.shape) {
        case _ParticleShape.square:
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size,
            ),
            paint,
          );
        case _ParticleShape.circle:
          canvas.drawCircle(Offset.zero, p.size / 2, paint);
        case _ParticleShape.strip:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: p.size * 1.6,
                height: p.size * 0.5,
              ),
              const Radius.circular(2),
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
