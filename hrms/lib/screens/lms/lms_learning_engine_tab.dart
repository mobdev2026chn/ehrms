// hrms/lib/screens/lms/lms_learning_engine_tab.dart
// Learning Engine tab — mirrors web LearningEngineDashboard.tsx (same API and layout).
// Data: GET /lms/analytics/my-scores (app_backend getMyScores) → summary, quizStats, courses.
// Top 3 cards use data.summary only:
//   Card 1 MY COMPLETION     → (summary.completedCourses / summary.totalCourses) * 100 %
//   Card 2 COURSES COMPLETED → summary.completedCourses / summary.totalCourses (e.g. "0/1")
//   Card 3 AVG ASSESSMENT SCORE → summary.overallScore %
// quizStats (totalAssigned, totalCompleted, easy/medium/hard) → Quiz performance card below.
// courses → Recent progress, Upcoming deadlines.
// Sections: 3 KPIs, heatmap,
// Quiz performance card, Recent progress, Upcoming deadlines.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../services/lms_service.dart';
import '../../widgets/app_tab_loader.dart';

class LmsLearningEngineTab extends StatefulWidget {
  final VoidCallback? onRefresh;

  const LmsLearningEngineTab({super.key, this.onRefresh});

  @override
  State<LmsLearningEngineTab> createState() => _LmsLearningEngineTabState();
}

class _LmsLearningEngineTabState extends State<LmsLearningEngineTab> {
  final LmsService _lmsService = LmsService();
  bool _scoresLoading = true;
  bool _heatmapLoading = true;
  Map<String, dynamic>? _scoresData;
  List<dynamic> _heatmap = [];
  String? _loadError;

