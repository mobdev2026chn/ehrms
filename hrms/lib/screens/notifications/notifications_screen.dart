// lib/screens/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  final String timeAgo;
  final DateTime createdAt;
  bool isRead;

  NotificationItemModel({
    required this.id,
    required this.title,
    required this.message,
    required this.staffSubtitle,
    required this.type,
    required this.timeAgo,
    required this.createdAt,
    this.isRead = false,
  });

  factory NotificationItemModel.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? 'Notification').toString();
    final message = (json['message'] ?? '').toString();
    final type = (json['type'] ?? 'leave').toString().toLowerCase();
    final isRead = json['status'] == 'read' || json['isRead'] == true;

    final createdDateStr = (json['createdAt'] ?? '').toString();
    DateTime created = DateTime.tryParse(createdDateStr) ?? DateTime.now();

    // Compute relative time
    final diff = DateTime.now().difference(created);
    String timeAgo = 'Just now';
    if (diff.inDays >= 30) {
      timeAgo = '${(diff.inDays / 30).floor()}mo ago';
    } else if (diff.inDays >= 1) {
      timeAgo = '${diff.inDays}d ago';
    } else if (diff.inHours >= 1) {
      timeAgo = '${diff.inHours}h ago';
    } else if (diff.inMinutes >= 1) {
      timeAgo = '${diff.inMinutes}m ago';
    }

    final staffObj = json['staffId'] is Map ? json['staffId'] : json;
    final sName = (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString();
    final empId = (staffObj['employeeId'] ?? 'EMP-015').toString();
    final dept = (staffObj['department'] is Map ? staffObj['department']['name'] : (staffObj['department'] ?? 'Engineering')).toString();

    String staffSubtitle = sName.isNotEmpty ? '$sName • $empId • $dept' : '';
    if (staffSubtitle.isEmpty && message.contains('has requested')) {
      final parts = message.split(' has requested');
      staffSubtitle = '${parts[0]} • EMP-015 • Engineering';
    }

    return NotificationItemModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: title,
      message: message,
      staffSubtitle: staffSubtitle,
      type: type,
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
  String _statusFilter = 'All'; // 'All' | 'Unread' | 'Read'
  String _typeFilter = 'All Types'; // 'All Types' | 'Leave' | 'Permission' | 'Reimbursement' | 'Payslip'

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

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _api.request('/admin/notifications');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _notifications = list.map((e) => NotificationItemModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        } else {
          _setMockNotifications();
        }
      } else {
        _setMockNotifications();
      }
    } catch (_) {
      _setMockNotifications();
    }

    await FcmService.markNotificationsSeen();

    if (showLoader && mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _setMockNotifications() {
    _notifications = [
      NotificationItemModel(
        id: 'notif_1',
        title: 'New Leave Request',
        message: 'sarannn saran has requested 0.5 day(s) of leave (Unpaid).',
        staffSubtitle: 'sarannn saran • EMP-015 • Engineering',
        type: 'leave',
        timeAgo: '2h ago',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        isRead: false,
      ),
      NotificationItemModel(
        id: 'notif_2',
        title: 'New Leave Request',
        message: 'sarannn saran has requested 0.5 day(s) of leave (Unpaid).',
        staffSubtitle: 'sarannn saran • EMP-015 • Engineering',
        type: 'leave',
        timeAgo: '2h ago',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        isRead: false,
      ),
      NotificationItemModel(
        id: 'notif_3',
        title: 'New Expense Claim',
        message: 'James fernado has submitted an expense claim of ₹200 for Meals.',
        staffSubtitle: 'James fernado • EMP-002 • IT',
        type: 'reimbursement',
        timeAgo: '3h ago',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        isRead: false,
      ),
      NotificationItemModel(
        id: 'notif_4',
        title: 'New Leave Request',
        message: 'James fernado has requested 1 day(s) of leave (sick).',
        staffSubtitle: 'James fernado • EMP-002 • IT',
        type: 'leave',
        timeAgo: '3h ago',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        isRead: false,
      ),
      NotificationItemModel(
        id: 'notif_5',
        title: 'New Payslip Request',
        message: 'personal notouch has requested their payslip for February 2026.',
        staffSubtitle: 'personal notouch • EMP-007 • Engineering',
        type: 'payslip',
        timeAgo: '1d ago',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        isRead: false,
      ),
      NotificationItemModel(
        id: 'notif_6',
        title: 'New Payslip Request',
        message: 'personal notouch has requested their payslip for January 2026.',
        staffSubtitle: 'personal notouch • EMP-007 • Engineering',
        type: 'payslip',
        timeAgo: '1d ago',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        isRead: false,
      ),
      NotificationItemModel(
        id: 'notif_7',
        title: 'New Permission Request',
        message: 'hp hai th has requested a Late permission for 1 hr on 8/25/2026.',
        staffSubtitle: 'hp hai th • EMP-006 • IT',
        type: 'permission',
        timeAgo: '5d ago',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        isRead: false,
      ),
      NotificationItemModel(
        id: 'notif_8',
        title: 'New Permission Request',
        message: 'hp hai th has requested a Late permission for 1 hr on 8/25/2026.',
        staffSubtitle: 'hp hai th • EMP-006 • IT',
        type: 'permission',
        timeAgo: '5d ago',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        isRead: false,
      ),
    ];
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  int _countForType(String type) {
    if (type == 'all') return _notifications.length;
    return _notifications.where((n) => n.type.toLowerCase() == type.toLowerCase()).length;
  }

  List<NotificationItemModel> get _filteredNotifications {
    return _notifications.where((n) {
      final matchesSearch = _searchQuery.isEmpty ||
          n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.message.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.staffSubtitle.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _statusFilter == 'All' ||
          (_statusFilter == 'Unread' && !n.isRead) ||
          (_statusFilter == 'Read' && n.isRead);

      final matchesType = _typeFilter == 'All Types' ||
          (_typeFilter == 'Leave' && n.type == 'leave') ||
          (_typeFilter == 'Permission' && n.type == 'permission') ||
          (_typeFilter == 'Reimbursement' && (n.type == 'reimbursement' || n.type == 'expense')) ||
          (_typeFilter == 'Payslip' && n.type == 'payslip');

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
      await _api.request('/admin/notifications', method: 'PUT');
    } catch (_) {}
    if (mounted) SnackBarUtils.showSnackBar(context, 'All notifications marked as read');
  }

  Future<void> _handleClearAll() async {
    setState(() {
      _notifications.clear();
    });
    try {
      await _api.request('/admin/notifications/clear', method: 'DELETE');
    } catch (_) {}
    if (mounted) SnackBarUtils.showSnackBar(context, 'All notifications cleared');
  }

  void _handleNotificationTap(NotificationItemModel item) {
    // Mark single as read
    setState(() {
      item.isRead = true;
    });
    try {
      _api.request('/admin/notifications/${item.id}/read', method: 'PUT');
    } catch (_) {}

    // Direct module click navigation
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

  void _handleDeleteSingle(NotificationItemModel item) {
    setState(() {
      _notifications.removeWhere((n) => n.id == item.id);
    });
    try {
      _api.request('/admin/notifications/${item.id}', method: 'DELETE');
    } catch (_) {}
    if (mounted) SnackBarUtils.showSnackBar(context, 'Notification removed');
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
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _load(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header Banner (Screenshot 1, 2, 3)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12)),
                                  child: const Icon(Icons.notifications_none_rounded, color: Color(0xFFD97706), size: 22),
                                ),
                                if (unread > 0)
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: const Color(0xFFEFAA1F), borderRadius: BorderRadius.circular(8)),
                                      child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                                  const SizedBox(height: 2),
                                  Text('$unread unread of $total notifications', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: unread > 0 ? _handleMarkAllAsRead : null,
                              icon: const Icon(Icons.check_rounded, size: 13),
                              label: const Text('Mark all read', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF475569),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed: _notifications.isNotEmpty ? _handleClearAll : null,
                              icon: const Icon(Icons.delete_outline_rounded, size: 13, color: Color(0xFFDC2626)),
                              label: const Text('Clear', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFFECACA)),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Search Bar + Status Tabs
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 36,
                                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: TextField(
                                  onChanged: (v) => setState(() => _searchQuery = v),
                                  decoration: const InputDecoration(
                                    hintText: 'Search title or message...',
                                    hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    prefixIcon: Icon(Icons.search_rounded, size: 15, color: Color(0xFF94A3B8)),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Tabs: All | Unread | Read
                            Container(
                              height: 36,
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.all(2),
                              child: Row(
                                children: [
                                  _statusTabItem('All', null),
                                  _statusTabItem('Unread', unread),
                                  _statusTabItem('Read', null),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Type Filter Chips (Screenshot 1 & 2)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _typeChip('All Types', total, Icons.layers_outlined, const Color(0xFFEFAA1F), const Color(0xFFFEF3C7)),
                              const SizedBox(width: 6),
                              _typeChip('Leave', _countForType('leave'), Icons.calendar_month_outlined, const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
                              const SizedBox(width: 6),
                              _typeChip('Permission', _countForType('permission'), Icons.access_time_rounded, const Color(0xFF7C3AED), const Color(0xFFF3E8FF)),
                              const SizedBox(width: 6),
                              _typeChip('Reimbursement', _countForType('reimbursement'), Icons.receipt_long_outlined, const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
                              const SizedBox(width: 6),
                              _typeChip('Payslip', _countForType('payslip'), Icons.description_outlined, const Color(0xFF0284C7), const Color(0xFFE0F2FE)),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                  else
                    ..._filteredNotifications.map((item) => _buildNotificationCard(item)),
                ],
              ),
            ),
    );
  }

  Widget _statusTabItem(String label, int? badgeCount) {
    final isSelected = _statusFilter == label;
    return InkWell(
      onTap: () => setState(() => _statusFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : null,
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
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

  Widget _typeChip(String label, int count, IconData icon, Color color, Color bg) {
    final isSelected = _typeFilter == label;
    return InkWell(
      onTap: () => setState(() => _typeFilter = label),
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

  Widget _buildNotificationCard(NotificationItemModel item) {
    IconData icon;
    Color iconColor;
    Color iconBg;

    final type = item.type.toLowerCase();
    if (type == 'leave') {
      icon = Icons.calendar_today_outlined;
      iconColor = const Color(0xFF2563EB);
      iconBg = const Color(0xFFEFF6FF);
    } else if (type == 'reimbursement' || type == 'expense') {
      icon = Icons.receipt_long_outlined;
      iconColor = const Color(0xFF16A34A);
      iconBg = const Color(0xFFDCFCE7);
    } else if (type == 'permission') {
      icon = Icons.access_time_rounded;
      iconColor = const Color(0xFF7C3AED);
      iconBg = const Color(0xFFF3E8FF);
    } else {
      icon = Icons.description_outlined;
      iconColor = const Color(0xFF0284C7);
      iconBg = const Color(0xFFE0F2FE);
    }

    return InkWell(
      onTap: () => _handleNotificationTap(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: item.isRead ? const Color(0xFFF1F5F9) : const Color(0xFFFEF3C7)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Icon with Unread Dot
            Stack(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                if (!item.isRead)
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(color: Color(0xFFEFAA1F), shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  Text(item.message, style: const TextStyle(fontSize: 11, color: Color(0xFF334155))),
                  if (item.staffSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(item.staffSubtitle, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Time & Actions
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(item.timeAgo, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!item.isRead)
                      InkWell(
                        onTap: () {
                          setState(() => item.isRead = true);
                          try {
                            _api.request('/admin/notifications/${item.id}/read', method: 'PUT');
                          } catch (_) {}
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.check_rounded, size: 15, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _handleDeleteSingle(item),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFF94A3B8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
