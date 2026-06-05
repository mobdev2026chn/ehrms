import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/request_success_dialog.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hrms/widgets/app_tab_loader.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../services/request_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';

/// Returns true if [s] is half-day leave type (case and space insensitive).
/// Backend may send "half day", "Half Day", "halfday", "half", "Half", etc.
bool _isHalfDayLeave(String? s) {
  if (s == null || s.isEmpty) return false;
  final n = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return n == 'halfday' || n == 'half';
}

class MyRequestsScreen extends StatefulWidget {
  final int initialTabIndex;
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  /// Called when user changes tab so dashboard can keep requested tab in sync for quick-action navigation.
  final void Function(int index)? onTabIndexChanged;

  /// When true, this screen is the visible tab (e.g. user tapped Request in bottom nav).
  final bool? isActiveTab;

  const MyRequestsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
    this.onTabIndexChanged,
    this.isActiveTab,
  });

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

/// The kind of request a feed item represents.
enum _RequestKind { leave, loan, expense, permission }

/// A single unified entry in the combined "Recent Submissions" feed.
class _RequestItem {
  final _RequestKind kind;
  final String title;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  const _RequestItem({
    required this.kind,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.raw,
  });
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  final RequestService _requestService = RequestService();
  bool _isLoading = true;
  bool _showAll = false;
  List<_RequestItem> _items = [];

  /// Items shown in the feed before the user taps "View All".
  static const int _recentCount = 5;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  @override
  void didUpdateWidget(MyRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActiveTab == true && oldWidget.isActiveTab != true) {
      _fetchAll();
    }
  }

  /// Fetches every request type in parallel and merges them into one
  /// reverse-chronological feed (newest first).
  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _requestService.getLeaveRequests(limit: 50),
      _requestService.getLoanRequests(limit: 50),
      _requestService.getExpenseRequests(limit: 50),
      _requestService.getPermissionRequests(),
    ]);
    if (!mounted) return;

    final items = <_RequestItem>[];
    items.addAll(_parseList(results[0], 'leaves').map(_leaveItem));
    items.addAll(_parseList(results[1], 'loans').map(_loanItem));
    items.addAll(_parseList(results[2], 'reimbursements').map(_expenseItem));
    items.addAll(_parseList(results[3], 'permissions').map(_permissionItem));
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  /// Extracts the record list from a service result whose `data` is either a
  /// List or a Map keyed by [listKey].
  List<Map<String, dynamic>> _parseList(
    Map<String, dynamic> result,
    String listKey,
  ) {
    if (result['success'] != true) return const [];
    final data = result['data'];
    List<dynamic> raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      raw = (data[listKey] as List?) ?? const [];
    } else {
      raw = const [];
    }
    return raw
        .map(
          (e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map),
        )
        .toList();
  }

  DateTime _parseDate(dynamic v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime(1970);

  // ── Per-type → unified item mappers ──────────────────────────────────────
  _RequestItem _leaveItem(Map<String, dynamic> m) => _RequestItem(
    kind: _RequestKind.leave,
    title: (m['leaveType'] ?? 'Leave').toString(),
    status: (m['status'] ?? '').toString(),
    createdAt: _parseDate(m['createdAt']),
    raw: m,
  );

  _RequestItem _loanItem(Map<String, dynamic> m) => _RequestItem(
    kind: _RequestKind.loan,
    title: (m['loanType'] ?? 'Loan').toString(),
    status: (m['status'] ?? '').toString(),
    createdAt: _parseDate(m['createdAt']),
    raw: m,
  );

  _RequestItem _expenseItem(Map<String, dynamic> m) => _RequestItem(
    kind: _RequestKind.expense,
    title: (m['type'] ?? m['expenseType'] ?? 'Expense').toString(),
    status: (m['status'] ?? '').toString(),
    createdAt: _parseDate(m['createdAt'] ?? m['date']),
    raw: m,
  );

  _RequestItem _permissionItem(Map<String, dynamic> m) => _RequestItem(
    kind: _RequestKind.permission,
    title: _permissionTypeLabel(m['type']?.toString()),
    status: (m['status'] ?? '').toString(),
    createdAt: _parseDate(m['createdAt'] ?? m['date']),
    raw: m,
  );

  static String _permissionTypeLabel(String? type) {
    switch (type) {
      case 'lateArrival':
        return 'Late Arrival Permission';
      case 'earlyExit':
        return 'Early Exit Permission';
      default:
        return 'Permission Request';
    }
  }

  IconData _iconFor(_RequestKind kind) {
    switch (kind) {
      case _RequestKind.leave:
        return Icons.event_available_rounded;
      case _RequestKind.loan:
        return Icons.account_balance_wallet_rounded;
      case _RequestKind.expense:
        return Icons.receipt_long_rounded;
      case _RequestKind.permission:
        return Icons.fact_check_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final pending =
        _items.where((e) => e.status.toLowerCase() == 'pending').length;
    final totalYtd =
        _items.where((e) => e.createdAt.year == now.year).length;
    final visible = _showAll || _items.length <= _recentCount
        ? _items
        : _items.take(_recentCount).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('My Requests', style: AppTextStyles.headingMedium),
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      drawer: AppDrawer(
        currentIndex: widget.dashboardTabIndex ?? 1,
        onNavigateToIndex: widget.onNavigateToIndex,
      ),
      floatingActionButton: SizedBox(
        height: 44,
        child: FloatingActionButton.extended(
          foregroundColor: Colors.white,
          backgroundColor: AppColors.primary,
          onPressed: _showCreateRequestMenu,
          icon: const Icon(Icons.add, size: 20),
          label: const Text(
            'New Request',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAll,
        child: _isLoading
            ? const Center(child: AppTabLoader())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  FadeSlideIn(child: _buildOverviewCard(pending, totalYtd)),
                  const SizedBox(height: 20),
                  _buildRecentHeader(),
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    _buildEmptyState()
                  else
                    ...visible.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FadeSlideIn(
                          delay: Duration(
                            milliseconds: (e.key * 45).clamp(0, 270),
                          ),
                          child: _buildRequestCard(e.value),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// Amber "Active Requests" hero with Pending / Total YTD stat tiles.
  Widget _buildOverviewCard(int pending, int totalYtd) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFAA1F), Color(0xFFF6C04A)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33EFAA1F),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OVERVIEW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Active Requests',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pending == 0
                      ? 'You have no requests pending review.'
                      : 'You have $pending request${pending == 1 ? '' : 's'} '
                            'currently pending review or action.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _overviewStat('$pending', 'Pending'),
          const SizedBox(width: 10),
          _overviewStat('$totalYtd', 'Total YTD'),
        ],
      ),
    );
  }

  Widget _overviewStat(String value, String label) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Recent Submissions', style: AppTextStyles.headingSmall),
        if (_items.length > _recentCount)
          GestureDetector(
            onTap: () => setState(() => _showAll = !_showAll),
            child: Text(
              _showAll ? 'Show Less' : 'View All',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No requests yet',
              style: AppTextStyles.headingSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap "New Request" to submit one.',
              style: TextStyle(fontSize: 13, color: AppColors.textCaption),
            ),
          ],
        ),
      ),
    );
  }

  /// A Figma-style feed row: icon tile · title + date · status pill.
  Widget _buildRequestCard(_RequestItem item) {
    final s = AppColors.statusStyle(item.status);
    final dateLabel = DateFormat('MMM dd, yyyy').format(item.createdAt);
    return InkWell(
      onTap: () => _showDetails(item),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _iconFor(item.kind),
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: AppColors.textHint,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: s.bg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item.status.isEmpty ? 'â€”' : item.status,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: s.fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── New-request menu (launches the existing create dialogs) ───────────────
  void _showCreateRequestMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('New Request', style: AppTextStyles.headingSmall),
              ),
            ),
            _createTile(
              Icons.event_available_rounded,
              'Apply Leave',
              () => _openCreate(_RequestKind.leave),
            ),
            _createTile(
              Icons.account_balance_wallet_rounded,
              'Request Loan',
              () => _openCreate(_RequestKind.loan),
            ),
            _createTile(
              Icons.receipt_long_rounded,
              'Claim Expense',
              () => _openCreate(_RequestKind.expense),
            ),
            _createTile(
              Icons.fact_check_outlined,
              'Request Permission',
              () => _openCreate(_RequestKind.permission),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _createTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textCaption),
      onTap: onTap,
    );
  }

  void _openCreate(_RequestKind kind) {
    Navigator.pop(context); // close the menu first
    switch (kind) {
      case _RequestKind.leave:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          builder: (ctx) => ApplyLeaveDialog(onSuccess: _fetchAll),
        );
        break;
      case _RequestKind.loan:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => RequestLoanDialog(onSuccess: _fetchAll),
        );
        break;
      case _RequestKind.expense:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          builder: (ctx) => ClaimExpenseDialog(onSuccess: _fetchAll),
        );
        break;
      case _RequestKind.permission:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          builder: (ctx) => RequestPermissionDialog(onSuccess: _fetchAll),
        );
        break;
    }
  }

  // ── Detail bottom sheet (reuses _RequestDetailBottomSheet) ────────────────
  void _showDetails(_RequestItem item) {
    final m = item.raw;
    late String title;
    late IconData icon;
    final children = <Widget>[];
    switch (item.kind) {
      case _RequestKind.leave:
        title = 'Leave Details';
        icon = Icons.event_available_rounded;
        children.addAll([
          _kv('Leave Type', m['leaveType']?.toString() ?? 'â€”'),
          _kv('Start Date', _fmtDate(m['startDate'])),
          _kv('End Date', _fmtDate(m['endDate'])),
          _kv('Days', '${m['days'] ?? 'â€”'}'),
          _kv('Applied Date', _fmtDate(m['createdAt'])),
          _kv('Status', item.status),
          if ((m['reason'] ?? '').toString().trim().isNotEmpty)
            _kv('Reason', m['reason'].toString()),
        ]);
        break;
      case _RequestKind.loan:
        title = 'Loan Details';
        icon = Icons.account_balance_wallet_rounded;
        children.addAll([
          _kv('Type', m['loanType']?.toString() ?? 'â€”'),
          _kv('Amount', 'â‚¹${m['amount'] ?? 0}'),
          _kv('Tenure', '${m['tenure'] ?? m['tenureMonths'] ?? 'â€”'} Months'),
          _kv('EMI', 'â‚¹${m['emi'] ?? 0}'),
          if (m['interestRate'] != null)
            _kv('Interest Rate', '${m['interestRate']}%'),
          if ((m['purpose'] ?? '').toString().trim().isNotEmpty)
            _kv('Purpose', m['purpose'].toString()),
          _kv('Status', item.status),
          _kv('Requested On', _fmtDate(m['createdAt'])),
        ]);
        break;
      case _RequestKind.expense:
        title = 'Expense Details';
        icon = Icons.receipt_long_rounded;
        children.addAll([
          _kv('Type', (m['type'] ?? m['expenseType'] ?? 'Expense').toString()),
          _kv('Amount', 'â‚¹${m['amount'] ?? 0}'),
          _kv('Date', _fmtDate(m['date'])),
          _kv('Applied Date', _fmtDate(m['createdAt'])),
          if ((m['description'] ?? '').toString().trim().isNotEmpty)
            _kv('Description', m['description'].toString()),
          _kv('Status', item.status),
        ]);
        break;
      case _RequestKind.permission:
        title = 'Permission Details';
        icon = Icons.fact_check_outlined;
        children.addAll([
          _kv('Type', _permissionTypeLabel(m['type']?.toString())),
          _kv('Date', _fmtDate(m['date'])),
          _kv('Requested Minutes', '${m['requestedMinutes'] ?? 0}'),
          if ((m['reason'] ?? '').toString().trim().isNotEmpty)
            _kv('Reason', m['reason'].toString()),
          _kv('Applied', _fmtDate(m['createdAt'])),
          _kv('Status', item.status),
        ]);
        break;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: title,
        icon: icon,
        iconColor: AppColors.primary,
        children: children,
      ),
    );
  }

  String _fmtDate(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? 'â€”' : DateFormat('MMM dd, yyyy').format(d.toLocal());
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Shows a single calendar in a bottom sheet to select from-date and to-date (range) in the same calendar.
/// Returns [DateTimeRange] with start at 00:00:00 and end at 23:59:59 of the selected days, or null if dismissed.
Future<DateTimeRange?> showDateRangePickerSameCalendar({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initialStart,
  DateTime? initialEnd,
}) async {
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _clampDay(DateTime d, DateTime min, DateTime max) {
    final day = _dateOnly(d);
    final minDay = _dateOnly(min);
    final maxDay = _dateOnly(max);
    if (day.isBefore(minDay)) return minDay;
    if (day.isAfter(maxDay)) return maxDay;
    return day;
  }

  final firstDay = _dateOnly(firstDate);
  final lastDay = _dateOnly(lastDate);
  final now = DateTime.now();
  DateTime? rangeStart = initialStart != null
      ? DateTime(initialStart.year, initialStart.month, initialStart.day)
      : null;
  DateTime? rangeEnd = initialEnd != null
      ? DateTime(initialEnd.year, initialEnd.month, initialEnd.day)
      : null;
  DateTime focusedDay = _clampDay(
    rangeEnd ?? rangeStart ?? DateTime(now.year, now.month, now.day),
    firstDay,
    lastDay,
  );

  final result = await showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select from - to date',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (rangeStart != null && rangeEnd != null) {
                              final start = rangeStart!.isAfter(rangeEnd!)
                                  ? rangeEnd!
                                  : rangeStart!;
                              final end = rangeStart!.isAfter(rangeEnd!)
                                  ? rangeStart!
                                  : rangeEnd!;
                              Navigator.pop(
                                context,
                                DateTimeRange(start: start, end: end),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Select start and end date in the calendar',
                                  ),
                                ),
                              );
                            }
                          },
                          child: Text('Apply'),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: TableCalendar(
                        firstDay: firstDay,
                        lastDay: lastDay,
                        focusedDay: focusedDay,
                        rangeStartDay: rangeStart,
                        rangeEndDay: rangeEnd,
                        rangeSelectionMode: RangeSelectionMode.enforced,
                        onRangeSelected: (start, end, focused) {
                          setModalState(() {
                            rangeStart = start;
                            rangeEnd = end;
                            focusedDay = _clampDay(focused, firstDay, lastDay);
                          });
                        },
                        onPageChanged: (focused) {
                          setModalState(
                            () => focusedDay = _clampDay(focused, firstDay, lastDay),
                          );
                        },
                        calendarFormat: CalendarFormat.month,
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                        ),
                        calendarStyle: CalendarStyle(
                          rangeStartDecoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          rangeEndDecoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          rangeHighlightColor: AppColors.primary.withOpacity(
                            0.2,
                          ),
                          selectedDecoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          todayDecoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  return result;
}

