// Leaves / Permissions / Reimbursement / Payslip Requests tabs of the admin Staff
// Detail screen (web: staffManagement/leaves.tsx, permissions.tsx,
// reimbursement.tsx, payslipRequests.tsx). Each reads the matching approvals
// queue filtered to this staff member (?staffId=) and approves / rejects in place.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../config/app_colors.dart';
import '../../../../../config/app_text_styles.dart';
import '../../../../../services/admin_staff_detail_service.dart';
import '../staff_detail_common.dart';

class StaffRequestsTab extends StatefulWidget {
  const StaffRequestsTab({super.key, required this.staffId, required this.kind});

  final String staffId;
  final StaffRequestKind kind;

  @override
  State<StaffRequestsTab> createState() => _StaffRequestsTabState();
}

class _StaffRequestsTabState extends State<StaffRequestsTab> {
  final _service = AdminStaffDetailService();

  String _status = 'All';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String? _busyId;

  List<String> get _statuses {
    switch (widget.kind) {
      case StaffRequestKind.leave:
        return const ['All', 'Pending', 'Approved', 'Rejected', 'Cancelled'];
      case StaffRequestKind.expense:
        return const ['All', 'Pending', 'Approved', 'Paid', 'Rejected'];
      default:
        return const ['All', 'Pending', 'Approved', 'Rejected'];
    }
  }

  String get _noun {
    switch (widget.kind) {
      case StaffRequestKind.leave:
        return 'leave requests';
      case StaffRequestKind.permission:
        return 'permission requests';
      case StaffRequestKind.expense:
        return 'reimbursement claims';
      case StaffRequestKind.payslip:
        return 'payslip requests';
    }
  }

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
      final items = await _service.getRequests(widget.kind, widget.staffId, status: _status);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _act(String id, Future<Map<String, dynamic>> Function() call, String ok) async {
    setState(() => _busyId = id);
    try {
      final res = await call();
      if (!mounted) return;
      setState(() => _busyId = null);
      sdShowSuccess(context, sdStr(res['message'], ok));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      sdShowError(context, e);
    }
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    final id = sdStr(r['id']);
    if (widget.kind == StaffRequestKind.expense) {
      final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _ExpenseApproveDialog(amount: r['amount'], upiId: sdStr(r['upiId'])),
      );
      if (payload == null) return;
      await _act(id, () => _service.approveRequest(widget.kind, id, payload), 'Claim marked as paid.');
      return;
    }
    final remarks = await sdAskText(context,
        title: 'Approve Request', label: 'Remarks (optional)', required: false, confirmText: 'Approve');
    if (remarks == null) return;
    await _act(id, () => _service.approveRequest(widget.kind, id, {'remarks': remarks}), 'Request approved.');
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final id = sdStr(r['id']);
    final reason = await sdAskText(context, title: 'Reject Request', label: 'Reason', confirmText: 'Reject');
    if (reason == null) return;
    await _act(id, () => _service.rejectRequest(widget.kind, id, reason), 'Request rejected.');
  }

  Future<void> _cancelLeave(Map<String, dynamic> r) async {
    final id = sdStr(r['id']);
    final reason = await sdAskText(context, title: 'Cancel Approved Leave', label: 'Reason', confirmText: 'Cancel Leave');
    if (reason == null) return;
    await _act(id, () => _service.cancelLeave(id, reason), 'Leave cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _statuses.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _statuses[i];
                final selected = s == _status;
                return ChoiceChip(
                  label: Text(s),
                  selected: selected,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.onPrimary : kSdInk),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: selected ? AppColors.primary : kSdLine),
                  shape: const StadiumBorder(),
                  onSelected: (_) {
                    if (selected) return;
                    setState(() => _status = s);
                    _load();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const SdLoading()
          else if (_error != null)
            SdErrorView(message: _error!, onRetry: _load)
          else if (_items.isEmpty)
            SdEmptyView(message: 'No $_noun found', icon: Icons.inbox_outlined)
          else
            ..._items.map(_buildCard),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final status = sdStr(r['status'], 'Pending');
    final id = sdStr(r['id']);
    final busy = _busyId == id;
    final rows = <Widget>[];
    String title;

    switch (widget.kind) {
      case StaffRequestKind.leave:
        final days = sdNum(r['days']);
        title = sdStr(r['leaveType'], 'Leave');
        rows.addAll([
          SdKeyValue('Dates', '${sdFmtDate(r['startDate'])} - ${sdFmtDate(r['endDate'])}'),
          SdKeyValue('Days',
              '${days % 1 == 0 ? days.toInt() : days}${r['isHalfDay'] == true ? ' (Half day ${sdStr(r['halfDaySession'])})' : ''}'),
          SdKeyValue('Category', sdStr(r['leaveTypeCategory'], 'paid')),
          SdKeyValue('Reason', sdStr(r['reason'], '-')),
        ]);
        break;
      case StaffRequestKind.permission:
        title = '${sdStr(r['type'], 'Permission')} permission';
        final mins = sdNum(r['durationMins']).toInt();
        rows.addAll([
          SdKeyValue('Date', sdFmtDate(r['date'])),
          SdKeyValue('Duration', mins > 0 ? '${mins ~/ 60}h ${mins % 60}m' : '-'),
          SdKeyValue('Reason', sdStr(r['reason'], '-')),
        ]);
        break;
      case StaffRequestKind.expense:
        title = sdStr(r['category'], 'Expense');
        rows.addAll([
          SdKeyValue('Date', sdFmtDate(r['date'])),
          SdKeyValue('Amount', sdMoney(r['amount'])),
          SdKeyValue('Description', sdStr(r['description'], '-')),
          if (sdStr(r['paymentRoute']).isNotEmpty)
            SdKeyValue('Payment', '${r['paymentRoute']}${sdStr(r['payrollMonth']).isNotEmpty ? ' · ${r['payrollMonth']}' : ''}'),
        ]);
        break;
      case StaffRequestKind.payslip:
        title = 'Payslip · ${sdStr(r['targetMonth'], '-')}';
        rows.addAll([
          SdKeyValue('Requested', sdStr(r['requestDate'], '-')),
          SdKeyValue('Purpose', sdStr(r['purpose'], '-')),
          SdKeyValue('Payroll', r['payrollPaid'] == true ? 'Paid' : (r['payrollGenerated'] == true ? 'Generated' : 'Not generated')),
        ]);
        break;
    }
    if (status != 'Pending') {
      rows.add(SdKeyValue('Reviewed By', sdStr(r['approvedBy'], '-')));
    }
    final remark = sdStr(r['rejectionReason']).isNotEmpty ? sdStr(r['rejectionReason']) : sdStr(r['remarks']);
    if (remark.isNotEmpty && remark != '—') rows.add(SdKeyValue('Remarks', remark));

    final canDecide = status == 'Pending' || (widget.kind == StaffRequestKind.expense && status == 'Approved');
    final canCancel = widget.kind == StaffRequestKind.leave && status == 'Approved';

    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(title, style: AppTextStyles.headingSmall),
            ),
            SdPill.status(status),
          ]),
          if (sdStr(r['requestId']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sdStr(r['requestId']), style: AppTextStyles.caption.copyWith(color: kSdSubtle)),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...rows,
          if (canDecide || canCancel) ...[
            const SizedBox(height: 12),
            if (busy)
              const LinearProgressIndicator(minHeight: 2)
            else
              Row(children: [
                if (canDecide) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(r),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _approve(r),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(widget.kind == StaffRequestKind.expense ? 'Approve & Pay' : 'Approve'),
                    ),
                  ),
                ],
                if (canCancel)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _cancelLeave(r),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel Leave'),
                    ),
                  ),
              ]),
          ],
        ],
      ),
    );
  }
}

