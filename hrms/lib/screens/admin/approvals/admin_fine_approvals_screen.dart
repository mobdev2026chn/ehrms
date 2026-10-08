// lib/screens/admin/approvals/admin_fine_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'approval_shared_widgets.dart';

class AdminFineRecord {
  final String id;
  final String employeeName;
  final String employeeId;
  final String shiftName;
  final String shiftTime;
  final String punchIn;
  final String punchOut;
  final String lateActualHrs;
  final String lateUpdatedHrs;
  final String lateFineOption;
  final double lateFineAmount;
  final String earlyActualHrs;
  final String earlyUpdatedHrs;
  final String earlyFineOption;
  final double earlyFineAmount;
  String status; // 'Approval Pending' | 'Approved' | 'Saved' | 'Rejected'

  AdminFineRecord({
    required this.id,
    required this.employeeName,
    required this.employeeId,
    required this.shiftName,
    this.shiftTime = '09:00 AM – 06:00 PM',
    required this.punchIn,
    required this.punchOut,
    required this.lateActualHrs,
    required this.lateUpdatedHrs,
    this.lateFineOption = 'Auto Calculate',
    required this.lateFineAmount,
    required this.earlyActualHrs,
    required this.earlyUpdatedHrs,
    this.earlyFineOption = 'Auto Calculate',
    required this.earlyFineAmount,
    required this.status,
  });

  double get totalFine => lateFineAmount + earlyFineAmount;

  /// One row of GET /admin/approvals/fine (`data[]`). Backend statuses: 'Approval Pending',
  /// 'Saved' (approved) and 'Edited' (rejected).
  factory AdminFineRecord.fromJson(Map<String, dynamic> json) {
    final raw = (json['status'] ?? 'Approval Pending').toString();
    final status = raw == 'Saved' || raw == 'Approved' ? 'Approved' : (raw == 'Edited' || raw == 'Rejected' ? 'Rejected' : 'Approval Pending');
    String hm(dynamic h, dynamic m) {
      final hh = int.tryParse((h ?? 0).toString()) ?? 0;
      final mm = int.tryParse((m ?? 0).toString()) ?? 0;
      return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')} hrs';
    }
    String actual(dynamic v) {
      final s = (v ?? '00:00').toString();
      return s.endsWith('hrs') ? s : '$s hrs';
    }

    return AdminFineRecord(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      employeeName: (json['employeeName'] ?? 'Staff Member').toString(),
      employeeId: (json['employeeId'] ?? '—').toString(),
      shiftName: (json['shiftName'] ?? 'General Shift').toString(),
      shiftTime: (json['shiftTime'] ?? '—').toString(),
      punchIn: (json['punchIn'] ?? '—').toString(),
      punchOut: (json['punchOut'] ?? '—').toString(),
      lateActualHrs: actual(json['lateActualHrs']),
      lateUpdatedHrs: hm(json['lateUpdatedHrsHour'], json['lateUpdatedHrsMin']),
      lateFineOption: (json['lateFineOption'] ?? 'Auto Calculate').toString(),
      lateFineAmount: double.tryParse((json['lateFineAmount'] ?? 0).toString()) ?? 0,
      earlyActualHrs: actual(json['earlyActualHrs']),
      earlyUpdatedHrs: hm(json['earlyUpdatedHrsHour'], json['earlyUpdatedHrsMin']),
      earlyFineOption: (json['earlyFineOption'] ?? 'Auto Calculate').toString(),
      earlyFineAmount: double.tryParse((json['earlyFineAmount'] ?? 0).toString()) ?? 0,
      status: status,
    );
  }
}

class AdminFineApprovalsScreen extends StatefulWidget {
  const AdminFineApprovalsScreen({super.key});

  @override
  State<AdminFineApprovalsScreen> createState() => _AdminFineApprovalsScreenState();
}