/// Reusable bottom sheet for request details (Leave, Loan, Expense, Payslip).
class _RequestDetailBottomSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _RequestDetailBottomSheet({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.3),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 20),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.headingMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- LEAVE TAB ---

class LeaveRequestsTab extends StatefulWidget {
  const LeaveRequestsTab({super.key});

  @override
  State<LeaveRequestsTab> createState() => _LeaveRequestsTabState();
}

class _LeaveRequestsTabState extends State<LeaveRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _leaves = [];
  List<dynamic> _leaveBalances = [];
  bool _isLoading = true;
  bool _isLoadingBalances = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Rejected',
  ];
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  int _totalPages = 0;
  bool _showFilters = false;

  /// Start of month for [date]; end of that month (23:59:59) for [_endDate].
  static DateTime _firstDayOfMonth(DateTime date) =>
      DateTime(date.year, date.month, 1);
  static DateTime _lastDayOfMonth(DateTime date) =>
      DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchLeaves();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = _firstDayOfMonth(now);
    _endDate = _lastDayOfMonth(now);
    _fetchLeaves();
    _fetchLeaveBalances();
  }

  Future<void> _fetchLeaveBalances() async {
    setState(() => _isLoadingBalances = true);

    final start = _startDate;
    final end = _endDate;
    final result = await _requestService.getLeaveTypes(
      startDate: start,
      endDate: end,
      month: start == null ? DateTime.now().month : null,
      year: start == null ? DateTime.now().year : null,
    );

    if (mounted) {
      if (result['success']) {
        setState(() {
          _leaveBalances = (result['data'] as List).where((e) {
            final type = e['type'].toString().toLowerCase();
            return type != 'paid' && type != 'paid leave';
          }).toList();
          _isLoadingBalances = false;
        });
      } else {
        setState(() => _isLoadingBalances = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchLeaves() async {
    _fetchLeaveBalances(); // Also refresh balances
    setState(() => _isLoading = true);
    final result = await _requestService.getLeaveRequests(
      status: _selectedStatus,
      search: _searchController.text,
      startDate: _startDate,
      endDate: _endDate,
      page: _currentPage,
      limit: _itemsPerPage,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          if (result['data'] is Map) {
            _leaves = result['data']['leaves'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _totalPages = pagination['pages'] ?? 0;
              _currentPage = pagination['page'] ?? 1;
            }
          } else if (result['data'] is List) {
            _leaves = result['data'];
            _totalPages = 1;
            _currentPage = 1;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch leaves',
          ),
          isError: true,
        );
      }
    }
  }

  /// Pick from-date and to-date in same calendar; leaves and balances are shown for that range.
  Future<void> _pickDateRange() async {
    final picked = await showDateRangePickerSameCalendar(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchLeaves();
    }
  }

  void _resetToCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _startDate = _firstDayOfMonth(now);
      _endDate = _lastDayOfMonth(now);
    });
    _fetchLeaves();
  }

  void showApplyLeaveDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => ApplyLeaveDialog(onSuccess: _fetchLeaves),
    );
  }

  void _showLeaveDetails(Map<String, dynamic> leave) {
    // Debug: log leave response for Half day on / approvedBy
    final halfDayOnValue =
        leave['halfDayType']?.toString().trim() ??
        leave['halfDaySession']?.toString().trim() ??
        (leave['session'] == '1'
            ? 'First Half Day'
            : leave['session'] == '2'
            ? 'Second Half Day'
            : 'â€”');
    final start = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['startDate']).toLocal());
    final end = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['endDate']).toLocal());
    final appliedDate = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['createdAt']));
    // Resolve approvedBy / rejectedBy: backend may populate with { name, email }
    String approvedBy = 'â€”';
    String rejectedBy = 'â€”';
    final approver = leave['approvedBy'];
    final rejector = leave['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = 'â€”';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = 'â€”';
      } else {
        rejectedBy = 'System';
      }
    } else if (leave['status'] == 'Rejected' && approver != null) {
      rejectedBy = approvedBy; // Backend may use approvedBy for rejector
    }
    final rejectionReason = leave['rejectionReason']?.toString().trim();
    final isRejected = leave['status'] == 'Rejected';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Leave Details',
        icon: Icons.calendar_today,
        iconColor: AppColors.primary,
        children: [
          _detailRow('Leave Type', leave['leaveType'] ?? ''),
          if (_isHalfDayLeave(leave['leaveType']))
            _detailRow('Half day on', halfDayOnValue),
          _detailRow('Start Date', start),
          _detailRow('End Date', end),
          _detailRow('Days', '${leave['days']}'),
          _detailRow('Applied Date', appliedDate),
          _detailRow('Status', leave['status'] ?? ''),
          if (isRejected) ...[
            _detailRow('Rejected By', rejectedBy),
            if (rejectionReason != null && rejectionReason.isNotEmpty)
              _detailRow('Rejection Reason', rejectionReason),
          ] else
            _detailRow('Approved By', approvedBy),
          if (leave['reason'] != null && leave['reason'].toString().isNotEmpty)
            _detailRow('Reason', leave['reason']),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildLeaveCard(Map<String, dynamic> leave) {
    final colorScheme = Theme.of(context).colorScheme;
    final start = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['startDate']).toLocal());
    final end = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['endDate']).toLocal());
    final appliedDate = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['createdAt']));
    final approver = leave['approvedBy'];
    final rejector = leave['rejectedBy'];
    final isRejectedLeave = leave['status'] == 'Rejected';
    final approvedBy = approver != null
        ? (approver is Map ? approver['name'] : 'System')
        : '-';
    final rejectedBy = rejector != null
        ? (rejector is Map ? rejector['name'] : 'System')
        : (isRejectedLeave && approver != null ? approvedBy : '-');

    Color statusColor = Colors.grey;
    if (leave['status'] == 'Approved') {
      statusColor = AppColors.success;
    } else if (leave['status'] == 'Rejected') {
      statusColor = AppColors.error;
    } else if (leave['status'] == 'Pending') {
      statusColor = AppColors.warning;
    }

    return InkWell(
      onTap: () => _showLeaveDetails(leave),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.calendar_today,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leave Type and Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            leave['leaveType'] ?? 'Leave',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            leave['status'] ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Details
                    _buildCardDetailRow(
                      Icons.date_range,
                      'Dates',
                      '$start - $end',
                    ),
                    const SizedBox(height: 4),
                    _buildCardDetailRow(
                      Icons.event,
                      'Days',
                      '${leave['days']}',
                    ),
                    const SizedBox(height: 4),
                    _buildCardDetailRow(
                      Icons.access_time,
                      'Applied',
                      appliedDate,
                    ),
                    if (isRejectedLeave && rejectedBy != '-') ...[
                      const SizedBox(height: 4),
                      _buildCardDetailRow(
                        Icons.person_off_outlined,
                        'Rejected By',
                        rejectedBy,
                      ),
                    ] else if (!isRejectedLeave && approvedBy != '-') ...[
                      const SizedBox(height: 4),
                      _buildCardDetailRow(
                        Icons.person,
                        'Approved By',
                        approvedBy,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardDetailRow(IconData icon, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(dynamic balance) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 140, // Slightly wider for longer text
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ), // Reduced vertical padding
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            balance['type'] ?? 'Leave',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${balance['takenCount'] ?? 0}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          Text(
            'Leaves Taken',
            style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Leave Balance Summary
        if (!_isLoadingBalances && _leaveBalances.isNotEmpty)
          Container(
            height: 110, // Increased from 100
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _leaveBalances.length,
              itemBuilder: (context, index) {
                final balance = _leaveBalances[index];
                return _buildBalanceCard(balance);
              },
            ),
          ),
        // Controls Column
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Leave...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      _fetchLeaves();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                                _fetchLeaves();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _startDate == null || _endDate == null
                                  ? 'Select from - to date'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null && _endDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: _resetToCurrentMonth,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // List Body
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchLeaves();
            },
            child: _isLoading
                ? const Center(child: AppTabLoader())
                : _leaves.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.calendar_today_outlined,
                                  size: 44,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No leave requests found',
                                style: AppTextStyles.headingSmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _leaves.length,
                    itemBuilder: (ctx, i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: FadeSlideIn(
                          delay: Duration(milliseconds: (i * 45).clamp(0, 270)),
                          child: _buildLeaveCard(_leaves[i]),
                        ),
                      );
                    },
                  ),
          ),
        ),

        // Pagination Controls
        if (!_isLoading && _leaves.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 140, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchLeaves();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchLeaves();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ApplyLeaveDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const ApplyLeaveDialog({super.key, required this.onSuccess});

  @override
  State<ApplyLeaveDialog> createState() => _ApplyLeaveDialogState();
}

