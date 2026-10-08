// hrms/lib/widgets/app_drawer.dart
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/auth/auth_bloc.dart';
import '../config/app_colors.dart';
import '../config/app_text_styles.dart';
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
import '../screens/admin/geo/admin_field_tracking_screen.dart';
import '../screens/admin/geo/admin_travel_allowance_screen.dart';
import '../screens/admin/geo/admin_geo_settings_screen.dart';
import '../screens/admin/announcements/admin_announcements_screen.dart';
import '../screens/performance/performance_module_screen.dart';
import '../screens/lms_admin/lms_admin_shell_screen.dart';
import '../screens/assets/assets_all_list_screen.dart';
import '../screens/grievance/grievance_shell_screen.dart';
import '../screens/admin/approvals/admin_leave_approvals_screen.dart';
import '../screens/admin/approvals/admin_permission_approvals_screen.dart';
import '../screens/admin/approvals/admin_punch_approvals_screen.dart';
import '../screens/admin/approvals/admin_fine_approvals_screen.dart';
import '../screens/admin/approvals/admin_reimbursement_approvals_screen.dart';
import '../screens/admin/approvals/admin_payslip_approvals_screen.dart';
import '../screens/admin/dashboard/admin_dashboard_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/loans/loans_screen.dart';
import '../screens/admin/loans/admin_loans_screen.dart';
import '../screens/admin/recruitment/admin_job_openings_screen.dart';
import '../screens/admin/recruitment/admin_candidates_screen.dart';
import '../screens/admin/recruitment/admin_appointments_screen.dart';
import '../screens/admin/recruitment/admin_interview_flow_screen.dart';
import '../screens/admin/recruitment/admin_interview_rounds_screen.dart';
import '../screens/admin/recruitment/admin_selected_rejected_screen.dart';
import '../screens/admin/recruitment/admin_offer_letter_screen.dart';
import '../screens/admin/recruitment/admin_verifications_screen.dart';
import '../screens/interaction/staff/staff_interaction_screen.dart';
import '../screens/announcements/announcements_screen.dart';
import '../screens/admin/staff/admin_import_staff_screen.dart';
import '../screens/admin/recruitment/admin_recruitment_analytics_screen.dart';
import '../screens/admin/recruitment/admin_communications_screen.dart';
import '../screens/admin/recruitment/admin_candidate_disposition_screen.dart';
import '../screens/admin/salary/admin_salary_overview_screen.dart';
import '../screens/admin/salary/admin_salary_structure_screen.dart';
import '../screens/admin/salary/admin_incentive_screen.dart';
import '../screens/admin/exit_process/admin_exit_process_screen.dart';
import '../screens/admin/settings/admin_settings_hub_screen.dart';
import '../screens/admin/settings/salary_settings_screen.dart';
import '../screens/admin/settings/shift_roster_screen.dart';
import '../screens/admin/settings/settings_reports_screen.dart';
import '../screens/admin/settings/company_master_screen.dart';
import '../screens/admin/settings/module_access_screen.dart';
import '../screens/admin/geo/admin_geo_tasks_screen.dart';
import '../screens/admin/geo/admin_geo_customers_screen.dart';
import '../screens/admin/geo/admin_geo_tracking_summary_screen.dart';
import '../screens/admin/loans/admin_salary_advance_screen.dart';
import '../screens/admin/loans/admin_loan_disbursement_screen.dart';
import '../screens/admin/loans/admin_payroll_recovery_screen.dart';
import '../screens/admin/loans/admin_loan_settings_screen.dart';
import '../screens/admin/celebration/admin_celebration_screen.dart';
import '../screens/admin/integrations/admin_integrations_screen.dart';

class AppDrawer extends StatefulWidget {
  final int? currentIndex;
  final void Function(int index)? onNavigateToIndex;

  const AppDrawer({super.key, this.currentIndex, this.onNavigateToIndex});

