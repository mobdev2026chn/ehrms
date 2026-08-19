// hrms/lib/screens/lms_admin/lms_admin_assessment_screen.dart
// Admin → Assessment Management. Stats + Requests/Upcoming/Completed sub-tabs.

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/lms_admin_service.dart';
import '../../widgets/app_tab_loader.dart';
import 'lms_admin_utils.dart';
import 'widgets/lms_admin_stat_card.dart';

class LmsAdminAssessmentScreen extends StatefulWidget {
  const LmsAdminAssessmentScreen({super.key});

  @override
  State<LmsAdminAssessmentScreen> createState() =>
      _LmsAdminAssessmentScreenState();
}

class _LmsAdminAssessmentScreenState extends State<LmsAdminAssessmentScreen> {
  final LmsAdminService _service = LmsAdminService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _all = [];
  int _tab = 0; // 0 Requests, 1 Upcoming, 2 Completed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    // No admin assessment route on this backend — derive from the user's
    // course assessment statuses (lmsController.getMyScores → data.courses).
    final res = await _service.getMyScores();
    if (!mounted) return;
    final data = res['data'];
    setState(() {
      _all = data is Map
          ? LmsAdminUtils.asMapList(data['courses'], const [])
          : <Map<String, dynamic>>[];
      _isLoading = false;
    });
  }

  String _status(Map<String, dynamic> m) =>
      (m['assessmentStatus'] ?? m['status'] ?? '').toString().toLowerCase();

  List<Map<String, dynamic>> get _requests => _all
      .where((m) =>
          _status(m).contains('not started') ||
          _status(m).contains('pending') ||
          _status(m).isEmpty)
      .toList();
  List<Map<String, dynamic>> get _upcoming => _all
      .where((m) => _status(m).contains('progress') || _status(m).contains('schedul'))
      .toList();
  List<Map<String, dynamic>> get _completed => _all
      .where((m) =>
          _status(m).contains('complet') ||
          _status(m).contains('pass') ||
          _status(m).contains('fail'))
      .toList();

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: AppTabLoader());

    final current = _tab == 0
        ? _requests
        : _tab == 1
            ? _upcoming
            : _completed;
    final emptyMsg = _tab == 0
        ? 'No assessment requests. Schedule a request to move it to Upcoming.'
        : _tab == 1
            ? 'No upcoming assessments.'
            : 'No completed assessments yet.';

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
                    'Assessment Management',
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
          LmsAdminStatRow(
            cards: [
              LmsAdminStatCard(
                label: 'Total Requests',
                value: '${_all.length}',
                icon: Icons.list_alt_rounded,
                iconColor: AppColors.info,
                iconBg: AppColors.infoBg,
              ),
              LmsAdminStatCard(
                label: 'Pending',
                value: '${_requests.length}',
                icon: Icons.edit_note_rounded,
              ),
              LmsAdminStatCard(
                label: 'Upcoming',
                value: '${_upcoming.length}',
                icon: Icons.schedule_rounded,
                iconColor: AppColors.success,
                iconBg: AppColors.successBg,
              ),
              LmsAdminStatCard(
                label: 'Completed',
                value: '${_completed.length}',
                icon: Icons.verified_rounded,
                iconColor: AppColors.indigo,
                iconBg: AppColors.indigoBg,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _tabChip('Assessment Requests', 0),
                _tabChip('Upcoming Assessments', 1),
                _tabChip('Completed', 2),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (current.isEmpty)
            LmsAdminUtils.emptyState(emptyMsg)
          else
            ...current.map((m) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _AssessmentCard(item: m),
                )),
        ],
      ),
    );
  }

  Widget _tabChip(String label, int index) {
    final active = _tab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AssessmentCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final title = (item['title'] ?? item['courseTitle'] ?? 'Assessment').toString();
    final category = (item['category'] ?? '').toString();
    final status = (item['assessmentStatus'] ?? item['status'] ?? '').toString();
    final score = item['assessmentScore'];
    final scoreText = score == null ? null : '${LmsAdminUtils.toInt(score)}%';

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
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              LmsAdminUtils.statusPill(status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.category_outlined, size: 14, color: AppColors.textCaption),
              const SizedBox(width: 6),
              Text(category.isEmpty ? '—' : category,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              if (scoreText != null) ...[
                const Spacer(),
                const Icon(Icons.emoji_events_outlined,
                    size: 13, color: AppColors.textCaption),
                const SizedBox(width: 6),
                Text('Score: $scoreText',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