class _ApplyLeaveDialogState extends State<ApplyLeaveDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();

  String? _leaveType;
  String? _session; // For Half Day
  List<dynamic> _allowedTypes = [];
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isOneDay = true;
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingTypes = true;
  double _availableCasualLeaves = 0.0;
  double _totalAllowed = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchLeaveTypes();
    _fetchLeaveBalance();
  }

  @override
  void dispose() {
    SnackBarUtils.dismiss();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _fetchLeaveBalance() async {
    final result = await _requestService.getLeaveBalance();
    if (mounted && result['success'] == true) {
      setState(() {
        _availableCasualLeaves =
            (result['availableCasualLeaves'] as num?)?.toDouble() ?? 0.0;
        _totalAllowed = (result['totalAllowed'] as num?)?.toDouble() ?? 0.0;
      });
    }
  }

  Future<void> _fetchLeaveTypes() async {
    final result = await _requestService.getLeaveTypesForApply();
    if (mounted) {
      if (result['success']) {
        final raw = List<dynamic>.from(result['data'] as List? ?? []);
        // Ensure Half Day is always present as static option (backend sends it; add if missing)
        final hasHalfDay = raw.any((e) {
          final t = (e is Map ? e['type'] as String? : null) ?? '';
          return t.toLowerCase().replaceAll(RegExp(r'\s+'), '') == 'halfday';
        });
        if (!hasHalfDay) {
          raw.insert(0, {'type': 'Half Day', 'days': 0.5});
        }
        setState(() {
          _allowedTypes = raw;
          if (_allowedTypes.isNotEmpty) {
            _leaveType = _allowedTypes.first['type'] as String?;
          }
          _isLoadingTypes = false;
        });
      } else {
        setState(() => _isLoadingTypes = false);
      }
    }
  }

  int get _days {
    if (_startDate == null) return 0;
    if (_isHalfDayLeave(_leaveType)) return 0; // 0.5 on backend
    if (_isOneDay) return 1;
    if (_endDate == null) return 1;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  Future<void> _pickDate(bool isStart) async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? today,
      firstDate: today,
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_isOneDay || _isHalfDayLeave(_leaveType)) {
          _endDate = picked;
        } else if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
        if (_startDate != null && picked.isBefore(_startDate!)) {
          _startDate = picked;
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null) {
      SnackBarUtils.showSnackBar(context, 'Please select date');
      return;
    }
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (_startDate!.isBefore(today)) {
      SnackBarUtils.showSnackBar(
        context,
        'Cannot select past dates. Please select today or future dates.',
        isError: true,
      );
      return;
    }
    final effectiveEnd = _isOneDay || _isHalfDayLeave(_leaveType)
        ? _startDate!
        : _endDate;
    if (!_isOneDay &&
        !_isHalfDayLeave(_leaveType) &&
        (effectiveEnd == null || effectiveEnd.isBefore(today))) {
      SnackBarUtils.showSnackBar(
        context,
        'End date cannot be in the past.',
        isError: true,
      );
      return;
    }
    if (!_isOneDay && _endDate != null && _endDate!.isBefore(_startDate!)) {
      SnackBarUtils.showSnackBar(
        context,
        'End date must be on or after start date.',
        isError: true,
      );
      return;
    }
    if (_isHalfDayLeave(_leaveType) &&
        !_isOneDay &&
        _endDate != null &&
        _endDate != _startDate) {
      SnackBarUtils.showSnackBar(
        context,
        'Half Day leave allows only one date.',
        isError: true,
      );
      return;
    }
    if (_isHalfDayLeave(_leaveType) && _session == null) {
      SnackBarUtils.showSnackBar(
        context,
        'Please select a session for Half Day leave',
        isError: true,
      );
      return;
    }

    final daysValue = _isHalfDayLeave(_leaveType) ? 0.5 : _days;
    final requestedDays = _isHalfDayLeave(_leaveType) ? 0.5 : _days.toDouble();
    final rangeEnd = effectiveEnd ?? _startDate!;

    // Unpaid Leave: no balance validation
    final isUnpaidLeave =
        _leaveType != null &&
        _leaveType!.toLowerCase().replaceAll(RegExp(r'\s+'), '') ==
            'unpaidleave';
    if (!isUnpaidLeave) {
      await _fetchLeaveBalance();
      if (!mounted) return;
      if (_availableCasualLeaves <= 0) {
        SnackBarUtils.showSnackBar(
          context,
          "You don't have enough leave balance.",
          isError: true,
        );
        return;
      }
      if (_availableCasualLeaves == 0.5) {
        if (!_isHalfDayLeave(_leaveType)) {
          SnackBarUtils.showSnackBar(
            context,
            "You don't have enough leave balance.",
            isError: true,
          );
          return;
        }
      } else if (requestedDays > _availableCasualLeaves) {
        SnackBarUtils.showSnackBar(
          context,
          "You don't have enough leave balance.",
          isError: true,
        );
        return;
      }
    }

    // Backend checks "leave already applied" and returns a single error message
    final payload = {
      'leaveType': _leaveType,
      'startDate': _startDate!.toIso8601String(),
      'endDate': rangeEnd.toIso8601String(),
      'days': daysValue,
      'reason': _reasonController.text,
      'session': _isHalfDayLeave(_leaveType) ? _session : null,
      if (_isHalfDayLeave(_leaveType) && _session != null)
        'halfDaySession': _session == '1'
            ? 'First Half Day'
            : 'Second Half Day',
    };

    setState(() => _isSubmitting = true);
    final result = await _requestService.applyLeave(payload);
    setState(() => _isSubmitting = false);

    if (mounted) {
      if (result['success']) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final overlay = Navigator.of(context, rootNavigator: true).overlay;
          Navigator.of(context).pop();
          widget.onSuccess();
          if (overlay != null && overlay.context.mounted) {
            showRequestSubmittedSuccessDialog(overlay.context);
          }
        });
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to submit leave',
          ),
          isError: true,
        );
      }
    }
  }

  /// Shows an integer when whole (14), else one decimal (13.5).
  String _trimNum(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
  }

  bool get _isUnpaidLeave =>
      _leaveType != null &&
      _leaveType!.toLowerCase().replaceAll(RegExp(r'\s+'), '') == 'unpaidleave';

  /// Uppercase caption above each section (Figma "New Request").
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// Amber "Leave Entitlement" hero â€” days remaining + progress + used/total.
  Widget _buildEntitlementCard() {
    final remaining = _availableCasualLeaves;
    final total = _totalAllowed;
    final used = total - remaining;
    final usedClamped = used < 0 ? 0.0 : (used > total ? total : used);
    final progress = total > 0 ? (usedClamped / total).clamp(0.0, 1.0) : 0.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Positioned(
              right: -16,
              top: -24,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LEAVE ENTITLEMENT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.textCaption,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isUnpaidLeave
                      ? 'Unpaid Leave'
                      : '${_trimNum(remaining)} Days Remaining',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _isUnpaidLeave ? 0 : progress,
                    minHeight: 8,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isUnpaidLeave
                      ? 'No balance limit applies to unpaid leave.'
                      : 'You have used ${_trimNum(usedClamped)} of ${_trimNum(total)} annual leave days.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Grey filled Leave Type dropdown card (Figma).
  Widget _buildLeaveTypeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _leaveType,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      items: _allowedTypes.map((e) {
        final type = e['type'] as String? ?? '';
        return DropdownMenuItem<String>(value: type, child: Text(type));
      }).toList(),
      onChanged: (val) {
        setState(() {
          _leaveType = val!;
          if (_isHalfDayLeave(_leaveType)) {
            _session = '1';
            _isOneDay = true;
            if (_startDate != null) _endDate = _startDate;
          }
        });
      },
    );
  }

  /// Single grey date card with a "From"/"To"/"Date" caption (Figma).
  Widget _buildDateCard({
    required String label,
    required DateTime? date,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        Opacity(
          opacity: enabled ? 1 : 0.55,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      date != null
                          ? DateFormat('MMM dd, yyyy').format(date)
                          : 'Select',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: date != null
                            ? AppColors.textPrimary
                            : AppColors.textCaption,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    final isSingle = _isOneDay || _isHalfDayLeave(_leaveType);
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header â€” back arrow + "New Request"
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 24),
                    color: AppColors.textPrimary,
                  ),
                  const Text(
                    'New Request',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leave Entitlement hero
                    _buildEntitlementCard(),
                    const SizedBox(height: 24),

                    // Leave Type
                    _sectionLabel('Leave Type'),
                    if (_isLoadingTypes)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: AppTabLoader()),
                      )
                    else if (_allowedTypes.isEmpty)
                      const Text(
                        'No leave types available. Please contact HR to assign a leave template.',
                        style: TextStyle(color: AppColors.error),
                      )
                    else
                      _buildLeaveTypeDropdown(),
                    const SizedBox(height: 20),

                    // Single-day toggle (hidden for Half Day, which is always single)
                    if (!_isHalfDayLeave(_leaveType))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            const Text(
                              'Single day',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: _isOneDay,
                              onChanged: (v) {
                                setState(() {
                                  _isOneDay = v;
                                  if (_isOneDay && _startDate != null) {
                                    _endDate = _startDate;
                                  }
                                });
                              },
                              activeThumbColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),

                    // From / To date cards
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildDateCard(
                            label: isSingle ? 'Date' : 'From',
                            date: _startDate,
                            onTap: () => _pickDate(true),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildDateCard(
                            label: 'To',
                            date: isSingle ? _startDate : _endDate,
                            onTap: isSingle ? null : () => _pickDate(false),
                            enabled: !isSingle,
                          ),
                        ),
                      ],
                    ),
                    if (_startDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _isHalfDayLeave(_leaveType)
                              ? 'Total: 0.5 day â€” ${_trimNum(_availableCasualLeaves)} days remaining'
                              : 'Total: $_days day${_days == 1 ? '' : 's'} â€” ${_trimNum(_availableCasualLeaves)} days remaining',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),

                    // Half Day session chips
                    if (_isHalfDayLeave(_leaveType) && _startDate != null) ...[
                      const SizedBox(height: 18),
                      _sectionLabel('Session for Half Day'),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('First Half Day'),
                            selected: _session == '1',
                            onSelected: (v) => setState(() => _session = '1'),
                            selectedColor: AppColors.primary.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 12),
                          ChoiceChip(
                            label: const Text('Second Half Day'),
                            selected: _session == '2',
                            onSelected: (v) => setState(() => _session = '2'),
                            selectedColor: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 22),

                    // Reason for Leave
                    _sectionLabel('Reason for Leave'),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 4,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Briefly describe your reason...',
                        hintStyle: const TextStyle(color: AppColors.textCaption),
                        filled: true,
                        fillColor: AppColors.inputFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Reason is required' : null,
                    ),
                    const SizedBox(height: 28),

                    // Submit Request
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Submit Request',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.send_rounded, size: 18),
                                ],
                              ),
                      ),
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
}

