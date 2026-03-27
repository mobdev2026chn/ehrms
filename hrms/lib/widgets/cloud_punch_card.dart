import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Cloud-style punch display: worked time from check-in over cloud image (no card, no checkout button).
/// Minutes shown are worked minutes (elapsed from check-in), updating every second.
class CloudPunchCard extends StatefulWidget {
  final DateTime punchInTime;
  final VoidCallback? onCheckOutTap;
  final bool isLoading;
  final bool enabled;

  const CloudPunchCard({
    super.key,
    required this.punchInTime,
    this.onCheckOutTap,
    this.isLoading = false,
    this.enabled = true,
  });

  @override
  State<CloudPunchCard> createState() => _CloudPunchCardState();
}

class _CloudPunchCardState extends State<CloudPunchCard> {
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final e = DateTime.now().difference(widget.punchInTime);
    if (e != _elapsed) setState(() => _elapsed = e);
  }

  @override
  Widget build(BuildContext context) {
    // Worked time from check-in: hours and minutes (minutes = worked minutes in current hour)
    final workedHours = _elapsed.inHours;
    final workedMinutes = _elapsed.inMinutes.remainder(60);
    final workingHrsText =
        '${workedHours.toString().padLeft(2, '0')}Hrs ${workedMinutes.toString().padLeft(2, '0')}Mins';
    final checkedInAtStr = DateFormat('hh:mm a').format(widget.punchInTime);

    // No card wrapper: cloud is shown without a card. Light overlay so cloud stays visible.
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          children: [
           
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.35),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Checked in today at $checkedInAtStr'),
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
                  const Text(
                    'Worked',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Checked in today at $checkedInAtStr',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