  /// Clears the admin menu's remembered sections and last opened screen.
  static void resetMenuMemory() => _AppDrawerState.resetMenuMemory();

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Map<String, dynamic>? _userData;
  // Whether the header avatar must be flipped 180° on display (legacy selfies were
  // stored upside-down). Detected from the image via ML Kit, same as the dashboard.
  bool _avatarNeedsFlip = false;
  // No section expanded by default — the drawer opens fully collapsed.
  // Admin menu memory. Static because every screen builds its own drawer: reopening the
  // menu shows the sections that were open and highlights the screen last opened from it.
  static final Set<String> _expandedSections = {};
  static final Set<String> _expandedSubSections = {};
  static String? _activeMenuKey;
  final GlobalKey _activeItemKey = GlobalKey();
  // Admin drawer menu search.
  final TextEditingController _menuSearch = TextEditingController();
  String _menuQuery = '';

  bool get _isAdmin {
    final role = (_userData?['role'] ?? '').toString().toLowerCase();
    final staffType = (_userData?['staffType'] ?? '').toString().toLowerCase();
    return role == 'admin' ||
        role == 'superadmin' ||
        role == 'hr' ||
        role == 'hr_admin' ||
        staffType == 'admin';
  }

  /// Forgets the open sections and last opened screen (on logout).
  static void resetMenuMemory() {
    _expandedSections.clear();
    _expandedSubSections.clear();
    _activeMenuKey = null;
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
    // Bring the last opened screen into view once the menu has laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeItemKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 250));
      }
    });
  }

  @override
  void dispose() {
    _menuSearch.dispose();
    super.dispose();
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
        DashboardScreen.goToTab(context, index);
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
    // Logout: unsent points must not upload later under someone else's login.
    resetMenuMemory();
    await PresenceTrackingService().stopTracking(discardOfflineQueue: true);
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
    if (_isAdmin) {
      return Drawer(
        width: MediaQuery.of(context).size.width * 0.84,
        backgroundColor: _aBg,
        surfaceTintColor: Colors.transparent,
        child: SafeArea(child: _buildAdminDrawer()),
      );
    }
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.80,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Card ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _buildHeaderCard(),
            ),
            const SizedBox(height: 4),

            // ── Nav Items ──
            Expanded(child: _buildEmployeeNavList()),

            // ── Logout ──
            const Divider(height: 1, color: Color(0xFFECEEF1)),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: _item(
                Icons.logout_rounded,
                'Logout',
                () => _logout(context),
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Standard Employee Drawer List
  Widget _buildEmployeeNavList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(
            'NAVIGATION',
            style: AppTextStyles.sectionLabel,
          ),
        ),
        _item(Icons.dashboard_rounded, 'Dashboard', () => _navigateToTab(0)),
        _item(Icons.calendar_month_rounded, 'Attendance', () => _navigateToTab(4)),
        _item(Icons.fact_check_rounded, 'Requests', () => _navigateToTab(1)),
        _item(Icons.account_balance_outlined, 'Loans', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const LoansScreen()));
        }),
        _item(Icons.assignment_turned_in_rounded, 'GEOtasks', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const MyTasksScreen(dashboardTabIndex: 1)));
        }),
        _item(Icons.schedule_rounded, 'Overtime', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const OvertimeScreen()));
        }),
        _item(Icons.forum_rounded, 'Interaction', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const StaffInteractionScreen()));
        }),
        _item(Icons.campaign_rounded, 'Announcements', () {
          Navigator.pop(context);
          Future.microtask(() => _push(const AnnouncementsScreen()));
        }),
        const SizedBox(height: 8),
        const Divider(height: 1, indent: 12, endIndent: 12, color: Color(0xFFECEEF1)),
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

  // ───────────────────────── Admin drawer ─────────────────────────

  static const _aBg = Color(0xFF131316);
  static const _aSurface = Color(0xFF1C1C21);
  static const _aBorder = Color(0xFF2A2A31);
  static const _aAccent = Color(0xFFF9B824);
  static const _aText = Color(0xFFF4F4F5);
  static const _aSubText = Color(0xFFD4D4D8);
  static const _aMuted = Color(0xFFA1A1AA);
  static const _aDim = Color(0xFF6B6B75);
  static const _aDanger = Color(0xFFEF4444);

  /// Closes the drawer and opens [screen] on top of the dashboard root.
  void _open(Widget screen) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (r) => r.isFirst,
    );
  }

  /// Identifies a menu screen by the groups above it plus its title.
  String _menuKey(_NavNode node, List<String> ancestors) => [...ancestors, node.title].join('/');

  /// Opens a menu screen and remembers it: its sections stay open and it is highlighted
  /// the next time the menu opens.
  void _openLeaf(_NavNode node, List<String> ancestors) {
    _activeMenuKey = _menuKey(node, ancestors);
    _expandedSections.clear();
    if (ancestors.isNotEmpty) _expandedSections.add(ancestors.first);
    _expandedSubSections.addAll(ancestors.skip(1));
    if (node.isHome) {
      // Back to a fresh dashboard as the only screen, rather than one more on the stack.
      final nav = Navigator.of(context);
      nav.pop();
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => node.builder!()), (_) => false);
      return;
    }
    _open(node.builder!());
  }

  /// Admin menu, same entries as the web admin sidebar.
  List<_NavGroup> get _adminMenu => [
        _NavGroup('Home', [
          _NavNode.leaf('Dashboard', Icons.space_dashboard_rounded, () => const AdminDashboardScreen(), isHome: true),
        ]),
        _NavGroup('Workspace', [
          _NavNode.group('recruitment', 'Recruitment', Icons.work_outline_rounded, [
            _NavNode.leaf('Analytics', Icons.insights_outlined, () => const AdminRecruitmentAnalyticsScreen()),
            _NavNode.leaf('Job Openings', Icons.list_alt_rounded, () => const AdminJobOpeningsScreen()),
            _NavNode.leaf('Candidates', Icons.people_outline_rounded, () => const AdminCandidatesScreen()),
            _NavNode.leaf('Appointments', Icons.event_outlined, () => const AdminAppointmentsScreen()),
            _NavNode.group('interview_process', 'Interview Process', Icons.account_tree_outlined, [
              _NavNode.leaf('Interview Flow', Icons.alt_route_rounded, () => const AdminInterviewFlowScreen()),
              _NavNode.leaf('Rounds', Icons.repeat_rounded, () => const AdminInterviewRoundsScreen()),
              _NavNode.leaf('Selected / Rejected', Icons.rule_rounded, () => const AdminSelectedRejectedScreen()),
            ]),
            _NavNode.leaf('Offer Letter', Icons.mail_outline_rounded, () => const AdminOfferLetterScreen()),
            _NavNode.group('verification', 'Verification', Icons.verified_user_outlined, [
              _NavNode.leaf('Document Verification', Icons.description_outlined, () => const AdminVerificationsScreen()),
              _NavNode.leaf('Convert to Staff', Icons.person_add_alt_1_outlined, () => const AdminVerificationsScreen(initialTab: 2)),
              _NavNode.leaf('Joining', Icons.how_to_reg_outlined, () => const AdminVerificationsScreen(initialTab: 3)),
            ]),
            _NavNode.leaf('Communications', Icons.chat_outlined, () => const AdminCommunicationsScreen()),
            _NavNode.leaf('Candidate Disposition', Icons.person_off_outlined, () => const AdminCandidateDispositionScreen()),
          ]),
          _NavNode.group('staff', 'Staff', Icons.groups_rounded, [
            _NavNode.leaf('Staff List', Icons.badge_outlined, () => const AdminStaffListScreen()),
            _NavNode.leaf('Import Staff', Icons.upload_file_outlined, () => const AdminImportStaffScreen()),
            _NavNode.leaf('Attendance', Icons.calendar_month_outlined, () => const AdminAttendanceScreen()),
            _NavNode.leaf('Overtime', Icons.schedule_rounded, () => const AdminOvertimeScreen()),
            _NavNode.leaf('GEOtasks', Icons.assignment_outlined, () => const AdminGeoTasksScreen()),
            _NavNode.group('salary', 'Salary', Icons.payments_outlined, [
              _NavNode.leaf('Overview', Icons.summarize_outlined, () => const AdminSalaryOverviewScreen()),
              _NavNode.leaf('Structure', Icons.account_balance_wallet_outlined, () => const AdminSalaryStructureScreen()),
              _NavNode.leaf('Payroll', Icons.receipt_long_outlined, () => const AdminPayrollScreen()),
              _NavNode.leaf('Incentive', Icons.emoji_events_outlined, () => const AdminIncentiveScreen()),
            ]),
            _NavNode.leaf('Exit Process', Icons.exit_to_app_rounded, () => const AdminExitProcessScreen()),
            _NavNode.group('approvals', 'Approvals', Icons.assignment_turned_in_outlined, [
              _NavNode.leaf('Leave', Icons.beach_access_outlined, () => const AdminLeaveApprovalsScreen()),
              _NavNode.leaf('Permission', Icons.more_time_rounded, () => const AdminPermissionApprovalsScreen()),
              _NavNode.leaf('Punch', Icons.fingerprint_rounded, () => const AdminPunchApprovalsScreen()),
              _NavNode.leaf('Fine', Icons.gavel_rounded, () => const AdminFineApprovalsScreen()),
              _NavNode.leaf('Reimbursement', Icons.receipt_outlined, () => const AdminReimbursementApprovalsScreen()),
              _NavNode.leaf('Payslip Requests', Icons.request_page_outlined, () => const AdminPayslipApprovalsScreen()),
              _NavNode.leaf('Loans', Icons.account_balance_outlined, () => const AdminLoansScreen()),
            ]),
            _NavNode.group('staff_settings', 'Settings', Icons.settings_outlined, [
              _NavNode.leaf('All Settings', Icons.apps_rounded, () => const AdminSettingsHubScreen()),
              _NavNode.leaf('Attendance', Icons.event_available_outlined, () => const AttendanceSettingsScreen()),
              _NavNode.leaf('Salary', Icons.price_change_outlined, () => const SalarySettingsScreen()),
              _NavNode.leaf('Business', Icons.business_outlined, () => const CompanyMasterScreen()),
              _NavNode.leaf('Shift Roster', Icons.view_week_outlined, () => const ShiftRosterScreen()),
              _NavNode.leaf('Module Access', Icons.lock_person_outlined, () => const ModuleAccessScreen()),
              _NavNode.leaf('Reports', Icons.assessment_outlined, () => const SettingsReportsScreen()),
            ]),
            _NavNode.leaf('Notifications', Icons.notifications_outlined, () => const NotificationsScreen()),
          ]),
          _NavNode.group('geo', 'HRMS GEO', Icons.public_rounded, [
            _NavNode.leaf('Field Tracking', Icons.my_location_rounded, () => const AdminFieldTrackingScreen()),
            _NavNode.leaf('Travel Allowance', Icons.currency_rupee_rounded, () => const AdminTravelAllowanceScreen()),
            _NavNode.leaf('Employee Tracking', Icons.people_alt_outlined, () => const AdminGeoTrackingSummaryScreen()),
            _NavNode.leaf('Tasks', Icons.task_alt_rounded, () => const AdminGeoTasksScreen()),
            _NavNode.leaf('Customers', Icons.storefront_outlined, () => const AdminGeoCustomersScreen()),
            _NavNode.leaf('Settings', Icons.tune_rounded, () => const AdminGeoSettingsScreen()),
          ]),
          _NavNode.group('loans', 'Loans', Icons.account_balance_outlined, [
            _NavNode.leaf('Dashboard & Requests', Icons.dashboard_outlined, () => const AdminLoansScreen()),
            _NavNode.leaf('Salary Advance', Icons.bolt_outlined, () => const AdminSalaryAdvanceScreen()),
            _NavNode.leaf('Disbursement', Icons.send_outlined, () => const AdminLoanDisbursementScreen()),
            _NavNode.leaf('Payroll Recovery', Icons.replay_outlined, () => const AdminPayrollRecoveryScreen()),
            _NavNode.leaf('Loan Policies', Icons.policy_outlined,
                () => const AdminLoanSettingsScreen(group: LoanSettingsGroup.policies)),
            _NavNode.leaf('Configuration', Icons.tune_rounded,
                () => const AdminLoanSettingsScreen(group: LoanSettingsGroup.configuration)),
          ]),
        ]),
        _NavGroup('Modules', [
          _NavNode.leaf('Performance', Icons.trending_up_rounded, () => const PerformanceModuleScreen()),
          _NavNode.leaf('LMS', Icons.school_outlined, () => const LmsAdminShellScreen()),
          _NavNode.leaf('Interaction', Icons.forum_outlined, () => const StaffInteractionScreen()),
          _NavNode.leaf('Asset Management', Icons.devices_other_outlined, () => const AssetsAllListScreen()),
          _NavNode.leaf('Grievance', Icons.report_gmailerrorred_outlined, () => const GrievanceShellScreen()),
          _NavNode.leaf('Announcements', Icons.campaign_rounded, () => const AdminAnnouncementsScreen()),
          _NavNode.leaf('Celebration', Icons.celebration_outlined, () => const AdminCelebrationScreen()),
          _NavNode.leaf('Integrations', Icons.extension_outlined, () => const AdminIntegrationsScreen()),
          _NavNode.leaf('Notifications', Icons.notifications_outlined, () => const NotificationsScreen()),
        ]),
        _NavGroup('Account', [
          _NavNode.leaf('Profile', Icons.person_outline_rounded, () => const ProfileScreen(dashboardTabIndex: 3)),
          _NavNode.leaf('App Settings', Icons.settings_outlined, () => const SettingsScreen()),
        ]),
      ];

  Widget _buildAdminDrawer() {
    final query = _menuQuery.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Brand bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 6, 0),
          child: Row(
            children: [
              Image.asset('assets/images/ektaHr_final.png', height: 40, fit: BoxFit.contain),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: _aMuted, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: _buildAdminProfileCard(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: _buildMenuSearch(),
        ),
        Expanded(
          child: query.isEmpty ? _buildAdminMenuList() : _buildMenuSearchResults(query),
        ),
        _buildAdminLogout(),
      ],
    );
  }

  Widget _buildAdminProfileCard() {
    final extracted = AuthService.extractNameFromMap(_userData);
    final name = extracted.isNotEmpty ? extracted : (_userData?['name'] ?? 'Admin').toString();
    final role = (_userData?['role'] ?? 'admin').toString();
    final roleLabel = role.isEmpty ? 'Admin' : role[0].toUpperCase() + role.substring(1);
    final avatarUrl = (_userData?['avatar'] ?? _userData?['photoUrl'])?.toString().trim() ?? '';
    final showAvatar = avatarUrl.startsWith('http');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return _pressable(
      radius: 16,
      onTap: () => _open(const ProfileScreen(dashboardTabIndex: 3)),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF27272D), Color(0xFF1A1A1F)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _aBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [_aAccent, _aAccent.withValues(alpha: 0.25)]),
              ),
              // Flip legacy (pre-fix, upside-down) seeded avatars 180°.
              child: RotatedBox(
                quarterTurns: (showAvatar && _avatarNeedsFlip) ? 2 : 0,
                child: CircleAvatar(
                  radius: 21,
                  backgroundColor: const Color(0xFF2E2A1F),
                  backgroundImage: showAvatar ? CachedNetworkImageProvider(avatarUrl) : null,
                  child: showAvatar
                      ? null
                      : Text(initial,
                          style: const TextStyle(color: _aAccent, fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _aText, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 12, color: _aAccent),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          roleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _aMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _aDim, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSearch() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _menuSearch,
        onChanged: (v) => setState(() => _menuQuery = v),
        style: const TextStyle(color: _aText, fontSize: 13.5),
        cursorColor: _aAccent,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search menu',
          hintStyle: const TextStyle(color: _aDim, fontSize: 13.5),
          prefixIcon: const Icon(Icons.search_rounded, color: _aDim, size: 20),
          suffixIcon: _menuQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 18, color: _aMuted),
                  onPressed: () {
                    _menuSearch.clear();
                    setState(() => _menuQuery = '');
                  },
                ),
          filled: true,
          fillColor: _aSurface,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _aBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _aAccent.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminMenuList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        for (final group in _adminMenu) ...[
          _menuSectionLabel(group.label),
          for (final node in group.items) node.isGroup ? _navCategory(node) : _navTopItem(node),
        ],
      ],
    );
  }

  Widget _menuSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.sectionLabel.copyWith(color: _aDim),
      ),
    );
  }

  Widget _iconTile(IconData icon, {bool active = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: active ? _aAccent : _aSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? _aAccent : _aBorder),
      ),
      child: Icon(icon, size: 18, color: active ? AppColors.ink : _aMuted),
    );
  }

  Widget _navTopItem(_NavNode node) {
    // Nothing opened from the menu yet: the admin is on the dashboard they landed on.
    final active = _activeMenuKey == _menuKey(node, const []) || (_activeMenuKey == null && node.isHome);
    return KeyedSubtree(
      key: active ? _activeItemKey : null,
      child: _pressable(
        onTap: () => _openLeaf(node, const []),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              _iconTile(node.icon, active: active),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  node.title,
                  style: TextStyle(
                    color: active ? _aAccent : _aSubText,
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navCategory(_NavNode node) {
    final open = _expandedSections.contains(node.id);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: open ? _aSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: open ? _aBorder : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pressable(
            radius: 14,
            onTap: () => _toggleSection(node.id!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  _iconTile(node.icon, active: open),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      node.title,
                      style: TextStyle(
                        color: open ? _aText : _aSubText,
                        fontSize: 14,
                        fontWeight: open ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${node.leafCount}',
                    style: const TextStyle(color: _aDim, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right_rounded, size: 20, color: open ? _aAccent : _aDim),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(22, 2, 6, 8),
                    child: _navTree(node.children, [node.id!]),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// Child items with a vertical guide line on the left.
  Widget _navTree(List<_NavNode> nodes, List<String> ancestors) {
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: _aBorder, width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in nodes) n.isGroup ? _navSubCategory(n, ancestors) : _navLeaf(n, ancestors),
        ],
      ),
    );
  }

  Widget _navLeaf(_NavNode node, List<String> ancestors) {
    final active = _activeMenuKey == _menuKey(node, ancestors);
    return KeyedSubtree(
      key: active ? _activeItemKey : null,
      child: _pressable(
        radius: 10,
        onTap: () => _openLeaf(node, ancestors),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: active ? _aAccent.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? _aAccent.withValues(alpha: 0.45) : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(node.icon, size: 17, color: active ? _aAccent : _aMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  node.title,
                  style: TextStyle(
                    color: active ? _aAccent : _aSubText,
                    fontSize: 13.2,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (active) const Icon(Icons.circle, size: 7, color: _aAccent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navSubCategory(_NavNode node, List<String> ancestors) {
    final open = _expandedSubSections.contains(node.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pressable(
          radius: 10,
          onTap: () => _toggleSubSection(node.id!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: [
                Icon(node.icon, size: 17, color: open ? _aAccent : _aMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    node.title,
                    style: TextStyle(
                      color: open ? _aText : _aSubText,
                      fontSize: 13.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.chevron_right_rounded, size: 18, color: _aDim),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: _navTree(node.children, [...ancestors, node.id!]),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildMenuSearchResults(String query) {
    final hits = <_MenuHit>[];
    void walk(List<_NavNode> nodes, String path, List<String> ancestors) {
      for (final n in nodes) {
        if (n.isGroup) {
          walk(n.children, path.isEmpty ? n.title : '$path › ${n.title}', [...ancestors, n.id!]);
        } else if (n.title.toLowerCase().contains(query) || path.toLowerCase().contains(query)) {
          hits.add(_MenuHit(n, path, ancestors));
        }
      }
    }

    for (final group in _adminMenu) {
      walk(group.items, '', const []);
    }

    if (hits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No menu items match', style: TextStyle(color: _aDim, fontSize: 13)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        for (final hit in hits)
          _pressable(
            onTap: () => _openLeaf(hit.node, hit.ancestors),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(
                children: [
                  _iconTile(hit.node.icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hit.node.title,
                          style: const TextStyle(color: _aText, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        if (hit.path.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(hit.path, style: const TextStyle(color: _aDim, fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAdminLogout() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _aBorder)),
      ),
      child: Material(
        color: _aDanger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _logout(context),
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, color: _aDanger, size: 18),
                SizedBox(width: 8),
                Text('Logout', style: TextStyle(color: _aDanger, fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pressable({required VoidCallback onTap, required Widget child, double radius = 12}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: _aAccent.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: child,
      ),
    );
  }

  Widget _item(IconData icon, String title, VoidCallback onTap, {Color? color, bool isDark = false}) {
    final fg = color ?? (isDark ? const Color(0xFFE4E4E7) : AppColors.textPrimary);
    // Icon tile: tinted square behind the icon (gold tint for regular items,
    // the item's own colour tint for coloured items such as Logout).
    final tileFg = color ?? (isDark ? fg : AppColors.primaryText);
    final tileBg = color != null
        ? color.withValues(alpha: 0.10)
        : (isDark ? Colors.white.withValues(alpha: 0.06) : AppColors.primary.withValues(alpha: 0.12));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: tileFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.label.copyWith(
                  fontSize: 14.5,
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
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
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onPrimary)),
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
                            style: AppTextStyles.headingMedium.copyWith(
                              color: AppColors.onPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 19,
                              height: 1.15,
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
                                color: Colors.white.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                role,
                                style: TextStyle(
                                  color: AppColors.onPrimary,
                                  fontSize: 12,
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
                    color: AppColors.onPrimary.withValues(alpha: 0.14),
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
        Icon(icon, size: 14, color: AppColors.onPrimary.withValues(alpha: 0.8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.onPrimary.withValues(alpha: 0.9),
              fontSize: 12.5,
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

/// A labelled block of admin menu entries (Workspace / Modules / Account).
class _NavGroup {
  final String label;
  final List<_NavNode> items;

  const _NavGroup(this.label, this.items);
}

/// An admin menu entry: either a screen ([builder]) or an expandable group.
class _NavNode {
  final String? id;
  final String title;
  final IconData icon;
  final Widget Function()? builder;
  final List<_NavNode> children;

  /// The admin home screen: opening it replaces the whole stack instead of stacking.
  final bool isHome;

  const _NavNode.leaf(this.title, this.icon, this.builder, {this.isHome = false})
      : id = null,
        children = const [];

  const _NavNode.group(this.id, this.title, this.icon, this.children)
      : builder = null,
        isHome = false;

  bool get isGroup => children.isNotEmpty;

  int get leafCount =>
      isGroup ? children.fold(0, (sum, c) => sum + c.leafCount) : 1;
}

/// A menu screen matched by the menu search, with where it sits in the menu.
class _MenuHit {
  final _NavNode node;
  final String path;
  final List<String> ancestors;

  const _MenuHit(this.node, this.path, this.ancestors);
}
