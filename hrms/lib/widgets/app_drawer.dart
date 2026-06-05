// hrms/lib/widgets/app_drawer.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hrms/screens/holidays/holidays_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/auth/auth_bloc.dart';
import '../config/app_colors.dart';
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

      final needsLocationAccess = !data.containsKey('locationAccess');
      final needsBranchName = !data.containsKey('branchName') || data['branchName'] == null;
      if (needsLocationAccess || needsBranchName) {
        try {
          final result = await AuthService().getProfile();
          if (result['success'] == true && mounted) {
            final profileData = result['data'] as Map<String, dynamic>?;
            final staffData = profileData?['staffData'] as Map<String, dynamic>?;
            if (needsLocationAccess) data['locationAccess'] = staffData?['locationAccess'] == true;
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
                  _item(Icons.school_outlined, 'My Learning', () {
                    Navigator.pop(context);
                    Future.microtask(() => _push(const LmsShellScreen()));
                  }),
               //   if (_isAdminLike)
                    _item(Icons.admin_panel_settings_outlined, 'LMS Admin', () {
                      Navigator.pop(context);
                      Future.microtask(() => _push(const LmsAdminShellScreen()));
                    }),
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
    final role     = _userData?['role']      ?? '';
    final empId    = _userData?['staffId']   ?? _userData?['id'] ?? '';
    final avatarUrl = _userData?['avatar']   ?? _userData?['photoUrl'];
    final showAvatar = avatarUrl != null &&
        avatarUrl.toString().trim().isNotEmpty &&
        avatarUrl.toString().startsWith('http');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      // Figma: vertical layout — avatar on top, name/role/ID stacked below.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              backgroundImage: showAvatar ? NetworkImage(avatarUrl.toString().trim()) : null,
              child: showAvatar
                  ? null
                  : Text(initial,
                      style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (role.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              role,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (empId.toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Employee ID: $empId',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
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
