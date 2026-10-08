import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_tab_loader.dart';
import '../../services/asset_service.dart';
import '../../models/asset_model.dart';
import 'asset_details_screen.dart';
import 'license_request_screen.dart';

/// Figma "Software Licenses" screen — status header, active subscriptions list
/// and a "Request New License" action.
///
/// Software licences are the subset of assets classified via [Asset.isSoftware].
class SoftwareLicensesScreen extends StatefulWidget {
  const SoftwareLicensesScreen({super.key});

  @override
  State<SoftwareLicensesScreen> createState() => _SoftwareLicensesScreenState();
}

class _SoftwareLicensesScreenState extends State<SoftwareLicensesScreen> {
  final AssetService _assetService = AssetService();
  List<Asset> _licenses = [];
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
    if (mounted) {
      final all = (result['data'] as List<Asset>?) ?? [];
      setState(() {
        _licenses = all.where((a) => a.isSoftware).toList();
        _isLoading = false;
      });
    }
  }

  int get _activeCount =>
      _licenses.where((a) => a.status.toLowerCase() == 'working').length;

  /// Smallest positive days-to-renew across licences (for the header stat).
  int? get _nextRenewalDays {
    final days = _licenses
        .map((a) => a.daysToRenew)
        .whereType<int>()
        .where((d) => d >= 0)
        .toList()
      ..sort();
    return days.isEmpty ? null : days.first;
  }

  void _openRequest({String? prefill}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LicenseRequestScreen(prefillSoftwareName: prefill),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Software Licenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifications',
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Active Subscriptions',
                        style: AppTextStyles.headingMedium,
                      ),
                      if (_licenses.isNotEmpty)
                        const Text(
                          'VIEW ALL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textCaption,
                            letterSpacing: 0.8,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_licenses.isEmpty)
                    _buildEmptyState()
                  else
                    ...List.generate(_licenses.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FadeSlideIn(
                          delay:
                              Duration(milliseconds: (i * 60).clamp(0, 300)),
                          child: _buildSubscriptionCard(_licenses[i]),
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _openRequest(),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Request New License'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _buildStatusCard() {
    final days = _nextRenewalDays;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT STATUS',
                    style: AppTextStyles.sectionLabel.copyWith(
                      color: AppColors.onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Software Licenses',
                    style: AppTextStyles.headingLarge.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.onPrimary.withValues(alpha: 0.12),
                ),
                child: Icon(Icons.verified_user_outlined,
                    color: AppColors.onPrimary, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  _activeCount.toString().padLeft(2, '0'),
                  'Active',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile(
                  days == null ? '—' : days.toString().padLeft(2, '0'),
                  'Days to Renew',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyles.displayLarge.copyWith(
              color: AppColors.onPrimary,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.onPrimary.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(Asset asset) {
    final badge = _renewBadge(asset);
    final renewLabel = asset.warrantyExpiry != null
        ? 'Renew: ${DateFormat('MMM d, yyyy').format(asset.warrantyExpiry!)}'
        : 'No renewal date';
    final isUrgent = badge.urgent;

    return InkWell(
      onTap: () => asset.id == null
          ? null
          : Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssetDetailsScreen(assetId: asset.id!),
              ),
            ),
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
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.apps_rounded,
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
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ((asset.type ?? '').isNotEmpty) asset.type,
                      if ((asset.assetCategory ?? '').isNotEmpty)
                        asset.assetCategory,
                    ].whereType<String>().join(' • '),
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        isUrgent
                            ? Icons.warning_amber_rounded
                            : Icons.calendar_today_outlined,
                        size: 14,
                        color: isUrgent
                            ? AppColors.warning
                            : AppColors.textCaption,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        renewLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isUrgent ? FontWeight.w600 : FontWeight.w400,
                          color: isUrgent
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badge.bg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: badge.fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, Color fg, Color bg, bool urgent}) _renewBadge(Asset asset) {
    final status = asset.status.toLowerCase();
    if (status == 'retired') {
      return (
        label: 'Inactive',
        fg: AppColors.textSecondary,
        bg: AppColors.inputFill,
        urgent: false,
      );
    }
    final days = asset.daysToRenew;
    if (days != null && days <= 14) {
      return (
        label: 'Expiring Soon',
        fg: AppColors.warning,
        bg: AppColors.warningBg,
        urgent: true,
      );
    }
    return (
      label: 'Active',
      fg: AppColors.success,
      bg: AppColors.successBg,
      urgent: false,
    );
  }

  Widget _buildEmptyState() {
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
            child: Icon(Icons.apps_outlined,
                size: 30, color: AppColors.primaryText),
          ),
          const SizedBox(height: 16),
          const Text(
            'No software licenses yet.',
            textAlign: TextAlign.center,
            style: AppTextStyles.headingSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Request a new license to get started.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}
