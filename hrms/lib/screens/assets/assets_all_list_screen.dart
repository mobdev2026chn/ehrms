import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/animations.dart';
import '../../services/asset_service.dart';
import '../../models/asset_model.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import 'asset_details_screen.dart';
import '../../widgets/app_tab_loader.dart';

/// Full, filterable + paginated asset list. Reached from the "VIEW ALL" action
/// on the My Assets overview. Preserves the original search / status-filter /
/// branch / asset-type / pagination behaviour.
class AssetsAllListScreen extends StatefulWidget {
  /// When non-null, only assets matching this software/hardware split are shown
  /// (classification is client-side via [Asset.isSoftware]).
  final bool? softwareOnly;
  final String title;

  const AssetsAllListScreen({
    super.key,
    this.softwareOnly,
    this.title = 'All Assets',
  });

  @override
  State<AssetsAllListScreen> createState() => _AssetsAllListScreenState();
}

class _AssetsAllListScreenState extends State<AssetsAllListScreen> {
  final AssetService _assetService = AssetService();
  List<Asset> _assets = [];
  List<Asset> _allAssets = []; // Keep all assets for accurate counts
  bool _isLoading = true;
  String _selectedStatus = 'All Assets';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Filter state
  bool _showFilterCard = false;
  String? _selectedAssetType;
  String? _selectedBranchId;
  List<Map<String, dynamic>> _assetTypes = [];
  List<Map<String, dynamic>> _branches = [];
  bool _isFetchingFilters = false; // Prevent concurrent fetches

  // Pagination state
  int _page = 1;
  int _totalPages = 1;
  int _totalRecords = 0;
  final int _limit = 10;

  final List<String> _statusOptions = [
    'All Assets',
    'Working',
    'Under Maintenance',
    'Damaged',
    'Retired',
  ];

  /// Applies the optional hardware/software split on top of a server page.
  List<Asset> _applySplit(List<Asset> source) {
    if (widget.softwareOnly == null) return source;
    return source.where((a) => a.isSoftware == widget.softwareOnly).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchAllAssetsForCounts();
    _fetchFilters();
    _fetchAssets(refresh: true);
  }

