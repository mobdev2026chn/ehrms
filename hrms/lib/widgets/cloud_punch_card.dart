import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Dashboard worked-time card.
///
/// - **In progress** (no checkout): live elapsed from [punchInTime], updates every second.
/// - **Completed** ([punchOutTime] set): fixed duration — prefers [workHoursFromAttendance]
///   (attendance collection / API, minutes or legacy fractional hours) when positive, else
///   [punchOutTime] − [punchInTime].
///
/// Styling matches leave request list cards (Requests → Leave).
class CloudPunchCard extends StatefulWidget {
  final DateTime punchInTime;
  final DateTime? punchOutTime;
  /// Raw `workHours` from today's attendance row (see dashboard `_workHoursToMinutes`).
  final num? workHoursFromAttendance;
  final VoidCallback? onCheckOutTap;
  final bool isLoading;
  final bool enabled;

  const CloudPunchCard({
    super.key,
    required this.punchInTime,
    this.punchOutTime,
    this.workHoursFromAttendance,
    this.onCheckOutTap,
    this.isLoading = false,
    this.enabled = true,
  });

  @override
  State<CloudPunchCard> createState() => _CloudPunchCardState();
}

/// Same rules as [HomeDashboardScreen._workHoursToMinutes]: API minutes vs legacy hours.
int? _attendanceWorkHoursToMinutes(num? workHours) {
  if (workHours == null) return null;
  final d = workHours.toDouble();
  if (d <= 0) return null;
  if (d < 24 && (d - d.truncate()).abs() > 0.001) {
    return (d * 60).round();
  }
  return d.round();
}

class _CloudPunchCardState extends State<CloudPunchCard> {
  Duration _displayed = Duration.zero;
  Timer? _timer;

  bool get _isLive => widget.punchOutTime == null;

  Duration _completedDuration() {
    final out = widget.punchOutTime;
    if (out == null) return Duration.zero;
    final apiMins = _attendanceWorkHoursToMinutes(widget.workHoursFromAttendance);
    if (apiMins != null && apiMins > 0) {
      return Duration(minutes: apiMins);
    }
    var d = out.difference(widget.punchInTime);
    if (d.isNegative) return Duration.zero;
    return d;
  }

  @override
  void initState() {
    super.initState();
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
        widget.workHoursFromAttendance == oldWidget.workHoursFromAttendance) {
      return;
    }
    final nowLive = widget.punchOutTime == null;
    if (nowLive) {
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
    super.dispose();
  }

  void _tick() {
    if (!mounted || !_isLive) return;
    final e = DateTime.now().difference(widget.punchInTime);
    if (e != _displayed) setState(() => _displayed = e);
  }

  String _formatHrsMins(Duration d) {
    if (d.isNegative) return '00Hrs 00Mins';
    final totalMins = d.inMinutes;
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    return '${h.toString().padLeft(2, '0')}Hrs ${m.toString().padLeft(2, '0')}Mins';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final workingHrsText = _formatHrsMins(_displayed);
    final checkedInAtStr = DateFormat('hh:mm a').format(widget.punchInTime);
    final checkedOutAtStr = widget.punchOutTime != null
        ? DateFormat('hh:mm a').format(widget.punchOutTime!)
        : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      workingHrsText,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    final msg = checkedOutAtStr != null
                        ? 'Check-in $checkedInAtStr · Check-out $checkedOutAtStr'
                        : 'Checked in today at $checkedInAtStr';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        'i',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _isLive ? 'Worked' : 'Worked today',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
