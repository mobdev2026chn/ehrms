// hrms/lib/screens/performance/my_goals_screen.dart
// My Goals - Summary cards, filters, goal cards with badges, progress bar, date range

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../../services/performance_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_tab_loader.dart';

class MyGoalsScreen extends StatefulWidget {
  final bool embeddedInModule;
  final bool hideAppBar;
  final int refreshTrigger;
  final int currentTabIndex;
  final int performanceTabIndex;

  const MyGoalsScreen({
    super.key,
    this.embeddedInModule = false,
    this.hideAppBar = false,
    this.refreshTrigger = 0,
    this.currentTabIndex = 0,
    this.performanceTabIndex = 1,
  });

  @override
  State<MyGoalsScreen> createState() => MyGoalsScreenState();
}

class MyGoalsScreenState extends State<MyGoalsScreen> {
  final PerformanceService _performanceService = PerformanceService();
  List<dynamic> _goals = [];
  List<dynamic> _cycles = [];
  List<dynamic> _kras = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedCycle;
  String? _selectedStatus;
  int _paginationTotal = 0;

  @override
  void initState() {
    super.initState();
    _fetchCycles();
    _fetchGoals();
    _fetchKras();
  }

  Future<void> _fetchKras() async {
    try {
      final result = await _performanceService.getKRAs(page: 1, limit: 1000);
      if (mounted) {
        final data = result['data'];
        setState(() => _kras = data?['kras'] as List? ?? []);
      }
    } catch (_) {}
  }

