// hrms/lib/widgets/bottom_navigation_bar.dart
// Reusable custom bottom navbar with dark theme and yellow accent (reference-style).
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_colors.dart';
import '../services/attendance_service.dart';
import '../services/break_service.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../utils/absent_alert_helper.dart';
import '../utils/break_datetime_util.dart';
import 'break_status_card.dart';

/// Config for a single nav item.
class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Reusable bottom navigation bar with dark bar, rounded top corners,
/// and selected icon with yellow circular background.
class AppBottomNavigationBar extends StatefulWidget {
  final int currentIndex;
  final Function(int)? onTap;
  final List<NavItem>? items;

  /// When provided, used for Punch button label (Punch In vs Punch Out). From today's attendance.
  final bool? isPunchedInToday;

  /// When provided, controls hide/show of punch CTA based on today's completion state.
  final bool? isPunchCompletedToday;
  final bool isPunchActionInProgress;
  final bool isBreakActive;
  final bool isBreakActionInProgress;
  final DateTime? activeBreakStartTime;
  final VoidCallback? onEndBreakTap;

  /// When false, hides the tea-break control for shifts with `breakPolicy.enabled == false`.
  final bool showBreakNavButton;

  /// When false, the employee has no salary configured: the Punch button is
  /// dimmed and shows a "Salary is not configured. Contact HR." tooltip.
  final bool salaryConfigured;

  const AppBottomNavigationBar({
    super.key,
    this.currentIndex = 0,
    this.onTap,
    this.items,
    this.isPunchedInToday,
    this.isPunchCompletedToday,
    this.isPunchActionInProgress = false,
    this.isBreakActive = false,
    this.isBreakActionInProgress = false,
    this.activeBreakStartTime,
    this.onEndBreakTap,
    this.showBreakNavButton = true,
    this.salaryConfigured = true,
  });

  static int getCurrentIndex(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    if (route == null) return 0;
    if (route.contains('DashboardScreen')) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is int) return args;
      return 0;
    }
    return 0;
  }

  @override
  State<AppBottomNavigationBar> createState() => _AppBottomNavigationBarState();
}

