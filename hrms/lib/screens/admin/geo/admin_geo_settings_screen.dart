// Admin GEO settings: live tracking on/off, timeline tracking, capture interval and how long
// location history is kept. HRMSbackend /api/admin/hrms-geo/settings/general-settings.

import 'package:flutter/material.dart';

import '../../../services/admin_geo_service.dart';
import '../../../utils/snackbar_utils.dart';

class AdminGeoSettingsScreen extends StatefulWidget {
  const AdminGeoSettingsScreen({super.key});

  @override
  State<AdminGeoSettingsScreen> createState() => _AdminGeoSettingsScreenState();
}

class _AdminGeoSettingsScreenState extends State<AdminGeoSettingsScreen> {
  static const _accent = Color(0xFFEFAA1F);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _intervals = [30, 60, 120, 300];

  bool _liveTracking = false;
  bool _timelineTracking = false;
  int _interval = 30;
  int _dataStoreDays = 30;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    final r = await AdminGeoService.instance.getGeneralSettings();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        final d = Map<String, dynamic>.from(r['data'] as Map);
        _liveTracking = d['liveTracking'] == true;
        _timelineTracking = d['timelineTracking'] == true;
        final iv = (d['liveTrackingInterval'] as num?)?.toInt() ?? 30;
        _interval = _intervals.contains(iv) ? iv : 30;
        _dataStoreDays = (d['dataStoreDays'] as num?)?.toInt() ?? 30;
      } else {
        _error = r['message']?.toString() ?? 'Could not load settings.';
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await AdminGeoService.instance.updateGeneralSettings(
      liveTracking: _liveTracking,
      timelineTracking: _timelineTracking,
      liveTrackingInterval: _interval,
      dataStoreDays: _dataStoreDays,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'GEO settings saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save.', isError: true);
    }
  }

  String _intervalLabel(int s) => s < 60 ? '$s seconds' : '${s ~/ 60} minute${s ~/ 60 == 1 ? '' : 's'}';

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
        title: const Text('GEO Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off_rounded, size: 40, color: _muted),
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: _muted)),
                    const SizedBox(height: 10),
                    OutlinedButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
                  children: [
                    _card([
                      _switchRow(
                        'Timeline tracking',
                        'Record each field visit (Field In / Field Out) as a timeline for the day.',
                        _timelineTracking,
                        (v) => setState(() => _timelineTracking = v),
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _switchRow(
                        'Live tracking',
                        'Continuously record the employee’s location while on the field.',
                        _liveTracking,
                        (v) => setState(() => _liveTracking = v),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _card([
                      _title('Capture interval'),
                      const SizedBox(height: 4),
                      const Text('How often a location is recorded while live tracking is on.',
                          style: TextStyle(fontSize: 12, color: _muted)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: _intervals.map((s) {
                          final sel = s == _interval;
                          return ChoiceChip(
                            selected: sel,
                            onSelected: _liveTracking ? (_) => setState(() => _interval = s) : null,
                            showCheckmark: false,
                            selectedColor: _accent,
                            backgroundColor: const Color(0xFFF1F5F9),
                            side: BorderSide.none,
                            label: Text(_intervalLabel(s),
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: sel ? Colors.white : _ink)),
                          );
                        }).toList(),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _card([
                      _title('Keep location history for'),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: Slider(
                            value: _dataStoreDays.toDouble().clamp(1, 180),
                            min: 1,
                            max: 180,
                            divisions: 179,
                            activeColor: _accent,
                            label: '$_dataStoreDays days',
                            onChanged: (v) => setState(() => _dataStoreDays = v.round()),
                          ),
                        ),
                        SizedBox(width: 64, child: Text('$_dataStoreDays days', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink))),
                      ]),
                      const Text('Older location points are deleted automatically.',
                          style: TextStyle(fontSize: 12, color: _muted)),
                    ]),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save settings', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _title(String t) => Text(t, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink));

  Widget _switchRow(String title, String sub, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 11.5, color: _muted)),
            ]),
          ),
          Switch(value: value, activeThumbColor: _accent, onChanged: onChanged),
        ]),
      );
}
