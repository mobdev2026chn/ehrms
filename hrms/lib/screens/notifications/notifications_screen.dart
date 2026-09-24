// lib/screens/notifications/notifications_screen.dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_colors.dart';
import '../../config/app_route_observer.dart';
import '../../services/api_client.dart';
import '../../services/fcm_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_tab_loader.dart';
import '../admin/approvals/admin_leave_approvals_screen.dart';
import '../admin/approvals/admin_permission_approvals_screen.dart';
import '../admin/approvals/admin_punch_approvals_screen.dart';
import '../admin/approvals/admin_reimbursement_approvals_screen.dart';
import '../admin/approvals/admin_payslip_approvals_screen.dart';

class NotificationItemModel {
  final String id;
  final String title;
  final String message;
  final String staffSubtitle;
  final String type; // 'leave' | 'permission' | 'reimbursement' | 'payslip' | 'punch' | 'system'
  /// Staff notifications (HRMSbackend): 'requests' | 'tasks' | 'profile' | 'exit'.
  final String module;
  final String timeAgo;
  final DateTime createdAt;
  bool isRead;

  NotificationItemModel({
    required this.id,
    required this.title,
    required this.message,
    required this.staffSubtitle,
    required this.type,
    this.module = '',
    required this.timeAgo,
    required this.createdAt,
    this.isRead = false,
  });

