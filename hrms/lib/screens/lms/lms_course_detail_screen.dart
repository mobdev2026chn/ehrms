// hrms/lib/screens/lms/lms_course_detail_screen.dart
// Course detail - mirrors web /lms/employee/course/:id
// Course content sidebar, embedded content viewer, Mark Done, Practice Quiz

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_colors.dart';
import '../../config/constants.dart';
import '../../services/lms_service.dart';
import '../../utils/snackbar_utils.dart' show SnackBarUtils;
import '../../utils/error_message_utils.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../dashboard/dashboard_screen.dart';
import 'lms_ai_quiz_attempt_screen.dart';
import 'lms_assessment_screen.dart';
import 'widgets/lms_content_viewer.dart';
import '../../widgets/app_tab_loader.dart';

class LmsCourseDetailScreen extends StatefulWidget {
  final String courseId;

  /// When provided, bottom nav "Live Sessions" will pop and switch to that tab.
  final void Function(int index)? onLmsTabSwitch;

  const LmsCourseDetailScreen({
    super.key,
    required this.courseId,
    this.onLmsTabSwitch,
  });

  @override
  State<LmsCourseDetailScreen> createState() => _LmsCourseDetailScreenState();
}

class _LmsCourseDetailScreenState extends State<LmsCourseDetailScreen> {
  final LmsService _lmsService = LmsService();
  dynamic _course;
  dynamic _progress;
  bool _loading = true;
  int _selectedIndex = 0;
  List<dynamic> _allMaterials = [];
  bool _generatingQuiz = false;

  @override
  void initState() {
    super.initState();
    _loadCourse();
  }

  Future<void> _loadCourse() async {
    setState(() => _loading = true);
    final res = await _lmsService.getCourseDetails(widget.courseId);
    if (mounted) {
      setState(() {
        _loading = false;
        _course = res['data']?['course'];
        _progress = res['data']?['progress'];
        _allMaterials = _buildMaterialsList();
        if (_allMaterials.isNotEmpty &&
            _selectedIndex >= _allMaterials.length) {
          _selectedIndex = 0;
        }
      });
    }
  }

  /// Build materials list - supports materials, contents, and lessons[].materials (like web).
  List<dynamic> _buildMaterialsList() {
    if (_course == null) return [];
    final materials = _course['materials'] as List? ?? [];
    final contents = _course['contents'] as List? ?? [];
    final lessons = _course['lessons'] as List? ?? [];
    // Support lessons[].materials (structured format from some backends)
    final fromLessons = <dynamic>[];
    for (final l in lessons) {
      final lessonMats = (l['materials'] as List?) ?? [];
      final lessonTitle = (l['title'] ?? l['lessonTitle'] ?? 'Course Materials')
          .toString();
      for (final m in lessonMats) {
        final mat = Map<String, dynamic>.from((m is Map) ? m : {});
        mat['lessonTitle'] = lessonTitle;
        fromLessons.add(mat);
      }
    }
    // Prefer materials if non-empty, else use fromLessons
    final primary = materials.isNotEmpty ? materials : fromLessons;
    final combined = <dynamic>[...primary, ...contents];
    // Normalize: ensure each item has lessonTitle
    return combined.map((m) {
      final map = (m is Map)
          ? Map<String, dynamic>.from(m)
          : <String, dynamic>{};
      if (!map.containsKey('lessonTitle') || map['lessonTitle'] == null) {
        map['lessonTitle'] = 'Course Materials';
      }
      return map;
    }).toList();
  }

  Map<String, List<dynamic>> _groupByLesson() {
    final map = <String, List<dynamic>>{};
    for (final m in _allMaterials) {
      final lesson = (m['lessonTitle'] ?? 'Course Materials').toString();
      map.putIfAbsent(lesson, () => []).add(m);
    }
    return map;
  }

  bool _isViewed(String? contentId) {
    if (contentId == null) return false;
    final list = _progress?['contentProgress'] as List? ?? [];
    for (final p in list) {
      if (p['contentId']?.toString() == contentId.toString()) {
        return p['viewed'] == true;
      }
    }
    return false;
  }

  bool _isLessonCompleted(String lessonTitle) {
    final materials = _allMaterials.where(
      (m) => (m['lessonTitle'] ?? 'Course Materials').toString() == lessonTitle,
    );
    if (materials.isEmpty) return false;
    return materials.every(
      (m) => _isViewed(m['_id']?.toString() ?? m['id']?.toString()),
    );
  }

