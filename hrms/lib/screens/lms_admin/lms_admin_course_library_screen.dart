// hrms/lib/screens/lms_admin/lms_admin_course_library_screen.dart
// Admin → Course Library. Stats + search/filter + course grid.
// Mirrors web LMS "Course Library". Read-only on mobile; create/edit/delete
// surface an informational message (managed from web admin console).

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/constants.dart';
import '../../services/lms_admin_service.dart';
import '../../widgets/app_tab_loader.dart';
import 'lms_admin_utils.dart';
import 'widgets/lms_admin_stat_card.dart';

class LmsAdminCourseLibraryScreen extends StatefulWidget {
  const LmsAdminCourseLibraryScreen({super.key});

  @override
  State<LmsAdminCourseLibraryScreen> createState() =>
      _LmsAdminCourseLibraryScreenState();
}

class _LmsAdminCourseLibraryScreenState
    extends State<LmsAdminCourseLibraryScreen> {
  final LmsAdminService _service = LmsAdminService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _courses = [];
  List<String> _categories = [];
  String _search = '';
  String? _categoryFilter;
  String? _statusFilter; // Published / Draft

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final res = await _service.getCourses();
    final cats = await _service.getCategories();
    if (!mounted) return;
    setState(() {
      _courses = LmsAdminUtils.asMapList(res['data'], ['courses', 'data']);
      _categories = LmsAdminUtils.categoryNames(cats['data']);
      if (_categories.isEmpty) {
        _categories = _courses
            .map((c) => (c['category'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
      }
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    return _courses.where((c) {
      final title = (c['title'] ?? '').toString().toLowerCase();
      final category = (c['category'] ?? '').toString();
      final published = c['isPublished'] == true ||
          (c['status'] ?? '').toString().toLowerCase() == 'published';
      final matchSearch = _search.isEmpty || title.contains(_search.toLowerCase());
      final matchCat = _categoryFilter == null || category == _categoryFilter;
      final matchStatus = _statusFilter == null ||
          (_statusFilter == 'Published' ? published : !published);
      return matchSearch && matchCat && matchStatus;
    }).toList();
  }

  int get _totalEnrollments {
    var sum = 0;
    for (final c in _courses) {
      sum += LmsAdminUtils.toInt(
        c['enrollmentCount'] ??
            c['enrolledCount'] ??
            c['enrollments'] ??
            (c['enrolledUsers'] is List ? (c['enrolledUsers'] as List).length : 0),
      );
    }
    return sum;
  }

  int get _mandatoryCount =>
      _courses.where((c) => c['isMandatory'] == true).length;

  /// Distinct categories actually present in the course list.
  Set<String> get _distinctCategories => _courses
      .map((c) => (c['category'] ?? '').toString())
      .where((s) => s.isNotEmpty)
      .toSet();

  void _comingFromWeb() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Course authoring is managed from the web admin console.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: AppTabLoader());
    final filtered = _filtered;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Heading + Create button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Course Library',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Manage and review all LMS courses in one place.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _comingFromWeb,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create'),
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
          const SizedBox(height: 4),

          // Stats
          LmsAdminStatRow(
            cards: [
              LmsAdminStatCard(
                label: 'Total Courses',
                value: '${_courses.length}',
                icon: Icons.menu_book_rounded,
                iconColor: AppColors.info,
                iconBg: AppColors.infoBg,
              ),
              LmsAdminStatCard(
                label: 'Categories',
                value: '${_distinctCategories.length}',
                icon: Icons.category_rounded,
                iconColor: AppColors.success,
                iconBg: AppColors.successBg,
              ),
              LmsAdminStatCard(
                label: 'Enrollments',
                value: '$_totalEnrollments',
                icon: Icons.groups_rounded,
              ),
              LmsAdminStatCard(
                label: 'Mandatory Courses',
                value: '$_mandatoryCount',
                icon: Icons.verified_rounded,
                iconColor: AppColors.indigo,
                iconBg: AppColors.indigoBg,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search + filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LmsAdminUtils.searchField(
                  hint: 'Search courses...',
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LmsAdminUtils.dropdown(
                        hint: 'Category',
                        value: _categoryFilter,
                        items: _categories,
                        onChanged: (v) => setState(() => _categoryFilter = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LmsAdminUtils.dropdown(
                        hint: 'Status',
                        value: _statusFilter,
                        items: const ['Published', 'Draft'],
                        onChanged: (v) => setState(() => _statusFilter = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (filtered.isEmpty)
            LmsAdminUtils.emptyState('No courses found.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.74,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _CourseCard(
                course: filtered[i],
                onTap: _comingFromWeb,
              ),
            ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final Map<String, dynamic> course;
  final VoidCallback onTap;
  const _CourseCard({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (course['title'] ?? 'Course').toString();
    final category = (course['category'] ?? 'GENERAL').toString();
    final mandatory = course['isMandatory'] == true;
    final lessons = LmsAdminUtils.toInt(
      course['lessonCount'] ??
          (course['materials'] is List ? (course['materials'] as List).length : 0) +
              (course['contents'] is List ? (course['contents'] as List).length : 0),
    );
    final thumb = course['thumbnailUrl']?.toString();
    final instructor = (course['instructor'] ?? 'Admin').toString();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: thumb != null && thumb.isNotEmpty
                      ? Image.network(
                          AppConstants.getLmsFileUrl(thumb),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _ph(),
                        )
                      : _ph(),
                ),
                if (mandatory)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.indigo,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Mandatory',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$lessons ${lessons == 1 ? 'Lesson' : 'Lessons'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 13, color: AppColors.textCaption),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            instructor,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textCaption,
                            ),
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

  Widget _ph() => Container(
        color: AppColors.inputFill,
        child: const Icon(Icons.image_outlined, size: 36, color: AppColors.textHint),
      );
}
