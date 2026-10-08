// Admin GEO travel-allowance settings: the transport modes and their rate per km (an
// employee's allowance = distance × the rate of the transport assigned under Employee Access),
// and the global km rate. HRMSbackend GET / PUT /api/admin/hrms-geo/settings/travel-allowance.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_geo_service.dart';
import 'geo_admin_ui.dart';

class AdminGeoTaSettingsScreen extends StatefulWidget {
  const AdminGeoTaSettingsScreen({super.key});

  @override
  State<AdminGeoTaSettingsScreen> createState() => _AdminGeoTaSettingsScreenState();
}

class _Row {
  _Row({this.id, String name = '', String rate = ''})
      : name = TextEditingController(text: name),
        rate = TextEditingController(text: rate);
  final String? id;
  final TextEditingController name;
  final TextEditingController rate;
}

class _AdminGeoTaSettingsScreenState extends State<AdminGeoTaSettingsScreen> {
  final List<_Row> _rows = [];
  final _global = TextEditingController();
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposeRows();
    _global.dispose();
    super.dispose();
  }

  void _disposeRows({bool later = false}) {
    final old = List<_Row>.of(_rows);
    _rows.clear();
    void run() {
      for (final r in old) {
        r.name.dispose();
        r.rate.dispose();
      }
    }

    // Fields still on screen hold these controllers until the next frame.
    later ? WidgetsBinding.instance.addPostFrameCallback((_) => run()) : run();
  }

  void _apply(Map<String, dynamic> s) {
    _disposeRows(later: true);
    if (s['transports'] is List) {
      for (final t in s['transports'] as List) {
        if (t is Map) _rows.add(_Row(id: GeoUi.s(t['_id']), name: GeoUi.s(t['name']), rate: '${GeoUi.n(t['rate'])}'));
      }
    }
    _global.text = s['globalKmRate'] is num ? '${s['globalKmRate']}' : '';
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await AdminGeoService.instance.getTaSettings();
      if (!mounted) return;
      setState(() {
        _apply(s);
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

  Future<void> _save() async {
    final transports = <Map<String, dynamic>>[];
    final names = <String>{};
    for (final r in _rows) {
      final name = r.name.text.trim();
      final rate = num.tryParse(r.rate.text.trim());
      if (name.isEmpty) {
        GeoUi.fail(context, 'Every transport needs a name.');
        return;
      }
      if (rate == null || rate < 0) {
        GeoUi.fail(context, 'Enter a rate of 0 or more for $name.');
        return;
      }
      if (!names.add(name.toLowerCase())) {
        GeoUi.fail(context, '$name is listed twice.');
        return;
      }
      transports.add({if (r.id != null && r.id!.isNotEmpty) '_id': r.id, 'name': name, 'rate': rate});
    }
    final global = _global.text.trim().isEmpty ? null : num.tryParse(_global.text.trim());
    if (_global.text.trim().isNotEmpty && (global == null || global < 0)) {
      GeoUi.fail(context, 'The global km rate must be a number of 0 or more.');
      return;
    }
    setState(() => _saving = true);
    try {
      final s = await AdminGeoService.instance.updateTaSettings(transports: transports, globalKmRate: global);
      if (!mounted) return;
      setState(() {
        _apply(s);
        _saving = false;
      });
      GeoUi.ok(context, 'Transport settings saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      GeoUi.fail(context, e);
    }
  }

  Future<void> _remove(int i) async {
    final r = _rows[i];
    if (r.id != null &&
        !await GeoUi.confirm(context, 'Remove transport',
            'Employees assigned "${r.name.text}" will have no valid transport until reassigned. Remove it? (Saved when you tap Save.)',
            action: 'Remove', destructive: true)) {
      return;
    }
    setState(() => _rows.removeAt(i));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      r.name.dispose();
      r.rate.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('Travel Allowance Settings', actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading || _saving ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: _loading
          ? GeoUi.loading
          : _error != null
              ? GeoUi.error(_error!, _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    GeoUi.card(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        GeoUi.sectionTitle('Transport modes', trailing: TextButton.icon(
                          onPressed: () => setState(() => _rows.add(_Row(rate: '0'))),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                        )),
                        const Text('The allowance is the distance travelled × the rate of the employee’s transport.',
                            style: TextStyle(fontSize: 12.5, color: GeoUi.muted)),
                        const SizedBox(height: 16),
                        if (_rows.isEmpty)
                          const Padding(padding: EdgeInsets.all(12), child: Text('No transport modes.', style: TextStyle(fontSize: 13, color: GeoUi.muted))),
                        for (var i = 0; i < _rows.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(children: [
                              Expanded(flex: 3, child: TextField(controller: _rows[i].name, decoration: GeoUi.input('Name'))),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _rows[i].rate,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: GeoUi.input('₹ / km'),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _remove(i),
                                icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                    GeoUi.card(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        GeoUi.sectionTitle('Global km rate'),
                        TextField(
                          controller: _global,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: GeoUi.input('₹ per km (optional)'),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    GeoUi.primaryButton('Save', _save, busy: _saving),
                  ],
                ),
    );
  }
}
