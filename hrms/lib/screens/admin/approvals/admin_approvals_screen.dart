// lib/screens/admin/approvals/admin_approvals_screen.dart
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'approval_shared_widgets.dart';

class AdminApprovalsScreen extends StatefulWidget {
  final String initialType; // 'leave' | 'permission' | 'punch' | 'fine' | 'expense' | 'payslip'

  const AdminApprovalsScreen({super.key, this.initialType = 'leave'});

  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminApprovalsService _approvalsService = AdminApprovalsService();

  late TabController _tabController;
  final List<Map<String, String>> _approvalTabs = [
    {'type': 'leave', 'label': 'Leave'},
    {'type': 'permission', 'label': 'Permission'},
    {'type': 'punch', 'label': 'Punch'},
    {'type': 'fine', 'label': 'Fine'},
    {'type': 'expense', 'label': 'Reimbursement'},
    {'type': 'payslip', 'label': 'Payslip'},
  ];

  late String _currentType;
  bool _isLoading = true;
  String? _loadError;
  String _statusFilter = 'All'; // 'All' | 'Pending' | 'Approved' | 'Rejected'
  String _searchQuery = '';

  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic> _summary = {'total': 0, 'pending': 0, 'approved': 0, 'rejected': 0};

  @override
  void initState() {
    super.initState();
    int initialIdx = _approvalTabs.indexWhere((t) => t['type'] == widget.initialType);
    if (initialIdx < 0) initialIdx = 0;
    _currentType = _approvalTabs[initialIdx]['type']!;

    _tabController = TabController(length: _approvalTabs.length, vsync: this, initialIndex: initialIdx);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final next = _approvalTabs[_tabController.index]['type']!;
      if (next == _currentType) return;
      setState(() {
        _currentType = next;
        _requests = [];
      });
      _fetchApprovals();
    });

    _fetchApprovals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Normalised status for a hub row. Punch rows carry `isPendingApproval`; fine rows use
  /// 'Approval Pending' / 'Saved' / 'Edited'.
  String _statusOf(Map<String, dynamic> r) {
    if (_currentType == 'punch') {
      return r['isPendingApproval'] == true ? 'Pending' : 'Approved';
    }
    final s = (r['status'] ?? 'Pending').toString();
    if (_currentType == 'fine') {
      if (s == 'Saved') return 'Approved';
      if (s == 'Edited') return 'Rejected';
      return 'Pending';
    }
    return s;
  }

  Future<void> _fetchApprovals({bool showLoader = true}) async {
    final type = _currentType;
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final page = await _approvalsService.getApprovalsList(
        type: type,
        status: _statusFilter,
        search: _searchQuery,
      );
      if (!mounted || type != _currentType) return;

      var reqs = page.requests;
      // Punch and fine lists have no server-side status/search filters or summary.
      if (AdminApprovalsService.batchTypes.contains(type)) {
        int p = 0, a = 0, r = 0;
        for (final x in reqs) {
          final st = _statusOf(x).toLowerCase();
          if (st == 'pending') p++;
          if (st == 'approved') a++;
          if (st == 'rejected') r++;
        }
        final summary = {'total': reqs.length, 'pending': p, 'approved': a, 'rejected': r};
        final q = _searchQuery.trim().toLowerCase();
        reqs = reqs.where((x) {
          final matchesStatus = _statusFilter == 'All' || _statusOf(x) == _statusFilter;
          final name = (x['staffName'] ?? x['employeeName'] ?? '').toString().toLowerCase();
          final empId = (x['employeeId'] ?? '').toString().toLowerCase();
          final matchesSearch = q.isEmpty || name.contains(q) || empId.contains(q);
          return matchesStatus && matchesSearch;
        }).toList();
        setState(() {
          _requests = reqs;
          _summary = summary;
          _loadError = null;
          _isLoading = false;
        });
      } else {
        setState(() {
          _requests = reqs;
          _summary = page.summary.isNotEmpty ? page.summary : {'total': reqs.length, 'pending': 0, 'approved': 0, 'rejected': 0};
          _loadError = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted || type != _currentType) return;
      final msg = AdminApprovalsService.messageOf(e, fallback: 'Failed to load approvals');
      setState(() {
        _loadError = msg;
        _isLoading = false;
      });
      if (!showLoader) SnackBarUtils.showSnackBar(context, msg, isError: true);
    }
  }

  Future<void> _handleApprove(Map<String, dynamic> req) async {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString();

    // A reimbursement needs its payout route (payroll month, or account details + proof).
    if (_currentType == 'expense') {
      final ok = await showReimbursementPayoutSheet(
        context,
        expenseId: reqId,
        staffId: (req['staffId'] ?? '').toString(),
        staffName: (req['name'] ?? 'Staff Member').toString(),
        amount: double.tryParse((req['amount'] ?? 0).toString()) ?? 0,
        claimUpiId: req['upiId']?.toString(),
        claimAccountNo: req['accountNo']?.toString(),
        claimIfscCode: req['ifscCode']?.toString(),
      );
      if (ok && mounted) _fetchApprovals(showLoader: false);
      return;
    }

    try {
      final msg = await _approvalsService.approveRequest(type: _currentType, requestId: reqId, remarks: 'Approved');
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _fetchApprovals(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to approve');
    }
  }

  Future<void> _showRejectDialog(Map<String, dynamic> req) async {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString();
    final isBatch = AdminApprovalsService.batchTypes.contains(_currentType);
    final String? reason;
    if (isBatch) {
      // Punch/fine rejects take no reason on the backend; just confirm.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Reject Request', style: AppTextStyles.headingMedium),
          content: Text(
            _currentType == 'punch' ? 'Rejecting marks this attendance as absent. Continue?' : 'Reject this fine adjustment?',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, minimumSize: const Size(96, 44)),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      reason = '';
    } else {
      reason = await showApprovalReasonDialog(
        context,
        title: 'Reject Request',
        subtitle: 'Please provide a reason for rejecting this request:',
      );
      if (reason == null) return;
    }
    if (!mounted) return;
    try {
      final msg = await _approvalsService.rejectRequest(type: _currentType, requestId: reqId, reason: reason);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      _fetchApprovals(showLoader: false);
    } catch (e) {
      if (mounted) showApprovalError(context, e, fallback: 'Failed to reject');
    }
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
        title: const Text('Approvals Hub'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _fetchApprovals(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: _approvalTabs.map((t) => Tab(text: t['label'])).toList(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchApprovals(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Summary Stats Pill Bar ──
                  _buildSummaryStats(),
                  const SizedBox(height: 16),

                  // ── Search and Status Filter Row ──
                  _buildSearchAndFilters(),
                  const SizedBox(height: 16),

                  // ── Requests List ──
                  if (_loadError != null)
                    ApprovalErrorView(message: _loadError!, onRetry: () => _fetchApprovals())
                  else if (_requests.isEmpty)
                    Container(
                      alignment: Alignment.center,
                      decoration: approvalCardDecoration(),
                      child: const ApprovalEmptyView(
                        icon: Icons.assignment_turned_in_outlined,
                        title: 'No requests found',
                      ),
                    )
                  else
                    ..._requests.map((r) => _buildRequestCard(r)),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryStats() {
    return Row(
      children: [
        Expanded(child: _summaryBox('Total', '${_summary['total'] ?? 0}', AppColors.textPrimary)),
        const SizedBox(width: 8),
        Expanded(child: _summaryBox('Pending', '${_summary['pending'] ?? 0}', AppColors.warning)),
        const SizedBox(width: 8),
        Expanded(child: _summaryBox('Approved', '${_summary['approved'] ?? 0}', AppColors.success)),
        const SizedBox(width: 8),
        Expanded(child: _summaryBox('Rejected', '${_summary['rejected'] ?? 0}', AppColors.error)),
      ],
    );
  }

  Widget _summaryBox(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kApprovalBorder),
      ),
      child: Column(
        children: [
          Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E5EA)),
            ),
            child: TextField(
              onChanged: (v) {
                _searchQuery = v;
                _fetchApprovals(showLoader: false);
              },
              style: AppTextStyles.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'Search requests...',
                hintStyle: TextStyle(fontSize: 14, color: AppColors.textCaption),
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textCaption),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E5EA)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _statusFilter,
              borderRadius: BorderRadius.circular(12),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              items: ['All', 'Pending', 'Approved', 'Rejected'].map((s) {
                return DropdownMenuItem(value: s, child: Text(s));
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _statusFilter = v);
                  _fetchApprovals();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> r) {
    final name = (r['name'] ?? r['employeeName'] ?? r['staffName'] ?? 'Staff Member').toString();
    final empId = (r['employeeId'] ?? '—').toString();
    final dept = (r['department'] ?? r['role'] ?? r['designation'] ?? r['shiftName'] ?? '—').toString();
    final String reqType;
    final String date;
    final String reason;
    switch (_currentType) {
      case 'leave':
        reqType = '${r['leaveType'] ?? 'Leave'} • ${r['days'] ?? 1} day(s)';
        final s = formatApprovalDate(r['startDate']);
        final e = formatApprovalDate(r['endDate']);
        date = s == e ? s : '$s → $e';
        reason = (r['reason'] ?? '').toString();
        break;
      case 'permission':
        reqType = '${r['type'] ?? 'Permission'} • ${r['durationMins'] ?? 0} mins';
        date = formatApprovalDate(r['date']);
        reason = (r['reason'] ?? '').toString();
        break;
      case 'punch':
        reqType = 'In ${r['punchInTime'] ?? '—'} / Out ${r['punchOutTime'] ?? '—'}';
        date = (r['punchInLocation'] ?? '').toString() == '—' ? '' : (r['punchInLocation'] ?? '').toString();
        reason = '';
        break;
      case 'fine':
        reqType = 'Fine ₹${r['fineAmountCurrent'] ?? 0}';
        date = (r['date'] ?? '').toString();
        reason = 'Late ₹${r['lateFineAmount'] ?? 0} • Early exit ₹${r['earlyFineAmount'] ?? 0}';
        break;
      case 'expense':
        reqType = '${r['category'] ?? 'Expense'} • ₹${r['amount'] ?? 0}';
        date = formatApprovalDate(r['date']);
        reason = (r['description'] ?? '').toString();
        break;
      default:
        reqType = 'Payslip • ${r['targetMonth'] ?? ''}';
        date = (r['requestDate'] ?? '').toString();
        reason = (r['purpose'] ?? '').toString();
    }
    final status = _statusOf(r);

    final isPending = status.toLowerCase() == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: approvalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ApprovalCardHeader(
            leading: ApprovalAvatar(name: name),
            title: name,
            subtitle: '$empId • $dept',
            trailing: ApprovalStatusPill(status: status, label: status.toUpperCase()),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TYPE', style: AppTextStyles.sectionLabel),
                      const SizedBox(height: 4),
                      Text(reqType, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (date.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DATE / PERIOD', style: AppTextStyles.sectionLabel),
                        const SizedBox(height: 4),
                        Text(date, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Reason: $reason',
              style: AppTextStyles.bodySmall.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showRejectDialog(r),
                    style: approvalRejectStyle(),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleApprove(r),
                    style: approvalApproveStyle(),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
