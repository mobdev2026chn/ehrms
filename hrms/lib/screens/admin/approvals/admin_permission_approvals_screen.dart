// lib/screens/admin/approvals/admin_permission_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'approval_shared_widgets.dart';

class AdminPermissionRecord {
  final String id;
  final String requestId;
  final String employeeId;
  final String name;
  final String department;
  final String designation;
  final String date;
  final String rawDate;
  final String type; // 'Late' | 'Early' | 'Custom'
  final String durationText;
  final int durationMins;
  String status; // 'Approved' | 'Pending' | 'Rejected' | 'Cancelled'
  final String approvedBy;
  final String reason;
  final String remarks;

  AdminPermissionRecord({
    required this.id,
    required this.requestId,
    required this.employeeId,
    required this.name,
    required this.department,
    required this.designation,
    required this.date,
    this.rawDate = '',
    required this.type,
    required this.durationText,
    this.durationMins = 30,
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

  /// One row of GET /admin/approvals/permission (`data.requests[]`).
  factory AdminPermissionRecord.fromJson(Map<String, dynamic> json) {
    final pType = (json['type'] ?? 'Custom').toString();
    final lateMins = (int.tryParse((json['lateHours'] ?? 0).toString()) ?? 0) * 60 + (int.tryParse((json['lateMinutes'] ?? 0).toString()) ?? 0);
    final earlyMins = (int.tryParse((json['earlyHours'] ?? 0).toString()) ?? 0) * 60 + (int.tryParse((json['earlyMinutes'] ?? 0).toString()) ?? 0);
    final dMins = int.tryParse((json['durationMins'] ?? '').toString()) ??
        (pType == 'Late' ? lateMins : (pType == 'Early' ? earlyMins : lateMins + earlyMins));

    String fmt(int m) => m >= 60 ? '${m ~/ 60}h${m % 60 > 0 ? ' ${m % 60}m' : ''}' : '${m}m';
    String dText;
    if (pType == 'Late') {
      dText = 'Late: ${fmt(dMins)}';
    } else if (pType == 'Early') {
      dText = 'Early: ${fmt(dMins)}';
    } else {
      final parts = <String>[];
      if (lateMins > 0) parts.add('Late ${fmt(lateMins)}');
      if (earlyMins > 0) parts.add('Early ${fmt(earlyMins)}');
      dText = parts.isEmpty ? 'Custom: ${fmt(dMins)}' : 'Custom: ${parts.join(', ')}';
    }

    final rawDate = (json['date'] ?? '').toString();
    final status = (json['status'] ?? 'Pending').toString();
    return AdminPermissionRecord(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      requestId: (json['requestId'] ?? '').toString(),
      employeeId: (json['employeeId'] ?? '—').toString(),
      name: (json['employeeName'] ?? json['name'] ?? 'Staff Member').toString(),
      department: (json['department'] ?? '—').toString(),
      designation: (json['designation'] ?? '—').toString(),
      date: formatApprovalDate(rawDate),
      rawDate: rawDate,
      type: pType,
      durationText: dText,
      durationMins: dMins,
      status: status,
      approvedBy: (json['approvedBy'] ?? '—').toString(),
      reason: (json['reason'] ?? '').toString(),
      remarks: (json['remarks'] ?? '').toString(),
    );
  }

  DateTime? get day {
    final d = DateTime.tryParse(rawDate)?.toLocal();
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }
}

class AdminPermissionApprovalsScreen extends StatefulWidget {
  const AdminPermissionApprovalsScreen({super.key});

  @override
  State<AdminPermissionApprovalsScreen> createState() => _AdminPermissionApprovalsScreenState();
}

class _AdminPermissionApprovalsScreenState extends State<AdminPermissionApprovalsScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminApprovalsService _service = AdminApprovalsService();
  String? _loadError;

  late TabController _tabController;
  bool _isLoading = true;
  String _searchQuery = '';
  String _timelineFilter = 'All Time'; // 'All Time' | 'Upcoming' | 'Past Only'
  String _statusFilter = 'All Statuses'; // 'All Statuses' | 'Pending' | 'Approved' | 'Rejected' | 'Cancelled'
  String _startDateFilter = '';
  String _endDateFilter = '';
  String _sortOrder = 'Newest First (Descending)';

  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<AdminPermissionRecord> _records = [];

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
      final page = await _service.getPermissionRequests(
        status: _statusFilter != 'All Statuses' ? _statusFilter : null,
        tab: _timelineFilter == 'Upcoming' ? 'upcoming' : (_timelineFilter == 'Past Only' ? 'previous' : null),
        startDate: _startDateFilter.isNotEmpty ? _startDateFilter : null,
        endDate: _endDateFilter.isNotEmpty ? _endDateFilter : null,
        sort: _sortOrder.startsWith('Oldest') ? 'Oldest' : 'Newest',
      );
      if (!mounted) return;
      setState(() {
        _records = page.requests.map(AdminPermissionRecord.fromJson).toList();
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = AdminApprovalsService.messageOf(e, fallback: 'Failed to load permission requests');
      setState(() {
        _loadError = msg;
        _isLoading = false;
      });
      if (!showLoader) SnackBarUtils.showSnackBar(context, msg, isError: true);
    }
  }

  List<AdminPermissionRecord> get _filteredRecords {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _records;
    return _records.where((r) {
      return r.name.toLowerCase().contains(q) ||
          r.employeeId.toLowerCase().contains(q) ||
          r.reason.toLowerCase().contains(q) ||
          r.type.toLowerCase().contains(q);
    }).toList();
  }

  // ── Actions (list refreshes only after the backend accepts) ──
  Future<void> _approve(AdminPermissionRecord r) async {
    try {
      final msg = await _service.approvePermission(r.id, remarks: 'Approved');
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to approve permission');
    }
  }

  Future<void> _reject(AdminPermissionRecord r) async {
    final reason = await showApprovalReasonDialog(
      context,
      title: 'Reject Permission Request',
      subtitle: 'Please provide a reason for rejecting ${r.name}\'s request:',
    );
    if (reason == null || !mounted) return;
    try {
      final msg = await _service.rejectPermission(r.id, reason: reason, remarks: reason);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to reject permission');
    }
  }

  // ── Action: View Permission Details (GET /admin/approvals/permission/:id) ──
  void _showPermissionDetailModal(AdminPermissionRecord r) {
    showApprovalDetailSheet(
      context,
      title: 'Permission Request Details',
      loader: () => _service.getPermissionDetail(r.id),
      buildRows: (d) {
        final staff = d['staffId'];
        final reviewer = d['reviewedBy'];
        return [
          MapEntry('REQUEST ID', r.requestId.isNotEmpty ? r.requestId : r.id),
          MapEntry('EMPLOYEE', approvalStaffName(staff, fallback: r.name)),
          MapEntry('EMPLOYEE ID', (staff is Map ? staff['employeeId'] : null)?.toString() ?? r.employeeId),
          MapEntry('DEPARTMENT', (staff is Map ? staff['department'] : null)?.toString() ?? r.department),
          MapEntry('TYPE', (d['type'] ?? r.type).toString()),
          MapEntry('REQUESTED DATE', formatApprovalDate(d['date'])),
          MapEntry('DURATION', r.durationText),
          if ((d['arrivalTime'] ?? '').toString().isNotEmpty) MapEntry('ARRIVAL TIME', d['arrivalTime'].toString()),
          if ((d['leavingTime'] ?? '').toString().isNotEmpty) MapEntry('LEAVING TIME', d['leavingTime'].toString()),
          MapEntry('STATUS', (d['status'] ?? r.status).toString()),
          MapEntry('REVIEWED BY', approvalStaffName(reviewer, fallback: r.approvedBy)),
          if (d['reviewedAt'] != null) MapEntry('REVIEWED ON', formatApprovalDate(d['reviewedAt'])),
          MapEntry('REASON', (d['reason'] ?? '').toString()),
          if ((d['rejectionReason'] ?? '').toString().isNotEmpty) MapEntry('REJECTION REASON', d['rejectionReason'].toString()),
          MapEntry('REMARKS', (d['remarks'] ?? '').toString()),
        ];
      },
      actions: r.status == 'Pending'
          ? (sheetCtx, d) => [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
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
                      Navigator.pop(sheetCtx);
                      _approve(r);
                    },
                    style: approvalApproveStyle(),
                    child: const Text('Approve'),
                  ),
                ),
              ]
          : null,
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

