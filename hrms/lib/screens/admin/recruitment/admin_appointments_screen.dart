// lib/screens/admin/recruitment/admin_appointments_screen.dart
// Appointments: every scheduled interview round (GET /interview-rounds) by date, with
// re-schedule, scorecard, Meet link, invite re-send and the Google Calendar connection.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_candidate_scorecard_screen.dart';
import 'admin_schedule_interview_sheet.dart';
import 'rec_widgets.dart';

const Map<String, String> _dateFilters = {
  'today': 'Today',
  'week': 'Next 7 days',
  'upcoming': 'Upcoming',
  'past': 'Past',
  'all': 'All',
};

class AdminAppointmentsScreen extends StatefulWidget {
  const AdminAppointmentsScreen({super.key});

  @override
  State<AdminAppointmentsScreen> createState() => _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState extends State<AdminAppointmentsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  List<RecInterviewRound> _rounds = [];
  RecGoogleCalendarStatus? _gcal;
  String? _gcalError;

  String _dateFilter = 'today';
  String? _pickedDate;
  String _status = 'All';
  String _mode = 'All';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    _loadCalendar();
    try {
      final rounds = await _service.getInterviewRounds();
      if (!mounted) return;
      setState(() {
        _rounds = rounds;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadCalendar() async {
    try {
      final s = await _service.getGoogleCalendarStatus();
      if (!mounted) return;
      setState(() {
        _gcal = s;
        _gcalError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _gcalError = e.toString());
    }
  }

  bool _inRange(RecInterviewRound r) {
    final today = recTodayKey();
    final d = r.interviewDate;
    if (_pickedDate != null) return d == _pickedDate;
    switch (_dateFilter) {
      case 'today':
        return d == today;
      case 'week':
        final end = recDateKeyOf(DateTime.now().add(const Duration(days: 7)));
        return d.compareTo(today) >= 0 && d.compareTo(end) <= 0;
      case 'upcoming':
        return d.compareTo(today) >= 0;
      case 'past':
        return d.compareTo(today) < 0;
      default:
        return true;
    }
  }

  Future<void> _connectGoogle() async {
    try {
      final url = await _service.getGoogleCalendarConnectUrl();
      if (!mounted) return;
      await recOpenUrl(context, url);
      if (mounted) recShowSuccess(context, 'Finish connecting in the browser, then refresh this page');
    } catch (e) {
      if (mounted) recShowError(context, e);
    }
  }

  Future<void> _disconnectGoogle() async {
    final ok = await recConfirm(context,
        title: 'Disconnect Google account?',
        message: 'New virtual interviews will no longer get a Google Meet link or calendar event.',
        confirmLabel: 'Disconnect',
        destructive: true);
    if (!ok) return;
    try {
      final msg = await _service.disconnectGoogleCalendar();
      if (!mounted) return;
      recShowSuccess(context, msg);
      _loadCalendar();
    } catch (e) {
      if (mounted) recShowError(context, e);
    }
  }

  Future<void> _actions(RecInterviewRound r) async {
    final scheduled = r.status == 'Scheduled' && !r.candidateWithdrawn;
    final a = await recShowActions(context, title: '${r.candidateName} - Round ${r.roundNumber}', actions: [
      const RecAction('scorecard', 'Open scorecard', Icons.fact_check_outlined),
      if (scheduled) const RecAction('reschedule', 'Re-schedule', Icons.event_repeat_rounded),
      if (r.meetLink.isNotEmpty) const RecAction('meet', 'Join Google Meet', Icons.video_call_outlined),
      if (scheduled) const RecAction('invite', 'Send invite again', Icons.send_outlined),
    ]);
    if (!mounted || a == null) return;
    switch (a) {
      case 'scorecard':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminCandidateScorecardScreen(roundId: r.id)));
        _load(showLoader: false);
        break;
      case 'reschedule':
        if (await showRescheduleInterviewSheet(context, round: r)) _load(showLoader: false);
        break;
      case 'meet':
        recOpenUrl(context, r.meetLink);
        break;
      case 'invite':
        try {
          final msg = await _service.syncRoundCalendar(r.id);
          if (!mounted) return;
          recShowSuccess(context, msg);
          _load(showLoader: false);
        } catch (e) {
          if (mounted) recShowError(context, e);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = recTodayKey();
    final weekEnd = recDateKeyOf(DateTime.now().add(const Duration(days: 7)));
    final q = _search.toLowerCase();
    final visible = _rounds.where((r) {
      if (!_inRange(r)) return false;
      if (_status != 'All' && r.displayStatus != _status) return false;
      if (_mode != 'All' && r.mode != _mode) return false;
      return q.isEmpty ||
          r.candidateName.toLowerCase().contains(q) ||
          r.position.toLowerCase().contains(q) ||
          r.interviewerName.toLowerCase().contains(q) ||
          r.roundName.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => '${a.interviewDate}T${a.interviewTime}'.compareTo('${b.interviewDate}T${b.interviewTime}'));

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kRecBg,
      drawer: const AppDrawer(),
      appBar: recAppBar(context, 'Appointments', drawerKey: _scaffoldKey, onRefresh: () => _load()),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: false,
        onRetry: _load,
        builder: () => RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _calendarCard(),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.15,
                children: [
                  RecStatTile(label: 'Today', value: '${_rounds.where((r) => r.interviewDate == today).length}', icon: Icons.today_rounded),
                  RecStatTile(
                      label: 'Next 7 days',
                      value: '${_rounds.where((r) => r.interviewDate.compareTo(today) >= 0 && r.interviewDate.compareTo(weekEnd) <= 0).length}',
                      icon: Icons.date_range_rounded,
                      color: AppColors.info),
                  RecStatTile(
                      label: 'Awaiting evaluation',
                      value: '${_rounds.where((r) => r.status == 'Scheduled').length}',
                      icon: Icons.pending_actions_rounded,
                      color: AppColors.brandDark),
                  RecStatTile(
                      label: 'Evaluated',
                      value: '${_rounds.where((r) => r.status == 'Evaluated').length}',
                      icon: Icons.task_alt_rounded,
                      color: AppColors.success),
                ],
              ),
              const SizedBox(height: 12),
              RecSearchField(hint: 'Search candidate, position, round or evaluator', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: RecFilterChips(
                    options: _dateFilters.keys.toList(),
                    selected: _pickedDate == null ? _dateFilter : '',
                    labelOf: (k) => _dateFilters[k]!,
                    onSelected: (k) => setState(() {
                      _dateFilter = k;
                      _pickedDate = null;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'Pick a date',
                  icon: Icon(Icons.calendar_month_outlined, color: _pickedDate != null ? AppColors.primaryText : kRecMuted),
                  onPressed: () async {
                    final d = await recPickDate(context, initial: _pickedDate ?? today);
                    if (d != null) setState(() => _pickedDate = d);
                  },
                ),
              ]),
              if (_pickedDate != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InputChip(
                    avatar: const Icon(Icons.event_outlined, size: 18, color: AppColors.brandDark),
                    label: Text(recFormatDate(_pickedDate)),
                    onDeleted: () => setState(() => _pickedDate = null),
                  ),
                ),
              const SizedBox(height: 8),
              RecFilterChips(
                options: const ['All', 'Scheduled', 'Passed', 'Selected', 'On Hold', 'Reassigned', 'Rejected'],
                selected: _status,
                labelOf: (s) => s == 'All' ? 'All statuses' : s,
                onSelected: (s) => setState(() => _status = s),
              ),
              const SizedBox(height: 8),
              RecFilterChips(
                options: const ['All', ...kInterviewModes],
                selected: _mode,
                labelOf: (s) => s == 'All' ? 'All modes' : s,
                onSelected: (s) => setState(() => _mode = s),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: RecEmptyState(text: 'No interviews for this selection', icon: Icons.event_busy_outlined),
                )
              else
                ...visible.map(_card),
            ],
          ),
        ),
      ),
    );
  }

