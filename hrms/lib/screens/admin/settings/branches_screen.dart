// Branches (/admin/settings/attendance/branches) with geofence editing
// (GET/PUT /branches/:id/geofence). Mirrors the web branch templates pages:
// a default radius plus one or more zones (lat/lng, optional label/radius).

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'settings_common.dart';

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _svc.listBranches();
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = settingsErrorText(e));
        if (_items != null) showSettingsError(context, e);
      }
    }
  }

  Future<void> _open([Map<String, dynamic>? b]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BranchFormScreen(branchId: b == null ? null : AdminSettingsService.idOf(b)),
    ));
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> b) async {
    final ok = await confirmSettingsAction(context,
        title: 'Delete branch?', message: 'Delete "${b['branchName']}"? This cannot be undone.');
    if (!ok || !mounted) return;
    try {
      await _svc.deleteBranch(AdminSettingsService.idOf(b));
      if (!mounted) return;
      showSettingsSuccess(context, 'Branch deleted');
      setState(() => _items = _items?.where((e) => AdminSettingsService.idOf(e) != AdminSettingsService.idOf(b)).toList());
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar('Branches & Geofence'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _open(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: settingsAsyncBody<Map<String, dynamic>>(
        items: _items,
        error: _error,
        onRefresh: _load,
        emptyText: 'No branches yet. Tap Add to create one.',
        builder: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final b = items[i];
            final g = AdminSettingsService.asMap(b['geofence']);
            final zones = (g['locations'] as List?)?.length ?? 0;
            final enabled = g['enabled'] == true;
            final street = AdminSettingsService.asMap(b['address'])['street']?.toString() ?? '';
            return SettingsListCard(
              leading: settingsIconTile(Icons.store_mall_directory_outlined, size: 40),
              title: (b['branchName'] ?? '-').toString(),
              subtitle: [b['branchCode'], street].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
              onTap: () => _open(b),
              trailing: PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (v) => v == 'edit' ? _open(b) : _delete(b),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit / Geofence')),
                  if (b['isSystemGenerated'] != true)
                    const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                ],
              ),
              footer: Wrap(spacing: 8, runSpacing: 6, children: [
                if (b['isHeadOffice'] == true)
                  const SettingsChip('Head office', color: AppColors.brandDark, background: AppColors.brandLight),
                enabled
                    ? SettingsChip('Geofence on · $zones zone${zones == 1 ? '' : 's'}',
                        color: AppColors.success, background: AppColors.successBg)
                    : const SettingsChip('Geofence off'),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _Zone {
  _Zone({double? lat, double? lng, String label = '', String radius = ''})
      : lat = TextEditingController(text: lat?.toString() ?? ''),
        lng = TextEditingController(text: lng?.toString() ?? ''),
        label = TextEditingController(text: label),
        radius = TextEditingController(text: radius);
  final TextEditingController lat;
  final TextEditingController lng;
  final TextEditingController label;
  final TextEditingController radius;

  LatLng? get point {
    final a = double.tryParse(lat.text.trim()), b = double.tryParse(lng.text.trim());
    if (a == null || b == null) return null;
    return LatLng(a, b);
  }

  void dispose() {
    lat.dispose();
    lng.dispose();
    label.dispose();
    radius.dispose();
  }
}

class BranchFormScreen extends StatefulWidget {
  const BranchFormScreen({super.key, this.branchId});
  final String? branchId;

  @override
  State<BranchFormScreen> createState() => _BranchFormScreenState();
}

class _BranchFormScreenState extends State<BranchFormScreen> {
  final _svc = AdminSettingsService.instance;
  bool get _isEdit => widget.branchId != null;

  bool _loading = true;
  String? _error;
  bool _saving = false;

  final _name = TextEditingController();
  final _code = TextEditingController();
  final _address = TextEditingController();
  bool _headOffice = false;
  Map<String, dynamic> _addressMap = {};

  bool _geofence = true;
  final _defaultRadius = TextEditingController(text: '10');
  final List<_Zone> _zones = [];
  int _active = 0;
  GoogleMapController? _map;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    _defaultRadius.dispose();
    for (final z in _zones) {
      z.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        final b = await _svc.getBranchGeofence(widget.branchId!);
        _name.text = (b['branchName'] ?? '').toString();
        _code.text = (b['branchCode'] ?? '').toString();
        _addressMap = AdminSettingsService.asMap(b['address']);
        _address.text = (_addressMap['street'] ?? '').toString();
        _headOffice = b['isHeadOffice'] == true;
        final g = AdminSettingsService.asMap(b['geofence']);
        _geofence = g['enabled'] == true;
        _defaultRadius.text = (g['radius'] ?? 10).toString();
        for (final z in _zones) {
          z.dispose();
        }
        _zones.clear();
        final locs = AdminSettingsService.asList(g['locations']);
        if (locs.isNotEmpty) {
          for (final l in locs) {
            _zones.add(_Zone(
              lat: toNum(l['latitude'])?.toDouble(),
              lng: toNum(l['longitude'])?.toDouble(),
              label: (l['label'] ?? '').toString(),
              radius: (toNum(l['radius']) ?? 0) > 0 ? l['radius'].toString() : '',
            ));
          }
        } else if (g['latitude'] != null && g['longitude'] != null) {
          _zones.add(_Zone(lat: toNum(g['latitude'])?.toDouble(), lng: toNum(g['longitude'])?.toDouble()));
        }
      }
      if (_zones.isEmpty) _zones.add(_Zone());
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = settingsErrorText(e);
        });
      }
    }
  }

  void _setZonePoint(LatLng p) {
    if (_zones.isEmpty) _zones.add(_Zone());
    final z = _zones[_active.clamp(0, _zones.length - 1)];
    setState(() {
      z.lat.text = p.latitude.toStringAsFixed(6);
      z.lng.text = p.longitude.toStringAsFixed(6);
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) showSettingsError(context, 'Location permission is required to use the current location.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final p = LatLng(pos.latitude, pos.longitude);
      _setZonePoint(p);
      _map?.animateCamera(CameraUpdate.newLatLngZoom(p, 17));
    } catch (e) {
      if (mounted) showSettingsError(context, 'Could not get the current location. ${settingsErrorText(e)}');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Branch Name is required';
    if (_code.text.trim().isEmpty) return 'Branch Code is required';
    if (!_geofence) return null;
    final def = double.tryParse(_defaultRadius.text.trim());
    final complete = _zones.where((z) => z.point != null).toList();
    if (complete.isEmpty) return 'Add at least one zone with latitude and longitude.';
    for (var i = 0; i < _zones.length; i++) {
      final z = _zones[i];
      final hasAny = z.lat.text.trim().isNotEmpty || z.lng.text.trim().isNotEmpty;
      if (hasAny && z.point == null) return 'Zone ${i + 1}: enter a valid latitude and longitude.';
      final p = z.point;
      if (p != null && (p.latitude.abs() > 90 || p.longitude.abs() > 180)) return 'Zone ${i + 1}: coordinates are out of range.';
      if (z.radius.text.trim().isNotEmpty && (double.tryParse(z.radius.text.trim()) ?? 0) <= 0) {
        return 'Zone ${i + 1}: radius must be greater than 0 when set';
      }
    }
    final needsDefault = complete.any((z) => z.radius.text.trim().isEmpty);
    if (needsDefault && (def == null || def <= 0)) return 'Default radius must be a number greater than 0';
    return null;
  }

  List<Map<String, dynamic>> _locations() => [
        for (final z in _zones.where((z) => z.point != null))
          {
            'latitude': z.point!.latitude,
            'longitude': z.point!.longitude,
            if (z.label.text.trim().isNotEmpty)
              'label': z.label.text.trim().length > 120 ? z.label.text.trim().substring(0, 120) : z.label.text.trim(),
            if ((double.tryParse(z.radius.text.trim()) ?? 0) > 0) 'radius': double.parse(z.radius.text.trim()),
          },
      ];

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      showSettingsError(context, err);
      return;
    }
    setState(() => _saving = true);
    final address = {..._addressMap, 'street': _address.text.trim()};
    final locs = _geofence ? _locations() : <Map<String, dynamic>>[];
    final defR = double.tryParse(_defaultRadius.text.trim());
    try {
      if (_isEdit) {
        await _svc.updateBranch(widget.branchId!, {
          'branchName': _name.text.trim(),
          'branchCode': _code.text.trim(),
          'isHeadOffice': _headOffice,
          'address': address,
        });
        if (_geofence) {
          await _svc.updateBranchGeofence(
            widget.branchId!,
            enabled: true,
            radius: defR,
            locations: locs,
            latitude: locs.first['latitude'] as double,
            longitude: locs.first['longitude'] as double,
          );
        } else {
          await _svc.updateBranchGeofence(widget.branchId!, enabled: false);
        }
      } else {
        await _svc.createBranch({
          'branchName': _name.text.trim(),
          'branchCode': _code.text.trim(),
          'isHeadOffice': _headOffice,
          'address': address,
          'geofence': _geofence
              ? {
                  'enabled': true,
                  'radius': ?defR,
                  'locations': locs,
                  'latitude': locs.first['latitude'],
                  'longitude': locs.first['longitude'],
                }
              : {'enabled': false, 'locations': <Map<String, dynamic>>[]},
          'geofenceStatus': _geofence ? 'enable' : 'disable',
        });
      }
      if (!mounted) return;
      showSettingsSuccess(context, _isEdit ? 'Branch and geofence updated' : 'Branch created');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _mapView() {
    final points = <int, LatLng>{
      for (var i = 0; i < _zones.length; i++)
        if (_zones[i].point != null) i: _zones[i].point!,
    };
    final def = double.tryParse(_defaultRadius.text.trim()) ?? 10;
    final center = points[_active] ?? (points.isNotEmpty ? points.values.first : const LatLng(20.5937, 78.9629));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 260,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: points.isEmpty ? 4 : 16),
          onMapCreated: (c) => _map = c,
          onTap: _setZonePoint,
          myLocationButtonEnabled: false,
          gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
          markers: {
            for (final e in points.entries)
              Marker(
                markerId: MarkerId('z${e.key}'),
                position: e.value,
                infoWindow: InfoWindow(title: _zones[e.key].label.text.isEmpty ? 'Zone ${e.key + 1}' : _zones[e.key].label.text),
                icon: BitmapDescriptor.defaultMarkerWithHue(e.key == _active ? BitmapDescriptor.hueRed : BitmapDescriptor.hueAzure),
                onTap: () => setState(() => _active = e.key),
              ),
          },
          circles: {
            for (final e in points.entries)
              Circle(
                circleId: CircleId('c${e.key}'),
                center: e.value,
                radius: double.tryParse(_zones[e.key].radius.text.trim()) ?? def,
                strokeWidth: 2,
                strokeColor: e.key == _active ? AppColors.error : AppColors.info,
                fillColor: (e.key == _active ? AppColors.error : AppColors.info).withValues(alpha: 0.12),
              ),
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar(_isEdit ? 'Edit Branch' : 'Add Branch'),
      body: _loading
          ? const SettingsLoading()
          : _error != null
              ? SettingsErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    const SettingsSectionTitle('Branch details'),
                    SettingsFormCard(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), children: [
                      TextField(controller: _name, decoration: settingsInput('Branch name *')),
                      const SizedBox(height: 12),
                      TextField(controller: _code, decoration: settingsInput('Branch code *')),
                      const SizedBox(height: 12),
                      TextField(controller: _address, maxLines: 2, decoration: settingsInput('Full address')),
                      SettingsSwitchTile(
                        title: 'Head office',
                        value: _headOffice,
                        onChanged: (v) => setState(() => _headOffice = v),
                      ),
                    ]),
                    const SettingsSectionTitle('Geofence'),
                    SettingsFormCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), children: [
                      SettingsSwitchTile(
                        title: 'Enable geofence',
                        subtitle: 'Staff on geofenced attendance must be inside a zone to punch',
                        value: _geofence,
                        onChanged: (v) => setState(() => _geofence = v),
                      ),
                    ]),
                    if (_geofence) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _defaultRadius,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: settingsInput('Default radius', suffix: 'm'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4, left: 4, bottom: 12),
                        child: Text('Used for zones that do not set their own radius',
                            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ),
                      _mapView(),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Expanded(
                          child: Text('Tap the map to place the active (red) zone. Tap a blue pin to switch zones.',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        ),
                        TextButton.icon(
                          onPressed: _locating ? null : _useCurrentLocation,
                          icon: _locating
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location_rounded, size: 18),
                          label: const Text('Current'),
                        ),
                      ]),
                      SettingsSectionTitle('Zones (${_zones.length})',
                          trailing: TextButton.icon(
                            onPressed: () => setState(() {
                              _zones.add(_Zone());
                              _active = _zones.length - 1;
                            }),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add zone'),
                          )),
                      for (var i = 0; i < _zones.length; i++) _zoneCard(i),
                    ],
                  ],
                ),
      bottomNavigationBar: _loading || _error != null ? null : SettingsSaveBar(saving: _saving, onSave: _save),
    );
  }

  Widget _zoneCard(int i) {
    final z = _zones[i];
    final active = i == _active;
    return GestureDetector(
      onTap: () => setState(() => _active = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppColors.error : const Color(0xFFECEEF1), width: active ? 1.5 : 1),
        ),
        child: Column(children: [
          Row(children: [
            Text('Zone ${i + 1}${active ? '  (active)' : ''}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const Spacer(),
            if (_zones.length > 1)
              IconButton(
                tooltip: 'Remove zone',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                onPressed: () => setState(() {
                  _zones.removeAt(i).dispose();
                  _active = _active.clamp(0, _zones.length - 1);
                }),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: z.label, decoration: settingsInput('Label (optional)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: z.lat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: settingsInput('Latitude'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: z.lng,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: settingsInput('Longitude'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: z.radius,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: settingsInput('Radius (optional)', suffix: 'm'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
    );
  }
}