class _AdminFineApprovalsScreenState extends State<AdminFineApprovalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminApprovalsService _service = AdminApprovalsService();
  String? _loadError;
  bool _submitting = false;

  bool _isLoading = true;
  String _searchQuery = '';
  DateTime _selectedDate = DateTime.now();
  final Set<String> _selectedIds = {};
  List<AdminFineRecord> _records = [];

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
      final list = await _service.getFineApprovals(date: DateFormat('yyyy-MM-dd').format(_selectedDate));
      if (!mounted) return;
      setState(() {
        _records = list.map(AdminFineRecord.fromJson).toList();
        _selectedIds.removeWhere((id) => !_records.any((r) => r.id == id));
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = AdminApprovalsService.messageOf(e, fallback: 'Failed to load fine approvals');
      setState(() {
        _loadError = msg;
        _isLoading = false;
      });
      if (!showLoader) SnackBarUtils.showSnackBar(context, msg, isError: true);
    }
  }

  List<AdminFineRecord> get _filteredRecords {
    if (_searchQuery.isEmpty) return _records;
    return _records.where((r) {
      return r.employeeName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.employeeId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.shiftName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Map<String, List<AdminFineRecord>> get _groupedByShift {
    final map = <String, List<AdminFineRecord>>{};
    for (var r in _filteredRecords) {
      map.putIfAbsent(r.shiftName, () => []).add(r);
    }
    return map;
  }

  // ── Actions: POST /admin/approvals/fine/approve|reject { ids } ──
  Future<void> _decide(List<String> ids, bool approve) async {
    if (ids.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final msg = approve ? await _service.approveFines(ids) : await _service.rejectFines(ids);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _selectedIds.removeAll(ids);
      });
      SnackBarUtils.showSnackBar(context, msg);
      _loadData(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showApprovalError(context, e, fallback: approve ? 'Failed to approve fines' : 'Failed to reject fines');
    }
  }

  Future<void> _handleApproveSingle(AdminFineRecord r) => _decide([r.id], true);

  Future<void> _handleRejectSingle(AdminFineRecord r) => _decide([r.id], false);

  Future<void> _handleBulkAction(String decision) => _decide(_selectedIds.toList(), decision == 'Approved');

  @override
  Widget build(BuildContext context) {
    final shiftGroups = _groupedByShift;
    final unapprovedRecords = _filteredRecords.where((r) => r.status == 'Approval Pending').toList();
    final allSelected = unapprovedRecords.isNotEmpty && unapprovedRecords.every((r) => _selectedIds.contains(r.id));

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
        title: const Text('Review Fine'),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () => _loadData(showLoader: false),
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Top Control Bar: Search & Date Picker
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: approvalCardDecoration(),
                        child: Column(
                          children: [
                            // Search Bar
                            Container(
                              height: 44,
                              decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
                              child: TextField(
                                onChanged: (v) => setState(() => _searchQuery = v),
                                style: AppTextStyles.bodyMedium,
                                decoration: const InputDecoration(
                                  hintText: 'Search by employee name / emp ID',
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

                            // Date Picker
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2028),
                                );
                                if (picked != null) {
                                  setState(() => _selectedDate = picked);
                                  _loadData();
                                }
                              },
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F8FA),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E5EA)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.primaryText),
                                        const SizedBox(width: 8),
                                        Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Select All Header Bar
                      if (unapprovedRecords.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: allSelected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedIds.addAll(unapprovedRecords.map((e) => e.id));
                                      } else {
                                        for (var e in unapprovedRecords) {
                                          _selectedIds.remove(e.id);
                                        }
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text('Select All', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),

                      // Shift Sections
                      if (_loadError != null)
                        ApprovalErrorView(message: _loadError!, onRetry: () => _loadData())
                      else if (shiftGroups.isEmpty)
                        Container(
                          alignment: Alignment.center,
                          decoration: approvalCardDecoration(),
                          child: const ApprovalEmptyView(
                            icon: Icons.receipt_long_outlined,
                            title: 'No fine adjustment records found for this date',
                          ),
                        )
                      else
                        ...shiftGroups.entries.map((entry) => _buildShiftSection(entry.key, entry.value)),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),

                // Floating Action Bar for Multi-Selected Items (Screenshot 3 & 4)
                if (_selectedIds.isNotEmpty)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Selected ${_selectedIds.length} staff member(s)',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _submitting ? null : () => _handleBulkAction('Approved'),
                            style: approvalApproveStyle().copyWith(
                              minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
                              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                            child: const Text('Approve'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _submitting ? null : () => _handleBulkAction('Rejected'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: const Size(0, 36),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            child: const Text('Reject'),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () => setState(() => _selectedIds.clear()),
                            child: const Text('Cancel', style: TextStyle(color: AppColors.textCaption, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildShiftSection(String shiftName, List<AdminFineRecord> list) {
    final unapprovedInShift = list.where((r) => r.status == 'Approval Pending').toList();
    final allShiftSelected = unapprovedInShift.isNotEmpty && unapprovedInShift.every((r) => _selectedIds.contains(r.id));
    final selectedInShiftCount = list.where((r) => _selectedIds.contains(r.id)).length;
    final shiftTime = list.first.shiftTime;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shift Sub-header banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (unapprovedInShift.isNotEmpty) ...[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: allShiftSelected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedIds.addAll(unapprovedInShift.map((e) => e.id));
                          } else {
                            for (var e in unapprovedInShift) {
                              _selectedIds.remove(e.id);
                            }
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Text(shiftName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(999)),
                  child: Text(shiftTime, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryText)),
                ),
                const Spacer(),
                Text('$selectedInShiftCount/${list.length} selected', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Cards List
          ...list.map((r) => _buildFineCard(r)),
        ],
      ),
    );
  }

  Widget _buildFineCard(AdminFineRecord r) {
    final isSelected = _selectedIds.contains(r.id);
    final isPending = r.status == 'Approval Pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: approvalCardDecoration(borderColor: isSelected ? AppColors.primary : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Checkbox + Staff + Status
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (isPending) ...[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedIds.add(r.id);
                          } else {
                            _selectedIds.remove(r.id);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ApprovalCardHeader(
                    leading: ApprovalAvatar(name: r.employeeName),
                    title: r.employeeName,
                    subtitle: r.employeeId,
                    trailing: ApprovalStatusPill(
                      status: isPending ? 'pending' : 'approved',
                      label: isPending ? 'Approval Pending' : 'Approved',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Body: Punch in & Punch out + Fine Breakdown
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Punch in / out row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PUNCH IN TIME', style: AppTextStyles.sectionLabel),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                const Icon(Icons.login_rounded, size: 16, color: AppColors.success),
                                const SizedBox(width: 8),
                                Flexible(child: Text(r.punchIn, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PUNCH OUT TIME', style: AppTextStyles.sectionLabel),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                const Icon(Icons.logout_rounded, size: 16, color: AppColors.error),
                                const SizedBox(width: 8),
                                Flexible(child: Text(r.punchOut, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Fine Adjustment Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('₹', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryText)),
                          const SizedBox(width: 4),
                          const Text('FINE ADJUSTMENT', style: AppTextStyles.sectionLabel),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Late Fine
                      _buildFineSection(
                        title: 'Late Fine',
                        color: AppColors.warning,
                        actualHrs: r.lateActualHrs,
                        updatedHrs: r.lateUpdatedHrs,
                        option: r.lateFineOption,
                        amount: r.lateFineAmount,
                      ),
                      const SizedBox(height: 8),

                      // Early Exit Fine
                      _buildFineSection(
                        title: 'Early Exit Fine',
                        color: AppColors.info,
                        actualHrs: r.earlyActualHrs,
                        updatedHrs: r.earlyUpdatedHrs,
                        option: r.earlyFineOption,
                        amount: r.earlyFineAmount,
                      ),
                      const SizedBox(height: 12),

                      // Section Total
                      Row(
                        children: [
                          Text('Total Fine: ', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text('₹ ${r.totalFine.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.error)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Card Footer
                Text(
                  'TOTAL FINE: ₹${r.totalFine.toStringAsFixed(2)}',
                  style: AppTextStyles.headingSmall,
                ),
                if (isPending) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _handleRejectSingle(r),
                          style: approvalRejectStyle(),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _handleApproveSingle(r),
                          style: approvalApproveStyle(),
                          child: const Text('Approve'),
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

  Widget _buildFineSection({
    required String title,
    required Color color,
    required String actualHrs,
    required String updatedHrs,
    required String option,
    required double amount,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kApprovalBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              _metricBox('ACTUAL HRS', actualHrs),
              const SizedBox(width: 4),
              _metricBox('UPDATED HRS', updatedHrs),
              const SizedBox(width: 4),
              _metricBox('FINE OPTION', option),
              const SizedBox(width: 4),
              _metricBox('FINE AMOUNT', '₹${amount.toStringAsFixed(2)}', isAmount: true, amount: amount),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String label, String value, {bool isAmount = false, double amount = 0}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Container(
            height: 30,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isAmount
                  ? (amount > 0 ? AppColors.errorBg : AppColors.successBg)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isAmount
                    ? (amount > 0 ? AppColors.error : AppColors.success)
                    : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
