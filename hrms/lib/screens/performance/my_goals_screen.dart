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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage your goals and track progress',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSummaryCards(),
                    const SizedBox(height: 24),
                    _buildFiltersSection(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.flag_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
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
                    const SizedBox(height: 12),
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
    return Card(
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.flag_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No goals found',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
          children: [
            _buildSummaryCard('Total', _total.toString(), Icons.flag_rounded),
            _buildSummaryCard(
              'Approved',
              _approved.toString(),
              Icons.check_circle_rounded,
            ),
            _buildSummaryCard(
              'Pending',
              _pending.toString(),
              Icons.schedule_rounded,
            ),
            _buildSummaryCard(
              'Completed',
              _completed.toString(),
              Icons.done_all_rounded,
            ),
          ],
    );
  }

  Widget _buildFiltersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filters',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
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

  Widget _buildSummaryCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                title,
                style: TextStyle(
                    fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
              ),
              ),
              Icon(icon, size: 14, color: AppColors.primary),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
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
            if (status == 'approved' ||
                (status == 'completed' && progress < 100)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showUpdateProgressSheet(context, goal),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: Text('Update Progress'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                    ),
                  ),
                  if (status == 'approved' && progress >= 100) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await _performanceService.completeGoal(
                            goal['_id']?.toString() ?? '',
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Goal completed successfully'),
                                backgroundColor: AppColors.primary,
                              ),
                            );
                            _fetchGoals();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed: ${e.toString().replaceAll('Exception: ', '')}',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text('Complete Goal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a review cycle')),
      );
      return;
    }
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end dates')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Goal submitted for approval'),
            backgroundColor: AppColors.primary,
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessageUtils.toUserFriendlyMessage(e)),
          ),
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
                  Text(
                    'Create New Goal',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'This will be submitted for manager approval.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    24 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  children: [
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
                      hint: 'e.g., 4.5/5, \$50K, 95%',
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
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _startDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) setState(() => _startDate = d);
                            },
                            child: InputDecorator(
                              decoration: _profileInputDecoration(
                                'Start Date',
                                Icons.calendar_today_rounded,
                              ),
                              child: Text(
                                _startDate != null
                                    ? DateFormat(
                                        'dd-MM-yyyy',
                                      ).format(_startDate!)
                                    : 'dd-mm-yyyy',
                                style: TextStyle(
                                  color: _startDate != null
                                      ? Colors.black87
                                      : Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
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
                            child: InputDecorator(
                              decoration: _profileInputDecoration(
                                'End Date',
                                Icons.event_rounded,
                              ),
                              child: Text(
                                _endDate != null
                                    ? DateFormat('dd-MM-yyyy').format(_endDate!)
                                    : 'dd-mm-yyyy',
                                style: TextStyle(
                                  color: _endDate != null
                                      ? Colors.black87
                                      : Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _selectedKraId,
                      decoration: _profileInputDecoration(
                        'Link to KRA (Optional)',
                        Icons.link_rounded,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('None - Don\'t link to KRA'),
                        ),
                        ...widget.kras.map((k) {
                          final id = k['_id']?.toString() ?? '';
                          final title = k['title'] ?? '';
                          final kpi = k['kpi'] ?? '';
                          final timeframe = k['timeframe'] ?? '';
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(
                              '$title - $kpi ($timeframe)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (v) => setState(() => _selectedKraId = v),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSubmitting ? null : widget.onCancel,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: AppColors.primary),
                              foregroundColor: AppColors.primary,
                            ),
                            child: Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                                : Text('Submit'),
                          ),
                        ),
                      ],
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

  InputDecoration _profileInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      decoration: _profileInputDecoration(label, icon).copyWith(hintText: hint),
      validator: validator,
      keyboardType: keyboardType,
      onChanged: onChanged,
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
    return DropdownButtonFormField<String?>(
      value: (value == null || value.isEmpty) ? null : value,
      decoration: _profileInputDecoration(label, icon),
      hint: Text(hint, style: TextStyle(color: Colors.grey.shade600)),
      items: items,
      onChanged: onChanged,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Progress updated successfully'),
            backgroundColor: AppColors.primary,
          ),
        );
        widget.onUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessageUtils.toUserFriendlyMessage(e)),
          ),
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
                        child: OutlinedButton(
                          onPressed: _isSubmitting ? null : widget.onCancel,
                          child: Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
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
                              : Text('Update Progress'),
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