  factory NotificationItemModel.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? 'Notification').toString();
    final message = (json['message'] ?? '').toString();
    final type = (json['type'] ?? 'leave').toString().toLowerCase();
    final module = (json['module'] ?? '').toString().toLowerCase();
    final isRead = json['status'] == 'read' || json['isRead'] == true;

    final createdDateStr = (json['createdAt'] ?? '').toString();
    final parsed = DateTime.tryParse(createdDateStr);
    DateTime created = parsed?.toLocal() ?? DateTime.now();

    // Same style as the web: relative within a day, then a short date ("4 Sep").
    final now = DateTime.now();
    final diff = now.difference(created);
    String timeAgo = 'Just now';
    if (diff.inHours >= 24) {
      timeAgo = DateFormat(created.year == now.year ? 'd MMM' : 'd MMM yyyy').format(created);
    } else if (diff.inHours >= 1) {
      timeAgo = '${diff.inHours}h ago';
    } else if (diff.inMinutes >= 1) {
      timeAgo = '${diff.inMinutes}m ago';
    }

    final staffObj = json['staffId'] is Map ? json['staffId'] : json;
    final sName = (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString();
    final empId = (staffObj['employeeId'] ?? '').toString();
    final dept = (staffObj['department'] is Map ? staffObj['department']['name'] : (staffObj['department'] ?? '')).toString();

    String staffSubtitle = sName.isNotEmpty
        ? [sName, empId, dept].where((s) => s.trim().isNotEmpty).join(' • ')
        : '';
    if (staffSubtitle.isEmpty && message.contains('has requested')) {
      staffSubtitle = message.split(' has requested')[0];
    }

    return NotificationItemModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: title,
      message: message,
      staffSubtitle: staffSubtitle,
      type: type,
      module: module,
      timeAgo: timeAgo,
      createdAt: created,
      isRead: isRead,
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  List<NotificationItemModel> _notifications = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'All'; // 'All' | 'Unread' | 'Read'
  String _typeFilter = 'all'; // 'all' or a key from [_categoryFilters]
  int _displayedCount = 10;

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
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _load(showLoader: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(showLoader: false);
    }
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

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);
    await _resolveRole();

    try {
      final res = await _api.request<dynamic>(_base, queryParameters: {'limit': 100});
      if (_ok(res)) {
        final list = (res.data['data'] as List?) ?? [];
        if (mounted) {
          setState(() {
            _notifications = list
                .whereType<Map>()
                .map((e) => NotificationItemModel.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          });
        }
      } else if (showLoader && mounted) {
        SnackBarUtils.showSnackBar(context, 'Failed to load notifications', isError: true);
      }
    } catch (_) {
      if (showLoader && mounted) {
        SnackBarUtils.showSnackBar(context, 'Failed to load notifications', isError: true);
      }
    }

    await FcmService.markNotificationsSeen();

    if (showLoader && mounted) {
      setState(() => _isLoading = false);
    }
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Category chips: staff notifications are grouped by `module`, admin ones by `type`.
  List<({String label, String key, IconData icon})> get _categoryFilters => _isAdmin
      ? const [
          (label: 'Leave', key: 'leave', icon: Icons.calendar_month_outlined),
          (label: 'Permission', key: 'permission', icon: Icons.access_time_rounded),
          (label: 'Reimbursement', key: 'reimbursement', icon: Icons.receipt_long_outlined),
          (label: 'Payslip', key: 'payslip', icon: Icons.description_outlined),
        ]
      : const [
          (label: 'Requests', key: 'requests', icon: Icons.assignment_outlined),
          (label: 'Tasks', key: 'tasks', icon: Icons.task_alt_rounded),
          (label: 'Profile', key: 'profile', icon: Icons.person_outline_rounded),
          (label: 'Exit', key: 'exit', icon: Icons.logout_rounded),
        ];

  String _categoryOf(NotificationItemModel n) {
    if (!_isAdmin) return n.module;
    return n.type == 'expense' ? 'reimbursement' : n.type;
  }

  int _countForCategory(String key) =>
      _notifications.where((n) => _categoryOf(n) == key).length;

  List<NotificationItemModel> get _filteredNotifications {
    return _notifications.where((n) {
      final matchesSearch = _searchQuery.isEmpty ||
          n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.message.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.staffSubtitle.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _statusFilter == 'All' ||
          (_statusFilter == 'Unread' && !n.isRead) ||
          (_statusFilter == 'Read' && n.isRead);

      final matchesType = _typeFilter == 'all' || _categoryOf(n) == _typeFilter;

      return matchesSearch && matchesStatus && matchesType;
    }).toList();
  }

  Future<void> _handleMarkAllAsRead() async {
    setState(() {
      for (var n in _notifications) {
        n.isRead = true;
      }
    });
    try {
      await _api.request<dynamic>(_base, method: 'PUT');
    } catch (_) {}
    if (mounted) SnackBarUtils.showSnackBar(context, 'All notifications marked as read');
  }

  void _handleNotificationTap(NotificationItemModel item) {
    // Mark single as read
    setState(() {
      item.isRead = true;
    });
    _api.request<dynamic>('$_base/${item.id}/read', method: 'PUT').catchError(
      (_) => Response<dynamic>(requestOptions: RequestOptions()),
    );

    // Admin approval screens only apply to admin notifications.
    if (!_isAdmin) return;
    final type = item.type.toLowerCase();
    if (type == 'leave') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminLeaveApprovalsScreen()));
    } else if (type == 'permission') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPermissionApprovalsScreen()));
    } else if (type == 'punch') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPunchApprovalsScreen()));
    } else if (type == 'reimbursement' || type == 'expense') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminReimbursementApprovalsScreen()));
    } else if (type == 'payslip') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPayslipApprovalsScreen()));
    }
  }

  Future<void> _handleDeleteSingle(NotificationItemModel item) async {
    final index = _notifications.indexWhere((n) => n.id == item.id);
    setState(() {
      _notifications.removeWhere((n) => n.id == item.id);
    });
    var removed = false;
    try {
      removed = _ok(await _api.request<dynamic>('$_base/${item.id}', method: 'DELETE'));
    } catch (_) {}
    if (!mounted) return;
    if (removed) {
      SnackBarUtils.showSnackBar(context, 'Notification removed');
    } else {
      setState(() => _notifications.insert(index < 0 ? 0 : index.clamp(0, _notifications.length), item));
      SnackBarUtils.showSnackBar(context, 'Failed to remove notification', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unreadCount;
    final total = _notifications.length;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (unread > 0)
            TextButton.icon(
              onPressed: _handleMarkAllAsRead,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Mark all read', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          const SizedBox(width: 4),
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
                  // Filters: search, status tabs, type chips (no header card)
                  Column(
                      children: [
                        // Search bar (full width)
                        SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _searchQuery = v),
                            textAlignVertical: TextAlignVertical.center,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              hintText: 'Search title or message...',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              suffixIcon: _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                                      splashRadius: 18,
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Tabs: All | Unread | Read (full width, equal segments)
                        Container(
                          height: 38,
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.all(3),
                          child: Row(
                            children: [
                              Expanded(child: _statusTabItem('All', null)),
                              Expanded(child: _statusTabItem('Unread', unread)),
                              Expanded(child: _statusTabItem('Read', null)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Category filter chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _typeChip('all', 'All', total, Icons.layers_outlined),
                              for (final f in _categoryFilters) ...[
                                const SizedBox(width: 6),
                                _typeChip(f.key, f.label, _countForCategory(f.key), f.icon),
                              ],
                            ],
                          ),
                        ),
                      ],
                  ),
                  const SizedBox(height: 14),

                  // Notifications List
                  if (_filteredNotifications.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: const [
                          Icon(Icons.notifications_none_rounded, size: 40, color: Color(0xFF94A3B8)),
                          SizedBox(height: 8),
                          Text('No notifications found', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          for (final (i, item) in _filteredNotifications.take(_displayedCount).indexed) ...[
                            if (i > 0) const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                            _buildNotificationCard(item),
                          ],
                        ],
                      ),
                    ),
                    if (_filteredNotifications.length > _displayedCount)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _displayedCount += 10;
                              });
                            },
                            icon: const Icon(Icons.expand_more_rounded, size: 18),
                            label: Text(
                              'Load More (${_filteredNotifications.length - _displayedCount} remaining)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEFAA1F),
                              side: const BorderSide(color: Color(0xFFFDE68A)),
                              backgroundColor: const Color(0xFFFFFBEB),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
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
      onTap: () => setState(() => _statusFilter = label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : null,
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
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                ),
              ),
            ),
            if (badgeCount != null && badgeCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                child: Text('$badgeCount', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String key, String label, int count, IconData icon) {
    const color = Color(0xFFEFAA1F);
    const bg = Color(0xFFFFFBEB);
    final isSelected = _typeFilter == key;
    return InkWell(
      onTap: () => setState(() => _typeFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? bg : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: isSelected ? color : const Color(0xFF64748B)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: isSelected ? color : const Color(0xFF475569)),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? color : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: isSelected ? Colors.white : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One row, styled like the web notification dropdown: unread rows are tinted with an
  /// amber dot; tap marks read (and opens the module for admins); swipe left deletes.
  Widget _buildNotificationCard(NotificationItemModel item) {
    return Dismissible(
      key: ValueKey('notif_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: const Color(0xFFFEE2E2),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
      ),
      onDismissed: (_) => _handleDeleteSingle(item),
      child: Material(
        color: item.isRead ? Colors.white : const Color(0xFFFFFBEB),
        child: InkWell(
          onTap: () => _handleNotificationTap(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: item.isRead
                        ? null
                        : Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEFAA1F),
                              shape: BoxShape.circle,
                            ),
                          ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (item.message.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.message,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                      if (_isAdmin && item.staffSubtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.staffSubtitle,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        item.timeAgo,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
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
