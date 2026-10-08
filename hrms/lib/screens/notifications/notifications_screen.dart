// lib/screens/notifications/notifications_screen.dart
//
// Notifications list for staff and admin logins, matching the web notifications pages:
// server-side paging (20 per page), search and All/Unread/Read + category filters, unread
// counts per category from the server, tap = mark read + open the related screen, per-row
// mark read/unread and delete, mark all read, clear read / clear everything.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_colors.dart';
import '../../config/app_route_observer.dart';
import '../../config/app_text_styles.dart';
import '../../services/api_client.dart';
import '../../services/fcm_service.dart';
import '../../services/task_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_tab_loader.dart';
import '../admin/approvals/admin_approvals_screen.dart';
import '../admin/approvals/admin_leave_approvals_screen.dart';
import '../admin/approvals/admin_permission_approvals_screen.dart';
import '../admin/approvals/admin_punch_approvals_screen.dart';
import '../admin/approvals/admin_reimbursement_approvals_screen.dart';
import '../admin/approvals/admin_payslip_approvals_screen.dart';
import '../admin/loans/admin_loan_request_screen.dart';
import '../admin/loans/admin_loans_screen.dart';
import '../geo/my_tasks_screen.dart';
import '../geo/task_detail_screen.dart';
import '../profile/profile_screen.dart';
import '../requests/my_requests_screen.dart';

class NotificationItemModel {
  final String id;
  final String title;
  final String message;
  final String staffSubtitle;
  final String type; // admin: 'leave' | 'permission' | 'reimbursement' | 'payslip' | 'loan'
  /// Staff notifications (HRMSbackend): 'requests' | 'tasks' | 'profile' | 'exit'.
  final String module;
  /// The record the notification is about (staff: the task for 'tasks').
  final String referenceId;
  final DateTime createdAt;
  bool isRead;

  NotificationItemModel({
    required this.id,
    required this.title,
    required this.message,
    required this.staffSubtitle,
    required this.type,
    this.module = '',
    this.referenceId = '',
    required this.createdAt,
    this.isRead = false,
  });

