// Admin GEO: travel-allowance claims from field employees, filtered by status / day / name, with
// approve (payroll month, or UPI / bank with proof), revise and reject, and a details screen.
// HRMSbackend /api/admin/hrms-geo/travel-allowance.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'admin_geo_travel_allowance_detail_screen.dart';
import 'geo_admin_ui.dart';
import 'geo_ta_actions.dart';

class AdminTravelAllowanceScreen extends StatefulWidget {
  const AdminTravelAllowanceScreen({super.key});

  @override
  State<AdminTravelAllowanceScreen> createState() => _AdminTravelAllowanceScreenState();
}

class _AdminTravelAllowanceScreenState extends State<AdminTravelAllowanceScreen> {
  static const _tabs = ['All', 'Pending', 'Approved', 'Rejected'];

  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _tab = 'Pending';
  DateTime? _day;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await AdminGeoService.instance
          .getTravelAllowances(date: _day != null ? AdminGeoService.dayKey(_day!) : null);
      if (!mounted) return;
      setState(() {
        _all = list;
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

  String _bucket(String s) => taIsPending(s) ? 'Pending' : taIsApproved(s) ? 'Approved' : s == 'Rejected' ? 'Rejected' : '';

  List<Map<String, dynamic>> get _visible {
    final q = _query.toLowerCase();
    return _all.where((c) {
      if (_tab != 'All' && _bucket(GeoUi.s(c['status'])) != _tab) return false;
      return q.isEmpty || GeoUi.s(c['staffName']).toLowerCase().contains(q);
    }).toList();
  }

  String _staffId(Map<String, dynamic> c) => GeoUi.s(c['staffId'] is Map ? (c['staffId'] as Map)['_id'] : c['staffId']);

  double _amount(Map<String, dynamic> c) {
    final revised = c['revisedAmount'];
    if (revised is num) return revised.toDouble();
    return GeoUi.n(c['generatedAmount']).toDouble();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _day ?? now, firstDate: DateTime(now.year - 2), lastDate: now);
    if (d == null) return;
    setState(() {
      _day = d;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{'All': _all.length};
    for (final c in _all) {
      final b = _bucket(GeoUi.s(c['status']));
      if (b.isNotEmpty) counts[b] = (counts[b] ?? 0) + 1;
    }
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Travel Allowance', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: GeoUi.input('Search employee', suffix: const Icon(Icons.search_rounded, size: 20)),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              _day == null
                  ? IconButton.outlined(onPressed: _pickDay, icon: const Icon(Icons.event_rounded), tooltip: 'Filter by day')
                  : InputChip(
                      label: Text(DateFormat('d MMM').format(_day!)),
                      onPressed: _pickDay,
                      onDeleted: () {
                        setState(() {
                          _day = null;
                          _loading = true;
                        });
                        _load();
                      },
                    ),
            ]),
            const SizedBox(height: 10),
            GeoUi.choiceChips<String>(
              values: _tabs,
              selected: _tab,
              label: (t) => (counts[t] ?? 0) > 0 ? '$t  ${counts[t]}' : t,
              onSelected: (t) => setState(() => _tab = t),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? GeoUi.loading
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _error != null
                      ? GeoUi.error(_error!, _load)
                      : _visible.isEmpty
                          ? GeoUi.message(Icons.receipt_long_outlined, 'No claims', 'Nothing in “$_tab”.')
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                              children: _visible.map(_card).toList(),
                            ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final name = GeoUi.s(c['staffName'], 'Staff');
    final status = GeoUi.s(c['status']);
    final date = GeoUi.s(c['date']);
    final staffId = _staffId(c);
    final transport = c['transport'] is Map ? GeoUi.s((c['transport'] as Map)['name']) : '';

    return GeoUi.card(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => AdminGeoTravelAllowanceDetailScreen(
                  claimId: GeoUi.s(c['_id']), staffId: staffId, date: date, staffName: name)))
          .then((_) => _load()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
          ),
          const SizedBox(width: 8),
          GeoUi.statusPill(status),
        ]),
        const SizedBox(height: 6),
        Text(
          [GeoUi.date(date), '${GeoUi.n(c['totalDistanceKm']).toStringAsFixed(1)} km', if (transport.isNotEmpty) transport].join('  ·  '),
          style: const TextStyle(fontSize: 12.5, color: GeoUi.muted),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text(GeoUi.money(_amount(c)), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GeoUi.ink)),
          if (c['revisedAmount'] is num) ...[
            const SizedBox(width: 6),
            const Text('revised', style: TextStyle(fontSize: 12, color: GeoUi.muted)),
          ],
          const Spacer(),
          if (taIsPending(status) && staffId.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () async {
                final ok = await showTaApproveSheet(context, staffId: staffId, date: date, amount: _amount(c), staffName: name);
                if (ok) _load();
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Approve'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
        ]),
      ]),
    );
  }
}
