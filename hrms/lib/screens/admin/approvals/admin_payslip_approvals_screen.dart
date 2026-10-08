// lib/screens/admin/approvals/admin_payslip_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'approval_shared_widgets.dart';

class AdminPayslipRequestRecord {
  final String id;
  final String name;
  final String employeeId;
  final String department;
  final String targetMonth;
  final String purpose;
  String status; // 'Pending' | 'Approved' | 'Rejected' | 'Cancelled'
  final String requestDate;
  final String approvedBy;
  final String remarks;
  final bool payrollGenerated;
  final bool payrollPaid;

  AdminPayslipRequestRecord({
    required this.id,
    required this.name,
    required this.employeeId,
    required this.department,
    required this.targetMonth,
    required this.purpose,
    required this.status,
    required this.requestDate,
    this.approvedBy = '—',
    this.remarks = '—',
    this.payrollGenerated = false,
    this.payrollPaid = false,
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  /// One row of GET /admin/approvals/payslip (`data.requests[]`).
  factory AdminPayslipRequestRecord.fromJson(Map<String, dynamic> json) {
    return AdminPayslipRequestRecord(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? 'Staff Member').toString(),
      employeeId: (json['employeeId'] ?? '—').toString(),
      department: (json['role'] ?? json['department'] ?? '—').toString(),
      targetMonth: (json['targetMonth'] ?? '—').toString(),
      purpose: (json['purpose'] ?? '—').toString(),
      status: (json['status'] ?? 'Pending').toString(),
      requestDate: (json['requestDate'] ?? '').toString(),
      approvedBy: (json['approvedBy'] ?? '—').toString(),
      remarks: (json['remarks'] ?? '').toString().isEmpty ? '—' : json['remarks'].toString(),
      payrollGenerated: json['payrollGenerated'] == true,
      payrollPaid: json['payrollPaid'] == true,
    );
  }
}

class AdminPayslipApprovalsScreen extends StatefulWidget {
  const AdminPayslipApprovalsScreen({super.key});

  @override
  State<AdminPayslipApprovalsScreen> createState() => _AdminPayslipApprovalsScreenState();
}

class _AdminPayslipApprovalsScreenState extends State<AdminPayslipApprovalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminApprovalsService _service = AdminApprovalsService();
  String? _loadError;

  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'All Statuses';
  String _startDateFilter = '';
  String _endDateFilter = '';
  String _sortOrder = 'Newest First (Descending)';

  List<AdminPayslipRequestRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final page = await _service.getPayslipRequests(
        status: _statusFilter != 'All Statuses' ? _statusFilter : null,
        startDate: _startDateFilter.isNotEmpty ? _startDateFilter : null,
        endDate: _endDateFilter.isNotEmpty ? _endDateFilter : null,
        sort: _sortOrder.startsWith('Newest') ? 'Newest' : 'Oldest',
      );
      if (!mounted) return;
      setState(() {
        _records = page.requests.map(AdminPayslipRequestRecord.fromJson).toList();
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = AdminApprovalsService.messageOf(e, fallback: 'Failed to load payslip requests');
      setState(() {
        _loadError = msg;
        _isLoading = false;
      });
      if (!showLoader) SnackBarUtils.showSnackBar(context, msg, isError: true);
    }
  }

  List<AdminPayslipRequestRecord> get _filteredRecords {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _records;
    return _records.where((r) {
      return r.name.toLowerCase().contains(q) ||
          r.employeeId.toLowerCase().contains(q) ||
          r.targetMonth.toLowerCase().contains(q) ||
          r.purpose.toLowerCase().contains(q);
    }).toList();
  }

  // ── Action: Approve (backend refuses until that month's payroll is generated and paid) ──
  Future<void> _approve(AdminPayslipRequestRecord r) async {
    try {
      final msg = await _service.approvePayslip(r.id, remarks: 'Approved');
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to approve payslip request');
    }
  }

