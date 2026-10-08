// lib/screens/admin/approvals/admin_reimbursement_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'approval_shared_widgets.dart';

/// One row of GET /admin/approvals/expense (`data.requests[]`).
class AdminReimbursementRecord {
  final String id;
  final String staffId;
  final String name;
  final String employeeId;
  final String department;
  final String category;
  final double amount;
  final String claimDate;
  final String description;
  final String? receiptUrl;
  final String? paymentRoute; // 'Immediate' | 'Payroll'
  final String? payrollMonth;
  final String? proofImgUrl;
  final String? upiId;
  final String? accountNo;
  final String? ifscCode;
  String status; // 'Pending' | 'Approved' | 'Paid' | 'Rejected' | 'Cancelled'
  final String approvedBy;
  final String remarksDate;
  final String remarks;

  AdminReimbursementRecord({
    required this.id,
    this.staffId = '',
    required this.name,
    required this.employeeId,
    required this.department,
    required this.category,
    required this.amount,
    required this.claimDate,
    required this.description,
    this.receiptUrl,
    this.paymentRoute,
    this.payrollMonth,
    this.proofImgUrl,
    this.upiId,
    this.accountNo,
    this.ifscCode,
    required this.status,
    this.approvedBy = '—',
    this.remarksDate = '',
    this.remarks = '',
  });

  String get initials {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  static String? _opt(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  factory AdminReimbursementRecord.fromJson(Map<String, dynamic> json) {
    final receipt = _opt(json['receiptName']);
    return AdminReimbursementRecord(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      staffId: (json['staffId'] is Map ? json['staffId']['_id'] : json['staffId'])?.toString() ?? '',
      name: (json['name'] ?? 'Staff Member').toString(),
      employeeId: (json['employeeId'] ?? '—').toString(),
      department: (json['role'] ?? json['department'] ?? '—').toString(),
      category: (json['category'] ?? '—').toString(),
      amount: double.tryParse((json['amount'] ?? '0').toString()) ?? 0.0,
      claimDate: (json['date'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      receiptUrl: receipt == 'No Proof' ? null : receipt,
      paymentRoute: _opt(json['paymentRoute']),
      payrollMonth: _opt(json['payrollMonth']),
      proofImgUrl: _opt(json['proofImg']),
      upiId: _opt(json['upiId']),
      accountNo: _opt(json['accountNo']),
      ifscCode: _opt(json['ifscCode']),
      status: (json['status'] ?? 'Pending').toString(),
      approvedBy: (json['approvedBy'] ?? '—').toString(),
      remarksDate: (json['remarksDate'] ?? '').toString(),
      remarks: (json['remarks'] ?? '').toString(),
    );
  }
}

class AdminReimbursementApprovalsScreen extends StatefulWidget {
  const AdminReimbursementApprovalsScreen({super.key});

  @override
  State<AdminReimbursementApprovalsScreen> createState() => _AdminReimbursementApprovalsScreenState();
}

class _AdminReimbursementApprovalsScreenState extends State<AdminReimbursementApprovalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminApprovalsService _service = AdminApprovalsService();
  String? _loadError;

  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'All Statuses';
  String _startDateFilter = '';
  String _endDateFilter = '';
  String _sortOrder = 'Newest First (Descending)';

  List<AdminReimbursementRecord> _records = [];

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
      final page = await _service.getExpenseRequests(
        status: _statusFilter != 'All Statuses' ? _statusFilter : null,
        startDate: _startDateFilter.isNotEmpty ? _startDateFilter : null,
        endDate: _endDateFilter.isNotEmpty ? _endDateFilter : null,
        sort: _sortOrder.startsWith('Newest') ? 'Newest' : 'Oldest',
      );
      if (!mounted) return;
      setState(() {
        _records = page.requests.map(AdminReimbursementRecord.fromJson).toList();
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = AdminApprovalsService.messageOf(e, fallback: 'Failed to load reimbursement claims');
      setState(() {
        _loadError = msg;
        _isLoading = false;
      });
      if (!showLoader) SnackBarUtils.showSnackBar(context, msg, isError: true);
    }
  }

  List<AdminReimbursementRecord> get _filteredRecords {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _records;
    return _records.where((r) {
      return r.name.toLowerCase().contains(q) ||
          r.employeeId.toLowerCase().contains(q) ||
          r.category.toLowerCase().contains(q) ||
          r.description.toLowerCase().contains(q);
    }).toList();
  }

  // ── Action: Approve (payout workflow, same body as the web modal) ──
  Future<void> _showApproveModal(AdminReimbursementRecord r) async {
    final ok = await showReimbursementPayoutSheet(
      context,
      expenseId: r.id,
      staffId: r.staffId,
      staffName: r.name,
      amount: r.amount,
      claimUpiId: r.upiId,
      claimAccountNo: r.accountNo,
      claimIfscCode: r.ifscCode,
    );
    if (ok && mounted) _loadData(showLoader: false);
  }

  // ── Action: Reject ──
  Future<void> _showRejectModal(AdminReimbursementRecord r) async {
    final reason = await showApprovalReasonDialog(
      context,
      title: 'Reject Reimbursement',
      subtitle: 'Rejecting claim of ₹${r.amount.toStringAsFixed(0)} for ${r.name}',
      actionLabel: 'Reject Claim',
    );
    if (reason == null || !mounted) return;
    try {
      final msg = await _service.rejectExpense(r.id, reason: reason, remarks: reason);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to reject claim');
    }
  }

  // ── Action: View details (GET /admin/approvals/expense/:id) ──
  void _showDetails(AdminReimbursementRecord r) {
    showApprovalDetailSheet(
      context,
      title: 'Reimbursement Claim Details',
      loader: () => _service.getExpenseDetail(r.id),
      buildRows: (d) {
        final reviewer = d['reviewedBy'];
        return [
          MapEntry('EMPLOYEE', approvalStaffName(d['staffId'], fallback: r.name)),
          MapEntry('EMPLOYEE ID', (d['staffId'] is Map ? d['staffId']['employeeId'] : null)?.toString() ?? r.employeeId),
          MapEntry('CATEGORY', (d['type'] ?? r.category).toString()),
          MapEntry('AMOUNT', '₹${d['amount'] ?? r.amount}'),
          MapEntry('CLAIM DATE', formatApprovalDate(d['date'])),
          MapEntry('DESCRIPTION', (d['description'] ?? '').toString()),
          MapEntry('RECEIPT', (d['proofFile'] ?? '').toString().isEmpty ? 'No Proof' : (d['proofFile']).toString()),
          MapEntry('STATUS', (d['status'] ?? r.status).toString()),
          if (d['paymentRoute'] != null) MapEntry('PAYMENT ROUTE', d['paymentRoute'].toString()),
          if (d['payrollMonth'] != null) MapEntry('PAYROLL MONTH', d['payrollMonth'].toString()),
          if (d['accountNo'] != null) MapEntry('ACCOUNT NO.', d['accountNo'].toString()),
          if (d['ifscCode'] != null) MapEntry('IFSC CODE', d['ifscCode'].toString()),
          if (d['upiId'] != null) MapEntry('UPI ID', d['upiId'].toString()),
          if (d['proofImg'] != null) MapEntry('PAYMENT PROOF', d['proofImg'].toString()),
          MapEntry('REVIEWED BY', (d['approvedBy'] ?? approvalStaffName(reviewer, fallback: '—')).toString()),
          if (d['reviewedAt'] != null) MapEntry('REVIEWED ON', formatApprovalDate(d['reviewedAt'])),
          MapEntry('REMARKS', (d['remarks'] ?? '').toString()),
        ];
      },
      actions: r.status == 'Pending'
          ? (sheetCtx, d) => [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _showRejectModal(r);
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
                      _showApproveModal(r);
                    },
                    style: approvalApproveStyle(),
                    child: const Text('Approve'),
                  ),
                ),
              ]
          : null,
    );
  }

