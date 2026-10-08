// Business > Company Master Details: GET/PUT /admin/company.
// Mirrors web features/admin/staff/settings/Business/CompanyMasterDetails.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'settings_common.dart';

class CompanyMasterScreen extends StatefulWidget {
  const CompanyMasterScreen({super.key});

  @override
  State<CompanyMasterScreen> createState() => _CompanyMasterScreenState();
}

class _CompanyMasterScreenState extends State<CompanyMasterScreen> {
  final _svc = AdminSettingsService.instance;
  Map<String, dynamic>? _company;
  String? _error;
  bool _editing = false;
  bool _saving = false;

  // key -> (label, required)
  static const _fields = <String, (String, bool)>{
    'name': ('Business / Company name', true),
    'code': ('Company code', true),
    'companyAdmin': ('Company admin', true),
    'email': ('Primary email', true),
    'mobileNumber': ('Primary contact', true),
    'organizationType': ('Organization type', false),
    'gstNumber': ('GST number', false),
    'industry': ('Industry', false),
    'website': ('Website', false),
    'address': ('Street address', true),
    'city': ('City', true),
    'state': ('State', true),
    'country': ('Country', true),
    'pincode': ('Pincode', true),
    'couponCode': ('Coupon code', false),
  };

  final Map<String, TextEditingController> _c = {for (final k in _fields.keys) k: TextEditingController()};
  final _grace = TextEditingController();
  String _status = 'active';
  String _renewal = 'manual';
  String _logo = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _grace.dispose();
    super.dispose();
  }

  void _fill(Map<String, dynamic> d) {
    for (final k in _fields.keys) {
      _c[k]!.text = (d[k] ?? (k == 'country' ? 'India' : '')).toString();
    }
    _grace.text = (d['gracePeriod'] ?? 0).toString();
    _status = (d['companyStatus'] ?? 'active').toString();
    _renewal = (d['renewalOption'] ?? 'manual').toString();
    _logo = (d['logo'] ?? '').toString();
  }

  Future<void> _load() async {
    try {
      final d = await _svc.getCompany();
      if (!mounted) return;
      setState(() {
        _company = d;
        _error = null;
        _fill(d);
      });
    } catch (e) {
      if (mounted) setState(() => _error = settingsErrorText(e));
    }
  }

  Future<void> _pickLogo() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) showSettingsError(context, 'Logo must be smaller than 5 MB.');
        return;
      }
      final ext = x.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      setState(() => _logo = 'data:image/$ext;base64,${base64Encode(bytes)}');
    } catch (e) {
      if (mounted) showSettingsError(context, 'Could not read the image. ${settingsErrorText(e)}');
    }
  }

  Future<void> _save() async {
    for (final e in _fields.entries) {
      if (e.value.$2 && _c[e.key]!.text.trim().isEmpty) {
        showSettingsError(context, 'Please fill in all required fields.');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        for (final k in _fields.keys) k: _c[k]!.text.trim(),
        'companyStatus': _status,
        'renewalOption': _renewal,
        'gracePeriod': int.tryParse(_grace.text.trim()) ?? 0,
        'logo': _logo,
      };
      final d = await _svc.updateCompany(body);
      if (!mounted) return;
      setState(() {
        _company = d.isEmpty ? _company : d;
        _editing = false;
        if (d.isNotEmpty) _fill(d);
      });
      showSettingsSuccess(context, 'Company master details updated successfully');
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    setState(() {
      _editing = false;
      if (_company != null) _fill(_company!);
    });
  }

  Widget _logoView() {
    Widget img;
    if (_logo.startsWith('data:image/')) {
      img = Image.memory(base64Decode(_logo.split(',').last), fit: BoxFit.contain);
    } else if (_logo.isNotEmpty) {
      img = Image.network(_logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.business_outlined, size: 36, color: AppColors.textCaption));
    } else {
      img = const Icon(Icons.business_outlined, size: 36, color: AppColors.textCaption);
    }
    return Row(children: [
      Container(
        width: 72,
        height: 72,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFECEEF1)),
        ),
        child: img,
      ),
      const SizedBox(width: 16),
      if (_editing)
        OutlinedButton.icon(onPressed: _pickLogo, icon: const Icon(Icons.upload_rounded, size: 18), label: const Text('Change logo')),
    ]);
  }

  Widget _field(String key) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[key],
          enabled: _editing,
          keyboardType: key == 'email'
              ? TextInputType.emailAddress
              : (key == 'mobileNumber' || key == 'pincode')
                  ? TextInputType.phone
                  : TextInputType.text,
          decoration: settingsInput('${_fields[key]!.$1}${_fields[key]!.$2 ? ' *' : ''}'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar('Company Master', actions: [
        if (_company != null && !_editing)
          TextButton.icon(onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit')),
        if (_editing) TextButton(onPressed: _saving ? null : _cancel, child: const Text('Cancel')),
      ]),
      body: _error != null && _company == null
          ? SettingsErrorView(message: _error!, onRetry: _load)
          : _company == null
              ? const SettingsLoading()
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _editing ? () async {} : _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      const SettingsSectionTitle('Company details'),
                      SettingsFormCard(children: [
                        for (final k in ['name', 'code', 'companyAdmin', 'email', 'mobileNumber', 'organizationType', 'gstNumber', 'industry', 'website'])
                          _field(k),
                        SettingsDropdown<String>(
                          label: 'Company status',
                          value: _status,
                          items: const [
                            DropdownMenuItem(value: 'active', child: Text('Active')),
                            DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          ],
                          onChanged: _editing ? (v) => setState(() => _status = v ?? 'active') : null,
                        ),
                        const SizedBox(height: 12),
                      ]),
                      const SettingsSectionTitle('Company logo'),
                      SettingsFormCard(padding: const EdgeInsets.all(16), children: [_logoView()]),
                      const SettingsSectionTitle('Address'),
                      SettingsFormCard(children: [for (final k in ['address', 'city', 'state', 'country', 'pincode']) _field(k)]),
                      const SettingsSectionTitle('Subscription'),
                      SettingsFormCard(children: [
                        Row(children: [
                          Expanded(child: _readOnly('Registered date', fmtDisplayDate(_company!['registeredAt'] ?? _company!['createdAt']))),
                          const SizedBox(width: 12),
                          Expanded(child: _readOnly('Expiry date', fmtDisplayDate(_company!['expiryDate']))),
                        ]),
                        const SizedBox(height: 12),
                        SettingsDropdown<String>(
                          label: 'Renewal option',
                          value: _renewal,
                          items: const [
                            DropdownMenuItem(value: 'auto', child: Text('Auto')),
                            DropdownMenuItem(value: 'manual', child: Text('Manual')),
                          ],
                          onChanged: _editing ? (v) => setState(() => _renewal = v ?? 'manual') : null,
                        ),
                        const SizedBox(height: 12),
                        _field('couponCode'),
                        TextField(
                          controller: _grace,
                          enabled: _editing,
                          keyboardType: TextInputType.number,
                          decoration: settingsInput('Grace period', suffix: 'days'),
                        ),
                        const SizedBox(height: 12),
                      ]),
                    ],
                  ),
                ),
      bottomNavigationBar: _editing ? SettingsSaveBar(saving: _saving, onSave: _save, label: 'Save changes') : null,
    );
  }

  Widget _readOnly(String label, String value) => InputDecorator(
        decoration: settingsInput(label),
        child: Text(value, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      );
}