// --- LOAN TAB ---

class LoanRequestsTab extends StatefulWidget {
  const LoanRequestsTab({super.key});

  @override
  State<LoanRequestsTab> createState() => _LoanRequestsTabState();
}

class _LoanRequestsTabState extends State<LoanRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _loans = [];
  bool _isLoading = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Rejected',
  ];

  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  int _totalPages = 0;
  bool _showFilters = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchLoans();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    _fetchLoans();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchLoans() async {
    setState(() => _isLoading = true);
    final result = await _requestService.getLoanRequests(
      status: _selectedStatus,
      search: _searchController.text,
      startDate: _startDate,
      endDate: _endDate,
      page: _currentPage,
      limit: _itemsPerPage,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          if (result['data'] is Map) {
            _loans = result['data']['loans'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _totalPages = pagination['pages'] ?? 0;
              _currentPage = pagination['page'] ?? 1;
            }
          } else if (result['data'] is List) {
            _loans = result['data'];
            _totalPages = 1;
            _currentPage = 1;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch loan requests',
          ),
          isError: true,
        );
      }
    }
  }

  void showRequestLoanDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RequestLoanDialog(onSuccess: _fetchLoans),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePickerSameCalendar(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end.add(
          const Duration(hours: 23, minutes: 59, seconds: 59),
        );
      });
      _fetchLoans();
    }
  }

  void _showLoanDetails(Map<String, dynamic> loan) {
    String approvedBy = 'â€”';
    String rejectedBy = 'â€”';
    final approver = loan['approvedBy'];
    final rejector = loan['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = 'â€”';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = 'â€”';
      } else {
        rejectedBy = 'System';
      }
    } else if (loan['status'] == 'Rejected' && approver != null) {
      rejectedBy = approvedBy;
    }
    final rejectionReason = loan['rejectionReason']?.toString().trim();
    final isRejected = loan['status'] == 'Rejected';
    final requestedOn = loan['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(loan['createdAt']))
        : 'â€”';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Loan Details',
        icon: Icons.account_balance_wallet,
        iconColor: AppColors.primary,
        children: [
          _detailRow('Type', loan['loanType'] ?? ''),
          _detailRow('Amount', 'â‚¹${loan['amount']}'),
          _detailRow(
            'Tenure',
            '${loan['tenure'] ?? loan['tenureMonths']} Months',
          ),
          _detailRow('EMI', 'â‚¹${loan['emi'] ?? 0}'),
          _detailRow('Interest Rate', '${loan['interestRate']}%'),
          _detailRow('Purpose', loan['purpose'] ?? ''),
          _detailRow('Status', loan['status'] ?? ''),
          if (isRejected) ...[
            _detailRow('Rejected By', rejectedBy),
            if (rejectionReason != null && rejectionReason.isNotEmpty)
              _detailRow('Rejection Reason', rejectionReason),
          ] else
            _detailRow('Approved By', approvedBy),
          _detailRow('Requested On', requestedOn),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildLoanCard(Map<String, dynamic> loan) {
    final appliedDate = loan['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(loan['createdAt']))
        : '-';
    Color statusColor = Colors.grey;
    if (loan['status'] == 'Approved' || loan['status'] == 'Active') {
      statusColor = AppColors.success;
    } else if (loan['status'] == 'Rejected') {
      statusColor = AppColors.error;
    } else if (loan['status'] == 'Pending') {
      statusColor = AppColors.warning;
    }

    String approvedByName = '-';
    String rejectedByName = '-';
    final approver = loan['approvedBy'];
    final rejector = loan['rejectedBy'];
    final isRejectedLoan = loan['status'] == 'Rejected';
    if (approver != null) {
      if (approver is Map) {
        approvedByName = approver['name'] ?? '-';
      } else {
        approvedByName = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map) {
        rejectedByName = rejector['name'] ?? '-';
      } else {
        rejectedByName = 'System';
      }
    } else if (isRejectedLoan && approver != null) {
      rejectedByName = approvedByName;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showLoanDetails(loan),
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        radius: 18,
        child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Loan Type and Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            loan['loanType'] ?? 'Loan',
                            style: AppTextStyles.headingSmall.copyWith(
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            loan['status'] ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Details
                    _buildLoanCardDetailRow(
                      Icons.currency_rupee,
                      'Amount',
                      'â‚¹${loan['amount']}',
                    ),
                    const SizedBox(height: 4),
                    _buildLoanCardDetailRow(
                      Icons.calendar_today,
                      'Tenure',
                      '${loan['tenure'] ?? loan['tenureMonths']} Months',
                    ),
                    const SizedBox(height: 4),
                    _buildLoanCardDetailRow(
                      Icons.payment,
                      'EMI',
                      'â‚¹${loan['emi'] ?? 0}',
                    ),
                    const SizedBox(height: 4),
                    _buildLoanCardDetailRow(
                      Icons.access_time,
                      'Applied',
                      appliedDate,
                    ),
                    if (isRejectedLoan && rejectedByName != '-') ...[
                      const SizedBox(height: 4),
                      _buildLoanCardDetailRow(
                        Icons.person_off_outlined,
                        'Rejected By',
                        rejectedByName,
                      ),
                    ] else if (!isRejectedLoan && approvedByName != '-') ...[
                      const SizedBox(height: 4),
                      _buildLoanCardDetailRow(
                        Icons.person,
                        'Approved By',
                        approvedByName,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildLoanCardDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF424242)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF424242),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: Color(0xFF424242)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls Column
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Type, Purpose...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      _fetchLoans();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                                _fetchLoans();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _startDate == null
                                  ? 'Date'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                  _fetchLoans();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // List Content
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchLoans();
            },
            child: _isLoading
                ? const Center(child: AppTabLoader())
                : _loans.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No loan requests found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _loans.length,
                    itemBuilder: (ctx, i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: FadeSlideIn(
                          delay: Duration(milliseconds: (i * 45).clamp(0, 270)),
                          child: _buildLoanCard(_loans[i]),
                        ),
                      );
                    },
                  ),
          ),
        ),

        // Pagination Controls
        if (!_isLoading && _loans.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 140, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchLoans();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchLoans();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class RequestLoanDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const RequestLoanDialog({super.key, required this.onSuccess});

  @override
  State<RequestLoanDialog> createState() => _RequestLoanDialogState();
}

class _RequestLoanDialogState extends State<RequestLoanDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();

  // Loan type options â€” display label vs. value sent to backend.
  static const List<({String value, String label})> _loanTypes = [
    (value: 'Personal', label: 'Personal Loan'),
    (value: 'Advance', label: 'Advance Salary'),
    (value: 'Emergency', label: 'Emergency Loan'),
  ];

  String _loanType = 'Personal';
  double _tenureMonths = 12;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final result = await _requestService.applyLoan({
      'loanType': _loanType,
      'amount': double.tryParse(_amountController.text) ?? 0,
      'tenure': _tenureMonths.round(),
      'interestRate': 0,
      'purpose': _purposeController.text,
    });
    setState(() => _isSubmitting = false);

    if (mounted) {
      if (result['success']) {
        final overlay = Navigator.of(context, rootNavigator: true).overlay;
        widget.onSuccess();
        Navigator.pop(context);
        if (overlay != null && overlay.context.mounted) {
          showRequestSubmittedSuccessDialog(overlay.context);
        }
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to submit loan request',
          ),
          isError: true,
        );
      }
    }
  }

  // â”€â”€ Section 1: Eligible amount header card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildEligibleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Decorative faint squares (top-right)
          Positioned(
            right: -6,
            top: 4,
            child: Icon(
              Icons.account_balance_wallet,
              size: 86,
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ELIGIBLE AMOUNT',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '₹10,000',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.info_outline, color: Colors.white, size: 15),
                    SizedBox(width: 6),
                    Text(
                      'Based on your tenure and salary',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // â”€â”€ Section 2: Active loans + credit score stat cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildStatCard({
    required String label,
    required String value,
    required String caption,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  InputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  // â”€â”€ Section 3: Application details card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildApplicationDetails() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Application Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // Loan Amount Request
          _fieldLabel('Loan Amount Request'),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: const TextStyle(color: AppColors.textHint),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Text(
                  '\$',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0),
              filled: true,
              fillColor: AppColors.inputFill,
              border: _fieldBorder(Colors.transparent),
              enabledBorder: _fieldBorder(Colors.transparent),
              focusedBorder: _fieldBorder(AppColors.primary, width: 1.5),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            validator: (val) => val == null || val.trim().isEmpty
                ? 'Amount is required'
                : null,
          ),
          const SizedBox(height: 18),

          // Loan Type
          _fieldLabel('Loan Type'),
          DropdownButtonFormField<String>(
            initialValue: _loanType,
            icon: const Icon(Icons.keyboard_arrow_down),
            items: _loanTypes
                .map(
                  (e) =>
                      DropdownMenuItem(value: e.value, child: Text(e.label)),
                )
                .toList(),
            onChanged: (val) => setState(() => _loanType = val!),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.inputFill,
              border: _fieldBorder(Colors.transparent),
              enabledBorder: _fieldBorder(Colors.transparent),
              focusedBorder: _fieldBorder(AppColors.primary, width: 1.5),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Tenure (Months) with slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _fieldLabel('Tenure (Months)'),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_tenureMonths.round()} Months',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.divider,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withOpacity(0.15),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 10,
              ),
            ),
            child: Slider(
              value: _tenureMonths,
              min: 3,
              max: 36,
              divisions: 33,
              onChanged: (v) => setState(() => _tenureMonths = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('3M', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text('12M', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text('24M', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text('36M', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Purpose of Loan
          _fieldLabel('Purpose of Loan'),
          TextFormField(
            controller: _purposeController,
            maxLines: 4,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Describe the reason for this request...',
              hintStyle: const TextStyle(color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.inputFill,
              border: _fieldBorder(Colors.transparent),
              enabledBorder: _fieldBorder(Colors.transparent),
              focusedBorder: _fieldBorder(AppColors.primary, width: 1.5),
              contentPadding: const EdgeInsets.all(16),
            ),
            validator: (val) => val == null || val.trim().isEmpty
                ? 'Purpose is required'
                : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Drag handle + header
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 24),
                    color: AppColors.textPrimary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  const Text('Request Loan', style: AppTextStyles.headingMedium),
                ],
              ),
            ),

            // Scrollable body â€” sections one by one
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEligibleCard(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            label: 'Active Loans',
                            value: '0',
                            caption: 'Applications',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            label: 'Credit Score',
                            value: 'A+',
                            caption: 'Excellent',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildApplicationDetails(),
                  ],
                ),
              ),
            ),

            // Submit button + footer
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  'Submit Request',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.send, size: 18),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'By submitting, you agree to the HRMS Loan Policy and Terms.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textCaption,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- EXPENSE TAB ---

class ExpenseRequestsTab extends StatefulWidget {
  const ExpenseRequestsTab({super.key});

  @override
  State<ExpenseRequestsTab> createState() => _ExpenseRequestsTabState();
}