  // ── Action: Reject ──
  Future<void> _showRejectModal(AdminPayslipRequestRecord r) async {
    final reason = await showApprovalReasonDialog(
      context,
      title: 'Reject Payslip Request',
      subtitle: 'Rejecting the payslip request of ${r.name} for ${r.targetMonth}',
      actionLabel: 'Reject Request',
    );
    if (reason == null || !mounted) return;
    try {
      final msg = await _service.rejectPayslip(r.id, reason: reason, remarks: reason);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to reject payslip request');
    }
  }

  // ── Action: Advanced Filters Slide-Over (Screenshots 3 & 4) ──
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

                // Request Status (Screenshot 3)
                const Text('REQUEST STATUS', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _drawerDropdown(_statusFilter, ['All Statuses', 'Pending', 'Approved', 'Rejected', 'Cancelled'], (v) {
                  setDrawerState(() => _statusFilter = v);
                  setState(() => _statusFilter = v);
                }),
                const SizedBox(height: 16),

                // Start & End Date (Screenshot 4)
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

                // Sort Order (Screenshot 4)
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
                            _startDateFilter = '';
                            _endDateFilter = '';
                            _sortOrder = 'Newest First (Descending)';
                          });
                          setState(() {
                            _statusFilter = 'All Statuses';
                            _startDateFilter = '';
                            _endDateFilter = '';
                            _sortOrder = 'Newest First (Descending)';
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
        title: const Text('Payslip Requests'),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _loadData(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header Bar: Search & Filter
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: approvalCardDecoration(),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
                            child: TextField(
                              onChanged: (v) => setState(() => _searchQuery = v),
                              style: AppTextStyles.bodyMedium,
                              decoration: const InputDecoration(
                                hintText: 'Search...',
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
                        ),
                        const SizedBox(width: 8),

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
                  ),
                  const SizedBox(height: 16),

                  // Subtitle
                  Row(
                    children: [
                      const Expanded(child: Text('List of Payslip Requests', style: AppTextStyles.headingSmall)),
                      const SizedBox(width: 8),
                      Text('Showing ${_filteredRecords.length} requests', style: AppTextStyles.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Records Cards
                  if (_loadError != null)
                    ApprovalErrorView(message: _loadError!, onRetry: () => _loadData())
                  else if (_filteredRecords.isEmpty)
                    Container(
                      alignment: Alignment.center,
                      decoration: approvalCardDecoration(),
                      child: const ApprovalEmptyView(
                        icon: Icons.receipt_long_outlined,
                        title: 'No payslip requests found',
                      ),
                    )
                  else
                    ..._filteredRecords.map((r) => _buildPayslipCard(r)),
                ],
              ),
            ),
    );
  }

  Widget _buildPayslipCard(AdminPayslipRequestRecord r) {
    final isPending = r.status == 'Pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.fromLTRB(16, 16, isPending ? 8 : 16, 16),
      decoration: approvalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Avatar + Name + Month + Status
          Row(
            children: [
              Expanded(
                child: ApprovalCardHeader(
                  leading: ApprovalAvatar(name: r.name, initials: r.initials),
                  title: r.name,
                  subtitle: '${r.employeeId} • ${r.department}',
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(r.targetMonth, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      ApprovalStatusPill(status: r.status, label: r.status),
                    ],
                  ),
                ),
              ),
              if (isPending) ...[
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                  tooltip: 'More actions',
                  onSelected: (val) {
                    if (val == 'approve') {
                      _approve(r);
                    } else if (val == 'reject') {
                      _showRejectModal(r);
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (!r.payrollGenerated || !r.payrollPaid)
                    PopupMenuItem(
                      enabled: false,
                      value: 'notice',
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Text(!r.payrollGenerated ? 'Please generate payroll' : 'Mark payroll as paid first', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.warning)),
                        ],
                      ),
                    ),
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
            ],
          ),
          const SizedBox(height: 12),

          // Details Box
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(right: isPending ? 8 : 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text('Purpose: ${r.purpose}', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                    const SizedBox(width: 8),
                    Text('📅 ${r.requestDate}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                if (r.approvedBy != '—' || r.remarks != '—') ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (r.approvedBy != '—')
                        Text('Approved By: ${r.approvedBy}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryText)),
                      if (r.remarks != '—')
                        Expanded(
                          child: Text(
                            'Remarks: ${r.remarks}',
                            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