  Future<void> _fetchCycles() async {
    try {
      // Fetch from /api/performance/cycles (app_backend reviewCycleController)
      final result = await _performanceService.getReviewCycles(
        page: 1,
        limit: 100,
        status:
            null, // null = all; use 'active' or 'goal-submission' for open cycles only
      );
      if (mounted) {
        final data = result['data'];
        final cycles = data?['cycles'] as List? ?? [];
        setState(() {
          _cycles = cycles;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchGoals() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _performanceService.getGoals(
        page: 1,
        limit: 100,
        cycle: _selectedCycle,
        status: _selectedStatus,
      );
      if (mounted) {
        final data = result['data'];
        final pagination = data?['pagination'] as Map<String, dynamic>?;
        setState(() {
          _goals = data?['goals'] ?? [];
          _paginationTotal =
              (pagination?['total'] as num?)?.toInt() ?? _goals.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  int get _total => _paginationTotal > 0 ? _paginationTotal : _goals.length;
  int get _approved =>
      _goals.where((g) => (g['status'] ?? '') == 'approved').length;
  int get _pending =>
      _goals.where((g) => (g['status'] ?? '') == 'pending').length;
  int get _completed =>
      _goals.where((g) => (g['status'] ?? '') == 'completed').length;

  Color _getStatusColor(String status) {
    if (status == 'completed' || status == 'approved') return AppColors.success;
    if (status == 'pending') return AppColors.warning;
    if (status == 'draft' || status == 'modified') return AppColors.info;
    return AppColors.textSecondary;
  }

  Widget _buildBadge(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    return status
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  void showCreateGoalSheet() {
    if (mounted) _showCreateGoalSheet(context);
  }

  @override
  void didUpdateWidget(MyGoalsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger &&
        widget.currentTabIndex == widget.performanceTabIndex) {
      _fetchGoals();
      _fetchCycles();
    }
  }

  void _showCreateGoalSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateGoalSheet(
        cycles: _cycles,
        kras: _kras,
        onCreated: () {
          Navigator.pop(ctx);
          _fetchGoals();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showUpdateProgressSheet(
    BuildContext context,
    Map<String, dynamic> goal,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UpdateProgressSheet(
        goal: goal,
        onUpdated: () {
          Navigator.pop(ctx);
          _fetchGoals();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showGoalDetailsSheet(BuildContext context, Map<String, dynamic> goal) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GoalDetailsSheet(
        goal: goal,
        statusColor: _getStatusColor((goal['status'] ?? '').toString()),
        formatStatus: _formatStatus,
        onClose: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
          ? const Center(child: AppTabLoader())
          : _error != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _fetchGoals,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryCard(),
                    const SizedBox(height: 16),
                    _buildGoalsHeaderCard(),
                    const SizedBox(height: 16),
                    _goals.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _goals.length,
                            itemBuilder: (context, index) {
                              return _buildGoalCard(
                                _goals[index] as Map<String, dynamic>,
                              );
                            },
                          ),
                  ],
                ),
              ),
          );

    if (widget.embeddedInModule) {
      return body;
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: Text(
          'My Goals',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        actions: [
          TextButton.icon(
            onPressed: () => _showCreateGoalSheet(context),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text('Add Goal'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Failed to load goals',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchGoals,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.flag_outlined,
                size: 32,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No goals yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Get started by creating your first\nperformance goal.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
//const SizedBox(height: 22),
            // ElevatedButton.icon(
            //   onPressed: () => _showCreateGoalSheet(context),
            //   icon: const Icon(Icons.add_rounded, size: 20),
            //   label: const Text('Add Goal'),
            //   style: ElevatedButton.styleFrom(
            //     backgroundColor: AppColors.primary,
            //     foregroundColor: Colors.white,
            //     elevation: 0,
            //     padding: const EdgeInsets.symmetric(
            //       horizontal: 28,
            //       vertical: 14,
            //     ),
            //     textStyle: const TextStyle(
            //       fontSize: 15,
            //       fontWeight: FontWeight.bold,
            //     ),
            //     shape: RoundedRectangleBorder(
            //       borderRadius: BorderRadius.circular(30),
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manage your goals and track progress',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.3,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Performance Summary',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem(
                _total.toString(),
                'TOTAL',
                Icons.flag_rounded,
                AppColors.primary,
              ),
              _buildStatItem(
                _approved.toString(),
                'APPROVED',
                Icons.check_circle_rounded,
                AppColors.success,
              ),
              _buildStatItem(
                _pending.toString(),
                'PENDING',
                Icons.schedule_rounded,
                AppColors.warning,
              ),
              _buildStatItem(
                _completed.toString(),
                'DONE',
                Icons.done_all_rounded,
                AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String value,
    String label,
    IconData icon,
    Color iconColor,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoalsHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.flag_rounded, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'My Goals (${_goals.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'FILTERS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildFilterDropdown(
                value: _selectedCycle,
                hint: 'All Cycles',
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Cycles'),
                  ),
                  ..._cycles.map((c) {
                    final name = c['name'] ?? c['_id'] ?? '';
                    return DropdownMenuItem<String?>(
                      value: name.toString(),
                      child: Text(
                        name.toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (v) {
                  setState(() {
                    _selectedCycle = v;
                    _fetchGoals();
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFilterDropdown(
                value: _selectedStatus,
                hint: 'All Statuses',
                items: const [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Statuses'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'pending',
                    child: Text('Pending'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'approved',
                    child: Text('Approved'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'completed',
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'draft',
                    child: Text('Draft'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'rejected',
                    child: Text('Rejected'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'modified',
                    child: Text('Modified'),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _selectedStatus = v;
                    _fetchGoals();
                  });
                },
              ),
            ),
          ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String?>> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: (value == null || value.isEmpty) ? null : value,
          hint: Text(
            hint,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: AppColors.textSecondary,
          ),
          iconSize: 16,
        ),
      ),
    );
  }

  Widget _buildGoalCard(Map<String, dynamic> goal) {
    final status = (goal['status'] ?? '').toString();
    final title = goal['title'] ?? 'Goal';
    final type = (goal['type'] ?? '').toString();
    final kpi = goal['kpi'] ?? '';
    final target = goal['target'] ?? '';
    final weightage = (goal['weightage'] ?? 0) as num;
    final progress = ((goal['progress'] ?? 0) as num).toDouble().clamp(
      0.0,
      100.0,
    );
    final cycle = goal['cycle'] ?? '';
    final startDate = goal['startDate']?.toString();
    final endDate = goal['endDate']?.toString();
    final createdBy = goal['createdBy'];
    final isSelfCreated = createdBy != null;

    String dateRangeStr = '';
    if (startDate != null && endDate != null) {
      try {
        final start = DateTime.tryParse(startDate);
        final end = DateTime.tryParse(endDate);
        if (start != null && end != null) {
          dateRangeStr =
              '${DateFormat('MMM dd, yyyy').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}';
        }
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (type.isNotEmpty)
                  _buildBadge(type, AppColors.divider, AppColors.textPrimary),
                _buildBadge(
                  _formatStatus(status),
                  _getStatusColor(status).withOpacity(0.15),
                  _getStatusColor(status),
                ),
                if (isSelfCreated)
                  _buildBadge(
                    'Self-Created',
                    AppColors.textSecondary.withOpacity(0.2),
                    AppColors.textSecondary,
                  ),
              ],
            ),
            if (kpi.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'KPI: $kpi',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            if (target.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Target: $target',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            if (weightage > 0) ...[
              const SizedBox(height: 2),
              Text(
                'Weight: ${weightage.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            if (cycle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Cycle: $cycle',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
            if (dateRangeStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dateRangeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progress',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          backgroundColor: AppColors.divider,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showGoalDetailsSheet(context, goal),
                    icon: const Icon(Icons.visibility_rounded, size: 16),
                    label: Text(
                      'View Details',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
                if (status == 'approved' ||
                    (status == 'completed' && progress < 100)) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showUpdateProgressSheet(context, goal),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: Text(
                        'Update Progress',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
                if (status == 'approved' && progress >= 100) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await _performanceService.completeGoal(
                            goal['_id']?.toString() ?? '',
                          );
                          if (mounted) {
                            SnackBarUtils.showSnackBar(
                              context,
                              'Goal completed successfully',
                            );
                            _fetchGoals();
                          }
                        } catch (e) {
                          if (mounted) {
                            SnackBarUtils.showSnackBar(
                              context,
                              'Failed: ${e.toString().replaceAll('Exception: ', '')}',
                              isError: true,
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text(
                        'Complete Goal',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateGoalSheet extends StatefulWidget {
  final List<dynamic> cycles;
  final List<dynamic> kras;
  final VoidCallback onCreated;
  final VoidCallback onCancel;

  const _CreateGoalSheet({
    required this.cycles,
    required this.kras,
    required this.onCreated,
    required this.onCancel,
  });

  @override
  State<_CreateGoalSheet> createState() => _CreateGoalSheetState();
}

class _CreateGoalSheetState extends State<_CreateGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _typeController = TextEditingController();
  final _kpiController = TextEditingController();
  final _targetController = TextEditingController();
  late final TextEditingController _weightageController;
  String? _selectedCycle;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedKraId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _weightageController = TextEditingController(text: '10');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _typeController.dispose();
    _kpiController.dispose();
    _targetController.dispose();
    _weightageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCycle == null || _selectedCycle!.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Please select a review cycle',
        isError: true,
      );
      return;
    }
    if (_startDate == null || _endDate == null) {
      SnackBarUtils.showSnackBar(
        context,
        'Please select start and end dates',
        isError: true,
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await PerformanceService().createGoal(
        title: _titleController.text.trim(),
        type: _typeController.text.trim(),
        kpi: _kpiController.text.trim(),
        target: _targetController.text.trim(),
        weightage: int.tryParse(_weightageController.text) ?? 10,
        startDate: _startDate!.toIso8601String(),
        endDate: _endDate!.toIso8601String(),
        cycle: _selectedCycle!,
        kraId: _selectedKraId,
      );
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Goal submitted for approval',
        );
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.toUserFriendlyMessage(e),
          isError: true,
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_back_rounded,
                        size: 22,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Add New goal',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    24 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  children: [
                    Text(
                      'Set Your Next Milestone',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Define clear, actionable goals to track your professional evolution.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildFormDropdown(
                      label: 'Review Cycle *',
                      value: _selectedCycle,
                      hint: widget.cycles.isEmpty
                          ? 'No cycles available'
                          : 'Select cycle',
                      icon: Icons.assignment_rounded,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Select cycle'),
                        ),
                        ...widget.cycles
                            .where(
                              (c) => (c['name'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty,
                            )
                            .map(
                              (c) => DropdownMenuItem<String?>(
                                value: c['name']?.toString().trim() ?? '',
                                child: Text(
                                  c['name']?.toString() ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                      ],
                      onChanged: (v) => setState(() => _selectedCycle = v),
                    ),
                    const SizedBox(height: 14),
                    _buildFormField(
                      controller: _titleController,
                      label: 'Goal Title *',
                      hint: 'Enter goal title',
                      icon: Icons.flag_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),
                    _buildFormField(
                      controller: _typeController,
                      label: 'Goal Type *',
                      hint: 'e.g., Code Quality, Revenue, etc.',
                      icon: Icons.category_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),
                    _buildFormField(
                      controller: _kpiController,
                      label: 'KPI *',
                      hint: 'e.g., Code Review Score, Revenue',
                      icon: Icons.analytics_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),
                    _buildFormField(
                      controller: _targetController,
                      label: 'Target *',
                      hint: 'e.g., 4.5/5, ₹50K, 95%',
                      icon: Icons.track_changes_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),
                    _buildFormField(
                      controller: _weightageController,
                      label: 'Weightage (%)',
                      hint: '10',
                      icon: Icons.percent_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                    _fieldCard(
                      'Target Date',
                      Row(
                        children: [
                          Expanded(
                            child: _buildDateBox(
                              hint: 'Start date',
                              value: _startDate,
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (d != null) setState(() => _startDate = d);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDateBox(
                              hint: 'End date',
                              value: _endDate,
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _endDate ?? _startDate ?? DateTime.now(),
                                  firstDate: _startDate ?? DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (d != null) setState(() => _endDate = d);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                   // const SizedBox(height: 14),
                    // _fieldCard(
                    //   'Link to KRA (Optional)',
                    //   DropdownButtonFormField<String>(
                    //     initialValue: _selectedKraId,
                    //     isExpanded: true,
                    //     decoration: _filledInput('None - Don\'t link to KRA'),
                    //     items: [
                    //       const DropdownMenuItem<String>(
                    //         value: null,
                    //         child: Text('None - Don\'t link to KRA'),
                    //       ),
                    //       ...widget.kras.map((k) {
                    //         final id = k['_id']?.toString() ?? '';
                    //         final title = k['title'] ?? '';
                    //         final kpi = k['kpi'] ?? '';
                    //         final timeframe = k['timeframe'] ?? '';
                    //         return DropdownMenuItem<String>(
                    //           value: id,
                    //           child: Text(
                    //             '$title - $kpi ($timeframe)',
                    //             overflow: TextOverflow.ellipsis,
                    //           ),
                    //         );
                    //       }),
                    //     ],
                    //     onChanged: (v) => setState(() => _selectedKraId = v),
                    //   ),
                    // ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox.shrink()
                            : const Icon(Icons.task_alt_rounded, size: 20),
                        label: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create Goal'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
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

  /// White card wrapper with an orange uppercase section label (Figma style).
  Widget _fieldCard(String label, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  /// Borderless filled input (light grey) used inside [_fieldCard].
  InputDecoration _filledInput(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textCaption, fontSize: 14),
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildDateBox({
    required String hint,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value != null
                    ? DateFormat('MM/dd/yyyy').format(value)
                    : hint,
                style: TextStyle(
                  color: value != null
                      ? AppColors.textPrimary
                      : AppColors.textCaption,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return _fieldCard(
      label,
      TextFormField(
        controller: controller,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        decoration: _filledInput(hint),
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFormDropdown({
    required String label,
    required String? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<String?>> items,
    required void Function(String?) onChanged,
  }) {
    return _fieldCard(
      label,
      DropdownButtonFormField<String?>(
        initialValue: (value == null || value.isEmpty) ? null : value,
        isExpanded: true,
        decoration: _filledInput(hint),
        hint: Text(
          hint,
          style: TextStyle(color: AppColors.textCaption, fontSize: 14),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _UpdateProgressSheet extends StatefulWidget {
  final Map<String, dynamic> goal;
  final VoidCallback onUpdated;
  final VoidCallback onCancel;

  const _UpdateProgressSheet({
    required this.goal,
    required this.onUpdated,
    required this.onCancel,
  });

  @override
  State<_UpdateProgressSheet> createState() => _UpdateProgressSheetState();
}

class _UpdateProgressSheetState extends State<_UpdateProgressSheet> {
  late int _progress;
  late TextEditingController _achievementsController;
  late TextEditingController _challengesController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _progress = ((widget.goal['progress'] ?? 0) as num).toInt().clamp(0, 100);
    _achievementsController = TextEditingController(
      text: (widget.goal['achievements'] ?? '').toString(),
    );
    _challengesController = TextEditingController(
      text: (widget.goal['challenges'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _achievementsController.dispose();
    _challengesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await PerformanceService().updateGoalProgress(
        widget.goal['_id']?.toString() ?? '',
        progress: _progress,
        achievements: _achievementsController.text.trim().isEmpty
            ? null
            : _achievementsController.text.trim(),
        challenges: _challengesController.text.trim().isEmpty
            ? null
            : _challengesController.text.trim(),
      );
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Progress updated successfully',
        );
        widget.onUpdated();
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.toUserFriendlyMessage(e),
          isError: true,
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Update Progress: ${widget.goal['title'] ?? 'Goal'}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text(
                    'Progress (%) *',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: _progress.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$_progress%',
                    onChanged: (v) => setState(() => _progress = v.round()),
                  ),
                  Text(
                    '$_progress%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _achievementsController,
                    decoration: const InputDecoration(
                      labelText: 'Achievements',
                      hintText: 'Describe your achievements...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _challengesController,
                    decoration: const InputDecoration(
                      labelText: 'Challenges',
                      hintText: 'Describe any challenges faced...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _isSubmitting ? null : widget.onCancel,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text('Cancel'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Update Progress',
                                    overflow: TextOverflow.ellipsis,
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
        ),
      ),
    );
  }
}

class _GoalDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> goal;
  final Color statusColor;
  final String Function(String) formatStatus;
  final VoidCallback onClose;

  const _GoalDetailsSheet({
    required this.goal,
    required this.statusColor,
    required this.formatStatus,
    required this.onClose,
  });

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    return d != null ? DateFormat('MMM dd, yyyy').format(d) : '';
  }

  @override
  Widget build(BuildContext context) {
    final status = (goal['status'] ?? '').toString();
    final title = (goal['title'] ?? 'Goal').toString();
    final type = (goal['type'] ?? '').toString();
    final kpi = (goal['kpi'] ?? '').toString();
    final target = (goal['target'] ?? '').toString();
    final weightage = (goal['weightage'] ?? 0) as num;
    final progress = ((goal['progress'] ?? 0) as num).toDouble().clamp(
      0.0,
      100.0,
    );
    final cycle = (goal['cycle'] ?? '').toString();
    final achievements = (goal['achievements'] ?? '').toString();
    final challenges = (goal['challenges'] ?? '').toString();
    final startStr = _formatDate(goal['startDate']?.toString());
    final endStr = _formatDate(goal['endDate']?.toString());
    final dateRange = (startStr.isNotEmpty && endStr.isNotEmpty)
        ? '$startStr - $endStr'
        : '';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Goal Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      formatStatus(status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _detailRow('Type', type),
                  _detailRow('KPI', kpi),
                  _detailRow('Target', target),
                  if (weightage > 0)
                    _detailRow('Weightage', '${weightage.toStringAsFixed(0)}%'),
                  _detailRow('Cycle', cycle),
                  if (dateRange.isNotEmpty) _detailRow('Duration', dateRange),
                  const SizedBox(height: 16),
                  Text(
                    'Progress',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      backgroundColor: AppColors.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${progress.toStringAsFixed(0)}% complete',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (achievements.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _detailBlock('Achievements', achievements),
                  ],
                  if (challenges.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _detailBlock('Challenges', challenges),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
