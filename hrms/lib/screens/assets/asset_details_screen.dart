import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
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
        title: Text(
          'Asset Details',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('OK'),
                      ),
                    ],
                  ),
                )
              : _asset == null
                  ? const Center(
                      child: Text('Asset not found'),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchAssetDetails,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          // Asset Details Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title with icon
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.info.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.info_outline,
                                        color: AppColors.info,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Asset Details',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                // Asset Photo (if available)
                                if (_asset!.assetPhoto != null &&
                                    _asset!.assetPhoto!.isNotEmpty)
                                  Center(
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 24),
                                      width: 200,
                                      height: 200,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: OrientedImage.network(
                                          _asset!.assetPhoto!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.image_not_supported,
                                              size: 48,
                                              color: Colors.grey,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
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
                                    const SizedBox(width: 32),
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
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                'OK',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        isStatus
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(value).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(value),
                  ),
                ),
              )
            : Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
      ],
    );
  }
}
