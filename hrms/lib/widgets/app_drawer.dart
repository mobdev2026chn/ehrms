// hrms/lib/widgets/app_drawer.dart
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/auth/auth_bloc.dart';
import '../config/app_colors.dart';
import '../utils/avatar_orientation.dart';
import '../services/auth_service.dart';
import '../services/presence_tracking_service.dart';
import '../screens/auth/login_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/overtime/overtime_screen.dart';
import '../screens/geo/my_tasks_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/admin/staff/admin_staff_list_screen.dart';
import '../screens/admin/staff/admin_attendance_screen.dart';
import '../screens/admin/staff/admin_overtime_screen.dart';
import '../screens/admin/staff/admin_payroll_screen.dart';
import '../screens/admin/approvals/admin_leave_approvals_screen.dart';
import '../screens/admin/approvals/admin_permission_approvals_screen.dart';
import '../screens/admin/approvals/admin_punch_approvals_screen.dart';
import '../screens/admin/approvals/admin_fine_approvals_screen.dart';
import '../screens/admin/approvals/admin_reimbursement_approvals_screen.dart';
import '../screens/admin/approvals/admin_payslip_approvals_screen.dart';
import '../screens/admin/dashboard/admin_dashboard_screen.dart';
import '../screens/admin/recruitment/admin_job_openings_screen.dart';
import '../screens/admin/recruitment/admin_candidates_screen.dart';
import '../screens/admin/recruitment/admin_appointments_screen.dart';
import '../screens/admin/recruitment/admin_interview_flow_screen.dart';
import '../screens/admin/recruitment/admin_interview_rounds_screen.dart';
import '../screens/admin/recruitment/admin_selected_rejected_screen.dart';
import '../screens/admin/recruitment/admin_offer_letter_screen.dart';
import '../screens/admin/recruitment/admin_verifications_screen.dart';

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
  final Set<String> _expandedSections = {'staff'};
  final Set<String> _expandedSubSections = {};

  bool get _isAdmin {
    final role = (_userData?['role'] ?? '').toString().toLowerCase();
    final staffType = (_userData?['staffType'] ?? '').toString().toLowerCase();
    return role == 'admin' ||
        role == 'superadmin' ||
        role == 'hr' ||
        role == 'hr_admin' ||
        staffType == 'admin';
  }

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

  void _toggleSection(String section) {
    setState(() {
      if (_expandedSections.contains(section)) {
        _expandedSections.remove(section);
      } else {
        _expandedSections.clear();
        _expandedSections.add(section);
      }
    });
  }

  void _toggleSubSection(String subSection) {
    setState(() {
      if (_expandedSubSections.contains(subSection)) {
        _expandedSubSections.remove(subSection);
      } else {
        _expandedSubSections.add(subSection);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkAdmin = _isAdmin;
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.80,
      backgroundColor: isDarkAdmin ? const Color(0xFF18181B) : Colors.white,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Card ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: isDarkAdmin ? _buildAdminHeaderCard() : _buildHeaderCard(),
            ),
            const SizedBox(height: 4),

            // ── Nav Items (Role Based Parity with Web App) ──
            Expanded(
              child: isDarkAdmin ? _buildAdminNavList() : _buildEmployeeNavList(),
            ),

            // ── Logout ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _item(
                Icons.logout_rounded,
                'Logout',
                () => _logout(context),
                color: const Color(0xFFEF4444),
                isDark: isDarkAdmin,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dark-themed Admin Header matching web app sidebar header
  Widget _buildAdminHeaderCard() {
    final name = (_userData?['name'] ?? 'akash').toString();
    final role = (_userData?['role'] ?? 'admin').toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF27272A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3F3F46)),
      ),
      child: Row(
        children: [
          // Logo / Avatar
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEFAA1F), Color(0xFFD97706)],
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'ekta',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'HR',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFEFAA1F),
                      ),
                    ),
                  ],
                ),
                Text(
                  '$name • $role',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFA1A1AA),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF3F3F46),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shield_outlined, size: 14, color: Color(0xFFEFAA1F)),
          ),
        ],
      ),
    );
  }

  /// Standard Employee Drawer List
  Widget _buildEmployeeNavList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
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
        _item(Icons.dashboard_rounded, 'Dashboard', () => _navigateToTab(0)),
        _item(Icons.calendar_month_rounded, 'Attendance', () => _navigateToTab(4)),
        _item(Icons.fact_check_rounded, 'Requests', () => _navigateToTab(1)),
        _item(Icons.assignment_turned_in_rounded, 'GEOtasks', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const MyTasksScreen(dashboardTabIndex: 1)));
        }),
        _item(Icons.schedule_rounded, 'Overtime', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const OvertimeScreen()));
        }),
        const SizedBox(height: 8),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        const SizedBox(height: 8),
        _item(Icons.person_outline_rounded, 'Profile', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const ProfileScreen(dashboardTabIndex: 3)));
        }),
        _item(Icons.settings_outlined, 'Settings', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const SettingsScreen()));
        }),
      ],
    );
  }

  /// Web App Parity Admin Drawer Navigation (Dark Theme with Solid Amber Highlight)
  Widget _buildAdminNavList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        // ── SECTION: RECRUITMENT ──
        _buildAdminCategory(
          title: 'Recruitment',
          icon: Icons.work_outline_rounded,
          isExpanded: _expandedSections.contains('recruitment'),
          onToggle: () => _toggleSection('recruitment'),
          children: [
            _adminSubItem(Icons.list_alt_rounded, 'Job Openings', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminJobOpeningsScreen()),
              );
            }, isSelected: true),
            _adminSubItem(Icons.people_outline_rounded, 'Candidates', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminCandidatesScreen()),
              );
            }),
            _adminSubItem(Icons.calendar_today_outlined, 'Appointments', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminAppointmentsScreen()),
              );
            }),
            _adminSubCategory(
              title: 'Interview Process',
              icon: Icons.account_tree_outlined,
              isExpanded: _expandedSubSections.contains('interview_process'),
              onToggle: () => _toggleSubSection('interview_process'),
              children: [
                _adminSubItem(Icons.circle_outlined, 'Interview Flow', () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminInterviewFlowScreen()),
                  );
                }, isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Rounds', () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminInterviewRoundsScreen()),
                  );
                }, isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Selected / Rejected', () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminSelectedRejectedScreen()),
                  );
                }, isNested: true),
              ],
            ),
            _adminSubItem(Icons.mail_outline_rounded, 'Offer Letter', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminOfferLetterScreen()),
              );
            }),
            _adminSubItem(Icons.verified_user_outlined, 'Verifications', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminVerificationsScreen()),
              );
            }),
          ],
        ),

        const SizedBox(height: 6),

        // ── SECTION: STAFF ──
        _buildAdminCategory(
          title: 'Staff',
          icon: Icons.groups_rounded,
          isExpanded: _expandedSections.contains('staff'),
          onToggle: () => _toggleSection('staff'),
          children: [
            _adminSubItem(Icons.dashboard_outlined, 'Dashboard', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
              );
            }),
            _adminSubItem(
              Icons.badge_outlined,
              'Staff List',
              () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminStaffListScreen()),
                );
              },
            ),
            _adminSubItem(Icons.calendar_month_outlined, 'Attendance', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminAttendanceScreen()),
              );
            }),
            _adminSubItem(Icons.schedule_rounded, 'Overtime', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminOvertimeScreen()),
              );
            }),
            _adminSubItem(Icons.payments_outlined, 'Payroll', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPayrollScreen()),
              );
            }),
            _adminSubCategory(
              title: 'Approvals',
              icon: Icons.assignment_turned_in_outlined,
              isExpanded: _expandedSubSections.contains('approvals'),
              onToggle: () => _toggleSubSection('approvals'),
              children: [
                _adminSubItem(Icons.circle_outlined, 'Leave', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLeaveApprovalsScreen()));
                }, isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Permission', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPermissionApprovalsScreen()));
                }, isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Punch', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPunchApprovalsScreen()));
                }, isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Fine', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminFineApprovalsScreen()));
                }, isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Reimbursement', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminReimbursementApprovalsScreen()));
                }, isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Payslip Requests', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPayslipApprovalsScreen()));
                }, isNested: true),
              ],
            ),
            _adminSubCategory(
              title: 'Settings',
              icon: Icons.settings_outlined,
              isExpanded: _expandedSubSections.contains('staff_settings'),
              onToggle: () => _toggleSubSection('staff_settings'),
              children: [
                _adminSubItem(Icons.circle_outlined, 'Attendance Templates', () => Navigator.pop(context), isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Holiday Templates', () => Navigator.pop(context), isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Leave Templates', () => Navigator.pop(context), isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Shift Templates', () => Navigator.pop(context), isNested: true),
                _adminSubItem(Icons.circle_outlined, 'Weekly Off Templates', () => Navigator.pop(context), isNested: true),
              ],
            ),
            _adminSubItem(Icons.notifications_outlined, 'Notifications', () => Navigator.pop(context)),
          ],
        ),

        const SizedBox(height: 6),

        // ── SECTION: HRMS GEO ──
        _buildAdminCategory(
          title: 'HRMS GEO',
          icon: Icons.public_rounded,
          isExpanded: _expandedSections.contains('geo'),
          onToggle: () => _toggleSection('geo'),
          children: [
            _adminSubItem(Icons.dashboard_outlined, 'Dashboard', () => Navigator.pop(context)),
            _adminSubItem(Icons.storefront_outlined, 'Customer', () => Navigator.pop(context)),
            _adminSubItem(Icons.currency_rupee_rounded, 'Travel Allowance', () => Navigator.pop(context)),
            _adminSubItem(Icons.task_alt_rounded, 'Tasks', () {
              Navigator.pop(context);
              Future.microtask(() => _push(const MyTasksScreen(dashboardTabIndex: 1)));
            }),
            _adminSubItem(Icons.explore_outlined, 'Tracking', () => Navigator.pop(context)),
            _adminSubItem(Icons.tune_rounded, 'Settings', () => Navigator.pop(context)),
          ],
        ),

        const SizedBox(height: 12),
        const Divider(height: 1, color: Color(0xFF27272A)),
        const SizedBox(height: 8),

        _item(
          Icons.person_outline_rounded,
          'Profile',
          () {
            Navigator.pop(context);
            Future.microtask(() => _push(const ProfileScreen(dashboardTabIndex: 3)));
          },
          isDark: true,
        ),
        _item(
          Icons.settings_outlined,
          'App Settings',
          () {
            Navigator.pop(context);
            Future.microtask(() => _push(const SettingsScreen()));
          },
          isDark: true,
        ),
      ],
    );
  }

  /// Solid Amber Active Group Header matching Web Screenshots
  Widget _buildAdminCategory({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isExpanded ? const Color(0xFFEFAA1F) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: isExpanded ? Colors.black : const Color(0xFFA1A1AA),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isExpanded ? FontWeight.w900 : FontWeight.w600,
                      color: isExpanded ? Colors.black : const Color(0xFFF4F4F5),
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded,
                  size: 19,
                  color: isExpanded ? Colors.black : const Color(0xFF71717A),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4, bottom: 6),
            child: Column(children: children),
          ),
      ],
    );
  }

  Widget _adminSubCategory({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: const Color(0xFFA1A1AA)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFD4D4D8)),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded,
                  size: 16,
                  color: const Color(0xFF71717A),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(children: children),
          ),
      ],
    );
  }

  Widget _adminSubItem(IconData icon, String title, VoidCallback onTap, {bool isSelected = false, bool isNested = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: isNested ? 6 : 8),
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFAA1F).withValues(alpha: 0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: const Color(0xFFEFAA1F).withValues(alpha: 0.40)) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: isNested ? 7 : 16,
              color: isSelected ? const Color(0xFFEFAA1F) : const Color(0xFFA1A1AA),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: isNested ? 12 : 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  color: isSelected ? const Color(0xFFEFAA1F) : const Color(0xFFE4E4E7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String title, VoidCallback onTap, {Color? color, bool isDark = false}) {
    final fg = color ?? (isDark ? const Color(0xFFE4E4E7) : AppColors.textPrimary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
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

  /// Amber rounded header card matching Figma exactly.
  Widget _buildHeaderCard() {
    final extractedName = AuthService.extractNameFromMap(_userData);
    final name = extractedName.isNotEmpty ? extractedName : (_userData?['name'] ?? 'Employee');
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
                            maxLines: 2,
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
}