class _ExpenseRequestsTabState extends State<ExpenseRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _expenses = [];
  bool _isLoading = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Rejected',
    'Paid',
  ];

  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  int _totalPages = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _showFilters = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchExpenses();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
    _fetchExpenses();
  }

  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);
    final result = await _requestService.getExpenseRequests(
      status: _selectedStatus,
      search: _searchController.text,
      startDate: _startDate,
      endDate: _endDate,
      page: _currentPage,
      limit: _itemsPerPage,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          if (result['data'] is Map) {
            _expenses = result['data']['reimbursements'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _totalPages = pagination['pages'] ?? 0;
              _currentPage = pagination['page'] ?? 1;
            }
          } else if (result['data'] is List) {
            _expenses = result['data'];
            _totalPages = 1;
            _currentPage = 1;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch expense requests',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePickerSameCalendar(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchExpenses();
    }
  }

  void _viewProof(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('Proof Document'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Image.network(
                url,
                loadingBuilder: (ctx, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: AppTabLoader());
                },
                errorBuilder: (ctx, error, stackTrace) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('Unable to load image or invalid format.'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // Changed to public for GlobalKey access
  void _showExpenseDetails(Map<String, dynamic> expense) {
    final date = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(expense['date']));
    final appliedDate = expense['createdAt'] != null
        ? DateFormat(
            'MMM dd, yyyy',
          ).format(DateTime.parse(expense['createdAt']))
        : 'â€”';

    String approvedByName = 'â€”';
    String rejectedByName = 'â€”';
    final approver = expense['approvedBy'];
    final rejector = expense['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedByName = approver['name'].toString().trim();
        if (approvedByName.isEmpty) approvedByName = 'â€”';
      } else {
        approvedByName = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedByName = rejector['name'].toString().trim();
        if (rejectedByName.isEmpty) rejectedByName = 'â€”';
      } else {
        rejectedByName = 'System';
      }
    } else if (expense['status'] == 'Rejected' && approver != null) {
      rejectedByName = approvedByName;
    }
    final rejectionReason = expense['rejectionReason']?.toString().trim();
    final isRejected = expense['status'] == 'Rejected';

    List<dynamic> proofs = expense['proofFiles'] ?? [];
    final detailChildren = <Widget>[
      _expenseDetailRow(
        'Type',
        expense['type'] ?? expense['expenseType'] ?? 'Expense',
      ),
      _expenseDetailRow('Amount', 'â‚¹${expense['amount']}'),
      _expenseDetailRow('Date', date),
      _expenseDetailRow('Applied Date', appliedDate),
      if (expense['description'] != null &&
          expense['description'].toString().isNotEmpty)
        _expenseDetailRow('Description', expense['description']),
      _expenseDetailRow('Status', expense['status'] ?? ''),
      if (isRejected) ...[
        _expenseDetailRow('Rejected By', rejectedByName),
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          _expenseDetailRow('Rejection Reason', rejectionReason),
      ] else
        _expenseDetailRow('Approved By', approvedByName),
      if (proofs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Proof Files:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        ...proofs.asMap().entries.map((entry) {
          final proof = entry.value;
          String proofUrl;
          if (proof is Map) {
            proofUrl =
                proof['url']?.toString() ??
                proof['fileUrl']?.toString() ??
                proof.toString();
          } else {
            proofUrl = proof.toString();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => _viewProof(proofUrl),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(Icons.attach_file, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'View Proof',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Expense Details',
        icon: Icons.receipt,
        iconColor: AppColors.primary,
        children: detailChildren,
      ),
    );
  }

  Widget _expenseDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // â”€â”€ Figma "Expense Claims" helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Category â†’ icon, matching the Figma claim rows.
  IconData _expenseIcon(String type) {
    switch (type.toLowerCase()) {
      case 'travel':
        return Icons.flight_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'accommodation':
        return Icons.hotel_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  double _amountOf(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  /// Indian-grouped amount with up to 2 decimals (keeps â‚¹ â€” the app is INR).
  String _formatAmount(dynamic v) =>
      NumberFormat('#,##0.##', 'en_IN').format(_amountOf(v));

  /// Sum of loaded claims whose status passes [test]. Derived from the already
  /// fetched `_expenses` â€” no new API call.
  double _sumWhere(bool Function(String status) test) {
    double total = 0;
    for (final e in _expenses) {
      if (test((e['status'] ?? '').toString())) total += _amountOf(e['amount']);
    }
    return total;
  }

  /// Amber summary hero â€” Total Reimbursed + Pending amount/count (Figma).
  Widget _buildClaimHero() {
    final reimbursed = _sumWhere((s) => s == 'Approved' || s == 'Paid');
    final pending = _sumWhere((s) => s == 'Pending');
    final pendingCount =
        _expenses.where((e) => (e['status'] ?? '') == 'Pending').length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, const Color(0xFFF5B841)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL REIMBURSED',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'â‚¹${_formatAmount(reimbursed)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.3), height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pending Amount',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'â‚¹${_formatAmount(pending)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$pendingCount Pending Claim${pendingCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Full-width amber "Create expense claim" button (Figma) â†’ existing dialog.
  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: showClaimExpenseDialog,
        icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
        label: const Text(
          'Create expense claim',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  /// "Recent Claims" header + amber "View All" link (clears filters â†’ all claims).
  Widget _buildRecentHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Recent Claims', style: AppTextStyles.headingSmall),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _selectedStatus = 'All Status';
              _startDate = null;
              _endDate = null;
              _currentPage = 1;
            });
            _fetchExpenses();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'View All',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense) {
    final date = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(expense['date']));
    final type =
        (expense['type'] ?? expense['expenseType'] ?? 'Expense').toString();
    final status = (expense['status'] ?? '').toString();

    Color statusColor = AppColors.warning;
    if (status == 'Approved' || status == 'Paid') {
      statusColor = AppColors.success;
    } else if (status == 'Rejected') {
      statusColor = AppColors.error;
    } else if (status == 'Pending') {
      statusColor = AppColors.warning;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showExpenseDetails(expense),
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        radius: 16,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Amber category icon tile
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_expenseIcon(type), color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            // Title + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(date, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Amount + status pill
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'â‚¹${_formatAmount(expense['amount'])}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                if (status.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void showClaimExpenseDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => ClaimExpenseDialog(onSuccess: _fetchExpenses),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Figma "Expense Claims": amber summary hero + create button + header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              FadeSlideIn(child: _buildClaimHero()),
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: _buildCreateButton(),
              ),
              const SizedBox(height: 18),
              _buildRecentHeader(),
            ],
          ),
        ),
        // Controls Column
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Type, Description...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onSubmitted: (_) => _fetchExpenses(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                                _fetchExpenses();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Date Filter Button
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _startDate == null
                                  ? 'Date'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                  _fetchExpenses();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // List Content
        Expanded(
          child: _isLoading
              ? const Center(child: AppTabLoader())
              : _expenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No expense requests found',
                        style: TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: _expenses.length,
                  itemBuilder: (ctx, i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: FadeSlideIn(
                        delay: Duration(milliseconds: (i * 45).clamp(0, 270)),
                        child: _buildExpenseCard(_expenses[i]),
                      ),
                    );
                  },
                ),
        ),

        // Pagination Controls
        if (!_isLoading && _expenses.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 140, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchExpenses();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchExpenses();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ClaimExpenseDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const ClaimExpenseDialog({super.key, required this.onSuccess});

  @override
  State<ClaimExpenseDialog> createState() => _ClaimExpenseDialogState();
}

class _ClaimExpenseDialogState extends State<ClaimExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();

  String _expenseType = 'Travel';
  final TextEditingController _amountController = TextEditingController();
  DateTime? _date;
  final TextEditingController _descriptionController =
      TextEditingController(); // Description
  File? _selectedFile; // Add File variable
  bool _isSubmitting = false;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null) {
      if (result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _date != null && !_date!.isAfter(today) ? _date! : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  /// Compress image file to reduce payload and avoid 413 Payload Too Large.
  static const int _maxProofImageWidth = 1200;
  static const int _proofImageQuality = 85;

  Future<List<int>> _compressImageFile(File file) async {
    final path = file.path.toLowerCase();
    final isImage =
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp');
    if (!isImage) {
      return await file.readAsBytes();
    }
    final result = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: _maxProofImageWidth,
      minHeight: _maxProofImageWidth,
      quality: _proofImageQuality,
      format: path.endsWith('.png') ? CompressFormat.png : CompressFormat.jpeg,
    );
    if (result == null || result.isEmpty) {
      return await file.readAsBytes();
    }
    return result;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      SnackBarUtils.showSnackBar(context, 'Please select a date');
      return;
    }
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (_date!.isAfter(today)) {
      SnackBarUtils.showSnackBar(
        context,
        'Expense date cannot be in the future. Please select today or a past date.',
        isError: true,
      );
      return;
    }

    if (_selectedFile == null) {
      SnackBarUtils.showSnackBar(context, 'Please upload a proof document');
      return;
    }

    setState(() => _isSubmitting = true);

    // Process file if exists: compress images to avoid 413 Payload Too Large
    List<String> proofFiles = [];
    if (_selectedFile != null) {
      final path = _selectedFile!.path.toLowerCase();
      final isPdf = path.endsWith('.pdf');
      const maxProofBytes = 5 * 1024 * 1024; // 5 MB max for PDF

      if (isPdf) {
        final length = await _selectedFile!.length();
        if (length > maxProofBytes) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            SnackBarUtils.showSnackBar(
              context,
              'Proof file is too large. Please use a file under 5 MB.',
              isError: true,
            );
          }
          return;
        }
        final bytes = await _selectedFile!.readAsBytes();
        final base64String = base64Encode(bytes);
        proofFiles.add('data:application/pdf;base64,$base64String');
      } else {
        // Image: compress to reduce payload and avoid 413
        final bytes = await _compressImageFile(_selectedFile!);
        final base64String = base64Encode(bytes);
        String mime = 'image/jpeg';
        if (path.endsWith('.png')) mime = 'image/png';
        proofFiles.add('data:$mime;base64,$base64String');
      }
    }

    final result = await _requestService.applyExpense({
      'type': _expenseType,
      'amount': double.tryParse(_amountController.text) ?? 0,
      'date': _date!.toIso8601String(),
      'description': _descriptionController.text,
      'proofFiles': proofFiles,
    });
    setState(() => _isSubmitting = false);

    if (mounted) {
      if (result['success']) {
        final overlay = Navigator.of(context, rootNavigator: true).overlay;
        widget.onSuccess();
        Navigator.pop(context);
        if (overlay != null && overlay.context.mounted) {
          showRequestSubmittedSuccessDialog(overlay.context);
        }
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to submit expense claim',
          ),
          isError: true,
        );
      }
    }
  }

  // ── Reference (Apply Leave / Request Loan) styling helpers ────────────────
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// Grey filled, borderless field decoration (amber focus) — matches the
  /// Apply Leave reason field / Request Loan inputs.
  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textCaption),
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  /// Grey date card with a calendar icon — matches Apply Leave's date cards.
  Widget _buildDateField({required DateTime? date, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              date == null
                  ? 'dd-mm-yyyy'
                  : DateFormat('dd-MM-yyyy').format(date),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: date == null ? AppColors.textCaption : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Figma dashed "Upload Receipt" dropzone â†’ existing `_pickFile`.
  Widget _buildUploadZone() {
    final hasFile = _selectedFile != null;
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(16),
      child: CustomPaint(
        painter: _DashedRRectPainter(
          color: hasFile ? AppColors.primary : Colors.grey.shade400,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasFile
                      ? Icons.check_circle_rounded
                      : Icons.cloud_upload_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasFile
                    ? _selectedFile!.path.split(RegExp(r'[/\\]')).last
                    : 'Upload Receipt',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasFile
                    ? 'Tap to replace'
                    : 'Tap to select or drag and drop JPG, PNG, or PDF',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header — back arrow + title
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 24),
                    color: AppColors.textPrimary,
                  ),
                  const Text(
                    'New Expense Claim',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Upload Receipt dropzone
                    _buildUploadZone(),
                    const SizedBox(height: 24),

                    // Category
                    _sectionLabel('Category'),
                    DropdownButtonFormField<String>(
                      initialValue: _expenseType,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      items: ['Travel', 'Food', 'Accommodation', 'Other']
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => _expenseType = val!),
                      decoration: _fieldDecoration(),
                    ),
                    const SizedBox(height: 20),

                    // Amount
                    _sectionLabel('Amount'),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      decoration: _fieldDecoration(hint: 'Enter expense amount'),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Amount is required'
                          : null,
                    ),
                    const SizedBox(height: 20),

                    // Date
                    _sectionLabel('Date'),
                    _buildDateField(date: _date, onTap: _pickDate),
                    const SizedBox(height: 20),

                    // Description
                    _sectionLabel('Description'),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      decoration: _fieldDecoration(
                        hint: 'Enter expense description',
                      ),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Description is required'
                          : null,
                    ),
                    const SizedBox(height: 28),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Submit Claim',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.send_rounded, size: 18),
                                ],
                              ),
                      ),
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
}

