// lib/screens/admin/recruitment/admin_verifications_screen.dart
// Verification: Add Documents / Verify Documents (scope=verify), Convert to Staff
// (scope=convert) and Joining (converted candidates against their staff joining date).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_convert_to_staff_screen.dart';
import 'admin_verification_detail_screen.dart';
import 'rec_widgets.dart';

bool _isDecided(RecVerificationCandidate c) => c.verificationStage != 'pending';
bool _isSubmitted(RecVerificationCandidate c) =>
    c.documentsSubmittedAt.isNotEmpty || c.documentsSavedAt.isNotEmpty || c.documentsSkippedAt.isNotEmpty || _isDecided(c);
bool _needsDocuments(RecVerificationCandidate c) =>
    c.documentsSavedAt.isEmpty &&
    c.documentsSkippedAt.isEmpty &&
    !_isDecided(c) &&
    (c.documentsSubmittedAt.isEmpty || !c.summary.allSubmitted);

String verifyStateOf(RecVerificationCandidate c) {
  final s = c.verificationStage;
  if (s == 'verificationHold' || s == 'verificationReject' || s == 'verificationBlacklist') {
    return kVerificationStageLabels[s]!;
  }
  if (c.documentsSkippedAt.isNotEmpty) return 'Docs Skipped';
  if (c.documentsSavedAt.isNotEmpty) return 'Verified';
  if (c.summary.readyToSave) return 'All Approved';
  return 'To Review';
}

class AdminVerificationsScreen extends StatefulWidget {
  /// 0 Add Documents, 1 Verify Documents, 2 Convert to Staff, 3 Joining.
  final int initialTab;
  const AdminVerificationsScreen({super.key, this.initialTab = 0});

  @override
  State<AdminVerificationsScreen> createState() => _AdminVerificationsScreenState();
}

