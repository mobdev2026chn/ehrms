// lib/screens/admin/dashboard/admin_dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_dashboard_service.dart';
import '../../../services/api_client.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import '../staff/admin_staff_list_screen.dart';
import '../staff/admin_attendance_screen.dart';
import '../approvals/admin_approvals_screen.dart';
import '../../notifications/notifications_screen.dart';

/// Admin dashboard. Every figure comes from one call, GET /admin/dashboard, exactly as the
/// web admin dashboard does - so all panels describe the same instant.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminDashboardService _dashboardService = AdminDashboardService.instance;
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String? _error;
  AdminDashboardData? _data;
  String _attendancePeriod = 'Today'; // 'Today' | '7 Days'
  String _deptMetric = 'total'; // 'total' | 'onboarding' (Total / New Joiners, as on web)

  DashboardAttendance get _att => _attendancePeriod == 'Today'
      ? (_data?.today ?? const DashboardAttendance())
      : (_data?.week ?? const DashboardAttendance());

  /// Unread admin notifications for the bell (server `meta.unread`, as on web).
  int _unreadNotifications = 0;
  Timer? _notificationPoll;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _refreshNotificationBadge();
    // Same cadence as the web admin bell.
    _notificationPoll = Timer.periodic(const Duration(seconds: 15), (_) => _refreshNotificationBadge());
  }

  @override
  void dispose() {
    _notificationPoll?.cancel();
    super.dispose();
  }

  Future<void> _refreshNotificationBadge() async {
    try {
      final res = await _api.request<dynamic>('/admin/notifications', queryParameters: {'limit': 1});
      final meta = res.data is Map ? (res.data as Map)['meta'] : null;
      final unread = meta is Map ? (meta['unread'] as num?)?.toInt() : null;
      if (unread != null && mounted && unread != _unreadNotifications) {
        setState(() => _unreadNotifications = unread);
      }
    } catch (e) {
      // Background poll every 15s: a SnackBar here would repeat endlessly while offline,
      // so the badge keeps its last value and the failure is logged.
      debugPrint('Admin notification badge refresh failed: $e');
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    await _refreshNotificationBadge();
  }

  Future<void> _loadDashboardData({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final res = await _dashboardService.getDashboard();
    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _data = res['data'] as AdminDashboardData;
        _error = null;
        _isLoading = false;
      });
      return;
    }

    final message = (res['message'] ?? 'Failed to load dashboard').toString();
    setState(() {
      // A failed refresh keeps the last good figures; the full error page is only for
      // when there is nothing to show yet.
      if (_data == null) _error = message;
      _isLoading = false;
    });
    if (_data != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  void _openApprovals(String type) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AdminApprovalsScreen(initialType: type)))
        .then((_) => _loadDashboardData(showLoader: false));
  }

  void _openStaffList() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminStaffListScreen()));
  }

  static const Color _hairline = Color(0xFFECEEF1);
  static const Color _tileFill = Color(0xFFF7F8FA);

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hairline),
        boxShadow: kSoftCardShadow,
      );

  /// 40px rounded icon tile with a tinted background.
  Widget _iconTile(IconData icon, Color color, {Color? background, double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  /// Card header: icon tile + title (headingSmall) + optional caption.
  Widget _cardHeader(IconData icon, String title, {String? subtitle, Widget? below}) {
    return Row(
      children: [
        _iconTile(icon, AppColors.primaryText, background: AppColors.primary.withValues(alpha: 0.12)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.headingSmall,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
              if (below != null) ...[
                const SizedBox(height: 4),
                below,
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Two-option segmented toggle container.
  Widget _segmented(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _segment(String label, bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: isSelected
            ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))]
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Open menu',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'ADMIN PORTAL',
                style: AppTextStyles.sectionLabel.copyWith(
                  color: AppColors.primaryText,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () => _loadDashboardData(),
            tooltip: 'Refresh analytics',
          ),
          IconButton(
            tooltip: 'Notifications',
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text(_unreadNotifications > 99 ? '99+' : '$_unreadNotifications'),
              backgroundColor: AppColors.error,
              textColor: Colors.white,
              child: const Icon(Icons.notifications_none_rounded, size: 22),
            ),
            onPressed: _openNotifications,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _loadDashboardData(showLoader: false),
              color: AppColors.primary,
              child: _data == null ? _buildErrorState() : _buildContent(),
            ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, size: 30, color: AppColors.error),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Could not load dashboard',
          textAlign: TextAlign.center,
          style: AppTextStyles.headingSmall,
        ),
        const SizedBox(height: 4),
        Text(
          _error ?? 'Something went wrong',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: () => _loadDashboardData(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final generatedAt = _data?.generatedAt;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Title / Analytics Overview Banner ──
        Row(
          children: [
            _iconTile(
              Icons.auto_awesome_mosaic_rounded,
              AppColors.primaryText,
              background: AppColors.primary.withValues(alpha: 0.12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ANALYTICS OVERVIEW',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    generatedAt != null
                        ? "Here's what's happening in your organization today · Updated ${DateFormat('h:mm a').format(generatedAt.toLocal())}"
                        : "Here's what's happening in your organization today.",
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _buildAttendanceSummaryCard(),
        const SizedBox(height: 12),

        _buildPendingApprovalsCard(),
        const SizedBox(height: 12),

        _buildCelebrationsSection(),
        const SizedBox(height: 12),

        _buildOrganizationMetrics(),
        const SizedBox(height: 12),

        _buildDepartmentChart(),
        const SizedBox(height: 16),

        // ── Quick Action: Jump to Staff List ──
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openStaffList,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: Row(
                children: [
                  _iconTile(
                    Icons.badge_outlined,
                    AppColors.onPrimary,
                    background: AppColors.onPrimary.withValues(alpha: 0.12),
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Staff Directory',
                          style: AppTextStyles.headingSmall.copyWith(color: AppColors.onPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'View directory, filters, bulk import & template assignments',
                          style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: AppColors.onPrimary, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Attendance ──
  Widget _buildAttendanceSummaryCard() {
    final att = _att;
    final periodNote = _attendancePeriod == 'Today' ? 'active staff' : 'active staff · staff-days over 7 days';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            Icons.people_outline_rounded,
            'Attendance Summary',
            subtitle: '${att.activeStaff} $periodNote',
          ),
          const SizedBox(height: 12),
          _segmented([
            _periodToggleBtn('Today'),
            _periodToggleBtn('7 Days'),
          ]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _attendanceStatBox(
                  'Present',
                  '${att.present}',
                  Icons.check_circle_outline_rounded,
                  AppColors.success,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAttendanceScreen(initialFilter: 'Present'))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _attendanceStatBox(
                  'Late',
                  '${att.late}',
                  Icons.schedule_rounded,
                  AppColors.warning,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAttendanceScreen(initialFilter: 'Late'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _attendanceStatBox(
                  'Absent',
                  '${att.absent}',
                  Icons.cancel_outlined,
                  AppColors.error,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAttendanceScreen(initialFilter: 'Absent'))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _attendanceStatBox(
                  'Pending / not marked',
                  '${att.pending}',
                  Icons.pending_actions_rounded,
                  AppColors.textSecondary,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAttendanceScreen(initialFilter: 'Pending'))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _periodToggleBtn(String label) {
    final isSelected = _attendancePeriod == label;
    return GestureDetector(
      onTap: () => setState(() => _attendancePeriod = label),
      child: _segment(label, isSelected),
    );
  }

  Widget _attendanceStatBox(String label, String value, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _tileFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconTile(icon, color),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textCaption),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              style: AppTextStyles.headingLarge.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Approvals ──

  /// Backend queue key -> AdminApprovalsScreen tab type. Reimbursement is 'expense' there.
  static const Map<String, String> _approvalTypeForKey = {
    'punch': 'punch',
    'leave': 'leave',
    'permission': 'permission',
    'fine': 'fine',
    'reimbursement': 'expense',
    'payslip': 'payslip',
  };

  static const Map<String, IconData> _approvalIconForKey = {
    'leave': Icons.calendar_month_outlined,
    'permission': Icons.schedule_rounded,
    'fine': Icons.gavel_rounded,
    'reimbursement': Icons.receipt_long_outlined,
    'payslip': Icons.description_outlined,
  };

  Widget _buildPendingApprovalsCard() {
    final data = _data!;
    final punch = data.punch;
    final queues = data.queues;

    // Two per row, last one full width when odd - same layout as before, driven by the server list.
    final rows = <Widget>[];
    for (var i = 0; i < queues.length; i += 2) {
      final a = queues[i];
      final b = i + 1 < queues.length ? queues[i + 1] : null;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(
        b == null
            ? _approvalTile(a)
            : Row(
                children: [
                  Expanded(child: _approvalTile(a)),
                  const SizedBox(width: 8),
                  Expanded(child: _approvalTile(b)),
                ],
              ),
      );
    }

    final allClear = data.approvalsTotal == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            Icons.assignment_turned_in_outlined,
            'Pending Approvals',
            below: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: allClear ? AppColors.successBg : AppColors.warningBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                data.approvalsTotal == 0 ? 'All caught up' : '${data.approvalsTotal} actions needed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: allClear ? AppColors.success : AppColors.warning,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Featured: Pending Punch Approvals
          InkWell(
            onTap: () => _openApprovals('punch'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  _iconTile(
                    Icons.fingerprint_rounded,
                    AppColors.primaryText,
                    background: AppColors.primary.withValues(alpha: 0.16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      punch.label.isNotEmpty ? punch.label : 'Pending Punch Approvals',
                      style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${punch.count}',
                    style: AppTextStyles.headingLarge.copyWith(fontSize: 24, color: AppColors.primaryText),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.primaryText),
                ],
              ),
            ),
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...rows,
          ],
        ],
      ),
    );
  }

  Widget _approvalTile(DashboardQueue q) {
    final type = _approvalTypeForKey[q.key];
    return InkWell(
      onTap: type == null ? null : () => _openApprovals(type),
      borderRadius: BorderRadius.circular(12),
      child: _approvalItem(q.label, q.count, _approvalIconForKey[q.key] ?? Icons.pending_actions_rounded),
    );
  }

  Widget _approvalItem(String label, int count, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _tileFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _hairline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: AppTextStyles.headingSmall.copyWith(fontWeight: FontWeight.w700),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Celebrations ──
  String _whenLabel(DashboardCelebration c) {
    if (c.inDays == 0) return 'Today';
    if (c.inDays == 1) return 'Tomorrow';
    return 'In ${c.inDays} days';
  }

  Widget _celebrationCard({
    required IconData icon,
    required String title,
    required String emptyText,
    required List<DashboardCelebration> people,
    required bool showYears,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconTile(icon, AppColors.primaryText, background: AppColors.primary.withValues(alpha: 0.12)),
              const Spacer(),
              if (people.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${people.length}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryText),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppTextStyles.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          if (people.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            for (var i = 0; i < people.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _celebrationPerson(people[i], showYears),
            ],
        ],
      ),
    );
  }

  Widget _celebrationPerson(DashboardCelebration p, bool showYears) {
    final isToday = p.inDays == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.name,
                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isToday ? AppColors.primary : AppColors.inputFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _whenLabel(p),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isToday ? AppColors.onPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [if (p.employeeId.isNotEmpty) p.employeeId, p.department].join(' — '),
            style: AppTextStyles.caption.copyWith(fontSize: 11, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            showYears && p.years != null ? '${p.years} Year(s) — ${p.date}' : p.date,
            style: TextStyle(fontSize: 11, color: AppColors.primaryText, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildCelebrationsSection() {
    final data = _data!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _celebrationCard(
            icon: Icons.cake_outlined,
            title: 'Upcoming Birthdays (10 days)',
            emptyText: 'No birthdays\nin next 10 days',
            people: data.birthdays,
            showYears: false,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _celebrationCard(
            icon: Icons.military_tech_outlined,
            title: 'Work Anniversaries (10 days)',
            emptyText: 'No work anniversaries\nin next 10 days',
            people: data.anniversaries,
            showYears: true,
          ),
        ),
      ],
    );
  }

  // ── Totals ──
  Widget _metricCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
    required String note,
  }) {
    return InkWell(
      onTap: _openStaffList,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconTile(icon, iconColor, background: iconBg),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              style: AppTextStyles.displayLarge,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrganizationMetrics() {
    final data = _data!;
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            icon: Icons.people_alt_outlined,
            iconColor: AppColors.primaryText,
            iconBg: AppColors.primary.withValues(alpha: 0.12),
            label: 'Total Employees',
            value: '${data.totalEmployees}',
            note: 'Active: ${data.activeEmployees} • Inactive: ${data.inactiveEmployees}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            icon: Icons.person_add_alt_1_outlined,
            iconColor: AppColors.info,
            iconBg: AppColors.info.withValues(alpha: 0.12),
            label: 'Recent Onboardings',
            value: '${data.recentOnboardings}',
            note: 'Last 30 days',
          ),
        ),
      ],
    );
  }

  // ── By Department Bar Chart (Total / New Joiners, as on web) ──
  Widget _deptMetricBtn(String key, String label) {
    final isSelected = _deptMetric == key;
    return GestureDetector(
      onTap: () => setState(() => _deptMetric = key),
      child: _segment(label, isSelected),
    );
  }

  Widget _buildDepartmentChart() {
    final data = _data!;
    final depts = _deptMetric == 'total' ? data.deptTotal : data.deptOnboarding;
    final sum = depts.fold<int>(0, (s, e) => s + e.count);
    final maxCount = depts.fold<int>(1, (max, e) => e.count > max ? e.count : max);
    final subtitle = _deptMetric == 'total'
        ? '$sum active employees across ${depts.length} departments'
        : '$sum new joiners (last 30 days)';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.domain_rounded, 'By Department', subtitle: subtitle),
          const SizedBox(height: 12),
          _segmented([
            _deptMetricBtn('total', 'Total'),
            _deptMetricBtn('onboarding', 'New Joiners'),
          ]),
          const SizedBox(height: 20),
          if (depts.isEmpty)
            Container(
              height: 100,
              alignment: Alignment.center,
              child: Text(
                _deptMetric == 'total' ? 'No active employees yet' : 'No new joiners in the last 30 days',
                style: AppTextStyles.bodySmall,
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 64),
                child: SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: depts.map((d) {
                      final heightFactor = (d.count / maxCount).clamp(0.05, 1.0);
                      return InkWell(
                        onTap: _openStaffList,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 60,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${d.count}',
                                maxLines: 1,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryText),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 24,
                                height: 90 * heightFactor,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
                                  ),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                d.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                _deptMetric == 'total' ? 'Total Employees' : 'New Joiners',
                style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