  /// Selected day key (yyyy-MM-dd) for heatmap; when set, that cell is shown in black like web.
  String? _selectedHeatmapKey;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _scoresLoading = true;
      _heatmapLoading = true;
      _loadError = null;
    });
    final scoresRes = await _lmsService.getMyScores();
    final heatmapRes = await _lmsService.getLearningEngine();
    if (mounted) {
      setState(() {
        _scoresLoading = false;
        _heatmapLoading = false;
        if (scoresRes['success'] == true && scoresRes['data'] != null) {
          _scoresData = _ensureMap(scoresRes['data']);
          _loadError = null;
        } else {
          if (_scoresData == null) {
            _loadError =
                scoresRes['message']?.toString() ??
                'Could not load dashboard. Pull to retry.';
          }
        }
        if (heatmapRes['heatmap'] != null) {
          _heatmap = heatmapRes['heatmap'] is List
              ? heatmapRes['heatmap'] as List
              : [];
        }
      });
    }
  }

  static Map<String, dynamic> _ensureMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static int _int(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final summary = _scoresData?['summary'] is Map
        ? Map<String, dynamic>.from(_scoresData!['summary'] as Map)
        : <String, dynamic>{};
    final coursesRaw = _scoresData?['courses'];
    final courses = coursesRaw is List ? coursesRaw : <dynamic>[];
    final totalCourses = _int(summary['totalCourses']);
    final completedCourses = _int(summary['completedCourses']);
    final overallScore = _int(summary['overallScore']);
    final myCompletion = totalCourses > 0
        ? ((completedCourses / totalCourses) * 100).round()
        : 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _loadError!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Text(
              'Learning Engine',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Track progress and stay consistent.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            // Top 3 cards from GET /lms/analytics/my-scores → data.summary
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'MY COMPLETION',
                    value: _scoresLoading ? '—' : '$myCompletion%',
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatCard(
                    title: 'COURSES COMPLETED',
                    value: _scoresLoading
                        ? '—'
                        : '$completedCourses/$totalCourses',
                    icon: Icons.menu_book_outlined,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatCard(
                    title: 'AVG ASSESSMENT SCORE',
                    value: _scoresLoading ? '—' : '$overallScore%',
                    icon: Icons.emoji_events_outlined,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Learning consistency',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Last 12 months',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_heatmapLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: AppTabLoader(),
                        ),
                      )
                    else if (_heatmap.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No learning activity yet',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      )
                    else
                      _buildHeatmapGrid(),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Less',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        ..._heatColors.asMap().entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: e.value,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'More',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildQuizPerformanceCard(),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.show_chart, size: 20, color: Colors.grey[600]),
                const SizedBox(width: 8),
                const Text(
                  'Recent progress',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (courses.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No courses assigned yet',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
              )
            else
              ..._recentProgressList(courses).map(
                (c) => _RecentProgressItem(
                  title: c['title'] ?? 'Course',
                  progress: (c['progress'] is num)
                      ? (c['progress'] as num).round()
                      : 0,
                  status: _progressStatusLabel(c),
                ),
              ),
            const SizedBox(height: 24),
            _buildUpcomingDeadlines(),
          ],
        ),
      ),
    );
  }

  /// Recent progress: sort by completedAt/openedAt descending, take 6 (match web).
  List<Map<String, dynamic>> _recentProgressList(List<dynamic> courses) {
    final list = courses
        .where((c) => c is Map)
        .map<Map<String, dynamic>>((c) => Map<String, dynamic>.from(c as Map))
        .toList();
    list.sort((a, b) {
      final ta = _parseDate(a['completedAt'] ?? a['openedAt']);
      final tb = _parseDate(b['completedAt'] ?? b['openedAt']);
      return tb.compareTo(ta);
    });
    return list.take(6).toList();
  }

  DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime(0);
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString()) ?? DateTime(0);
  }

  String _progressStatusLabel(Map<String, dynamic> c) {
    final status = c['status']?.toString() ?? '';
    final progress = (c['progress'] is num)
        ? (c['progress'] as num).toDouble()
        : 0.0;
    if (status == 'Completed') return 'Completed';
    if (progress > 0) return 'In Progress';
    return 'Not Started';
  }

  Widget _buildQuizPerformanceCard() {
    final quizStatsRaw = _scoresData?['quizStats'];
    final quizStats = quizStatsRaw is Map
        ? Map<String, dynamic>.from(quizStatsRaw)
        : <String, dynamic>{};
    if (_scoresLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: const Center(
            child: AppTabLoader(),
          ),
        ),
      );
    }
    final totalAssigned = _int(quizStats['totalAssigned']);
    final totalCompleted = _int(quizStats['totalCompleted']);
    final completionPercent = _int(quizStats['completionPercent']);
    final easy = quizStats['easy'] is Map
        ? Map<String, dynamic>.from(quizStats['easy'] as Map)
        : <String, dynamic>{};
    final medium = quizStats['medium'] is Map
        ? Map<String, dynamic>.from(quizStats['medium'] as Map)
        : <String, dynamic>{};
    final hard = quizStats['hard'] is Map
        ? Map<String, dynamic>.from(quizStats['hard'] as Map)
        : <String, dynamic>{};

    if (totalAssigned == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No quizzes assigned yet. Complete lessons in your courses to unlock practice quizzes.',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  color: Colors.amber[700],
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Quiz performance',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: completionPercent / 100,
                          strokeWidth: 6,
                          backgroundColor: const Color(0xFFe5e7eb),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF22c55e),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$totalCompleted',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1f2937),
                            ),
                          ),
                          Text(
                            'of $totalAssigned\ncompleted',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      _QuizDifficultyRow(
                        label: 'Easy',
                        completed: _int(easy['completed']),
                        total: _int(easy['total']),
                        percent: _int(easy['percent']),
                        color: Colors.green,
                      ),
                      const SizedBox(height: 8),
                      _QuizDifficultyRow(
                        label: 'Medium',
                        completed: _int(medium['completed']),
                        total: _int(medium['total']),
                        percent: _int(medium['percent']),
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 8),
                      _QuizDifficultyRow(
                        label: 'Hard',
                        completed: _int(hard['completed']),
                        total: _int(hard['total']),
                        percent: _int(hard['percent']),
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingDeadlines() {
    final coursesRaw = _scoresData?['courses'];
    final courses = coursesRaw is List ? coursesRaw : <dynamic>[];
    final deadlines =
        courses
            .where(
              (c) =>
                  c is Map &&
                  c['dueDate'] != null &&
                  (c['status']?.toString() != 'Completed'),
            )
            .map((c) {
              final m = Map<String, dynamic>.from(c as Map);
              m['daysRemaining'] = _int(m['daysRemaining']);
              return m;
            })
            .toList()
          ..sort(
            (a, b) => (a['daysRemaining'] as int).compareTo(
              b['daysRemaining'] as int,
            ),
          );

    final top5 = deadlines.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 8),
            const Text(
              'Upcoming deadlines',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (top5.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No upcoming deadlines',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          )
        else
          ...top5.map((c) {
            final days = c['daysRemaining'] ?? 0;
            final urgency = days < 0 ? 'overdue' : (days <= 7 ? 'soon' : 'ok');
            final bg = urgency == 'overdue'
                ? Colors.red.withOpacity(0.1)
                : (urgency == 'soon'
                      ? Colors.amber.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1));
            final border = urgency == 'overdue'
                ? Colors.red
                : (urgency == 'soon' ? Colors.amber : Colors.green);

            final daysText = days < 0
                ? '${-days}d overdue'
                : days == 0
                ? 'Due today'
                : '${days}d left';
            final isSoon = days >= 0 && days <= 7;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: border.withOpacity(0.5)),
              ),
              color: bg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c['title'] ?? 'Course',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (c['dueDate'] != null)
                      Text(
                        _formatDate(c['dueDate']),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSoon
                            ? Colors.orange.withOpacity(0.2)
                            : border.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        daysText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSoon ? Colors.orange.shade800 : border,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  /// Format as "Mar 3, 2026" to match web.
  String _formatDate(dynamic date) {
    if (date == null) return '—';
    try {
      final d = date is DateTime ? date : DateTime.tryParse(date.toString());
      if (d == null) return '—';
      return '${_monthShort(d.month)} ${d.day}, ${d.year}';
    } catch (_) {
      return '—';
    }
  }

  String _monthShort(int m) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[m - 1];
  }

  static const _heatColors = [
    Color(0xFFebedf0),
    Color(0xFF9be9a8),
    Color(0xFF40c463),
    Color(0xFF30a14e),
    Color(0xFF216e39),
  ];

  static const _daysLast12Months = 371;

  /// Match web frontend: CELL_MIN = 14, CELL_GAP = 4
  static const _cellSize = 14.0;
  static const _cellGap = 4.0;
  static const _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ]; // DateTime.weekday 1..7

  /// Build date -> activity level (0-4) map from API heatmap. Matches frontend/bb logic.
  Map<String, int> _buildActivityLevelMap() {
    final map = <String, int>{};
    for (final h in _heatmap) {
      final date = h['date']?.toString();
      if (date == null) continue;
      final score = (h['activityScore'] is num)
          ? (h['activityScore'] as num).toDouble()
          : (h['totalMinutes'] is num)
          ? (h['totalMinutes'] as num).toDouble()
          : 0.0;
      int level = 0;
      if (score > 60)
        level = 4;
      else if (score > 40)
        level = 3;
      else if (score > 20)
        level = 2;
      else if (score > 0)
        level = 1;
      map[date] = level;
    }
    return map;
  }

  /// GitHub-style heatmap: 371 days (last 12 months), weeks as columns, 7 rows (Sun–Sat), month labels, legend.
  Widget _buildHeatmapGrid() {
    final now = DateTime.now();
    final rangeStart = now.subtract(
      const Duration(days: _daysLast12Months - 1),
    );
    final levelMap = _buildActivityLevelMap();
    final numWeeks = (_daysLast12Months / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month row
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Row(
                  children: List.generate(numWeeks, (col) {
                    final firstDayOfWeek = rangeStart.add(
                      Duration(days: col * 7),
                    );
                    final prevWeek = col > 0
                        ? rangeStart.add(Duration(days: (col - 1) * 7))
                        : null;
                    final showMonth =
                        prevWeek == null ||
                        firstDayOfWeek.month != prevWeek.month;
                    return SizedBox(
                      width: _cellSize + _cellGap,
                      child: showMonth
                          ? Text(
                              DateFormat('MMM').format(firstDayOfWeek),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : const SizedBox(),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 6),
              // Grid: 7 rows (Mon–Sun) x numWeeks columns
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Day-of-week labels (row 0 = weekday of day 0, etc.)
                  SizedBox(
                    width: 28,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(7, (row) {
                        final dayOfFirstWeek = rangeStart.add(
                          Duration(days: row),
                        );
                        final wd = dayOfFirstWeek.weekday; // 1=Mon .. 7=Sun
                        final label = _weekdayNames[wd - 1];
                        return SizedBox(
                          height: _cellSize + _cellGap,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Cells: row = day of week (0=Mon .. 6=Sun), col = week
                  Column(
                    children: List.generate(7, (row) {
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: row < 6 ? _cellGap : 0,
                        ),
                        child: Row(
                          children: List.generate(numWeeks, (col) {
                            final dayIndex = col * 7 + row;
                            if (dayIndex >= _daysLast12Months) {
                              return SizedBox(
                                width: _cellSize + _cellGap,
                                height: _cellSize + _cellGap,
                              );
                            }
                            final d = rangeStart.add(Duration(days: dayIndex));
                            final key = DateFormat('yyyy-MM-dd').format(d);
                            final level = levelMap[key] ?? 0;
                            final isToday =
                                key == DateFormat('yyyy-MM-dd').format(now);
                            final isSelected = key == _selectedHeatmapKey;
                            final cellColor = isSelected
                                ? Colors.black
                                : _heatColors[level];
                            return Padding(
                              padding: EdgeInsets.only(
                                right: col < numWeeks - 1 ? _cellGap : 0,
                              ),
                              child: Builder(
                                builder: (cellContext) {
                                  return GestureDetector(
                                    onTap: () {
                                      final box =
                                          cellContext.findRenderObject()
                                              as RenderBox?;
                                      if (box != null && box.hasSize) {
                                        final position = box.localToGlobal(
                                          Offset.zero,
                                        );
                                        setState(
                                          () => _selectedHeatmapKey = key,
                                        );
                                        _showHeatmapPopup(
                                          context,
                                          key,
                                          d,
                                          now,
                                          position,
                                          box.size,
                                        );
                                      }
                                    },
                                    child: Tooltip(
                                      message: _heatmapTooltip(
                                        key,
                                        level,
                                        d,
                                        now,
                                      ),
                                      child: Container(
                                        width: _cellSize,
                                        height: _cellSize,
                                        decoration: BoxDecoration(
                                          color: cellColor,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                          border: isToday
                                              ? Border.all(
                                                  color: const Color(
                                                    0xFF22c55e,
                                                  ),
                                                  width: 2,
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _heatmapTooltip(String key, int level, DateTime d, DateTime now) {
    final sameDay = key == DateFormat('yyyy-MM-dd').format(now);
    final dateStr = DateFormat('MMM d, yyyy').format(d);
    final sb = StringBuffer(dateStr);
    if (sameDay) sb.write('\nToday');
    Map<String, dynamic>? point;
    for (final h in _heatmap) {
      if (h is Map && h['date']?.toString() == key) {
        point = Map<String, dynamic>.from(h);
        break;
      }
    }
    if (point != null) {
      final mins = point['totalMinutes'] ?? 0;
      final lessons = point['lessonsCompleted'] ?? 0;
      final quizzes = point['quizzesAttempted'] ?? 0;
      final assessments = point['assessmentsAttempted'] ?? 0;
      final live = point['liveSessionsAttended'] ?? 0;
      if (mins > 0) sb.write('\n${mins} min learned');
      if (lessons > 0)
        sb.write('\n$lessons lesson${lessons != 1 ? 's' : ''} completed');
      if (quizzes > 0)
        sb.write('\n$quizzes quiz${quizzes != 1 ? 'zes' : ''} attempted');
      if (assessments > 0)
        sb.write('\n$assessments assessment${assessments != 1 ? 's' : ''}');
      if (live > 0)
        sb.write('\n$live live session${live != 1 ? 's' : ''} attended');
    }
    if (level == 0 && point == null) sb.write('\nNo activity');
    return sb.toString();
  }

  /// Build activity detail lines for a day (same as web tooltip).
  List<String> _heatmapDayDetailLines(String key) {
    Map<String, dynamic>? point;
    for (final h in _heatmap) {
      if (h is Map && h['date']?.toString() == key) {
        point = Map<String, dynamic>.from(h);
        break;
      }
    }
    final lines = <String>[];
    if (point != null) {
      final mins = (point['totalMinutes'] is num)
          ? (point['totalMinutes'] as num).toInt()
          : 0;
      final lessons = (point['lessonsCompleted'] is num)
          ? (point['lessonsCompleted'] as num).toInt()
          : 0;
      final quizzes = (point['quizzesAttempted'] is num)
          ? (point['quizzesAttempted'] as num).toInt()
          : 0;
      final assessments = (point['assessmentsAttempted'] is num)
          ? (point['assessmentsAttempted'] as num).toInt()
          : 0;
      final live = (point['liveSessionsAttended'] is num)
          ? (point['liveSessionsAttended'] as num).toInt()
          : 0;
      if (mins > 0) lines.add('${mins} min learned');
      if (lessons > 0)
        lines.add('$lessons lesson${lessons != 1 ? 's' : ''} completed');
      if (quizzes > 0)
        lines.add('$quizzes quiz${quizzes != 1 ? 'zes' : ''} attempted');
      if (assessments > 0)
        lines.add(
          '$assessments assessment${assessments != 1 ? 's' : ''} attempted',
        );
      if (live > 0)
        lines.add('$live live session${live != 1 ? 's' : ''} attended');
    }
    if (lines.isEmpty) lines.add('No activity');
    return lines;
  }

  /// Show dark tooltip popup above the heatmap cell (like web: dark bg, white text, triangle pointer).
  void _showHeatmapPopup(
    BuildContext context,
    String key,
    DateTime d,
    DateTime now,
    Offset cellPosition,
    Size cellSize,
  ) {
    final dateStr = DateFormat('MMM d, yyyy').format(d);
    final sameDay = key == DateFormat('yyyy-MM-dd').format(now);
    final detailLines = _heatmapDayDetailLines(key);

    const double popupPadding = 12;
    const double arrowHeight = 6;
    const double popupRadius = 8;
    const double popupWidth = 240;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final centerX = cellPosition.dx + cellSize.width / 2;
    final left = (centerX - popupWidth / 2).clamp(
      8.0,
      screenWidth - popupWidth - 8,
    );

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          GestureDetector(
            onTap: () {
              overlayEntry.remove();
              if (mounted) setState(() => _selectedHeatmapKey = null);
            },
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
          Positioned(
            left: left,
            bottom: screenHeight - cellPosition.dy,
            width: popupWidth,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: popupPadding,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(popupRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (sameDay)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Today',
                              style: TextStyle(
                                color: Colors.green.shade300,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ...detailLines.map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              line,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: CustomPaint(
                      size: const Size(16, arrowHeight),
                      painter: _TrianglePainter(
                        color: const Color(0xFF1F2937),
                        pointUp: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }
}

/// Paints a small triangle for the tooltip pointer (point up or down).
class _TrianglePainter extends CustomPainter {
  final Color color;
  final bool pointUp;

  _TrianglePainter({required this.color, this.pointUp = false});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointUp) {
      path.moveTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizDifficultyRow extends StatelessWidget {
  final String label;
  final int completed;
  final int total;
  final int percent;
  final Color color;

  const _QuizDifficultyRow({
    required this.label,
    required this.completed,
    required this.total,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isGreen = color == Colors.green;
    final isAmber = color == Colors.amber;
    final bgColor = isGreen
        ? const Color(0xFFf0fdf4)
        : (isAmber ? const Color(0xFFfffbeb) : const Color(0xFFfef2f2));
    final borderColor = isGreen
        ? const Color(0xFFdcfce7)
        : (isAmber ? const Color(0xFFfef3c7) : const Color(0xFFfecaca));
    final textColor = isGreen
        ? const Color(0xFF166534)
        : (isAmber ? const Color(0xFF92400e) : const Color(0xFF991b1b));
    final percentBg = isGreen
        ? const Color(0xFFbbf7d0)
        : (isAmber ? const Color(0xFFfde68a) : const Color(0xFFfecaca));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          Text(
            '$completed/$total',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: percentBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$percent%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentProgressItem extends StatelessWidget {
  final String title;
  final int progress;
  final String status;

  const _RecentProgressItem({
    required this.title,
    required this.progress,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 80,
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  status == 'Completed' ? Colors.green : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: Text(
                status,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
