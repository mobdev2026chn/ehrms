// hrms/lib/screens/lms_admin/lms_admin_live_sessions_screen.dart
// Admin → Live Sessions. Stats + Scheduled/Ended toggle + session rows.

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../utils/snackbar_utils.dart';
import '../../services/lms_admin_service.dart';
import '../../widgets/app_tab_loader.dart';
import 'lms_admin_utils.dart';
import 'widgets/lms_admin_stat_card.dart';

class LmsAdminLiveSessionsScreen extends StatefulWidget {
  const LmsAdminLiveSessionsScreen({super.key});

  @override
  State<LmsAdminLiveSessionsScreen> createState() =>
      _LmsAdminLiveSessionsScreenState();
}

class _LmsAdminLiveSessionsScreenState
    extends State<LmsAdminLiveSessionsScreen> {
  final LmsAdminService _service = LmsAdminService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _sessions = [];
  bool _showEnded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final res = await _service.getSessions();
    if (!mounted) return;
    setState(() {
      _sessions = LmsAdminUtils.asMapList(res['data'], ['sessions', 'data']);
      _isLoading = false;
    });
  }

  /// LiveSession.status ∈ {Scheduled, Live, Completed, Cancelled}. We surface
  /// 'Live' as "Live Now" to match the web wording.
  String _status(Map<String, dynamic> m) {
    final s = (m['status'] ?? '').toString();
    if (s.toLowerCase() == 'live') return 'Live Now';
    return s.isEmpty ? 'Scheduled' : s;
  }

  bool _isEnded(Map<String, dynamic> m) {
    final s = (m['status'] ?? '').toString().toLowerCase();
    return s == 'completed' || s.contains('ended');
  }

  int get _scheduledCount => _sessions.where((m) => !_isEnded(m)).length;
  int get _liveCount => _sessions
      .where((m) => (m['status'] ?? '').toString().toLowerCase() == 'live')
      .length;
  int get _endedCount => _sessions.where(_isEnded).length;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: AppTabLoader());
    final list =
        _sessions.where((m) => _showEnded ? _isEnded(m) : !_isEnded(m)).toList();

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
                    'Live Sessions',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => SnackBarUtils.showSnackBar(
                    context,
                    'Scheduling sessions is managed from the web admin console.',
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Schedule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          LmsAdminStatRow(
            cards: [
              LmsAdminStatCard(
                label: 'Total Sessions',
                value: '${_sessions.length}',
                icon: Icons.list_alt_rounded,
                iconColor: AppColors.info,
                iconBg: AppColors.infoBg,
              ),
              LmsAdminStatCard(
                label: 'Scheduled',
                value: '$_scheduledCount',
                icon: Icons.event_rounded,
                iconColor: AppColors.success,
                iconBg: AppColors.successBg,
              ),
              LmsAdminStatCard(
                label: 'Live Now',
                value: '$_liveCount',
                icon: Icons.play_circle_fill_rounded,
              ),
              LmsAdminStatCard(
                label: 'Ended',
                value: '$_endedCount',
                icon: Icons.check_circle_rounded,
                iconColor: AppColors.indigo,
                iconBg: AppColors.indigoBg,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Scheduled / Ended toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _toggle('Scheduled', !_showEnded, () => setState(() => _showEnded = false)),
                const SizedBox(width: 8),
                _toggle('Ended', _showEnded, () => setState(() => _showEnded = true)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            LmsAdminUtils.emptyState(
              _showEnded ? 'No ended sessions.' : 'No scheduled sessions.',
            )
          else
            ...list.map((m) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _SessionCard(session: m, status: _status(m)),
                )),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final String status;
  const _SessionCard({required this.session, required this.status});

  @override
  Widget build(BuildContext context) {
    // Field names per LiveSession model: title, category(=type), dateTime,
    // duration(min), trainerName / trainerId{name}.
    final title = (session['title'] ?? 'Session').toString();
    final type = (session['category'] ?? session['type'] ?? 'Session').toString();
    final sessionAt = LmsAdminUtils.fmtDate(
      session['dateTime'] ?? session['sessionAt'] ?? session['scheduledAt'],
      pattern: 'dd MMM yyyy · hh:mm a',
    );
    final duration = LmsAdminUtils.toInt(session['duration']);
    final trainer = session['trainerId'];
    final hostName = (session['trainerName'] ??
            (trainer is Map ? trainer['name'] : null) ??
            'Admin')
        .toString();

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
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.indigoBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              type,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.indigo,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _row(Icons.schedule, sessionAt),
          const SizedBox(height: 4),
          _row(Icons.timer_outlined, '$duration min'),
          const SizedBox(height: 4),
          _row(Icons.person_outline, hostName),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textCaption),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
