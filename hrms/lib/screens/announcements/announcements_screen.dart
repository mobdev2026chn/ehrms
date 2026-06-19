import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../services/interaction_service.dart';
import '../../services/auth_service.dart';
import 'announcement_detail_screen.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_tab_loader.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<dynamic> _announcements = [];
  int _unseenEngagementTotal = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await InteractionService.instance.getAnnouncements();
      final unseen = await InteractionService.instance
          .getAnnouncementsUnseenHrTotal();
      final profileInfo = await _loadProfileInfo();
      final joiningDate = profileInfo.joiningDate;
      final myStaffId = profileInfo.staffId;
      if (!mounted) return;
      if (result['success'] == true) {
        final data = result['data'] is List
            ? result['data']
            : result['announcements'];
        final unseenData = unseen['data'];
        int unseenTotal = 0;
        if (unseenData is Map && unseenData['total'] is num) {
          unseenTotal = (unseenData['total'] as num).toInt();
        } else if (unseen['total'] is num) {
          unseenTotal = (unseen['total'] as num).toInt();
        }
        final list = data is List ? List<dynamic>.from(data) : <dynamic>[];
        // Show only relevant announcements:
        //  - expired ones are dropped entirely (they no longer add value), and
        //  - ones created before the employee joined are hidden (they predate
        //    this employee and aren't meant for them).
        final filtered = list.where((item) {
          if (!_isForThisEmployee(item, myStaffId)) return false;
          if (_isExpired(item)) return false;
          if (joiningDate != null && _isBeforeJoining(item, joiningDate)) {
            return false;
          }
          return true;
        }).toList();
        setState(() {
          _announcements = filtered;
          _unseenEngagementTotal = unseenTotal;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to load announcements',
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: Text(
          'Announcements',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _loadAnnouncements,
        color: colorScheme.primary,
        child: _isLoading
            ? _buildLoadingState(context)
            : _error != null
            ? _buildErrorState(context)
            : _announcements.isEmpty
            ? _buildEmptyState(context)
            : _buildContent(context),
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppTabLoader(),
          const SizedBox(height: 16),
          Text(
            'Loading announcements...',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.error.withOpacity(0.2),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadAnnouncements,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.5),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.15),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Icon(
                Icons.campaign_outlined,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No announcements yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for updates from your team',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.campaign_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_announcements.length} ${_announcements.length == 1 ? 'announcement' : 'announcements'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_unseenEngagementTotal > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Engagement unseen: $_unseenEngagementTotal',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final a = _announcements[index] as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildAnnouncementCard(context, a, index),
              );
            }, childCount: _announcements.length),
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementCard(
    BuildContext context,
    Map<String, dynamic> a,
    int index,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = a['title']?.toString() ?? 'Announcement';
    final description = a['description']?.toString() ?? '';
    final fromName = a['fromName']?.toString();
    final date = _parseDate(a['publishDate']) ?? _parseDate(a['effectiveDate']);
    final dateStr = date != null
        ? DateFormat('d MMM y, h:mm a').format(date)
        : '';
    final expiry = _parseDate(a['expiryDate']) ?? _parseDate(a['endDate']);
    final expiryStr = expiry != null
        ? DateFormat('d MMM y, h:mm a').format(expiry)
        : '';
    final isExpired = _isExpired(a);

    return Opacity(
      opacity: isExpired ? 0.6 : 1.0,
      child: Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AnnouncementDetailScreen(
                  announcement: a,
                  accent: AppColors.primary,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.campaign_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: colorScheme.onSurface,
                              height: 1.3,
                            ),
                          ),
                          if (isExpired) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_clock_outlined,
                                    size: 13,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Expired',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (fromName != null && fromName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'From: $fromName',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (dateStr.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Published: $dateStr',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (expiryStr.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.event_busy_rounded,
                                  size: 14,
                                  color: isExpired
                                      ? colorScheme.error
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isExpired
                                      ? 'Expired on: $expiryStr'
                                      : 'Expires: $expiryStr',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isExpired
                                        ? colorScheme.error
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Whether an announcement's expiry/end date has passed. Expired announcements
  /// stay visible in the list (marked "Expired" on the card) but engagement is
  /// disabled in the detail screen. Mirrors the dashboard expiry check.
  static bool _isExpired(dynamic item) {
    if (item is! Map) return false;

    DateTime? parseLocal(dynamic value) {
      final raw = value?.toString().trim() ?? '';
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    final now = DateTime.now();
    final expiryDate = parseLocal(item['expiryDate']);
    if (expiryDate != null && expiryDate.isBefore(now)) {
      return true;
    }

    final endDate = parseLocal(item['endDate']);
    if (endDate != null && endDate.isBefore(now)) {
      return true;
    }

    return false;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is Map && value['\$date'] != null) {
      return DateTime.tryParse(value['\$date'].toString());
    }
    return null;
  }

  /// The employee's Date of Joining and Staff `_id`, read from the profile/staff
  /// record. Both are null when unavailable so the related filters no-op.
  Future<({DateTime? joiningDate, String? staffId})> _loadProfileInfo() async {
    try {
      final result = await AuthService().getProfile();
      if (result['success'] != true || result['data'] is! Map) {
        return (joiningDate: null, staffId: null);
      }
      final data = result['data'] as Map;
      final staffData = data['staffData'];
      final rawJoin = (staffData is Map ? staffData['joiningDate'] : null) ??
          data['joiningDate'];
      final staffId = _idString(
            (staffData is Map ? staffData['_id'] : null) ??
                data['_id'] ??
                data['staffId'],
          );
      return (joiningDate: _parseDate(rawJoin), staffId: staffId);
    } catch (_) {
      return (joiningDate: null, staffId: null);
    }
  }

  /// Normalize an id that may be a String, an ObjectId map (`{$oid: ...}`), or a
  /// populated staff object (`{_id: ...}`) down to its hex string.
  static String? _idString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.trim();
    if (value is Map) {
      return _idString(
        value['_id'] ?? value['\$oid'] ?? value['id'] ?? value['staffId'],
      );
    }
    return value.toString().trim();
  }

  /// Whether this announcement is meant for the current employee.
  ///
  /// Targeting is decided by the recipient list the payload carries
  /// (`targetStaffIds`/`assignedTo`/`recipients`/`staffIds`). When no recipient
  /// list is present the announcement is company-wide and shown to everyone.
  /// When it explicitly targets specific staff, it is shown ONLY if the current
  /// employee is in that list — this is the app-side guard against the backend
  /// returning a personally-targeted announcement to the wrong staff member.
  static bool _isForThisEmployee(dynamic item, String? myStaffId) {
    if (item is! Map) return true;
    final targets = <String>{};
    for (final key in const [
      'targetStaffIds',
      'assignedTo',
      'recipients',
      'staffIds',
      'targetStaff',
    ]) {
      final v = item[key];
      if (v is List) {
        for (final e in v) {
          final id = _idString(e);
          if (id != null && id.isNotEmpty) targets.add(id);
        }
      }
    }
    // No explicit recipient list → company-wide → visible to all.
    if (targets.isEmpty) return true;
    // Targeted: only the listed staff may see it. If we can't resolve the current
    // staff id, hide rather than risk leaking a targeted announcement.
    if (myStaffId == null || myStaffId.isEmpty) return false;
    return targets.contains(myStaffId);
  }

  /// Whether an announcement was created before the employee joined. Uses the
  /// announcement's creation/publish date (createdAt → publishDate →
  /// effectiveDate); when none is present the announcement is kept (not hidden).
  static bool _isBeforeJoining(dynamic item, DateTime joiningDate) {
    if (item is! Map) return false;
    final created = _parseDate(item['createdAt']) ??
        _parseDate(item['publishDate']) ??
        _parseDate(item['effectiveDate']);
    if (created == null) return false;
    // Compare at day granularity so an announcement created on the joining day
    // is still shown.
    final joinDay =
        DateTime(joiningDate.year, joiningDate.month, joiningDate.day);
    return created.toLocal().isBefore(joinDay);
  }
}