class _AdminVerificationsScreenState extends State<AdminVerificationsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  List<RecVerificationCandidate> _verify = [];
  List<RecVerificationCandidate> _convert = [];
  List<Map<String, dynamic>> _staff = [];
  String? _staffError;
  String _search = '';
  String _stageFilter = 'All';
  String _joinFilter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final vF = _service.getVerificationCandidates('verify');
      final cF = _service.getVerificationCandidates('convert');
      final v = await vF;
      final c = await cF;
      List<Map<String, dynamic>> staff = _staff;
      String? staffError;
      try {
        staff = await _service.getStaffRecords();
      } catch (e) {
        staffError = e.toString();
      }
      if (!mounted) return;
      setState(() {
        _verify = v;
        _convert = c;
        _staff = staff;
        _staffError = staffError;
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

  bool _match(RecVerificationCandidate c) {
    final q = _search.toLowerCase();
    return q.isEmpty ||
        c.fullName.toLowerCase().contains(q) ||
        c.email.toLowerCase().contains(q) ||
        c.position.toLowerCase().contains(q);
  }

  Future<void> _openDetail(RecVerificationCandidate c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminVerificationDetailScreen(candidateId: c.id)));
    _load(showLoader: false);
  }

  Future<void> _openConvert(RecVerificationCandidate c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminConvertToStaffScreen(candidateId: c.id)));
    _load(showLoader: false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab.clamp(0, 3),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: kRecBg,
        drawer: const AppDrawer(),
        appBar: recAppBar(
          context,
          'Verification',
          drawerKey: _scaffoldKey,
          onRefresh: () => _load(),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Add Documents'),
              Tab(text: 'Verify Documents'),
              Tab(text: 'Convert to Staff'),
              Tab(text: 'Joining'),
            ],
          ),
        ),
        body: RecAsyncBody(
          loading: _loading,
          error: _error,
          isEmpty: false,
          onRetry: _load,
          builder: () => TabBarView(children: [
            _list(
              _verify.where(_needsDocuments).where(_match).toList(),
              empty: 'No candidates waiting for documents',
              badge: (c) => '${c.summary.notSubmitted + c.summary.rejected} missing',
              badgeKey: (c) => (c.summary.notSubmitted + c.summary.rejected) == 0 ? 'completed' : 'pending',
              onTap: _openDetail,
            ),
            _list(
              _verify.where(_isSubmitted).where(_match).toList(),
              empty: 'No documents to verify yet',
              badge: verifyStateOf,
              badgeKey: (c) => verifyStateOf(c) == 'To Review' ? 'pending review' : (verifyStateOf(c) == 'All Approved' ? 'scheduled' : verifyStateOf(c)),
              onTap: _openDetail,
            ),
            _convertTab(),
            _joiningTab(),
          ]),
        ),
      ),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: RecSearchField(hint: 'Search name, email or position', onChanged: (v) => setState(() => _search = v)),
      );

  Widget _list(
    List<RecVerificationCandidate> rows, {
    required String empty,
    required String Function(RecVerificationCandidate) badge,
    required String Function(RecVerificationCandidate) badgeKey,
    required void Function(RecVerificationCandidate) onTap,
    Widget? header,
  }) {
    return RefreshIndicator(
      onRefresh: () => _load(showLoader: false),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _searchBar(),
          if (header != null) header,
          if (rows.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 60), child: RecEmptyState(text: empty, icon: Icons.folder_open_outlined))
          else
            ...rows.map((c) => RecCard(
                  onTap: () => onTap(c),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        RecAvatar(c.fullName, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                              Text('${c.position}${c.department.isNotEmpty ? ' • ${c.department}' : ''}',
                                  style: const TextStyle(fontSize: 13, color: kRecMuted, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        RecBadge(badge(c), colorKey: badgeKey(c)),
                      ]),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: c.summary.required == 0 ? 0 : c.summary.verified / c.summary.required,
                        minHeight: 6,
                        backgroundColor: AppColors.inputFill,
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${c.summary.verified}/${c.summary.required} verified • ${c.summary.pendingReview} to review • '
                        '${c.summary.rejected} rejected • ${c.summary.notSubmitted} not submitted',
                        style: const TextStyle(fontSize: 12, color: kRecMuted),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _convertTab() {
    const filters = {'All': 'All', 'pending': 'Ready to Convert', 'verificationHold': 'On Hold', 'converted': 'Converted'};
    final rows = _convert.where((c) => _stageFilter == 'All' || c.verificationStage == _stageFilter).where(_match).toList();
    String label(RecVerificationCandidate c) =>
        c.verificationStage == 'pending' ? 'Ready to Convert' : (kVerificationStageLabels[c.verificationStage] ?? c.verificationStage);
    return _list(
      rows,
      empty: 'No candidates to convert',
      badge: label,
      badgeKey: (c) => c.verificationStage == 'pending' ? 'scheduled' : label(c),
      onTap: (c) => c.verificationStage == 'converted' || c.verificationStage == 'pending' ? _openConvert(c) : _openDetail(c),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: RecFilterChips(
          options: filters.keys.toList(),
          selected: _stageFilter,
          labelOf: (k) => filters[k]!,
          counts: {
            'All': _convert.length,
            for (final k in filters.keys.skip(1)) k: _convert.where((c) => c.verificationStage == k).length,
          },
          onSelected: (k) => setState(() => _stageFilter = k),
        ),
      ),
    );
  }

  Widget _joiningTab() {
    final today = recTodayKey();
    final byId = {for (final s in _staff) (s['_id'] ?? s['id']).toString(): s};
    final joiners = <Map<String, dynamic>>[];
    for (final c in _convert.where((c) => c.verificationStage == 'converted' && c.staffId.isNotEmpty)) {
      final s = byId[c.staffId];
      final jd = recDateKey(s?['joiningDate']);
      if (s == null || jd.isEmpty) continue;
      final branch = s['branch'] is Map ? (s['branch']['branchName'] ?? '').toString() : '';
      final status = jd.compareTo(today) > 0 ? 'Convert to Staff' : (jd == today ? 'Joined' : 'Expired');
      final days = DateTime.parse(jd).difference(DateTime.parse(today)).inDays;
      joiners.add({
        'c': c,
        'joiningDate': jd,
        'status': status,
        'days': days,
        'employeeId': (s['employeeId'] ?? '').toString(),
        'position': (s['jobRole'] ?? s['designation'] ?? c.position).toString(),
        'branch': branch,
      });
    }
    joiners.sort((a, b) => (a['joiningDate'] as String).compareTo(b['joiningDate'] as String));
    final thisWeek = joiners.where((j) => (j['days'] as int) >= 0 && (j['days'] as int) <= 7).length;
    final q = _search.toLowerCase();
    final visible = joiners.where((j) {
      if (_joinFilter != 'All' && j['status'] != _joinFilter) return false;
      final c = j['c'] as RecVerificationCandidate;
      return q.isEmpty ||
          c.fullName.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q) ||
          (j['position'] as String).toLowerCase().contains(q) ||
          (j['employeeId'] as String).toLowerCase().contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _load(showLoader: false),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _searchBar(),
          if (_staffError != null)
            RecNotice('Staff records could not be loaded: $_staffError',
                color: AppColors.error, background: AppColors.errorBg, icon: Icons.error_outline_rounded),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.15,
            children: [
              RecStatTile(label: 'Joining this week', value: '$thisWeek', icon: Icons.event_available_rounded),
              RecStatTile(
                  label: 'Joining later',
                  value: '${joiners.where((j) => j['status'] == 'Convert to Staff').length}',
                  icon: Icons.person_add_alt_1_outlined,
                  color: AppColors.info),
              RecStatTile(
                  label: 'Joined today',
                  value: '${joiners.where((j) => j['status'] == 'Joined').length}',
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.success),
              RecStatTile(
                  label: 'Date passed',
                  value: '${joiners.where((j) => j['status'] == 'Expired').length}',
                  icon: Icons.timer_off_outlined,
                  color: AppColors.error),
            ],
          ),
          const SizedBox(height: 12),
          RecFilterChips(
            options: const ['All', 'Convert to Staff', 'Joined', 'Expired'],
            selected: _joinFilter,
            onSelected: (s) => setState(() => _joinFilter = s),
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 40), child: RecEmptyState(text: 'No converted candidates with a joining date'))
          else
            ...visible.map((j) {
              final c = j['c'] as RecVerificationCandidate;
              final days = j['days'] as int;
              return RecCard(
                child: Row(children: [
                  RecAvatar(c.fullName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                        const SizedBox(height: 2),
                        Text('${j['position']}${(j['branch'] as String).isNotEmpty ? ' • ${j['branch']}' : ''}',
                            style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                        Text(
                          'Joining ${recFormatDate(j['joiningDate'] as String)} '
                          '(${days == 0 ? 'today' : days > 0 ? 'in $days day${days == 1 ? '' : 's'}' : '${-days} day${days == -1 ? '' : 's'} ago'})'
                          '${(j['employeeId'] as String).isNotEmpty ? ' • ${j['employeeId']}' : ''}',
                          style: const TextStyle(fontSize: 12, color: kRecMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  RecBadge(j['status'] as String,
                      colorKey: j['status'] == 'Joined' ? 'joined' : (j['status'] == 'Expired' ? 'expired' : 'pending')),
                ]),
              );
            }),
        ],
      ),
    );
  }
}
