import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_tab_loader.dart';
import '../../services/asset_service.dart';
import '../../models/asset_model.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import 'asset_details_screen.dart';
import 'assets_all_list_screen.dart';
import 'software_licenses_screen.dart';

/// "My Assets" overview (Figma redesign). Summarises the employee's hardware
/// assets and software licences, with deep-links into the full hardware list,
/// the software licences screen and asset details.
///
/// Hardware vs software is derived client-side via [Asset.isSoftware] since the
/// backend exposes a single generic asset collection.
class AssetsListingScreen extends StatefulWidget {
  const AssetsListingScreen({super.key});

  @override
  State<AssetsListingScreen> createState() => _AssetsListingScreenState();
}

class _AssetsListingScreenState extends State<AssetsListingScreen> {
  final AssetService _assetService = AssetService();
  List<Asset> _hardware = [];
  List<Asset> _software = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    final result =
        await _assetService.getAssets(status: null, page: 1, limit: 1000);
    if (!mounted) return;

    if (result['success']) {
      final all = (result['data'] as List<Asset>?) ?? [];
      setState(() {
        _software = all.where((a) => a.isSoftware).toList();
        _hardware = all.where((a) => !a.isSoftware).toList();
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(),
            fallback: 'Failed to fetch assets'),
        isError: true,
      );
    }
  }

  void _openHardwareList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AssetsAllListScreen(
          softwareOnly: false,
          title: 'Hardware Assets',
        ),
      ),
    );
  }

  void _openSoftware() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SoftwareLicensesScreen()),
    ).then((_) => _fetch());
  }

  void _openDetails(Asset asset) {
    if (asset.id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssetDetailsScreen(assetId: asset.id!),
      ),
    );
  }

  void _reportIssue(Asset asset) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.report_problem_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            const Expanded(child: Text('Report Issue')),
          ],
        ),
        content: Text(
          'Raise an issue for "${asset.name}"? Your IT / admin team will be '
          'notified to follow up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              SnackBarUtils.showSnackBar(
                context,
                'Issue reported for ${asset.name}.',
              );
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        centerTitle: false,
        title: const Text(
          'My Assets',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Icon(Icons.person, color: AppColors.primary, size: 20),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _buildSummaryRow(),
                  const SizedBox(height: 28),
                  _buildSectionHeader('Hardware Assets',
                      onViewAll: _hardware.isEmpty ? null : _openHardwareList),
                  const SizedBox(height: 12),
                  if (_hardware.isEmpty)
                    _buildEmpty('No hardware assigned to you.',
                        Icons.devices_other_outlined)
                  else
                    ...List.generate(
                      _hardware.length > 3 ? 3 : _hardware.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: FadeSlideIn(
                          delay:
                              Duration(milliseconds: (i * 60).clamp(0, 240)),
                          child: _buildHardwareCard(_hardware[i]),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('Software Licenses',
                      onViewAll: _openSoftware),
                  const SizedBox(height: 12),
                  if (_software.isEmpty)
                    _buildEmpty('No software licenses yet.',
                        Icons.apps_outlined)
                  else
                    SizedBox(
                      height: 168,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _software.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 14),
                        itemBuilder: (context, i) => FadeSlideIn(
                          delay:
                              Duration(milliseconds: (i * 60).clamp(0, 240)),
                          child: _buildSoftwareCard(_software[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  // ── Summary cards ────────────────────────────────────────────────────────
  Widget _buildSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            filled: true,
            icon: Icons.devices_outlined,
            label: 'HARDWARE',
            count: _hardware.length,
            onTap: _hardware.isEmpty ? null : _openHardwareList,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _summaryCard(
            filled: false,
            icon: Icons.dvr_outlined,
            label: 'SOFTWARE',
            count: _software.length,
            onTap: _openSoftware,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required bool filled,
    required IconData icon,
    required String label,
    required int count,
    VoidCallback? onTap,
  }) {
    final fg = filled ? Colors.white : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: filled
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: filled ? Colors.white : AppColors.primary, size: 26),
            const SizedBox(height: 20),
            Text(
              label,
              style: TextStyle(
                color: filled
                    ? Colors.white.withValues(alpha: 0.9)
                    : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              count.toString().padLeft(2, '0'),
              style: TextStyle(
                color: fg,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section header ───────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, {VoidCallback? onViewAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: Text(
              'VIEW ALL',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
      ],
    );
  }

  // ── Hardware card ────────────────────────────────────────────────────────
  Widget _buildHardwareCard(Asset asset) {
    final badge = _statusBadge(asset.status);
    return InkWell(
      onTap: () => _openDetails(asset),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_hardwareIcon(asset),
                      color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (asset.serialNumber != null &&
                                asset.serialNumber!.isNotEmpty)
                            ? 'S/N: ${asset.serialNumber}'
                            : (asset.type ?? asset.assetCategory ?? '—'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: badge.bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: badge.fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Report issue action.
            InkWell(
              onTap: () => _reportIssue(asset),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: AppColors.primaryDark),
                    const SizedBox(width: 6),
                    Text(
                      'REPORT ISSUE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Software card (horizontal) ───────────────────────────────────────────
  Widget _buildSoftwareCard(Asset asset) {
    final renewLabel = asset.warrantyExpiry != null
        ? DateFormat('dd MMM yyyy').format(asset.warrantyExpiry!)
        : '—';
    return InkWell(
      onTap: () => _openDetails(asset),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.widgets_outlined,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              asset.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              asset.type ?? asset.assetCategory ?? 'License',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            const Divider(height: 16),
            Text(
              'RENEWAL',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppColors.textCaption,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              renewLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.textHint),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  IconData _hardwareIcon(Asset asset) {
    final s = '${asset.type ?? ''} ${asset.assetCategory ?? ''} ${asset.name}'
        .toLowerCase();
    if (s.contains('laptop') || s.contains('macbook') || s.contains('book')) {
      return Icons.laptop_mac;
    }
    if (s.contains('monitor') || s.contains('display') || s.contains('screen')) {
      return Icons.desktop_windows_outlined;
    }
    if (s.contains('mouse') || s.contains('keyboard')) {
      return Icons.mouse_outlined;
    }
    if (s.contains('phone') || s.contains('mobile')) return Icons.smartphone;
    if (s.contains('printer')) return Icons.print_outlined;
    return Icons.devices_other_outlined;
  }

  ({String label, Color fg, Color bg}) _statusBadge(String status) {
    switch (status.toLowerCase()) {
      case 'working':
        return (
          label: 'ACTIVE',
          fg: AppColors.primaryDark,
          bg: AppColors.primary.withValues(alpha: 0.12),
        );
      case 'under maintenance':
        return (
          label: 'MAINTENANCE',
          fg: AppColors.warning,
          bg: AppColors.warningBg,
        );
      case 'damaged':
        return (label: 'DAMAGED', fg: AppColors.error, bg: AppColors.errorBg);
      case 'retired':
        return (
          label: 'RETIRED',
          fg: AppColors.textSecondary,
          bg: AppColors.inputFill,
        );
      default:
        return (
          label: status.toUpperCase(),
          fg: AppColors.textSecondary,
          bg: AppColors.inputFill,
        );
    }
  }
}
