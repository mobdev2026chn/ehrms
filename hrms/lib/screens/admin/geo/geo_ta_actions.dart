// Travel-allowance decisions shared by the Tracking Details and Travel Allowance screens:
// approve (payroll month, or immediate payout by UPI / bank with a proof image), revise the
// figures, and reject with a reason. HRMSbackend /api/admin/hrms-geo/travel-allowance/*.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'geo_admin_ui.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// Approve a claim. Returns true once the backend has approved it.
/// [payout] may carry the staff member's `upiId`, `accountNumber`, `ifscCode`, `bankName`; when
/// it is null they are read from GET /tracking/:staffId for that day.
Future<bool> showTaApproveSheet(
  BuildContext context, {
  required String staffId,
  required String date,
  required double amount,
  String? staffName,
  Map<String, dynamic>? payout,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ApproveSheet(staffId: staffId, date: date, amount: amount, staffName: staffName, payout: payout),
  );
  return r == true;
}

class _ApproveSheet extends StatefulWidget {
  const _ApproveSheet({required this.staffId, required this.date, required this.amount, this.staffName, this.payout});
  final String staffId;
  final String date;
  final double amount;
  final String? staffName;
  final Map<String, dynamic>? payout;

  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
  String _route = 'Payroll'; // Payroll | UPI | Bank
  List<String> _months = [];
  String? _month;
  Map<String, dynamic> _payout = {};
  String? _proof; // data URL
  String? _proofName;
  bool _loading = true;
  String? _error;
  bool _busy = false;

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
      final paid = await AdminGeoService.instance.getPaidPayrollMonths(widget.staffId);
      var payout = widget.payout;
      if (payout == null) {
        final rec = await AdminGeoService.instance
            .getTrackingDetails(widget.staffId, startDate: widget.date, endDate: widget.date);
        payout = rec;
      }
      final now = DateTime.now();
      final all = <String>[
        for (var i = 3; i >= 1; i--) _monthLabel(DateTime(now.year, now.month + i, 1)),
        for (var i = 0; i < 12; i++) _monthLabel(DateTime(now.year, now.month - i, 1)),
      ];
      final open = all.where((m) => !paid.contains(m)).toList();
      if (!mounted) return;
      setState(() {
        _payout = payout ?? {};
        _months = open;
        final current = _monthLabel(now);
        _month = open.contains(current) ? current : (open.isNotEmpty ? open.first : null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String get _upi => GeoUi.s(_payout['upiId']);
  String get _acc => GeoUi.s(_payout['accountNumber'] ?? _payout['accountNo']);
  String get _ifsc => GeoUi.s(_payout['ifscCode']);

  Future<void> _pickProof() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1600);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) GeoUi.fail(context, 'Proof image must be 2 MB or smaller.');
        return;
      }
      final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      setState(() {
        _proof = 'data:image/$ext;base64,${base64Encode(bytes)}';
        _proofName = file.name;
      });
    } catch (e) {
      if (mounted) GeoUi.fail(context, 'Could not read the image: $e');
    }
  }

  Future<void> _submit() async {
    if (_route == 'Payroll' && _month == null) {
      GeoUi.fail(context, 'Choose a payroll month.');
      return;
    }
    if (_route == 'UPI' && _upi.isEmpty) {
      GeoUi.fail(context, 'No UPI ID is saved on this employee\'s profile.');
      return;
    }
    if (_route == 'Bank' && (_acc.isEmpty || _ifsc.isEmpty)) {
      GeoUi.fail(context, 'No bank account is saved on this employee\'s profile.');
      return;
    }
    setState(() => _busy = true);
    try {
      final immediate = _route != 'Payroll';
      await AdminGeoService.instance.approveTravelAllowance(
        staffId: widget.staffId,
        date: widget.date,
        paymentRoute: immediate ? 'Immediate' : 'Payroll',
        payrollMonth: immediate ? null : _month,
        upiId: _route == 'UPI' ? _upi : null,
        accountNo: _route == 'Bank' ? _acc : null,
        ifscCode: _route == 'Bank' ? _ifsc : null,
        proofImg: immediate ? _proof : null,
      );
      if (!mounted) return;
      GeoUi.ok(context, 'Claim approved.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: GeoUi.border, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 14),
          const Text('Approve claim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GeoUi.ink)),
          const SizedBox(height: 4),
          Text('${widget.staffName ?? 'Employee'} · ${GeoUi.date(widget.date)} · ${GeoUi.money(widget.amount)}',
              style: const TextStyle(color: GeoUi.muted, fontSize: 13)),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(padding: EdgeInsets.all(30), child: GeoUi.loading)
          else if (_error != null)
            Column(children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: GeoUi.muted)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ])
          else ...[
            const Text('Payment route', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Payroll', label: Text('Payroll'), icon: Icon(Icons.calendar_month_rounded, size: 18)),
                ButtonSegment(value: 'UPI', label: Text('UPI'), icon: Icon(Icons.qr_code_rounded, size: 18)),
                ButtonSegment(value: 'Bank', label: Text('Bank'), icon: Icon(Icons.account_balance_rounded, size: 18)),
              ],
              selected: {_route},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _route = s.first),
            ),
            const SizedBox(height: 16),
            if (_route == 'Payroll') ...[
              DropdownButtonFormField<String>(
                initialValue: _month,
                isExpanded: true,
                decoration: GeoUi.input('Payroll month'),
                items: [for (final m in _months) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => setState(() => _month = v),
              ),
              const SizedBox(height: 6),
              const Text('Months whose payroll is already paid are not listed.',
                  style: TextStyle(fontSize: 12.5, color: GeoUi.muted)),
            ] else ...[
              if (_route == 'UPI')
                GeoUi.kv('UPI ID', _upi)
              else ...[
                GeoUi.kv('Bank', GeoUi.s(_payout['bankName'])),
                GeoUi.kv('Account no.', _acc),
                GeoUi.kv('IFSC', _ifsc),
              ],
              const Text('Payout details come from the employee profile.',
                  style: TextStyle(fontSize: 12.5, color: GeoUi.muted)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickProof,
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: Text(_proofName ?? 'Attach payment proof (optional)', overflow: TextOverflow.ellipsis),
              ),
              if (_proof != null)
                TextButton(onPressed: () => setState(() { _proof = null; _proofName = null; }), child: const Text('Remove proof')),
            ],
            const SizedBox(height: 20),
            GeoUi.primaryButton('Approve', _submit, busy: _busy),
          ],
        ]),
      ),
    );
  }
}

