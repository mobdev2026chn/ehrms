// hrms/lib/screens/lms/lms_live_sessions_screen.dart
// My Live Sessions - mirrors web /lms/employee/live-sessions
// Tabs: Upcoming, Ended. Schedule Session modal.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_colors.dart';
import '../../services/lms_service.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../dashboard/dashboard_screen.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import '../../utils/snackbar_utils.dart' show SnackBarUtils;
import '../../utils/error_message_utils.dart';
import '../../widgets/app_tab_loader.dart';

class LmsLiveSessionsScreen extends StatefulWidget {
  /// When true, rendered inside LmsShellScreen (no Scaffold, app bar, drawer).
  final bool embeddedInShell;

  const LmsLiveSessionsScreen({super.key, this.embeddedInShell = false});

  @override
  State<LmsLiveSessionsScreen> createState() => _LmsLiveSessionsScreenState();
}

class _LmsLiveSessionsScreenState extends State<LmsLiveSessionsScreen>
    with SingleTickerProviderStateMixin {
  final LmsService _lmsService = LmsService();
  late TabController _tabController;

  List<dynamic> _sessions = [];
  bool _isLoading = true;
  List<dynamic> _departments = [];
  List<dynamic> _employees = [];

  /// Staff ID for creator check (trainerId in session is Staff id).
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCurrentUser();
    _loadSessions();
    _loadMeta();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final staffStr = prefs.getString('staff');
      if (staffStr != null) {
        final staff = jsonDecode(staffStr) as Map<String, dynamic>?;
        final staffId = staff?['_id']?.toString();
        if (mounted) setState(() => _currentUserId = staffId);
        return;
      }
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final user = jsonDecode(userStr) as Map<String, dynamic>?;
        final id = user?['_id']?.toString();
        if (mounted) setState(() => _currentUserId = id);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final res = await _lmsService.getMySessions();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _sessions = (res['data'] as List?) ?? [];
      });
    }
  }

  Future<void> _loadMeta() async {
    final deptRes = await _lmsService.getDepartments();
    final empRes = await _lmsService.getEmployees();
    if (mounted) {
      setState(() {
        _departments = (deptRes['data']?['departments'] as List?) ?? [];
        _employees = (empRes['data']?['staff'] as List?) ?? [];
      });
    }
  }

  List<dynamic> get _upcomingSessions {
    final now = DateTime.now();
    return _sessions.where((s) {
      final dt = s['dateTime'];
      if (dt == null) return false;
      final d = dt is DateTime ? dt : DateTime.tryParse(dt.toString());
      if (d == null) return false;
      final end = d.add(Duration(minutes: s['duration'] ?? 60));
      return end.isAfter(now);
    }).toList();
  }

  List<dynamic> get _endedSessions {
    final now = DateTime.now();
    return _sessions.where((s) {
      final dt = s['dateTime'];
      if (dt == null) return true;
      final d = dt is DateTime ? dt : DateTime.tryParse(dt.toString());
      if (d == null) return true;
      final end = d.add(Duration(minutes: s['duration'] ?? 60));
      return end.isBefore(now) || end.isAtSameMomentAs(now);
    }).toList();
  }

  String _getStatus(dynamic session) {
    final dt = session['dateTime'];
    if (dt == null) return 'Upcoming';
    final d = dt is DateTime ? dt : DateTime.tryParse(dt.toString());
    if (d == null) return 'Upcoming';
    final now = DateTime.now();
    final end = d.add(Duration(minutes: session['duration'] ?? 60));
    if (now.isBefore(d)) return 'Upcoming';
    if (now.isBefore(end) || now.isAtSameMomentAs(end)) return 'Live Now';
    return 'Ended';
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = TabBar(
      controller: _tabController,
      labelColor: AppColors.primary,
      unselectedLabelColor: Colors.black87,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      indicator: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      tabs: const [
        Tab(text: 'Upcoming', icon: Icon(Icons.event_outlined, size: 20)),
        Tab(text: 'Ended', icon: Icon(Icons.check_circle_outline, size: 20)),
      ],
    );

    final body = TabBarView(
      controller: _tabController,
      children: [
        _buildSessionList(_upcomingSessions),
        _buildSessionList(_endedSessions),
      ],
    );

    if (widget.embeddedInShell) {
      return Column(
        children: [
          Container(color: AppColors.surface, child: tabBar),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _loadSessions,
                ),
                ElevatedButton.icon(
                  onPressed: () => _showScheduleModal(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Schedule Session'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text(
          'My Live Sessions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadSessions,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: () => _showScheduleModal(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Schedule Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(color: AppColors.surface, child: tabBar),
        ),
      ),
      drawer: const AppDrawer(),
      body: body,
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: -1,
        onTap: (index) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => DashboardScreen(initialIndex: index),
            ),
            (route) => route.isFirst,
          );
        },
      ),
    );
  }

  Widget _buildSessionList(List<dynamic> sessions) {
    if (_isLoading) {
      return const Center(child: AppTabLoader());
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Join interactive classrooms. Tap a session to see details.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          if (sessions.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.video_call_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No sessions',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final session = sessions[index];
                final status = _getStatus(session);
                final hasLeft =
                    session['mySessionLog']?['left'] == true ||
                    session['myAttendance']?['left'] == true;
                return _SessionCard(
                  session: session,
                  status: status,
                  currentUserId: _currentUserId,
                  hasLeft: hasLeft,
                  onJoin: () => _joinSession(session),
                  onLeave: () => _showLeaveModal(context, session),
                  onEdit: () => _showScheduleModal(context, session: session),
                  onDelete: () => _deleteSession(session),
                  onStartSession: () => _updateSessionStatus(session, 'Live'),
                  onCancelSession: () =>
                      _updateSessionStatus(session, 'Cancelled'),
                  onEndSession: () =>
                      _updateSessionStatus(session, 'Completed'),
                  onWatchRecording: () => _openUrl(session['recordingUrl']),
                );
              }, childCount: sessions.length),
            ),
        ],
      ),
    );
  }

  Future<void> _openUrl(dynamic url) async {
    final s = url?.toString();
    if (s == null || s.isEmpty) return;
    final uri = Uri.tryParse(s);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _joinSession(dynamic session) async {
    final link = session['meetingLink']?.toString();
    if (link != null && link.isNotEmpty) {
      await _openUrl(link);
    }
    await _lmsService.joinSession(session['_id']);
  }

  Future<void> _updateSessionStatus(dynamic session, String status) async {
    final res = await _lmsService.updateSession(
      session['_id'],
      <String, dynamic>{'status': status},
    );
    if (mounted) {
      if (res['success'] == true) {
        SnackBarUtils.showSnackBar(
          context,
          status == 'Cancelled'
              ? 'Session cancelled'
              : status == 'Completed'
              ? 'Session ended'
              : 'Session started',
        );
        _loadSessions();
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(res['message']?.toString(), fallback: 'Failed'),
          isError: true,
        );
      }
    }
  }

  void _showLeaveModal(BuildContext context, dynamic session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _LeaveSessionSheet(
        sessionTitle: session['title'] ?? 'Session',
        onSubmit: (feedbackSummary, issues, rating) async {
          final res = await _lmsService.leaveSession(
            session['_id'],
            feedbackSummary: feedbackSummary,
            issues: issues,
            rating: rating,
          );
          if (mounted) {
            Navigator.pop(ctx);
            if (res['success'] == true) {
              SnackBarUtils.showSnackBar(
                context,
                'Session log saved. You have left the session.',
              );
              _loadSessions();
            } else {
              SnackBarUtils.showSnackBar(
                context,
                ErrorMessageUtils.sanitizeForDisplay(res['message']?.toString(), fallback: 'Failed'),
                isError: true,
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _deleteSession(dynamic session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text('Remove "${session['title']}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await _lmsService.deleteSession(session['_id']);
    if (mounted) {
      if (res['success'] == true) {
        SnackBarUtils.showSnackBar(context, 'Session deleted');
        _loadSessions();
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(res['message']?.toString(), fallback: 'Delete failed'),
          isError: true,
        );
      }
    }
  }

  void _showScheduleModal(BuildContext context, {dynamic session}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ScheduleSessionSheet(
        session: session,
        departments: _departments,
        employees: _employees,
        onSaved: () {
          Navigator.pop(ctx);
          _loadSessions();
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final dynamic session;
  final String status;
  final String? currentUserId;
  final bool hasLeft;
  final VoidCallback onJoin;
  final VoidCallback? onLeave;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onStartSession;
  final VoidCallback? onCancelSession;
  final VoidCallback? onEndSession;
  final VoidCallback? onWatchRecording;

  const _SessionCard({
    required this.session,
    required this.status,
    this.currentUserId,
    this.hasLeft = false,
    required this.onJoin,
    this.onLeave,
    required this.onEdit,
    required this.onDelete,
    this.onStartSession,
    this.onCancelSession,
    this.onEndSession,
    this.onWatchRecording,
  });

  bool get _isCreator {
    final trainerId = session['trainerId'];
    if (trainerId == null || currentUserId == null) return false;
    final id = trainerId is Map
        ? trainerId['_id']?.toString()
        : trainerId.toString();
    return id == currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    final dt = session['dateTime'];
    DateTime? d;
    if (dt != null) {
      d = dt is DateTime ? dt : DateTime.tryParse(dt.toString());
    }
    final host =
        session['trainerName'] ?? session['trainerId']?['name'] ?? 'Host';
    final isUpcoming = status == 'Upcoming';
    final isLive = status == 'Live Now';
    final isEnded = status == 'Ended';
    final recordingUrl = session['recordingUrl']?.toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session['title'] ?? 'Session',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isLive
                        ? Colors.green
                        : isUpcoming
                        ? Colors.blue
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasLeft && isLive ? 'You left' : status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_isCreator) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (d != null)
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16),
                  const SizedBox(width: 8),
                  Text(DateFormat('d MMM yyyy · h:mm a').format(d)),
                ],
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16),
                const SizedBox(width: 8),
                Text(host.toString()),
                const SizedBox(width: 16),
                Text('${session['duration'] ?? 60} min'),
              ],
            ),
            if (session['agenda']?.toString().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                'Agenda: ${session['agenda']}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isUpcoming && _isCreator) ...[
                  if (onStartSession != null)
                    ElevatedButton.icon(
                      onPressed: onStartSession,
                      icon: const Icon(Icons.play_circle_outlined, size: 18),
                      label: const Text('Start Session'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (onCancelSession != null)
                    OutlinedButton.icon(
                      onPressed: onCancelSession,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel Session'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                ],
                if (isLive && _isCreator && onEndSession != null)
                  OutlinedButton.icon(
                    onPressed: onEndSession,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('End Session'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                    ),
                  ),
                if ((isUpcoming || isLive) && (!_isCreator || isUpcoming))
                  ElevatedButton.icon(
                    onPressed: onJoin,
                    icon: const Icon(Icons.video_call, size: 18),
                    label: Text(isLive ? 'Join Now' : 'Join'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (isLive && !_isCreator && !hasLeft && onLeave != null)
                  OutlinedButton.icon(
                    onPressed: onLeave,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Leave Session'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                if (isEnded &&
                    recordingUrl != null &&
                    recordingUrl.isNotEmpty &&
                    onWatchRecording != null)
                  OutlinedButton.icon(
                    onPressed: onWatchRecording,
                    icon: const Icon(Icons.video_library_outlined, size: 18),
                    label: const Text('Watch Recording'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleSessionSheet extends StatefulWidget {
  final dynamic session;
  final List<dynamic> departments;
  final List<dynamic> employees;
  final VoidCallback onSaved;

  const _ScheduleSessionSheet({
    this.session,
    required this.departments,
    required this.employees,
    required this.onSaved,
  });

  @override
  State<_ScheduleSessionSheet> createState() => _ScheduleSessionSheetState();
}

class _ScheduleSessionSheetState extends State<_ScheduleSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _agendaController = TextEditingController();
  final _meetingLinkController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int _duration = 60;
  String _sessionType = 'Normal Session';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.session != null) {
      final s = widget.session;
      _titleController.text = s['title'] ?? '';
      _agendaController.text = s['agenda'] ?? '';
      _meetingLinkController.text = s['meetingLink'] ?? '';
      _duration = s['duration'] ?? 60;
      _sessionType = s['category'] ?? 'Normal Session';
      final dt = s['dateTime'];
      if (dt != null) {
        final d = dt is DateTime ? dt : DateTime.tryParse(dt.toString());
        if (d != null) {
          _selectedDate = d;
          _selectedTime = TimeOfDay(hour: d.hour, minute: d.minute);
        }
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _agendaController.dispose();
    _meetingLinkController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date and time')),
      );
      return;
    }

    final combined = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    setState(() => _saving = true);

    final payload = {
      'title': _titleController.text.trim(),
      'agenda': _agendaController.text.trim(),
      'meetingLink': _meetingLinkController.text.trim(),
      'dateTime': combined.toIso8601String(),
      'duration': _duration,
      'category': _sessionType,
      'assignmentType': 'All',
    };

    final lmsService = LmsService();
    Map<String, dynamic> res;
    if (widget.session != null) {
      res = await lmsService.updateSession(widget.session!['_id'], payload);
    } else {
      res = await lmsService.createSession(payload);
    }

    if (mounted) {
      setState(() => _saving = false);
      if (res['success'] == true) {
        SnackBarUtils.showSnackBar(
          context,
          widget.session != null ? 'Session updated' : 'Session scheduled',
        );
        widget.onSaved();
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(res['message']?.toString(), fallback: 'Failed'),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Schedule Live Session',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create and manage external meetings',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Session Title *',
                      hintText: 'e.g. Q3 Sales Strategy',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _sessionType,
                    decoration: const InputDecoration(
                      labelText: 'Session Type',
                      border: OutlineInputBorder(),
                    ),
                    items: ['Normal Session', 'Training', 'Assessment']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _sessionType = v ?? 'Normal Session'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _agendaController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Agenda',
                      hintText: 'e.g. 1. Intro 2. Demo 3. Q&A',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _meetingLinkController,
                    decoration: const InputDecoration(
                      labelText: 'Meeting Link *',
                      hintText: 'https://meet.google.com/...',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (date != null) {
                              setState(() => _selectedDate = date);
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            _selectedDate != null
                                ? DateFormat(
                                    'dd MMM yyyy',
                                  ).format(_selectedDate!)
                                : 'Select date',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: _selectedTime ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setState(() => _selectedTime = time);
                            }
                          },
                          icon: const Icon(Icons.access_time),
                          label: Text(
                            _selectedTime != null
                                ? _selectedTime!.format(context)
                                : 'Select time',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Duration (minutes):'),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: _duration,
                        items: [30, 60, 90, 120]
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text('$e min'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _duration = v ?? 60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Schedule Session'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LeaveSessionSheet extends StatefulWidget {
  final String sessionTitle;
  final Future<void> Function(
    String feedbackSummary,
    String? issues,
    int? rating,
  )
  onSubmit;

  const _LeaveSessionSheet({
    required this.sessionTitle,
    required this.onSubmit,
  });

  @override
  State<_LeaveSessionSheet> createState() => _LeaveSessionSheetState();
}

class _LeaveSessionSheetState extends State<_LeaveSessionSheet> {
  final _summaryController = TextEditingController();
  final _issuesController = TextEditingController();
  int? _rating;
  bool _submitting = false;

  @override
  void dispose() {
    _summaryController.dispose();
    _issuesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final summary = _summaryController.text.trim();
    if (summary.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Please enter what you learned or a brief summary.',
        isError: true,
      );
      return;
    }
    setState(() => _submitting = true);
    await widget.onSubmit(
      summary,
      _issuesController.text.trim().isEmpty
          ? null
          : _issuesController.text.trim(),
      _rating,
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.logout, size: 28, color: Colors.red[700]),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Leave Live Session',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Before leaving, please share your session feedback.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _summaryController,
                decoration: const InputDecoration(
                  labelText: 'Session Summary / What you learned *',
                  hintText: 'Summarize key takeaways...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _issuesController,
                decoration: const InputDecoration(
                  labelText: 'Issues faced (optional)',
                  hintText: 'Audio / Video / Content issues...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Text(
                'Session Rating (1–5 stars)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: Icon(
                        _rating != null && star <= _rating!
                            ? Icons.star
                            : Icons.star_border,
                        size: 32,
                        color: Colors.amber,
                      ),
                      onPressed: () => setState(
                        () => _rating = _rating == star ? null : star,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Submit & Leave'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