  // ── Action: Advanced Filters Slide-Over (Screenshots 4 & 5) ──
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

                // Claim Status (Screenshot 4)
                const Text('CLAIM STATUS', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _drawerDropdown(_statusFilter, ['All Statuses', 'Pending', 'Approved', 'Paid', 'Rejected', 'Cancelled'], (v) {
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

                // Sort Order (Screenshot 5)
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
        title: const Text('Reimbursement'),
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
                                hintText: 'Search (case-insensitive)...',
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

                  // Sub-header title
                  Row(
                    children: [
                      const Expanded(child: Text('ALL REIMBURSEMENT CLAIMS', style: AppTextStyles.sectionLabel)),
                      const SizedBox(width: 8),
                      Text('Showing ${_filteredRecords.length} claims', style: AppTextStyles.bodySmall),
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
                        title: 'No reimbursement claims found',
                      ),
                    )
                  else
                    ..._filteredRecords.map((r) => _buildReimbursementCard(r)),
                ],
              ),
            ),
    );
  }

  Widget _buildReimbursementCard(AdminReimbursementRecord r) {
    final isPending = r.status == 'Pending';
    final isRejected = r.status == 'Rejected';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      decoration: approvalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Avatar + Name + Amount + Status
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
                      Text('₹${r.amount.toStringAsFixed(0)}', style: AppTextStyles.headingSmall.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      ApprovalStatusPill(status: r.status, label: r.status),
                    ],
                  ),
                ),
              ),
              ...[
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                  tooltip: 'More actions',
                  onSelected: (val) {
                    if (val == 'approve') {
                      _showApproveModal(r);
                    } else if (val == 'reject') {
                      _showRejectModal(r);
                    } else if (val == 'view') {
                      _showDetails(r);
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
            ],
          ),
          const SizedBox(height: 12),

          // Details Card
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text('Category: ${r.category}', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                    const SizedBox(width: 8),
                    Text('📅 ${r.claimDate}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                if (r.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Description: ', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                      Expanded(child: Text(r.description, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
                if (r.paymentRoute != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.paymentRoute == 'Payroll' ? 'Payment: Payroll (${r.payrollMonth})' : 'Payment: Immediate',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: r.paymentRoute == 'Payroll' ? AppColors.info : AppColors.success),
                        ),
                      ),
                      if (r.approvedBy.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isRejected ? 'Rejected: ${r.remarks}' : 'Approved by: ${r.approvedBy}',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppColors.primaryText, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
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