  bool _isLessonLocked(int lessonIndex, List<String> lessonTitles) {
    if (lessonIndex == 0) return false;
    return !_isLessonCompleted(lessonTitles[lessonIndex - 1]);
  }

  List<String> get _completedLessonTitles {
    final grouped = _groupByLesson();
    return grouped.keys.where((k) => _isLessonCompleted(k)).toList();
  }

  Future<void> _markLessonComplete(String lessonTitle) async {
    final res = await _lmsService.completeLesson(widget.courseId, lessonTitle);
    if (mounted) {
      if (res['success'] == true) {
        SnackBarUtils.showSnackBar(context, 'Lesson marked as complete!');
        setState(() => _progress = res['data']);
        _lmsService.logLearningActivity(lessonsCompleted: 1);
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(res['message']?.toString(), fallback: 'Failed'),
          isError: true,
        );
      }
    }
  }

  Future<void> _updateProgress(
    String contentId, {
    bool completed = true,
  }) async {
    final res = await _lmsService.updateProgress(
      widget.courseId,
      contentId,
      completed: completed,
    );
    if (mounted && res['success'] == true) {
      setState(() => _progress = res['data']);
    }
  }

  Future<Map<String, dynamic>?> _generateQuiz(
    List<String> lessonTitles, {
    String difficulty = 'Medium',
    int questionCount = 5,
    List<String>? materialIds,
  }) async {
    if (lessonTitles.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Select at least one completed lesson',
        isError: true,
      );
      return null;
    }
    final res = await _lmsService.generateAIQuiz(
      courseId: widget.courseId,
      lessonTitles: lessonTitles,
      questionCount: questionCount,
      difficulty: difficulty,
      materialId: materialIds != null && materialIds.isNotEmpty
          ? materialIds.first
          : null,
    );
    if (mounted) {
      if (res['success'] == true && res['data'] != null) {
        return res;
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(res['message']?.toString(), fallback: 'Failed to generate quiz'),
          isError: true,
        );
      }
    }
    return null;
  }

  void _openMaterial(dynamic material) {
    final type = (material['type'] ?? 'URL').toString().toUpperCase();
    var url =
        material['url'] ??
        material['filePath'] ??
        material['link'] ??
        material['externalUrl'] ??
        '';
    url = url.toString().trim();

    if (url.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'No content URL', isError: true);
      return;
    }

    String urlToLaunch = url;
    if (type == 'YOUTUBE') {
      final videoId = url.contains('v=')
          ? url.split('v=')[1]?.split('&')[0]
          : url.split('/').last;
      urlToLaunch = 'https://www.youtube.com/watch?v=$videoId';
    } else if (!url.startsWith('http') && !url.startsWith('data:')) {
      urlToLaunch = AppConstants.getLmsFileUrl(url);
    }

    final uri = Uri.tryParse(urlToLaunch);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Loading...'),
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
        ),
        body: const Center(child: AppTabLoader()),
      );
    }

    if (_course == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Course'),
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
        ),
        body: const Center(child: Text('Course not found')),
      );
    }

    final grouped = _groupByLesson();
    final lessonTitles = grouped.keys.toList();
    final currentMaterial =
        _allMaterials.isNotEmpty && _selectedIndex < _allMaterials.length
        ? _allMaterials[_selectedIndex]
        : null;
    final completionPercent = _progress?['completionPercentage'] ?? 0;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            title: const Text('Course'),
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.textPrimary,
          ),
          drawer: const AppDrawer(),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _showCourseContentSheet(
                        context,
                        lessonTitles,
                        grouped,
                        completionPercent,
                      ),
                      icon: const Icon(Icons.list_alt, size: 20),
                      label: const Text('Course content'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildContentViewer(currentMaterial)),
            ],
          ),
          bottomNavigationBar: _buildLmsBottomNav(context),
        ),
        if (_generatingQuiz)
          Positioned.fill(
            child: Material(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppTabLoader(),
                    const SizedBox(height: 20),
                    Text(
                      'Wait, your quiz is generating…',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showCourseContentSheet(
    BuildContext context,
    List<String> lessonTitles,
    Map<String, List<dynamic>> grouped,
    int completionPercent,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Course content',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _course['title'] ?? 'Course',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildSidebar(
                lessonTitles,
                grouped,
                completionPercent,
                compact: false,
                scrollController: scrollController,
                onSelectMaterial: (idx) {
                  setState(() => _selectedIndex = idx);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLmsBottomNav(BuildContext context) {
    return AppBottomNavigationBar(
      currentIndex: -1,
      onTap: (index) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(initialIndex: index),
          ),
          (route) => route.isFirst,
        );
      },
    );
  }

  Widget _buildContentViewer(dynamic material) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (material == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Text(
                    _allMaterials.isEmpty
                        ? 'No learning material available for this lesson.'
                        : 'Select content to view',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        material['title'] ??
                            material['lessonTitle'] ??
                            'Content',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (material['type'] ?? 'URL').toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openMaterial(material),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LmsContentViewer(
                  material: material,
                  onMarkDone: _isViewed(material['_id']?.toString()) == false
                      ? () {
                          final contentId = material['_id']?.toString();
                          if (contentId != null) {
                            _updateProgress(contentId);
                          }
                          final lesson =
                              (material['lessonTitle'] ?? 'Course Materials')
                                  .toString();
                          if (_isLessonCompleted(lesson)) {
                            _markLessonComplete(lesson);
                          }
                        }
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSidebar(
    List<String> lessonTitles,
    Map<String, List<dynamic>> grouped,
    int completionPercent, {
    bool compact = false,
    ScrollController? scrollController,
    void Function(int idx)? onSelectMaterial,
  }) {
    final content = ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Course content',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '${grouped.length} sections • ${_allMaterials.length} items',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'YOUR PROGRESS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$completionPercent% Completed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: completionPercent / 100,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
        const SizedBox(height: 24),
        ...lessonTitles.asMap().entries.map((entry) {
          final i = entry.key;
          final title = entry.value;
          final materials = grouped[title]!;
          final isLocked = _isLessonLocked(i, lessonTitles);
          final isCompleted = _isLessonCompleted(title);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 1),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: ExpansionTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              initiallyExpanded: i == 0,
              leading: Icon(
                isLocked
                    ? Icons.lock
                    : (isCompleted
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked),
                color: isLocked
                    ? Colors.grey
                    : (isCompleted ? Colors.green : AppColors.primary),
                size: 20,
              ),
              title: Text(
                '${i + 1}. $title',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isLocked ? Colors.grey : null,
                ),
              ),
              subtitle: Row(
                children: [
                  Text(
                    '${materials.length} item(s)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  if (isCompleted) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Completed',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              children: [
                ...materials.map((m) {
                  final matId = m['_id']?.toString();
                  final viewed = _isViewed(matId);
                  final idx = _allMaterials.indexWhere(
                    (x) => (x['_id']?.toString()) == matId,
                  );
                  if (idx < 0) return const SizedBox();

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      viewed ? Icons.check_circle : Icons.play_circle_outline,
                      size: 18,
                      color: viewed ? Colors.green : Colors.grey,
                    ),
                    title: Text(
                      m['title'] ?? m['type'] ?? 'Content',
                      style: TextStyle(
                        fontSize: 12,
                        color: isLocked ? Colors.grey : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: (m['type'] ?? '').toString().isNotEmpty
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (m['type'] ?? 'URL').toString(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[700],
                              ),
                            ),
                          )
                        : null,
                    onTap: isLocked
                        ? null
                        : () {
                            if (onSelectMaterial != null) {
                              onSelectMaterial(idx);
                            } else {
                              setState(() => _selectedIndex = idx);
                            }
                          },
                  );
                }),
                if (!isLocked) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showQuizModal(context, preSelected: [title]),
                      icon: const Icon(Icons.quiz_outlined, size: 16),
                      label: const Text('AI Quiz'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ],
                if (!isLocked && !isCompleted) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _markLessonComplete(title),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Mark Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
        if (_completedLessonTitles.isNotEmpty) ...[
          const SizedBox(height: 16),
          Builder(
            builder: (ctx) {
              // Match web: show Final Assessment when ALL lessons completed (same as web renderSidebarFooter)
              final allLessonsCompleted =
                  lessonTitles.isNotEmpty &&
                  lessonTitles.every((t) => _isLessonCompleted(t));
              final isLiveAssessment = _course?['isLiveAssessment'] == true;
              final assessmentRequested =
                  _progress?['assessmentStatus'] == 'Requested' ||
                  _progress?['assessmentStatus'] == 'In Progress';

              // Web shows "Start Final Assessment" or "Request Final Assessment" whenever allLessonsCompleted (no hasAssessment check)
              if (allLessonsCompleted && !isLiveAssessment) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => LmsAssessmentScreen(
                                courseId: widget.courseId,
                              ),
                            ),
                          )
                          .then((_) => mounted ? _loadCourse() : null);
                    },
                    icon: const Icon(Icons.emoji_events),
                    label: const Text('Start Final Assessment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                );
              }
              if (allLessonsCompleted &&
                  isLiveAssessment &&
                  !assessmentRequested) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      SnackBarUtils.showSnackBar(
                        context,
                        'Live assessment request not yet supported in app',
                      );
                    },
                    icon: const Icon(Icons.emoji_events),
                    label: const Text('Request Final Assessment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                );
              }
              // Some but not all lessons completed: show Practice Quiz
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showQuizModal(context),
                  icon: const Icon(Icons.quiz_outlined),
                  label: const Text('Practice Quiz'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
    if (compact) {
      return Container(
        color: Colors.grey[100],
        constraints: const BoxConstraints(maxHeight: 280),
        child: content,
      );
    }
    return content;
  }

  void _showQuizModal(BuildContext context, {List<String>? preSelected}) {
    final completed = _completedLessonTitles;
    if (completed.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Complete at least one lesson to generate a quiz.',
        isError: true,
      );
      return;
    }
    List<String> initialSelected = preSelected != null
        ? preSelected.where((s) => completed.contains(s)).toList()
        : (completed.isNotEmpty ? [completed.first] : []);
    if (initialSelected.isEmpty && completed.isNotEmpty) {
      initialSelected = [completed.first];
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AiQuizModalContent(
        completedLessons: completed,
        initialSelected: initialSelected,
        onGenerate: (selected, difficulty, questionCount) {
          Navigator.pop(ctx);
          // Send material IDs for selected lessons so backend uses exact content
          final ids = _allMaterials
              .where(
                (m) => selected.contains(
                  (m['lessonTitle'] ?? 'Course Materials').toString(),
                ),
              )
              .map((m) => m['_id']?.toString())
              .whereType<String>()
              .toList();
          Future.delayed(const Duration(milliseconds: 150), () {
            if (!mounted) return;
            setState(() => _generatingQuiz = true);
            _generateQuiz(
              selected,
              difficulty: difficulty,
              questionCount: questionCount,
              materialIds: ids.isNotEmpty ? ids : null,
            ).then((res) {
              if (!mounted) return;
              setState(() => _generatingQuiz = false);
              if (res != null &&
                  res['success'] == true &&
                  res['data'] != null) {
                final quizId = res['data']['_id']?.toString();
                if (quizId != null) {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              LmsAiQuizAttemptScreen(quizId: quizId),
                        ),
                      )
                      .then((_) => _loadCourse());
                }
              }
            });
          });
        },
      ),
    );
  }
}

/// Modal content for AI Practice Quiz; owns [TextEditingController] and disposes it correctly to avoid _dependents assertion.
class _AiQuizModalContent extends StatefulWidget {
  final List<String> completedLessons;
  final List<String> initialSelected;
  final void Function(
    List<String> selected,
    String difficulty,
    int questionCount,
  )
  onGenerate;

  const _AiQuizModalContent({
    required this.completedLessons,
    required this.initialSelected,
    required this.onGenerate,
  });

  @override
  State<_AiQuizModalContent> createState() => _AiQuizModalContentState();
}

class _AiQuizModalContentState extends State<_AiQuizModalContent> {
  late List<String> _selected;
  late String _difficulty;
  late TextEditingController _questionCountController;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelected);
    _difficulty = 'Medium';
    _questionCountController = TextEditingController(text: '5');
  }

  @override
  void dispose() {
    _questionCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.quiz_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'AI Practice Quiz',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Choose completed lessons and generate a quiz.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          const Text(
            'Select Lessons *',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...widget.completedLessons.map((lesson) {
            final isSelected = _selected.contains(lesson);
            return CheckboxListTile(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    if (!_selected.contains(lesson)) {
                      _selected = [..._selected, lesson];
                    }
                  } else {
                    _selected = _selected.where((s) => s != lesson).toList();
                  }
                });
              },
              title: Text(lesson, style: const TextStyle(fontSize: 14)),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Difficulty',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: _difficulty,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: ['Easy', 'Medium', 'Hard']
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _difficulty = v ?? 'Medium'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Questions (1–10)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _questionCountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        hintText: '5',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_selected.isEmpty) return;
              final q = int.tryParse(_questionCountController.text) ?? 5;
              final clampedCount = q.clamp(1, 10);
              widget.onGenerate(_selected, _difficulty, clampedCount);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Generate Quiz'),
          ),
        ],
      ),
    );
  }
}
