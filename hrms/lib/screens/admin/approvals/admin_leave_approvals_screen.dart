// lib/screens/admin/approvals/admin_leave_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'approval_shared_widgets.dart';

class AdminLeaveRecord {
  final String id;
  final String requestId;
  final String employeeId;
  final String name;
  final String department;
  final String designation;
  final String leaveType;
  final String leaveTypeCategory; // 'paid' | 'unpaid'
  final double days;
  final bool isHalfDay;
  final String halfDaySession; // '1st Half' | '2nd Half'
  final String startDate;
  final String endDate;
  String status; // 'Pending' | 'Approved' | 'Rejected'
  final String approvedBy;
  final String reason;
  final String remarks;

  AdminLeaveRecord({
    required this.id,
    required this.requestId,
    required this.employeeId,
    required this.name,
    required this.department,
    required this.designation,
    required this.leaveType,
    this.leaveTypeCategory = 'unpaid',
    required this.days,
    this.isHalfDay = false,
    this.halfDaySession = '',
    required this.startDate,
    required this.endDate,
    required this.status,
    this.approvedBy = 'Admin',
    this.reason = '',
    this.remarks = '',
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  /// One row of GET /admin/approvals/leave (`data.requests[]`).
  factory AdminLeaveRecord.fromJson(Map<String, dynamic> json) {
    final isHalf = json['isHalfDay'] == true;
    final daysVal = double.tryParse((json['days'] ?? (isHalf ? 0.5 : 1)).toString()) ?? (isHalf ? 0.5 : 1.0);
    final id = (json['id'] ?? json['_id'] ?? '').toString();

    return AdminLeaveRecord(
      id: id,
      requestId: (json['requestId'] ?? '').toString(),
      employeeId: (json['employeeId'] ?? '—').toString(),
      name: (json['name'] ?? 'Staff Member').toString(),
      department: (json['department'] ?? '—').toString(),
      designation: (json['designation'] ?? '—').toString(),
      leaveType: (json['leaveType'] ?? 'Leave').toString(),
      leaveTypeCategory: (json['leaveTypeCategory'] ?? 'paid').toString(),
      days: daysVal,
      isHalfDay: isHalf,
      halfDaySession: (json['halfDaySession'] ?? '').toString(),
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? json['startDate'] ?? '').toString(),
      status: (json['status'] ?? 'Pending').toString(),
      approvedBy: (json['approvedBy'] ?? '—').toString(),
      reason: (json['reason'] ?? '').toString(),
      remarks: (json['remarks'] ?? '').toString(),
    );
  }

  DateTime? get startDay {
    final d = DateTime.tryParse(startDate)?.toLocal();
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  DateTime? get endDay {
    final d = DateTime.tryParse(endDate)?.toLocal();
    return d == null ? startDay : DateTime(d.year, d.month, d.day);
  }

  String get dateLabel {
    final s = formatApprovalDate(startDate);
    final e = formatApprovalDate(endDate);
    return (e == s || e == '—') ? s : '$s → $e';
  }
}

class AdminLeaveApprovalsScreen extends StatefulWidget {
  const AdminLeaveApprovalsScreen({super.key});

  @override
  State<AdminLeaveApprovalsScreen> createState() => _AdminLeaveApprovalsScreenState();
}

class _AdminLeaveApprovalsScreenState extends State<AdminLeaveApprovalsScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminApprovalsService _service = AdminApprovalsService();
  String? _loadError;
  final Set<String> _knownLeaveTypes = {};

  late TabController _tabController;
  bool _isLoading = true;
  String _searchQuery = '';
  String _timelineFilter = 'All Timeline'; // 'All Timeline' | 'Upcoming Leaves' | 'Past Leaves'
  String _statusFilter = 'All Statuses'; // 'All Statuses' | 'Pending' | 'Approved' | 'Rejected'
  String _leaveTypeFilter = 'All Types';
  String _sortOrder = 'Newest First';
  String _startDateFilter = '';
  String _endDateFilter = '';

  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<AdminLeaveRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final page = await _service.getLeaveRequests(
        status: _statusFilter != 'All Statuses' ? _statusFilter : null,
        leaveType: _leaveTypeFilter != 'All Types' ? _leaveTypeFilter : null,
        tab: _timelineFilter == 'Upcoming Leaves' ? 'upcoming' : (_timelineFilter == 'Past Leaves' ? 'previous' : null),
        sort: _sortOrder == 'Oldest First' ? 'Oldest' : null,
        startDate: _startDateFilter.isNotEmpty ? _startDateFilter : null,
        endDate: _endDateFilter.isNotEmpty ? _endDateFilter : null,
      );
      if (!mounted) return;
      setState(() {
        _records = page.requests.map(AdminLeaveRecord.fromJson).toList();
        for (final r in _records) {
          if (r.leaveType.isNotEmpty) _knownLeaveTypes.add(r.leaveType);
        }
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = AdminApprovalsService.messageOf(e, fallback: 'Failed to load leave requests');
      setState(() {
        _loadError = msg;
        _isLoading = false;
      });
      if (!showLoader) SnackBarUtils.showSnackBar(context, msg, isError: true);
    }
  }

  List<AdminLeaveRecord> get _filteredRecords {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _records;
    return _records.where((r) {
      return r.name.toLowerCase().contains(q) ||
          r.employeeId.toLowerCase().contains(q) ||
          r.leaveType.toLowerCase().contains(q) ||
          r.reason.toLowerCase().contains(q);
    }).toList();
  }

  // ── Actions (update the list only after the backend accepts) ──
  Future<void> _approve(AdminLeaveRecord r) async {
    try {
      final msg = await _service.approveLeave(r.id, remarks: 'Approved');
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to approve leave');
    }
  }

  Future<void> _reject(AdminLeaveRecord r) async {
    final reason = await showApprovalReasonDialog(
      context,
      title: r.status == 'Approved' ? 'Revoke Approved Leave' : 'Reject Leave Request',
      subtitle: 'Please provide a reason for rejecting ${r.name}\'s ${r.leaveType} request:',
    );
    if (reason == null || !mounted) return;
    try {
      final msg = await _service.rejectLeave(r.id, reason: reason, remarks: reason);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to reject leave');
    }
  }

  /// POST /admin/approvals/leave/:id/cancel — only for Approved leave.
  Future<void> _cancel(AdminLeaveRecord r) async {
    final reason = await showApprovalReasonDialog(
      context,
      title: 'Cancel Approved Leave',
      subtitle: 'The days go back to ${r.name}\'s balance and the attendance for them is cleared so it can be marked again.',
      actionLabel: 'Cancel Leave',
      hint: 'Reason (optional)',
      required: false,
    );
    if (reason == null || !mounted) return;
    try {
      final msg = await _service.cancelLeave(r.id, reason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to cancel leave');
    }
  }

  List<Widget> _actionButtons(AdminLeaveRecord r, VoidCallback close) {
    if (r.status == 'Pending') {
      return [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              close();
              _reject(r);
            },
            style: approvalRejectStyle(),
            child: const Text('Reject'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              close();
              _approve(r);
            },
            style: approvalApproveStyle(),
            child: const Text('Approve'),
          ),
        ),
      ];
    }
    if (r.status == 'Approved') {
      return [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              close();
              _cancel(r);
            },
            style: approvalRejectStyle().copyWith(
              foregroundColor: const WidgetStatePropertyAll(AppColors.warning),
              side: WidgetStatePropertyAll(BorderSide(color: AppColors.warning.withValues(alpha: 0.5), width: 1.2)),
            ),
            child: const Text('Cancel Leave'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              close();
              _reject(r);
            },
            style: approvalRejectStyle(),
            child: const Text('Revoke'),
          ),
        ),
      ];
    }
    return const [];
  }

  // ── Action: View Leave Details (GET /admin/approvals/leave/:id) ──
  void _showLeaveDetailModal(AdminLeaveRecord r) {
    showApprovalDetailSheet(
      context,
      title: 'Leave Request Details',
      loader: () => _service.getLeaveDetail(r.id),
      buildRows: (d) {
        final staff = d['staffId'];
        final isHalf = d['isHalfDay'] == true;
        final reviewer = d['reviewedBy'];
        final status = (d['status'] ?? r.status).toString();
        return [
          MapEntry('REQUEST ID', r.requestId.isNotEmpty ? r.requestId : r.id),
          MapEntry('EMPLOYEE', approvalStaffName(staff, fallback: r.name)),
          MapEntry('EMPLOYEE ID', (staff is Map ? staff['employeeId'] : null)?.toString() ?? r.employeeId),
          MapEntry('DEPARTMENT', (staff is Map ? staff['department'] : null)?.toString() ?? r.department),
          MapEntry('LEAVE TYPE', (d['leaveTypeName'] ?? r.leaveType).toString()),
          MapEntry('CATEGORY', (d['leaveTypeCategory'] ?? r.leaveTypeCategory).toString()),
          MapEntry('DURATION', '${d['duration'] ?? r.days} day(s)${isHalf ? ' (${d['halfDaySession'] ?? ''})' : ''}'),
          MapEntry('FROM', formatApprovalDate(d['startDate'])),
          MapEntry('TO', formatApprovalDate(d['endDate'])),
          MapEntry('STATUS', status),
          MapEntry('REVIEWED BY', approvalStaffName(reviewer, fallback: r.approvedBy)),
          if (d['reviewedAt'] != null) MapEntry('REVIEWED ON', formatApprovalDate(d['reviewedAt'])),
          MapEntry('REASON', (d['reason'] ?? '').toString()),
          if ((d['rejectionReason'] ?? '').toString().isNotEmpty) MapEntry('REJECTION REASON', d['rejectionReason'].toString()),
          MapEntry('REMARKS / NOTES', (d['remarks'] ?? '').toString().isNotEmpty ? d['remarks'].toString() : 'No remarks provided.'),
          MapEntry('APPLIED ON', formatApprovalDate(d['createdAt'])),
        ];
      },
      actions: (sheetCtx, d) => _actionButtons(r, () => Navigator.pop(sheetCtx)),
    );
  }

  // ── Action: Advanced Filters Slide-Over (Screenshot 5) ──
  void _showAdvancedFiltersDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDrawerState) {
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.filter_alt_outlined, color: AppColors.primaryText, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text('ADVANCED FILTERS', style: AppTextStyles.headingSmall),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Leave Status (Screenshot 1)
                const Text('LEAVE STATUS', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _drawerDropdown(_statusFilter, ['All Statuses', 'Pending', 'Approved', 'Rejected', 'Cancelled'], (v) {
                  setDrawerState(() => _statusFilter = v);
                  setState(() => _statusFilter = v);
                }),
                const SizedBox(height: 16),

                // Leave Type (Screenshot 2)
                const Text('LEAVE TYPE', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _drawerDropdown(_leaveTypeFilter, ['All Types', ...(_knownLeaveTypes.toList()..sort())], (v) {
                  setDrawerState(() => _leaveTypeFilter = v);
                  setState(() => _leaveTypeFilter = v);
                }),
                const SizedBox(height: 16),

                // Sort Order (Screenshot 3)
                const Text('SORT ORDER', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _drawerDropdown(_sortOrder, ['Newest First', 'Oldest First'], (v) {
                  setDrawerState(() => _sortOrder = v);
                  setState(() => _sortOrder = v);
                }),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setDrawerState(() {
                            _statusFilter = 'All Statuses';
                            _leaveTypeFilter = 'All Types';
                            _sortOrder = 'Newest First';
                          });
                          setState(() {
                            _statusFilter = 'All Statuses';
                            _leaveTypeFilter = 'All Types';
                            _sortOrder = 'Newest First';
                          });
                          Navigator.pop(ctx);
                          _loadData();
                        },
                        child: const Text('Clear All'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _loadData();
                        },
                        child: const Text('Apply Filters'),
                      ),
                    ),
                  ],
                ),
              ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _drawerDropdown(String value, List<String> items, Function(String) onChanged) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500)))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
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
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Open menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Leaves Approvals'),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Leave Requests (${_records.length})'),
            const Tab(text: 'Leave Calendar'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRequestsTab(),
                _buildCalendarTab(),
              ],
            ),
    );
  }

  // ── Tab 1: Leave Requests List (Screenshots 1 & 2) ──
  Widget _buildRequestsTab() {
    return RefreshIndicator(
      onRefresh: () => _loadData(showLoader: false),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Filter & Timeline Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: approvalCardDecoration(),
            child: Column(
              children: [
                // Search
                Container(
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: AppTextStyles.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'Search employee, leave...',
                      hintStyle: TextStyle(fontSize: 14, color: AppColors.textCaption),
                      prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textCaption),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    // Timeline Dropdown (Screenshot 2)
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _timelineFilter,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(12),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                            items: ['All Timeline', 'Upcoming Leaves', 'Past Leaves']
                                .map((t) => DropdownMenuItem(value: t, child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _timelineFilter = v);
                                _loadData();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Filters Button
                    OutlinedButton.icon(
                      onPressed: _showAdvancedFiltersDrawer,
                      icon: const Icon(Icons.filter_alt_outlined, size: 18),
                      label: const Text('Filters'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Refresh Button
                    IconButton(
                      onPressed: () => _loadData(),
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF7F8FA),
                        minimumSize: const Size(44, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E5EA))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Header count
          Row(
            children: [
              const Expanded(child: Text('List of All & Past Leaves', style: AppTextStyles.headingSmall)),
              const SizedBox(width: 8),
              Text('Showing ${_filteredRecords.length} records', style: AppTextStyles.bodySmall),
            ],
          ),
          const SizedBox(height: 12),

          // Cards
          if (_loadError != null)
            ApprovalErrorView(message: _loadError!, onRetry: () => _loadData())
          else if (_filteredRecords.isEmpty)
            Container(
              alignment: Alignment.center,
              decoration: approvalCardDecoration(),
              child: const ApprovalEmptyView(
                icon: Icons.event_busy_outlined,
                title: 'No leave applications found',
              ),
            )
          else
            ..._filteredRecords.map((r) => _buildLeaveCard(r)),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  Widget _buildLeaveCard(AdminLeaveRecord r) {
    final isApproved = r.status == 'Approved';
    final isPending = r.status == 'Pending';
    final isUnpaid = r.leaveTypeCategory == 'unpaid' || r.leaveType.toLowerCase().contains('unpaid');

    Color typeBg = isUnpaid ? AppColors.indigoBg : AppColors.infoBg;
    Color typeFg = isUnpaid ? AppColors.indigo : AppColors.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showLeaveDetailModal(r),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kApprovalBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ApprovalCardHeader(
                        leading: ApprovalAvatar(name: r.name, initials: r.initials),
                        title: r.name,
                        subtitle: '${r.employeeId} • ${r.department}',
                        trailing: ApprovalStatusPill(status: r.status, label: r.status),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                      tooltip: 'More actions',
                      onSelected: (val) {
                        if (val == 'view') {
                          _showLeaveDetailModal(r);
                        } else if (val == 'approve') {
                          _approve(r);
                        } else if (val == 'reject') {
                          _reject(r);
                        } else if (val == 'cancel') {
                          _cancel(r);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Row(
                            children: [
                              Icon(Icons.visibility_outlined, size: 18, color: AppColors.info),
                              SizedBox(width: 12),
                              Text('View Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        if (isPending) _menuItem('approve', Icons.check_circle_outline_rounded, 'Approve', AppColors.success),
                        if (isPending) _menuItem('reject', Icons.cancel_outlined, 'Reject', AppColors.error),
                        if (isApproved) _menuItem('cancel', Icons.event_busy_outlined, 'Cancel Leave', AppColors.warning),
                        if (isApproved) _menuItem('reject', Icons.cancel_outlined, 'Revoke (Reject)', AppColors.error),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Type
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(999)),
                            child: Text('${r.leaveType}${r.isHalfDay ? " (${r.halfDaySession})" : ""}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: typeFg)),
                          ),
                          // Days
                          Text('${r.days} days', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          // Date
                          Text(r.dateLabel, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Reason
                      Text('Reason: ${r.reason}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Tab 2: Leave Calendar Matrix (Screenshot 4) ──
  Widget _buildCalendarTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Month Selector Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: approvalCardDecoration(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_outlined, color: AppColors.primaryText, size: 20),
                    const SizedBox(width: 8),
                    const Flexible(child: Text('Leave Calendar', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingSmall)),
                  ],
                ),
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    child: const Text('Today'),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    tooltip: 'Previous month',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1)),
                  ),
                  Text(DateFormat('MMMM yyyy').format(_calendarMonth), style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    tooltip: 'Next month',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Days Header
        Row(
          children: ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'].map((d) {
            return Expanded(
              child: Center(
                child: Text(d, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),

        // Grid of month days
        _buildCalendarGrid(),
        const SizedBox(height: 16),

        // Bottom Legend Bar (Screenshot 4)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: approvalCardDecoration(),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Legend:', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              _legendItem('Sick Leave', AppColors.info),
              _legendItem('Casual Leave', AppColors.success),
              _legendItem('Medical Leave', const Color(0xFF7C3AED)),
              _legendItem('Pending Approval', AppColors.warning),
              _legendItem('Rejected / Cancelled', AppColors.error),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final firstDayWeekday = DateTime(year, month, 1).weekday % 7; // 0 = Sun
    final totalDays = DateTime(year, month + 1, 0).day;

    final List<Widget> dayWidgets = [];

    // Empty lead cells
    for (int i = 0; i < firstDayWeekday; i++) {
      dayWidgets.add(Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8))));
    }

    // Days 1..totalDays
    for (int d = 1; d <= totalDays; d++) {
      final day = DateTime(year, month, d);
      final leavesForDay = _records.where((r) {
        final s = r.startDay;
        final e = r.endDay ?? s;
        if (s == null || e == null) return false;
        if (r.status == 'Rejected' || r.status == 'Cancelled') return false;
        return !day.isBefore(s) && !day.isAfter(e);
      }).toList();

      dayWidgets.add(
        Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: leavesForDay.isNotEmpty ? AppColors.brandBorder : kApprovalBorder),
          ),
          child: ClipRect(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$d', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              if (leavesForDay.isNotEmpty) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    '${leavesForDay.length} on leave',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.warning),
                  ),
                ),
                const SizedBox(height: 2),
                ...leavesForDay.take(2).map((l) => InkWell(
                      onTap: () => _showLeaveDetailModal(l),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(4)),
                        child: Text(l.name, style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w600, color: AppColors.success), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    )),
              ],
            ],
          ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.6,
      children: dayWidgets,
    );
  }
}
