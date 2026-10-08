import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/break_summary.dart';

/// Dashboard worked-time card — dark gradient, live timer, punch times.
class CloudPunchCard extends StatefulWidget {
  final DateTime punchInTime;
  final DateTime? punchOutTime;
  final num? workHoursFromAttendance;
  final VoidCallback? onCheckOutTap;
  final bool isLoading;
  final bool enabled;

  /// Today's break summary (list + total). When present and non-empty, the card
  /// renders today's breaks in ascending time order with the day's total.
  final BreakSummary? breakSummary;

  const CloudPunchCard({
    super.key,
    required this.punchInTime,
    this.punchOutTime,
    this.workHoursFromAttendance,
    this.onCheckOutTap,
    this.isLoading = false,
    this.enabled = true,
    this.breakSummary,
  });

  @override
  State<CloudPunchCard> createState() => _CloudPunchCardState();
}

int? _attendanceWorkHoursToMinutes(num? workHours) {
  if (workHours == null) return null;
  final d = workHours.toDouble();
  if (d <= 0) return null;
  if (d < 24 && (d - d.truncate()).abs() > 0.001) return (d * 60).round();
  return d.round();
}

class _CloudPunchCardState extends State<CloudPunchCard>
    with SingleTickerProviderStateMixin {
  Duration _displayed = Duration.zero;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  bool get _isLive => widget.punchOutTime == null;

  Duration _completedDuration() {
    final out = widget.punchOutTime;
    if (out == null) return Duration.zero;
    final apiMins = _attendanceWorkHoursToMinutes(
      widget.workHoursFromAttendance,
    );
    if (apiMins != null && apiMins > 0) return Duration(minutes: apiMins);
    final d = out.difference(widget.punchInTime);
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (_isLive) {
      _tick();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _displayed = _completedDuration();
    }
  }

  @override
  void didUpdateWidget(CloudPunchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.punchInTime == oldWidget.punchInTime &&
        widget.punchOutTime == oldWidget.punchOutTime &&
        widget.workHoursFromAttendance == oldWidget.workHoursFromAttendance)
      return;
    if (widget.punchOutTime == null) {
      _timer?.cancel();
      _tick();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _timer?.cancel();
      _timer = null;
      _displayed = _completedDuration();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted || !_isLive) return;
    final e = DateTime.now().difference(widget.punchInTime);
    if (e != _displayed) setState(() => _displayed = e);
  }

  String _hrs(Duration d) {
    if (d.isNegative) return '00';
    return (d.inMinutes ~/ 60).toString().padLeft(2, '0');
  }

  String _mins(Duration d) {
    if (d.isNegative) return '00';
    return (d.inMinutes % 60).toString().padLeft(2, '0');
  }

  String _secs(Duration d) {
    if (d.isNegative || !_isLive) return '';
    return (d.inSeconds % 60).toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final inStr = DateFormat('hh:mm a').format(widget.punchInTime);
    final outStr = widget.punchOutTime != null
        ? DateFormat('hh:mm a').format(widget.punchOutTime!)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Charcoal brand surface (same family as the bottom nav / login).
        gradient: const LinearGradient(
          colors: [Color(0xFF26262B), AppColors.ink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Animated pulse ring + icon
              SizedBox(
                width: 58,
                height: 58,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isLive)
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, __) => Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withValues(
                                alpha: _pulseAnim.value * 0.5,
                              ),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Icon(
                        _isLive
                            ? Icons.timer_rounded
                            : Icons.check_circle_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Time display
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          _isLive ? 'Currently Working' : 'Worked Today',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.64),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (_isLive) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_hrs(_displayed)}:${_mins(_displayed)}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                            height: 1.0,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (_isLive) ...[
                          const SizedBox(width: 3),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              ':${_secs(_displayed)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                                height: 1.0,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'hrs : mins${_isLive ? ' : secs' : ''}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.42),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Punch in / out times column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTimeTag(
                    icon: Icons.login_rounded,
                    label: 'IN',
                    time: inStr,
                    color: const Color(0xFF34D399),
                  ),
                  const SizedBox(height: 8),
                  _buildTimeTag(
                    icon: Icons.logout_rounded,
                    label: 'OUT',
                    time: outStr ?? '--:--',
                    color: outStr != null
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.38),
                  ),
                ],
              ),
            ],
          ),
          ..._buildBreakSection(),
        ],
      ),
    );
  }

  /// Today's breaks (ascending) + total + remaining. Shown whenever the summary
  /// has loaded — even with zero breaks, so the daily limit is always visible.
  /// Returns empty only when the summary has not loaded yet (or the request
  /// failed), to avoid rendering a blank section.
  List<Widget> _buildBreakSection() {
    final summary = widget.breakSummary;
    if (summary == null) return const [];

    // Breaks are turned off for this shift — there is no allocation to track,
    // so hide the entire break section (heading, allowance bar and rows) on the
    // punch card. `policyDisabled` is true only when the shift explicitly
    // disabled breaks; legacy/unconfigured shifts keep showing it.
    if (summary.policyDisabled) return const [];

    // Break time is only tallied once a break has been properly ended. While a
    // break is still ongoing it must not inflate the day's total or the
    // remaining bar, so use completed-only seconds (excludes the running break).
    final completedSeconds = summary.completedBreakSeconds;

    return [
      const SizedBox(height: 16),
      Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
      const SizedBox(height: 12),
      Row(
        children: [
          Icon(
            Icons.coffee_outlined,
            size: 16,
            color: AppColors.brand,
          ),
          const SizedBox(width: 8),
          Text(
            'Breaks Today',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          Text(
            'Total ${BreakSummary.formatDuration(completedSeconds)}',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.brand,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      if (!summary.isUnlimited) ...[
        const SizedBox(height: 10),
        _buildRemainingBar(summary, completedSeconds),
      ],
      const SizedBox(height: 10),
      if (summary.breaks.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            'No breaks taken yet today',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        )
      else
        ...summary.breaks.map(_buildBreakRow),
    ];
  }

  /// Remaining break-limit indicator: "15m 30s of 45m 00s" + a thin progress
  /// bar. Turns red once the daily limit is used up. Second precision.
  Widget _buildRemainingBar(BreakSummary summary, int usedSeconds) {
    final allowedSec = summary.allowedSeconds ?? (summary.allowedMinutes * 60);
    // Base remaining/used on completed breaks only — an ongoing break isn't
    // counted until it has been ended, so it neither drains the balance nor
    // advances the progress bar.
    final remainingSec = allowedSec - usedSeconds > 0
        ? allowedSec - usedSeconds
        : 0;
    final exhausted = remainingSec <= 0;
    final accent = exhausted
        ? const Color(0xFFF87171)
        : const Color(0xFF34D399);
    final fraction = allowedSec > 0
        ? (usedSeconds / allowedSec).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              exhausted ? 'Limit reached' : 'Remaining',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.64),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              '${BreakSummary.formatDuration(remainingSec)} of ${BreakSummary.formatDuration(allowedSec)}',
              style: TextStyle(
                fontSize: 12,
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ],
    );
  }

  Widget _buildBreakRow(BreakEntry b) {
    final start = b.startTime != null
        ? DateFormat('hh:mm a').format(b.startTime!)
        : '--:--';
    final end = b.ongoing
        ? 'Ongoing'
        : (b.endTime != null
              ? DateFormat('hh:mm a').format(b.endTime!)
              : '--:--');
    final durColor = b.ongoing
        ? AppColors.brand
        : Colors.white.withValues(alpha: 0.85);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: b.ongoing
                  ? AppColors.brand
                  : Colors.white.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              b.ongoing ? '$start  →  Break Ongoing' : '$start  →  $end',
              style: TextStyle(
                fontSize: 12,
                color: b.ongoing
                    ? AppColors.brandLight
                    : Colors.white.withValues(alpha: 0.8),
                fontWeight: b.ongoing ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (b.ongoing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.brand.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'ON BREAK',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.brand,
                ),
              ),
            )
          else
            Text(
              BreakSummary.formatDuration(b.durationSeconds),
              style: TextStyle(
                fontSize: 12,
                color: durColor,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeTag({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                time,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
