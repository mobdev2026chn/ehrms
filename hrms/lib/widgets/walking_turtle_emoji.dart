import 'package:flutter/material.dart';

// final Set<String> _playedTurtleAnimationKeys = <String>{};

/// Turtle emoji (🐢) shown standing above Late Login / Early Exit card.
/// Movement animation commented out — turtle is static.
class WalkingTurtleEmoji extends StatefulWidget {
  final double fontSize;
  final bool playOnlyOncePerApp;
  final String animationKey;
  final String emoji;

  const WalkingTurtleEmoji({
    super.key,
    this.fontSize = 72,
    this.playOnlyOncePerApp = false,
    this.animationKey = 'walking-turtle',
    this.emoji = '🐢',
  });

  @override
  State<WalkingTurtleEmoji> createState() => _WalkingTurtleEmojiState();
}

class _WalkingTurtleEmojiState extends State<WalkingTurtleEmoji> {
  // --- Turtle movement (commented out): walking right→left with step bounce ---
  // with SingleTickerProviderStateMixin {
  // late AnimationController _controller;
  // late Animation<double> _moveX;
  // late Animation<double> _bounce;

  // @override
  // void initState() {
  //   super.initState();
  //   _controller = AnimationController(
  //     duration: const Duration(milliseconds: 4000),
  //     vsync: this,
  //   );
  //   _moveX = Tween<double>(begin: 170, end: -170).animate(
  //     CurvedAnimation(parent: _controller, curve: Curves.linear),
  //   );
  //   _bounce = TweenSequence<double>([
  //     TweenSequenceItem(tween: Tween<double>(begin: 0, end: 4), weight: 0.25),
  //     TweenSequenceItem(tween: Tween<double>(begin: 4, end: 0), weight: 0.25),
  //     TweenSequenceItem(tween: Tween<double>(begin: 0, end: 4), weight: 0.25),
  //     TweenSequenceItem(tween: Tween<double>(begin: 4, end: 0), weight: 0.25),
  //   ]).animate(
  //     CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  //   );
  //   final shouldAnimate =
  //       !widget.playOnlyOncePerApp ||
  //       !_playedTurtleAnimationKeys.contains(widget.animationKey);
  //   if (shouldAnimate) {
  //     _playedTurtleAnimationKeys.add(widget.animationKey);
  //     _controller.forward();
  //   } else {
  //     _controller.value = 1.0;
  //   }
  // }
  // @override
  // void dispose() {
  //   _controller.dispose();
  //   super.dispose();
  // }

  @override
  Widget build(BuildContext context) {
    // Standing reaction emoji only (no movement)
    return Text(
      widget.emoji,
      style: TextStyle(fontSize: widget.fontSize),
      textAlign: TextAlign.center,
    );
    // --- Movement (commented out) ---
    // return AnimatedBuilder(
    //   animation: _controller,
    //   builder: (context, child) {
    //     if (_controller.isCompleted) {
    //       return const SizedBox.shrink();
    //     }
    //     return Transform.translate(
    //       offset: Offset(_moveX.value, -_bounce.value),
    //       child: Text(
    //         '🐢',
    //         style: TextStyle(fontSize: widget.fontSize),
    //         textAlign: TextAlign.center,
    //       ),
    //     );
    //   },
    // );
  }
}