  Widget _calendarCard() {
    final s = _gcal;
    String text;
    Color color;
    if (_gcalError != null) {
      text = 'Google Calendar status unavailable';
      color = kRecMuted;
    } else if (s == null) {
      text = 'Checking Google Calendar…';
      color = kRecMuted;
    } else if (!s.configured) {
      text = 'Google Meet is not set up for your company (Integrations).';
      color = kRecMuted;
    } else if (s.needsReconnect) {
      text = 'Google revoked access - connect the account again.';
      color = AppColors.error;
    } else if (s.connected) {
      text = 'Connected as ${s.googleEmail}. Virtual interviews get a Google Meet link.';
      color = AppColors.success;
    } else {
      text = 'Not connected - virtual interviews will not get a Meet link.';
      color = AppColors.brandDark;
    }
    return RecCard(
      margin: EdgeInsets.zero,
      child: Row(children: [
        RecIconTile(Icons.video_camera_front_outlined, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color))),
        if (s != null && s.configured)
          TextButton(
            onPressed: s.connected && !s.needsReconnect ? _disconnectGoogle : _connectGoogle,
            child: Text(s.connected && !s.needsReconnect ? 'Disconnect' : 'Connect'),
          ),
      ]),
    );
  }

  Widget _card(RecInterviewRound r) {
    return RecCard(
      onTap: () => _actions(r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(recFormatDate(r.interviewDate).split(' ').first,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kRecInk, height: 1.1)),
              const SizedBox(height: 2),
              Text(recFormatDate(r.interviewDate).split(' ').skip(1).join(' '),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandDark)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(r.candidateName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                  ),
                  const SizedBox(width: 8),
                  RecBadge(r.displayStatus),
                ]),
                const SizedBox(height: 2),
                Text(r.position, style: const TextStyle(fontSize: 13, color: kRecMuted, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text('Round ${r.roundNumber}: ${r.roundName}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kRecInk)),
                const SizedBox(height: 2),
                Text('${recFormatTime(r.interviewTime)} • ${r.duration} • ${r.mode} • ${r.interviewerName}',
                    style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                if (r.calendarSyncStatus == 'Failed')
                  Text('Calendar: ${r.calendarSyncError}', style: const TextStyle(fontSize: 12, color: AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
