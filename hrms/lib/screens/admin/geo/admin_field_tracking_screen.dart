// Admin GEO: field employees out today, their live status and task, and a tap-through to
// each person's day route. Data from HRMSbackend /api/admin/hrms-geo/tracking/* and
// /api/admin/hrms-geo/day-route/:staffId (admins only).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/admin_geo_service.dart';
import '../../geo/my_day_route_screen.dart';

class AdminFieldTrackingScreen extends StatefulWidget {
  const AdminFieldTrackingScreen({super.key});

  @override
  State<AdminFieldTrackingScreen> createState() => _AdminFieldTrackingScreenState();
}

class _AdminFieldTrackingScreenState extends State<AdminFieldTrackingScreen> {
  static const _accent = Color(0xFFEFAA1F);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);

  Map<String, dynamic> _dash = {};
  List<Map<String, dynamic>> _live = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    final results = await Future.wait([
      AdminGeoService.instance.getDashboard(),
      AdminGeoService.instance.getLive(),
    ]);
    if (!mounted) return;
    final dash = results[0];
    final live = results[1];
    setState(() {
      _loading = false;
      if (dash['success'] == true) _dash = Map<String, dynamic>.from(dash['data'] as Map);
      _live = List<Map<String, dynamic>>.from(live['data'] as List);
      if (dash['success'] != true && live['success'] != true) {
        _error = (dash['message'] ?? live['message'])?.toString() ?? 'Could not load field tracking.';
      }
    });
  }

  num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: const Text('Field Tracking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                children: [
                  _summary(),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Text('Out now', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _ink)),
                    const SizedBox(width: 6),
                    Text('${_live.length}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _muted)),
                  ]),
                  const SizedBox(height: 8),
                  if (_error != null && _live.isEmpty)
                    _emptyBox(Icons.wifi_off_rounded, 'Could not load', _error!)
                  else if (_live.isEmpty)
                    _emptyBox(Icons.location_off_outlined, 'No field staff out', 'Nobody is punched in on the field right now.')
                  else
                    ..._live.map(_liveCard),
                ],
              ),
            ),
    );
  }

  Widget _summary() {
    final ts = _dash['taskStatus'] is Map ? Map<String, dynamic>.from(_dash['taskStatus'] as Map) : {};
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0B1220)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.public_rounded, size: 18, color: _accent),
            ),
            const SizedBox(width: 10),
            const Text('Field overview', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            Text('Today', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _tile('Field staff', '${_n(_dash['totalFieldEmployees'])}', Icons.groups_outlined),
            _vline(),
            _tile('Tasks', '${_n(_dash['totalTasksToday'])}', Icons.assignment_outlined),
            _vline(),
            _tile('Distance', '${_n(_dash['totalDistanceKm'])}', Icons.route_outlined, unit: 'km'),
            _vline(),
            _tile('Claims', '${_n(_dash['pendingClaims'])}', Icons.currency_rupee_rounded),
          ]),
          if (ts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Assigned', ts['assigned'], const Color(0xFF60A5FA)),
              _chip('In progress', ts['inProgress'], _accent),
              _chip('Hold', ts['hold'], const Color(0xFF94A3B8)),
              _chip('Completed', ts['completed'], const Color(0xFF34D399)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _vline() => Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.08));

  Widget _tile(String label, String value, IconData icon, {String? unit}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(icon, size: 16, color: _accent),
          const SizedBox(height: 7),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              text: value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, height: 1),
              children: unit != null
                  ? [TextSpan(text: ' $unit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.6)))]
                  : null,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.6))),
        ]),
      );

  Widget _chip(String label, dynamic value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label ${_n(value).toInt()}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _liveCard(Map<String, dynamic> d) {
    final name = (d['staffName'] ?? 'Staff').toString();
    final empId = (d['employeeId'] ?? '').toString();
    final source = (d['source'] ?? '').toString(); // live | punch_in
    final status = (d['status'] ?? d['movementType'] ?? '').toString();
    final taskTitle = (d['taskTitle'] ?? '').toString();
    final taskStatus = (d['taskStatus'] ?? '').toString();
    final tsRaw = d['timestamp'];
    String lastSeen = '';
    final t = tsRaw != null ? DateTime.tryParse(tsRaw.toString())?.toLocal() : null;
    if (t != null) lastSeen = DateFormat('d MMM, h:mm a').format(t);
    final isLive = source == 'live';
    final staffId = (d['staffId'] ?? '').toString();

    return GestureDetector(
      onTap: staffId.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MyDayRouteScreen(staffId: staffId, staffName: name),
              )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w900, color: _accent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLive ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(isLive ? 'LIVE' : 'PUNCHED IN',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: isLive ? const Color(0xFF15803D) : const Color(0xFF92400E))),
                ),
              ]),
              if (empId.isNotEmpty || status.isNotEmpty)
                Text([if (empId.isNotEmpty) empId, if (status.isNotEmpty) status].join('  ·  '),
                    style: const TextStyle(fontSize: 11.5, color: _muted)),
              if (taskTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('Task: $taskTitle${taskStatus.isNotEmpty ? ' ($taskStatus)' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _ink)),
                ),
              if (lastSeen.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('Last seen $lastSeen', style: const TextStyle(fontSize: 11, color: _muted)),
                ),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: _muted),
        ]),
      ),
    );
  }

  Widget _emptyBox(IconData icon, String title, String msg) => Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        alignment: Alignment.center,
        child: Column(children: [
          Icon(icon, size: 40, color: _muted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 4),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: _muted)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
}
