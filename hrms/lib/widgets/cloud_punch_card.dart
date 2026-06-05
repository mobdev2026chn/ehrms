import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';

/// Dashboard worked-time card — dark gradient, live timer, punch times.
class CloudPunchCard extends StatefulWidget {
  final DateTime punchInTime;
  final DateTime? punchOutTime;
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
    final apiMins = _attendanceWorkHoursToMinutes(widget.workHoursFromAttendance);
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
        widget.workHoursFromAttendance == oldWidget.workHoursFromAttendance) return;
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
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
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
                          color: AppColors.primary.withValues(alpha: _pulseAnim.value * 0.5),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isLive ? Icons.timer_rounded : Icons.check_circle_rounded,
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
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
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
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        height: 1.0,
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
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'hrs : mins${_isLive ? ' : secs' : ''}',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.3),
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
                color: Colors.greenAccent.shade400,
              ),
              const SizedBox(height: 8),
              _buildTimeTag(
                icon: Icons.logout_rounded,
                label: 'OUT',
                time: outStr ?? '--:--',
                color: outStr != null ? AppColors.primary : Colors.white.withValues(alpha: 0.2),
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                time,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
