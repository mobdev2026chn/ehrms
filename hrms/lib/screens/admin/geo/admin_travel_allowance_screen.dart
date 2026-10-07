// Admin GEO: travel-allowance claims from field employees, with approve (paid via payroll).
// HRMSbackend /api/admin/hrms-geo/travel-allowance.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/admin_geo_service.dart';
import '../../../utils/snackbar_utils.dart';

class AdminTravelAllowanceScreen extends StatefulWidget {
  const AdminTravelAllowanceScreen({super.key});

  @override
  State<AdminTravelAllowanceScreen> createState() => _AdminTravelAllowanceScreenState();
}

class _AdminTravelAllowanceScreenState extends State<AdminTravelAllowanceScreen> {
  static const _accent = Color(0xFFEFAA1F);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _tabs = ['All', 'Pending', 'Approved', 'Rejected'];

  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _tab = 'Pending';
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    final r = await AdminGeoService.instance.getTravelAllowances();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _all = List<Map<String, dynamic>>.from(r['data'] as List);
      } else {
        _error = r['message']?.toString() ?? 'Could not load claims.';
      }
    });
  }

  bool _isPending(String s) => s == 'Pending' || s == 'Generated';
  bool _isApproved(String s) => s == 'Approved' || s == 'Revised-Approved';

  List<Map<String, dynamic>> get _visible {
    return _all.where((c) {
      final s = (c['status'] ?? '').toString();
      switch (_tab) {
        case 'Pending':
          return _isPending(s);
        case 'Approved':
          return _isApproved(s);
        case 'Rejected':
          return s == 'Rejected';
        default:
          return true;
      }
    }).toList();
  }

  num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

  double _amount(Map<String, dynamic> c) {
    final revised = c['revisedAmount'];
    if (revised is num) return revised.toDouble();
    return _n(c['generatedAmount']).toDouble();
  }

  Future<void> _approve(Map<String, dynamic> c) async {
    final staffId = (c['staffId'] is Map ? c['staffId']['_id'] : c['staffId'])?.toString() ?? '';
    final date = (c['date'] ?? '').toString();
    if (staffId.isEmpty || date.isEmpty) return;
    final key = '$staffId|$date';

    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve claim'),
        content: Text('Approve ₹${_amount(c).toStringAsFixed(2)} for ${c['staffName'] ?? 'this employee'}, paid through payroll $month?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyKey = key);
    final r = await AdminGeoService.instance.approveTravelAllowance(staffId: staffId, date: date, payrollMonth: month);
    if (!mounted) return;
    setState(() => _busyKey = null);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Claim approved.');
      _load();
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not approve.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{'All': _all.length};
    for (final c in _all) {
      final s = (c['status'] ?? '').toString();
      final bucket = _isPending(s) ? 'Pending' : _isApproved(s) ? 'Approved' : s == 'Rejected' ? 'Rejected' : null;
      if (bucket != null) counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: const Text('Travel Allowance', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final t = _tabs[i];
                  final sel = t == _tab;
                  final n = counts[t] ?? 0;
                  return ChoiceChip(
                    selected: sel,
                    onSelected: (_) => setState(() => _tab = t),
                    showCheckmark: false,
                    selectedColor: _accent,
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    label: Text(n > 0 ? '$t  $n' : t,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: sel ? Colors.white : _ink)),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: (_error != null && _all.isEmpty)
                        ? _center(Icons.wifi_off_rounded, 'Could not load', _error!)
                        : _visible.isEmpty
                            ? _center(Icons.receipt_long_outlined, 'No claims', 'Nothing in “$_tab”.')
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                                children: _visible.map(_card).toList(),
                              ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final name = (c['staffName'] ?? 'Staff').toString();
    final status = (c['status'] ?? '').toString();
    final dateStr = (c['date'] ?? '').toString();
    DateTime? d = DateTime.tryParse(dateStr);
    final dateLabel = d != null ? DateFormat('d MMM yyyy').format(d) : dateStr;
    final km = _n(c['totalDistanceKm']);
    final staffId = (c['staffId'] is Map ? c['staffId']['_id'] : c['staffId'])?.toString() ?? '';
    final key = '$staffId|$dateStr';
    final (bg, fg) = _isApproved(status)
        ? (const Color(0xFFDCFCE7), const Color(0xFF15803D))
        : status == 'Rejected'
            ? (const Color(0xFFFEE2E2), const Color(0xFFB91C1C))
            : (const Color(0xFFFEF3C7), const Color(0xFF92400E));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(status.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('$dateLabel  ·  ${km.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 12.5, color: _muted)),
        const SizedBox(height: 8),
        Row(children: [
          Text('₹${_amount(c).toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)),
          const Spacer(),
          if (_isPending(status))
            _busyKey == key
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : ElevatedButton.icon(
                    onPressed: () => _approve(c),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
        ]),
      ]),
    );
  }

  Widget _center(IconData icon, String title, String msg) => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(icon, size: 40, color: _muted),
          const SizedBox(height: 10),
          Center(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink))),
          const SizedBox(height: 4),
          Center(child: Text(msg, style: const TextStyle(fontSize: 12.5, color: _muted))),
          const SizedBox(height: 12),
          Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
        ],
      );
}