/// Revise a claim's rate / distance / amount. Returns true once saved.
Future<bool> showTaReviseDialog(
  BuildContext context, {
  required String staffId,
  required String date,
  required double rate,
  required double distance,
  required double amount,
  String? description,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _ReviseDialog(
        staffId: staffId, date: date, rate: rate, distance: distance, amount: amount, description: description),
  );
  return r == true;
}

class _ReviseDialog extends StatefulWidget {
  const _ReviseDialog({required this.staffId, required this.date, required this.rate, required this.distance, required this.amount, this.description});
  final String staffId;
  final String date;
  final double rate;
  final double distance;
  final double amount;
  final String? description;

  @override
  State<_ReviseDialog> createState() => _ReviseDialogState();
}

class _ReviseDialogState extends State<_ReviseDialog> {
  late final _rate = TextEditingController(text: widget.rate.toStringAsFixed(2));
  late final _dist = TextEditingController(text: widget.distance.toStringAsFixed(1));
  late final _amount = TextEditingController(text: widget.amount.toStringAsFixed(2));
  late final _desc = TextEditingController(text: widget.description ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _rate.dispose();
    _dist.dispose();
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _recalc() {
    final r = double.tryParse(_rate.text);
    final d = double.tryParse(_dist.text);
    if (r != null && d != null) _amount.text = (r * d).clamp(0, double.infinity).toStringAsFixed(2);
  }

  Future<void> _save() async {
    final r = double.tryParse(_rate.text);
    final d = double.tryParse(_dist.text);
    final a = double.tryParse(_amount.text);
    if (r == null || r < 0 || d == null || d < 0 || a == null || a < 0) {
      GeoUi.fail(context, 'Rate, distance and amount must be numbers of 0 or more.');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await AdminGeoService.instance.reviseTravelAllowance(
        staffId: widget.staffId,
        date: widget.date,
        ratePerKm: r,
        totalDistanceKm: d,
        revisedAmount: a,
        description: _desc.text.trim(),
      );
      if (!mounted) return;
      GeoUi.ok(context, GeoUi.s(res['message'], 'Claim revised.'));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    const kb = TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      title: const Text('Revise amount'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _dist, keyboardType: kb, decoration: GeoUi.input('Distance (km)'), onChanged: (_) => _recalc()),
          const SizedBox(height: 12),
          TextField(controller: _rate, keyboardType: kb, decoration: GeoUi.input('Rate per km (₹)'), onChanged: (_) => _recalc()),
          const SizedBox(height: 12),
          TextField(controller: _amount, keyboardType: kb, decoration: GeoUi.input('Revised amount (₹)')),
          const SizedBox(height: 12),
          TextField(controller: _desc, maxLines: 3, decoration: GeoUi.input('Reason / description')),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Reject a claim with a reason. Returns true once rejected.
Future<bool> showTaRejectDialog(BuildContext context, {required String staffId, required String date}) async {
  final r = await showDialog<bool>(context: context, builder: (_) => _RejectDialog(staffId: staffId, date: date));
  return r == true;
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.staffId, required this.date});
  final String staffId;
  final String date;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _reject() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      GeoUi.fail(context, 'Enter a reason for rejecting.');
      return;
    }
    setState(() => _busy = true);
    try {
      await AdminGeoService.instance.rejectTravelAllowance(staffId: widget.staffId, date: widget.date, reason: reason);
      if (!mounted) return;
      GeoUi.ok(context, 'Claim rejected.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject claim'),
      content: TextField(controller: _reason, maxLines: 3, decoration: GeoUi.input('Reason')),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _reject,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Reject'),
        ),
      ],
    );
  }
}

/// Claim status helpers shared by the TA screens.
bool taIsPending(String s) => s == 'Pending' || s == 'Generated';
bool taIsApproved(String s) => s == 'Approved' || s == 'Revised-Approved';
