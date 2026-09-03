import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/break_service.dart';

class BreakStatusCard extends StatefulWidget {
  final DateTime startTime;
  final VoidCallback? onEndBreak;
  final bool isBusy;
  final bool showSuccessBanner;

  /// When set, the live timer stops advancing and is pinned to this instant.
  /// Passed by the parent at the moment the user taps "End Break" — the same
  /// button-tap instant that becomes the recorded break end time — so the
  /// displayed elapsed equals the saved duration instead of drifting upward
  /// while the end selfie/face-verification/network round-trip completes.
  final DateTime? freezeAt;

  /// Seconds of COMPLETED breaks taken earlier today (excludes the ongoing one).
  /// When non-null, the card shows a live "Taken today" total = this + the
  /// current break's running elapsed. Null hides that line.
  final int? completedBreakSecondsToday;

  const BreakStatusCard({
    super.key,
    required this.startTime,
    this.onEndBreak,
    this.isBusy = false,
    this.showSuccessBanner = false,
    this.completedBreakSecondsToday,
    this.freezeAt,
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
    // If the passed start is essentially "now" (e.g. fallback DateTime.now()),
    // but BreakService knows the actual earlier start time (e.g. 11:47 AM or 11:57 AM),
    // always prefer the earlier authentic start time so the timer is cumulative!
    final persisted = BreakService.lastKnownBreakStartTime;
    if (persisted != null && persisted.isBefore(now)) {
      if (apiStart.difference(now).abs() < const Duration(seconds: 10)) {
        return persisted;
      }
    }
    if (apiStart.isAfter(now.add(const Duration(seconds: 3)))) {
      return persisted ?? now;
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
    BreakService.getPersistedActiveBreakStart().then((persisted) {
      if (persisted != null && mounted) {
        if (_anchorStart.difference(persisted).inSeconds.abs() > 10) {
          setState(() {
            _anchorStart = persisted;
            _tick();
          });
        }
      }
    });
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
      _tick();
    }
    // Once the parent pins a freeze instant (End Break tapped), stop the ticker
    // so the displayed elapsed stays at the recorded value during the
    // selfie/face-verification/network round-trip instead of climbing past it.
    if (oldWidget.freezeAt != widget.freezeAt) {
      if (widget.freezeAt != null) {
        _timer?.cancel();
        _timer = null;
      } else {
        // Freeze released (end aborted) — resume the live ticker.
        _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
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
    // While ending, pin "now" to the tap instant so elapsed matches the saved
    // break duration rather than continuing to advance during the end request.
    final now = widget.freezeAt ?? DateTime.now();
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

  String _hms(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final hours = s ~/ 3600;
    final minutes = (s % 3600) ~/ 60;
    final seconds = s % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // No trailing " hrs" — saves width next to [End Break] on narrow screens.
  String get _timerText => _hms(_elapsed.inSeconds);

  /// Running total break taken today = completed-earlier + current elapsed.
  /// Null when the caller did not supply today's completed total.
  String? get _takenTodayText {
    final prior = widget.completedBreakSecondsToday;
    if (prior == null) return null;
    return _hms(prior + _elapsed.inSeconds);
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

                final startedFromStr =
                    DateFormat('hh:mm a').format(widget.startTime.toLocal());
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
                final takenToday = _takenTodayText;
                final takenTodayLabel = takenToday == null
                    ? null
                    : Text(
                        'Break taken today: $takenToday',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );

                final headerRow = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green.shade500,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Break Ongoing',
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Started from $startedFromStr',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                );

                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      headerRow,
                      const SizedBox(height: 6),
                      Text(
                        _timerText,
                        style: timerStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (takenTodayLabel != null) ...[
                        const SizedBox(height: 4),
                        takenTodayLabel,
                      ],
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
                          headerRow,
                          const SizedBox(height: 6),
                          Text(
                            _timerText,
                            style: timerStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (takenTodayLabel != null) ...[
                            const SizedBox(height: 4),
                            takenTodayLabel,
                          ],
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
