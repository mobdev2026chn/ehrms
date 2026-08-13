import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
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
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Software Licenses',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
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
                padding: const EdgeInsets.all(20),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Active Subscriptions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (_licenses.isNotEmpty)
                        const Text(
                          'VIEW ALL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textCaption,
                            letterSpacing: 0.5,
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
                    child: ElevatedButton(
                      onPressed: () => _openRequest(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Request New License',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
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
        borderRadius: BorderRadius.circular(18),
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
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Software Licenses',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.verified_user_outlined,
                    color: Colors.white, size: 22),
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
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
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
        padding: const EdgeInsets.all(14),
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
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.apps, color: AppColors.primary, size: 24),
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
                    [
                      if ((asset.type ?? '').isNotEmpty) asset.type,
                      if ((asset.assetCategory ?? '').isNotEmpty)
                        asset.assetCategory,
                    ].whereType<String>().join(' • '),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        isUrgent
                            ? Icons.warning_amber_rounded
                            : Icons.calendar_today_outlined,
                        size: 13,
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
                              isUrgent ? FontWeight.w600 : FontWeight.normal,
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
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badge.bg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge.label,
                style: TextStyle(
                  fontSize: 11,
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
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.apps_outlined, size: 56, color: AppColors.textHint),
          const SizedBox(height: 12),
          const Text(
            'No software licenses yet.',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Request a new license to get started.',
            style: TextStyle(fontSize: 13, color: AppColors.textCaption),
          ),
        ],
      ),
    );
  }
}
