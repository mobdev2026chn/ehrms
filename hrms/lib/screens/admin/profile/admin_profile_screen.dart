// lib/screens/admin/profile/admin_profile_screen.dart
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_settings_service.dart';
import '../../../services/auth_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import '../../../widgets/bottom_navigation_bar.dart';
import '../../../widgets/menu_icon_button.dart';
import '../../auth/login_screen.dart';
import '../../notifications/notifications_screen.dart';
import '../settings/company_master_screen.dart';

class AdminProfileScreen extends StatefulWidget {
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  const AdminProfileScreen({
    super.key,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
  });

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final AdminSettingsService _settingsSvc = AdminSettingsService.instance;
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _cachedUserData;
  Map<String, dynamic>? _companyData;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadFromCacheAndFetch();
  }

  Future<void> _loadFromCacheAndFetch() async {
    // 1. Instant load from local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final parsed = jsonDecode(userStr);
        if (parsed is Map) {
          _cachedUserData = Map<String, dynamic>.from(parsed);
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        if (_cachedUserData != null) {
          _isLoading = false;
        }
      });
    }

    // 2. Fetch fresh company details from backend
    try {
      final company = await _settingsSvc.getCompany();
      if (mounted) {
        setState(() {
          _companyData = company;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _val(String key, [String fallback = '—']) {
    final v = _companyData?[key] ?? _cachedUserData?[key];
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String get _adminName {
    final name = _val('companyAdmin', '');
    if (name.isNotEmpty && name != '—') return name;
    final uName = _val('name', '');
    if (uName.isNotEmpty && uName != '—') return uName;
    return 'Administrator';
  }

  String get _companyName {
    final name = _val('name', '');
    if (name.isNotEmpty && name != '—') return name;
    return 'Company';
  }

  String get _email => _val('email');
  String get _phone => _val('mobileNumber', _val('phoneNumber'));
  String get _code => _val('code');
  String get _role {
    final r = (_cachedUserData?['role'] ?? _companyData?['role'] ?? 'admin').toString();
    return r.isEmpty ? 'ADMIN' : r.toUpperCase();
  }

  String get _status {
    final s = (_companyData?['companyStatus'] ?? _cachedUserData?['status'] ?? 'active').toString();
    return s.isEmpty ? 'ACTIVE' : s.toUpperCase();
  }

  String get _logoUrl {
    final l = (_companyData?['logo'] ?? _cachedUserData?['logo'] ?? _cachedUserData?['avatar'])?.toString().trim() ?? '';
    return l.startsWith('http') ? l : '';
  }

  String get _initial {
    final n = _adminName.trim();
    return n.isNotEmpty ? n[0].toUpperCase() : 'A';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: AppDrawer(
        currentIndex: widget.dashboardTabIndex ?? 3,
        onNavigateToIndex: widget.onNavigateToIndex,
      ),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('Admin Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, size: 24),
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh Profile',
            onPressed: () => _loadFromCacheAndFetch(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading && _cachedUserData == null && _companyData == null
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: _loadFromCacheAndFetch,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildHeroHeader(),
                  const SizedBox(height: 16),
                  _buildAccountInfoCard(),
                  const SizedBox(height: 16),
                  _buildCompanyInfoCard(),
                  const SizedBox(height: 16),
                  _buildAddressCard(),
                  const SizedBox(height: 16),
                  _buildSecurityCard(),
                  const SizedBox(height: 24),
                  _buildLogoutButton(),
                ],
              ),
            ),
      bottomNavigationBar: widget.onNavigateToIndex != null
          ? null
          : const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _buildHeroHeader() {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandLight,
                  border: Border.all(color: AppColors.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _logoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _logoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _buildInitialsAvatar(),
                        )
                      : _buildInitialsAvatar(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _adminName,
                      style: AppTextStyles.headingSmall.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _companyName,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildBadge(
                          label: _role == 'SUPERADMIN' ? 'SUPER ADMIN' : 'ADMINISTRATOR',
                          icon: Icons.shield_rounded,
                          color: const Color(0xFFB45309),
                          bgColor: const Color(0xFFFEF3C7),
                        ),
                        _buildBadge(
                          label: _status,
                          icon: Icons.check_circle_rounded,
                          color: AppColors.success,
                          bgColor: AppColors.successBg,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_code.isNotEmpty && _code != '—') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.corporate_fare_rounded, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Company Code:',
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _code,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brandLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Root Account',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar() {
    return Center(
      child: Text(
        _initial,
        style: TextStyle(
          color: AppColors.primaryDark,
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountInfoCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle(
                icon: Icons.person_outline_rounded,
                title: 'Account Information',
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                tooltip: 'Edit Details',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                onPressed: _showEditProfileSheet,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailRow(
            label: 'Administrator Name',
            value: _adminName,
            icon: Icons.badge_outlined,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildDetailRow(
            label: 'Primary Email',
            value: _email,
            icon: Icons.alternate_email_rounded,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildDetailRow(
            label: 'Contact Number',
            value: _phone,
            icon: Icons.phone_outlined,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildDetailRow(
            label: 'System Role',
            value: _role == 'SUPERADMIN' ? 'Super Administrator' : 'Administrator (Full Access)',
            icon: Icons.verified_user_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyInfoCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle(
                icon: Icons.business_outlined,
                title: 'Organization Details',
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CompanyMasterScreen()),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.settings_outlined, size: 15),
                label: const Text('Manage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailRow(
            label: 'Company / Business Name',
            value: _companyName,
            icon: Icons.apartment_rounded,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildDetailRow(
            label: 'Company Code',
            value: _code,
            icon: Icons.tag_rounded,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildDetailRow(
            label: 'Industry',
            value: _val('industry'),
            icon: Icons.category_outlined,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildDetailRow(
            label: 'Organization Type',
            value: _val('organizationType'),
            icon: Icons.account_balance_outlined,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildDetailRow(
            label: 'Website',
            value: _val('website'),
            icon: Icons.language_rounded,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildDetailRow(
            label: 'GST / Tax Number',
            value: _val('gstNumber', 'Not Provided'),
            icon: Icons.receipt_long_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    final street = _val('address', '');
    final city = _val('city', '');
    final state = _val('state', '');
    final country = _val('country', '');
    final pincode = _val('pincode', '');

    final hasAddress = street != '—' || city != '—' || state != '—' || country != '—';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            icon: Icons.location_on_outlined,
            title: 'Registered Address',
          ),
          const SizedBox(height: 14),
          if (!hasAddress)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No registered address entered yet. Configure it under Company Master Details.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            )
          else ...[
            _buildDetailRow(
              label: 'Street Address',
              value: street.isEmpty ? '—' : street,
              icon: Icons.home_outlined,
            ),
            const Divider(height: 18, color: AppColors.divider),
            Row(
              children: [
                Expanded(
                  child: _buildDetailRow(
                    label: 'City',
                    value: city.isEmpty ? '—' : city,
                    icon: Icons.location_city_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDetailRow(
                    label: 'State',
                    value: state.isEmpty ? '—' : state,
                    icon: Icons.map_outlined,
                  ),
                ),
              ],
            ),
            const Divider(height: 18, color: AppColors.divider),
            Row(
              children: [
                Expanded(
                  child: _buildDetailRow(
                    label: 'Country',
                    value: country.isEmpty ? 'India' : country,
                    icon: Icons.public_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDetailRow(
                    label: 'Pincode',
                    value: pincode.isEmpty ? '—' : pincode,
                    icon: Icons.pin_drop_outlined,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            icon: Icons.security_rounded,
            title: 'Security & Access',
          ),
          const SizedBox(height: 14),
          _buildActionTile(
            icon: Icons.edit_note_rounded,
            title: 'Edit Administrator Details',
            subtitle: 'Update your administrator name, primary email or phone number',
            onTap: _showEditProfileSheet,
          ),
          const Divider(height: 18, color: AppColors.divider),
          _buildActionTile(
            icon: Icons.business_center_outlined,
            title: 'Company Master Settings',
            subtitle: 'Update business logo, legal entity type, GST number and addresses',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CompanyMasterScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return OutlinedButton.icon(
      onPressed: _confirmLogout,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: Color(0xFFFCA5A5)),
        backgroundColor: const Color(0xFFFEF2F2),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.logout_rounded, size: 20),
      label: const Text(
        'Sign Out of Admin Account',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }

  Widget _buildSectionTitle({required IconData icon, required String title}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.brandLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: AppTextStyles.headingSmall.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showEditProfileSheet() {
    final nameCtrl = TextEditingController(text: _adminName == 'Administrator' ? '' : _adminName);
    final emailCtrl = TextEditingController(text: _email == '—' ? '' : _email);
    final phoneCtrl = TextEditingController(text: _phone == '—' ? '' : _phone);
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Edit Administrator Details',
                    style: AppTextStyles.headingSmall.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Update primary contact details for your administrator account.',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Administrator Full Name *',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Primary Email Address *',
                      prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Primary Phone Number *',
                      prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required' : null,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setSheetState(() => _isSaving = true);
                                  setState(() => _isSaving = true);
                                  try {
                                    final current = _companyData ?? <String, dynamic>{};
                                    final updatedPayload = Map<String, dynamic>.from(current)
                                      ..['companyAdmin'] = nameCtrl.text.trim()
                                      ..['email'] = emailCtrl.text.trim()
                                      ..['mobileNumber'] = phoneCtrl.text.trim();

                                    final res = await _settingsSvc.updateCompany(updatedPayload);

                                    // Update cached SharedPreferences user
                                    final prefs = await SharedPreferences.getInstance();
                                    final userStr = prefs.getString('user');
                                    if (userStr != null) {
                                      try {
                                        final u = jsonDecode(userStr);
                                        if (u is Map) {
                                          u['name'] = nameCtrl.text.trim();
                                          u['companyAdmin'] = nameCtrl.text.trim();
                                          u['email'] = emailCtrl.text.trim();
                                          u['phoneNumber'] = phoneCtrl.text.trim();
                                          u['mobileNumber'] = phoneCtrl.text.trim();
                                          await prefs.setString('user', jsonEncode(u));
                                        }
                                      } catch (_) {}
                                    }

                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                    if (mounted) {
                                      setState(() {
                                        _companyData = res;
                                        _isSaving = false;
                                      });
                                      SnackBarUtils.showSnackBar(
                                        context,
                                        'Administrator profile updated successfully!',
                                      );
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      setSheetState(() => _isSaving = false);
                                    }
                                    if (mounted) {
                                      setState(() => _isSaving = false);
                                      SnackBarUtils.showSnackBar(
                                        context,
                                        ErrorMessageUtils.toUserFriendlyMessage(e),
                                        isError: true,
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.ink,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Save Details', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of your Administrator account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _authService.logout();
    if (!mounted) return;
    AppDrawer.resetMenuMemory();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}
