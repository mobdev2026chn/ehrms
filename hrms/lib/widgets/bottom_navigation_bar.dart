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

class _AppBottomNavigationBarState extends State<AppBottomNavigationBar> {
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
  void didUpdateWidget(AppBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refresh prefs-backed punch state on nav changes when external dashboard
    // state is not provided. This avoids show/hide flicker during tab switches.
    final usesInternalPunchState =
        widget.isPunchedInToday == null && widget.isPunchCompletedToday == null;
    if (usesInternalPunchState && oldWidget.currentIndex != widget.currentIndex) {
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

  bool get _effectiveBreakActive => _useExternalBreakState
      ? (widget.isBreakActive || widget.activeBreakStartTime != null)
      : _fetchedBreakStartTime != null;

  Future<void> _fetchActiveBreak() async {
    final result = await _breakService.getCurrentBreak();
    if (!mounted) return;
    final data = result['data'];
    final parsed = data is Map
        ? parseApiDateTimeToLocal(data['startTime'])
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

      final isPunchedInFromPrefs = cacheDay == todayKey &&
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
      try {
        final todayRes = await _attendanceService.getTodayAttendance(
          forceRefresh: true,
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
    // Bottom-nav third icon is Attendance; DashboardScreen expects tab index 4.
    final targetIndex = index == 2 ? 4 : index;
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
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
      ),
      NavItem(
        icon: Icons.description_outlined,
        activeIcon: Icons.description_rounded,
        label: 'Requests',
      ),
      NavItem(
        icon: Icons.fact_check_outlined,
        activeIcon: Icons.fact_check,
        label: 'Attendance',
      ),
    ];
  }

  /// [fillNavColumn] — pill stretches to fill the punch column (reference UI: large CTA).
  Widget _buildPunchButton(BuildContext context, {bool fillNavColumn = false}) {
    // Prefer dashboard today-card state when provided; else use prefs (same logic as today card)
    final isPunchedIn = widget.isPunchedInToday ?? _isPunchedIn;
    final label = isPunchedIn ? 'Punch Out' : 'Punch In';
    final icon = isPunchedIn ? Icons.logout_rounded : Icons.login_rounded;
    final isDisabled = widget.isPunchActionInProgress;

    // Keep Punch In/Out fully visible in narrow dashboard widths.
    final hPad = fillNavColumn ? 8.0 : 10.0;
    final vPad = fillNavColumn ? 10.0 : 8.0;
    final fontSize = fillNavColumn ? 11.0 : 10.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: IgnorePointer(
        ignoring: isDisabled,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isDisabled ? 0.6 : 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleNavigation(context, 5),
            // [Container] not [AnimatedContainer]: when the break chip is inserted after
            // punch-in, Flutter can reuse the same slot; tweening pill (borderRadius) ↔
            // break circle (BoxShape.circle) throws (box_decoration.dart assertion).
            child: Container(
              width: fillNavColumn ? double.infinity : null,
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: fillNavColumn
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                children: [
                  fillNavColumn
                      ? Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Text(
                          label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                  SizedBox(width: fillNavColumn ? 3 : 2),
                  Icon(icon, size: fillNavColumn ? 16 : 16, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBreakButton(BuildContext context) {
    final icon = _effectiveBreakActive
        ? Icons.free_breakfast_rounded
        : Icons.free_breakfast_outlined;
    final isDisabled = widget.isBreakActionInProgress;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      child: IgnorePointer(
        ignoring: isDisabled,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isDisabled ? 0.6 : 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleNavigation(context, 6),
            // Use [Container] (not [AnimatedContainer]): inserting this row when punch-in
            // flips can otherwise reuse the punch button's element and tween incompatible
            // decorations (circle vs borderRadius). [AnimatedOpacity] still smooths feedback.
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _effectiveBreakActive
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : const Color(0xFF111827),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _effectiveBreakActive
                      ? AppColors.primary.withValues(alpha: 0.45)
                      : const Color(0xFF2B3545),
                ),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navItems = widget.items ?? _buildItems();
    final usesInternalPunchState =
        widget.isPunchedInToday == null && widget.isPunchCompletedToday == null;
    final canRenderPunchButton = !usesInternalPunchState || _isPunchStateResolved;
    // Break icon visibility is controlled by shift break policy from dashboard.
    // Keep punch-state value for other UX pieces (e.g. BreakStatusCard).
    final isPunchedInForBreak = widget.isPunchedInToday ?? _isPunchedIn;

    // Nav bar background: black
    final barBg = Colors.black;
    final unselectedColor = const Color(0xFF94A3B8);
    final selectedColor = AppColors.primary;
    if (kDebugMode) {
      debugPrint(
        '[BreakPolicy][BottomNav] showBreakNavButton=${widget.showBreakNavButton} '
        'isPunchedInForBreak=$isPunchedInForBreak activeBreak=${_effectiveBreakStartTime != null}',
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
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          decoration: BoxDecoration(
            color: barBg,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFF222222), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left cluster: tabs + break share ~2/3 of the bar; tight, even spacing
                  // (reference: no huge dead gap in the middle).
                  Expanded(
                    flex: 5,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (int i = 0; i < navItems.length; i++)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _handleNavigation(context, i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: widget.currentIndex == i
                                    ? selectedColor
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                boxShadow: widget.currentIndex == i
                                    ? [
                                        BoxShadow(
                                          color: selectedColor.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                widget.currentIndex == i
                                    ? navItems[i].activeIcon
                                    : navItems[i].icon,
                                size: 24,
                                color: widget.currentIndex == i
                                    ? Colors.white
                                    : unselectedColor,
                              ),
                            ),
                          ),
                        if (widget.currentIndex >= 0 &&
                            isPunchedInForBreak &&
                            widget.showBreakNavButton)
                          KeyedSubtree(
                            key: const ValueKey('bottom_nav_break'),
                            child: _buildBreakButton(context),
                          ),
                      ],
                    ),
                  ),
                  // Punch CTA: ~3/8 of bar — larger pill (reference ~30–35% width).
                  if (canRenderPunchButton &&
                      !(widget.isPunchCompletedToday ?? _isPunchCompletedToday))
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, right: 10),
                        child: KeyedSubtree(
                          key: const ValueKey('bottom_nav_punch'),
                          child: _buildPunchButton(context, fillNavColumn: true),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
