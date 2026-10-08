// Admin GEO employee access: for each employee, the field type (internal / external / none),
// the transport their travel allowance is paid at and, for internal field employees, the
// branches they visit. HRMSbackend /api/admin/hrms-geo/settings/employee-access[/:id], with
// /settings/travel-allowance (transports) and /admin/settings/attendance/branches.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'geo_admin_ui.dart';

class AdminGeoEmployeeAccessScreen extends StatefulWidget {
  const AdminGeoEmployeeAccessScreen({super.key});

  @override
  State<AdminGeoEmployeeAccessScreen> createState() => _AdminGeoEmployeeAccessScreenState();
}

class _AdminGeoEmployeeAccessScreenState extends State<AdminGeoEmployeeAccessScreen> {
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic> _ta = {};
  bool _loading = true;
  String? _error;
  String _query = '';
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final svc = AdminGeoService.instance;
      final r = await Future.wait<Object>([svc.getEmployeeAccess(), svc.getBranches(), svc.getTaSettings()]);
      if (!mounted) return;
      setState(() {
        _staff = r[0] as List<Map<String, dynamic>>;
        _branches = r[1] as List<Map<String, dynamic>>;
        _ta = r[2] as Map<String, dynamic>;
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

  List<Map<String, dynamic>> get _transports =>
      _ta['transports'] is List ? [for (final t in _ta['transports'] as List) if (t is Map) Map<String, dynamic>.from(t)] : [];

  String _transportName(Map<String, dynamic> s) {
    final t = s['transport'];
    if (t is! Map) return 'No transport';
    for (final x in _transports) {
      if (GeoUi.s(x['_id']) == GeoUi.s(t['transportId'])) return '${GeoUi.s(x['name'])} · ₹${GeoUi.n(x['rate'])}/km';
    }
    return 'Transport not found';
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.toLowerCase();
    return _staff.where((s) {
      final type = GeoUi.s(s['type'], 'None');
      if (_filter != 'All' && type != _filter) return false;
      return q.isEmpty || GeoUi.s(s['name']).toLowerCase().contains(q) || GeoUi.s(s['employeeId']).toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccessSheet(
        staff: s,
        branches: _branches,
        transports: _transports,
        taSettingsId: GeoUi.s(_ta['_id']),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      final i = _staff.indexWhere((x) => GeoUi.s(x['id']) == GeoUi.s(s['id']));
      if (i >= 0) _staff[i] = {..._staff[i], ...updated};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Employee Access', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            TextField(
              decoration: GeoUi.input('Search employees', suffix: const Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 10),
            GeoUi.choiceChips<String>(
              values: const ['All', 'Internal', 'External', 'None'],
              selected: _filter,
              label: (f) => f == 'None' ? 'No field access' : f,
              onSelected: (f) => setState(() => _filter = f),
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
                          ? GeoUi.message(Icons.manage_accounts_outlined, 'No employees', 'Nothing matches the filters.')
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                              children: _visible.map(_card).toList(),
                            ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> s) {
    final type = GeoUi.s(s['type']);
    final branches = s['HRMSbranches'] is List ? (s['HRMSbranches'] as List).length : 0;
    return GeoUi.card(
      onTap: () => _edit(s),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.brandLight,
          child: Text(GeoUi.s(s['name'], 'Employee')[0].toUpperCase(),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.brandDark)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(GeoUi.s(s['name'], 'Employee'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink))),
              const SizedBox(width: 8),
              type.isEmpty
                  ? GeoUi.pill('NO ACCESS', AppColors.inputFill, AppColors.textSecondary)
                  : GeoUi.pill(type.toUpperCase(), AppColors.warningBg, AppColors.warning),
            ]),
            const SizedBox(height: 2),
            Text('${GeoUi.s(s['employeeId'])} · ${GeoUi.s(s['department'])}', style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
            const SizedBox(height: 4),
            Text(
              [_transportName(s), if (type == 'Internal') '$branches branch${branches == 1 ? '' : 'es'}'].join('  ·  '),
              style: const TextStyle(fontSize: 12.5, color: GeoUi.ink),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
      ]),
    );
  }
}

class _AccessSheet extends StatefulWidget {
  const _AccessSheet({required this.staff, required this.branches, required this.transports, required this.taSettingsId});
  final Map<String, dynamic> staff;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> transports;
  final String taSettingsId;

  @override
  State<_AccessSheet> createState() => _AccessSheetState();
}

class _AccessSheetState extends State<_AccessSheet> {
  late String _type = GeoUi.s(widget.staff['type'], 'None');
  late String? _transportId = widget.staff['transport'] is Map ? GeoUi.s((widget.staff['transport'] as Map)['transportId']) : null;
  late final Set<String> _branches = {
    if (widget.staff['HRMSbranches'] is List) for (final b in widget.staff['HRMSbranches'] as List) b.toString(),
  };
  bool _busy = false;

  Future<void> _save() async {
    if (_transportId != null && widget.taSettingsId.isEmpty) {
      GeoUi.fail(context, 'Travel allowance settings are not available.');
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await AdminGeoService.instance.updateEmployeeAccess(GeoUi.s(widget.staff['id']), {
        'type': _type == 'None' ? null : _type,
        'transport': _transportId == null ? null : {'travelAllowanceSettingsId': widget.taSettingsId, 'transportId': _transportId},
        'HRMSbranches': _type == 'Internal' ? _branches.toList() : <String>[],
      });
      if (!mounted) return;
      GeoUi.ok(context, 'Employee access updated.');
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GeoUi.fail(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final validTransport = widget.transports.any((t) => GeoUi.s(t['_id']) == _transportId) ? _transportId : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(GeoUi.s(widget.staff['name'], 'Employee'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GeoUi.ink)),
            Text(GeoUi.s(widget.staff['employeeId']), style: const TextStyle(fontSize: 13, color: GeoUi.muted)),
            const SizedBox(height: 20),
            const Text('Field access type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'None', label: Text('None')),
                ButtonSegment(value: 'Internal', label: Text('Internal')),
                ButtonSegment(value: 'External', label: Text('External')),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String?>(
              initialValue: validTransport,
              isExpanded: true,
              decoration: GeoUi.input('Transport'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('No transport')),
                for (final t in widget.transports)
                  DropdownMenuItem<String?>(value: GeoUi.s(t['_id']), child: Text('${GeoUi.s(t['name'])} · ₹${GeoUi.n(t['rate'])}/km')),
              ],
              onChanged: (v) => setState(() => _transportId = v),
            ),
            if (_type == 'Internal') ...[
              const SizedBox(height: 20),
              Text('Branches (${_branches.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
              const Text('A daily visit is generated for each branch.', style: TextStyle(fontSize: 12.5, color: GeoUi.muted)),
              if (widget.branches.isEmpty)
                const Padding(padding: EdgeInsets.all(10), child: Text('No branches are set up.', style: TextStyle(fontSize: 13, color: GeoUi.muted)))
              else
                for (final b in widget.branches)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primary,
                    value: _branches.contains(GeoUi.s(b['_id'])),
                    title: Text(GeoUi.s(b['branchName'], 'Branch'), style: const TextStyle(fontSize: 14, color: GeoUi.ink)),
                    onChanged: (v) => setState(() => v == true ? _branches.add(GeoUi.s(b['_id'])) : _branches.remove(GeoUi.s(b['_id']))),
                  ),
            ],
            const SizedBox(height: 20),
            GeoUi.primaryButton('Save', _save, busy: _busy),
          ]),
        ),
      ),
    );
  }
}
