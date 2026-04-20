import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class BreakStatusCard extends StatefulWidget {
  final DateTime startTime;
  final VoidCallback? onEndBreak;
  final bool isBusy;
  final bool showSuccessBanner;

  const BreakStatusCard({
    super.key,
    required this.startTime,
    this.onEndBreak,
    this.isBusy = false,
    this.showSuccessBanner = false,
  });

  @override
  State<BreakStatusCard> createState() => _BreakStatusCardState();
}

class _BreakStatusCardState extends State<BreakStatusCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  /// Stable anchor for the ticker — [widget.startTime] can be recomputed each parent
  /// rebuild (e.g. parser edge cases); mutating "now" there would reset elapsed every frame.
  late DateTime _anchorStart;

  static DateTime _anchorFromApiStart(DateTime apiStart) {
    final now = DateTime.now();
    // Parsed start should not be meaningfully after host clock (bad TZ / payload).
    if (apiStart.isAfter(now.add(const Duration(seconds: 3)))) {
      return now;
    }
    return apiStart;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anchorStart = _anchorFromApiStart(widget.startTime);
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
    }
  }

  @override
  void didUpdateWidget(covariant BreakStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime) {
      _anchorStart = _anchorFromApiStart(widget.startTime);
      _elapsed = Duration.zero;
      _tick();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_anchorStart.isAfter(now.add(const Duration(seconds: 3)))) {
      setState(() {
        _anchorStart = now;
        _elapsed = Duration.zero;
      });
      return;
    }
    final raw = now.difference(_anchorStart);
    // Clock skew / bad parse can make start appear in the future; never show negative.
    final elapsed = raw.isNegative ? Duration.zero : raw;
    if (elapsed != _elapsed) {
      setState(() => _elapsed = elapsed);
    }
  }

  String get _timerText {
    final totalSeconds = _elapsed.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    // No trailing " hrs" — saves width next to [End Break] on narrow screens.
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showSuccessBanner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE9DDFE),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Text(
                'Your break has started!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 340;
                final btn = SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: widget.isBusy ? null : widget.onEndBreak,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: widget.isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.timer_off_rounded, size: 20),
                    label: Text(widget.isBusy ? 'Ending...' : 'End Break'),
                  ),
                );

                final titleStyle = TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                );
                const timerStyle = TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                );

                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Break Ongoing',
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _timerText,
                        style: timerStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      btn,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Break Ongoing',
                            style: titleStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _timerText,
                            style: timerStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      fit: FlexFit.loose,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: btn,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