class _AppBottomNavigationBarState extends State<AppBottomNavigationBar>
    with SingleTickerProviderStateMixin {
  /// Gentle continuous pulse for the center Punch button (the primary CTA).
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  // ignore: unused_field
  bool _isCandidate = false;
  bool _isPunchedIn = false;
  bool _isPunchCompletedToday = false;
  bool _isPunchStateResolved = false;
  final AttendanceService _attendanceService = AttendanceService();
  final BreakService _breakService = BreakService();
  DateTime? _fetchedBreakStartTime;

  bool _isSameLocalDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isPunchDateForToday(String? rawValue, DateTime today) {
    if (!hasParsablePunchDateTime(rawValue)) return false;
    final parsed = DateTime.tryParse(rawValue!.trim())?.toLocal();
    if (parsed == null) return false;
    return _isSameLocalDate(parsed, today);
  }

  @override
  void initState() {
    super.initState();
    _checkRole();
    _checkPunchState();
    _fetchActiveBreak();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refresh prefs-backed punch state on nav changes when external dashboard
    // state is not provided. This avoids show/hide flicker during tab switches.
    final usesInternalPunchState =
        widget.isPunchedInToday == null && widget.isPunchCompletedToday == null;
    if (usesInternalPunchState &&
        oldWidget.currentIndex != widget.currentIndex) {
      _checkPunchState();
    }
  }

  bool get _useExternalBreakState =>
      widget.onEndBreakTap != null ||
      widget.activeBreakStartTime != null ||
      widget.isBreakActive;

  DateTime? get _effectiveBreakStartTime => _useExternalBreakState
      ? widget.activeBreakStartTime
      : _fetchedBreakStartTime;

  // ignore: unused_element
  bool get _effectiveBreakActive => _useExternalBreakState
      ? (widget.isBreakActive || widget.activeBreakStartTime != null)
      : _fetchedBreakStartTime != null;

  Future<void> _fetchActiveBreak() async {
    final result = await _breakService.getCurrentBreak();
    if (!mounted) return;
    final data = result['data'];
    final parsed = data is Map
        ? breakDisplayStartFromApi(data['startTime'])
        : null;
    setState(() {
      _fetchedBreakStartTime = parsed;
    });
  }

  Future<void> _checkRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');
      if (userString != null) {
        final userData = jsonDecode(userString);
        if (mounted) {
          setState(() {
            _isCandidate =
                (userData['role'] ?? '').toString().toLowerCase() ==
                'candidate';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _checkPunchState() async {
    final wasResolved = _isPunchStateResolved;
    if (mounted && !wasResolved) {
      setState(() {
        _isPunchStateResolved = false;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      // Read cached today's attendance punch state (same logic as dashboard today card)
      final punchIn = prefs.getString('today_punch_in');
      final punchOut = prefs.getString('today_punch_out');
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month}-${today.day}';
      final cacheDay = prefs.getString('today_punch_date');
      final hasPunchInToday = _isPunchDateForToday(punchIn, today);
      final hasPunchOutToday = _isPunchDateForToday(punchOut, today);

      final isPunchedInFromPrefs =
          cacheDay == todayKey &&
          isAwaitingPunchOutFromCachedPunchStrings(
            punchIn: punchIn,
            punchOut: punchOut,
          );
      final isPunchCompletedTodayFromPrefs =
          cacheDay == todayKey && hasPunchInToday && hasPunchOutToday;
      bool resolvedPunchedIn = isPunchedInFromPrefs;
      bool resolvedPunchCompleted = isPunchCompletedTodayFromPrefs;

      // Prefer live today attendance (same source used by Dashboard) so all screens
      // keep the same Punch CTA visibility. Fall back to prefs on errors/offline.
      // Use the service cache (forceRefresh: false) instead of forcing a network
      // hit on every screen/nav mount — the Dashboard and punch submit already
      // refresh this cache, so the nav piggybacks on fresh data without adding
      // redundant /attendance/today calls during the peak punch window.
      try {
        final todayRes = await _attendanceService.getTodayAttendance(
          forceRefresh: false,
        );
        final data = todayRes['data'];
        if (todayRes['success'] == true && data is Map<String, dynamic>) {
          final attendance = flattenTodayAttendancePayload(data) ?? data;
          final hasIn =
              attendance['hasPunchIn'] == true ||
              hasParsablePunchDateTime(attendance['punchIn']);
          final hasOut =
              attendance['hasPunchOut'] == true ||
              hasParsablePunchDateTime(attendance['punchOut']);
          resolvedPunchedIn = isAwaitingPunchOutFromTodayAttendance(attendance);
          resolvedPunchCompleted = hasIn && hasOut;
        }
      } catch (_) {}

      if (kDebugMode) {
        final label = resolvedPunchedIn ? 'Punch Out' : 'Punch In';
        debugPrint(
          '[AppBottomNav] _checkPunchState: todayKey=$todayKey cacheDay=$cacheDay '
          'punchIn=${punchIn != null ? "set" : "null"} punchOut=${punchOut != null ? "set" : "null"} '
          'hasPunchInToday=$hasPunchInToday hasPunchOutToday=$hasPunchOutToday '
          'awaitingPunchOut=$resolvedPunchedIn completedToday=$resolvedPunchCompleted',
        );
        debugPrint(
          '[PunchButton][BottomNav][today-from-prefs] '
          'todayKey=$todayKey cacheDay=$cacheDay '
          'punchIn="${punchIn ?? ""}" punchOut="${punchOut ?? ""}" '
          'awaitingPunchOut=$resolvedPunchedIn => label="$label"',
        );
      }

      if (mounted) {
        setState(() {
          _isPunchedIn = resolvedPunchedIn;
          _isPunchCompletedToday = resolvedPunchCompleted;
          _isPunchStateResolved = true;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AppBottomNav] _checkPunchState error: $e');
      if (mounted) {
        setState(() {
          _isPunchStateResolved = true;
        });
      }
    }
  }

  void _handleNavigation(BuildContext context, int index) {
    HapticFeedback.lightImpact();
    // Canonical layout: slot 0=Home, 1=Attendance, 2=Break, 3=My Request,
    // center=Punch. Map each slot to the DashboardScreen screen index, or to an
    // action code (5=punch, 6=break) handled by the shell / DashboardScreen.
    // Screen indices: 0=Home, 1=My Request, 4=Attendance.
    final int targetIndex;
    switch (index) {
      case 0:
        targetIndex = 0; // Home
        break;
      case 1:
        targetIndex = 4; // Attendance
        break;
      case 2:
        targetIndex = 6; // Break flow
        break;
      case 3:
        targetIndex = 1; // My Request
        break;
      default:
        targetIndex = index; // 5 = punch (passthrough)
    }
    if (widget.onTap != null) {
      widget.onTap!(targetIndex);
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(initialIndex: targetIndex),
        ),
        (route) => route.isFirst,
      );
    }
  }

  List<NavItem> _buildItems() {
    return const [
      NavItem(
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view_rounded,
        label: 'Home',
      ),
      NavItem(
        icon: Icons.access_time_outlined,
        activeIcon: Icons.access_time_filled_rounded,
        label: 'Attendance',
      ),
      NavItem(
        icon: Icons.coffee_outlined,
        activeIcon: Icons.coffee_rounded,
        label: 'Break',
      ),
      NavItem(
        icon: Icons.description_outlined,
        activeIcon: Icons.description_rounded,
        label: 'My Request',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final navItems = widget.items ?? _buildItems();
    final usesInternalPunchState =
        widget.isPunchedInToday == null && widget.isPunchCompletedToday == null;
    final canRenderPunchButton =
        !usesInternalPunchState || _isPunchStateResolved;
    final isPunchedInForBreak = widget.isPunchedInToday ?? _isPunchedIn;
    final isPunchedIn = widget.isPunchedInToday ?? _isPunchedIn;

    const barBg = Color(0xFF1C1C1E);
    const unselected = Color(0xFF8E8E93);
    final selected = AppColors.primary;

    if (kDebugMode) {
      debugPrint(
        '[BottomNav] showBreakNavButton=${widget.showBreakNavButton} isPunchedInForBreak=$isPunchedInForBreak',
      );
    }

    // A break is only valid while punched in (between punch-in and punch-out).
    // `isPunchedIn` (awaiting-punch-out) is true only in that window, so it is
    // the exact condition for enabling the Break tab.
    final breakAllowed = isPunchedIn;

    // Figma layout: 2 tabs | center punch circle | 2 tabs
    // navItems[0]=Home, [1]=Attendance, center=Punch, [2]=Break, [3]=My Request
    Widget navTab(
      int idx,
      NavItem item,
      int navIdx, {
      bool dimmed = false,
      bool busy = false,
    }) {
      final isActive = widget.currentIndex == navIdx;
      return Expanded(
        child: Opacity(
          opacity: dimmed ? 0.4 : 1.0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: busy
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _handleNavigation(context, navIdx);
                  },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(selected),
                        ),
                      )
                    : Icon(
                        isActive ? item.activeIcon : item.icon,
                        size: 22,
                        color: isActive ? selected : unselected,
                      ),
                const SizedBox(height: 4),
                Text(
                  busy ? 'Please wait' : item.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? selected : unselected,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isPunchedInForBreak && _effectiveBreakStartTime != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: BreakStatusCard(
              startTime: _effectiveBreakStartTime!,
              onEndBreak:
                  widget.onEndBreakTap ?? () => _handleNavigation(context, 6),
              isBusy: widget.isBreakActionInProgress,
              showSuccessBanner: false,
            ),
          ),
        SafeArea(
          top: false,
          child: Container(
            height: 72,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: barBg,
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Left 2 tabs: Home + Attendance
                if (navItems.isNotEmpty) navTab(0, navItems[0], 0),
                if (navItems.length > 1) navTab(1, navItems[1], 1),

                // Center: Punch button (raised amber circle)
                SizedBox(
                  width: 72,
                  child: canRenderPunchButton
                      ? Center(
                          child: Tooltip(
                            message: widget.salaryConfigured
                                ? ''
                                : 'Salary is not configured. Contact HR.',
                            triggerMode: widget.salaryConfigured
                                ? TooltipTriggerMode.manual
                                : TooltipTriggerMode.tap,
                            preferBelow: false,
                            child: GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              _handleNavigation(context, 5);
                            },
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 1.0, end: 1.045)
                                  .animate(
                                    CurvedAnimation(
                                      parent: _pulseController,
                                      curve: Curves.easeInOut,
                                    ),
                                  ),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 150),
                                opacity:
                                    (widget.isPunchActionInProgress ||
                                        !widget.salaryConfigured ||
                                        (widget.isPunchCompletedToday ??
                                            _isPunchCompletedToday))
                                    ? 0.5
                                    : 1.0,
                                child: Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.primary,
                                        AppColors.primaryDark,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.5,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isPunchedIn
                                            ? Icons.fingerprint
                                            : Icons.fingerprint,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                      Text(
                                        isPunchedIn ? 'Punch out' : 'Punch in',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 7,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                // Right 2 tabs: Break + My Request
                // Break is dimmed when not punched in / already punched out — the
                // tap is still intercepted and explained by DashboardScreen's gate.
                if (navItems.length > 2)
                  navTab(
                    2,
                    navItems[2],
                    2,
                    dimmed: !breakAllowed && !widget.isBreakActionInProgress,
                    busy: widget.isBreakActionInProgress,
                  ),
                if (navItems.length > 3) navTab(3, navItems[3], 3),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
