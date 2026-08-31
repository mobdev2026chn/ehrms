import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/request_success_dialog.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';
import 'package:hrms/widgets/app_tab_loader.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/request_service.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_service.dart';
import '../../services/salary_service.dart';
import '../../utils/fine_calculation_util.dart';
import '../../utils/holiday_off_util.dart';
import '../../utils/absent_alert_helper.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import '../../widgets/oriented_image.dart';
import '../../utils/image_orientation.dart';
import '../../services/fcm_service.dart';

/// Source for an expense proof attachment: camera capture or file storage.
enum _ProofSource { camera, files }

/// How much of the working day a leave covers. Half-day is a DURATION that can be
/// applied to any leave type (Casual, Sick, …) — First Half or Second Half.
enum _LeaveDuration { full, firstHalf, secondHalf }

/// Returns true if [s] is the legacy standalone half-day leave *type* (case and
/// space insensitive). Backend may send "half day", "Half Day", "halfday", etc.
/// Half-day is now modelled as a duration, so this only matches legacy data.
bool _isHalfDayLeave(String? s) {
  if (s == null || s.isEmpty) return false;
  final n = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return n == 'halfday' || n == 'half';
}

/// True when a leave *record* (map from the API) is a half-day, independent of its
/// leaveType. Detects from session / halfDaySession / halfDayType / days == 0.5,
/// with the legacy 'Half Day' leaveType still recognised.
bool _isHalfDayLeaveRecord(Map leave) {
  if (_isHalfDayLeave(leave['leaveType']?.toString())) return true;
  final s = leave['session']?.toString();
  if (s == '1' || s == '2') return true;
  final hs = (leave['halfDaySession'] ?? leave['halfDayType'])
      ?.toString()
      .trim()
      .toLowerCase();
  if (hs == 'first half day' || hs == 'second half day') return true;
  final d = leave['days'];
  final days = d is num ? d.toDouble() : double.tryParse(d?.toString() ?? '');
  return days == 0.5;
}

/// Short label for a half-day leave's session ("First Half" / "Second Half").
/// Resolves from halfDaySession / halfDayType / session; empty when unknown.
String _halfDaySessionLabel(Map leave) {
  final hs = (leave['halfDaySession'] ?? leave['halfDayType'])
      ?.toString()
      .trim()
      .toLowerCase();
  if (hs == 'first half day') return 'First Half';
  if (hs == 'second half day') return 'Second Half';
  final s = leave['session']?.toString();
  if (s == '1') return 'First Half';
  if (s == '2') return 'Second Half';
  return 'Half Day';
}

/// True when [a] and [b] fall on the same calendar day (ignores time).
bool _isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Normalises a single `proofFiles` entry (a URL string, or a Map with a
/// `url`/`fileUrl` key) into a plain URL string.
String _proofUrlOf(dynamic proof) {
  if (proof is Map) {
    return proof['url']?.toString() ??
        proof['fileUrl']?.toString() ??
        proof.toString();
  }
  return proof.toString();
}

/// Builds the "Proof Files" section for an expense detail sheet: a header plus
/// one tappable "View Proof" row per uploaded document. Tapping a row opens the
/// document via [showProofDocument]. Returns an empty list when [proofs] is
/// empty so callers can spread it unconditionally.
List<Widget> buildProofFileRows(
  BuildContext context,
  RequestService requestService,
  List<dynamic> proofs,
) {
  if (proofs.isEmpty) return const [];
  return <Widget>[
    const SizedBox(height: 12),
    Text(
      'Proof Files:',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    ),
    const SizedBox(height: 6),
    ...proofs.map((proof) {
      final proofUrl = _proofUrlOf(proof);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          onTap: () => showProofDocument(context, requestService, proofUrl),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Icon(Icons.attach_file, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
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
  ];
}

/// Opens an uploaded expense proof. Downloads the file, then displays images
/// inline (zoomable) and opens PDFs (or any non-image file) with the device's
/// default viewer. Falls back to the browser if the file can't be downloaded.
Future<void> showProofDocument(
  BuildContext context,
  RequestService requestService,
  String url,
) async {
  final trimmed = url.trim();
  final uri = Uri.tryParse(trimmed);
  if (trimmed.isEmpty || uri == null || !uri.hasScheme) {
    if (context.mounted) {
      SnackBarUtils.showSnackBar(
        context,
        'Document link is not available.',
        isError: true,
      );
    }
    return;
  }

  bool loadingShown = false;
  try {
    loadingShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: AppTabLoader()),
    );

    final result = await requestService.getPdfBytesFromUrl(trimmed);
    if (context.mounted && loadingShown) {
      Navigator.pop(context);
      loadingShown = false;
    }

    if (result['success'] != true || result['data'] == null) {
      // Couldn't download the bytes; fall back to opening in the browser.
      await _openProofInBrowser(context, trimmed);
      return;
    }

    final bytes = List<int>.from(result['data'] as List);
    final isPdf =
        bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46; // %PDF magic number

    if (isPdf) {
      await _openProofFile(context, bytes, 'pdf');
    } else if (context.mounted) {
      _showProofImageDialog(context, bytes);
    }
  } catch (_) {
    if (context.mounted && loadingShown) {
      Navigator.pop(context);
    }
    await _openProofInBrowser(context, trimmed);
  }
}

void _showProofImageDialog(BuildContext context, List<int> bytes) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: const Text('Proof Document'),
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
            child: InteractiveViewer(
              child: OrientedImage.memory(
                Uint8List.fromList(bytes),
                errorBuilder: (ctx, error, stackTrace) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('Unable to display this document.'),
                  ),
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

Future<void> _openProofFile(
  BuildContext context,
  List<int> bytes,
  String extension,
) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/Expense_Proof_'
      '${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done && context.mounted) {
      SnackBarUtils.showSnackBar(
        context,
        'Unable to open document: ${result.message}',
        isError: true,
      );
    }
  } catch (e) {
    if (context.mounted) {
      SnackBarUtils.showSnackBar(
        context,
        'Error opening document: ${e.toString()}',
        isError: true,
      );
    }
  }
}

Future<void> _openProofInBrowser(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null && uri.hasScheme) {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
  }
  if (context.mounted) {
    SnackBarUtils.showSnackBar(
      context,
      'Unable to open document.',
      isError: true,
    );
  }
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

/// Label + icon for one segment of the top tab strip.
class _RequestTabSpec {
  final String label;
  final IconData icon;
  const _RequestTabSpec(this.label, this.icon);
}

class _MyRequestsScreenState extends State<MyRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Toggle to hide/show the Loan tab. Set to false to hide the Loan tab.
  static const bool _showLoanTab = false;

  /// All tab specs.
  static const List<_RequestTabSpec> _allTabSpecs = [
    _RequestTabSpec('Leave', Icons.event_available_rounded),
    _RequestTabSpec('Permission', Icons.fact_check_outlined),
    _RequestTabSpec('Expense', Icons.receipt_long_rounded),
    _RequestTabSpec('Payslip', Icons.description_outlined),
    _RequestTabSpec('Loan', Icons.account_balance_wallet_rounded),
  ];

  /// Tab specs in display order. Index maps 1:1 to the [TabBarView] children.
  static List<_RequestTabSpec> get _tabSpecs =>
      _showLoanTab ? _allTabSpecs : _allTabSpecs.where((t) => t.label != 'Loan').toList();

  // Keys let the app-bar filter button and the create FAB drive whichever tab
  // is currently visible (each tab exposes toggleFilters / show…Dialog).
  final GlobalKey<_LeaveRequestsTabState> _leaveKey = GlobalKey();
  final GlobalKey<_PermissionRequestsTabState> _permissionKey = GlobalKey();
  final GlobalKey<_ExpenseRequestsTabState> _expenseKey = GlobalKey();
  final GlobalKey<_PayslipRequestsTabState> _payslipKey = GlobalKey();
  final GlobalKey<_LoanRequestsTabState> _loanKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTabIndex
        .clamp(0, _tabSpecs.length - 1)
        .toInt();
    _tabController = TabController(
      length: _tabSpecs.length,
      vsync: this,
      initialIndex: initial,
    );
    _tabController.addListener(() {
      // Rebuild immediately so the IndexedStack swaps to the tapped tab without
      // waiting for the indicator animation to settle, and the FAB label tracks
      // the active tab. Notify the dashboard only once the change has settled.
      setState(() {});
      if (!_tabController.indexIsChanging) {
        widget.onTabIndexChanged?.call(_tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MyRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabController.length != _tabSpecs.length) {
      _tabController.dispose();
      final initial = widget.initialTabIndex
          .clamp(0, _tabSpecs.length - 1)
          .toInt();
      _tabController = TabController(
        length: _tabSpecs.length,
        vsync: this,
        initialIndex: initial,
      );
      _tabController.addListener(() {
        setState(() {});
        if (!_tabController.indexIsChanging) {
          widget.onTabIndexChanged?.call(_tabController.index);
        }
      });
    } else if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      final target = widget.initialTabIndex
          .clamp(0, _tabSpecs.length - 1)
          .toInt();
      if (_tabController.index != target) {
        _tabController.animateTo(target);
      }
    }
    if (widget.isActiveTab == true && oldWidget.isActiveTab != true) {
      _refreshActiveTab();
    }
  }

  /// Refreshes whichever tab is currently visible.
  void _refreshActiveTab() {
    switch (_tabController.index) {
      case 0:
        _leaveKey.currentState?.refresh();
        break;
      case 1:
        _permissionKey.currentState?.refresh();
        break;
      case 2:
        _expenseKey.currentState?.refresh();
        break;
      case 3:
        _payslipKey.currentState?.refresh();
        break;
      case 4:
        if (_showLoanTab) _loanKey.currentState?.refresh();
        break;
    }
  }

  /// App-bar funnel → toggle the active tab's filter panel.
  void _toggleActiveFilters() {
    switch (_tabController.index) {
      case 0:
        _leaveKey.currentState?.toggleFilters();
        break;
      case 1:
        _permissionKey.currentState?.toggleFilters();
        break;
      case 2:
        _expenseKey.currentState?.toggleFilters();
        break;
      case 3:
        _payslipKey.currentState?.toggleFilters();
        break;
      case 4:
        if (_showLoanTab) _loanKey.currentState?.toggleFilters();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('My Requests', style: AppTextStyles.headingMedium),
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: _toggleActiveFilters,
            icon: const Icon(Icons.filter_alt_outlined),
            color: AppColors.primary,
          ),
        ],
      ),
      drawer: AppDrawer(
        currentIndex: widget.dashboardTabIndex ?? 1,
        onNavigateToIndex: widget.onNavigateToIndex,
      ),
      // The create-request action now lives in each tab's bottom bar
      // (_PaginationBar), next to the page numbers — no floating FAB.
      body: Column(
        children: [
          _buildTabStrip(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                LeaveRequestsTab(
                  key: _leaveKey,
                  isVisible: () => _tabController.index == 0,
                ),
                PermissionRequestsTab(
                  key: _permissionKey,
                  isVisible: () => _tabController.index == 1,
                ),
                ExpenseRequestsTab(
                  key: _expenseKey,
                  isVisible: () => _tabController.index == 2,
                ),
                PayslipRequestsTab(
                  key: _payslipKey,
                ),
                if (_showLoanTab)
                  LoanRequestsTab(
                    key: _loanKey,
                    isVisible: () => _tabController.index == 4,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The top tab strip: five equal segments occupying the full screen width.
  Widget _buildTabStrip() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(3),
        indicator: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        dividerColor: Colors.transparent,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        tabs: _tabSpecs
            .map(
              (t) => Tab(
                height: 56,
                iconMargin: const EdgeInsets.only(bottom: 3),
                icon: Icon(t.icon, size: 20),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(t.label, maxLines: 1),
                ),
              ),
            )
            .toList(),
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
                              SnackBarUtils.showSnackBar(
                                context,
                                'Select start and end date in the calendar',
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
                            () => focusedDay = _clampDay(
                              focused,
                              firstDay,
                              lastDay,
                            ),
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

/// Shared bottom action bar for the request tabs. It hosts the page-number
/// pager on the left (prev arrow → up to three numbers → next arrow) and the
/// tab's "create request" button on the right, both inside a single white
/// footer strip. The pager only appears when there's more than one page; the
/// create button only appears when [onCreate] is supplied. When neither is
/// needed the bar collapses to nothing.
///
/// The pager window slides so its right edge tracks the current page — once
/// you're past page 3 it shows the latest reachable pages (6 pages, last page
/// → 4 5 6). The current page is filled; tapping any other number jumps to it.
class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageSelected;

  /// Trailing create-request action. When [onCreate] is null the button is
  /// omitted (e.g. read-only tabs like payslips).
  final String? createLabel;
  final VoidCallback? onCreate;

  /// When non-empty, surfaced as a tap-tooltip on the create button (e.g. the
  /// permission fine notice for a quota-0 / disabled / unconfigured shift, or the
  /// out-of-session gating message). It is purely informational — the button's
  /// [onCreate] still fires on tap.
  final String? createTooltip;

  /// Optional handle to the create button's [Tooltip] so the owner can surface
  /// the tooltip programmatically (e.g. show the gating message when the request
  /// is blocked because the user is out of session). Only attached when
  /// [createTooltip] is non-empty.
  final GlobalKey<TooltipState>? createTooltipKey;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageSelected,
    this.createLabel,
    this.onCreate,
    this.createTooltip,
    this.createTooltipKey,
  });

  /// Up to three contiguous page numbers. The window's right edge follows the
  /// current page so the latest pages stay visible; near the start it fills
  /// forward so three numbers still show (page 1 of 6 → 1 2 3).
  List<int> _visiblePages() {
    if (totalPages <= 1) return [1];
    var start = (currentPage - 2).clamp(1, totalPages);
    final end = (start + 2).clamp(1, totalPages);
    start = (end - 2).clamp(1, totalPages); // slide back to keep three numbers
    return [for (var p = start; p <= end; p++) p];
  }

  Widget _pageChip(int page) {
    final isCurrent = page == currentPage;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: isCurrent ? null : () => onPageSelected(page),
      child: Container(
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isCurrent ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent
                ? AppColors.primary
                : AppColors.primary.withOpacity(0.3),
          ),
        ),
        child: Text(
          '$page',
          style: TextStyle(
            color: isCurrent ? Colors.white : AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 22,
          color: enabled ? AppColors.primary : Colors.grey.shade400,
        ),
      ),
    );
  }

  Widget _pager() {
    final pages = _visiblePages();
    // Scrolls horizontally as a fallback so it can never overflow on very
    // narrow screens while the next arrow stays right after the last number.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(
            Icons.chevron_left,
            currentPage > 1,
            () => onPageSelected(currentPage - 1),
          ),
          for (final p in pages) ...[const SizedBox(width: 6), _pageChip(p)],
          const SizedBox(width: 6),
          _arrow(
            Icons.chevron_right,
            currentPage < totalPages,
            () => onPageSelected(currentPage + 1),
          ),
        ],
      ),
    );
  }

  Widget _createButton() {
    final button = ElevatedButton.icon(
      onPressed: onCreate,
      icon: const Icon(Icons.add, size: 20),
      label: Text(
        createLabel ?? '',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final tip = createTooltip;
    if (tip == null || tip.trim().isEmpty) return button;
    // Show the notice on tap (fine notice, or the out-of-session gating message
    // surfaced programmatically by the owner). The button still fires [onCreate].
    return Tooltip(
      key: createTooltipKey,
      message: tip,
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: false,
      showDuration: const Duration(seconds: 4),
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPager = totalPages > 1;
    final hasButton = onCreate != null;
    if (!showPager && !hasButton) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            // Pager takes the free space on the left; otherwise a spacer pushes
            // the create button to the right edge.
            if (showPager) Expanded(child: _pager()) else const Spacer(),
            if (hasButton) ...[const SizedBox(width: 8), _createButton()],
          ],
        ),
      ),
    );
  }
}

