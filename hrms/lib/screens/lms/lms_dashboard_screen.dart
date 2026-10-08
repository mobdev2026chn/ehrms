// hrms/lib/screens/lms/lms_dashboard_screen.dart
// My Learning Dashboard - mirrors web /lms/employee/dashboard
// Tabs: My Courses, Learning Engine; when embedded in shell also Live Sessions. Library tab hidden.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../dashboard/dashboard_screen.dart';
import '../../config/constants.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../services/lms_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import 'lms_course_detail_screen.dart';
import 'lms_learning_engine_tab.dart';
import 'lms_live_sessions_screen.dart';
import '../../widgets/app_tab_loader.dart';

class LmsDashboardScreen extends StatefulWidget {
  /// When true, rendered inside LmsShellScreen (no Scaffold, app bar, drawer).
  final bool embeddedInShell;

  /// When embedded in shell, include Live Sessions as 4th tab and use this as initial tab index.
  final int initialIndex;

  /// When provided, course detail can switch LMS tab on pop (e.g. to Live Sessions).
  final void Function(int index)? onLmsTabSwitch;

  const LmsDashboardScreen({
    super.key,
    this.embeddedInShell = false,
    this.initialIndex = 0,
    this.onLmsTabSwitch,
  });

  @override
  State<LmsDashboardScreen> createState() => _LmsDashboardScreenState();
}

