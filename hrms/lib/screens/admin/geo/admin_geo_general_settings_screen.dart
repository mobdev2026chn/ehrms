// Admin GEO general settings: auto task approval, timeline tracking, live tracking, capture
// interval and how long location history is kept (each saved as it is changed), plus every
// employee's auto-approval / timeline / live switches and "turn off for all".
// HRMSbackend /api/admin/hrms-geo/settings/general-settings[/external-employees|/staff/:id/*|/global-*].

import 'package:flutter/material.dart';

import '../../../widgets/app_card.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'geo_admin_ui.dart';

class AdminGeoGeneralSettingsScreen extends StatefulWidget {
  const AdminGeoGeneralSettingsScreen({super.key});

  @override
  State<AdminGeoGeneralSettingsScreen> createState() => _AdminGeoGeneralSettingsScreenState();
}

class _AdminGeoGeneralSettingsScreenState extends State<AdminGeoGeneralSettingsScreen> {
  static const _intervals = [30, 60, 120, 300];

  Map<String, dynamic> _s = {};
  List<Map<String, dynamic>> _staff = [];
  String? _staffError;
  bool _loading = true;
  String? _error;
  String? _busy; // key of the control being saved
  double? _daysDraft;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await AdminGeoService.instance.getGeneralSettings();
      if (!mounted) return;
      setState(() {
        _s = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return;
    }
    await _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final list = await AdminGeoService.instance.getExternalEmployees();
      if (!mounted) return;
      setState(() {
        _staff = list;
        _staffError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _staffError = e.toString());
    }
  }

  bool _b(String k) => _s[k] == true;

  Future<void> _saveGlobal(String key, Future<Map<String, dynamic>> Function() call, {bool reloadStaff = false}) async {
    setState(() => _busy = key);
    try {
      final s = await call();
      if (!mounted) return;
      setState(() {
        _s = {..._s, ...s};
        _busy = null;
      });
      GeoUi.ok(context, 'Settings saved.');
      if (reloadStaff) _loadStaff();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      GeoUi.fail(context, e);
    }
  }

