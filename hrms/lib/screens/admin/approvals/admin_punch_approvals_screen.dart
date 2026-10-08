// lib/screens/admin/approvals/admin_punch_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'approval_shared_widgets.dart';

class AdminPunchRecord {
  final String id;
  final String staffName;
  final String employeeId;
  final String department;
  final String shiftName;
  final String punchInTime;
  final String punchInLocation;
  final String? punchInPhoto;
  final String punchOutTime;
  final String punchOutLocation;
  final String? punchOutPhoto;
  final bool isPendingApproval;
  String status; // 'present' | 'half_day' | 'leave' | 'absent' | 'Approved' | 'Pending'

  AdminPunchRecord({
    required this.id,
    required this.staffName,
    required this.employeeId,
    required this.department,
    required this.shiftName,
    required this.punchInTime,
    required this.punchInLocation,
    this.punchInPhoto,
    required this.punchOutTime,
    required this.punchOutLocation,
    this.punchOutPhoto,
    required this.isPendingApproval,
    required this.status,
  });

  String get initials {
    final parts = staffName.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return staffName.isNotEmpty ? staffName[0].toUpperCase() : 'U';
  }

  /// One row of GET /admin/approvals/punch (`data[]`).
  factory AdminPunchRecord.fromJson(Map<String, dynamic> json) {
    final isPending = json['isPendingApproval'] == true;
    String? photo(dynamic v) {
      final s = (v ?? '').toString();
      return s.isEmpty ? null : s;
    }

    return AdminPunchRecord(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      staffName: (json['staffName'] ?? 'Staff Member').toString(),
      employeeId: (json['employeeId'] ?? '—').toString(),
      department: (json['department'] ?? '—').toString(),
      shiftName: (json['shiftName'] ?? 'General Shift').toString(),
      punchInTime: (json['punchInTime'] ?? '—').toString(),
      punchInLocation: (json['punchInLocation'] ?? '—').toString(),
      punchInPhoto: photo(json['punchInSelfie']),
      punchOutTime: (json['punchOutTime'] ?? '—').toString(),
      punchOutLocation: (json['punchOutLocation'] ?? '—').toString(),
      punchOutPhoto: photo(json['punchOutSelfie']),
      isPendingApproval: isPending,
      status: (json['status'] ?? '').toString(),
    );
  }
}

class AdminPunchApprovalsScreen extends StatefulWidget {
  const AdminPunchApprovalsScreen({super.key});

  @override
  State<AdminPunchApprovalsScreen> createState() => _AdminPunchApprovalsScreenState();
}

