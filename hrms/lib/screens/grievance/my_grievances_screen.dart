import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../services/grievance_service.dart';
import '../../utils/error_message_utils.dart';
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
        return AppColors.primaryText;
      case 'Escalated':
      case 'Rejected':
        return AppColors.error;
      case 'Closed':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  void refresh() => _load();

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'Critical':
        return AppColors.error;
      case 'High':
        return AppColors.brand;
      case 'Medium':
        return AppColors.warning;
      case 'Low':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
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
                decoration: const InputDecoration(
                  hintText: 'Search by ticket, title...',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  fillColor: AppColors.surface,
                  contentPadding: EdgeInsets.symmetric(
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
        checkmarkColor: AppColors.primaryText,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? AppColors.primaryText : AppColors.textSecondary,
        ),
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: selected ? Colors.transparent : const Color(0xFFE2E5EA),
        ),
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
          const Text('Loading grievances...', style: AppTextStyles.bodySmall),
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
            _stateIcon(Icons.error_outline_rounded, AppColors.error, AppColors.errorBg),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
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
          height: 240,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stateIcon(Icons.report_problem_outlined, AppColors.primaryText, AppColors.primary.withValues(alpha: 0.12)),
                const SizedBox(height: 16),
                const Text('No grievances yet', style: AppTextStyles.headingSmall),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stateIcon(IconData icon, Color fg, Color bg) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 30, color: fg),
    );
  }

  /// Pill badge (radius 999, h10 v4, 12/w600).
  Widget _pill(String text, Color fg, Color bg, {Widget? leading}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 6)],
          Text(
            text,
            maxLines: 1,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }

  /// Status pill colours: shared [AppColors.statusStyle] where it knows the
  /// status, otherwise the screen's own grievance status colour.
  ({Color fg, Color bg}) _statusPillColors(String status) {
    final s = AppColors.statusStyle(status);
    if (s.fg != AppColors.textSecondary) return (fg: s.fg, bg: s.bg);
    final c = _statusColor(status);
    return (fg: c, bg: c.withValues(alpha: 0.12));
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
      if (createdAt is String) {
        date = DateTime.tryParse(createdAt);
      } else if (createdAt is Map && createdAt['\$date'] != null) date = DateTime.tryParse(createdAt['\$date'].toString());
    }
    final dateStr = date != null ? DateFormat('MMM dd, yyyy').format(date) : '';

    final statusColors = _statusPillColors(status);
    final priorityColor = _priorityColor(priority);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
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
        borderRadius: BorderRadius.circular(16),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _pill(status, statusColors.fg, statusColors.bg),
                  if (slaBreached) ...[
                    const SizedBox(width: 6),
                    _pill(
                      'SLA',
                      AppColors.error,
                      AppColors.errorBg,
                      leading: const Icon(Icons.timer_off_outlined, size: 12, color: AppColors.error),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: AppTextStyles.headingSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (category.isNotEmpty)
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                border: Border.all(color: const Color(0xFFECEEF1)),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(category, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                            ),
                          ),
                        const SizedBox(width: 8),
                        _pill(
                          priority,
                          AppColors.textPrimary,
                          priorityColor.withValues(alpha: 0.12),
                          leading: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: priorityColor, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (dateStr.isNotEmpty)
                    Text(dateStr, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('View', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primaryText)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.primaryText),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
