import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import '../../widgets/profile_app_bar_actions.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_tab_loader.dart';
import '../../services/asset_service.dart';
import '../../models/asset_model.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/swr_cache.dart';
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
  static const String _cacheKey = 'my_assets';

  final AssetService _assetService = AssetService();
  List<Asset> _hardware = [];
  List<Asset> _software = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-loaded assets instantly (no loader).
    // Skip the network while the cache is still fresh so moving tab-to-tab
    // doesn't reload or replay animations ("double load").
    final cached = SwrCache.get<List<Asset>>(_cacheKey);
    if (cached != null) {
      _software = cached.where((a) => a.isSoftware).toList();
      _hardware = cached.where((a) => !a.isSoftware).toList();
      _isLoading = false;
    }
    if (!SwrCache.isFresh(_cacheKey)) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    // Don't blank already-visible (cached) data with a loader on revalidation.
    if (_hardware.isEmpty && _software.isEmpty) {
      setState(() => _isLoading = true);
    }
    final result =
        await _assetService.getAssets(status: null, page: 1, limit: 1000);
    if (!mounted) return;

    if (result['success']) {
      final all = (result['data'] as List<Asset>?) ?? [];
      SwrCache.set(_cacheKey, all);
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
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.report_problem_outlined,
                  color: AppColors.primaryText, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('Report Issue',
                    style: AppTextStyles.headingMedium)),
          ],
        ),
        content: Text(
          'Raise an issue for "${asset.name}"? Your IT / admin team will be '
          'notified to follow up.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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
      body: RefreshIndicator(
        onRefresh: _fetch,
        // Full-screen scroll: the app bar is a sliver so the title scrolls
        // away with the content instead of staying pinned at the top.
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              leading: const MenuIconButton(),
              centerTitle: false,
              floating: true,
              snap: true,
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              title: const Text(
                'My Assets',
                style: AppTextStyles.headingLarge,
              ),
              actions: const [
                ProfileAppBarActions(),
              ],
            ),
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: AppTabLoader()),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSummaryRow(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Hardware Assets',
                        onViewAll:
                            _hardware.isEmpty ? null : _openHardwareList),
                    const SizedBox(height: 12),
                    if (_hardware.isEmpty)
                      _buildEmpty('No hardware assigned to you.',
                          Icons.devices_other_outlined)
                    else
                      ...List.generate(
                        _hardware.length > 3 ? 3 : _hardware.length,
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FadeSlideIn(
                            delay: Duration(
                                milliseconds: (i * 60).clamp(0, 240)),
                            child: _buildHardwareCard(_hardware[i]),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    _buildSectionHeader('Software Licenses',
                        onViewAll: _openSoftware),
                    const SizedBox(height: 12),
                    if (_software.isEmpty)
                      _buildEmpty('No software licenses yet.',
                          Icons.apps_outlined)
                    else
                      SizedBox(
                        height: 190,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _software.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, i) => FadeSlideIn(
                            delay: Duration(
                                milliseconds: (i * 60).clamp(0, 240)),
                            child: _buildSoftwareCard(_software[i]),
                          ),
                        ),
                      ),
                  ]),
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
        const SizedBox(width: 12),
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
    final fg = filled ? AppColors.onPrimary : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: filled
              ? null
              : Border.all(color: const Color(0xFFECEEF1)),
          boxShadow: [
            BoxShadow(
              color: filled
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
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
                color: filled
                    ? AppColors.onPrimary.withValues(alpha: 0.12)
                    : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: filled ? AppColors.onPrimary : AppColors.primaryText,
                  size: 22),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: AppTextStyles.sectionLabel.copyWith(
                color: filled
                    ? AppColors.onPrimary.withValues(alpha: 0.8)
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              count.toString().padLeft(2, '0'),
              style: AppTextStyles.displayLarge.copyWith(color: fg),
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
          style: AppTextStyles.headingMedium,
        ),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                'VIEW ALL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Hardware card ────────────────────────────────────────────────────────
  Widget _buildHardwareCard(Asset asset) {
    // The web Assets module has no "Active"/"Inactive" status, so don't surface
    // the fabricated ACTIVE badge for working assets. Real states
    // (maintenance / damaged / retired) are still shown.
    final isWorking = asset.status.toLowerCase() == 'working';
    final badge = _statusBadge(asset.status);
    return InkWell(
      onTap: () => _openDetails(asset),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFECEEF1)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_hardwareIcon(asset),
                      color: AppColors.primaryText, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        style: AppTextStyles.headingSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (asset.serialNumber != null &&
                                asset.serialNumber!.isNotEmpty)
                            ? 'S/N: ${asset.serialNumber}'
                            : (asset.type ?? asset.assetCategory ?? '—'),
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!isWorking) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badge.bg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: badge.fg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Report issue action.
            InkWell(
              onTap: () => _reportIssue(asset),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: AppColors.primaryText),
                    const SizedBox(width: 8),
                    Text(
                      'REPORT ISSUE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.primaryText,
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
          border: Border.all(color: const Color(0xFFECEEF1)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 3),
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
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.widgets_outlined,
                  color: AppColors.primaryText, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              asset.name,
              style: AppTextStyles.headingSmall.copyWith(height: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              asset.type ?? asset.assetCategory ?? 'License',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            const Divider(height: 16),
            Text(
              'RENEWAL',
              style: AppTextStyles.sectionLabel.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 4),
            Text(
              renewLabel,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
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
        border: Border.all(color: const Color(0xFFECEEF1)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: AppColors.primaryText),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary),
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
          fg: AppColors.primaryText,
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