/// Payment route for an expense claim: added to a payroll month, or paid out now.
class _ExpenseApproveDialog extends StatefulWidget {
  const _ExpenseApproveDialog({required this.amount, required this.upiId});
  final dynamic amount;
  final String upiId;

  @override
  State<_ExpenseApproveDialog> createState() => _ExpenseApproveDialogState();
}

class _ExpenseApproveDialogState extends State<_ExpenseApproveDialog> {
  String _route = 'Payroll';
  late String _month;
  late final List<String> _months;
  late final TextEditingController _upi;
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _remarks = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _months = [for (var i = 0; i < 12; i++) DateFormat('MMMM yyyy').format(DateTime(now.year, now.month - i))];
    _month = _months.first;
    _upi = TextEditingController(text: widget.upiId);
  }

  @override
  void dispose() {
    _upi.dispose();
    _account.dispose();
    _ifsc.dispose();
    _remarks.dispose();
    super.dispose();
  }

  String? _nn(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Approve ${sdMoney(widget.amount)}', style: AppTextStyles.headingMedium),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _route,
              decoration: sdInput('Payment Route'),
              items: const [
                DropdownMenuItem(value: 'Payroll', child: Text('Add to Payroll')),
                DropdownMenuItem(value: 'Immediate', child: Text('Pay Immediately')),
              ],
              onChanged: (v) => setState(() => _route = v ?? 'Payroll'),
            ),
            const SizedBox(height: 12),
            if (_route == 'Payroll')
              DropdownButtonFormField<String>(
                initialValue: _month,
                decoration: sdInput('Payroll Month'),
                items: _months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _month = v ?? _month),
              )
            else ...[
              TextField(controller: _upi, decoration: sdInput('UPI ID')),
              const SizedBox(height: 12),
              TextField(controller: _account, decoration: sdInput('Account Number')),
              const SizedBox(height: 12),
              TextField(controller: _ifsc, decoration: sdInput('IFSC Code')),
            ],
            const SizedBox(height: 12),
            TextField(controller: _remarks, decoration: sdInput('Remarks (optional)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: sdPrimaryButton(),
          onPressed: () => Navigator.pop(context, <String, dynamic>{
            'paymentRoute': _route,
            'payrollMonth': _route == 'Payroll' ? _month : null,
            'upiId': _route == 'Immediate' ? _nn(_upi) : null,
            'accountNo': _route == 'Immediate' ? _nn(_account) : null,
            'ifscCode': _route == 'Immediate' ? _nn(_ifsc) : null,
            'proofImg': null,
            if (_remarks.text.trim().isNotEmpty) 'remarks': _remarks.text.trim(),
          }),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
