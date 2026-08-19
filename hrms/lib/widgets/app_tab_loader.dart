import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Staggered three-dot indicator (black + [AppColors.primary]) — same visual as Salary Overview.
class AppTabLoader extends StatefulWidget {
  const AppTabLoader({super.key});

  @override
  State<AppTabLoader> createState() => _AppTabLoaderState();
}

class _AppTabLoaderState extends State<AppTabLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final color = i.isEven ? Colors.black : AppColors.primary;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = (_controller.value + i / 3) % 1.0;
            final t = math.sin(phase * 2 * math.pi);
            final scale = 0.45 + 0.55 * ((t + 1) / 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: scale,
                child: child,
              ),
            );
          },
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}
