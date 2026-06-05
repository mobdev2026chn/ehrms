// hrms/lib/screens/splash/splash_screen.dart
//
// NOTE: This screen uses the `google_fonts` package for the Bricolage Grotesque
// headline. Add it to pubspec.yaml if it isn't already present:
//
//   dependencies:
//     google_fonts: ^6.2.1
//
// If you'd rather not add the dependency, replace the GoogleFonts.bricolageGrotesque(...)
// calls with TextStyle(fontFamily: 'YourBundledFont', ...).

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_colors.dart';
import '../../services/geo/live_tracking_service.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../geo/live_tracking_screen.dart';

// Palette for the dark splash (matches the web design).
const _ink = Color(0xFF121212);
const _ink2 = Color(0xFF1C1B19);
const _inkGlow = Color(0xFF2A2622);
const _paper = Color(0xFFF4EFE6);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Gold accent — driven by the saved theme colour so the splash stays on-brand.
  Color _primaryColor = AppColors.primary;
  bool _isLoadingTheme = true;

  // One-shot entrance (logo / headline / underline / tagline / dots).
  late final AnimationController _introController;
  // Gentle perpetual motion: logo float + doodle bob + glimmer.
  late final AnimationController _ambientController;
  // Looping loader dots.
  late final AnimationController _dotsController;
  // Slow drifting aurora glow behind everything.
  late final AnimationController _auraController;
  // Specular light-sweep across the wordmark.
  late final AnimationController _shimmerController;
  // Drives the rising gold motes.
  late final AnimationController _motesController;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _welcomeFade;
  late final Animation<Offset> _welcomeSlide;
  late final Animation<double> _underline;
  late final Animation<double> _tagFade;
  late final Animation<double> _dotsFade;

  // HRMS line doodles scattered around the edges.
  static const List<_Doodle> _doodles = [
    _Doodle(Icons.calendar_today_outlined, Alignment(-0.82, -0.80), 30, 0.00, 0.0),
    _Doodle(Icons.access_time, Alignment(0.84, -0.62), 28, 0.30, 0.7),
    _Doodle(Icons.work_outline, Alignment(-0.86, 0.40), 32, 0.55, 1.4),
    _Doodle(Icons.person_outline, Alignment(-0.62, 0.66), 28, 0.70, 2.1),
    _Doodle(Icons.description_outlined, Alignment(0.80, 0.52), 30, 0.45, 0.4),
    _Doodle(Icons.bar_chart, Alignment(-0.55, -0.50), 28, 0.62, 1.0),
    _Doodle(Icons.verified_user_outlined, Alignment(0.90, 0.04), 30, 0.25, 1.7),
    _Doodle(Icons.mail_outline, Alignment(0.66, 0.78), 28, 0.80, 0.9),
    _Doodle(Icons.badge_outlined, Alignment(-0.90, -0.10), 28, 0.68, 1.3),
    _Doodle(Icons.account_tree_outlined, Alignment(0.30, -0.84), 30, 0.50, 2.4),
    _Doodle(Icons.payments_outlined, Alignment(-0.30, 0.84), 28, 0.85, 0.6),
    _Doodle(Icons.location_on_outlined, Alignment(-0.18, -0.70), 26, 0.40, 1.8),
    _Doodle(Icons.settings, Alignment(0.50, 0.90), 26, 0.58, 2.0),
    _Doodle(Icons.groups_outlined, Alignment(0.10, 0.62), 30, 0.72, 1.1),
  ];

  late final List<_Mote> _motes;

  @override
  void initState() {
    super.initState();

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _motesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _logoFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.0, 0.30, curve: Curves.easeIn),
    );
    _logoScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _welcomeFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.25, 0.60, curve: Curves.easeIn),
    );
    _welcomeSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.25, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _underline = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.55, 0.85, curve: Curves.easeOutCubic),
    );
    _tagFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.60, 0.85, curve: Curves.easeIn),
    );
    _dotsFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.70, 1.0, curve: Curves.easeIn),
    );

    // Seed the floating motes.
    final rnd = math.Random(7);
    _motes = List.generate(40, (_) {
      return _Mote(
        x: rnd.nextDouble(),
        baseY: rnd.nextDouble(),
        r: rnd.nextDouble() * 1.6 + 0.6,
        speed: rnd.nextDouble() * 0.6 + 0.3,
        alpha: rnd.nextDouble() * 0.45 + 0.12,
      );
    });

    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _introController.forward();
    });

    _loadThemeColor();
    _checkAuth();
  }

  @override
  void dispose() {
    _dotsController.dispose();
    _ambientController.dispose();
    _auraController.dispose();
    _shimmerController.dispose();
    _motesController.dispose();
    _introController.dispose();
    super.dispose();
  }

  Future<void> _loadThemeColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('theme_color');

    if (mounted) {
      setState(() {
        if (colorValue != null) {
          _primaryColor = Color(colorValue);
          AppColors.updateTheme(_primaryColor);
        } else {
          _primaryColor = AppColors.primary;
        }
        _isLoadingTheme = false;
      });
    }
  }

  Future<void> _checkAuth() async {
    // Wait for theme to load
    while (_isLoadingTheme) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Simulate a short loading time for branding or initialization
    await Future.delayed(const Duration(seconds: 2));

    // If the API server (baseUrl) changed since last run, the stored token was
    // signed by a different backend and will 401 on every protected call. Clear
    // it so we fall through to the login screen instead of a broken session.
    await AuthService().clearSessionIfBaseUrlChanged();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      final activeInfo = await LiveTrackingService().getActiveTaskInfo();
      if (activeInfo != null && mounted) {
        // If user tapped "Stop tracking" in notification, native tracking stopped but we had stale state.
        // Sync: clear LiveTrackingService and go to dashboard.
        // Retry: on cold start the native plugin often returns false until initialized — don't wipe prefs.
        final isTracking =
            await LiveTrackingService().isBackgroundLocationTrackingRunningWithRetry();
        if (!isTracking) {
          await LiveTrackingService().stopTracking();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => DashboardScreen()),
          );
          return;
        }
        // Live tracking in progress – go directly to LiveTrackingScreen (no resume prompt)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LiveTrackingScreen(
              taskId: activeInfo['taskId'] as String,
              taskMongoId: activeInfo['taskMongoId'] as String,
              pickupLocation: LatLng(
                activeInfo['pickupLat'] as double,
                activeInfo['pickupLng'] as double,
              ),
              dropoffLocation: LatLng(
                activeInfo['dropoffLat'] as double,
                activeInfo['dropoffLng'] as double,
              ),
              task: null,
            ),
          ),
        );
        return;
      }
      // User is logged in, navigate to Dashboard
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => DashboardScreen()));
    } else {
      // User is not logged in, navigate to Login
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final gold = _primaryColor;
    final blob = math.min(size.width, size.height) * 0.62;

    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        children: [
          // ---- Layered dark gradient backdrop ----
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.25),
                radius: 1.1,
                colors: [_inkGlow, _ink2, _ink],
                stops: [0.0, 0.45, 0.82],
              ),
            ),
            child: SizedBox.expand(),
          ),

          // ---- Drifting aurora glow (replaces the old curved panel) ----
          _auraBlob(
            size: blob,
            align: const Alignment(-0.55, -0.45),
            color: gold.withOpacity(0.30),
            phase: 0,
          ),
          _auraBlob(
            size: blob * 0.85,
            align: const Alignment(0.6, 0.5),
            color: gold.withOpacity(0.22),
            phase: math.pi,
          ),

          // ---- Animated HRMS doodles ----
          ..._doodles.map((d) => _buildDoodle(d, gold)),

          // ---- Rising gold motes ----
          AnimatedBuilder(
            animation: _motesController,
            builder: (context, _) {
              return CustomPaint(
                size: Size.infinite,
                painter: _MotePainter(
                  motes: _motes,
                  progress: _motesController.value,
                  color: gold,
                ),
              );
            },
          ),

          // ---- Centered content ----
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ektaHr wordmark: fade + scale in, light-sweep, gentle float.
                AnimatedBuilder(
                  animation: Listenable.merge([
                    _introController,
                    _ambientController,
                  ]),
                  builder: (context, child) {
                    final floatY = _introController.isCompleted
                        ? -3.0 *
                            math.sin(_ambientController.value * 2 * math.pi)
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(0, floatY),
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Opacity(
                          opacity: _logoFade.value.clamp(0.0, 1.0),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: _shimmerLogo(),
                ),

                const SizedBox(height: 36),

                // "Welcome Back" headline (Bricolage Grotesque).
                ClipRect(
                  child: SlideTransition(
                    position: _welcomeSlide,
                    child: FadeTransition(
                      opacity: _welcomeFade,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Welcome',
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: _paper,
                              ),
                            ),
                            TextSpan(
                              text: ' Back',
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: gold,
                                shadows: [
                                  Shadow(
                                    color: gold.withOpacity(0.5),
                                    blurRadius: 22,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Animated gold underline.
                AnimatedBuilder(
                  animation: _underline,
                  builder: (context, _) {
                    return Container(
                      height: 2,
                      width: 200 * _underline.value,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            gold.withOpacity(0),
                            gold,
                            gold.withOpacity(0),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 22),

                // Spaced tagline.
                FadeTransition(
                  opacity: _tagFade,
                  child: Text(
                    'COMPLETE HUMAN RESOURCE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                      color: _paper.withOpacity(0.40),
                    ),
                  ),
                ),

                const SizedBox(height: 34),

                // Pulsing loader dots (gold).
                FadeTransition(
                  opacity: _dotsFade,
                  child: AnimatedBuilder(
                    animation: _dotsController,
                    builder: (context, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(3, (i) {
                          final t = (_dotsController.value - i * 0.18) % 1.0;
                          final wave =
                              math.sin((t.clamp(0.0, 1.0)) * math.pi);
                          final opacity = 0.3 + 0.7 * wave;
                          final scale = 0.7 + 0.5 * wave;
                          return Padding(
                            padding: EdgeInsets.only(right: i < 2 ? 11 : 0),
                            child: Opacity(
                              opacity: opacity,
                              child: Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: gold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Logo with a moving specular sheen ----
  Widget _shimmerLogo() {
    final logo = Image.asset(
      'assets/images/ektaHr_final.png',
      width: 230,
      fit: BoxFit.contain,
    );
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        // Band sweeps across the central span; clamped so gradient stops stay valid.
        final p = (0.13 + _shimmerController.value * 0.74);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0),
                Colors.white.withOpacity(0),
                Colors.white.withOpacity(0.85),
                Colors.white.withOpacity(0),
                Colors.white.withOpacity(0),
              ],
              stops: [0.0, p - 0.12, p, p + 0.12, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: logo,
    );
  }

  // ---- Single drifting aurora blob ----
  Widget _auraBlob({
    required double size,
    required Alignment align,
    required Color color,
    required double phase,
  }) {
    return AnimatedBuilder(
      animation: _auraController,
      builder: (context, _) {
        final t = _auraController.value * 2 * math.pi + phase;
        final dx = math.sin(t) * 26;
        final dy = math.cos(t * 0.8) * 22;
        final sc = 1 + 0.12 * math.sin(t * 0.6);
        return Align(
          alignment: align,
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(
              scale: sc,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [color, color.withOpacity(0)],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- One HRMS doodle: staggered fade/scale-in, then float + glimmer ----
  Widget _buildDoodle(_Doodle d, Color gold) {
    return Align(
      alignment: d.align,
      child: AnimatedBuilder(
        animation: Listenable.merge([_introController, _ambientController]),
        builder: (context, _) {
          final appear =
              ((_introController.value - d.delay) / 0.4).clamp(0.0, 1.0);
          final amb = _ambientController.value * 2 * math.pi;
          final floatY = math.sin(amb + d.phase) * 6.0;
          final glim = 0.12 + 0.10 * (0.5 + 0.5 * math.sin(amb + d.phase * 1.7));
          return Transform.translate(
            offset: Offset(0, floatY),
            child: Transform.scale(
              scale: 0.8 + 0.2 * appear,
              child: Opacity(
                opacity: appear * glim,
                child: Icon(d.icon, size: d.size, color: gold),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Doodle {
  final IconData icon;
  final Alignment align;
  final double size;
  final double delay; // 0..~0.85 entrance stagger
  final double phase; // float/glimmer offset
  const _Doodle(this.icon, this.align, this.size, this.delay, this.phase);
}

class _Mote {
  final double x; // 0..1 horizontal
  final double baseY; // 0..1 starting vertical
  final double r; // radius px
  final double speed; // travel per loop
  final double alpha;
  const _Mote({
    required this.x,
    required this.baseY,
    required this.r,
    required this.speed,
    required this.alpha,
  });
}

class _MotePainter extends CustomPainter {
  final List<_Mote> motes;
  final double progress; // 0..1 looping
  final Color color;
  _MotePainter({
    required this.motes,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final m in motes) {
      // Move upward and wrap around.
      double y = (m.baseY - progress * m.speed) % 1.0;
      if (y < 0) y += 1.0;
      paint.color = color.withOpacity(m.alpha);
      canvas.drawCircle(
        Offset(m.x * size.width, y * size.height),
        m.r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MotePainter old) =>
      old.progress != progress || old.color != color;
}