class _AdminPunchApprovalsScreenState extends State<AdminPunchApprovalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminApprovalsService _service = AdminApprovalsService();
  String? _loadError;
  bool _submitting = false;

  bool _isLoading = true;
  String _searchQuery = '';
  DateTime _selectedDate = DateTime.now();
  final Set<String> _selectedIds = {};
  List<AdminPunchRecord> _records = [];

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
      final list = await _service.getPunchApprovals(date: DateFormat('yyyy-MM-dd').format(_selectedDate));
      if (!mounted) return;
      setState(() {
        _records = list.map(AdminPunchRecord.fromJson).toList();
        _selectedIds.removeWhere((id) => !_records.any((r) => r.id == id));
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = AdminApprovalsService.messageOf(e, fallback: 'Failed to load punch approvals');
      setState(() {
        _loadError = msg;
        _isLoading = false;
      });
      if (!showLoader) SnackBarUtils.showSnackBar(context, msg, isError: true);
    }
  }

  List<AdminPunchRecord> get _filteredRecords {
    if (_searchQuery.isEmpty) return _records;
    return _records.where((r) {
      return r.staffName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.employeeId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.shiftName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.department.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Map<String, List<AdminPunchRecord>> get _groupedByShift {
    final map = <String, List<AdminPunchRecord>>{};
    for (var r in _filteredRecords) {
      map.putIfAbsent(r.shiftName, () => []).add(r);
    }
    return map;
  }

  // ── Batch decide: POST /admin/approvals/punch/approve|reject { ids } ──
  Future<void> _decide(List<String> ids, bool approve) async {
    if (ids.isEmpty || _submitting) return;
    if (!approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Reject Attendance', style: AppTextStyles.headingMedium),
          content: Text('Rejecting marks ${ids.length} attendance record(s) as absent. Continue?',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
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
      if (confirmed != true || !mounted) return;
    }
    setState(() => _submitting = true);
    try {
      final msg = approve ? await _service.approvePunches(ids) : await _service.rejectPunches(ids);
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
      showApprovalError(context, e, fallback: approve ? 'Failed to approve attendance' : 'Failed to reject attendance');
    }
  }

  Future<void> _handleBulkAction(String decision) => _decide(_selectedIds.toList(), decision == 'Approved');

  Widget _selfie(String label, String? url) {
    return Expanded(
      child: Column(
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.sectionLabel.copyWith(fontSize: 10, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: url == null
                ? Container(
                    height: 96,
                    color: AppColors.background,
                    alignment: Alignment.center,
                    child: const Text('No photo', style: AppTextStyles.caption),
                  )
                : Image.network(
                    url,
                    height: 96,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 96,
                      color: AppColors.background,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined, color: AppColors.textCaption),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Action: Punch Details Modal ──
  void _showPunchDetailModal(AdminPunchRecord r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        contentPadding: const EdgeInsets.all(20),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.fingerprint_rounded, color: AppColors.primaryText, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Punch Attendance Details', style: AppTextStyles.headingSmall),
                        const SizedBox(height: 2),
                        Text(DateFormat('dd MMMM yyyy').format(_selectedDate), style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.textSecondary),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    ApprovalAvatar(name: r.staffName, initials: r.initials),
                    const SizedBox(width: 12),
                    Expanded(child: Text(r.staffName, style: AppTextStyles.headingSmall)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _detailRow('SHIFT', r.shiftName),
              _detailRow('PUNCH IN', '${r.punchInTime} (${r.punchInLocation})'),
              _detailRow('PUNCH OUT', '${r.punchOutTime} (${r.punchOutLocation})'),
              _detailRow('DAY STATUS', r.status == 'half_day' ? 'Half Day' : 'Present'),
              _detailRow('APPROVAL', r.isPendingApproval ? 'Pending' : 'Approved', isStatus: true),
              const SizedBox(height: 8),
              Row(
                children: [
                  _selfie('PUNCH IN SELFIE', r.punchInPhoto),
                  const SizedBox(width: 12),
                  _selfie('PUNCH OUT SELFIE', r.punchOutPhoto),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _decide([r.id], false);
                      },
                      style: approvalRejectStyle(),
                      child: const Text('Reject'),
                    ),
                  ),
                  if (r.isPendingApproval) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _decide([r.id], true);
                        },
                        style: approvalApproveStyle(),
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(width: 96, child: Text(label, style: AppTextStyles.bodySmall)),
          const SizedBox(width: 8),
          if (isStatus)
            ApprovalStatusPill(status: value, label: value)
          else
            Expanded(child: Text(value, textAlign: TextAlign.end, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shiftGroups = _groupedByShift;

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
        title: const Text('Attendance Pending for Approval'),
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
                      // Top Control Bar: Search, Date Picker, Today
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
                                  hintText: 'Search staff...',
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
                                // Date Picker Button
                                Expanded(
                                  child: InkWell(
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
                                ),
                                const SizedBox(width: 8),

                                // Today Button
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() => _selectedDate = DateTime.now());
                                    _loadData();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  child: const Text('Today'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Shift Sections
                      if (_loadError != null)
                        ApprovalErrorView(message: _loadError!, onRetry: () => _loadData())
                      else if (shiftGroups.isEmpty)
                        Container(
                          alignment: Alignment.center,
                          decoration: approvalCardDecoration(),
                          child: const ApprovalEmptyView(
                            icon: Icons.fingerprint_rounded,
                            title: 'No punch approval records for this date',
                          ),
                        )
                      else
                        ...shiftGroups.entries.map((entry) => _buildShiftSection(entry.key, entry.value)),
                      const SizedBox(height: 80), // bottom space for floating action bar
                    ],
                  ),
                ),

                // Floating Action Bar for Selected Items
                if (_selectedIds.isNotEmpty)
                  Positioned(
                    bottom: 16,
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
                              'Selected ${_selectedIds.length} staff',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _selectedIds.clear()),
                            child: const Text('Cancel', style: TextStyle(color: AppColors.textCaption, fontSize: 13)),
                          ),
                          const SizedBox(width: 4),
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
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _submitting ? null : () => _handleBulkAction('Approved'),
                            style: approvalApproveStyle().copyWith(
                              minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
                              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                            child: const Text('Approve'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildShiftSection(String shiftName, List<AdminPunchRecord> list) {
    final allSelected = list.isNotEmpty && list.every((r) => _selectedIds.contains(r.id));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shift Header
          Row(
            children: [
              Flexible(child: Text(shiftName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingSmall)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                child: Text('${list.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryText)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Shift Card Table
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: approvalCardDecoration(),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: AppColors.background,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: allSelected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.addAll(list.map((e) => e.id));
                              } else {
                                for (var e in list) {
                                  _selectedIds.remove(e.id);
                                }
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text('STAFF', style: AppTextStyles.sectionLabel.copyWith(fontSize: 10, letterSpacing: 0.5))),
                      Expanded(child: Text('PUNCH IN', style: AppTextStyles.sectionLabel.copyWith(fontSize: 10, letterSpacing: 0.5))),
                      Expanded(child: Text('PUNCH OUT', style: AppTextStyles.sectionLabel.copyWith(fontSize: 10, letterSpacing: 0.5))),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Table rows
                ...list.map((r) => _buildPunchRow(r)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPunchRow(AdminPunchRecord r) {
    final isSelected = _selectedIds.contains(r.id);
    final isApproved = !r.isPendingApproval;
    final st = AppColors.statusStyle(isApproved ? 'approved' : 'pending');

    return InkWell(
      onTap: () => _showPunchDetailModal(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: kApprovalBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Checkbox
            SizedBox(
              width: 24,
              height: 24,
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
            const SizedBox(width: 8),

            // Staff column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.staffName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: st.bg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isApproved ? 'APPROVED' : 'PENDING',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: st.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Punch In column
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.login_rounded, size: 14, color: AppColors.success),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.punchInTime, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        Text('● ${r.punchInLocation}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Punch Out column
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.logout_rounded, size: 14, color: AppColors.error),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.punchOutTime, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        Text('● ${r.punchOutLocation}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