                // Permission Status (Screenshot 1)
                const Text('PERMISSION STATUS', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _drawerDropdown(_statusFilter, ['All Statuses', 'Pending', 'Approved', 'Rejected', 'Cancelled'], (v) {
                  setDrawerState(() => _statusFilter = v);
                  setState(() => _statusFilter = v);
                }),
                const SizedBox(height: 16),

                // Start & End Date (Screenshot 1)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('START DATE', style: AppTextStyles.sectionLabel),
                          const SizedBox(height: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2028));
                              if (picked != null) {
                                final s = DateFormat('yyyy-MM-dd').format(picked);
                                setDrawerState(() => _startDateFilter = s);
                                setState(() => _startDateFilter = s);
                              }
                            },
                            child: _dateBox(_startDateFilter),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('END DATE', style: AppTextStyles.sectionLabel),
                          const SizedBox(height: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2028));
                              if (picked != null) {
                                final s = DateFormat('yyyy-MM-dd').format(picked);
                                setDrawerState(() => _endDateFilter = s);
                                setState(() => _endDateFilter = s);
                              }
                            },
                            child: _dateBox(_endDateFilter),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Sort Order (Screenshot 2)
                const Text('SORT ORDER', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _drawerDropdown(_sortOrder, ['Newest First (Descending)', 'Oldest First (Ascending)'], (v) {
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
                            _sortOrder = 'Newest First (Descending)';
                            _startDateFilter = '';
                            _endDateFilter = '';
                          });
                          setState(() {
                            _statusFilter = 'All Statuses';
                            _sortOrder = 'Newest First (Descending)';
                            _startDateFilter = '';
                            _endDateFilter = '';
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

  /// Read-only date field look used by the filter sheet.
  Widget _dateBox(String value) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(value.isNotEmpty ? value : 'yyyy-mm-dd', style: TextStyle(fontSize: 14, color: value.isNotEmpty ? AppColors.textPrimary : AppColors.textCaption)),
          const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondary),
        ],
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
        title: const Text('Permission Requests'),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'All Requests (${_records.length})'),
            const Tab(text: 'Permission Calendar'),
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

  // ── Tab 1: Requests List (Screenshots 1 & 2) ──
  Widget _buildRequestsTab() {
    return RefreshIndicator(
      onRefresh: () => _loadData(showLoader: false),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search & Filter Row
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
                      hintText: 'Search employee, ID, reason...',
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
                    // Timeline Dropdown (Screenshot 4)
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
                            items: ['All Time', 'Upcoming', 'Past Only']
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
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              const Expanded(child: Text('List of Permission Requests', style: AppTextStyles.headingSmall)),
              const SizedBox(width: 8),
              Text('Showing ${_filteredRecords.length} requests', style: AppTextStyles.bodySmall),
            ],
          ),
          const SizedBox(height: 12),

          // Records List
          if (_loadError != null)
            ApprovalErrorView(message: _loadError!, onRetry: () => _loadData())
          else if (_filteredRecords.isEmpty)
            Container(
              alignment: Alignment.center,
              decoration: approvalCardDecoration(),
              child: const ApprovalEmptyView(
                icon: Icons.more_time_rounded,
                title: 'No permission requests found',
              ),
            )
          else
            ..._filteredRecords.map((r) => _buildPermissionCard(r)),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(AdminPermissionRecord r) {
    final isPending = r.status == 'Pending';
    final isLate = r.type == 'Late';
    final isEarly = r.type == 'Early';

    Color typeBg = isLate ? AppColors.warningBg : (isEarly ? AppColors.infoBg : const Color(0xFFEDE9FE));
    Color typeFg = isLate ? AppColors.warning : (isEarly ? AppColors.info : const Color(0xFF7C3AED));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showPermissionDetailModal(r),
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
                          _showPermissionDetailModal(r);
                        } else if (val == 'approve') {
                          _approve(r);
                        } else if (val == 'reject') {
                          _reject(r);
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
                        if (isPending)
                          const PopupMenuItem(
                            value: 'approve',
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.success),
                                SizedBox(width: 12),
                                Text('Approve', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.success)),
                              ],
                            ),
                          ),
                        if (isPending)
                          const PopupMenuItem(
                            value: 'reject',
                            child: Row(
                              children: [
                                Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                                SizedBox(width: 12),
                                Text('Reject', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.error)),
                              ],
                            ),
                          ),
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
                            child: Text(r.type, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: typeFg)),
                          ),
                          // Duration
                          Text(r.durationText, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          // Date
                          Text(r.date, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
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

  // ── Tab 2: Permission Calendar ──
  Widget _buildCalendarTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                    const Flexible(child: Text('Permission Calendar', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingSmall)),
                  ],
                ),
              ),
              Row(
                children: [
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

        Row(
          children: ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'].map((d) {
            return Expanded(
              child: Center(child: Text(d, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
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
              _legendItem('Late Arrival', AppColors.warning),
              _legendItem('Early Leaving', AppColors.info),
              _legendItem('Custom Break', const Color(0xFF7C3AED)),
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
    final firstDayWeekday = DateTime(year, month, 1).weekday % 7;
    final totalDays = DateTime(year, month + 1, 0).day;

    final List<Widget> dayWidgets = [];

    for (int i = 0; i < firstDayWeekday; i++) {
      dayWidgets.add(Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8))));
    }

    for (int d = 1; d <= totalDays; d++) {
      final day = DateTime(year, month, d);
      final permsForDay = _records.where((r) => r.day == day && r.status != 'Rejected' && r.status != 'Cancelled').toList();

      dayWidgets.add(
        Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: permsForDay.isNotEmpty ? AppColors.brandBorder : kApprovalBorder),
          ),
          child: ClipRect(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$d', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              if (permsForDay.isNotEmpty) ...[
                const SizedBox(height: 2),
                ...permsForDay.take(2).map((p) => InkWell(
                      onTap: () => _showPermissionDetailModal(p),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(4)),
                        child: Text(p.name, style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w600, color: AppColors.warning), maxLines: 1, overflow: TextOverflow.ellipsis),
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
