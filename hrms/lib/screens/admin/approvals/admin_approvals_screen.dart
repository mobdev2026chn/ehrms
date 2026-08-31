// lib/screens/admin/approvals/admin_approvals_screen.dart
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

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
  String _statusFilter = 'All'; // 'All' | 'Pending' | 'Approved' | 'Rejected'
  String _searchQuery = '';

  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic> _summary = {'total': 0, 'pending': 0, 'approved': 0, 'rejected': 0};

  @override
  void initState() {
    super.initState();
    _currentType = widget.initialType;
    int initialIdx = _approvalTabs.indexWhere((t) => t['type'] == widget.initialType);
    if (initialIdx < 0) initialIdx = 0;

    _tabController = TabController(length: _approvalTabs.length, vsync: this, initialIndex: initialIdx);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _currentType = _approvalTabs[_tabController.index]['type']!;
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

  Future<void> _fetchApprovals({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _approvalsService.getApprovalsList(
        type: _currentType,
        status: _statusFilter,
        search: _searchQuery,
      );

      if (res['success'] == true && res['data'] != null) {
        final rawReqs = (res['data']['requests'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final rawSummary = res['data']['summary'] is Map ? Map<String, dynamic>.from(res['data']['summary']) : null;

        if (mounted) {
          setState(() {
            _requests = rawReqs;
            if (rawSummary != null) {
              _summary = rawSummary;
            } else {
              int p = 0, a = 0, r = 0;
              for (final x in rawReqs) {
                final st = (x['status'] ?? '').toString().toLowerCase();
                if (st == 'pending') p++;
                if (st == 'approved') a++;
                if (st == 'rejected') r++;
              }
              _summary = {'total': rawReqs.length, 'pending': p, 'approved': a, 'rejected': r};
            }
          });
        }
      }
    } catch (_) {}

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleApprove(Map<String, dynamic> req) async {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString();
    final res = await _approvalsService.approveRequest(type: _currentType, requestId: reqId);
    if (res['success'] == true) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, 'Request approved successfully');
        _fetchApprovals(showLoader: false);
      }
    } else {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, res['message'] ?? 'Failed to approve', isError: true);
      }
    }
  }

  void _showRejectDialog(Map<String, dynamic> req) {
    final reqId = (req['id'] ?? req['_id'] ?? '').toString();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Request', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Please provide a reason for rejecting this request:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter reason...',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEFAA1F))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonCtrl.text.trim().isEmpty) {
                  SnackBarUtils.showSnackBar(context, 'Please enter a reason', isError: true);
                  return;
                }
                Navigator.pop(ctx);
                final res = await _approvalsService.rejectRequest(type: _currentType, requestId: reqId, reason: reasonCtrl.text.trim());
                if (res['success'] == true) {
                  if (mounted) {
                    SnackBarUtils.showSnackBar(context, 'Request rejected');
                    _fetchApprovals(showLoader: false);
                  }
                } else {
                  if (mounted) {
                    SnackBarUtils.showSnackBar(context, res['message'] ?? 'Failed to reject', isError: true);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Approvals Hub',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _fetchApprovals(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFFD97706),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFFD97706),
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                  const SizedBox(height: 14),

                  // ── Search and Status Filter Row ──
                  _buildSearchAndFilters(),
                  const SizedBox(height: 16),

                  // ── Requests List ──
                  if (_requests.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Column(
                        children: const [
                          Icon(Icons.assignment_turned_in_outlined, size: 40, color: Color(0xFF94A3B8)),
                          SizedBox(height: 10),
                          Text(
                            'No pending requests found',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                          ),
                        ],
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
        Expanded(child: _summaryBox('Total', '${_summary['total'] ?? 0}', const Color(0xFF64748B))),
        const SizedBox(width: 8),
        Expanded(child: _summaryBox('Pending', '${_summary['pending'] ?? 0}', const Color(0xFFD97706))),
        const SizedBox(width: 8),
        Expanded(child: _summaryBox('Approved', '${_summary['approved'] ?? 0}', const Color(0xFF10B981))),
        const SizedBox(width: 8),
        Expanded(child: _summaryBox('Rejected', '${_summary['rejected'] ?? 0}', const Color(0xFFEF4444))),
      ],
    );
  }

  Widget _summaryBox(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        children: [
          Text(count, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 1),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              onChanged: (v) {
                _searchQuery = v;
                _fetchApprovals(showLoader: false);
              },
              decoration: const InputDecoration(
                hintText: 'Search requests...',
                hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _statusFilter,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
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
    final name = (r['name'] ?? r['employeeName'] ?? 'Staff Member').toString();
    final empId = (r['employeeId'] ?? '—').toString();
    final dept = (r['department'] ?? 'Engineering').toString();
    final reqType = (r['leaveType'] ?? r['type'] ?? r['category'] ?? _currentType).toString();
    final status = (r['status'] ?? 'Pending').toString();
    final reason = (r['reason'] ?? r['remarks'] ?? '').toString();
    final date = (r['startDate'] != null ? '${r['startDate']} → ${r['endDate'] ?? ''}' : (r['date'] ?? '')).toString();

    final isPending = status.toLowerCase() == 'pending';

    Color stBg;
    Color stFg;
    if (status.toLowerCase() == 'approved') {
      stBg = const Color(0xFFDCFCE7);
      stFg = const Color(0xFF16A34A);
    } else if (status.toLowerCase() == 'rejected') {
      stBg = const Color(0xFFFEE2E2);
      stFg = const Color(0xFFDC2626);
    } else {
      stBg = const Color(0xFFFEF3C7);
      stFg = const Color(0xFFD97706);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$empId • $dept',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: stBg, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: stFg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TYPE', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                      const SizedBox(height: 1),
                      Text(reqType, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    ],
                  ),
                ),
                if (date.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DATE / PERIOD', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                        const SizedBox(height: 1),
                        Text(date, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: $reason',
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontStyle: FontStyle.italic),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showRejectDialog(r),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Reject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleApprove(r),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
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
