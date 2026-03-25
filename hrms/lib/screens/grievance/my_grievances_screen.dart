import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../services/grievance_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/bottom_navigation_bar.dart';
import 'grievance_detail_screen.dart';
import '../../widgets/app_tab_loader.dart';

class MyGrievancesScreen extends StatefulWidget {
  final bool embeddedInShell;

  const MyGrievancesScreen({super.key, this.embeddedInShell = false});

  @override
  State<MyGrievancesScreen> createState() => MyGrievancesScreenState();
}

class MyGrievancesScreenState extends State<MyGrievancesScreen> {
  final GrievanceService _service = GrievanceService();
  List<dynamic> _grievances = [];
  Map<String, dynamic>? _pagination;
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'all';
  String _searchQuery = '';
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _service.getGrievances(
        status: _statusFilter != 'all' ? _statusFilter : null,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        page: _page,
        limit: 10,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>?;
        setState(() {
          _grievances = (data?['grievances'] as List?)?.cast<dynamic>() ?? [];
          _pagination = data?['pagination'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to load grievances',
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong';
          _isLoading = false;
        });
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Submitted':
        return AppColors.info;
      case 'Under Review':
      case 'Assigned':
      case 'Investigation':
        return AppColors.warning;
      case 'Action Taken':
        return AppColors.primary;
      case 'Escalated':
      case 'Rejected':
        return AppColors.error;
      case 'Closed':
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  void refresh() => _load();

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'Critical':
        return AppColors.error;
      case 'High':
        return Colors.orange;
      case 'Medium':
        return AppColors.warning;
      case 'Low':
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search by ticket, title...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (v) {
                  _searchQuery = v;
                  _page = 1;
                  _load();
                },
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All', 'all'),
                    _buildFilterChip('Submitted', 'Submitted'),
                    _buildFilterChip('Under Review', 'Under Review'),
                    _buildFilterChip('Assigned', 'Assigned'),
                    _buildFilterChip('Investigation', 'Investigation'),
                    _buildFilterChip('Closed', 'Closed'),
                    _buildFilterChip('Rejected', 'Rejected'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _page = 1;
              await _load();
            },
            color: colorScheme.primary,
            child: _isLoading
                ? _buildLoading(colorScheme)
                : _error != null
                    ? _buildError(colorScheme)
                    : _grievances.isEmpty
                        ? _buildEmpty(colorScheme)
                        : _buildList(colorScheme),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _statusFilter = value;
            _page = 1;
            _load();
          });
        },
        selectedColor: AppColors.primary.withOpacity(0.3),
        checkmarkColor: AppColors.primary,
      ),
    );
  }

  Widget _buildLoading(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppTabLoader(),
          const SizedBox(height: 16),
          Text('Loading grievances...', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme colorScheme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.report_problem_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('No grievances yet', style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: _grievances.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _grievances.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: () {
                  _page++;
                  _load();
                },
                child: const Text('Load more'),
              ),
            ),
          );
        }
        final g = _grievances[index] as Map<String, dynamic>;
        return _buildGrievanceCard(context, g, colorScheme);
      },
    );
  }

  bool get _hasMore {
    if (_pagination == null) return false;
    final page = _pagination!['page'] ?? 1;
    final pages = _pagination!['pages'] ?? 1;
    return page < pages;
  }

  Widget _buildGrievanceCard(BuildContext context, Map<String, dynamic> g, ColorScheme colorScheme) {
    final ticketId = g['ticketId']?.toString() ?? '';
    final title = g['title']?.toString() ?? '';
    final category = (g['categoryId'] is Map ? (g['categoryId'] as Map)['name'] : g['category'])?.toString() ?? g['category']?.toString() ?? '';
    final status = g['status']?.toString() ?? 'Submitted';
    final priority = g['priority']?.toString() ?? 'Medium';
    final slaBreached = g['slaBreached'] == true;
    final createdAt = g['createdAt'];
    DateTime? date;
    if (createdAt != null) {
      if (createdAt is String) date = DateTime.tryParse(createdAt);
      else if (createdAt is Map && createdAt['\$date'] != null) date = DateTime.tryParse(createdAt['\$date'].toString());
    }
    final dateStr = date != null ? DateFormat('MMM dd, yyyy').format(date) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GrievanceDetailScreen(
                grievanceId: g['_id']?.toString() ?? '',
              ),
            ),
          ).then((_) => _load());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticketId,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(status)),
                    ),
                  ),
                  if (slaBreached) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('SLA', style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (category.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(category, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _priorityColor(priority).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(priority, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _priorityColor(priority))),
                  ),
                  const Spacer(),
                  if (dateStr.isNotEmpty)
                    Text(dateStr, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('View', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20, color: AppColors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