class _LmsDashboardScreenState extends State<LmsDashboardScreen>
    with SingleTickerProviderStateMixin {
  final LmsService _lmsService = LmsService();
  late TabController _tabController;

  List<dynamic> _courses = [];
  List<dynamic> _libraryCourses = [];
  List<String> _categories = [];
  bool _isLoading = true;
  bool _isLoadingLibrary = false;
  String _searchTerm = '';
  String? _categoryFilter;
  String _librarySearch = '';
  String? _libraryCategoryFilter;
  final TextEditingController _courseSearchController = TextEditingController();
  final TextEditingController _librarySearchController = TextEditingController();

  int get _tabCount => widget.embeddedInShell ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, _tabCount - 1),
    );
    _loadCourses();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final res = await _lmsService.getCategories();
    if (mounted && res['success'] == true) {
      final list = (res['data'] as List?) ?? [];
      final names = list
          .map((e) {
            if (e is String) return e;
            return (e['name'] ?? e['title'] ?? e).toString();
          })
          .where((s) => s.toString().isNotEmpty)
          .map((s) => s.toString())
          .toList();
      setState(
        () => _categories = names.isNotEmpty
            ? names
            : [
                'Development',
                'Business',
                'Design',
                'Marketing',
                'IT & Software',
                'Personal Development',
                'GENERAL',
              ],
      );
    } else if (mounted) {
      setState(
        () => _categories = [
          'Development',
          'Business',
          'Design',
          'Marketing',
          'IT & Software',
          'Personal Development',
          'GENERAL',
        ],
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _courseSearchController.dispose();
    _librarySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    setState(() => _isLoading = true);
    final res = await _lmsService.getMyCourses();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _courses = (res['data'] as List?) ?? [];
      });
    }
  }

  Future<void> _loadLibrary() async {
    setState(() => _isLoadingLibrary = true);
    final res = await _lmsService.getAllCourses();
    if (mounted) {
      setState(() {
        _isLoadingLibrary = false;
        _libraryCourses = (res['data'] as List?) ?? [];
      });
    }
  }

  bool _isEnrolled(String? courseId) {
    if (courseId == null) return false;
    for (final item in _courses) {
      final c = item['courseId'] ?? item;
      final id = c['_id']?.toString();
      if (id == courseId) return true;
    }
    return false;
  }

  List<dynamic> get _filteredCourses {
    return _courses.where((item) {
      final course = item['courseId'] ?? item;
      final title = (course['title'] ?? '').toString();
      final category = (course['category'] ?? '').toString();
      final matchesSearch =
          _searchTerm.isEmpty ||
          title.toLowerCase().contains(_searchTerm.toLowerCase());
      final matchesCategory =
          _categoryFilter == null ||
          _categoryFilter!.isEmpty ||
          category == _categoryFilter;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Small tab icons and text
    const tabIconSize = 16.0;
    const tabFontSize = 12.0;
    final tabs = <Tab>[
      Tab(height: 44, iconMargin: const EdgeInsets.only(bottom: 2), text: 'My Courses', icon: Icon(Icons.menu_book_outlined, size: tabIconSize)),
      Tab(
        height: 44,
        iconMargin: const EdgeInsets.only(bottom: 2),
        text: 'Learning Engine',
        icon: Icon(Icons.bar_chart_outlined, size: tabIconSize),
      ),
      if (widget.embeddedInShell)
        Tab(height: 44, iconMargin: const EdgeInsets.only(bottom: 2), text: 'Live Sessions', icon: Icon(Icons.video_call_outlined, size: tabIconSize)),
    ];
    final tabBar = TabBar(
      controller: _tabController,
      labelColor: AppColors.primaryText,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      labelStyle: const TextStyle(fontSize: tabFontSize, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: tabFontSize, fontWeight: FontWeight.w500),
      indicator: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      tabs: tabs,
    );

    final tabChildren = <Widget>[
      _buildMyCoursesTab(),
      LmsLearningEngineTab(onRefresh: _loadCourses),
      if (widget.embeddedInShell) const LmsLiveSessionsScreen(embeddedInShell: true),
    ];
    final body = TabBarView(
      controller: _tabController,
      children: tabChildren,
    );

    if (widget.embeddedInShell) {
      return Column(
        children: [
          // Dashboard header — mirrors web /lms/employee/dashboard
          Container(
            width: double.infinity,
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'My Learning Dashboard',
                  style: AppTextStyles.headingLarge,
                ),
                SizedBox(height: 4),
                Text(
                  'Track your progress, resume courses, and achieve your learning goals.',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            height: 52,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: Color(0xFFECEEF1))),
            ),
            child: tabBar,
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('My Learning Dashboard'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(color: AppColors.surface, child: tabBar),
        ),
      ),
      drawer: const AppDrawer(),
      body: body,
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: -1,
        onTap: (index) {
          DashboardScreen.goToTab(context, index);
        },
      ),
    );
  }

  Widget _buildMyCoursesTab() {
    if (_isLoading) {
      return const Center(child: AppTabLoader());
    }

    final filtered = _filteredCourses;

    return RefreshIndicator(
      onRefresh: _loadCourses,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _courseSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search your courses...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _courseSearchController,
                        builder: (_, value, __) {
                          if (value.text.isEmpty) return const SizedBox.shrink();
                          return IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: 'Clear',
                            onPressed: () {
                              _courseSearchController.clear();
                              setState(() => _searchTerm = '');
                            },
                          );
                        },
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchTerm = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _categoryFilter,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.category_outlined, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    hint: Text(
                      'All Categories',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(
                          'All Categories',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      ..._categories.map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _categoryFilter = v),
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFECEEF1)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.school_outlined,
                          size: 28,
                          color: AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchTerm.isNotEmpty || _categoryFilter != null
                            ? 'No matches found in your library.'
                            : 'No courses assigned yet. Contact your administrator to get assigned to courses.',
                        style: AppTextStyles.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = filtered[index];
                  final course = item['courseId'] ?? item;
                  final p = item['completionPercentage'];
                  final progress = (p is num) ? p.round().clamp(0, 100) : 0;
                  final status = (item['status'] ?? 'Not Started').toString();
                  return _CourseCard(
                    course: course,
                    progress: progress,
                    status: status,
                    onTap: () => _openCourse(course['_id']?.toString()),
                  );
                }, childCount: filtered.length),
              ),
            ),
        ],
      ),
    );
  }

  // ignore: unused_element - Library tab hidden; kept for potential re-enable
  Widget _buildLibraryTab() {
    if (_libraryCourses.isEmpty && !_isLoadingLibrary) {
      return Center(
        child: TextButton.icon(
          onPressed: () => _loadLibrary(),
          icon: const Icon(Icons.refresh),
          label: const Text('Load library'),
        ),
      );
    }
    if (_isLoadingLibrary) {
      return const Center(child: AppTabLoader());
    }
    final all = _libraryCourses;
    final filtered = all.where((c) {
      final title = (c['title'] ?? '').toString();
      final category = (c['category'] ?? '').toString();
      final matchSearch = _librarySearch.isEmpty ||
          title.toLowerCase().contains(_librarySearch.toLowerCase());
      final matchCat = _libraryCategoryFilter == null ||
          _libraryCategoryFilter!.isEmpty ||
          category == _libraryCategoryFilter;
      return matchSearch && matchCat;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadLibrary,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _librarySearchController,
                    decoration: InputDecoration(
                      hintText: 'Search library...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _librarySearchController,
                        builder: (_, value, __) {
                          if (value.text.isEmpty) return const SizedBox.shrink();
                          return IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: 'Clear',
                            onPressed: () {
                              _librarySearchController.clear();
                              setState(() => _librarySearch = '');
                            },
                          );
                        },
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) => setState(() => _librarySearch = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _libraryCategoryFilter,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.category_outlined, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    hint: Text(
                      'All Categories',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(
                          'All Categories',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      ..._categories.map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _libraryCategoryFilter = v),
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No courses in library or no matches.',
                  style: AppTextStyles.bodySmall,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final course = filtered[index] as Map<String, dynamic>;
                  final courseId = course['_id']?.toString();
                  final enrolled = _isEnrolled(courseId);
                  return _LibraryCourseCard(
                    course: course,
                    enrolled: enrolled,
                    onEnroll: enrolled ? null : () => _enrollAndRefresh(courseId),
                    onOpen: enrolled ? () => _openCourse(courseId) : null,
                  );
                }, childCount: filtered.length),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _enrollAndRefresh(String? courseId) async {
    if (courseId == null) return;
    final res = await _lmsService.enrollCourse(courseId);
    if (!mounted) return;
    if (res['success'] == true) {
      await _loadCourses();
      if (mounted) _tabController.animateTo(0);
      SnackBarUtils.showSnackBar(context, 'Enrolled successfully');
    } else {
      final msg = res['message']?.toString() ?? 'Enroll failed';
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.isTechnicalMessage(msg)
            ? 'Something went wrong. Please try again.'
            : msg,
      );
    }
  }

  void _openCourse(String? courseId) {
    if (courseId == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LmsCourseDetailScreen(
              courseId: courseId,
              onLmsTabSwitch: widget.onLmsTabSwitch,
            ),
          ),
        )
        .then((result) {
          if (result is int && widget.onLmsTabSwitch != null) {
            widget.onLmsTabSwitch!(result);
          }
          _loadCourses();
        });
  }
}