  Future<void> _staffSwitch(Map<String, dynamic> s, String kind, String field, bool v) async {
    final id = GeoUi.s(s['id']);
    setState(() => _busy = '$id|$kind');
    try {
      await AdminGeoService.instance.updateStaffGeoSwitch(id, kind, v);
      if (!mounted) return;
      setState(() {
        s[field] = v;
        _busy = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      GeoUi.fail(context, e);
    }
  }

  Future<void> _disableAll(String kind, String label) async {
    if (!await GeoUi.confirm(context, 'Turn off $label', 'Turn off $label for every employee? It is also switched off company-wide.',
        action: 'Turn off', destructive: true)) {
      return;
    }
    setState(() => _busy = 'all|$kind');
    try {
      final r = await AdminGeoService.instance.disableForAll(kind);
      if (!mounted) return;
      setState(() => _busy = null);
      GeoUi.ok(context, GeoUi.s(r['message'], '$label turned off.'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      GeoUi.fail(context, e);
    }
  }

  String _intervalLabel(int s) => s < 60 ? '$s seconds' : '${s ~/ 60} minute${s ~/ 60 == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('General Settings', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: _loading
          ? GeoUi.loading
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? GeoUi.error(_error!, _load)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _card([
                          _switchRow('Auto task approval', 'Tasks staff create are approved without review (for employees switched on below).',
                              'autoTaskApproval', (v) => _saveGlobal('autoTaskApproval',
                                  () => AdminGeoService.instance.updateGeneralSettings(autoTaskApproval: v), reloadStaff: !v)),
                          const Divider(height: 1, color: GeoUi.line),
                          _switchRow('Timeline tracking', 'Record each field visit (Field In / Field Out) as a timeline for the day.',
                              'timelineTracking', (v) => _saveGlobal('timelineTracking',
                                  () => AdminGeoService.instance.updateGeneralSettings(timelineTracking: v), reloadStaff: !v)),
                          const Divider(height: 1, color: GeoUi.line),
                          _switchRow('Live tracking', 'Continuously record the employee’s location while on the field.',
                              'liveTracking', (v) => _saveGlobal('liveTracking',
                                  () => AdminGeoService.instance.updateGeneralSettings(liveTracking: v), reloadStaff: !v)),
                        ]),
                        const SizedBox(height: 12),
                        _card([
                          _title('Capture interval'),
                          const SizedBox(height: 4),
                          const Text('How often a location is saved while live tracking is on.',
                              style: TextStyle(fontSize: 12.5, color: GeoUi.muted)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _intervals.map((s) {
                              final sel = s == GeoUi.n(_s['liveTrackingInterval']).toInt();
                              return ChoiceChip(
                                selected: sel,
                                onSelected: _busy != null || sel
                                    ? null
                                    : (_) => _saveGlobal('interval', () => AdminGeoService.instance.updateGeneralSettings(liveTrackingInterval: s)),
                                showCheckmark: false,
                                selectedColor: AppColors.primary,
                                backgroundColor: AppColors.surface,
                                side: BorderSide(color: sel ? Colors.transparent : GeoUi.border),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                label: Text(_intervalLabel(s),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? AppColors.onPrimary : GeoUi.ink)),
                              );
                            }).toList(),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        _days(),
                        const SizedBox(height: 20),
                        _employees(),
                      ],
                    ),
            ),
    );
  }

  Widget _days() {
    final saved = GeoUi.n(_s['dataStoreDays']).toDouble().clamp(1, 40).toDouble();
    final v = _daysDraft ?? saved;
    return _card([
      _title('Keep location history for'),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: Slider(
            value: v,
            min: 1,
            max: 40,
            divisions: 39,
            activeColor: AppColors.primary,
            label: '${v.round()} days',
            onChanged: _busy != null ? null : (x) => setState(() => _daysDraft = x),
            onChangeEnd: (x) async {
              await _saveGlobal('days', () => AdminGeoService.instance.updateGeneralSettings(dataStoreDays: x.round()));
              if (mounted) setState(() => _daysDraft = null);
            },
          ),
        ),
        SizedBox(
          width: 64,
          child: Text('${v.round()} days', textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeoUi.ink)),
        ),
      ]),
      const Text('Older location points are deleted automatically (at most 40 days).', style: TextStyle(fontSize: 12.5, color: GeoUi.muted)),
    ]);
  }

  Widget _employees() {
    final q = _query.toLowerCase();
    final list = _staff
        .where((s) => q.isEmpty || GeoUi.s(s['name']).toLowerCase().contains(q) || GeoUi.s(s['employeeId']).toLowerCase().contains(q))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GeoUi.sectionTitle('Employees'),
      const Text('Per-employee switches work only while the matching setting above is on.',
          style: TextStyle(fontSize: 12.5, color: GeoUi.muted)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _allButton('auto-approval', 'auto approval'),
        _allButton('timeline-tracking', 'timeline tracking'),
        _allButton('live-tracking', 'live tracking'),
      ]),
      const SizedBox(height: 12),
      TextField(
        decoration: GeoUi.input('Search employees', suffix: const Icon(Icons.search_rounded, size: 20)),
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
      const SizedBox(height: 12),
      if (_staffError != null)
        Column(children: [
          Text(_staffError!, style: const TextStyle(fontSize: 13, color: GeoUi.muted)),
          OutlinedButton(onPressed: _loadStaff, child: const Text('Retry')),
        ])
      else if (list.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('No employees.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: GeoUi.muted)))
      else
        ...list.map(_employeeCard),
    ]);
  }

  Widget _allButton(String kind, String label) => OutlinedButton.icon(
        onPressed: _busy != null ? null : () => _disableAll(kind, label),
        icon: _busy == 'all|$kind'
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.power_settings_new_rounded, size: 18),
        label: Text('All $label off', style: const TextStyle(fontSize: 13)),
      );

  Widget _employeeCard(Map<String, dynamic> s) {
    final id = GeoUi.s(s['id']);
    Widget sw(String label, String kind, String field, String globalKey) {
      final busy = _busy == '$id|$kind';
      return Expanded(
        child: Column(children: [
          busy
              ? const SizedBox(height: 40, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : Switch(
                  value: s[field] == true,
                  onChanged: _busy != null || (!_b(globalKey) && s[field] != true) ? null : (v) => _staffSwitch(s, kind, field, v),
                ),
          Text(label, style: const TextStyle(fontSize: 12, color: GeoUi.muted)),
        ]),
      );
    }

    return GeoUi.card(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(GeoUi.s(s['name'], 'Employee'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
        const SizedBox(height: 2),
        Text('${GeoUi.s(s['employeeId'])} · ${GeoUi.s(s['department'])}', style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
        const SizedBox(height: 4),
        const Divider(height: 12),
        Row(children: [
          sw('Auto approval', 'auto-approval', 'autoApproval', 'autoTaskApproval'),
          sw('Timeline', 'timeline-tracking', 'timelineTracking', 'timelineTracking'),
          sw('Live', 'live-tracking', 'liveTracking', 'liveTracking'),
        ]),
      ]),
    );
  }

  Widget _card(List<Widget> children) => AppCard(
        border: Border.all(color: GeoUi.line),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _title(String t) => Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink));

  Widget _switchRow(String title, String sub, String key, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          _busy == key
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : Switch(value: _b(key), onChanged: _busy != null ? null : onChanged),
        ]),
      );
}