/// Dashed rounded-rectangle border for the Figma "Upload Receipt" dropzone.
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  static const double _radius = 16;
  static const double _dashWidth = 6;
  static const double _dashGap = 4;
  static const double _strokeWidth = 1.5;

  const _DashedRRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );
    final source = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = dist + _dashWidth;
        dashed.addPath(
          metric.extractPath(dist, next.clamp(0, metric.length)),
          Offset.zero,
        );
        dist = next + _dashGap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) => old.color != color;
}

// --- PERMISSION TAB ---

class PermissionRequestsTab extends StatefulWidget {
  const PermissionRequestsTab({super.key});

  @override
  State<PermissionRequestsTab> createState() => _PermissionRequestsTabState();
}

class _PermissionRequestsTabState extends State<PermissionRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _requests = [];
  bool _isLoading = true;
  bool _showFilters = false;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = const [
    'All Status',
    'Pending',
    'Approved',
    'Rejected',
    'Cancelled',
  ];
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _balance;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchRequests();
  }

  @override
  void initState() {
    super.initState();
    _fetchRequests();
    _fetchBalance();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    final result = await _requestService.getPermissionRequests(
      status: _selectedStatus,
      month: _selectedMonth.month,
      year: _selectedMonth.year,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'];
      setState(() {
        _requests = data is Map ? (data['permissions'] ?? []) : [];
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to fetch permission requests',
        ),
        isError: true,
      );
    }
  }

  Future<void> _fetchBalance() async {
    final result = await _requestService.getPermissionBalance(
      month: _selectedMonth.month,
      year: _selectedMonth.year,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _balance = result['data'] is Map<String, dynamic>
            ? result['data'] as Map<String, dynamic>
            : (result['data'] is Map
                  ? Map<String, dynamic>.from(result['data'])
                  : null);
      });
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final initial = _selectedMonth;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Select Month',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
    });
    await _fetchRequests();
    await _fetchBalance();
  }

  Future<void> _cancelRequest(String id) async {
    final result = await _requestService.cancelPermissionRequest(id);
    if (!mounted) return;
    if (result['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Permission request cancelled');
      await _fetchRequests();
    } else {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to cancel permission request',
        ),
        isError: true,
      );
    }
  }

  String _fmtDate(dynamic value) {
    if (value == null) return '-';
    final d = DateTime.tryParse(value.toString());
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy').format(d.toLocal());
  }

  String _fmtType(String? type) {
    switch (type) {
      case 'lateArrival':
        return 'Late Arrival';
      case 'earlyExit':
        return 'Early Exit';
      case 'both':
        return 'Both';
      default:
        return type ?? '-';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      case 'Cancelled':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  void showRequestPermissionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => RequestPermissionDialog(
        onSuccess: () {
          _fetchRequests();
          _fetchBalance();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final quota = (_balance?['monthlyQuotaMinutes'] as num?)?.toDouble() ?? 0;
    final consumed = (_balance?['consumedMinutes'] as num?)?.toDouble() ?? 0;
    final remain = (_balance?['remainingMinutes'] as num?)?.toDouble() ?? 0;
    String hoursAndMinutes(double minutes) {
      final normalized = minutes < 0 ? 0 : minutes;
      final hrs = (normalized / 60).toStringAsFixed(2);
      return '$hrs h\n${normalized.toInt()} min';
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchRequests();
        await _fetchBalance();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Permission Balance ($monthLabel)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickMonth,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Month'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _balanceTile('Quota', hoursAndMinutes(quota)),
              const SizedBox(width: 8),
              _balanceTile('Consumed', hoursAndMinutes(consumed)),
              const SizedBox(width: 8),
              _balanceTile('Remaining', hoursAndMinutes(remain)),
            ],
          ),
          const SizedBox(height: 12),
          if (_showFilters)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  items: _statusOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  decoration: const InputDecoration(labelText: 'Status'),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _selectedStatus = v);
                    await _fetchRequests();
                  },
                ),
              ),
            ),
          if (_showFilters) const SizedBox(height: 12),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: AppTabLoader(),
              ),
            )
          else if (_requests.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No permission requests found'),
              ),
            )
          else
            ..._requests.map((raw) {
              final req = raw is Map<String, dynamic>
                  ? raw
                  : Map<String, dynamic>.from(raw as Map);
              final status = (req['status'] ?? '').toString();
              final isPending = status == 'Pending';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _fmtDate(req['date']),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: _statusColor(status),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Type: ${_fmtType(req['type']?.toString())}'),
                      Text(
                        'Requested Minutes: ${req['requestedMinutes'] ?? 0}',
                      ),
                      if ((req['reason'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Reason: ${req['reason']}'),
                      ],
                      const SizedBox(height: 4),
                      Text('Applied: ${_fmtDate(req['createdAt'])}'),
                      if (isPending) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _cancelRequest(req['_id'].toString()),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _balanceTile(String title, String value) {
    IconData icon;
    switch (title.toLowerCase()) {
      case 'quota':
        icon = Icons.inventory_2_outlined;
        break;
      case 'consumed':
        icon = Icons.timelapse_outlined;
        break;
      case 'remaining':
        icon = Icons.check_circle_outline;
        break;
      default:
        icon = Icons.check_circle_outline;
        break;
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RequestPermissionDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const RequestPermissionDialog({super.key, required this.onSuccess});

  @override
  State<RequestPermissionDialog> createState() =>
      _RequestPermissionDialogState();
}

class _RequestPermissionDialogState extends State<RequestPermissionDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();
  DateTime _date = DateTime.now();
  String _type = 'both';
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;

  DateTime? _permissionDateOnly(dynamic value) {
    if (value == null) return null;
    try {
      final parsed = DateTime.parse(value.toString()).toLocal();
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  bool _isActivePermissionStatus(dynamic statusValue) {
    final status = (statusValue ?? '').toString().trim().toLowerCase();
    if (status.isEmpty) return true;
    return status != 'rejected' &&
        status != 'cancelled' &&
        status != 'canceled';
  }

  Future<bool> _hasExistingPermissionForDate(DateTime date) async {
    final target = DateTime(date.year, date.month, date.day);
    final result = await _requestService.getPermissionRequests(
      month: target.month,
      year: target.year,
    );
    if (result['success'] != true) return false;

    final data = result['data'];
    final List<dynamic> permissions = data is Map
        ? (data['permissions'] as List? ?? <dynamic>[])
        : (data is List ? data : <dynamic>[]);

    for (final raw in permissions) {
      if (raw is! Map) continue;
      final req = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw);
      if (!_isActivePermissionStatus(req['status'])) continue;
      final reqDate = _permissionDateOnly(req['date']);
      if (reqDate == null) continue;
      if (reqDate == target) return true;
    }

    return false;
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final minutes = int.tryParse(_minutesController.text.trim());
    final reason = _reasonController.text.trim();
    if (minutes == null || minutes <= 0) {
      SnackBarUtils.showSnackBar(
        context,
        'Requested minutes must be greater than 0',
        isError: true,
      );
      return;
    }
    if (reason.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Reason is required', isError: true);
      return;
    }

    final alreadyExists = await _hasExistingPermissionForDate(_date);
    if (!mounted) return;
    if (alreadyExists) {
      SnackBarUtils.showSnackBar(
        context,
        'Permission request already exists for this date',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await _requestService.createPermissionRequest(
      date: _date,
      type: _type,
      requestedMinutes: minutes,
      reason: reason,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      Navigator.of(context).pop();
      widget.onSuccess();
      final overlay = Navigator.of(context, rootNavigator: true).overlay;
      if (overlay != null && overlay.mounted) {
        showRequestSubmittedSuccessDialog(overlay.context);
      }
    } else {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to submit permission request',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header — back arrow + title
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 24),
                    color: AppColors.textPrimary,
                  ),
                  const Text(
                    'Request Permission',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date
                    _sectionLabel('Date'),
                    _buildDateField(date: _date, onTap: _pickDate),
                    const SizedBox(height: 20),

                    // Permission Type
                    _sectionLabel('Permission Type'),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      decoration: _fieldDecoration(),
                      items: const [
                        DropdownMenuItem(value: 'both', child: Text('Both')),
                        DropdownMenuItem(
                          value: 'lateArrival',
                          child: Text('Late Arrival'),
                        ),
                        DropdownMenuItem(
                          value: 'earlyExit',
                          child: Text('Early Exit'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'both'),
                    ),
                    const SizedBox(height: 20),

                    // Requested Minutes
                    _sectionLabel('Requested Minutes'),
                    TextFormField(
                      controller: _minutesController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      decoration: _fieldDecoration(hint: 'Enter minutes'),
                      validator: (value) {
                        final mins = int.tryParse((value ?? '').trim());
                        if (mins == null || mins <= 0) {
                          return 'Enter valid minutes';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Reason
                    _sectionLabel('Reason'),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 4,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      decoration: _fieldDecoration(
                        hint: 'Briefly describe your reason...',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter reason';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Submit Request',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.send_rounded, size: 18),
                                ],
                              ),
                      ),
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

  // ── Reference (Apply Leave / Request Loan) styling helpers ────────────────
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// Grey filled, borderless field decoration (amber focus).
  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textCaption),
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  /// Grey date card with a calendar icon — matches Apply Leave's date cards.
  Widget _buildDateField({required DateTime date, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              DateFormat('dd MMM yyyy').format(date),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- PAYSLIP TAB ---

class PayslipRequestsTab extends StatefulWidget {
  const PayslipRequestsTab({super.key});

  @override
  State<PayslipRequestsTab> createState() => _PayslipRequestsTabState();
}

class _PayslipRequestsTabState extends State<PayslipRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _requests = [];
  bool _isLoading = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Generated',
    'Rejected',
  ];

  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  int _totalPages = 0;
  bool _showFilters = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchRequests();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    _fetchRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    final result = await _requestService.getPayslipRequests(
      status: _selectedStatus,
      search: _searchController.text,
      startDate: _startDate,
      endDate: _endDate,
      page: _currentPage,
      limit: _itemsPerPage,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          if (result['data'] is Map) {
            _requests = result['data']['requests'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _totalPages = pagination['pages'] ?? 0;
              _currentPage = pagination['page'] ?? 1;
            }
          } else if (result['data'] is List) {
            _requests = result['data'];
            _totalPages = 1;
            _currentPage = 1;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch payslip requests',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _viewPayslip(String? requestId, {String? payslipUrl}) async {
    if (requestId == null || requestId.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Invalid payslip request id',
        isError: true,
      );
      return;
    }
    bool loadingShown = false;
    try {
      String? url = payslipUrl?.trim();
      // If URL is already present, open in browser directly (most reliable on mobile).
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      if (url == null || url.isEmpty) {
        loadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: AppTabLoader()),
        );
        final result = await _requestService.viewPayslipRequest(requestId);
        if (mounted) {
          Navigator.pop(context);
          loadingShown = false;
        }
        url = result['payslipUrl']?.toString();
        if (url == null || url.isEmpty) {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              result['message']?.toString(),
              fallback: 'Payslip not available yet',
            ),
            isError: true,
          );
          return;
        }
      }

      // View: open in browser for consistent and reliable behavior on mobile.
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Unable to open payslip link.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        if (loadingShown) Navigator.pop(context);
        SnackBarUtils.showSnackBar(
          context,
          'Error viewing payslip: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  // Helper function to convert month number or name to month name
  String _getMonthName(dynamic month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    if (month is int && month >= 1 && month <= 12) {
      return months[month - 1];
    } else if (month is String) {
      // If it's already a month name, return it
      if (months.contains(month)) {
        return month;
      }
      // Try to parse as number
      final monthNum = int.tryParse(month);
      if (monthNum != null && monthNum >= 1 && monthNum <= 12) {
        return months[monthNum - 1];
      }
    }
    return month?.toString() ?? 'Unknown';
  }

  // Helper function to get period text from request
  String _getPeriodText(Map<String, dynamic> req) {
    if (req['period'] != null) {
      return req['period'].toString();
    } else if (req['month'] != null) {
      final monthName = _getMonthName(req['month']);
      final year = req['year']?.toString() ?? '';
      return '$monthName $year'.trim();
    }
    return '-';
  }

  Future<void> _downloadPayslip(
    String requestId,
    String month,
    int year, {
    String? payslipUrl,
  }) async {
    bool loadingShown = false;
    try {
      String? url = payslipUrl?.trim();
      // If URL is already present, download via browser so it lands in device Downloads.
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) {
            SnackBarUtils.showSnackBar(
              context,
              'Downloading fileâ€¦ Check your browser downloads.',
              isError: false,
            );
          }
          return;
        }
      }
      if (url == null || url.isEmpty) {
        loadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: AppTabLoader()),
        );
        final result = await _requestService.downloadPayslipRequest(requestId);
        if (mounted) {
          Navigator.pop(context);
          loadingShown = false;
        }
        url = result['payslipUrl']?.toString().trim();
        if (url == null || url.isEmpty) {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              result['message']?.toString(),
              fallback: 'Payslip not available yet',
            ),
            isError: true,
          );
          return;
        }
      }

      // Download: always use browser so it downloads to device Downloads.
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Downloading fileâ€¦ Check your browser downloads.',
            isError: false,
          );
        }
        return;
      }
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Unable to start download.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        if (loadingShown) Navigator.pop(context);
        SnackBarUtils.showSnackBar(
          context,
          'Error downloading payslip: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  Future<void> _sharePayslipPdf({
    required String url,
    required String fileBaseName,
  }) async {
    bool loadingShown = false;
    try {
      final trimmed = url.trim();
      if (trimmed.isEmpty) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Payslip link not available yet',
            isError: true,
          );
        }
        return;
      }

      loadingShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: AppTabLoader()),
      );

      final result = await _requestService.getPdfBytesFromUrl(trimmed);
      if (mounted && loadingShown) {
        Navigator.pop(context);
        loadingShown = false;
      }

      if (result['success'] != true || result['data'] == null) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Unable to fetch payslip for sharing.',
            isError: true,
          );
        }
        return;
      }

      final bytes = result['data'] as List<int>;
      final isPdf =
          bytes.length >= 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46; // %PDF
      if (!isPdf) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Payslip file is not a valid PDF.',
            isError: true,
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final safeBase = fileBaseName.trim().isEmpty
          ? 'Payslip'
          : fileBaseName.trim();
      final file = File('${dir.path}/$safeBase.pdf');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: safeBase,
        text: safeBase,
      );
    } catch (e) {
      if (mounted) {
        if (loadingShown) Navigator.pop(context);
        SnackBarUtils.showSnackBar(
          context,
          'Error sharing payslip: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  Future<void> _fallbackOpenPayslipInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Payslip opened in browser. You can view or download it there.',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _openPdf(
    List<int> pdfBytes,
    String action, {
    String? month,
    int? year,
  }) async {
    try {
      // 1) Save PDF to app documents directory (visible via "App internal storage")
      final baseDir = await getApplicationDocumentsDirectory();
      final payslipsDir = Directory('${baseDir.path}/Payslips');
      if (!await payslipsDir.exists()) {
        await payslipsDir.create(recursive: true);
      }

      final fileName = month != null && year != null
          ? 'Payslip_${month}_$year.pdf'
          : 'Payslip_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${payslipsDir.path}/$fileName');

      await file.writeAsBytes(pdfBytes, flush: true);

      if (action == 'view') {
        // 2a) VIEW: open directly with default PDF viewer
        final result = await OpenFilex.open(file.path);

        if (result.type != ResultType.done) {
          SnackBarUtils.showSnackBar(
            context,
            'Unable to open payslip: ${result.message}',
            isError: true,
          );
        }
      } else {
        // 2b) DOWNLOAD: just save file, do not open
        SnackBarUtils.showSnackBar(
          context,
          'Payslip downloaded to: ${file.path}',
        );
      }
    } catch (e) {
      SnackBarUtils.showSnackBar(
        context,
        'Error handling PDF: ${e.toString()}',
        isError: true,
      );
    }
  }

  void _showPayslipDetails(Map<String, dynamic> req) {
    final appliedDate = req['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(req['createdAt']))
        : 'â€”';
    String approvedBy = 'â€”';
    String rejectedBy = 'â€”';
    final approver = req['approvedBy'];
    final rejector = req['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = 'â€”';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = 'â€”';
      } else {
        rejectedBy = 'System';
      }
    } else if (req['status'] == 'Rejected' && approver != null) {
      rejectedBy = approvedBy;
    }
    final rejectionReason = (req['actionReason'] ?? req['rejectionReason'])
        ?.toString()
        .trim();
    final isRejected = req['status'] == 'Rejected';

    final children = <Widget>[
      _payslipDetailRow('Period', _getPeriodText(req)),
      if (req['reason'] != null && req['reason'].toString().isNotEmpty)
        _payslipDetailRow('Reason', req['reason']),
      _payslipDetailRow('Applied Date', appliedDate),
      _payslipDetailRow('Status', req['status'] ?? ''),
      if (isRejected) ...[
        _payslipDetailRow('Rejected By', rejectedBy),
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          _payslipDetailRow('Rejection Reason', rejectionReason),
      ] else
        _payslipDetailRow('Approved By', approvedBy),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Payslip Request Details',
        icon: Icons.description,
        iconColor: AppColors.primary,
        children: children,
      ),
    );
  }

  Widget _payslipDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildPayslipCard(Map<String, dynamic> req) {
    final appliedDate = req['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(req['createdAt']))
        : '-';
    final approver = req['approvedBy'];
    final rejector = req['rejectedBy'];
    final isRejectedPayslip = req['status'] == 'Rejected';
    final approvedBy = approver != null
        ? (approver is Map ? approver['name'] : 'System')
        : '-';
    final rejectedBy = rejector != null
        ? (rejector is Map ? rejector['name'] : 'System')
        : (isRejectedPayslip && approver != null ? approvedBy : '-');

    // Get month name from month number or period
    String periodText = 'Payslip Request';
    if (req['period'] != null) {
      periodText = req['period'].toString();
    } else if (req['month'] != null) {
      final monthName = _getMonthName(req['month']);
      final year = req['year']?.toString() ?? '';
      periodText = '$monthName $year'.trim();
    }

    Color statusColor = Colors.grey;
    if (req['status'] == 'Generated' || req['status'] == 'Approved') {
      statusColor = AppColors.success;
    } else if (req['status'] == 'Rejected') {
      statusColor = AppColors.error;
    } else if (req['status'] == 'Pending') {
      statusColor = AppColors.warning;
    }

    final isApproved =
        req['status'] == 'Approved' || req['status'] == 'Generated';

    // Payslip URL from payroll (when approved and generated)
    final payroll = req['payrollId'];
    final String? payslipUrl = payroll is Map
        ? (payroll['payslipUrl']?.toString().trim())
        : null;
    final bool hasPayslipUrl = payslipUrl != null && payslipUrl.isNotEmpty;
    if (hasPayslipUrl) {
      statusColor = AppColors.success;
    }

    // Status label: approved but not yet generated vs approved and viewable
    String statusLabel = req['status'] ?? '';
    if (isApproved && !hasPayslipUrl) {
      statusLabel = 'Approved - wait for generation';
    }
    if (hasPayslipUrl) {
      statusLabel = 'Generated';
    }

    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showPayslipDetails(req),
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        radius: 18,
        child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.description,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period and Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            periodText,
                            style: AppTextStyles.headingSmall.copyWith(
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Details
                    if (req['reason'] != null &&
                        req['reason'].toString().isNotEmpty) ...[
                      _buildPayslipCardDetailRow(
                        Icons.info_outline,
                        'Reason',
                        req['reason'] ?? '',
                      ),
                      const SizedBox(height: 4),
                    ],
                    _buildPayslipCardDetailRow(
                      Icons.access_time,
                      'Applied',
                      appliedDate,
                    ),
                    if (isRejectedPayslip && rejectedBy != '-') ...[
                      const SizedBox(height: 4),
                      _buildPayslipCardDetailRow(
                        Icons.person_off_outlined,
                        'Rejected By',
                        rejectedBy,
                      ),
                    ] else if (!isRejectedPayslip && approvedBy != '-') ...[
                      const SizedBox(height: 4),
                      _buildPayslipCardDetailRow(
                        Icons.person,
                        'Approved By',
                        approvedBy,
                      ),
                    ],
                    // Download / Share actions â€“ show whenever payslip URL exists
                    if (hasPayslipUrl) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Share Payslip',
                            icon: const Icon(Icons.ios_share_rounded, size: 20),
                            color: AppColors.primary,
                            onPressed: () {
                              String monthName = 'Month';
                              int year = DateTime.now().year;
                              if (req['month'] != null && req['year'] != null) {
                                monthName = _getMonthName(req['month']);
                                final yr = req['year'];
                                if (yr is int) {
                                  year = yr;
                                } else if (yr is num) {
                                  year = yr.toInt();
                                } else if (yr is String) {
                                  year = int.tryParse(yr) ?? year;
                                }
                              } else {
                                final period = _getPeriodText(req);
                                final parts = period.split(' ');
                                if (parts.isNotEmpty) monthName = parts[0];
                                if (parts.length > 1) {
                                  final yr = int.tryParse(parts[1]);
                                  if (yr != null) year = yr;
                                }
                              }
                              _sharePayslipPdf(
                                url: payslipUrl,
                                fileBaseName: 'Payslip_$monthName',
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Download Payslip',
                            icon: const Icon(Icons.download_outlined, size: 20),
                            color: AppColors.primary,
                            onPressed: () {
                              final requestId = req['_id']?.toString();
                              if (requestId == null || requestId.isEmpty) {
                                SnackBarUtils.showSnackBar(
                                  context,
                                  'Invalid payslip request id',
                                  isError: true,
                                );
                                return;
                              }
                              String monthName = 'Month';
                              int year = DateTime.now().year;
                              if (req['month'] != null && req['year'] != null) {
                                monthName = _getMonthName(req['month']);
                                final yr = req['year'];
                                if (yr is int) {
                                  year = yr;
                                } else if (yr is num) {
                                  year = yr.toInt();
                                } else if (yr is String) {
                                  year = int.tryParse(yr) ?? year;
                                }
                              } else {
                                final period = _getPeriodText(req);
                                final parts = period.split(' ');
                                if (parts.isNotEmpty) monthName = parts[0];
                                if (parts.length > 1) {
                                  final yr = int.tryParse(parts[1]);
                                  if (yr != null) year = yr;
                                }
                              }
                              _downloadPayslip(
                                requestId,
                                monthName,
                                year,
                                payslipUrl: payslipUrl,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildPayslipCardDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF424242)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF424242),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: Color(0xFF424242)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void showRequestPayslipDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => RequestPayslipDialog(onSuccess: _fetchRequests),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePickerSameCalendar(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end.add(
          const Duration(hours: 23, minutes: 59, seconds: 59),
        );
      });
      _fetchRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls Column
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Reason, Month...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      _fetchRequests();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                                _fetchRequests();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _startDate == null
                                  ? 'Date'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                  _fetchRequests();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // List Body
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchRequests();
            },
            child: _isLoading
                ? const Center(child: AppTabLoader())
                : _requests.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No payslip requests found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    itemBuilder: (ctx, i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: FadeSlideIn(
                          delay: Duration(milliseconds: (i * 45).clamp(0, 270)),
                          child: _buildPayslipCard(_requests[i]),
                        ),
                      );
                    },
                  ),
          ),
        ),

        // Pagination Controls
        if (!_isLoading && _requests.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 140, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchRequests();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchRequests();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class RequestPayslipDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const RequestPayslipDialog({super.key, required this.onSuccess});

  @override
  State<RequestPayslipDialog> createState() => _RequestPayslipDialogState();
}

