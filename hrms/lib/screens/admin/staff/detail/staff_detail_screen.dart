// lib/screens/admin/staff/detail/staff_detail_screen.dart
//
// Admin view of one staff member - the mobile counterpart of the web
// "features/admin/staff/staff/pages/staff.tsx": a header with activate /
// deactivate, and one tab per area of the staff record.
import 'package:flutter/material.dart';

import '../../../../config/app_colors.dart';
import '../../../../services/admin_staff_detail_service.dart';
import 'staff_detail_common.dart';
import 'tabs/staff_attendance_tab.dart';
import 'tabs/staff_documents_tab.dart';
import 'tabs/staff_profile_tab.dart';
import 'tabs/staff_requests_tab.dart';
import 'tabs/staff_salary_overview_tab.dart';
import 'tabs/staff_salary_structure_tab.dart';
import 'tabs/staff_shifts_tab.dart';

class StaffDetailScreen extends StatefulWidget {
  const StaffDetailScreen({super.key, required this.staffId});

  final String staffId;

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  final _service = AdminStaffDetailService();

  Map<String, dynamic>? _staff;
  bool _loading = true;
  String? _error;
  bool _statusBusy = false;

  /// Whether anything on the record changed, so the list can refresh on return.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final staff = await _service.getStaff(widget.staffId);
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sdErrorText(e);
        _loading = false;
      });
    }
  }

  void _onStaffUpdated(Map<String, dynamic> updated) {
    if (updated.isEmpty) return;
    setState(() {
      _staff = {...?_staff, ...updated};
      _changed = true;
    });
  }

  bool get _isActive => sdStr(_staff?['status'], 'Active').toLowerCase() == 'active';

  Future<void> _toggleStatus() async {
    final staff = _staff;
    if (staff == null) return;
    final activate = !_isActive;
    final name = sdStaffName(staff);
    final ok = await sdConfirm(
      context,
      title: activate ? 'Activate Staff Profile' : 'Deactivate Staff Profile',
      message: activate
          ? 'Are you sure you want to activate the profile for $name? This will restore access to all systems.'
          : 'Are you sure you want to deactivate the profile for $name? This will suspend access to all systems.',
      confirmText: activate ? 'Activate' : 'Deactivate',
      danger: !activate,
    );
    if (!ok || !mounted) return;

    setState(() => _statusBusy = true);
    try {
      if (activate) {
        // Same seat check the web runs before activating: any plan already at its seat limit
        // blocks the activation (the backend repeats the check).
        final sub = await _service.getSubscription();
        final plans = (sub?['planDetails'] as List?) ?? const [];
        final seatFull = plans.whereType<Map>().any((p) {
          final total = sdNum(p['totalSeat']);
          final active = (p['activeUsers'] as List?)?.length ?? 0;
          return total > 0 && active >= total;
        });
        if (seatFull) {
          if (!mounted) return;
          setState(() => _statusBusy = false);
          sdShowError(context, StaffDetailApiException('seat has been full please contact the admistrator'));
          return;
        }
      }
      final updated = await _service.setActive(widget.staffId, activate);
      if (!mounted) return;
      setState(() {
        _staff = {...staff, 'status': sdStr(updated['status'], activate ? 'Active' : 'Deactive')};
        _statusBusy = false;
        _changed = true;
      });
      sdShowSuccess(context, 'Status changed to ${_staff!['status']}.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusBusy = false);
      sdShowError(context, e);
    }
  }

  static const _tabs = <(String, IconData)>[
    ('Profile', Icons.person_outline_rounded),
    ('Attendance', Icons.access_time_rounded),
    ('Salary Overview', Icons.currency_rupee_rounded),
    ('Salary Structure', Icons.description_outlined),
    ('Leaves', Icons.event_note_outlined),
    ('Permissions', Icons.key_outlined),
    ('Shifts', Icons.calendar_month_outlined),
    ('Documents', Icons.folder_open_outlined),
    ('Reimbursement', Icons.receipt_long_outlined),
    ('Payslip Requests', Icons.request_page_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: DefaultTabController(
        length: _tabs.length,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(_changed),
            ),
            title: const Text('Staff Details'),
            actions: [
              if (_staff != null)
                PopupMenuButton<String>(
                  enabled: !_statusBusy,
                  tooltip: 'More options',
                  icon: _statusBusy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.more_vert_rounded),
                  onSelected: (_) => _toggleStatus(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(_isActive ? 'Deactivate' : 'Activate',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _isActive ? AppColors.error : AppColors.success)),
                    ),
                  ],
                ),
            ],
          ),
          body: _loading
              ? const SdLoading()
              : _error != null
                  ? Center(child: SdErrorView(message: _error!, onRetry: _load))
                  : NestedScrollView(
                      headerSliverBuilder: (_, __) => [
                        SliverToBoxAdapter(child: _buildHeader()),
                        SliverPersistentHeader(pinned: true, delegate: _TabBarDelegate(_buildTabBar())),
                      ],
                      body: TabBarView(
                        children: [
                          _KeepAlive(child: StaffProfileTab(staff: _staff!, onUpdated: _onStaffUpdated)),
                          _KeepAlive(child: StaffAttendanceTab(staff: _staff!)),
                          _KeepAlive(child: StaffSalaryOverviewTab(staff: _staff!)),
                          _KeepAlive(child: StaffSalaryStructureTab(staff: _staff!, onStaffUpdated: _onStaffUpdated)),
                          _KeepAlive(child: StaffRequestsTab(staffId: widget.staffId, kind: StaffRequestKind.leave)),
                          _KeepAlive(
                              child: StaffRequestsTab(staffId: widget.staffId, kind: StaffRequestKind.permission)),
                          _KeepAlive(child: StaffShiftsTab(staff: _staff!)),
                          _KeepAlive(child: StaffDocumentsTab(staffId: widget.staffId)),
                          _KeepAlive(child: StaffRequestsTab(staffId: widget.staffId, kind: StaffRequestKind.expense)),
                          _KeepAlive(child: StaffRequestsTab(staffId: widget.staffId, kind: StaffRequestKind.payslip)),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  TabBar _buildTabBar() {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      labelColor: kSdInk,
      unselectedLabelColor: kSdMuted,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      tabs: [
        for (final t in _tabs)
          Tab(
            height: 46,
            child: Row(children: [Icon(t.$2, size: 18), const SizedBox(width: 6), Text(t.$1)]),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    final s = _staff!;
    final name = sdStaffName(s);
    final pic = sdStr(s['profilePic']);
    final status = sdStr(s['status'], 'Active');
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              backgroundImage: pic.startsWith('http') ? NetworkImage(pic) : null,
              child: pic.startsWith('http')
                  ? null
                  : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primaryText)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? '-' : name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kSdInk)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    SdPill(sdStr(s['employeeId'], '-'),
                        color: AppColors.warning, bg: AppColors.warningBg),
                    SdPill(sdStr(s['employmentType'], 'Full Time')),
                    if (sdStr(s['designation']).isNotEmpty) SdPill(sdStr(s['designation'])),
                    SdPill(status,
                        color: status == 'Active' ? AppColors.success : kSdMuted,
                        bg: status == 'Active' ? AppColors.successBg : kSdSoft),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height + 1;
  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: kSdHairline)),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => oldDelegate.tabBar != tabBar;
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