class _CourseCard extends StatelessWidget {
  final dynamic course;
  final int progress;
  final String status;
  final VoidCallback onTap;

  const _CourseCard({
    required this.course,
    required this.progress,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = (course['title'] ?? 'Course').toString();
    final category = (course['category'] ?? 'GENERAL').toString();
    final duration = course['completionDuration'];
    final durationText = duration != null && duration['value'] != null
        ? '${duration['value']} ${(duration['unit'] ?? 'W')[0]}'
        : 'N/A';
    final materialsCount =
        (course['materials']?.length ?? 0) + (course['contents']?.length ?? 0);
    final thumbnailUrl = course['thumbnailUrl']?.toString();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: AppConstants.getLmsFileUrl(thumbnailUrl),
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholderImage(),
                      errorWidget: (_, __, ___) => _placeholderImage(),
                    )
                  : _placeholderImage(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.3,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status == 'Completed' ? 'Completed' : '$progress% Complete',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFECEEF1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        status == 'Completed' ? AppColors.success : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '$durationText • $materialsCount ${materialsCount == 1 ? 'Lesson' : 'Lessons'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        height: 30,
                        child: ElevatedButton(
                          onPressed: status == 'Completed' ? null : onTap,
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: AppColors.successBg,
                            disabledForegroundColor: AppColors.success,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: Text(
                            status == 'Completed'
                                ? 'Completed'
                                : progress > 0
                                ? 'Resume'
                                : 'Start',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          (course['instructor'] ?? 'Admin').toString(),
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

  Widget _placeholderImage() {
    return Container(
      color: AppColors.inputFill,
      child: const Icon(Icons.image_outlined, size: 32, color: AppColors.textCaption),
    );
  }
}

class _LibraryCourseCard extends StatelessWidget {
  final Map<String, dynamic> course;
  final bool enrolled;
  final VoidCallback? onEnroll;
  final VoidCallback? onOpen;

  const _LibraryCourseCard({
    required this.course,
    required this.enrolled,
    this.onEnroll,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final title = (course['title'] ?? 'Course').toString();
    final category = (course['category'] ?? 'GENERAL').toString();
    final thumbnailUrl = course['thumbnailUrl']?.toString();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: AppConstants.getLmsFileUrl(thumbnailUrl),
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _placeholder(),
                    errorWidget: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: enrolled ? onOpen : onEnroll,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: Text(
                      enrolled ? 'Open' : 'Enroll',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.inputFill,
      child: const Icon(Icons.image_outlined, size: 32, color: AppColors.textCaption),
    );
  }
}