// --- LEAVE TAB ---

class LeaveRequestsTab extends StatefulWidget {
  /// Returns true when this tab is the one currently visible in the parent's
  /// IndexedStack. Used to suppress load-error toasts for background tabs, which
  /// all fetch at screen open and would otherwise pop up while the user is on a
  /// different tab. Null is treated as visible.
  final bool Function()? isVisible;

  const LeaveRequestsTab({super.key, this.isVisible});

  @override
  State<LeaveRequestsTab> createState() => _LeaveRequestsTabState();
}

class _LeaveRequestsTabState extends State<LeaveRequestsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final RequestService _requestService = RequestService();
  List<dynamic> _leaves = [];
  List<dynamic> _leaveBalances = [];
  bool _isLoading = true;
  bool _isLoadingBalances = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Approved',
    'Pending',
    'Rejected',
  ];
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 5;
  int _totalPages = 0;
  bool _showFilters = false;
  bool _isTableView = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  Future<void> _cancelLeave(Map<String, dynamic> leave) async {
    final leaveId = leave['_id']?.toString() ?? leave['id']?.toString();
    if (leaveId == null || leaveId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Leave Request', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: const Text('Are you sure you want to cancel this leave request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Yes, Cancel', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final res = await _requestService.cancelLeaveRequest(leaveId);
    if (!mounted) return;
    if (res['success'] == true) {
      SnackBarUtils.showSnackBar(context, res['message'] ?? 'Leave request cancelled');
      _fetchLeaves();
    } else {
      SnackBarUtils.showSnackBar(
        context,
        res['message'] ?? 'Failed to cancel leave request',
        isError: true,
      );
    }
  }

  void refresh() {
    // Background refresh (e.g. returning to the screen): keep the current list
    // on screen instead of flashing the loader over it.
    _fetchLeaves(showLoader: false);
  }

  @override
  void initState() {
    super.initState();
    // Date filter is single-date only; start unfiltered (no range).
    _startDate = null;
    _endDate = null;
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
          // Show every configured leave type as a card. This is the same set
          // the Apply Leave dropdown offers (template leaveTypes + Unpaid Leave);
          // do NOT filter out 'paid'/'paid leave' — those are now legitimate
          // admin-configured types, not the old synthetic aggregate pool entry,
          // so dropping them left configured types missing from the dashboard.
          _leaveBalances = List<dynamic>.from(result['data'] as List);
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

  Future<void> _fetchLeaves({bool showLoader = true}) async {
    _fetchLeaveBalances(); // Also refresh balances
    if (showLoader) setState(() => _isLoading = true);
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
            final raw = result['data']['requests'] ?? result['data']['leaves'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _leaves = List<Map<String, dynamic>>.from(raw as List);
              _totalPages = pagination['pages'] ?? 1;
              _currentPage = pagination['page'] ?? 1;
            } else {
              final all = List<Map<String, dynamic>>.from(raw as List);
              _totalPages = (all.length / _itemsPerPage).ceil().clamp(1, 999);
              _leaves = all.skip((_currentPage - 1) * _itemsPerPage).take(_itemsPerPage).toList();
            }
          } else if (result['data'] is List) {
            final all = List<Map<String, dynamic>>.from(result['data'] as List);
            _totalPages = (all.length / _itemsPerPage).ceil().clamp(1, 999);
            _leaves = all.skip((_currentPage - 1) * _itemsPerPage).take(_itemsPerPage).toList();
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (widget.isVisible?.call() ?? true) {
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
  }

  /// Pick from-date and to-date in same calendar; leaves and balances are shown for that range.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        _endDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
          999,
        );
      });
      _fetchLeaves();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
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
            : '-');
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
    String approvedBy = '-';
    String rejectedBy = '-';
    final approver = leave['approvedBy'];
    final rejector = leave['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = '-';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = '-';
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
          if (_isHalfDayLeaveRecord(leave))
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
          ] else if (leave['status'] == 'Approved')
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

  static String _trimBalanceNum(num n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }

  Widget _buildWebLeaveTopSection() {
        int approvedCount = 0;
        int rejectedCount = 0;
        int pendingCount = 0;
        for (final l in _leaves) {
          final s = l['status']?.toString();
          if (s == 'Approved') {
            approvedCount++;
          } else if (s == 'Rejected') {
            rejectedCount++;
          } else if (s == 'Pending') {
            pendingCount++;
          }
        }
        final totalRequests = _leaves.length;

        num totalAvailableLeaves = 0;
        for (final b in _leaveBalances) {
          if (b is Map) {
            final total = (b['allocated'] as num? ?? 0) + (b['carryForwardBalance'] as num? ?? 0);
            final used = (b['takenCount'] as num? ?? b['used'] as num? ?? 0);
            final avail = b['remaining'] as num? ?? b['availableBalance'] as num? ?? (total > used ? total - used : 0);
            totalAvailableLeaves += avail;
          }
        }

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF1F5F9)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.calendar_month_outlined,
                                color: Color(0xFFEFAA1F),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Leave Entitlements & Balances',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'leaves',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Available: ',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEFAA1F),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                _trimBalanceNum(totalAvailableLeaves),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                    ),
                    child: Row(
                      children: const [
                        Expanded(
                          flex: 4,
                          child: Text(
                            'TYPE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'ALLOCATED',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'USED',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'AVAILABLE',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_leaveBalances.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No leave balances found',
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    )
                  else
                    ..._leaveBalances.map((b) {
                      final name = (b['leaveType'] ?? b['name'] ?? 'Leave').toString();
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : 'L';
                      final total = (b['allocated'] as num? ?? 0) + (b['carryForwardBalance'] as num? ?? 0);
                      final used = (b['takenCount'] as num? ?? b['used'] as num? ?? 0);
                      final avail = b['remaining'] as num? ?? b['availableBalance'] as num? ?? (total > used ? total - used : 0);
                      final isCasual = name.toLowerCase().contains('casual');
                      final badgeBg = isCasual ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB);
                      final badgeColor = isCasual ? const Color(0xFF047857) : const Color(0xFFD97706);

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: badgeBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E293B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const Text(
                                          'Paid • Carry Forward',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _trimBalanceNum(total),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _trimBalanceNum(used),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '${_trimBalanceNum(avail)} day(s)',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFEFAA1F),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF1F5F9)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.mail_outline_rounded,
                          color: Color(0xFFEFAA1F),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Total Requests',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFEFAA1F), width: 3),
                          color: Colors.white,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$totalRequests',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFEFAA1F),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Approved',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                ),
                                Text(
                                  '$approvedCount',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                                ),
                              ],
                            ),
                            const Divider(height: 10, color: Color(0xFFF1F5F9)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Rejected',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                ),
                                Text(
                                  '$rejectedCount',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFF43F5E)),
                                ),
                              ],
                            ),
                            const Divider(height: 10, color: Color(0xFFF1F5F9)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Pending',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                ),
                                Text(
                                  '$pendingCount',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFEFAA1F)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$totalRequests request(s) total',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }

      Widget _buildControlBar() {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Leave Requests',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => setState(() => _isTableView = false),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: !_isTableView ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: !_isTableView
                                  ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4)]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.grid_view_rounded,
                                  size: 14,
                                  color: !_isTableView ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Cards',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: !_isTableView ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _isTableView = true),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isTableView ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _isTableView
                                  ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4)]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.table_rows_rounded,
                                  size: 14,
                                  color: _isTableView ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Table',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _isTableView ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                          ),
                        ),
                        onChanged: (val) {
                          if (_debounce?.isActive ?? false) _debounce!.cancel();
                          _debounce = Timer(const Duration(milliseconds: 400), () {
                            _fetchLeaves();
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _statusOptions.contains(_selectedStatus) ? _selectedStatus : _statusOptions.first,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                        items: _statusOptions
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
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
                ],
              ),
            ],
          ),
        );
      }

      Widget _buildLeaveCard(Map<String, dynamic> leave) {
        final start = DateFormat('MMM dd, yyyy').format(DateTime.parse(leave['startDate']).toLocal());
        final end = DateFormat('MMM dd, yyyy').format(DateTime.parse(leave['endDate']).toLocal());
        final status = leave['status']?.toString() ?? 'Pending';
        final isPending = status.toLowerCase() == 'pending';
        final isApproved = status.toLowerCase() == 'approved';
        final isRejected = status.toLowerCase() == 'rejected';

        final Color statusBg = isApproved
            ? const Color(0xFFECFDF5)
            : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
        final Color statusBorder = isApproved
            ? const Color(0xFFA7F3D0)
            : (isRejected ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
        final Color statusText = isApproved
            ? const Color(0xFF059669)
            : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));

        final leaveType = leave['leaveType']?.toString() ?? 'Leave';
        final days = leave['days']?.toString() ?? '1';
        final reason = leave['reason']?.toString() ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showLeaveDetails(leave),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 15,
                                  color: Color(0xFFEFAA1F),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isHalfDayLeaveRecord(leave) ? '$leaveType (Half Day)' : leaveType,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusBorder),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 18, color: Color(0xFFF1F5F9)),
                    Row(
                      children: [
                        const Icon(Icons.date_range_outlined, size: 14, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 6),
                        Text(
                          '$start ➔ $end',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$days Day(s)',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Reason: $reason',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (isPending) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelLeave(leave),
                          icon: const Icon(Icons.cancel_outlined, size: 14, color: Color(0xFFDC2626)),
                          label: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFFECACA)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }

  Widget _buildLeaveTableView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            headingTextStyle: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
            dataTextStyle: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            columns: const [
              DataColumn(label: Text('LEAVE TYPE')),
              DataColumn(label: Text('START DATE')),
              DataColumn(label: Text('END DATE')),
              DataColumn(label: Text('DAYS')),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('REASON')),
              DataColumn(label: Text('ACTION')),
            ],
            rows: _leaves.map((leave) {
              final start = DateFormat('MMM dd, yyyy').format(DateTime.parse(leave['startDate']).toLocal());
              final end = DateFormat('MMM dd, yyyy').format(DateTime.parse(leave['endDate']).toLocal());
              final status = leave['status']?.toString() ?? 'Pending';
              final isPending = status.toLowerCase() == 'pending';
              final isApproved = status.toLowerCase() == 'approved';
              final isRejected = status.toLowerCase() == 'rejected';

              final Color statusBg = isApproved
                  ? const Color(0xFFECFDF5)
                  : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
              final Color statusBorder = isApproved
                  ? const Color(0xFFA7F3D0)
                  : (isRejected ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
              final Color statusText = isApproved
                  ? const Color(0xFF059669)
                  : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));

              final leaveType = leave['leaveType']?.toString() ?? 'Leave';
              final days = leave['days']?.toString() ?? '1';
              final reason = leave['reason']?.toString() ?? '-';

              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      _isHalfDayLeaveRecord(leave) ? '$leaveType (Half Day)' : leaveType,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  DataCell(Text(start)),
                  DataCell(Text(end)),
                  DataCell(Text(days, style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusBorder),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: statusText,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    isPending
                        ? OutlinedButton(
                            onPressed: () => _cancelLeave(leave),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFECACA)),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel_outlined, size: 12, color: Color(0xFFDC2626)),
                                SizedBox(width: 4),
                                Text(
                                  'Cancel',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                          )
                        : const Text('-', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchLeaves(showLoader: false);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Top Balances & Summary Section
                _buildWebLeaveTopSection(),

                // Search & Filter & View Mode Switcher
                _buildControlBar(),

                // Body: Loader / Empty / Cards / Table
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.35,
                    child: const Center(child: AppTabLoader()),
                  )
                else if (_leaves.isEmpty)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.35,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFBEB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.calendar_today_outlined,
                              size: 40,
                              color: Color(0xFFEFAA1F),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No leave requests found',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_isTableView)
                  _buildLeaveTableView()
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      children: [
                        for (int i = 0; i < _leaves.length; i++)
                          FadeSlideIn(
                            delay: Duration(
                              milliseconds: (i * 40).clamp(0, 240),
                            ),
                            child: _buildLeaveCard(_leaves[i]),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bottom action bar: page numbers & Apply Leave button
        _PaginationBar(
          currentPage: _currentPage,
          totalPages: _totalPages,
          onPageSelected: (page) {
            setState(() => _currentPage = page);
            _fetchLeaves();
          },
          createLabel: 'Apply Leave',
          onCreate: showApplyLeaveDialog,
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
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _leaveTypeOptions = [];
  Map<String, dynamic>? _assignedTemplate;
  String? _selectedLeaveTypeName;
  bool _isHalfDay = false;
  String _halfDaySession = '1st Half'; // '1st Half' | '2nd Half'
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _reasonController = TextEditingController();
  String? _errorMessage;
  bool _isLoadingTypes = true;
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _holidays = [];
  List<dynamic> _existingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingTypes = true);
    await Future.wait([
      _fetchLeaveTypesAndBalances(),
      _fetchHolidaysAndProfile(),
      _fetchExistingRequests(),
    ]);
    if (mounted) {
      setState(() => _isLoadingTypes = false);
    }
  }

  Future<void> _fetchLeaveTypesAndBalances() async {
    try {
      final res = await _requestService.getLeaveTypesForApply();
      if (res['success'] == true) {
        final list = List<dynamic>.from(res['data'] as List? ?? []);
        final template = res['leaveTemplate'] as Map<String, dynamic>?;
        if (template != null) {
          _assignedTemplate = template;
        }

        final options = <Map<String, dynamic>>[];
        for (final item in list) {
          if (item is Map) {
            final name = (item['name'] ?? item['type'] ?? '').toString().trim();
            if (name.isEmpty || name.toLowerCase() == 'half day') continue;
            final type = (item['type'] ?? 'paid').toString().toLowerCase();
            final num? avail = item['availableBalance'] as num? ?? item['days'] as num?;
            final num? alloc = item['allocated'] as num? ?? item['days'] as num?;
            final num? used = item['used'] as num?;

            options.add({
              'label': name,
              'value': name,
              'badge': name.isNotEmpty ? name[0].toUpperCase() : 'L',
              'badgeBg': type == 'paid'
                  ? const Color(0xFFECFDF5)
                  : (type == 'unpaid' ? const Color(0xFFFAF5FF) : const Color(0xFFFFFBEB)),
              'badgeText': type == 'paid'
                  ? const Color(0xFF059669)
                  : (type == 'unpaid' ? const Color(0xFF9333EA) : const Color(0xFFD97706)),
              'balance': avail?.toDouble() ?? 0.0,
              'allocated': alloc?.toDouble(),
              'used': used?.toDouble() ?? 0.0,
              'isUnpaid': type == 'unpaid',
              'isPredefinedUnpaid': false,
              'subtext': '${avail ?? 0} day(s) available ($type)',
            });
          }
        }

        // Always add the standard Unpaid option as in Web App
        options.add({
          'label': 'Unpaid',
          'value': 'Unpaid',
          'badge': 'U',
          'badgeBg': const Color(0xFFFAF5FF),
          'badgeText': const Color(0xFF9333EA),
          'balance': null,
          'allocated': null,
          'used': null,
          'isUnpaid': true,
          'isPredefinedUnpaid': true,
          'subtext': 'Loss of Pay (Unpaid)',
        });

        _leaveTypeOptions = options;
        if (_leaveTypeOptions.isNotEmpty && _selectedLeaveTypeName == null) {
          _selectedLeaveTypeName = _leaveTypeOptions.first['value'] as String;
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchHolidaysAndProfile() async {
    try {
      final res = await _authService.getProfile();
      if (res['success'] == true) {
        final data = res['data'] as Map<String, dynamic>?;
        final template = data?['holidayTemplate'] as Map<String, dynamic>? ??
            data?['staffData']?['holidayTemplate'] as Map<String, dynamic>?;
        final hols = template?['holidays'] as List? ?? [];
        _holidays = hols.map((h) => Map<String, dynamic>.from(h as Map)).toList();
      }
    } catch (_) {}
  }

  Future<void> _fetchExistingRequests() async {
    try {
      final res = await _requestService.getLeaveRequests(page: 1, limit: 100);
      if (res['success'] == true) {
        if (res['data'] is Map) {
          _existingRequests = res['data']['requests'] ?? [];
        } else if (res['data'] is List) {
          _existingRequests = res['data'];
        }
      }
    } catch (_) {}
  }

  Map<String, dynamic>? get _selectedOption {
    if (_selectedLeaveTypeName == null) return null;
    return _leaveTypeOptions.firstWhere(
      (o) => o['value'] == _selectedLeaveTypeName,
      orElse: () => _leaveTypeOptions.isNotEmpty ? _leaveTypeOptions.first : {},
    );
  }

  Future<void> _pickDateFor(bool isStart) async {
    final DateTime initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final DateTime? picked = await _showWebStyledDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _errorMessage = null;
        if (_isHalfDay) {
          _startDate = picked;
          _endDate = picked;
        } else if (isStart) {
          _startDate = picked;
          if (_endDate == null || _endDate!.isBefore(picked)) {
            _endDate = picked;
          }
        } else {
          _endDate = picked;
          if (_startDate == null || picked.isBefore(_startDate!)) {
            _startDate = picked;
          }
        }
      });
    }
  }

  Future<DateTime?> _showWebStyledDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime navDate = DateTime(initialDate.year, initialDate.month, 1);
    DateTime? selectedDate = initialDate;

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final daysInMonth = DateTime(navDate.year, navDate.month + 1, 0).day;
            final firstWeekday = DateTime(navDate.year, navDate.month, 1).weekday % 7; // 0=Sun, 1=Mon...

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x25000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Month & Navigation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 22, color: Color(0xFF64748B)),
                          onPressed: () {
                            setDialogState(() {
                              navDate = DateTime(navDate.year, navDate.month - 1, 1);
                            });
                          },
                        ),
                        Text(
                          DateFormat('MMMM yyyy').format(navDate),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF64748B)),
                          onPressed: () {
                            setDialogState(() {
                              navDate = DateTime(navDate.year, navDate.month + 1, 1);
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFFF1F5F9), height: 16),
                    // Weekday headers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        Text('SU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('MO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('TU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('WE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('TH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('FR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('SA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Days Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: firstWeekday + daysInMonth,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemBuilder: (c, index) {
                        if (index < firstWeekday) {
                          return const SizedBox.shrink();
                        }
                        final dayNumber = index - firstWeekday + 1;
                        final currentDay = DateTime(navDate.year, navDate.month, dayNumber);
                        final isSelected = selectedDate != null &&
                            selectedDate!.year == currentDay.year &&
                            selectedDate!.month == currentDay.month &&
                            selectedDate!.day == currentDay.day;

                        return InkWell(
                          onTap: () {
                            Navigator.pop(ctx, currentDay);
                          },
                          borderRadius: BorderRadius.circular(100),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEFAA1F) : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLeaveTypePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Select Leave Type',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _leaveTypeOptions.length,
                  separatorBuilder: (_, __) => const Divider(color: Color(0xFFF1F5F9), height: 1),
                  itemBuilder: (ctx, index) {
                    final opt = _leaveTypeOptions[index];
                    final isSelected = opt['value'] == _selectedLeaveTypeName;
                    final isPredefinedUnpaid = opt['isPredefinedUnpaid'] == true;
                    final num? bal = opt['balance'] as num?;

                    return ListTile(
                      onTap: () {
                        setState(() {
                          _selectedLeaveTypeName = opt['value'] as String;
                          _errorMessage = null;
                        });
                        Navigator.pop(sheetCtx);
                      },
                      leading: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: opt['badgeBg'] as Color? ?? const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          opt['badge'] as String? ?? 'L',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: opt['badgeText'] as Color? ?? const Color(0xFFEFAA1F),
                          ),
                        ),
                      ),
                      title: Text(
                        opt['label'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? const Color(0xFFEFAA1F) : const Color(0xFF0F172A),
                        ),
                      ),
                      subtitle: opt['subtext'] != null
                          ? Text(
                              opt['subtext'] as String,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isPredefinedUnpaid && bal != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: bal > 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: bal > 0 ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                                ),
                              ),
                              child: Text(
                                '${bal.toInt()} Left',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: bal > 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle_rounded, color: Color(0xFFEFAA1F), size: 18),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleApplyLeaveSubmit() async {
    setState(() => _errorMessage = null);

    if (_selectedLeaveTypeName == null || _selectedLeaveTypeName!.isEmpty) {
      setState(() => _errorMessage = 'Please select a leave type');
      return;
    }

    if (_startDate == null) {
      setState(() => _errorMessage = 'Please select start date');
      return;
    }

    if (!_isHalfDay && _endDate == null) {
      setState(() => _errorMessage = 'Please select end date');
      return;
    }

    final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final end = _isHalfDay
        ? start
        : DateTime(_endDate!.year, _endDate!.month, _endDate!.day);

    if (start.isAfter(end)) {
      setState(() => _errorMessage = 'Start date cannot be after end date');
      return;
    }

    if (_reasonController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a reason for your leave');
      return;
    }

    final double duration = _isHalfDay
        ? 0.5
        : (end.difference(start).inDays + 1).toDouble();

    // Check Balance (only for paid leave)
    final opt = _selectedOption;
    if (opt != null && opt['isPredefinedUnpaid'] != true) {
      final double avail = (opt['balance'] as num?)?.toDouble() ?? 0.0;
      if (duration > avail) {
        setState(() {
          _errorMessage = 'Insufficient leave balance. You only have ${avail.toInt()} day(s) available.';
        });
        return;
      }
    }

    // Check Overlap with Holidays
    final List<String> selectedDateStrings = [];
    DateTime cur = start;
    while (!cur.isAfter(end)) {
      selectedDateStrings.add(DateFormat('yyyy-MM-dd').format(cur));
      cur = cur.add(const Duration(days: 1));
    }

    final matchedHolidays = _holidays.where((h) {
      final rawDate = h['date']?.toString() ?? '';
      String hKey = '';
      if (rawDate.length >= 10) {
        hKey = rawDate.substring(0, 10);
      }
      return selectedDateStrings.contains(hKey);
    }).toList();

    if (matchedHolidays.isNotEmpty) {
      final names = matchedHolidays.map((h) => h['name']?.toString() ?? 'Holiday').join(', ');
      setState(() => _errorMessage = 'Cannot apply for leave on a holiday: $names');
      return;
    }

    // Check Overlap with existing Approved Requests
    final hasOverlap = _existingRequests.any((req) {
      if (req is! Map) return false;
      final status = (req['status'] ?? '').toString();
      if (status != 'Approved') return false;
      final sStr = (req['startDate'] ?? '').toString();
      final eStr = (req['endDate'] ?? '').toString();
      if (sStr.length < 10 || eStr.length < 10) return false;
      final exStart = sStr.substring(0, 10);
      final exEnd = eStr.substring(0, 10);
      final reqStartStr = DateFormat('yyyy-MM-dd').format(start);
      final reqEndStr = DateFormat('yyyy-MM-dd').format(end);

      return reqStartStr.compareTo(exEnd) <= 0 && exStart.compareTo(reqEndStr) <= 0;
    });

    if (hasOverlap) {
      setState(() => _errorMessage = 'You already have an approved leave request on these date(s).');
      return;
    }

    // Prepare Web App Parity Payload
    final startDateStr = DateFormat('yyyy-MM-dd').format(start);
    final endDateStr = DateFormat('yyyy-MM-dd').format(end);

    final payload = <String, dynamic>{
      'leaveTypeName': _selectedLeaveTypeName,
      'startDate': startDateStr,
      'endDate': endDateStr,
      'duration': duration,
      'reason': _reasonController.text.trim(),
      'isHalfDay': _isHalfDay,
      if (_isHalfDay) 'halfDaySession': _halfDaySession,
      // Compatibility keys for standard backend routes
      'leaveType': _selectedLeaveTypeName,
      'days': duration,
      if (_isHalfDay) 'session': _halfDaySession == '1st Half' ? '1' : '2',
    };

    setState(() => _isSubmitting = true);
    final res = await _requestService.applyLeave(payload);
    setState(() => _isSubmitting = false);

    if (!mounted) return;

    if (res['success'] == true) {
      Navigator.pop(context);
      widget.onSuccess();
      showRequestSubmittedSuccessDialog(context);
    } else {
      setState(() {
        _errorMessage = ErrorMessageUtils.sanitizeForDisplay(
          res['message']?.toString(),
          fallback: 'Failed to submit leave request. Please check balance.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final opt = _selectedOption;
    final isPaid = opt != null && opt['isPredefinedUnpaid'] != true;
    final num? bal = opt?['balance'] as num?;
    final num? alloc = opt?['allocated'] as num?;
    final num? used = opt?['used'] as num?;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.description_rounded,
                          size: 20,
                          color: Color(0xFFEFAA1F),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Apply for Leave',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            _assignedTemplate?['name']?.toString() ?? 'leaves',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFF1F5F9), height: 24),

              // Error banner if any
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _errorMessage = null),
                        child: const Icon(Icons.close, size: 14, color: Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Leave Type Label & Half Day Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'LEAVE TYPE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  // Half Day Pill Button
                  InkWell(
                    onTap: () {
                      setState(() {
                        _isHalfDay = !_isHalfDay;
                        if (_isHalfDay && _startDate != null) {
                          _endDate = _startDate;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(100),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isHalfDay ? const Color(0xFFFFFBEB) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: _isHalfDay ? const Color(0xFFEFAA1F) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _isHalfDay ? const Color(0xFFEFAA1F) : const Color(0xFF94A3B8),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Half Day',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _isHalfDay ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Custom Dropdown Trigger
              InkWell(
                onTap: _isLoadingTypes ? null : _showLeaveTypePicker,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      if (opt != null)
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: opt['badgeBg'] as Color? ?? const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            opt['badge'] as String? ?? 'L',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: opt['badgeText'] as Color? ?? const Color(0xFFEFAA1F),
                            ),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt?['label'] as String? ?? (_isLoadingTypes ? 'Loading leave types...' : 'Select Leave Type'),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (opt?['subtext'] != null)
                              Text(
                                opt!['subtext'] as String,
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                              ),
                          ],
                        ),
                      ),
                      if (isPaid && bal != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Text(
                            '${bal.toInt()} Left',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B), size: 18),
                    ],
                  ),
                ),
              ),

              // Selected Leave Balance card (when paid)
              if (isPaid && bal != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Available Balance: ',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          ),
                          Text(
                            '${bal.toInt()} Left',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFFD97706)),
                          ),
                        ],
                      ),
                      if (alloc != null)
                        Text(
                          'Allocated: ${alloc.toInt()} • Used: ${(used ?? 0).toInt()}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ),
              ],

              // Half Day Session Selector (1st Half / 2nd Half)
              if (_isHalfDay) ...[
                const SizedBox(height: 16),
                const Text(
                  'SELECT HALF',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _halfDaySession = '1st Half'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _halfDaySession == '1st Half' ? const Color(0xFFEFAA1F) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _halfDaySession == '1st Half' ? const Color(0xFFEFAA1F) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _halfDaySession == '1st Half' ? Colors.white : const Color(0xFF94A3B8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '1st Half',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _halfDaySession == '1st Half' ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _halfDaySession = '2nd Half'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _halfDaySession == '2nd Half' ? const Color(0xFFEFAA1F) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _halfDaySession == '2nd Half' ? const Color(0xFFEFAA1F) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _halfDaySession == '2nd Half' ? Colors.white : const Color(0xFF94A3B8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '2nd Half',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _halfDaySession == '2nd Half' ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // Date Pickers (Single date for Half Day, Start & End for full day)
              if (_isHalfDay) ...[
                const Text(
                  'SELECT DATE *',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _pickDateFor(true),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFFEFAA1F)),
                            const SizedBox(width: 8),
                            Text(
                              _startDate != null ? DateFormat('MMM dd, yyyy').format(_startDate!) : 'Select Date',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _startDate != null ? FontWeight.w800 : FontWeight.w500,
                                color: _startDate != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    // Start Date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'START DATE *',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _pickDateFor(true),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today_rounded, size: 15, color: Color(0xFFEFAA1F)),
                                      const SizedBox(width: 6),
                                      Text(
                                        _startDate != null ? DateFormat('MMM dd, yyyy').format(_startDate!) : 'Select Date',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _startDate != null ? FontWeight.w800 : FontWeight.w500,
                                          color: _startDate != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // End Date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'END DATE *',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _pickDateFor(false),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today_rounded, size: 15, color: Color(0xFFEFAA1F)),
                                      const SizedBox(width: 6),
                                      Text(
                                        _endDate != null ? DateFormat('MMM dd, yyyy').format(_endDate!) : 'Select Date',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _endDate != null ? FontWeight.w800 : FontWeight.w500,
                                          color: _endDate != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // Reason
              const Text(
                'REASON',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonController,
                maxLines: 3,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'State the reason for your leave request...',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons (Cancel & Submit Request)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleApplyLeaveSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFAA1F),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Submit Request',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- LOAN TAB ---

class LoanRequestsTab extends StatefulWidget {
  /// See [LeaveRequestsTab.isVisible].
  final bool Function()? isVisible;

  const LoanRequestsTab({super.key, this.isVisible});

  @override
  State<LoanRequestsTab> createState() => _LoanRequestsTabState();
}

class _LoanRequestsTabState extends State<LoanRequestsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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
  final int _itemsPerPage = 5;
  int _totalPages = 0;
  bool _showFilters = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    // Background refresh: keep the current list instead of flashing the loader.
    _fetchLoans(showLoader: false);
  }

  @override
  void initState() {
    super.initState();
    // Date filter is single-date only; start unfiltered (no range).
    _startDate = null;
    _endDate = null;
    _fetchLoans();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchLoans({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
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
        if (widget.isVisible?.call() ?? true) {
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
  }

  void showRequestLoanDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RequestLoanDialog(onSuccess: _fetchLoans),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        _endDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
          999,
        );
      });
      _fetchLoans();
    }
  }

  void _showLoanDetails(Map<String, dynamic> loan) {
    String approvedBy = '-';
    String rejectedBy = '-';
    final approver = loan['approvedBy'];
    final rejector = loan['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = '-';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = '-';
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
        : '-';

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
          _detailRow('Amount', '${loan['amount']}'),
          _detailRow(
            'Tenure',
            '${loan['tenure'] ?? loan['tenureMonths']} Months',
          ),
          _detailRow('EMI', '${loan['emi'] ?? 0}'),
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
                    '₹${loan['amount']}',
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
                    '₹${loan['emi'] ?? 0}',
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
    super.build(context); // keep-alive
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchLoans(showLoader: false);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                      borderSide: BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
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
                            value: _statusOptions.contains(_selectedStatus)
                                ? _selectedStatus
                                : _statusOptions.first,
                            isExpanded: true,
                            items: _statusOptions
                                .toSet()
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
                      onTap: _pickDate,
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
                                  ? 'Date'
                                  : _isSameCalendarDay(_startDate!, _endDate!)
                                  ? DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(_startDate!)
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

                // List Content — loader / empty / items scroll with the header.
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: const Center(child: AppTabLoader()),
                  )
                else if (_loans.isEmpty)
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
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        for (int i = 0; i < _loans.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: FadeSlideIn(
                              delay: Duration(
                                milliseconds: (i * 45).clamp(0, 270),
                              ),
                              child: _buildLoanCard(_loans[i]),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bottom action bar: page numbers (only when multi-page) on the left
        // and the Request Loan button on the right (pinned footer).
        _PaginationBar(
          currentPage: _currentPage,
          totalPages: _totalPages,
          onPageSelected: (page) {
            setState(() => _currentPage = page);
            _fetchLoans();
          },
          createLabel: 'Request Loan',
          onCreate: showRequestLoanDialog,
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

  // Loan type options - display label vs. value sent to backend.
  static const List<({String value, String label})> _loanTypes = [
    (value: 'Personal', label: 'Personal Loan'),
    (value: 'Advance', label: 'Advance Salary'),
    (value: 'Emergency', label: 'Emergency Loan'),
  ];

  String _loanType = 'Personal';
  double _tenureMonths = 12;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _interestRateController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  bool _isSubmitting = false;

  // Per-user loan stats fetched from the DB (replaces static placeholders).
  int _activeLoanCount = 0;
  int _pendingLoanCount = 0;
  double _totalOutstanding = 0;

  @override
  void initState() {
    super.initState();
    _fetchLoanSummary();
  }

  Future<void> _fetchLoanSummary() async {
    final result = await _requestService.getLoanSummary();
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      setState(() {
        _activeLoanCount = (data['activeCount'] as num?)?.toInt() ?? 0;
        _pendingLoanCount = (data['pendingCount'] as num?)?.toInt() ?? 0;
        _totalOutstanding = (data['totalOutstanding'] as num?)?.toDouble() ?? 0;
      });
      return;
    }
    // Fallback (summary endpoint not available on this backend): compute the
    // per-user loan stats client-side from the employee's own loan records.
    await _computeLoanSummaryFromRecords();
  }

  Future<void> _computeLoanSummaryFromRecords() async {
    int active = 0;
    int pending = 0;
    double outstanding = 0;
    try {
      final result = await _requestService.getLoanRequests(
        status: 'All Status',
        page: 1,
        limit: 500,
      );
      if (result['success'] == true) {
        final data = result['data'];
        final list = data is Map
            ? (data['loans'] as List? ?? [])
            : (data is List ? data : []);
        for (final l in list) {
          if (l is! Map) continue;
          final status = (l['status'] ?? '').toString();
          if (status == 'Active' || status == 'Approved') {
            active++;
            final rem = l['remainingAmount'];
            outstanding += rem is num
                ? rem.toDouble()
                : double.tryParse(rem?.toString() ?? '') ?? 0;
          } else if (status == 'Pending') {
            pending++;
          }
        }
      }
    } catch (_) {
      // best-effort
    }
    if (!mounted) return;
    setState(() {
      _activeLoanCount = active;
      _pendingLoanCount = pending;
      _totalOutstanding = outstanding;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _interestRateController.dispose();
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
      'interestRate': double.tryParse(_interestRateController.text.trim()) ?? 0,
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
                'OUTSTANDING LOAN AMOUNT',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₹${NumberFormat('#,##0.##', 'en_IN').format(_totalOutstanding)}',
                style: const TextStyle(
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
                      'Total remaining across your active loans',
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
                  '₹',
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
            validator: (val) =>
                val == null || val.trim().isEmpty ? 'Amount is required' : null,
          ),
          const SizedBox(height: 18),

          // Loan Type
          _fieldLabel('Loan Type'),
          DropdownButtonFormField<String>(
            value: _loanType,
            icon: const Icon(Icons.keyboard_arrow_down),
            items: _loanTypes
                .map(
                  (e) => DropdownMenuItem(value: e.value, child: Text(e.label)),
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
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
                Text(
                  '3M',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '12M',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '24M',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '36M',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Interest Rate (%)
          _fieldLabel('Interest Rate (%)'),
          TextFormField(
            controller: _interestRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '0.0',
              hintStyle: const TextStyle(color: AppColors.textHint),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(left: 8, right: 16),
                child: Text(
                  '%',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 0),
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
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Interest rate is required';
              }
              final rate = double.tryParse(val.trim());
              if (rate == null || rate < 0 || rate > 100) {
                return 'Enter a valid rate (0–100)';
              }
              return null;
            },
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
              padding: const EdgeInsets.fromLTRB(8, 14, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios, size: 24),
                    color: AppColors.textPrimary,
                  ),
                  const Text(
                    'Request Loan',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable body - sections one by one
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                   // _buildEligibleCard(),
                  //  const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            label: 'Active Loans',
                            value: '$_activeLoanCount',
                            caption: 'Applications',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            label: 'Pending Requests',
                            value: '$_pendingLoanCount',
                            caption: 'Awaiting approval',
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
  /// See [LeaveRequestsTab.isVisible].
  final bool Function()? isVisible;

  const ExpenseRequestsTab({super.key, this.isVisible});

  @override
  State<ExpenseRequestsTab> createState() => _ExpenseRequestsTabState();
}

class _ExpenseRequestsTabState extends State<ExpenseRequestsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final RequestService _requestService = RequestService();
  List<dynamic> _expenses = [];
  bool _isLoading = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Paid',
    'Rejected',
    'Cancelled',
  ];

  // All-time totals for the hero card - independent of the paginated/filtered
  // `_expenses` list, fetched straight from the DB for this employee.
  double _totalReimbursed = 0;
  double _totalPending = 0;
  int _pendingClaimCount = 0;

  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 5;
  int _totalPages = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _showFilters = false;
  bool _isTableView = false;

  Future<void> _cancelExpense(Map<String, dynamic> expense) async {
    final id = expense['_id']?.toString() ?? expense['id']?.toString();
    if (id == null || id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Expense Claim?'),
        content: const Text('Are you sure you want to cancel this reimbursement request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final res = await _requestService.cancelExpenseRequest(id);
      if (res['success'] == true) {
        SnackBarUtils.showSnackBar(
          context,
          'Expense claim cancelled successfully',
          isError: false,
        );
        _fetchExpenses();
        _fetchExpenseSummary();
      } else {
        SnackBarUtils.showSnackBar(
          context,
          res['message']?.toString() ?? 'Failed to cancel claim',
          isError: true,
        );
      }
    }
  }

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    // Background refresh: keep the current list instead of flashing the loader.
    _fetchExpenses(showLoader: false);
    _fetchExpenseSummary();
  }

  @override
  void initState() {
    super.initState();
    // Date filter is single-date only; start unfiltered (no range).
    _startDate = null;
    _endDate = null;
    _fetchExpenses();
    _fetchExpenseSummary();
  }

  Future<void> _fetchExpenseSummary() async {
    final result = await _requestService.getExpenseSummary();
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>? ?? {};
      final reimbursed = (data['totalReimbursed'] as num?)?.toDouble() ?? 0;
      final pending = (data['totalPending'] as num?)?.toDouble() ?? 0;
      final count = (data['pendingCount'] as num?)?.toInt() ?? 0;
      // A non-zero summary is authoritative. But an all-zero response can come
      // from a stale/older summary endpoint that fails to match the records
      // even when the employee has claims — so fall through and recompute from
      // the records, so the hero card matches the visible claims instead of
      // collapsing to 0 (the records list below is the source of truth).
      if (reimbursed != 0 || pending != 0 || count != 0) {
        if (!mounted) return;
        setState(() {
          _totalReimbursed = reimbursed;
          _totalPending = pending;
          _pendingClaimCount = count;
        });
        return;
      }
    }
    // Summary unavailable (endpoint missing on this backend) or all-zero:
    // compute the all-time totals client-side from the employee's own records.
    await _computeExpenseSummaryFromRecords();
  }

  Future<void> _computeExpenseSummaryFromRecords() async {
    double reimbursed = 0;
    double pending = 0;
    int pendingCount = 0;
    try {
      final result = await _requestService.getExpenseRequests(
        status: 'All Status',
        page: 1,
        limit: 500,
      );
      if (result['success'] == true) {
        final data = result['data'];
        final list = data is Map
            ? (data['reimbursements'] as List? ?? [])
            : (data is List ? data : []);
        for (final e in list) {
          if (e is! Map) continue;
          // Normalize so case/whitespace variants (e.g. 'pending'/'PENDING')
          // are still counted correctly.
          final status = (e['status'] ?? '').toString().trim().toLowerCase();
          final amt = e['amount'];
          final amount = amt is num
              ? amt.toDouble()
              : double.tryParse(amt?.toString() ?? '') ?? 0;
          if (status == 'approved' ||
              status == 'paid' ||
              status == 'processed') {
            reimbursed += amount;
          } else if (status == 'pending') {
            pending += amount;
            pendingCount++;
          }
        }
      }
    } catch (_) {
      // best-effort
    }
    if (!mounted) return;
    setState(() {
      _totalReimbursed = reimbursed;
      _totalPending = pending;
      _pendingClaimCount = pendingCount;
    });
  }

  Future<void> _fetchExpenses({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
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
            _expenses = result['data']['requests'] ??
                result['data']['reimbursements'] ??
                result['data']['expenses'] ??
                [];
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
        if (widget.isVisible?.call() ?? true) {
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
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        _endDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
          999,
        );
      });
      _fetchExpenses();
    }
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
        : '-';

    String approvedByName = '-';
    String rejectedByName = '-';
    final approver = expense['approvedBy'];
    final rejector = expense['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedByName = approver['name'].toString().trim();
        if (approvedByName.isEmpty) approvedByName = '-';
      } else {
        approvedByName = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedByName = rejector['name'].toString().trim();
        if (rejectedByName.isEmpty) rejectedByName = '-';
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
      _expenseDetailRow('Amount', '₹${expense['amount']}'),
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
      ...buildProofFileRows(context, _requestService, proofs),
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

  /// Indian-grouped amount with up to 2 decimals (keeps ₹ - the app is INR).
  String _formatAmount(dynamic v) =>
      NumberFormat('#,##0.##', 'en_IN').format(_amountOf(v));

  /// Amber summary hero - Total Reimbursed + Pending amount/count (Figma).
  /// Values come from [_fetchExpenseSummary] - all-time totals for this
  /// employee from the DB, not just the current page/filter of `_expenses`.
  Widget _buildClaimHero() {
    final reimbursed = _totalReimbursed;
    final pending = _totalPending;
    final pendingCount = _pendingClaimCount;
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
                    '${_formatAmount(reimbursed)}',
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
                    '${_formatAmount(pending)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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

  Widget _buildExpenseControlBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reimbursement Claims',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              // Card / Table View Mode Toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _isTableView = false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: !_isTableView ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: !_isTableView
                              ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4)]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.grid_view_rounded,
                              size: 14,
                              color: !_isTableView ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Cards',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: !_isTableView ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _isTableView = true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isTableView ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _isTableView
                              ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4)]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.table_rows_rounded,
                              size: 14,
                              color: _isTableView ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Table',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _isTableView ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Search input
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _fetchExpenses(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Status dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statusOptions.contains(_selectedStatus) ? _selectedStatus : _statusOptions.first,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                    items: _statusOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense) {
    final date = DateFormat('MMM dd, yyyy').format(DateTime.parse(expense['date']));
    final type = (expense['type'] ?? expense['expenseType'] ?? 'Expense').toString();
    final status = (expense['status'] ?? '').toString();
    final isPending = status.toLowerCase() == 'pending';
    final isApproved = status.toLowerCase() == 'approved' || status.toLowerCase() == 'paid';
    final isRejected = status.toLowerCase() == 'rejected';

    final Color statusBg = isApproved
        ? const Color(0xFFECFDF5)
        : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
    final Color statusBorder = isApproved
        ? const Color(0xFFA7F3D0)
        : (isRejected ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
    final Color statusText = isApproved
        ? const Color(0xFF059669)
        : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));

    final desc = (expense['description'] ?? '').toString().trim();
    final amount = _formatAmount(expense['amount']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showExpenseDetails(expense),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(_expenseIcon(type), color: const Color(0xFFEFAA1F), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              type,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              date,
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          amount,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: statusBorder),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: statusText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (isPending) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelExpense(expense),
                      icon: const Icon(Icons.cancel_outlined, size: 14, color: Color(0xFFDC2626)),
                      label: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseTableView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            headingTextStyle: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
            dataTextStyle: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            columns: const [
              DataColumn(label: Text('TYPE')),
              DataColumn(label: Text('AMOUNT')),
              DataColumn(label: Text('DATE')),
              DataColumn(label: Text('DESCRIPTION')),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('ACTION')),
            ],
            rows: _expenses.map((expense) {
              final raw = expense is Map<String, dynamic> ? expense : Map<String, dynamic>.from(expense as Map);
              final date = DateFormat('MMM dd, yyyy').format(DateTime.parse(raw['date']));
              final type = (raw['type'] ?? raw['expenseType'] ?? 'Expense').toString();
              final status = (raw['status'] ?? '').toString();
              final isPending = status.toLowerCase() == 'pending';
              final isApproved = status.toLowerCase() == 'approved' || status.toLowerCase() == 'paid';
              final isRejected = status.toLowerCase() == 'rejected';

              final Color statusBg = isApproved
                  ? const Color(0xFFECFDF5)
                  : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
              final Color statusBorder = isApproved
                  ? const Color(0xFFA7F3D0)
                  : (isRejected ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
              final Color statusText = isApproved
                  ? const Color(0xFF059669)
                  : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));

              final desc = (raw['description'] ?? '-').toString().trim();
              final amount = _formatAmount(raw['amount']);

              return DataRow(
                cells: [
                  DataCell(Text(type, style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(Text(amount, style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(Text(date)),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusBorder),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: statusText,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    isPending
                        ? OutlinedButton(
                            onPressed: () => _cancelExpense(raw),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFECACA)),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel_outlined, size: 12, color: Color(0xFFDC2626)),
                                SizedBox(width: 4),
                                Text(
                                  'Cancel',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                          )
                        : const Text('-', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                ],
              );
            }).toList(),
          ),
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
    super.build(context); // keep-alive
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchExpenses(showLoader: false);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Top Hero Card
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: FadeSlideIn(child: _buildClaimHero()),
                ),

                // Control Bar with Dual View Mode Switcher
                _buildExpenseControlBar(),

                // List / Table Content
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.35,
                    child: const Center(child: AppTabLoader()),
                  )
                else if (_expenses.isEmpty)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.35,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFBEB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              size: 40,
                              color: Color(0xFFEFAA1F),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No expense requests found',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_isTableView)
                  _buildExpenseTableView()
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      children: [
                        for (int i = 0; i < _expenses.length; i++)
                          FadeSlideIn(
                            delay: Duration(
                              milliseconds: (i * 40).clamp(0, 240),
                            ),
                            child: _buildExpenseCard(_expenses[i]),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bottom action bar: page numbers & Claim Expense button
        _PaginationBar(
          currentPage: _currentPage,
          totalPages: _totalPages,
          onPageSelected: (page) {
            setState(() => _currentPage = page);
            _fetchExpenses();
          },
          createLabel: 'Claim Expense',
          onCreate: showClaimExpenseDialog,
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
  final TextEditingController _descriptionController = TextEditingController();
  File? _selectedFile;
  String? _errorMessage;
  bool _isSubmitting = false;

  final List<String> _expenseTypeOptions = const [
    'Travel',
    'Food',
    'Meals',
    'Office Supplies',
    'Client Entertainment',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _errorMessage = null);
    final source = await showModalBottomSheet<_ProofSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Upload Proof Image',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFFEFAA1F), size: 20),
                ),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                onTap: () => Navigator.pop(sheetContext, _ProofSource.camera),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFFEFAA1F), size: 20),
                ),
                title: const Text('Choose from Gallery / Files', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('JPG, JPEG, PNG, WEBP (Max 5MB)', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                onTap: () => Navigator.pop(sheetContext, _ProofSource.files),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (source == null) return;
    if (source == _ProofSource.camera) {
      await _pickFromCamera();
    } else {
      await _pickFromFiles();
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked != null) {
        final f = File(picked.path);
        final len = await f.length();
        if (len > 5 * 1024 * 1024) {
          setState(() => _errorMessage = 'File size must not exceed 5MB.');
          return;
        }
        setState(() => _selectedFile = f);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Unable to capture photo. Please check permissions.');
    }
  }

  Future<void> _pickFromFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result != null && result.files.single.path != null) {
        final f = File(result.files.single.path!);
        final len = await f.length();
        if (len > 5 * 1024 * 1024) {
          setState(() => _errorMessage = 'File size must not exceed 5MB.');
          return;
        }
        setState(() => _selectedFile = f);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to select file.');
    }
  }

  Future<void> _pickDate() async {
    final DateTime initial = _date ?? DateTime.now();
    final DateTime? picked = await _showWebStyledDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _date = picked;
        _errorMessage = null;
      });
    }
  }

  Future<DateTime?> _showWebStyledDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime navDate = DateTime(initialDate.year, initialDate.month, 1);
    DateTime? selectedDate = initialDate;

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final daysInMonth = DateTime(navDate.year, navDate.month + 1, 0).day;
            final firstWeekday = DateTime(navDate.year, navDate.month, 1).weekday % 7;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x25000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Month & Navigation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 22, color: Color(0xFF64748B)),
                          onPressed: () {
                            setDialogState(() {
                              navDate = DateTime(navDate.year, navDate.month - 1, 1);
                            });
                          },
                        ),
                        Text(
                          DateFormat('MMMM yyyy').format(navDate),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF64748B)),
                          onPressed: () {
                            setDialogState(() {
                              navDate = DateTime(navDate.year, navDate.month + 1, 1);
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFFF1F5F9), height: 16),
                    // Weekday headers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        Text('SU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('MO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('TU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('WE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('TH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('FR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('SA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Days Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: firstWeekday + daysInMonth,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemBuilder: (c, index) {
                        if (index < firstWeekday) {
                          return const SizedBox.shrink();
                        }
                        final dayNumber = index - firstWeekday + 1;
                        final currentDay = DateTime(navDate.year, navDate.month, dayNumber);
                        final isSelected = selectedDate != null &&
                            selectedDate!.year == currentDay.year &&
                            selectedDate!.month == currentDay.month &&
                            selectedDate!.day == currentDay.day;

                        return InkWell(
                          onTap: () => Navigator.pop(ctx, currentDay),
                          borderRadius: BorderRadius.circular(100),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEFAA1F) : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final amtStr = _amountController.text.trim();
    final amt = double.tryParse(amtStr);
    if (amt == null || amt <= 0) {
      setState(() => _errorMessage = 'Please enter a valid amount greater than 0.');
      return;
    }

    if (_date == null) {
      setState(() => _errorMessage = 'Please select a date.');
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a description.');
      return;
    }

    setState(() => _isSubmitting = true);

    String base64Proof = '';
    if (_selectedFile != null) {
      try {
        final bytes = await _selectedFile!.readAsBytes();
        final ext = _selectedFile!.path.split('.').last.toLowerCase();
        String mime = 'image/jpeg';
        if (ext == 'png') mime = 'image/png';
        if (ext == 'webp') mime = 'image/webp';
        base64Proof = 'data:$mime;base64,${base64Encode(bytes)}';
      } catch (e) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to process proof image file.';
        });
        return;
      }
    }

    final formattedDate = DateFormat('MMM dd, yyyy').format(_date!);
    final isoDate = _date!.toIso8601String();

    final payload = <String, dynamic>{
      'type': _expenseType,
      'amount': amt,
      'date': isoDate,
      'displayDate': formattedDate,
      'description': _descriptionController.text.trim(),
      'proofFile': base64Proof,
      if (base64Proof.isNotEmpty) 'proofFiles': [base64Proof],
    };

    final result = await _requestService.applyExpense(payload);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      Navigator.pop(context);
      widget.onSuccess();
      showRequestSubmittedSuccessDialog(context);
    } else {
      setState(() {
        _errorMessage = ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to submit reimbursement claim.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Claim Expense',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Submit a new expense claim',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFF1F5F9), height: 24),

              // Error banner if any
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _errorMessage = null),
                        child: const Icon(Icons.close, size: 14, color: Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Expense Type
              const Text(
                'Expense Type',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _expenseType,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                    items: _expenseTypeOptions
                        .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (val) {
                            if (val != null) setState(() => _expenseType = val);
                          },
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Amount (₹)
              const Text(
                'Amount (₹)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                enabled: !_isSubmitting,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'Enter expense amount',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Date *
              Row(
                children: const [
                  Text(
                    'Date',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  SizedBox(width: 3),
                  Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _isSubmitting ? null : _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _date != null ? DateFormat('MM/dd/yyyy').format(_date!) : 'mm/dd/yyyy',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _date != null ? FontWeight.w600 : FontWeight.w500,
                          color: _date != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                        ),
                      ),
                      const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Description *
              Row(
                children: const [
                  Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  SizedBox(width: 3),
                  Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                enabled: !_isSubmitting,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'e.g., Client meeting travel, Team lunch, Conference accommodation',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Briefly describe the expense so approvers can verify your claim.',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
              ),

              const SizedBox(height: 14),

              // Proof Document (Image)
              const Text(
                'Proof Document (Image)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),

              if (_selectedFile != null) ...[
                // Selected file view with preview & change/remove buttons
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _selectedFile!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (c, o, s) => Container(
                            width: 50,
                            height: 50,
                            color: const Color(0xFFE2E8F0),
                            child: const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF64748B)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedFile!.path.split(RegExp(r'[/\\]')).last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Click "Change" or "Remove" to update.',
                              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          InkWell(
                            onTap: _isSubmitting ? null : _pickFile,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Change', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            ),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: _isSubmitting ? null : () => setState(() => _selectedFile = null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Remove', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Dashed Upload box matching Web App
                InkWell(
                  onTap: _isSubmitting ? null : _pickFile,
                  borderRadius: BorderRadius.circular(14),
                  child: CustomPaint(
                    painter: const _DashedRRectPainter(color: Color(0xFFCBD5E1)),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.file_upload_outlined, size: 24, color: Color(0xFF94A3B8)),
                          SizedBox(height: 6),
                          Text(
                            'Upload Proof Image',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Upload receipt or bill image (JPG, JPEG, PNG, WEBP. Max 5MB).',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFAA1F),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Submit Claim',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
  /// See [LeaveRequestsTab.isVisible].
  final bool Function()? isVisible;

  const PermissionRequestsTab({super.key, this.isVisible});

  @override
  State<PermissionRequestsTab> createState() => _PermissionRequestsTabState();
}

class _PermissionRequestsTabState extends State<PermissionRequestsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final RequestService _requestService = RequestService();
  final AttendanceService _attendanceService = AttendanceService();
  List<dynamic> _requests = [];
  bool _isLoading = true;
  bool _showFilters = false;
  bool _isTableView = false;
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
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // Cached today's punch session, used to surface the out-of-session gating
  // message as a tap-tooltip on the Request Permission button (parity with the
  // fine-notice tooltip). Null until resolved (fail open → no gate tooltip).
  bool? _sessionPunchedIn;
  bool? _sessionPunchedOut;

  // Handle to the Request Permission button's tooltip so a blocked tap can show
  // the gating message in the same tooltip the fine notice uses.
  final GlobalKey<TooltipState> _permissionTooltipKey =
      GlobalKey<TooltipState>();

  // Permission requests come back for the whole month in one response, so we
  // page through them on the client (5 per page) to match the other tabs.
  int _currentPage = 1;
  final int _itemsPerPage = 5;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void refresh() {
    // Background refresh: keep the current list instead of flashing the loader.
    _fetchRequests(showLoader: false);
    _refreshSession();
  }

  @override
  void initState() {
    super.initState();
    _fetchRequests();
    _fetchBalance();
    _refreshSession();
  }

  /// Caches today's punch session so the button's gating tooltip is accurate
  /// before the user taps. Fail-open: leaves the flags null on any error.
  Future<void> _refreshSession() async {
    final session = await _resolveTodaySession();
    if (!mounted) return;
    setState(() {
      _sessionPunchedIn = session.punchedIn;
      _sessionPunchedOut = session.punchedOut;
    });
  }

  Future<void> _fetchRequests({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    final result = await _requestService.getPermissionRequests(
      status: _selectedStatus,
      month: _selectedMonth.month,
      year: _selectedMonth.year,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'];
      setState(() {
        if (data is Map) {
          _requests = data['requests'] ?? data['permissions'] ?? [];
        } else if (data is List) {
          _requests = data;
        } else {
          _requests = [];
        }
        // Reset to page 1 only on an explicit (query-changing) load; a quiet
        // background refresh keeps the user on their current page.
        if (showLoader) _currentPage = 1;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (widget.isVisible?.call() ?? true) {
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
    final firstYear = now.year - 2;
    final lastYear = now.year + 2;

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        int viewYear = _selectedMonth.year;
        int selMonth = _selectedMonth.month;
        int selYear = _selectedMonth.year;
        const monthNames = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select Month',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    // Year navigator
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            color: AppColors.textPrimary,
                            onPressed: viewYear > firstYear
                                ? () => setSheetState(() => viewYear--)
                                : null,
                          ),
                          Text(
                            '$viewYear',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            color: AppColors.textPrimary,
                            onPressed: viewYear < lastYear
                                ? () => setSheetState(() => viewYear++)
                                : null,
                          ),
                        ],
                      ),
                    ),
                    // Month grid
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.4,
                        children: List.generate(12, (i) {
                          final month = i + 1;
                          final selected =
                              month == selMonth && viewYear == selYear;
                          return Material(
                            color: selected
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  Navigator.pop(ctx, DateTime(viewYear, month)),
                              child: Center(
                                child: Text(
                                  monthNames[i],
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
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

  // Resolve a populated approvedBy/rejectedBy ref ({ name, email }) to a name.
  String _resolveActor(dynamic actor) {
    if (actor == null) return '-';
    if (actor is Map && actor['name'] != null) {
      final name = actor['name'].toString().trim();
      return name.isEmpty ? '-' : name;
    }
    return 'System';
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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

  void _showPermissionDetails(Map<String, dynamic> req) {
    final status = (req['status'] ?? '').toString();
    final isApproved = status == 'Approved';
    final isRejected = status == 'Rejected';

    final fromTime = (req['fromTime'] ?? '').toString().trim();
    final toTime = (req['toTime'] ?? '').toString().trim();
    final reason = (req['reason'] ?? '').toString().trim();
    final approvalReason = (req['approvalReason'] ?? '').toString().trim();
    final rejectionReason = (req['rejectionReason'] ?? '').toString().trim();
    final actualMinutes = req['actualMinutes'];
    final overrunMinutes = req['overrunMinutes'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Permission Details',
        icon: Icons.timelapse,
        iconColor: AppColors.primary,
        children: [
          _detailRow('Date', _fmtDate(req['date'])),
          _detailRow('Type', _fmtType(req['type']?.toString())),
          _detailRow(
            'Requested Minutes',
            '${req['requestedMinutes'] ?? 0}',
          ),
          if (fromTime.isNotEmpty) _detailRow('From Time', fromTime),
          if (toTime.isNotEmpty) _detailRow('To Time', toTime),
          if (req['actualOutAt'] != null)
            _detailRow('Permission Out', _fmtDateTime(req['actualOutAt'])),
          if (req['actualInAt'] != null)
            _detailRow('Permission In', _fmtDateTime(req['actualInAt'])),
          if (actualMinutes != null)
            _detailRow('Actual Minutes', '$actualMinutes'),
          if (overrunMinutes != null &&
              (overrunMinutes is num ? overrunMinutes > 0 : true))
            _detailRow('Overrun Minutes', '$overrunMinutes'),
          _detailRow('Status', status.isEmpty ? '-' : status),
          if (isApproved) ...[
            _detailRow('Approved By', _resolveActor(req['approvedBy'])),
            if (approvalReason.isNotEmpty)
              _detailRow('Approval Reason', approvalReason),
          ],
          if (isRejected) ...[
            _detailRow(
              'Rejected By',
              _resolveActor(req['rejectedBy'] ?? req['approvedBy']),
            ),
            if (rejectionReason.isNotEmpty)
              _detailRow('Rejection Reason', rejectionReason),
          ],
          if (reason.isNotEmpty) _detailRow('Reason', reason),
          _detailRow('Applied', _fmtDate(req['createdAt'])),
        ],
      ),
    );
  }

  String _fmtDateTime(dynamic value) {
    if (value == null) return '-';
    final d = DateTime.tryParse(value.toString());
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(d.toLocal());
  }

  /// Reads today's attendance to derive whether the user is mid-session
  /// (punched in, not yet punched out). /attendance/today returns authoritative
  /// top-level hasPunchIn/hasPunchOut flags; fall back to the record's punch
  /// timestamps. Both fields stay null when the read fails (fail open).
  Future<({bool? punchedIn, bool? punchedOut})> _resolveTodaySession() async {
    bool? punchedIn;
    bool? punchedOut;
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final att = await _attendanceService.getAttendanceByDate(dateStr);
      final body = att['data'] as Map<String, dynamic>?;
      if (att['success'] == true && body != null) {
        final record = body['data'] is Map ? body['data'] as Map : null;
        punchedIn = body['hasPunchIn'] == true ||
            hasParsablePunchDateTime(record?['punchIn']);
        punchedOut = body['hasPunchOut'] == true ||
            hasParsablePunchDateTime(record?['punchOut']);
      }
    } catch (_) {}
    return (punchedIn: punchedIn, punchedOut: punchedOut);
  }

  Future<void> showRequestPermissionDialog() async {
    // Permission is ALWAYS allowed (parity with the break flow) and we no longer
    // block opening the form out-of-session. The dialog itself restricts which
    // permission TYPES are selectable per the date + punch matrix — future dates
    // and today-before-punch-in offer Late Arrival only; an active session offers
    // all types; after punch-out none — and re-checks on submit. This lets a
    // member plan a future-dated Late Arrival before punching in.
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

  Widget _buildWebPermissionBalanceCard(double quota, double consumed, double balance, bool hasBalance, String monthLabel) {
    String formatMinutes(double min) {
      final total = min < 0 ? 0 : min.round();
      final hrs = total ~/ 60;
      final mins = total % 60;
      if (hrs > 0 && mins > 0) return '$hrs hr $mins mins';
      if (hrs > 0) return '$hrs hrs';
      return '$mins mins';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        color: Color(0xFFEFAA1F),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Permission Balance',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: _pickMonth,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_outlined, size: 13, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        monthLabel,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3 Columns: MONTHLY QUOTA, CONSUMED / PENDING, REMAINING
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MONTHLY QUOTA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMinutes(hasBalance ? quota : 0),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 32, color: const Color(0xFFF1F5F9)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONSUMED / PENDING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMinutes(hasBalance ? consumed : 0),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 32, color: const Color(0xFFF1F5F9)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REMAINING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMinutes(hasBalance ? balance : 0),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildPermissionControlBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Permission Requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              // Card / Table View Mode Toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _isTableView = false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: !_isTableView ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: !_isTableView
                              ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4)]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.grid_view_rounded,
                              size: 14,
                              color: !_isTableView ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Cards',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: !_isTableView ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _isTableView = true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isTableView ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _isTableView
                              ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4)]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.table_rows_rounded,
                              size: 14,
                              color: _isTableView ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Table',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _isTableView ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Search input
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                      ),
                    ),
                    onChanged: (val) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), () {
                        _fetchRequests();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Status dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statusOptions.contains(_selectedStatus) ? _selectedStatus : _statusOptions.first,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                    items: _statusOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(Map<String, dynamic> req) {
    final status = (req['status'] ?? '').toString();
    final isPending = status == 'Pending';
    final isApproved = status == 'Approved';
    final isRejected = status == 'Rejected';

    final Color statusBg = isApproved
        ? const Color(0xFFECFDF5)
        : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
    final Color statusBorder = isApproved
        ? const Color(0xFFA7F3D0)
        : (isRejected ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
    final Color statusText = isApproved
        ? const Color(0xFF059669)
        : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));

    final type = _fmtType(req['type']?.toString());
    final isEarly = type.toLowerCase().contains('early');
    final isLate = type.toLowerCase().contains('late');
    final Color typeBg = isEarly
        ? const Color(0xFFEFF6FF)
        : (isLate ? const Color(0xFFFFF7ED) : const Color(0xFFFAF5FF));
    final Color typeBorder = isEarly
        ? const Color(0xFFBFDBFE)
        : (isLate ? const Color(0xFFFED7AA) : const Color(0xFFE9D5FF));
    final Color typeText = isEarly
        ? const Color(0xFF1D4ED8)
        : (isLate ? const Color(0xFFC2410C) : const Color(0xFF7E22CE));

    final dateStr = _fmtDate(req['date']);
    final requestedMinutes = req['requestedMinutes'] ?? 0;
    final durationStr = '$type: ${requestedMinutes >= 60 ? '${requestedMinutes ~/ 60} hr' : ''}${requestedMinutes % 60 > 0 ? ' ${requestedMinutes % 60} mins' : ''}'.trim();
    final reason = (req['reason'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPermissionDetails(req),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Date & Type Pill + Status Pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: typeBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: typeBorder),
                          ),
                          child: Text(
                            type,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: typeText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusBorder),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusText,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),

                // Duration Row
                Row(
                  children: [
                    const Icon(Icons.timelapse_rounded, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 6),
                    Text(
                      'Requested: $durationStr',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                    ),
                  ],
                ),

                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Reason: $reason',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Cancel Button if Pending
                if (isPending) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelRequest(req['_id'].toString()),
                      icon: const Icon(Icons.cancel_outlined, size: 14, color: Color(0xFFDC2626)),
                      label: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionTableView(List<dynamic> pagedRequests) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            headingTextStyle: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
            dataTextStyle: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            columns: const [
              DataColumn(label: Text('DATE')),
              DataColumn(label: Text('TYPE')),
              DataColumn(label: Text('REQUESTED DURATION')),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('REASON')),
              DataColumn(label: Text('ACTION')),
            ],
            rows: pagedRequests.map((raw) {
              final req = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
              final status = (req['status'] ?? '').toString();
              final isPending = status == 'Pending';
              final isApproved = status == 'Approved';
              final isRejected = status == 'Rejected';

              final Color statusBg = isApproved
                  ? const Color(0xFFECFDF5)
                  : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
              final Color statusBorder = isApproved
                  ? const Color(0xFFA7F3D0)
                  : (isRejected ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
              final Color statusText = isApproved
                  ? const Color(0xFF059669)
                  : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));

              final type = _fmtType(req['type']?.toString());
              final isEarly = type.toLowerCase().contains('early');
              final isLate = type.toLowerCase().contains('late');
              final Color typeBg = isEarly
                  ? const Color(0xFFEFF6FF)
                  : (isLate ? const Color(0xFFFFF7ED) : const Color(0xFFFAF5FF));
              final Color typeBorder = isEarly
                  ? const Color(0xFFBFDBFE)
                  : (isLate ? const Color(0xFFFED7AA) : const Color(0xFFE9D5FF));
              final Color typeText = isEarly
                  ? const Color(0xFF1D4ED8)
                  : (isLate ? const Color(0xFFC2410C) : const Color(0xFF7E22CE));

              final dateStr = _fmtDate(req['date']);
              final requestedMinutes = req['requestedMinutes'] ?? 0;
              final durationStr = '$type: ${requestedMinutes >= 60 ? '${requestedMinutes ~/ 60} hr' : ''}${requestedMinutes % 60 > 0 ? ' ${requestedMinutes % 60} mins' : ''}'.trim();
              final reason = (req['reason'] ?? '-').toString().trim();

              return DataRow(
                cells: [
                  DataCell(Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: typeBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: typeBorder),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: typeText,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(durationStr)),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusBorder),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: statusText,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    isPending
                        ? OutlinedButton(
                            onPressed: () => _cancelRequest(req['_id'].toString()),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFECACA)),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel_outlined, size: 12, color: Color(0xFFDC2626)),
                                SizedBox(width: 4),
                                Text(
                                  'Cancel',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                          )
                        : const Text('-', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final quota = (_balance?['monthlyQuotaMinutes'] as num?)?.toDouble() ?? 0;
    final consumed = (_balance?['consumedMinutes'] as num?)?.toDouble() ?? 0;
    final configured = _balance == null || _balance?['configured'] != false;
    final enabled = _balance == null || _balance?['enabled'] != false;
    final bool hasBalance = configured && enabled && quota > 0;
    final double balance = (quota - consumed) < 0 ? 0 : (quota - consumed);

    final filtered = _requests.where((r) {
      if (_selectedStatus != 'All Status') {
        if (r['status'] != _selectedStatus) return false;
      }
      final q = _searchController.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        final reason = (r['reason'] ?? '').toString().toLowerCase();
        final type = (r['type'] ?? '').toString().toLowerCase();
        if (!reason.contains(q) && !type.contains(q)) return false;
      }
      return true;
    }).toList();

    // Client-side paging
    final totalPages = filtered.isEmpty ? 1 : (filtered.length / _itemsPerPage).ceil();
    final safePage = _currentPage.clamp(1, totalPages);
    final pageStart = (safePage - 1) * _itemsPerPage;
    final pagedRequests = filtered.skip(pageStart).take(_itemsPerPage).toList();

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _fetchRequests(showLoader: false);
              await _fetchBalance();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Top Web-styled Permission Balance Card
                _buildWebPermissionBalanceCard(quota, consumed, balance, hasBalance, monthLabel),

                // Controls & Dual View Switcher Bar
                _buildPermissionControlBar(),

                // Body: Loader / Empty / Cards / Table
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.35,
                    child: const Center(child: AppTabLoader()),
                  )
                else if (filtered.isEmpty)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.35,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFBEB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              size: 40,
                              color: Color(0xFFEFAA1F),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No permission requests found',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_isTableView)
                  _buildPermissionTableView(pagedRequests)
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      children: [
                        for (final raw in pagedRequests)
                          _buildPermissionCard(
                            raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bottom action bar: page numbers & Request Permission button
        _PaginationBar(
          currentPage: safePage,
          totalPages: totalPages,
          onPageSelected: (page) => setState(() => _currentPage = page),
          createLabel: 'Request Permission',
          onCreate: showRequestPermissionDialog,
          createTooltip: _permissionButtonTooltip(),
          createTooltipKey: _permissionTooltipKey,
        ),
      ],
    );
  }

  /// Informational out-of-session note for the Request Permission button, from
  /// the cached today's punch state. The request is NOT blocked — only the
  /// selectable permission TYPES change (enforced in the dialog): a future-dated
  /// Late Arrival can be applied even before punch-in / after punch-out. Null
  /// when mid-session (or unknown → fail open).
  String? _permissionSessionInfoNotice() {
    if (_sessionPunchedIn == false) {
      return 'Before punching in you can apply Late Arrival '
          '(including for future dates). Early Exit and Custom '
          'permissions need an active session.';
    }
    if (_sessionPunchedOut == true) {
      return 'Today is closed. You can still apply a Late Arrival '
          'permission for a future date.';
    }
    return null;
  }

  /// Combined tap-tooltip wording for the Request Permission button: the
  /// out-of-session info note takes precedence, otherwise the fine notice. Both
  /// are informational — the request always opens; type eligibility is handled
  /// inside the dialog.
  String? _permissionButtonTooltip() =>
      _permissionSessionInfoNotice() ?? _permissionFineNotice();

  /// Tap-tooltip wording for the Request Permission button, mirroring the break
  /// policy's four scenarios (keyed on enabled + monthly quota minutes).
  /// Informational only — the request itself is still allowed in every case (the
  /// disabled / no-quota cases are processed as Fine):
  ///  - S1 enabled  + minutes > 0 : "Permission allowed for X minutes. Beyond X → Fine."
  ///  - S2 enabled  + minutes = 0 : "Permission taken will be considered as Fine. Contact HR."
  ///  - S3 disabled + minutes > 0 : "Permission taken will be considered as Fine. Contact HR."
  ///  - S4 disabled + minutes = 0 : "Permission is not configured... Fine will be calculated."
  String? _permissionFineNotice() {
    final quotaMin =
        ((_balance?['monthlyQuotaMinutes'] as num?)?.toDouble() ?? 0).round();
    final configured = _balance == null || _balance?['configured'] != false;
    final enabled = _balance == null || _balance?['enabled'] != false;
    final hasQuota = configured && quotaMin > 0;
    if (!enabled) {
      return hasQuota
          ? 'Permission taken will be considered as Fine.\n'
                'Contact HR.' // S3 (disabled + minutes)
          : 'Permission is not configured for your shift. Contact HR.\n'
                'Fine will be calculated.'; // S4 (disabled + no minutes)
    }
    if (!hasQuota) {
      return 'Permission taken will be considered as Fine.\n'
          'Contact HR.'; // S2 (enabled + no minutes)
    }
    // S1 (enabled + minutes): within the monthly quota is free; beyond is fined.
    return 'Permission allowed for $quotaMin minutes.\n'
        'Permission taken beyond $quotaMin minutes will be considered as Fine.';
  }

  Widget _permissionNotice({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceTile(String title, String value) {
    IconData icon;
    switch (title.toLowerCase()) {
      case 'monthly allocated':
        icon = Icons.inventory_2_outlined;
        break;
      case 'used':
        icon = Icons.timelapse_outlined;
        break;
      case 'pending':
        icon = Icons.hourglass_bottom_outlined;
        break;
      case 'balance':
        icon = Icons.account_balance_wallet_outlined;
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            const SizedBox(height: 8),
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

  DateTime? _permDate;
  String _permType = 'Late'; // 'Late' | 'Early' | 'Custom'
  final TextEditingController _lateHoursController = TextEditingController();
  final TextEditingController _lateMinutesController = TextEditingController();
  final TextEditingController _earlyHoursController = TextEditingController();
  final TextEditingController _earlyMinutesController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Default to tomorrow as per Web App validation
    final now = DateTime.now();
    _permDate = DateTime(now.year, now.month, now.day + 1);
  }

  @override
  void dispose() {
    _lateHoursController.dispose();
    _lateMinutesController.dispose();
    _earlyHoursController.dispose();
    _earlyMinutesController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime initial = _permDate ?? DateTime.now().add(const Duration(days: 1));
    final DateTime? picked = await _showWebStyledDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _permDate = picked;
        _errorMessage = null;
      });
    }
  }

  Future<DateTime?> _showWebStyledDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime navDate = DateTime(initialDate.year, initialDate.month, 1);
    DateTime? selectedDate = initialDate;

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final daysInMonth = DateTime(navDate.year, navDate.month + 1, 0).day;
            final firstWeekday = DateTime(navDate.year, navDate.month, 1).weekday % 7; // 0=Sun, 1=Mon...

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x25000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Month & Navigation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 22, color: Color(0xFF64748B)),
                          onPressed: () {
                            setDialogState(() {
                              navDate = DateTime(navDate.year, navDate.month - 1, 1);
                            });
                          },
                        ),
                        Text(
                          DateFormat('MMMM yyyy').format(navDate),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF64748B)),
                          onPressed: () {
                            setDialogState(() {
                              navDate = DateTime(navDate.year, navDate.month + 1, 1);
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFFF1F5F9), height: 16),
                    // Weekday headers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        Text('SU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('MO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('TU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('WE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('TH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('FR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                        Text('SA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Days Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: firstWeekday + daysInMonth,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemBuilder: (c, index) {
                        if (index < firstWeekday) {
                          return const SizedBox.shrink();
                        }
                        final dayNumber = index - firstWeekday + 1;
                        final currentDay = DateTime(navDate.year, navDate.month, dayNumber);
                        final isSelected = selectedDate != null &&
                            selectedDate!.year == currentDay.year &&
                            selectedDate!.month == currentDay.month &&
                            selectedDate!.day == currentDay.day;

                        return InkWell(
                          onTap: () {
                            Navigator.pop(ctx, currentDay);
                          },
                          borderRadius: BorderRadius.circular(100),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEFAA1F) : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleRequestPermissionSubmit() async {
    setState(() => _errorMessage = null);

    if (_permDate == null) {
      setState(() => _errorMessage = 'Please select a date');
      return;
    }

    if (_reasonController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter reason for permission request');
      return;
    }

    final lH = int.tryParse(_lateHoursController.text.trim()) ?? 0;
    final lM = int.tryParse(_lateMinutesController.text.trim()) ?? 0;
    final eH = int.tryParse(_earlyHoursController.text.trim()) ?? 0;
    final eM = int.tryParse(_earlyMinutesController.text.trim()) ?? 0;

    int totalDuration = 0;
    if (_permType == 'Late') {
      totalDuration = lH * 60 + lM;
    } else if (_permType == 'Early') {
      totalDuration = eH * 60 + eM;
    } else if (_permType == 'Custom') {
      totalDuration = (lH * 60 + lM) + (eH * 60 + eM);
    }

    if (totalDuration <= 0) {
      setState(() => _errorMessage = 'Please enter a valid duration greater than 0 minutes.');
      return;
    }

    // Backend payload matching web app
    final payload = <String, dynamic>{
      'type': _permType, // 'Late' | 'Early' | 'Custom'
      'date': DateFormat('yyyy-MM-dd').format(_permDate!),
      'lateHours': lH,
      'lateMinutes': lM,
      'earlyHours': eH,
      'earlyMinutes': eM,
      'durationMins': totalDuration,
      'reason': _reasonController.text.trim(),
      // Backward compatibility keys
      'minutes': totalDuration,
      'permissionType': _permType == 'Late' ? 'lateArrival' : (_permType == 'Early' ? 'earlyExit' : 'both'),
    };

    setState(() => _isSubmitting = true);
    final res = await _requestService.createPermissionRequest(
      date: _permDate!,
      type: _permType == 'Late' ? 'lateArrival' : (_permType == 'Early' ? 'earlyExit' : 'both'),
      requestedMinutes: totalDuration,
      reason: _reasonController.text.trim(),
      lateHours: lH,
      lateMinutes: lM,
      earlyHours: eH,
      earlyMinutes: eM,
      permTypeWeb: _permType,
    );
    setState(() => _isSubmitting = false);

    if (!mounted) return;

    if (res['success'] == true) {
      Navigator.pop(context);
      widget.onSuccess();
      showRequestSubmittedSuccessDialog(context);
    } else {
      setState(() {
        _errorMessage = ErrorMessageUtils.sanitizeForDisplay(
          res['message']?.toString(),
          fallback: 'Failed to submit permission request.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.access_time_rounded,
                          size: 20,
                          color: Color(0xFFEFAA1F),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Request Permission',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFF1F5F9), height: 24),

              // Error banner if any
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _errorMessage = null),
                        child: const Icon(Icons.close, size: 14, color: Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // DATE *
              const Text(
                'DATE *',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFFEFAA1F)),
                          const SizedBox(width: 8),
                          Text(
                            _permDate != null ? DateFormat('MMM dd, yyyy').format(_permDate!) : 'Select Date',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _permDate != null ? FontWeight.w800 : FontWeight.w500,
                              color: _permDate != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // PERMISSION TYPE
              const Text(
                'PERMISSION TYPE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _permType,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    items: const [
                      DropdownMenuItem(value: 'Late', child: Text('Late')),
                      DropdownMenuItem(value: 'Early', child: Text('Early')),
                      DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _permType = val);
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Duration Input Fields based on _permType
              if (_permType == 'Late') ...[
                const Text(
                  'LATE DURATION *',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _lateHoursController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Hours (e.g. 1)',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Hours', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _lateMinutesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Minutes (e.g. 30)',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Minutes', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else if (_permType == 'Early') ...[
                const Text(
                  'EARLY DURATION *',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _earlyHoursController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Hours (e.g. 0)',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Hours', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _earlyMinutesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Minutes (e.g. 45)',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Minutes', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Custom: Both Late & Early rows
                const Text(
                  'LATE DURATION *',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _lateHoursController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Hours (e.g. 0)',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Hours', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _lateMinutesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Minutes (e.g. 0)',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Minutes', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'EARLY DURATION *',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _earlyHoursController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Hours (e.g. 0)',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Hours', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _earlyMinutesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Minutes (e.g. 30)',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Minutes', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // REASON *
              const Text(
                'REASON *',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonController,
                maxLines: 3,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'State the reason for permission request...',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons (Cancel & Submit Request)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleRequestPermissionSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFAA1F),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Submit Request',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

class _PayslipRequestsTabState extends State<PayslipRequestsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final RequestService _requestService = RequestService();
  List<dynamic> _requests = [];
  bool _isLoading = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Rejected',
    'Cancelled',
  ];

  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 5;
  int _totalPages = 0;
  bool _showFilters = false;
  bool _isTableView = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    // Background refresh: keep the current list instead of flashing the loader.
    _fetchRequests(showLoader: false);
  }

  @override
  void initState() {
    super.initState();
    // Date filter is single-date only; start unfiltered (no range).
    _startDate = null;
    _endDate = null;
    _fetchRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchRequests({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
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

  Future<void> _viewPayslipItem(Map<String, dynamic> req) async {
    try {
      final payroll = req['payrollId'];
      final payrollId = payroll is Map
          ? (payroll['_id']?.toString() ?? payroll['id']?.toString())
          : (payroll is String ? payroll : req['_id']?.toString());
      final token = await _requestService.getToken();
      final baseUrl = _requestService.baseUrl.replaceAll(RegExp(r'/+$'), '');

      String? url = req['payslipUrl']?.toString() ??
          (payroll is Map ? payroll['payslipUrl']?.toString() : null);

      if (url == null || url.isEmpty) {
        if (payrollId != null && payrollId.isNotEmpty) {
          url = '$baseUrl/admin/staff/payroll/statement/$payrollId/view?token=$token';
        }
      }

      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Unable to open payslip preview.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Error opening payslip: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _downloadPayslipItem(Map<String, dynamic> req) async {
    try {
      final payroll = req['payrollId'];
      final payrollId = payroll is Map
          ? (payroll['_id']?.toString() ?? payroll['id']?.toString())
          : (payroll is String ? payroll : req['_id']?.toString());
      final token = await _requestService.getToken();
      final baseUrl = _requestService.baseUrl.replaceAll(RegExp(r'/+$'), '');

      String? downloadUrl;
      if (payrollId != null && payrollId.isNotEmpty) {
        downloadUrl = '$baseUrl/admin/staff/payroll/statement/$payrollId/view?token=$token&download=true';
      } else {
        downloadUrl = req['payslipUrl']?.toString() ??
            (payroll is Map ? payroll['payslipUrl']?.toString() : null);
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Payslip download link not available.',
            isError: true,
          );
        }
        return;
      }

      // Try in-app download and open file
      try {
        final dir = await getApplicationDocumentsDirectory();
        final fileName = 'payslip_${payrollId ?? "statement"}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final savePath = '${dir.path}/$fileName';

        final dio = Dio();
        final response = await dio.download(downloadUrl, savePath);
        if (response.statusCode == 200) {
          final openRes = await OpenFilex.open(savePath);
          if (mounted) {
            SnackBarUtils.showSnackBar(
              context,
              'Payslip downloaded successfully',
              isError: false,
            );
          }
          return;
        }
      } catch (_) {
        // Fallback to browser launch
      }

      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Downloading payslip... Check your browser downloads.',
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
        SnackBarUtils.showSnackBar(
          context,
          'Error downloading payslip: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _cancelPayslipRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Payslip Request'),
        content: const Text('Are you sure you want to cancel this payslip request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final res = await _requestService.cancelPayslipRequest(requestId);
    if (!mounted) return;
    if (res['success'] == true) {
      SnackBarUtils.showSnackBar(
        context,
        res['message']?.toString() ?? 'Payslip request cancelled',
        isError: false,
      );
      _fetchRequests();
    } else {
      SnackBarUtils.showSnackBar(
        context,
        res['message']?.toString() ?? 'Failed to cancel payslip request',
        isError: true,
      );
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
        : '-';
    String approvedBy = '-';
    String rejectedBy = '-';
    final approver = req['approvedBy'];
    final rejector = req['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = '-';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = '-';
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

  Widget _buildPayslipControlBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Payslip Requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              // Card / Table View Mode Toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _isTableView = false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: !_isTableView ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: !_isTableView
                              ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4)]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.grid_view_rounded,
                              size: 14,
                              color: !_isTableView ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Cards',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: !_isTableView ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _isTableView = true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isTableView ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _isTableView
                              ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4)]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.table_rows_rounded,
                              size: 14,
                              color: _isTableView ? const Color(0xFFEFAA1F) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Table',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _isTableView ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Search input
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search Reason, Month...',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                      ),
                    ),
                    onChanged: (val) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 500), () {
                        _fetchRequests();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Status dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statusOptions.contains(_selectedStatus) ? _selectedStatus : _statusOptions.first,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                    items: _statusOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayslipCard(Map<String, dynamic> req) {
    final appliedDate = req['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(req['createdAt']))
        : '-';

    String periodText = 'Payslip Request';
    if (req['period'] != null) {
      periodText = req['period'].toString();
    } else if (req['month'] != null) {
      final monthName = _getMonthName(req['month']);
      final year = req['year']?.toString() ?? '';
      periodText = '$monthName $year'.trim();
    }

    final status = (req['status'] ?? 'Pending').toString();
    final isPending = status.toLowerCase() == 'pending';
    final isApproved = status.toLowerCase() == 'approved' || status.toLowerCase() == 'generated';
    final isRejected = status.toLowerCase() == 'rejected';

    final Color statusBg = isApproved
        ? const Color(0xFFECFDF5)
        : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
    final Color statusBorder = isApproved
        ? const Color(0xFFA7F3D0)
        : (isRejected ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
    final Color statusText = isApproved
        ? const Color(0xFF059669)
        : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));

    final reason = (req['reason'] ?? '').toString().trim();
    final rejectionReason = (req['actionReason'] ?? req['rejectionReason'])?.toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPayslipDetails(req),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFEFAA1F), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              periodText,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Applied: $appliedDate',
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusBorder),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: statusText,
                        ),
                      ),
                    ),
                  ],
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    reason,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (isRejected && rejectionReason != null && rejectionReason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 13, color: Color(0xFFDC2626)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Rejected: $rejectionReason',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isApproved) ...[
                      OutlinedButton.icon(
                        onPressed: () => _viewPayslipItem(req),
                        icon: const Icon(Icons.description_outlined, size: 14, color: Color(0xFF0F172A)),
                        label: const Text('View', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _downloadPayslipItem(req),
                        icon: const Icon(Icons.download_rounded, size: 14),
                        label: const Text('Download', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEFAA1F),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ] else if (isPending) ...[
                      OutlinedButton.icon(
                        onPressed: () {
                          final id = req['_id']?.toString() ?? req['id']?.toString();
                          if (id != null && id.isNotEmpty) {
                            _cancelPayslipRequest(id);
                          }
                        },
                        icon: const Icon(Icons.cancel_outlined, size: 14, color: Color(0xFFDC2626)),
                        label: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPayslipTableView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            headingTextStyle: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
            dataTextStyle: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            columns: const [
              DataColumn(label: Text('MONTH/YEAR')),
              DataColumn(label: Text('REQUEST REASON')),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('REJECTION REASON')),
              DataColumn(label: Text('ACTION')),
            ],
            rows: _requests.map((req) {
              final raw = req is Map<String, dynamic> ? req : Map<String, dynamic>.from(req as Map);
              String periodText = '-';
              if (raw['period'] != null) {
                periodText = raw['period'].toString();
              } else if (raw['month'] != null) {
                final monthName = _getMonthName(raw['month']);
                final year = raw['year']?.toString() ?? '';
                periodText = '$monthName $year'.trim();
              }

              final status = (raw['status'] ?? 'Pending').toString();
              final isPending = status.toLowerCase() == 'pending';
              final isApproved = status.toLowerCase() == 'approved' || status.toLowerCase() == 'generated';
              final isRejected = status.toLowerCase() == 'rejected';

              final Color statusBg = isApproved
                  ? const Color(0xFFECFDF5)
                  : (isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
              final Color statusBorder = isApproved
                  ? const Color(0xFFA7F3D0)
                  : (isRejected ? const Color(0xFFFECACA) : const Color(0xFFFDE68A));
              final Color statusText = isApproved
                  ? const Color(0xFF059669)
                  : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFD97706));

              final reason = (raw['reason'] ?? '-').toString().trim();
              final rejReason = (raw['actionReason'] ?? raw['rejectionReason'] ?? '-').toString().trim();

              return DataRow(
                cells: [
                  DataCell(Text(periodText, style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusBorder),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: statusText,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(isRejected ? rejReason : '-', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    isApproved
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_red_eye_outlined, size: 16, color: Color(0xFF0F172A)),
                                onPressed: () => _viewPayslipItem(raw),
                                tooltip: 'View',
                              ),
                              IconButton(
                                icon: const Icon(Icons.download_rounded, size: 16, color: Color(0xFFEFAA1F)),
                                onPressed: () => _downloadPayslipItem(raw),
                                tooltip: 'Download',
                              ),
                            ],
                          )
                        : (isPending
                            ? OutlinedButton(
                                onPressed: () {
                                  final id = raw['_id']?.toString() ?? raw['id']?.toString();
                                  if (id != null && id.isNotEmpty) {
                                    _cancelPayslipRequest(id);
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFFECACA)),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  minimumSize: Size.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.cancel_outlined, size: 12, color: Color(0xFFDC2626)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Cancel',
                                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                                    ),
                                  ],
                                ),
                              )
                            : const Text('-', style: TextStyle(color: Color(0xFF94A3B8)))),
                  ),
                ],
              );
            }).toList(),
          ),
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
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF424242),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: Color(0xFF424242)),
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        _endDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
          999,
        );
      });
      _fetchRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchRequests(showLoader: false);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Control Bar with Dual View Mode Switcher
                _buildPayslipControlBar(),

                // List / Table Content
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: const Center(child: AppTabLoader()),
                  )
                else if (_requests.isEmpty)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFBEB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.description_outlined,
                              size: 40,
                              color: Color(0xFFEFAA1F),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No payslip requests found',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_isTableView)
                  _buildPayslipTableView()
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      children: [
                        for (int i = 0; i < _requests.length; i++)
                          FadeSlideIn(
                            delay: Duration(
                              milliseconds: (i * 40).clamp(0, 240),
                            ),
                            child: _buildPayslipCard(_requests[i]),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bottom action bar: page numbers & Request Payslip button
        _PaginationBar(
          currentPage: _currentPage,
          totalPages: _totalPages,
          onPageSelected: (page) {
            setState(() => _currentPage = page);
            _fetchRequests();
          },
          createLabel: 'Request Payslip',
          onCreate: showRequestPayslipDialog,
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

  static const List<String> _months = [
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

  late String _month;
  late final TextEditingController _yearController;
  final TextEditingController _reasonController = TextEditingController();

  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = _months[now.month - 1];
    _yearController = TextEditingController(text: now.year.toString());
  }

  @override
  void dispose() {
    _yearController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final yearStr = _yearController.text.trim();
    final year = int.tryParse(yearStr);
    if (year == null || year < 2000 || year > 2100) {
      setState(() => _errorMessage = 'Please enter a valid year.');
      return;
    }

    setState(() => _isSubmitting = true);

    final payload = <String, dynamic>{
      'month': _month,
      'year': yearStr,
      'reason': _reasonController.text.trim(),
      // Fallback number representation if needed
      'monthNumber': _months.indexOf(_month) + 1,
    };

    final result = await _requestService.requestPayslip(payload);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      Navigator.pop(context);
      widget.onSuccess();
      showRequestSubmittedSuccessDialog(context);
    } else {
      setState(() {
        _errorMessage = ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to submit payslip request.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Request Payslip',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Request a payslip for a specific month',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFF1F5F9), height: 24),

              // Error banner if any
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _errorMessage = null),
                        child: const Icon(Icons.close, size: 14, color: Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Month
              const Text(
                'Month',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _month,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                    items: _months
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (val) {
                            if (val != null) setState(() => _month = val);
                          },
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Year
              const Text(
                'Year',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _yearController,
                keyboardType: TextInputType.number,
                enabled: !_isSubmitting,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'e.g., 2026',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Reason (Optional)
              const Text(
                'Reason (Optional)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                enabled: !_isSubmitting,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'Enter reason for payslip request',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFAA1F),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Submit Request',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
