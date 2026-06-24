// hrms/lib/widgets/app_drawer.dart
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hrms/screens/holidays/holidays_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/auth/auth_bloc.dart';
import '../config/app_colors.dart';
import '../utils/avatar_orientation.dart';
import '../services/auth_service.dart';
import '../services/presence_tracking_service.dart';
import '../screens/auth/login_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/assets/assets_listing_screen.dart';
import '../screens/geo/my_tasks_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/performance/performance_module_screen.dart';
import '../screens/announcements/announcements_screen.dart';
import '../screens/grievance/grievance_shell_screen.dart';
import '../screens/interaction/interaction_shell_screen.dart';
import '../screens/lms/lms_shell_screen.dart';
import '../screens/lms_admin/lms_admin_shell_screen.dart';

class AppDrawer extends StatefulWidget {
  final int? currentIndex;
  final void Function(int index)? onNavigateToIndex;

  const AppDrawer({super.key, this.currentIndex, this.onNavigateToIndex});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Map<String, dynamic>? _userData;
  // Whether the header avatar must be flipped 180° on display (legacy selfies were
  // stored upside-down). Detected from the image via ML Kit, same as the dashboard.
  bool _avatarNeedsFlip = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userString = prefs.getString('user');
    if (userString != null && mounted) {
      final data = jsonDecode(userString) as Map<String, dynamic>;
      setState(() => _userData = data);
      _resolveAvatarFlip(data['avatar'] ?? data['photoUrl']);

      final needsLocationAccess = !data.containsKey('locationAccess');
      final needsBranchName = !data.containsKey('branchName') || data['branchName'] == null;
      // Older cached sessions predate employeeId in the login response; backfill it.
      final needsEmployeeId = data['employeeId'] == null ||
          data['employeeId'].toString().trim().isEmpty;
      // staffType (Intern / Full Time / …) lives on the Staff record, not the
      // login user payload, so backfill it from the profile for the header.
      final needsStaffType = data['staffType'] == null ||
          data['staffType'].toString().trim().isEmpty;
      if (needsLocationAccess || needsBranchName || needsEmployeeId || needsStaffType) {
        try {
          final result = await AuthService().getProfile();
          if (result['success'] == true && mounted) {
            final profileData = result['data'] as Map<String, dynamic>?;
            final staffData = profileData?['staffData'] as Map<String, dynamic>?;
            if (needsLocationAccess) data['locationAccess'] = staffData?['locationAccess'] == true;
            if (needsEmployeeId && staffData?['employeeId'] != null) {
              data['employeeId'] = staffData!['employeeId'];
            }
            if (needsStaffType && staffData?['staffType'] != null) {
              data['staffType'] = staffData!['staffType'];
            }
            if (needsBranchName) {
              final bn = profileData?['branchName']?.toString() ??
                  (staffData?['branchId'] is Map ? (staffData!['branchId'] as Map)['branchName']?.toString() : null);
              if (bn != null && bn.isNotEmpty) data['branchName'] = bn;
            }
            await prefs.setString('user', jsonEncode(data));
            if (mounted) setState(() => _userData = data);
          }
        } catch (_) {}
      }
    }
  }

  /// Detect (once, cached) whether the header avatar is stored upside-down and
  /// flip it on display. No-op for empty / non-http urls or undetectable images.
  Future<void> _resolveAvatarFlip(dynamic avatarUrl) async {
    final url = avatarUrl?.toString().trim() ?? '';
    if (url.isEmpty || !url.startsWith('http')) return;
    final needsFlip = await AvatarOrientation.resolveNeedsFlip(url);
    if (needsFlip == null || needsFlip == _avatarNeedsFlip || !mounted) return;
    setState(() => _avatarNeedsFlip = needsFlip);
  }

  /// Admin-like roles that can access the LMS admin console.
  bool get _isAdminLike {
    final role = (_userData?['role'] ?? '').toString().toLowerCase().trim();
    return role == 'admin' ||
        role == 'super admin' ||
        role == 'superadmin' ||
        role == 'hr' ||
        role == 'senior hr';
  }

  void _navigateToTab(int index) {
    final callback = widget.onNavigateToIndex;
    Navigator.pop(context);
    Future.microtask(() {
      if (callback != null) {
        callback(index);
        if (mounted && context.mounted) {
          final nav = Navigator.of(context);
          if (nav.canPop()) nav.popUntil((r) => r.isFirst);
        }
      } else if (mounted && context.mounted) {
        _push(DashboardScreen(initialIndex: index));
      }
    });
  }

  void _push(Widget screen) {
    if (!mounted || !context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (r) => r.isFirst,
    );
  }

  Future<void> _logout(BuildContext context) async {
    await PresenceTrackingService().stopTracking();
    await AuthService().logout();
    if (!context.mounted) return;
    context.read<AuthBloc>().add(const AuthLogoutRequested());
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      // Narrower than the Material default (304) so the drawer doesn't cover as
      // much of the screen; capped to a fraction on small devices.
      width: MediaQuery.of(context).size.width * 0.72,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Amber Profile Header Card ─────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _buildHeaderCard(),
            ),
            const SizedBox(height: 8),
            // ── Nav Label ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'NAVIGATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textCaption,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            // ── Nav Items ────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _item(Icons.person_outline, 'Profile', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const ProfileScreen(dashboardTabIndex: 3)));
                  }),
                  _item(Icons.calendar_today_outlined, 'Attendance', () => _navigateToTab(4)),
                  _item(Icons.inventory_2_outlined, 'My Assets', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const AssetsListingScreen()));
                  }),
                  _item(Icons.trending_up_outlined, 'Performance', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const PerformanceModuleScreen()));
                  }),
                    _item(Icons.umbrella_outlined, 'Holidays', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const HolidaysScreen()));
                  }),
                  _item(Icons.assignment_outlined, 'Tasks', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const MyTasksScreen(dashboardTabIndex: 1)));
                  }),
                  _item(Icons.share_outlined, 'Interaction', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const InteractionShellScreen()));
                  }),
                  _item(Icons.campaign_outlined, 'Announcements', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const AnnouncementsScreen()));
                  }),
                  _item(Icons.warning_amber_outlined, 'Grievance', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const GrievanceShellScreen()));
                  }),
              //     _item(Icons.school_outlined, 'My Learning', () {
              //       Navigator.pop(context);
              //       Future.microtask(() => _push(const LmsShellScreen()));
              //     }),
              //  //   if (_isAdminLike)
              //       _item(Icons.admin_panel_settings_outlined, 'LMS Admin', () {
              //         Navigator.pop(context);
              //         Future.microtask(() => _push(const LmsAdminShellScreen()));
              //       }),
                  _item(Icons.settings_outlined, 'Settings', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const SettingsScreen()));
                  }),
                ],
              ),
            ),
            // ── Logout ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: _item(Icons.logout_rounded, 'Logout', () => _logout(context),
                  color: AppColors.error),
            ),
          ],
        ),
      ),
    );
  }

  /// Amber rounded header card matching Figma exactly.
  Widget _buildHeaderCard() {
    final name     = _userData?['name']      ?? 'Employee';
    // Show the staff type (Intern / Full Time / …); fall back to role when the
    // staffType hasn't been backfilled yet (older cached sessions).
    final staffType = _userData?['staffType']?.toString().trim() ?? '';
    final role     = staffType.isNotEmpty ? staffType : (_userData?['role'] ?? '');
    final empId    = _userData?['employeeId']?.toString() ?? '';
    final branch   = _userData?['branchName']?.toString() ?? '';
    final avatarUrl = _userData?['avatar']   ?? _userData?['photoUrl'];
    final showAvatar = avatarUrl != null &&
        avatarUrl.toString().trim().isNotEmpty &&
        avatarUrl.toString().startsWith('http');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      // Decorative soft glow blobs behind the content for depth.
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -24,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -36,
            left: -20,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            // Avatar + name/role on a row, meta chips stacked below.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.9),
                            Colors.white.withValues(alpha: 0.4),
                          ],
                        ),
                      ),
                      // Flip legacy (pre-fix, upside-down) seeded avatars 180°.
                      child: RotatedBox(
                        quarterTurns: (showAvatar && _avatarNeedsFlip) ? 2 : 0,
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
                          backgroundImage: showAvatar
                              ? CachedNetworkImageProvider(avatarUrl.toString().trim())
                              : null,
                          child: showAvatar
                              ? null
                              : Text(initial,
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (role.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                role,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (empId.toString().isNotEmpty || branch.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  const SizedBox(height: 12),
                ],
                if (empId.toString().isNotEmpty)
                  _metaRow(Icons.badge_outlined, 'Employee ID: $empId'),
                if (empId.toString().isNotEmpty && branch.isNotEmpty)
                  const SizedBox(height: 8),
                if (branch.isNotEmpty)
                  _metaRow(Icons.location_on_outlined, branch),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A small icon + label row used for employee ID / branch under the header.
  Widget _metaRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _item(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    final fg = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
