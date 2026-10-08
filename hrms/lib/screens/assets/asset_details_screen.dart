import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../services/asset_service.dart';
import '../../models/asset_model.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/oriented_image.dart';

class AssetDetailsScreen extends StatefulWidget {
  final String? assetId;

  const AssetDetailsScreen({super.key, required this.assetId});

  @override
  State<AssetDetailsScreen> createState() => _AssetDetailsScreenState();
}

class _AssetDetailsScreenState extends State<AssetDetailsScreen> {
  final AssetService _assetService = AssetService();
  Asset? _asset;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAssetDetails();
  }

  Future<void> _fetchAssetDetails() async {
    if (widget.assetId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Asset ID is required';
      });
      return;
    }

    setState(() => _isLoading = true);
    final result = await _assetService.getAssetById(widget.assetId!);
    if (mounted) {
      if (result['success']) {
        setState(() {
          _asset = result['data'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch asset details',
          );
        });
        SnackBarUtils.showSnackBar(
          context,
          _errorMessage!,
          isError: true,
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'working':
        return AppColors.success;
      case 'under maintenance':
        return AppColors.warning;
      case 'damaged':
        return AppColors.error;
      case 'retired':
        return AppColors.textSecondary;
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Asset Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: AppColors.errorBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            size: 32,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                )
              : _asset == null
                  ? Center(
                      child: Text(
                        'Asset not found',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchAssetDetails,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          // Asset Details Card
                          AppCard(
                            padding: const EdgeInsets.all(20.0),
                            border: Border.all(color: const Color(0xFFECEEF1)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title with icon
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppColors.info.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.info_outline_rounded,
                                        color: AppColors.info,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Asset Details',
                                        style: AppTextStyles.headingMedium,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                // Asset Photo (if available)
                                if (_asset!.assetPhoto != null &&
                                    _asset!.assetPhoto!.isNotEmpty)
                                  Center(
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 20),
                                      width: 200,
                                      height: 200,
                                      decoration: BoxDecoration(
                                        color: AppColors.inputFill,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFFECEEF1),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: OrientedImage.network(
                                          _asset!.assetPhoto!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.image_not_supported_outlined,
                                              size: 48,
                                              color: AppColors.textCaption,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                const Divider(height: 1),
                                const SizedBox(height: 20),
                                // Two-column layout for details
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Left Column
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildDetailRow(
                                            'Asset Name',
                                            _asset!.name,
                                          ),
                                          const SizedBox(height: 16),
                                          _buildDetailRow(
                                            'Asset Category',
                                            _asset!.assetCategory ?? '-',
                                          ),
                                          const SizedBox(height: 16),
                                          _buildDetailRow(
                                            'Status',
                                            _asset!.status,
                                            isStatus: true,
                                          ),
                                          const SizedBox(height: 16),
                                          _buildDetailRow(
                                            'Location',
                                            _asset!.location ?? '-',
                                          ),
                                          const SizedBox(height: 16),
                                          _buildDetailRow(
                                            'Notes',
                                            _asset!.notes ?? '-',
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Right Column
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildDetailRow(
                                            'Type',
                                            _asset!.type ?? '-',
                                          ),
                                          const SizedBox(height: 16),
                                          _buildDetailRow(
                                            'Serial Number',
                                            _asset!.serialNumber ?? '-',
                                          ),
                                          const SizedBox(height: 16),
                                          _buildDetailRow(
                                            'Branch',
                                            _asset!.branchName.isNotEmpty
                                                ? _asset!.branchName
                                                : '-',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // OK Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'),
                            ),
                          ),
                        ],
                      ),
                    ),
                      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isStatus = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        isStatus
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(value).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(value),
                  ),
                ),
              )
            : Text(
                value,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
      ],
    );
  }
}