  /// Same as the web page: "Just now", "5m ago", "3h ago", "2d ago" for a week, then a date.
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays >= 7) return DateFormat('d MMM yyyy').format(createdAt);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  factory NotificationItemModel.fromJson(Map<String, dynamic> json) {
    final message = (json['message'] ?? '').toString();
    final staffObj = json['staffId'] is Map ? json['staffId'] as Map : const {};
    final sName = (staffObj['name'] ??
            '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim())
        .toString();
    final empId = (staffObj['employeeId'] ?? '').toString();
    final dept = (staffObj['department'] is Map
            ? staffObj['department']['name']
            : (staffObj['department'] ?? ''))
        .toString();
    var staffSubtitle = [sName, empId, dept].where((s) => s.trim().isNotEmpty).join(' · ');
    if (staffSubtitle.isEmpty && message.contains('has requested')) {
      staffSubtitle = message.split(' has requested')[0];
    }
    final ref = json['referenceId'];
    return NotificationItemModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Notification').toString(),
      message: message,
      staffSubtitle: staffSubtitle,
      type: (json['type'] ?? '').toString().toLowerCase(),
      module: (json['module'] ?? '').toString().toLowerCase(),
      referenceId: (ref is Map ? (ref['_id'] ?? '') : (ref ?? '')).toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      isRead: json['status'] == 'read' || json['isRead'] == true,
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver, RouteAware {
  static const _pageSize = 20;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<NotificationItemModel> _notifications = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _pages = 1;

  // Server counts (meta), as on web.
  int _unreadTotal = 0;
  Map<String, int> _unreadByCategory = {};

  String _searchQuery = '';
  String _statusFilter = 'All'; // 'All' | 'Unread' | 'Read'
  String _typeFilter = 'all'; // 'all' or a key from [_categoryFilters]

  ModalRoute<void>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() => _load(showLoader: false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(showLoader: false);
  }

  /// HRMSbackend keeps staff and admin notifications apart: a staff login must use
  /// `/staff/notifications`, admins `/admin/notifications`.
  bool _isAdmin = false;
  String get _base => _isAdmin ? '/admin/notifications' : '/staff/notifications';

  Future<void> _resolveRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null) return;
      final user = jsonDecode(userStr);
      if (user is! Map) return;
      final role = (user['role'] ?? '').toString().toLowerCase().replaceAll(' ', '');
      _isAdmin = role == 'admin' || role == 'superadmin';
    } catch (_) {}
  }

  static bool _ok(Response<dynamic> res) => res.data is Map && res.data['success'] == true;

  Map<String, dynamic> _query(int page) => {
        'page': page,
        'limit': _pageSize,
        if (_statusFilter == 'Unread') 'status': 'unread',
        if (_statusFilter == 'Read') 'status': 'read',
        if (_typeFilter != 'all') (_isAdmin ? 'type' : 'module'): _typeFilter,
        if (_searchQuery.trim().isNotEmpty) 'search': _searchQuery.trim(),
      };

  /// First page for the current filters (replaces the list).
  Future<void> _load({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);
    await _resolveRole();
    try {
      final res = await _api.request<dynamic>(_base, queryParameters: _query(1));
      if (_ok(res)) {
        _applyPage(res.data as Map, page: 1, append: false);
      } else if (showLoader && mounted) {
        SnackBarUtils.showSnackBar(context, 'Failed to load notifications', isError: true);
      }
    } catch (_) {
      if (showLoader && mounted) {
        SnackBarUtils.showSnackBar(context, 'Failed to load notifications', isError: true);
      }
    }
    // Local push watermark only; nothing is marked read on the server by opening the list.
    await FcmService.markNotificationsSeen();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _pages) return;
    setState(() => _loadingMore = true);
    try {
      final res = await _api.request<dynamic>(_base, queryParameters: _query(_page + 1));
      if (_ok(res)) _applyPage(res.data as Map, page: _page + 1, append: true);
    } catch (_) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Failed to load more', isError: true);
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _applyPage(Map body, {required int page, required bool append}) {
    final items = ((body['data'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => NotificationItemModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final meta = body['meta'] is Map ? body['meta'] as Map : const {};
    final byCategory = meta[_isAdmin ? 'unreadByType' : 'unreadByModule'];
    if (!mounted) return;
    setState(() {
      _notifications = append ? [..._notifications, ...items] : items;
      _page = page;
      _pages = (meta['pages'] as num?)?.toInt() ?? 1;
      _unreadTotal = (meta['unread'] as num?)?.toInt() ??
          (body['unreadCount'] as num?)?.toInt() ??
          _notifications.where((n) => !n.isRead).length;
      _unreadByCategory = byCategory is Map
          ? byCategory.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0))
          : {};
    });
  }

  void _setFilter({String? status, String? type}) {
    setState(() {
      if (status != null) _statusFilter = status;
      if (type != null) _typeFilter = type;
    });
    _load(showLoader: false);
  }

  void _onSearchChanged(String v) {
    setState(() => _searchQuery = v);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _load(showLoader: false));
  }

  /// Category chips: staff notifications are grouped by `module`, admin ones by `type`
  /// (same chips as the web pages).
  List<({String label, String key, IconData icon})> get _categoryFilters => _isAdmin
      ? const [
          (label: 'Leave', key: 'leave', icon: Icons.calendar_month_outlined),
          (label: 'Permission', key: 'permission', icon: Icons.access_time_rounded),
          (label: 'Reimbursement', key: 'reimbursement', icon: Icons.receipt_long_outlined),
          (label: 'Payslip', key: 'payslip', icon: Icons.description_outlined),
          (label: 'Loan', key: 'loan', icon: Icons.account_balance_outlined),
        ]
      : const [
          (label: 'Requests', key: 'requests', icon: Icons.assignment_outlined),
          (label: 'Profile', key: 'profile', icon: Icons.person_outline_rounded),
          (label: 'Tasks', key: 'tasks', icon: Icons.task_alt_rounded),
        ];

  String _categoryOf(NotificationItemModel n) => _isAdmin ? n.type : n.module;

  /// Keeps the server counts in step after a local read/unread change.
  void _adjustUnread(NotificationItemModel n, int delta) {
    _unreadTotal = (_unreadTotal + delta).clamp(0, 1 << 30);
    final key = _categoryOf(n);
    if (_unreadByCategory.containsKey(key)) {
      _unreadByCategory[key] = (_unreadByCategory[key]! + delta).clamp(0, 1 << 30);
    }
  }

  Future<void> _setRead(NotificationItemModel item, bool read) async {
    if (item.isRead == read) return;
    setState(() {
      item.isRead = read;
      _adjustUnread(item, read ? -1 : 1);
    });
    var ok = false;
    try {
      ok = _ok(await _api.request<dynamic>('$_base/${item.id}/${read ? 'read' : 'unread'}', method: 'PUT'));
    } catch (_) {}
    if (!ok && mounted) {
      setState(() {
        item.isRead = !read;
        _adjustUnread(item, read ? 1 : -1);
      });
      SnackBarUtils.showSnackBar(context, 'Could not update the notification', isError: true);
    }
  }

  Future<void> _handleMarkAllAsRead() async {
    var ok = false;
    try {
      ok = _ok(await _api.request<dynamic>(_base, method: 'PUT'));
    } catch (_) {}
    if (!mounted) return;
    if (ok) {
      SnackBarUtils.showSnackBar(context, 'All notifications marked as read');
    } else {
      SnackBarUtils.showSnackBar(context, 'Could not mark notifications as read', isError: true);
    }
    _load(showLoader: false);
  }

  /// Web's "Clear" dialog: remove read notifications only, or everything.
  Future<void> _handleClear() async {
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear notifications'),
        content: const Text('Remove the notifications you have already read, or clear everything?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'read'), child: const Text('Clear read only')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear everything'),
          ),
        ],
      ),
    );
    if (scope == null) return;
    var ok = false;
    try {
      ok = _ok(await _api.request<dynamic>(
        _base,
        method: 'DELETE',
        queryParameters: scope == 'all' ? {'scope': 'all'} : null,
      ));
    } catch (_) {}
    if (!mounted) return;
    SnackBarUtils.showSnackBar(
      context,
      ok ? (scope == 'all' ? 'All notifications cleared' : 'Read notifications cleared') : 'Could not clear notifications',
      isError: !ok,
    );
    _load(showLoader: false);
  }

  /// Tap: mark read and open what the notification is about (same targets as web).
  Future<void> _handleNotificationTap(NotificationItemModel item) async {
    unawaited(_setRead(item, true));
    if (_isAdmin) {
      final Widget screen;
      switch (item.type) {
        case 'leave':
          screen = const AdminLeaveApprovalsScreen();
        case 'permission':
          screen = const AdminPermissionApprovalsScreen();
        case 'punch':
          screen = const AdminPunchApprovalsScreen();
        case 'reimbursement':
        case 'expense':
          screen = const AdminReimbursementApprovalsScreen();
        case 'payslip':
          screen = const AdminPayslipApprovalsScreen();
        case 'loan':
          // The notification's referenceId is the loan request.
          screen = item.referenceId.isNotEmpty
              ? AdminLoanRequestScreen(requestId: item.referenceId)
              : const AdminLoansScreen();
        default:
          // Loan and anything new: the approvals list, as on web.
          screen = const AdminApprovalsScreen();
      }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      return;
    }
    switch (item.module) {
      case 'tasks':
        await _openTask(item.referenceId);
      case 'profile':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen(dashboardTabIndex: 3)),
        );
      default:
        // 'requests' and anything else (web: /staff/requests).
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyRequestsScreen()));
    }
  }

  /// The task itself when it can be loaded, otherwise the task list (web: /staff/tasks[/:id]).
  Future<void> _openTask(String taskId) async {
    if (taskId.isNotEmpty) {
      try {
        final task = await TaskService().getTaskById(taskId);
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)));
        return;
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTasksScreen()));
  }

  Future<void> _handleDeleteSingle(NotificationItemModel item) async {
    final index = _notifications.indexWhere((n) => n.id == item.id);
    setState(() {
      _notifications.removeWhere((n) => n.id == item.id);
      if (!item.isRead) _adjustUnread(item, -1);
    });
    var removed = false;
    try {
      removed = _ok(await _api.request<dynamic>('$_base/${item.id}', method: 'DELETE'));
    } catch (_) {}
    if (!mounted) return;
    if (removed) {
      SnackBarUtils.showSnackBar(context, 'Notification removed');
    } else {
      setState(() {
        _notifications.insert(index < 0 ? 0 : index.clamp(0, _notifications.length), item);
        if (!item.isRead) _adjustUnread(item, 1);
      });
      SnackBarUtils.showSnackBar(context, 'Failed to remove notification', isError: true);
    }
  }

  /// Long-press actions for one row (web: per-row read/unread toggle and delete).
  Future<void> _showRowActions(NotificationItemModel item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              ListTile(
                leading: Icon(
                  item.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
                  color: AppColors.textPrimary,
                ),
                title: Text(item.isRead ? 'Mark as unread' : 'Mark as read', style: AppTextStyles.label),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () => Navigator.pop(ctx, 'toggle'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: Text('Delete', style: AppTextStyles.label.copyWith(color: AppColors.error)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == 'toggle') await _setRead(item, !item.isRead);
    if (action == 'delete') await _handleDeleteSingle(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Notifications'),
        actions: [
          if (_unreadTotal > 0)
            TextButton.icon(
              onPressed: _handleMarkAllAsRead,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Mark all read', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _handleClear,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _load(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      textAlignVertical: TextAlignVertical.center,
                      style: AppTextStyles.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _isAdmin ? 'Search employee, title or message...' : 'Search title or message...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textCaption),
                                splashRadius: 18,
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 40,
                    decoration: BoxDecoration(color: const Color(0xFFECEEF1), borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        Expanded(child: _statusTabItem('All', null)),
                        Expanded(child: _statusTabItem('Unread', _unreadTotal)),
                        Expanded(child: _statusTabItem('Read', null)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Category chips with UNREAD counts, as on web.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _typeChip('all', 'All', _unreadTotal, Icons.layers_outlined),
                        for (final f in _categoryFilters) ...[
                          const SizedBox(width: 8),
                          _typeChip(f.key, f.label, _unreadByCategory[f.key] ?? 0, f.icon),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_notifications.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFECEEF1)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.notifications_none_rounded, size: 28, color: AppColors.primaryText),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isAdmin ? 'No notifications' : 'You have no notifications yet.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.headingSmall,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFECEEF1)),
                        boxShadow: kSoftCardShadow,
                      ),
                      child: Column(
                        children: [
                          for (final (i, item) in _notifications.indexed) ...[
                            if (i > 0) const Divider(height: 1, thickness: 1, color: Color(0xFFECEEF1)),
                            _buildNotificationCard(item),
                          ],
                        ],
                      ),
                    ),
                    if (_page < _pages)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 16),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: _loadingMore ? null : _loadMore,
                            icon: _loadingMore
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.expand_more_rounded, size: 18),
                            label: const Text('Load more'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _statusTabItem(String label, int? badgeCount) {
    final isSelected = _statusFilter == label;
    return InkWell(
      onTap: () => _setFilter(status: label),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected ? kSoftCardShadow : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ),
            if (badgeCount != null && badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(999)),
                child: Text('$badgeCount', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandDark)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Category chip; the badge is the category's unread count (hidden at 0), as on web.
  Widget _typeChip(String key, String label, int unread, IconData icon) {
    final color = AppColors.primary;
    final bg = AppColors.primary.withValues(alpha: 0.12);
    final isSelected = _typeFilter == key;
    return InkWell(
      onTap: () => _setFilter(type: key),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? bg : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? color : const Color(0xFFE2E5EA)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? AppColors.primaryText : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.primaryText : AppColors.textPrimary,
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? color : AppColors.brandLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$unread',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.onPrimary : AppColors.brandDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Leading icon for a row: the icon of its category chip (presentation only).
  IconData _categoryIcon(NotificationItemModel n) {
    final key = _categoryOf(n);
    for (final f in _categoryFilters) {
      if (f.key == key) return f.icon;
    }
    return Icons.notifications_none_rounded;
  }

  /// One row: unread rows are tinted with an amber dot; tap = mark read + open; long-press =
  /// mark read/unread or delete; swipe left deletes.
  Widget _buildNotificationCard(NotificationItemModel item) {
    return Dismissible(
      key: ValueKey('notif_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.errorBg,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
      ),
      onDismissed: (_) => _handleDeleteSingle(item),
      child: Material(
        color: item.isRead ? AppColors.surface : AppColors.primary.withValues(alpha: 0.06),
        child: InkWell(
          onTap: () => _handleNotificationTap(item),
          onLongPress: () => _showRowActions(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: item.isRead ? AppColors.background : AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _categoryIcon(item),
                    size: 20,
                    color: item.isRead ? AppColors.textSecondary : AppColors.primaryText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: AppTextStyles.headingSmall.copyWith(fontSize: 14),
                      ),
                      if (item.message.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.message,
                          style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF374151)),
                        ),
                      ],
                      if (_isAdmin && item.staffSubtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.staffSubtitle,
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        item.timeAgo,
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 18,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, left: 10),
                    child: item.isRead
                        ? null
                        : Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
