// hrms/lib/screens/lms_admin/lms_admin_learners_screen.dart
// Admin → Learners Management. Search + department/status filter + paginated
// learner rows (mobile card layout instead of a wide web table).

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/lms_admin_service.dart';
import '../../widgets/app_tab_loader.dart';
import 'lms_admin_utils.dart';

class LmsAdminLearnersScreen extends StatefulWidget {
  const LmsAdminLearnersScreen({super.key});

  @override
  State<LmsAdminLearnersScreen> createState() => _LmsAdminLearnersScreenState();
}

class _LmsAdminLearnersScreenState extends State<LmsAdminLearnersScreen> {
  final LmsAdminService _service = LmsAdminService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _learners = [];
  String _search = '';
  String? _deptFilter;
  String? _statusFilter;
  int _page = 1;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final res = await _service.getLearners();
    if (!mounted) return;
    setState(() {
      // /lms/employees returns { data: { staff: [{name, email}] } }
      _learners = LmsAdminUtils.asMapList(
          res['data'], ['staff', 'learners', 'employees', 'data', 'users']);
      _isLoading = false;
      _page = 1;
    });
  }

  String _name(Map<String, dynamic> m) =>
      (m['name'] ?? m['fullName'] ?? m['staffName'] ?? 'Learner').toString();
  String _email(Map<String, dynamic> m) =>
      (m['email'] ?? m['officialEmail'] ?? '').toString();
  String _dept(Map<String, dynamic> m) {
    final d = m['department'] ?? m['departmentName'] ?? m['dept'];
    if (d is Map) return (d['name'] ?? d['departmentName'] ?? '—').toString();
    return (d ?? '—').toString();
  }

  String _status(Map<String, dynamic> m) {
    final s = (m['status'] ?? m['learningStatus'] ?? '').toString();
    if (s.isNotEmpty) return s;
    final completed = LmsAdminUtils.toInt(m['coursesCompleted'] ?? m['completed']);
    final assigned = LmsAdminUtils.toInt(m['assigned'] ?? m['coursesAssigned']);
    if (assigned == 0) return 'Not Started';
    if (completed >= assigned && assigned > 0) return 'Completed';
    return completed > 0 ? 'In Progress' : 'Not Started';
  }

  List<String> get _departments => _learners
      .map(_dept)
      .where((s) => s.isNotEmpty && s != '—')
      .toSet()
      .toList();

  List<Map<String, dynamic>> get _filtered {
    return _learners.where((m) {
      final q = _search.toLowerCase();
      final matchSearch = q.isEmpty ||
          _name(m).toLowerCase().contains(q) ||
          _email(m).toLowerCase().contains(q);
      final matchDept = _deptFilter == null || _dept(m) == _deptFilter;
      final matchStatus = _statusFilter == null || _status(m) == _statusFilter;
      return matchSearch && matchDept && matchStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: AppTabLoader());
    final filtered = _filtered;
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 9999);
    if (_page > totalPages) _page = totalPages;
    final start = (_page - 1) * _pageSize;
    final pageItems = filtered.skip(start).take(_pageSize).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Learners Management',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LmsAdminUtils.searchField(
                  hint: 'Search by name or email',
                  onChanged: (v) => setState(() {
                    _search = v;
                    _page = 1;
                  }),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LmsAdminUtils.dropdown(
                        hint: 'All Departments',
                        value: _deptFilter,
                        items: _departments,
                        onChanged: (v) => setState(() {
                          _deptFilter = v;
                          _page = 1;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LmsAdminUtils.dropdown(
                        hint: 'Status',
                        value: _statusFilter,
                        items: const ['Not Started', 'In Progress', 'Completed'],
                        onChanged: (v) => setState(() {
                          _statusFilter = v;
                          _page = 1;
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Total ${filtered.length} learner${filtered.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textCaption),
            ),
          ),
          const SizedBox(height: 8),
          if (pageItems.isEmpty)
            LmsAdminUtils.emptyState('No learners found.')
          else
            ...pageItems.map((m) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _LearnerCard(
                    name: _name(m),
                    email: _email(m),
                    dept: _dept(m),
                    assigned: LmsAdminUtils.toInt(m['assigned'] ?? m['coursesAssigned']),
                    completed:
                        LmsAdminUtils.toInt(m['coursesCompleted'] ?? m['completed']),
                    avgScore: LmsAdminUtils.toDouble(
                        m['avgQuizScore'] ?? m['avgAiQuizScore'] ?? m['avgScore']),
                    status: _status(m),
                  ),
                )),
          if (filtered.length > _pageSize) _pager(totalPages),
        ],
      ),
    );
  }

  Widget _pager(int totalPages) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 22),
            onPressed: _page > 1 ? () => setState(() => _page--) : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$_page / $totalPages',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 22),
            onPressed: _page < totalPages ? () => setState(() => _page++) : null,
          ),
        ],
      ),
    );
  }
}

class _LearnerCard extends StatelessWidget {
  final String name;
  final String email;
  final String dept;
  final int assigned;
  final int completed;
  final double avgScore;
  final String status;

  const _LearnerCard({
    required this.name,
    required this.email,
    required this.dept,
    required this.assigned,
    required this.completed,
    required this.avgScore,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textCaption,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              LmsAdminUtils.statusPill(status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric('Dept', dept),
              _metric('Assigned', '$assigned'),
              _metric('Completed', '$completed'),
              _metric('Avg Score', '${avgScore.toStringAsFixed(0)}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textCaption,
              letterSpacing: 0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
