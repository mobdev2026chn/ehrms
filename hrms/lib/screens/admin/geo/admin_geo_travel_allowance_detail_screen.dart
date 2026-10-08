// Admin GEO: one travel-allowance claim — figures, payout, proof and the per-task distance
// breakdown — with approve / revise / reject.
// HRMSbackend GET /api/admin/hrms-geo/travel-allowance/:id and
// GET /api/admin/hrms-geo/task/travel-allowance?staffId&date.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'admin_geo_tracking_details_screen.dart';
import 'geo_admin_ui.dart';
import 'geo_ta_actions.dart';

class AdminGeoTravelAllowanceDetailScreen extends StatefulWidget {
  const AdminGeoTravelAllowanceDetailScreen({
    super.key,
    required this.claimId,
    required this.staffId,
    required this.date,
    this.staffName,
  });

  final String claimId;
  final String staffId;

  /// The claim's day, yyyy-MM-dd (IST) as the list returns it.
  final String date;
  final String? staffName;

  @override
  State<AdminGeoTravelAllowanceDetailScreen> createState() => _AdminGeoTravelAllowanceDetailScreenState();
}

class _AdminGeoTravelAllowanceDetailScreenState extends State<AdminGeoTravelAllowanceDetailScreen> {
  Map<String, dynamic>? _claim;
  Map<String, dynamic>? _breakdown;
  String? _breakdownError;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final claim = await AdminGeoService.instance.getTravelAllowance(widget.claimId);
      Map<String, dynamic>? breakdown;
      String? bErr;
      try {
        breakdown = await AdminGeoService.instance.getTaskTravelBreakdown(widget.staffId, widget.date);
      } catch (e) {
        bErr = e.toString();
      }
      if (!mounted) return;
      setState(() {
        _claim = claim;
        _breakdown = breakdown;
        _breakdownError = bErr;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _listOf(dynamic v) =>
      v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Claim details', actions: [
        IconButton(
          tooltip: 'Tracking details',
          onPressed: () {
            final d = DateTime.tryParse(widget.date);
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AdminGeoTrackingDetailsScreen(
                    staffId: widget.staffId, staffName: widget.staffName, startDate: d, endDate: d)));
          },
          icon: const Icon(Icons.map_outlined),
        ),
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: _loading
          ? GeoUi.loading
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null ? GeoUi.error(_error!, _load) : _body(),
            ),
    );
  }

  Widget _body() {
    final c = _claim!;
    final status = GeoUi.s(c['status'], 'Pending');
    final rate = GeoUi.n(c['ratePerKm']).toDouble();
    final dist = GeoUi.n(c['totalDistanceKm']).toDouble();
    final generated = GeoUi.n(c['generatedAmount']).toDouble();
    final revised = c['revisedAmount'] is num ? (c['revisedAmount'] as num).toDouble() : null;
    final payable = revised ?? generated;
    final transport = c['transport'] is Map ? Map<String, dynamic>.from(c['transport'] as Map) : <String, dynamic>{};
    final immediate = c['paymentRoute'] == 'Immediate';
    final canRevise = status != 'Rejected' && !(taIsApproved(status) && immediate);
    final name = GeoUi.s(c['staffName'], widget.staffName ?? 'Employee');

    Future<void> after(bool done) async {
      if (done) await _load();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        GeoUi.card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GeoUi.ink))),
              const SizedBox(width: 8),
              GeoUi.statusPill(status),
            ]),
            const SizedBox(height: 4),
            Text(GeoUi.date(widget.date), style: const TextStyle(fontSize: 13, color: GeoUi.muted)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Payable amount', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.brandDark)),
                const SizedBox(height: 4),
                Text(GeoUi.money(payable), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: GeoUi.ink)),
              ]),
            ),
            const Divider(height: 24, color: GeoUi.line),
            GeoUi.kv('Transport', '${GeoUi.s(transport['name'], '—')} (₹${GeoUi.n(transport['rate'])}/km base)'),
            GeoUi.kv('Distance', '${dist.toStringAsFixed(1)} km'),
            GeoUi.kv('Rate', '₹${rate.toStringAsFixed(2)} / km'),
            GeoUi.kv('Generated', GeoUi.money(generated)),
            if (revised != null) GeoUi.kv('Revised', GeoUi.money(revised)),
            if (GeoUi.s(c['description']).isNotEmpty) GeoUi.kv('Reason', GeoUi.s(c['description'])),
          ]),
        ),
        if (GeoUi.s(c['paymentRoute']).isNotEmpty)
          GeoUi.card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GeoUi.sectionTitle('Payout'),
              GeoUi.kv('Route', GeoUi.s(c['paymentRoute'])),
              if (GeoUi.s(c['payrollMonth']).isNotEmpty) GeoUi.kv('Payroll month', GeoUi.s(c['payrollMonth'])),
              if (GeoUi.s(c['upiId']).isNotEmpty) GeoUi.kv('UPI ID', GeoUi.s(c['upiId'])),
              if (GeoUi.s(c['accountNo']).isNotEmpty) GeoUi.kv('Account no.', GeoUi.s(c['accountNo'])),
              if (GeoUi.s(c['ifscCode']).isNotEmpty) GeoUi.kv('IFSC', GeoUi.s(c['ifscCode'])),
              _proof(GeoUi.s(c['proofImg'])),
            ]),
          ),
        GeoUi.card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GeoUi.sectionTitle('Per-task breakdown'),
            ..._breakdownRows(c),
          ]),
        ),
        const SizedBox(height: 8),
        if (taIsPending(status)) ...[
          GeoUi.primaryButton('Approve', () async {
            after(await showTaApproveSheet(context, staffId: widget.staffId, date: widget.date, amount: payable, staffName: name));
          }),
          const SizedBox(height: 12),
        ],
        Row(children: [
          if (canRevise)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async => after(await showTaReviseDialog(context,
                    staffId: widget.staffId,
                    date: widget.date,
                    rate: rate > 0 ? rate : GeoUi.n(transport['rate']).toDouble(),
                    distance: dist,
                    amount: payable,
                    description: GeoUi.s(c['description']))),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Revise'),
              ),
            ),
          if (canRevise && taIsPending(status)) const SizedBox(width: 12),
          if (taIsPending(status))
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async => after(await showTaRejectDialog(context, staffId: widget.staffId, date: widget.date)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error, width: 1.2)),
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.error),
                label: const Text('Reject', style: TextStyle(color: AppColors.error)),
              ),
            ),
        ]),
      ],
    );
  }

  List<Widget> _breakdownRows(Map<String, dynamic> claim) {
    final live = _listOf(_breakdown?['tasks']);
    if (live.isNotEmpty) {
      return [
        for (final t in live)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(GeoUi.s(t['title'], GeoUi.s(t['taskId'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
            subtitle: Text('${GeoUi.s(t['taskId'])} · ${GeoUi.s(t['taskType'])} · ${GeoUi.dateTime(t['completedDate'])}'),
            trailing: Text('${GeoUi.n(t['distanceKm'])} km', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          ),
        const Divider(color: GeoUi.line),
        Text('Total ${GeoUi.n(_breakdown?['totalDistanceKm'])} km',
            textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
      ];
    }
    // The tasks stored on the claim when it was generated.
    final stored = _listOf(claim['tasks']);
    return [
      if (_breakdownError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_breakdownError!, style: const TextStyle(fontSize: 12.5, color: AppColors.error)),
        ),
      if (stored.isEmpty)
        const Text('No completed tasks recorded for this day.', style: TextStyle(fontSize: 13, color: GeoUi.muted))
      else
        for (final t in stored)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(GeoUi.s(t['taskNumber'], 'Task'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
            trailing: Text('${GeoUi.n(t['distanceKm'])} km', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          ),
    ];
  }

  Widget _proof(String src) {
    if (src.isEmpty) return const SizedBox.shrink();
    Widget img;
    if (src.startsWith('data:image')) {
      try {
        img = Image.memory(base64Decode(src.substring(src.indexOf(',') + 1)), fit: BoxFit.cover);
      } on FormatException {
        return const Text('Proof image could not be read.', style: TextStyle(fontSize: 13, color: GeoUi.muted));
      }
    } else if (src.startsWith('http')) {
      img = Image.network(src, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Text('Proof image could not be loaded.', style: TextStyle(fontSize: 13, color: GeoUi.muted)));
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: img),
    );
  }
}
