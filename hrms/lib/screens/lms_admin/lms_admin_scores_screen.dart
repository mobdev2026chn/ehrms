// hrms/lib/screens/lms_admin/lms_admin_scores_screen.dart
// Admin → Scores & Analytics. Overview stats + Course Performance.
//
// This backend exposes only per-user analytics (lmsController.getMyScores →
// { summary, courses, quizStats }); there is no admin-aggregate route here, so
// the figures reflect the signed-in user's learning data.

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/lms_admin_service.dart';
import '../../widgets/app_tab_loader.dart';
import 'lms_admin_utils.dart';
import 'widgets/lms_admin_stat_card.dart';

class LmsAdminScoresScreen extends StatefulWidget {
  const LmsAdminScoresScreen({super.key});

  @override
  State<LmsAdminScoresScreen> createState() => _LmsAdminScoresScreenState();
}

class _LmsAdminScoresScreenState extends State<LmsAdminScoresScreen> {
  final LmsAdminService _service = LmsAdminService();

  bool _isLoading = true;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _courses = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final res = await _service.getMyScores();
    if (!mounted) return;
    final data = res['data'];
    setState(() {
      if (data is Map) {
        _summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'])
            : {};
        _courses = LmsAdminUtils.asMapList(data['courses'], const []);
      } else {
        _summary = {};
        _courses = [];
      }
      _isLoading = false;
    });
  }

  int _i(String key) => LmsAdminUtils.toInt(_summary[key]);

  String get _totalEnrollments => '${_i('totalCourses')}';

  String get _completionRate {
    final total = _i('totalCourses');
    if (total == 0) return '0%';
    return '${((_i('completedCourses') / total) * 100).toStringAsFixed(0)}%';
  }

  String get _avgAssessment => '${_i('overallScore')}%';

  String get _passRate {
    final passed = _i('passedAssessments');
    final failed = _i('failedAssessments');
    final total = passed + failed;
    if (total == 0) return '0%';
    return '${((passed / total) * 100).toStringAsFixed(0)}%';
  }

  List<Map<String, dynamic>> get _filteredCourses {
    if (_search.isEmpty) return _courses;
    final q = _search.toLowerCase();
    return _courses.where((c) {
      final t = (c['title'] ?? '').toString().toLowerCase();
      final cat = (c['category'] ?? '').toString().toLowerCase();
      return t.contains(q) || cat.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: AppTabLoader());
    final courses = _filteredCourses;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Scores & Analytics',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          LmsAdminStatRow(
            cards: [
              LmsAdminStatCard(
                label: 'Total Enrollments',
                value: _totalEnrollments,
                icon: Icons.people_alt_rounded,
                iconColor: AppColors.info,
                iconBg: AppColors.infoBg,
              ),
              LmsAdminStatCard(
                label: 'Completion Rate',
                value: _completionRate,
                icon: Icons.check_circle_rounded,
                iconColor: AppColors.success,
                iconBg: AppColors.successBg,
              ),
              LmsAdminStatCard(
                label: 'Avg Assessment Score',
                value: _avgAssessment,
                icon: Icons.emoji_events_rounded,
              ),
              LmsAdminStatCard(
                label: 'Pass Rate',
                value: _passRate,
                icon: Icons.workspace_premium_rounded,
                iconColor: AppColors.indigo,
                iconBg: AppColors.indigoBg,
              ),
              LmsAdminStatCard(
                label: 'In Progress',
                value: '${_i('inProgress')}',
                icon: Icons.timelapse_rounded,
                iconColor: AppColors.warning,
                iconBg: AppColors.warningBg,
              ),
              LmsAdminStatCard(
                label: 'Passed',
                value: '${_i('passedAssessments')}',
                icon: Icons.verified_rounded,
                iconColor: AppColors.success,
                iconBg: AppColors.successBg,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Score distribution summary (mirrors web empty/summary card)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Score Distribution',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: AppColors.textHint),
                        const SizedBox(height: 10),
                        Text(
                          _i('totalCourses') == 0
                              ? 'No score data yet'
                              : 'Overall score: $_avgAssessment · '
                                  '${_i('completedCourses')}/${_i('totalCourses')} completed',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Course Performance',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LmsAdminUtils.searchField(
              hint: 'Search by course or category...',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 12),
          if (courses.isEmpty)
            LmsAdminUtils.emptyState('No course performance data.')
          else
            ...courses.map((c) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _CoursePerfCard(
                    title: (c['title'] ?? 'Course').toString(),
                    category: (c['category'] ?? '—').toString(),
                    status: (c['status'] ?? '').toString(),
                    progress: LmsAdminUtils.toDouble(c['progress']),
                    score: c['assessmentScore'] == null
                        ? null
                        : LmsAdminUtils.toDouble(c['assessmentScore']),
                  ),
                )),
        ],
      ),
    );
  }
}

class _CoursePerfCard extends StatelessWidget {
  final String title;
  final String category;
  final String status;
  final double progress;
  final double? score;

  const _CoursePerfCard({
    required this.title,
    required this.category,
    required this.status,
    required this.progress,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final pct = progress.clamp(0, 100).toDouble();
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category,
                      style: const TextStyle(fontSize: 11, color: AppColors.textCaption),
                    ),
                  ],
                ),
              ),
              if (status.isNotEmpty) LmsAdminUtils.statusPill(status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 7,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation(
                      pct >= 100 ? AppColors.success : AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (score != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.emoji_events_outlined,
                    size: 14, color: AppColors.textCaption),
                const SizedBox(width: 4),
                Text(
                  '${score!.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