  Future<void> _fetchFilters({bool forceRefresh = false}) async {
    if (_isFetchingFilters) return;

    _isFetchingFilters = true;

    try {
      final assetTypesResult =
          await _assetService.getAssetTypes(forceRefresh: forceRefresh);
      await Future.delayed(const Duration(milliseconds: 300));
      final branchesResult =
          await _assetService.getBranches(forceRefresh: forceRefresh);

      if (mounted) {
        setState(() {
          if (assetTypesResult['success'] == true &&
              assetTypesResult['data'] != null) {
            final data = assetTypesResult['data'];
            _assetTypes =
                data is List ? List<Map<String, dynamic>>.from(data) : [];
          } else if (_assetTypes.isEmpty) {
            _assetTypes = [];
          }

          if (branchesResult['success'] == true &&
              branchesResult['data'] != null) {
            final data = branchesResult['data'];
            _branches =
                data is List ? List<Map<String, dynamic>>.from(data) : [];
          } else if (_branches.isEmpty) {
            _branches = [];
          }
        });
      }
    } catch (_) {
      // Keep existing filter data on error.
    } finally {
      _isFetchingFilters = false;
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query != _searchQuery) {
      setState(() => _searchQuery = query);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_searchController.text.trim() == query) {
          _fetchAssets(refresh: true);
        }
      });
    }
  }

  Future<void> _fetchAllAssetsForCounts() async {
    final result =
        await _assetService.getAssets(status: null, page: 1, limit: 1000);
    if (mounted && result['success']) {
      setState(() => _allAssets = _applySplit(result['data'] ?? []));
    }
  }

  Future<void> _fetchAssets({bool refresh = false, int? page}) async {
    if (_isLoading && !refresh) return;

    final pageToFetch = page ?? _page;
    if (refresh) {
      _page = 1;
      _assets.clear();
    }

    setState(() => _isLoading = true);

    final result = await _assetService.getAssets(
      status: _selectedStatus == 'All Assets' ? null : _selectedStatus,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
      type: _selectedAssetType,
      branchId: _selectedBranchId,
      page: pageToFetch,
      limit: _limit,
    );

    if (mounted) {
      if (result['success']) {
        final pagination = result['pagination'] ?? {};
        setState(() {
          _assets = _applySplit(result['data'] ?? []);
          _page = pageToFetch;
          _totalRecords = pagination['total'] ?? 0;
          _totalPages = ((_totalRecords / _limit).ceil())
              .clamp(1, double.infinity)
              .toInt();
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
  }

  void _onStatusChanged(String status) {
    setState(() => _selectedStatus = status);
    _fetchAssets(refresh: true);
  }

  void _viewAssetDetails(Asset asset) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AssetDetailsScreen(assetId: asset.id!),
      ),
    );
  }

  int _getStatusCount(String status) {
    if (status == 'All Assets') return _allAssets.length;
    return _allAssets.where((a) => a.status == status).length;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _showFilterCard ? Icons.filter_alt : Icons.filter_alt_outlined,
              color:
                  _showFilterCard ? colorScheme.primary : colorScheme.onSurface,
            ),
            onPressed: () =>
                setState(() => _showFilterCard = !_showFilterCard),
            tooltip: 'Filter',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status filter tabs
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            color: colorScheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statusOptions.map((status) {
                  final isSelected = _selectedStatus == status;
                  final count = _getStatusCount(status);
                  return GestureDetector(
                    onTap: () => _onStatusChanged(status),
                    child: Container(
                      margin: const EdgeInsets.only(right: 24),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        '$status${count > 0 ? ' ($count)' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_showFilterCard) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.outline),
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by name, type, category...',
                              hintStyle: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13),
                              prefixIcon: Icon(Icons.search,
                                  color: colorScheme.onSurfaceVariant,
                                  size: 20),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 4),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: () {
                          _fetchFilters(forceRefresh: true);
                          _fetchAssets(refresh: true);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Refresh',
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedAssetType,
                              isExpanded: true,
                              hint: const Text('All Asset Types',
                                  style: TextStyle(fontSize: 13)),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Asset Types',
                                      style: TextStyle(fontSize: 13)),
                                ),
                                ..._assetTypes.map((type) {
                                  final typeName =
                                      type['name']?.toString() ?? '';
                                  return DropdownMenuItem<String>(
                                    value: typeName.isEmpty ? null : typeName,
                                    child: Text(
                                      typeName.isEmpty ? 'N/A' : typeName,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }).where((item) => item.value != null),
                              ],
                              onChanged: (value) {
                                setState(() => _selectedAssetType = value);
                                _fetchAssets(refresh: true);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedBranchId,
                              isExpanded: true,
                              hint: const Text('All Branches',
                                  style: TextStyle(fontSize: 13)),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Branches',
                                      style: TextStyle(fontSize: 13)),
                                ),
                                ..._branches.map((branch) {
                                  final branchId =
                                      branch['_id']?.toString() ??
                                          branch['id']?.toString();
                                  final branchName =
                                      branch['branchName']?.toString() ?? '';
                                  return DropdownMenuItem<String>(
                                    value: branchId,
                                    child: Text(
                                      branchName.isEmpty ? 'N/A' : branchName,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                setState(() => _selectedBranchId = value);
                                _fetchAssets(refresh: true);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _isLoading && _assets.isEmpty
                  ? const Center(
                      key: ValueKey('assets-loading'),
                      child: AppTabLoader(),
                    )
                  : _assets.isEmpty
                      ? RefreshIndicator(
                          onRefresh: () async {
                            setState(() => _page = 1);
                            await _fetchAssets(refresh: true);
                          },
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inventory_2_outlined,
                                          size: 64,
                                          color: AppColors.textSecondary),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No assets assigned to you.',
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: () async {
                                  setState(() => _page = 1);
                                  await _fetchAssets(refresh: true);
                                },
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(16.0),
                                  itemCount: _assets.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12.0),
                                      child: FadeSlideIn(
                                        delay: Duration(
                                          milliseconds:
                                              (index * 45).clamp(0, 270),
                                        ),
                                        child: _buildAssetCard(_assets[index]),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (_totalPages > 1) ...[
                              const SizedBox(height: 16),
                              _buildPaginationControls(),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _buildAssetCard(Asset asset) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _viewAssetDetails(asset),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  asset.isSoftware
                      ? Icons.apps_outlined
                      : Icons.inventory_2_outlined,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            asset.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(asset.status)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            asset.status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(asset.status),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildCardDetailRow(
                        Icons.category_outlined, 'Type', asset.type ?? '-'),
                    const SizedBox(height: 4),
                    _buildCardDetailRow(Icons.label_outline, 'Category',
                        asset.assetCategory ?? '-'),
                    if (asset.serialNumber != null &&
                        asset.serialNumber!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildCardDetailRow(
                          Icons.qr_code, 'Serial', asset.serialNumber!),
                    ],
                    if (asset.location != null &&
                        asset.location!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildCardDetailRow(Icons.location_on_outlined,
                          'Location', asset.location!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardDetailRow(IconData icon, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaginationControls() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed:
                _page > 1 ? () => _fetchAssets(page: _page - 1) : null,
            color: _page > 1
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              _totalPages.clamp(0, 10),
              (index) {
                final pageNum = index + 1;
                final isCurrentPage = pageNum == _page;
                return GestureDetector(
                  onTap: () => _fetchAssets(page: pageNum),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrentPage
                          ? colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrentPage
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                    ),
                    child: Text(
                      '$pageNum',
                      style: TextStyle(
                        color: isCurrentPage
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                        fontWeight: isCurrentPage
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _page < _totalPages
                ? () => _fetchAssets(page: _page + 1)
                : null,
            color: _page < _totalPages
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
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
}