class _RequestPayslipDialogState extends State<RequestPayslipDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();
  final AuthService _authService = AuthService();

  bool _isBulkMode = false;
  String _month = 'January';
  final TextEditingController _yearController = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  List<dynamic> _existingRequests = [];
  final Set<String> _selectedMonths = {};
  DateTime? _joiningDate;

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _loadJoiningDateAndExistingRequests();
  }

  /// Parse joining date from API/prefs (ISO string or { "$date": "..." }).
  static DateTime? _parseJoiningDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    String? str;
    if (value is String) {
      str = value;
    } else if (value is Map && value.containsKey(r'$date')) {
      str = value[r'$date']?.toString();
    }
    if (str == null || str.isEmpty) return null;
    return DateTime.tryParse(str);
  }

  Future<void> _loadJoiningDateAndExistingRequests() async {
    final profileResult = await _authService.getProfile();
    DateTime? joining;
    if (profileResult['success'] == true && profileResult['data'] is Map) {
      final data = profileResult['data'] as Map<String, dynamic>;
      final staffData = data['staffData'];
      if (staffData is Map && staffData.containsKey('joiningDate')) {
        joining = _parseJoiningDate(staffData['joiningDate']);
      }
      if (joining == null && data.containsKey('joiningDate')) {
        joining = _parseJoiningDate(data['joiningDate']);
      }
    }
    final result = await _requestService.getPayslipRequests();
    if (mounted) {
      setState(() {
        _joiningDate = joining;
        if (result['success'] && result['data'] != null) {
          if (result['data'] is Map) {
            _existingRequests = result['data']['requests'] ?? [];
          } else if (result['data'] is List) {
            _existingRequests = result['data'];
          }
        }
        _clampMonthAndYearToAllowed();
      });
    }
  }

  int get _currentYear => DateTime.now().year;
  int get _currentMonth => DateTime.now().month;
  int get _joiningYear => _joiningDate?.year ?? _currentYear;
  int get _joiningMonth => _joiningDate?.month ?? 1;

  List<int> get _allowedYears {
    final joinYear = _joiningYear;
    final end = _currentYear;
    if (joinYear > end) return [end];
    return List.generate(end - joinYear + 1, (i) => joinYear + i);
  }

  int get _selectedYear {
    final y = int.tryParse(_yearController.text) ?? _currentYear;
    final allowed = _allowedYears;
    if (allowed.isEmpty) return _currentYear;
    if (y < allowed.first) return allowed.first;
    if (y > allowed.last) return allowed.last;
    return y;
  }

  List<String> get _allowedMonthsForSelectedYear {
    final year = _selectedYear;
    int first = 1;
    int last = 12;
    if (year == _joiningYear) first = _joiningMonth;
    // Only completed previous months â€“ exclude current month (payslip not ready for current month yet)
    if (year == _currentYear) last = _currentMonth - 1;
    if (first > last) return [];
    return _months.sublist(first - 1, last);
  }

  void _clampMonthAndYearToAllowed() {
    final allowedYears = _allowedYears;
    if (allowedYears.isEmpty) return;
    int year = int.tryParse(_yearController.text) ?? _currentYear;
    if (year < allowedYears.first || year > allowedYears.last) {
      _yearController.text = allowedYears.last.toString();
    }
    final allowedMonths = _allowedMonthsForSelectedYear;
    if (allowedMonths.isEmpty) return;
    if (!allowedMonths.contains(_month)) {
      _month = allowedMonths.last;
    }
    _selectedMonths.removeWhere((m) => !allowedMonths.contains(m));
  }

  bool _isDuplicateRequest(String month, int year) {
    // Convert month name to number for comparison
    final monthNumber = _months.indexOf(month) + 1;
    return _existingRequests.any((req) {
      final reqMonth = req['month'];
      // Handle both number and string formats
      final reqMonthNumber = reqMonth is int
          ? reqMonth
          : (reqMonth is String ? _months.indexOf(reqMonth) + 1 : 0);
      return reqMonthNumber == monthNumber && req['year'] == year;
    });
  }

  Future<void> _pickYear() async {
    final years = _allowedYears;
    if (years.isEmpty) return;
    final currentYear = _selectedYear;
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Year',
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: years.length,
                  itemBuilder: (context, index) {
                    final year = years[index];
                    return ListTile(
                      title: Text('$year'),
                      selected: year == currentYear,
                      onTap: () => Navigator.pop(context, year),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _yearController.text = picked.toString();
        _clampMonthAndYearToAllowed();
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final selectedYear =
        int.tryParse(_yearController.text) ?? DateTime.now().year;
    final reason = _reasonController.text.trim();

    if (_isBulkMode) {
      // Bulk request
      if (_selectedMonths.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Please select at least one month',
          isError: true,
        );
        return;
      }

      // Check for duplicates
      final duplicateMonths = _selectedMonths
          .where((month) => _isDuplicateRequest(month, selectedYear))
          .toList();

      if (duplicateMonths.isNotEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Requests already exist for: ${duplicateMonths.join(", ")}',
          isError: true,
        );
        return;
      }

      setState(() => _isSubmitting = true);
      // Convert month names to numbers (January = 1, December = 12)
      final monthNumbers = _selectedMonths
          .map((monthName) => _months.indexOf(monthName) + 1)
          .toList();
      final result = await _requestService.requestPayslip({
        'months': monthNumbers,
        'year': selectedYear,
        'reason': reason,
      });
      setState(() => _isSubmitting = false);

      if (mounted) {
        if (result['success']) {
          final overlay = Navigator.of(context, rootNavigator: true).overlay;
          widget.onSuccess();
          Navigator.pop(context);
          if (overlay != null && overlay.context.mounted) {
            showRequestSubmittedSuccessDialog(overlay.context);
          }
        } else {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              result['message']?.toString(),
              fallback: 'Failed to submit payslip requests',
            ),
            isError: true,
          );
        }
      }
    } else {
      // Single request
      if (_isDuplicateRequest(_month, selectedYear)) {
        SnackBarUtils.showSnackBar(
          context,
          'A payslip request for $_month $selectedYear already exists',
          isError: true,
        );
        return;
      }

      setState(() => _isSubmitting = true);
      // Convert month name to number (January = 1, December = 12)
      final monthNumber = _months.indexOf(_month) + 1;
      final result = await _requestService.requestPayslip({
        'month': monthNumber,
        'year': selectedYear,
        'reason': reason,
      });
      setState(() => _isSubmitting = false);

      if (mounted) {
        if (result['success']) {
          final overlay = Navigator.of(context, rootNavigator: true).overlay;
          widget.onSuccess();
          Navigator.pop(context);
          if (overlay != null && overlay.context.mounted) {
            showRequestSubmittedSuccessDialog(overlay.context);
          }
        } else {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              result['message']?.toString(),
              fallback: 'Failed to submit payslip request',
            ),
            isError: true,
          );
        }
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.description,
                          color: AppColors.primary,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Request Payslip',
                          style: AppTextStyles.headingLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Submit a new payslip request',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 28),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text('Single Month'),
                            selected: !_isBulkMode,
                            selectedColor: AppColors.primary.withOpacity(0.2),
                            onSelected: (selected) {
                              setState(() {
                                _isBulkMode = !selected;
                                if (!_isBulkMode) _selectedMonths.clear();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: Text('Bulk Months'),
                            selected: _isBulkMode,
                            selectedColor: AppColors.primary.withOpacity(0.2),
                            onSelected: (selected) {
                              setState(() {
                                _isBulkMode = selected;
                                if (_isBulkMode) {
                                  _month =
                                      _allowedMonthsForSelectedYear.isNotEmpty
                                      ? _allowedMonthsForSelectedYear.first
                                      : 'January';
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (!_isBulkMode) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              _allowedMonthsForSelectedYear.contains(_month)
                              ? _month
                              : (_allowedMonthsForSelectedYear.isNotEmpty
                                    ? _allowedMonthsForSelectedYear.first
                                    : 'January'),
                          items: _allowedMonthsForSelectedYear
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                          onChanged: _allowedMonthsForSelectedYear.isEmpty
                              ? null
                              : (val) => setState(() => _month = val!),
                          decoration: _inputDecoration(
                            'Month',
                            Icons.calendar_month,
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Select Months *',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _allowedMonthsForSelectedYear.map((month) {
                            final isSelected = _selectedMonths.contains(month);
                            return FilterChip(
                              label: Text(month),
                              selected: isSelected,
                              selectedColor: AppColors.primary.withOpacity(0.2),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedMonths.add(month);
                                  } else {
                                    _selectedMonths.remove(month);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      if (_selectedMonths.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Selected: ${_selectedMonths.length} month(s)',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    InkWell(
                      onTap: _pickYear,
                      borderRadius: BorderRadius.circular(16),
                      child: IgnorePointer(
                        child: TextFormField(
                          controller: _yearController,
                          readOnly: true,
                          style: TextStyle(fontWeight: FontWeight.w500),
                          decoration:
                              _inputDecoration(
                                'Year',
                                Icons.calendar_today,
                              ).copyWith(
                                hintText: 'Tap to select year',
                                suffixIcon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.grey,
                                ),
                              ),
                          validator: (val) => val == null || val.isEmpty
                              ? 'Year is required'
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 3,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Reason *',
                        Icons.note,
                      ).copyWith(hintText: 'Enter reason for payslip request'),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Reason is required'
                          : null,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isBulkMode
                                  ? 'Submit Bulk Request'
                                  : 'Submit Request',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
