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

  /// Tab specs in display order. Index maps 1:1 to the [TabBarView] children.
  static const List<_RequestTabSpec> _tabSpecs = [
    _RequestTabSpec('Leave', Icons.event_available_rounded),
    _RequestTabSpec('Permission', Icons.fact_check_outlined),
    _RequestTabSpec('Expense', Icons.receipt_long_rounded),
    _RequestTabSpec('Loan', Icons.account_balance_wallet_rounded),
  ];

  // Keys let the app-bar filter button and the create FAB drive whichever tab
  // is currently visible (each tab exposes toggleFilters / show…Dialog).
  final GlobalKey<_LeaveRequestsTabState> _leaveKey = GlobalKey();
  final GlobalKey<_LoanRequestsTabState> _loanKey = GlobalKey();
  final GlobalKey<_ExpenseRequestsTabState> _expenseKey = GlobalKey();
  final GlobalKey<_PermissionRequestsTabState> _permissionKey = GlobalKey();

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
    // The screen is no longer recreated on a sub-tab change (stable key in the
    // dashboard), so honor an externally-requested tab (deep link / drawer) by
    // jumping the controller. When the change is just the echo of an in-screen
    // tap, the controller is already on [target] and animateTo is a no-op.
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
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
        _loanKey.currentState?.refresh();
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
        _loanKey.currentState?.toggleFilters();
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
            // IndexedStack (not TabBarView) builds all four tabs up front, so
            // each one fetches its data at screen open and switching between
            // them is instant — no per-tab loading spinner. Tab taps drive the
            // visible index via the TabController listener above.
            child: IndexedStack(
              index: _tabController.index,
              sizing: StackFit.expand,
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
                LoanRequestsTab(
                  key: _loanKey,
                  isVisible: () => _tabController.index == 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The Figma-style top tab strip: four equal segments, icon over label,
  /// the active segment filled with a soft amber pill.
  Widget _buildTabStrip() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        indicator: BoxDecoration(
          color: AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        dividerColor: Colors.transparent,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: _tabSpecs
            .map(
              (t) => Tab(
                height: 58,
                iconMargin: const EdgeInsets.only(bottom: 4),
                icon: Icon(t.icon, size: 22),
                // Scale the label down to fit its segment so longer labels
                // (e.g. "Permission") are never clipped.
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

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageSelected,
    this.createLabel,
    this.onCreate,
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
    return ElevatedButton.icon(
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

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
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
                      _isHalfDayLeaveRecord(leave)
                          ? '${leave['days']} (${_halfDaySessionLabel(leave)})'
                          : '${leave['days']}',
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
      child: _buildBalanceCardBody(balance, colorScheme),
    );
  }

  /// Card content. When the assigned leave template configures an allocation for
  /// this type (`allocated` present), show the remaining balance prominently with
  /// the entitlement and usage breakdown. Otherwise (uncapped, e.g. Unpaid Leave),
  /// fall back to showing days taken.
  Widget _buildBalanceCardBody(dynamic balance, ColorScheme colorScheme) {
    final num? allocated = balance is Map && balance['allocated'] is num
        ? balance['allocated'] as num
        : null;
    final pending = _balancePendingCount(balance);

    final header = Text(
      balance['type'] ?? 'Leave',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (allocated == null) {
      // Uncapped type — no template allocation to show.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          header,
          const SizedBox(height: 2),
          Text(
            _trimBalanceNum(balance['takenCount']),
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
          if (pending > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${_trimBalanceNum(balance['pendingCount'])} pending',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ],
        ],
      );
    }

    // Prefer the backend-computed remaining; fall back to allocated − taken − pending.
    final num remaining = balance['remaining'] is num
        ? balance['remaining'] as num
        : (allocated -
                  ((balance['takenCount'] is num)
                      ? balance['takenCount'] as num
                      : 0) -
                  pending)
              .clamp(0, allocated);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        header,
        const SizedBox(height: 2),
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              TextSpan(
                text: _trimBalanceNum(remaining),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              TextSpan(
                text: ' / ${_trimBalanceNum(allocated)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Available',
          style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          '${_trimBalanceNum(balance['takenCount'])} taken'
          '${pending > 0 ? ' • ${_trimBalanceNum(balance['pendingCount'])} pending' : ''}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: pending > 0 ? AppColors.warning : colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Pending leave days for this type (0 if absent). Per-user value from the DB.
  double _balancePendingCount(dynamic balance) {
    final v = balance is Map ? balance['pendingCount'] : null;
    return v is num ? v.toDouble() : 0.0;
  }

  /// Trim a numeric count for display: "2" not "2.0", "0.5" kept as-is.
  String _trimBalanceNum(dynamic v) {
    final n = v is num ? v.toDouble() : 0.0;
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toString();
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
                                  ? 'Select date'
                                  : _isSameCalendarDay(_startDate!, _endDate!)
                                  ? DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(_startDate!)
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null && _endDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: _clearDateFilter,
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

                // List Body — loader / empty / items scroll with the header.
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: const Center(child: AppTabLoader()),
                  )
                else if (_leaves.isEmpty)
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
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        for (int i = 0; i < _leaves.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: FadeSlideIn(
                              delay: Duration(
                                milliseconds: (i * 45).clamp(0, 270),
                              ),
                              child: _buildLeaveCard(_leaves[i]),
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
        // and the Apply Leave button on the right (pinned footer).
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
  final AttendanceService _attendanceService = AttendanceService();

  String? _leaveType;
  // Leave duration: Full Day / First Half / Second Half. Half-day applies to ANY
  // leave type and is only offered when the staff's shift enables it
  // (_halfDayEnabled).
  _LeaveDuration _duration = _LeaveDuration.full;
  bool _halfDayEnabled = false;
  List<dynamic> _allowedTypes = [];
  // Employee gender (e.g. "Male"/"Female"), used to gate Maternity/Paternity
  // leave. Empty when unknown — in that case no gender restriction is applied.
  String _gender = '';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isOneDay = true;
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingTypes = true;
  double _availableCasualLeaves = 0.0;
  double _totalAllowed = 0.0;
  double _usedLeaveDays = 0.0;
  double _pendingLeaveDays = 0.0;
  HolidayOffConfig _offConfig = HolidayOffConfig.empty;
  bool _showLimitWarning = false;
  String _limitWarningMsg = '';
  // Today's shift end time ("HH:mm", 24h). Once this passes, the working day is
  // over and same-day leave no longer makes sense — today gets blocked. Falls
  // back to the codebase-wide default shift end when the template is unknown.
  String _shiftEndTime = '18:30';

  /// True when the selected duration is a half-day (First or Second Half).
  bool get _isHalf => _duration != _LeaveDuration.full;

  /// Backend session value for the selected half-day: '1' (first) / '2' (second),
  /// or null for a full-day leave.
  String? get _session => _duration == _LeaveDuration.firstHalf
      ? '1'
      : _duration == _LeaveDuration.secondHalf
          ? '2'
          : null;

  @override
  void initState() {
    super.initState();
    _fetchLeaveTypes();
    _fetchLeaveBalance();
    _loadOffConfig();
    _loadShiftCutoff();
  }

  Future<void> _loadOffConfig() async {
    final config = await loadHolidayOffConfig();
    if (mounted) setState(() => _offConfig = config);
  }

  /// Loads today's shift end time so same-day leave can be blocked once the
  /// working day is over. Best-effort: keeps the default end on any failure.
  Future<void> _loadShiftCutoff() async {
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final att = await _attendanceService.getAttendanceByDate(dateStr);
      final body = att['data'] as Map<String, dynamic>?;
      final template = body?['template'] as Map?;
      final end = template?['shiftEndTime']?.toString().trim();
      if (end != null && end.isNotEmpty && mounted) {
        setState(() => _shiftEndTime = end);
      }
    } catch (_) {
      // Best-effort; keep the default shift end.
    }
  }

  /// Today's same-day leave cutoff: today's date at the shift end time. After
  /// this instant the working day is over, so today can no longer be chosen.
  DateTime _todayCutoff() {
    final now = DateTime.now();
    var h = 18;
    var m = 30;
    final parts = _shiftEndTime.split(':');
    if (parts.length >= 2) {
      h = int.tryParse(parts[0].trim()) ?? h;
      m = int.tryParse(parts[1].trim()) ?? m;
    }
    return DateTime(now.year, now.month, now.day, h, m);
  }

  /// True once today's working day has ended — same-day leave is no longer
  /// allowed and the leave must start tomorrow or later.
  bool get _isTodayClosed => DateTime.now().isAfter(_todayCutoff());

  /// True when [day] is today and the working day has already ended.
  bool _isClosedToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year &&
        day.month == now.month &&
        day.day == now.day &&
        _isTodayClosed;
  }

  @override
  void dispose() {
    SnackBarUtils.dismiss();
    _reasonController.dispose();
    super.dispose();
  }

  /// The month the leave balance is scoped to: the selected leave's start month,
  /// or the current month before a date is picked. The template allocation is a
  /// monthly quota that resets each month, so a next-month application must be
  /// validated against next month's fresh quota — not this month's usage.
  DateTime get _balanceMonth => _startDate ?? DateTime.now();

  Future<void> _fetchLeaveBalance() async {
    final month = _balanceMonth;
    final result = await _requestService.getLeaveBalance(forMonth: month);
    if (!mounted || result['success'] != true) return;

    final total = (result['totalAllowed'] as num?)?.toDouble() ?? 0.0;

    // Always load the employee's own leave records so we can show per-type
    // allocated/used/pending (the records endpoint works on every backend).
    final usage = await _computeLeaveUsageFromRecords(forMonth: month);

    // Prefer backend-computed overall totals when present; otherwise use the
    // totals derived from the records.
    final beUsed = (result['usedDays'] as num?)?.toDouble();
    final bePending = (result['pendingLeaveDays'] as num?)?.toDouble();

    if (!mounted) return;
    setState(() {
      _totalAllowed = total;
      _usedLeaveDays = beUsed ?? usage.$1;
      _pendingLeaveDays = bePending ?? usage.$2;
      _availableCasualLeaves = (total - _usedLeaveDays).clamp(0.0, total);
    });
  }

  /// Normalizes a leave-type name to a match key (mirrors the backend):
  /// lowercase, drop the word "leave", strip spaces. "Casual Leave" -> "casual".
  String _leaveTypeKey(String? s) {
    final t = (s ?? '').toLowerCase().trim();
    return t.replaceAll(RegExp(r'\bleave\b'), '').replaceAll(RegExp(r'\s+'), '');
  }

  /// Allocated days for [type] from the staff's leave template (null = no fixed
  /// allocation, e.g. Unpaid Leave). Sourced from getLeaveTypesForApply.
  ///
  /// Half Day is special: the backend sends it as `{type:'Half Day', days:0.5}`
  /// where `days` is the per-request duration of a half-day leave, NOT an annual
  /// allocation. Half Day draws from the same shared pool as every other type
  /// (see backend getAvailableLeavePool), so treat it as having no specific
  /// allocation and let the entitlement card fall back to the overall pool
  /// total. Returning 0.5 here would mislabel the pool as "0.5 allocated days".
  double? _allocatedForType(String? type) {
    if (_isHalfDayLeave(type)) return null;
    final key = _leaveTypeKey(type);
    for (final e in _allowedTypes) {
      if (e is Map && _leaveTypeKey(e['type'] as String?) == key) {
        final d = e['days'];
        return d is num ? d.toDouble() : null;
      }
    }
    return null;
  }

  /// Loads this employee's Approved (used) and Pending leave days for the target
  /// month ([forMonth], defaulting to the current month) from their own records,
  /// returning the overall (usedDays, pendingDays). The template allocation is a
  /// monthly quota that resets each month, so usage is scoped to that month to
  /// match the backend balance (see getLeaveBalance). Only a fallback — the
  /// backend normally supplies these totals directly.
  Future<(double, double)> _computeLeaveUsageFromRecords({
    DateTime? forMonth,
  }) async {
    final base = forMonth ?? DateTime.now();
    final monthStart = DateTime(base.year, base.month, 1);
    final monthEnd = DateTime(base.year, base.month + 1, 0, 23, 59, 59);

    double daysOf(dynamic l) {
      final d = (l is Map) ? l['days'] : null;
      return d is num ? d.toDouble() : double.tryParse(d?.toString() ?? '') ?? 0;
    }

    List<dynamic> listOf(Map<String, dynamic> res) {
      final data = res['data'];
      return data is Map
          ? (data['leaves'] as List? ?? [])
          : (data is List ? data : []);
    }

    double used = 0;
    double pending = 0;
    try {
      final approved = await _requestService.getLeaveRequests(
        status: 'Approved',
        startDate: monthStart,
        endDate: monthEnd,
        page: 1,
        limit: 500,
      );
      if (approved['success'] == true) {
        for (final l in listOf(approved)) {
          used += daysOf(l);
        }
      }

      // Pending requests overlapping the current month commit against this
      // month's allocation (same monthly window as approved usage).
      final pend = await _requestService.getLeaveRequests(
        status: 'Pending',
        startDate: monthStart,
        endDate: monthEnd,
        page: 1,
        limit: 500,
      );
      if (pend['success'] == true) {
        for (final l in listOf(pend)) {
          pending += daysOf(l);
        }
      }
    } catch (_) {
      // Best-effort; leave totals at 0 on failure.
    }
    return (used, pending);
  }

  /// Gender-restricted leave types: Maternity is female-only, Paternity is
  /// male-only. Returns false only when the employee's gender is positively
  /// known to be the wrong one; an unknown/empty gender is permissive so we
  /// never wrongly block a legitimate applicant.
  bool _isTypeAllowedForGender(String? type) {
    final g = _gender.toLowerCase().trim();
    final isFemale = g.startsWith('f');
    final isMale = g.startsWith('m');
    switch (_leaveTypeKey(type)) {
      case 'maternity':
        return !isMale; // female or unknown
      case 'paternity':
        return !isFemale; // male or unknown
      default:
        return true;
    }
  }

  /// Loads the employee's gender from their profile so Maternity/Paternity
  /// leave can be gated. Best-effort: leaves [_gender] empty on failure.
  Future<void> _loadGender() async {
    try {
      final result = await _authService.getProfile();
      if (result['success'] == true) {
        final data = result['data'];
        final staff = data is Map ? data['staffData'] : null;
        final g = staff is Map ? staff['gender'] : null;
        _gender = g?.toString() ?? '';
      }
    } catch (_) {
      // Best-effort; leave _gender empty (no restriction) on failure.
    }
  }

  Future<void> _fetchLeaveTypes() async {
    // Gender must be known before filtering the types so Maternity/Paternity
    // are gated from the start (and the default selection is a valid type).
    await _loadGender();
    final result = await _requestService.getLeaveTypesForApply();
    if (mounted) {
      if (result['success']) {
        // Half-day is a duration now, not a type — drop any legacy 'Half Day'
        // entry the backend might still send, and gate Maternity/Paternity by
        // gender.
        final raw = List<dynamic>.from(result['data'] as List? ?? [])
            .where((e) {
              final type = e is Map ? e['type'] as String? : null;
              if (_isHalfDayLeave(type)) return false;
              return _isTypeAllowedForGender(type);
            })
            .toList();
        setState(() {
          _allowedTypes = raw;
          // The shift gates half-day via halfDaySettings.enabled; the backend
          // reports it so the form can offer First/Second Half on any type.
          _halfDayEnabled = result['halfDayEnabled'] == true;
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
    if (_isHalf) return 0; // 0.5 on backend
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
    // Once today's working day is over, the earliest selectable day is tomorrow.
    final earliest = _isTodayClosed ? today.add(const Duration(days: 1)) : today;
    final candidate = (isStart ? _startDate : _endDate) ?? earliest;
    final initial = _offConfig.firstSelectableOnOrAfter(
      candidate.isBefore(earliest) ? earliest : candidate,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: DateTime(2030, 12, 31),
      selectableDayPredicate: (day) =>
          !_offConfig.isDisabled(day) && !_isClosedToday(day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _showLimitWarning = false;
      if (isStart) {
        _startDate = picked;
        if (_isOneDay || _isHalf) {
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
    // The chosen start date may fall in a different month than was last loaded;
    // refresh the balance so the entitlement card and limit warning reflect that
    // month's quota (usage resets monthly — see _balanceMonth).
    if (isStart) unawaited(_fetchLeaveBalance());
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
    // Same-day cutoff: once today's working day has ended, a leave that starts
    // today no longer makes sense — require it to start tomorrow or later.
    if (_isClosedToday(_startDate!)) {
      SnackBarUtils.showSnackBar(
        context,
        'The working day has already ended. You can apply leave from tomorrow onwards.',
        isError: true,
      );
      return;
    }
    final effectiveEnd = _isOneDay || _isHalf ? _startDate! : _endDate;
    if (!_isOneDay &&
        !_isHalf &&
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
    if (_isHalf && !_isOneDay && _endDate != null && _endDate != _startDate) {
      SnackBarUtils.showSnackBar(
        context,
        'Half-day leave allows only one date.',
        isError: true,
      );
      return;
    }
    // Safety net: Maternity is female-only, Paternity is male-only. The
    // dropdown already hides the mismatched type, but re-check on submit in
    // case gender loaded late or the list was stale.
    if (!_isTypeAllowedForGender(_leaveType)) {
      final isMaternity = _leaveTypeKey(_leaveType) == 'maternity';
      SnackBarUtils.showSnackBar(
        context,
        isMaternity
            ? 'Maternity Leave is available only for female employees.'
            : 'Paternity Leave is available only for male employees.',
        isError: true,
      );
      return;
    }

    final daysValue = _isHalf ? 0.5 : _days;
    final requestedDays = _isHalf ? 0.5 : _days.toDouble();
    final rangeEnd = effectiveEnd ?? _startDate!;

    // Unpaid Leave: no balance validation
    final isUnpaidLeave =
        _leaveType != null &&
        _leaveType!.toLowerCase().replaceAll(RegExp(r'\s+'), '') ==
            'unpaidleave';
    if (!isUnpaidLeave) {
      await _fetchLeaveBalance();
      if (!mounted) return;
      // Effective available = approved balance minus any still-pending requests.
      final effectiveAvailable = _effectiveAvailableLeaves;
      final pendingNote = _pendingLeaveDays > 0
          ? ' (${_trimNum(_pendingLeaveDays)} day${_pendingLeaveDays != 1 ? "s" : ""} pending approval)'
          : '';
      if (effectiveAvailable <= 0) {
        final msg =
            'Leave balance exhausted$pendingNote. Requesting '
            '${_trimNum(requestedDays)} day${requestedDays != 1 ? "s" : ""} '
            'may result in a fine/salary deduction.';
        setState(() {
          _showLimitWarning = true;
          _limitWarningMsg = msg;
        });
        unawaited(
          FcmService.showLimitExceededLocalNotification(
            type: 'leave',
            message: msg,
          ),
        );
        unawaited(
          _requestService.notifyAdminLimitExceeded(
            type: 'leave',
            requested: requestedDays,
            limit: 0,
          ),
        );
        return;
      }
      if (effectiveAvailable == 0.5) {
        if (!_isHalf) {
          final msg =
              'Only 0.5 days remaining$pendingNote. Requesting '
              '${_trimNum(requestedDays)} day${requestedDays != 1 ? "s" : ""} '
              'may result in a fine/salary deduction.';
          setState(() {
            _showLimitWarning = true;
            _limitWarningMsg = msg;
          });
          unawaited(
            FcmService.showLimitExceededLocalNotification(
              type: 'leave',
              message: msg,
            ),
          );
          unawaited(
            _requestService.notifyAdminLimitExceeded(
              type: 'leave',
              requested: requestedDays,
              limit: 0.5,
            ),
          );
          return;
        }
      } else if (requestedDays > effectiveAvailable) {
        final excess = requestedDays - effectiveAvailable;
        final msg =
            'Insufficient balance$pendingNote. Requested ${_trimNum(requestedDays)} '
            'day${requestedDays != 1 ? "s" : ""}, only '
            '${_trimNum(effectiveAvailable)} available. '
            '${_trimNum(excess)} excess day${excess != 1 ? "s" : ""} '
            'may be deducted as a fine.';
        setState(() {
          _showLimitWarning = true;
          _limitWarningMsg = msg;
        });
        unawaited(
          FcmService.showLimitExceededLocalNotification(
            type: 'leave',
            message: msg,
          ),
        );
        unawaited(
          _requestService.notifyAdminLimitExceeded(
            type: 'leave',
            requested: requestedDays,
            limit: effectiveAvailable,
          ),
        );
        return;
      }
    }

    // Backend checks "leave already applied" and returns a single error message.
    // leaveType stays the real type (Casual/Sick/…); the half-day is conveyed via
    // session + halfDaySession so the backend records it as 0.5 of that type.
    final payload = {
      'leaveType': _leaveType,
      'startDate': _startDate!.toIso8601String(),
      'endDate': rangeEnd.toIso8601String(),
      'days': daysValue,
      'reason': _reasonController.text,
      'session': _isHalf ? _session : null,
      if (_isHalf)
        'halfDaySession':
            _session == '1' ? 'First Half Day' : 'Second Half Day',
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

  /// Approved balance minus still-pending requests, clamped to the allowance.
  double get _effectiveAvailableLeaves =>
      (_availableCasualLeaves - _pendingLeaveDays).clamp(
        0.0,
        _totalAllowed > 0 ? _totalAllowed : _availableCasualLeaves,
      );

  /// Combined allocated days across ALL leave types in the staff's template
  /// (sum of every type's `days`). Half Day is excluded (its 0.5 is a
  /// per-request duration, not an allocation) and types without a fixed
  /// allocation (e.g. Unpaid Leave, days == null) contribute nothing.
  double get _totalAllocatedAllTypes {
    double sum = 0;
    for (final e in _allowedTypes) {
      if (e is! Map) continue;
      final type = e['type'] as String?;
      if (_isHalfDayLeave(type)) continue;
      final d = e['days'];
      if (d is num) sum += d.toDouble();
    }
    return sum;
  }

  /// Full entitlement for the selected leave type (its allocated days). The
  /// "days remaining" labels show the entitlement; used/pending are
  /// informational and surfaced separately, so they are NOT subtracted here
  /// (mirrors the entitlement card headline).
  double get _selectedTypeRemaining {
    final allocated = _allocatedForType(_leaveType) ?? _totalAllowed;
    return allocated > 0 ? allocated : 0.0;
  }

  Widget _buildLimitWarningBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade400),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leave Limit Exceeded',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your admin has been notified.',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

  /// Amber "Leave Entitlement" hero - the headline shows the FULL leave
  /// entitlement (total allocated days). Approved (used) and pending days are
  /// informational only and shown in the sub-line; they do NOT reduce the
  /// headline figure.
  Widget _buildEntitlementCard() {
    // Show the COMBINED entitlement across all leave types (sum of the
    // template's per-type allocations), not just the selected type. Falls back
    // to the backend overall total if the template carries no per-type days.
    final allocated =
        _totalAllocatedAllTypes > 0 ? _totalAllocatedAllTypes : _totalAllowed;
    final total = allocated;
    final usedType = _usedLeaveDays;
    final pendingType = _pendingLeaveDays;
    // Headline = full entitlement (allocated). Used/pending are not subtracted.
    final entitlement = total;
    final usedClamped = usedType > allocated ? allocated : usedType;
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
                      : '${_trimNum(entitlement)} Days Remaining',
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
                      : pendingType > 0
                      ? 'Used ${_trimNum(usedClamped)} of ${_trimNum(total)} allocated days · ${_trimNum(pendingType)} pending approval.'
                      : 'You have used ${_trimNum(usedClamped)} of ${_trimNum(total)} allocated days.',
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      items: _allowedTypes.map((e) {
        final type = e['type'] as String? ?? '';
        // Show the leave template's total allocated count next to the type.
        // Skip Half Day (its 0.5 is a per-request duration, not an annual
        // allocation) and Unpaid Leave / untyped allocations (days == null).
        final days = (!_isHalfDayLeave(type) && e is Map) ? e['days'] : null;
        final countLabel = days is num ? '  ·  ${_trimNum(days)} days' : '';
        return DropdownMenuItem<String>(
          value: type,
          child: Text('$type$countLabel'),
        );
      }).toList(),
      onChanged: (val) {
        setState(() {
          _leaveType = val!;
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

  /// Build a single duration choice chip (Full Day / First Half / Second Half).
  Widget _durationChip(String label, _LeaveDuration value) {
    return ChoiceChip(
      label: Text(label),
      selected: _duration == value,
      onSelected: (_) {
        setState(() {
          _duration = value;
          // Half-day is always a single date — collapse any range.
          if (_isHalf) {
            _isOneDay = true;
            if (_startDate != null) _endDate = _startDate;
          }
        });
      },
      selectedColor: AppColors.primary.withValues(alpha: 0.3),
    );
  }

  /// Leave duration selector — lets the employee take any leave type as a Full
  /// Day, First Half, or Second Half. Only shown when the shift enables half-day.
  Widget _buildDurationSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Duration'),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _durationChip('Full Day', _LeaveDuration.full),
              _durationChip('First Half', _LeaveDuration.firstHalf),
              _durationChip('Second Half', _LeaveDuration.secondHalf),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = _isOneDay || _isHalf;
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header - back arrow + "New Request"
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
                  crossAxisAlignment:CrossAxisAlignment.start,
                  children: [
                    // Leave Entitlement hero
                   _buildEntitlementCard(),
                    const SizedBox(height: 14),
                    if (_showLimitWarning)
                      _buildLimitWarningBanner(_limitWarningMsg),
                    if (!_showLimitWarning) const SizedBox(height: 10),

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

                    // Leave duration (Full / First Half / Second Half) — applies
                    // to every leave type when the shift enables half-day.
                    if (_halfDayEnabled) _buildDurationSelector(),

                    // Single-day toggle (hidden for half-day, which is always single)
                    if (!_isHalf)
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
                          _isUnpaidLeave
                              ? (_isHalf
                                    ? 'Total: 0.5 day · No balance limit'
                                    : 'Total: $_days day${_days == 1 ? '' : 's'} · No balance limit')
                              : _isHalf
                              ? 'Total: 0.5 day - ${_trimNum(_selectedTypeRemaining)} days remaining'
                              : 'Total: $_days day${_days == 1 ? '' : 's'} - ${_trimNum(_selectedTypeRemaining)} days remaining',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),

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
                        hintStyle: const TextStyle(
                          color: AppColors.textCaption,
                        ),
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
                          borderSide: BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Reason is required'
                          : null,
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
            initialValue: _loanType,
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
                  const Text(
                    'Request Loan',
                    style: AppTextStyles.headingMedium,
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
    'Rejected',
    'Paid',
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
      if (!mounted) return;
      setState(() {
        _totalReimbursed = (data['totalReimbursed'] as num?)?.toDouble() ?? 0;
        _totalPending = (data['totalPending'] as num?)?.toDouble() ?? 0;
        _pendingClaimCount = (data['pendingCount'] as num?)?.toInt() ?? 0;
      });
      return;
    }
    // Fallback (summary endpoint not available on this backend): compute the
    // all-time totals client-side from the employee's own expense records.
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
          if (status == 'approved' || status == 'paid') {
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
    final type = (expense['type'] ?? expense['expenseType'] ?? 'Expense')
        .toString();
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
              child: Icon(
                _expenseIcon(type),
                color: AppColors.primary,
                size: 22,
              ),
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
                  '${_formatAmount(expense['amount'])}',
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
    super.build(context); // keep-alive
    // The whole tab is one scroll view so the hero, filters and list scroll
    // together — previously only the inner list scrolled, so with filters open
    // the upper section was cramped and unscrollable on small screens.
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
                // Figma "Expense Claims": amber summary hero + create button + header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      FadeSlideIn(child: _buildClaimHero()),
                      // const SizedBox(height: 14),
                      // FadeSlideIn(
                      // delay: const Duration(milliseconds: 60),
                      //  child: _buildCreateButton(),
                      // ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
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
                              onTap: _pickDate,
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
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
                                          : _isSameCalendarDay(
                                              _startDate!,
                                              _endDate!,
                                            )
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
                // While (re)loading after a query change show the loader and
                // reveal the list only once loaded, so stale results never flash.
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: const Center(child: AppTabLoader()),
                  )
                else if (_expenses.isEmpty)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Center(
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
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        for (int i = 0; i < _expenses.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: FadeSlideIn(
                              delay: Duration(
                                milliseconds: (i * 45).clamp(0, 270),
                              ),
                              child: _buildExpenseCard(_expenses[i]),
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
        // and the Claim Expense button on the right.
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
  final TextEditingController _descriptionController =
      TextEditingController(); // Description
  File? _selectedFile; // Add File variable
  bool _isSubmitting = false;

  /// Presents a chooser so the user can either capture a receipt with the
  /// device camera or pick an existing JPG/PNG/PDF from storage.
  Future<void> _pickFile() async {
    final source = await showModalBottomSheet<_ProofSource>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Take Photo'),
                onTap: () =>
                    Navigator.pop(sheetContext, _ProofSource.camera),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Choose from Files'),
                subtitle: const Text('JPG, PNG, or PDF'),
                onTap: () =>
                    Navigator.pop(sheetContext, _ProofSource.files),
              ),
              const SizedBox(height: 8),
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

  /// Captures a receipt photo with the device camera.
  Future<void> _pickFromCamera() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked != null) {
        setState(() {
          _selectedFile = File(picked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Unable to capture photo. Please check camera permissions.',
          isError: true,
        );
      }
    }
  }

  /// Picks an existing JPG/PNG/PDF receipt from device storage.
  Future<void> _pickFromFiles() async {
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
    // Bake EXIF orientation into the pixels FIRST so the stored proof is upright
    // everywhere (compression strips EXIF, and neither Flutter nor a stripped
    // copy would otherwise render the rotation). bakeBytes returns the same
    // instance when no rotation is needed, so PNGs keep their original encoding.
    final original = await file.readAsBytes();
    final upright = await ImageOrientation.bakeBytes(original);
    final rotated = !identical(upright, original);
    final result = await FlutterImageCompress.compressWithList(
      upright,
      minWidth: _maxProofImageWidth,
      minHeight: _maxProofImageWidth,
      quality: _proofImageQuality,
      // A rotated image was re-encoded to JPEG by the bake step.
      format: (path.endsWith('.png') && !rotated)
          ? CompressFormat.png
          : CompressFormat.jpeg,
    );
    if (result.isEmpty) {
      return upright;
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
  Widget _buildDateField({
    required DateTime? date,
    required VoidCallback onTap,
  }) {
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
                color: date == null
                    ? AppColors.textCaption
                    : AppColors.textPrimary,
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
                    : 'Take a photo or select a JPG, PNG, or PDF',
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                      decoration: _fieldDecoration(
                        hint: 'Enter expense amount',
                      ),
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

  // Permission requests come back for the whole month in one response, so we
  // page through them on the client (5 per page) to match the other tabs.
  int _currentPage = 1;
  final int _itemsPerPage = 5;

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
    _fetchRequests();
    _fetchBalance();
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
        _requests = data is Map ? (data['permissions'] ?? []) : [];
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

  void showRequestPermissionDialog() {
    // Block when permission is not configured for the shift at all.
    if (_balance != null && _balance?['configured'] == false) {
      SnackBarUtils.showSnackBar(
        context,
        'Permission is not configured for your shift. Contact HR.',
        isError: true,
      );
      return;
    }
    // Every other scenario opens the dialog — the request is always allowed and the
    // entire duration is processed as Fine when the shift is disabled and/or has no
    // quota: S2 (enabled, no quota), S3 (disabled, has quota), S4 (disabled, no quota).
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
    super.build(context); // keep-alive
    final theme = Theme.of(context);
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final quota = (_balance?['monthlyQuotaMinutes'] as num?)?.toDouble() ?? 0;
    final consumed = (_balance?['consumedMinutes'] as num?)?.toDouble() ?? 0;
    final pending = (_balance?['pendingMinutes'] as num?)?.toDouble() ?? 0;
    // Treat missing flags as configured/enabled so older backends are not blocked.
    final configured = _balance == null || _balance?['configured'] != false;
    final enabled = _balance == null || _balance?['enabled'] != false;
    // Hours line is whole hours; minutes line is the leftover minutes (total % 60)
    // so the two read as a single "Hh Mm" value (e.g. 90 -> "1 h / 30 min").
    // Showing total minutes on the second line (e.g. "60 h / 3600 min") looked
    // like the two figures disagreed.
    String hoursAndMinutes(double minutes) {
      final total = minutes < 0 ? 0 : minutes.round();
      final hrs = total ~/ 60;
      final mins = total % 60;
      return '$hrs h\n$mins min';
    }

    // Client-side paging: the backend returns the whole month at once.
    final totalPages = _requests.isEmpty
        ? 1
        : (_requests.length / _itemsPerPage).ceil();
    final safePage = _currentPage.clamp(1, totalPages);
    final pageStart = (safePage - 1) * _itemsPerPage;
    final pagedRequests = _requests
        .skip(pageStart)
        .take(_itemsPerPage)
        .toList();

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
                // Balance figures: only meaningful when Permission is configured,
                // enabled, and has a quota. Hide when disabled/unconfigured/no-quota
                // so misleading numbers (e.g. a stale monthly quota) are not shown.
                if (configured && enabled && quota > 0) ...[
                  Row(
                    children: [
                      _balanceTile('Monthly Allocated', hoursAndMinutes(quota)),
                      const SizedBox(width: 8),
                      _balanceTile('Used', hoursAndMinutes(consumed)),
                      const SizedBox(width: 8),
                      _balanceTile('Pending', hoursAndMinutes(pending)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                // Policy-state notices — show the appropriate message based on
                // configured / enabled / quota state.
                if (!configured)
                  _permissionNotice(
                    icon: Icons.info_outline,
                    color: Colors.orange,
                    message: 'Permission is not configured for your shift. Contact HR.',
                  ),
                if (!configured) const SizedBox(height: 12),
                if (configured && !enabled) ...[
                  _permissionNotice(
                    icon: Icons.info_outline,
                    color: Colors.orange,
                    message: quota > 0
                        ? 'Permission is disabled for your shift. Contact HR to enable.\n'
                              'Any permission request will be processed as Fine.'
                        : 'Permission is not configured for your shift. Contact HR.\n'
                              'Any permission request will be processed as Fine.',
                  ),
                  const SizedBox(height: 12),
                ],
                if (configured && enabled && quota <= 0) ...[
                  _permissionNotice(
                    icon: Icons.info_outline,
                    color: Colors.blue,
                    message:
                        'Permission is not configured for your shift. Contact HR.\n'
                        'Any permission request will be processed as Fine.',
                  ),
                  const SizedBox(height: 12),
                ],
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
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
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
                // While (re)loading after a query change show the loader and
                // reveal the list only once loaded, so stale results never flash.
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
                  ...pagedRequests.map((raw) {
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
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showPermissionDetails(req),
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
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(
                                      status,
                                    ).withOpacity(0.12),
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
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        // Bottom action bar: page numbers (only when multi-page) on the left
        // and the Request Permission button on the right.
        _PaginationBar(
          currentPage: safePage,
          totalPages: totalPages,
          onPageSelected: (page) => setState(() => _currentPage = page),
          createLabel: 'Request Permission',
          onCreate: showRequestPermissionDialog,
        ),
      ],
    );
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
  final AttendanceService _attendanceService = AttendanceService();
  DateTime _date = DateTime.now();
  String _type = 'lateArrival';
  // Planned out/in window — only used for the 'both' (custom-time) type.
  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  HolidayOffConfig _offConfig = HolidayOffConfig.empty;
  // Permission configuration gate. Defaults keep the form usable until config loads.
  bool _configured = true;
  bool _enabled = true;
  double _quotaMinutes = 0;
  double _consumedMinutes = 0;
  double _pendingMinutes = 0;
  bool _showLimitWarning = false;
  String _limitWarningMsg = '';

  // Per-user fine context (DB fine settings + this staff's salary/shift). Used to
  // preview the late/early fine that an over-quota or disabled permission incurs.
  Map<String, dynamic>? _fineCalculation;
  double? _netPerDaySalary;
  double _shiftHours = 9.0; // Fallback: default 09:30–18:30 shift.
  // Today's shift window as minutes-of-day. Used to reject a same-day permission
  // request whose time period has already begun. Null until the template loads.
  int? _shiftStartMinutes;
  int? _shiftEndMinutes;

  @override
  void initState() {
    super.initState();
    _loadOffConfig();
    _loadPermissionConfig();
    _loadFineContext();
    // Live-refresh the fine estimate as the user edits the requested minutes.
    _minutesController.addListener(_onMinutesChanged);
  }

  void _onMinutesChanged() {
    if (mounted) setState(() {});
  }

  /// Loads the DB fine rules, this user's per-day salary and shift hours so the
  /// form can estimate the fine for over-quota / disabled-permission minutes.
  Future<void> _loadFineContext() async {
    Map<String, dynamic>? fineConfig;
    try {
      final fineResult = await _attendanceService.getFineCalculation();
      if (fineResult['success'] == true) {
        fineConfig = fineResult['data'] as Map<String, dynamic>?;
      }
    } catch (_) {}

    double? net;
    try {
      final prefs = await SharedPreferences.getInstance();
      net = prefs.getDouble(kAppNetPerDaySalaryPrefsKey);
      if (net == null || net <= 0) {
        final gross = prefs.getDouble(kAppGrossPerDaySalaryPrefsKey);
        if (gross != null && gross > 0) net = gross;
      }
    } catch (_) {}

    double shiftHours = _shiftHours;
    int? shiftStartMinutes;
    int? shiftEndMinutes;
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final att = await _attendanceService.getAttendanceByDate(dateStr);
      final body = att['data'] as Map<String, dynamic>?;
      final template = body?['template'] as Map?;
      final start = template?['shiftStartTime']?.toString().trim();
      final end = template?['shiftEndTime']?.toString().trim();
      if (start != null && start.isNotEmpty && end != null && end.isNotEmpty) {
        final h = calculateShiftHours(start, end);
        if (h > 0) shiftHours = h;
        shiftStartMinutes = _shiftTimeToMinutes(start);
        shiftEndMinutes = _shiftTimeToMinutes(end);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _fineCalculation = fineConfig;
      _netPerDaySalary = net;
      _shiftHours = shiftHours;
      _shiftStartMinutes = shiftStartMinutes;
      _shiftEndMinutes = shiftEndMinutes;
    });
  }

  /// Parses an "HH:mm" shift-time string into minutes-of-day. Null if unparseable.
  int? _shiftTimeToMinutes(String? raw) {
    if (raw == null) return null;
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// A permission must be requested *before* its time period begins — a member
  /// cannot ask for late-arrival / early-exit cover after the fact. For a request
  /// dated today, returns an error message once that window's start time has
  /// passed; returns null when submission may proceed (future date, or the window
  /// hasn't started, or the shift window is unknown so we fail open).
  String? _periodAlreadyStartedError(int minutes) {
    final now = DateTime.now();
    final isToday =
        _date.year == now.year && _date.month == now.month && _date.day == now.day;
    if (!isToday) return null; // Future-dated requests: the period hasn't begun.
    final nowMinutes = now.hour * 60 + now.minute;

    int? windowStart;
    switch (_type) {
      case 'lateArrival':
        // Late-arrival cover starts at shift start; submitting after that means
        // the member has already arrived (late).
        windowStart = _shiftStartMinutes;
        break;
      case 'earlyExit':
        // Early-exit cover begins when the member would leave: shiftEnd − minutes.
        final end = _shiftEndMinutes;
        windowStart = end == null ? null : end - minutes;
        break;
      case 'both':
        // Custom window — its planned From time is the period start.
        final from = _fromTime;
        windowStart = from == null ? null : from.hour * 60 + from.minute;
        break;
    }
    if (windowStart == null) return null; // Unknown window — don't block.
    if (nowMinutes >= windowStart) {
      return 'A permission request must be submitted before its time period '
          'begins. The requested time has already passed for today — please '
          'request it for a future date.';
    }
    return null;
  }

  /// Maps the selected permission type to the fine-rule action key.
  String get _fineActionType {
    switch (_type) {
      case 'lateArrival':
        return 'lateArrival';
      case 'earlyExit':
        return 'earlyExit';
      default:
        return 'both';
    }
  }

  /// Estimated fine (₹) for [minutes] of the selected permission type, using the
  /// DB fine rules + this user's per-day salary. Returns 0 when salary is unknown.
  double _estimateFine(int minutes) {
    final net = _netPerDaySalary;
    if (net == null || net <= 0 || minutes <= 0) return 0.0;
    return estimateRuleBasedFine(
      fineCalculation: _fineCalculation,
      actionApplyToType: _fineActionType,
      minutes: minutes,
      netPerDaySalary: net,
      shiftHours: _shiftHours,
    );
  }

  Future<void> _loadPermissionConfig() async {
    final result = await _requestService.getPermissionBalance(
      month: _date.month,
      year: _date.year,
    );
    if (!mounted) return;
    final data = result['data'];
    if (result['success'] == true && data is Map) {
      setState(() {
        _configured = data['configured'] != false;
        _enabled = data['enabled'] != false;
        _quotaMinutes = (data['monthlyQuotaMinutes'] as num?)?.toDouble() ?? 0;
        _consumedMinutes = (data['consumedMinutes'] as num?)?.toDouble() ?? 0;
        _pendingMinutes = (data['pendingMinutes'] as num?)?.toDouble() ?? 0;
      });
    }
  }

  Future<void> _loadOffConfig() async {
    final config = await loadHolidayOffConfig();
    if (!mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _offConfig = config;
      // If the current default date is a holiday/week-off, move to the next working day.
      final current = _date.isBefore(today) ? today : _date;
      if (config.isDisabled(current)) {
        _date = config.firstSelectableOnOrAfter(current);
      }
    });
  }

  @override
  void dispose() {
    _minutesController.removeListener(_onMinutesChanged);
    _minutesController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Only today and future dates are selectable; past dates and holidays/week-offs are not.
    final base = _date.isBefore(today) ? today : _date;
    final initial = _offConfig.firstSelectableOnOrAfter(base);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 1, 12, 31),
      selectableDayPredicate: (day) => !_offConfig.isDisabled(day),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
        _showLimitWarning = false;
      });
    }
  }

  /// 24h "HH:mm" wire format expected by the backend.
  String _formatTimeHHmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime({required bool isFrom}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isFrom ? _fromTime : _toTime) ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromTime = picked;
        } else {
          _toTime = picked;
        }
        _syncMinutesFromWindow();
      });
    }
  }

  /// The From/To window is authoritative for 'both': total minutes (To − From)
  /// drive the quota/fine, so auto-fill Requested Minutes from the picked window.
  void _syncMinutesFromWindow() {
    final from = _fromTime;
    final to = _toTime;
    if (from == null || to == null) return;
    final minutes = (to.hour * 60 + to.minute) - (from.hour * 60 + from.minute);
    if (minutes > 0) {
      _minutesController.text = minutes.toString();
    }
  }

  /// Grey tappable card showing a selected time (or a hint) — matches the date card.
  Widget _buildTimeField({
    required TimeOfDay? value,
    required String hint,
    required VoidCallback onTap,
  }) {
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
            Icon(Icons.schedule, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              value != null ? value.format(context) : hint,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: value != null
                    ? AppColors.textPrimary
                    : AppColors.textCaption,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionLimitBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade400),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permission Quota Exceeded',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your admin has been notified. Request is still submitted.',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The minutes that would actually be fined for the current input, plus a
  /// human label for why. Returns (0, '') when no fine applies.
  ({int minutes, String basis}) _finedMinutesForInput() {
    final requested = int.tryParse(_minutesController.text.trim()) ?? 0;
    if (requested <= 0) return (minutes: 0, basis: '');

    // Any non-normal scenario — entire request is fine: S2 (enabled, no quota),
    // S3 (disabled, has quota), S4 (disabled, no quota).
    if (!(_enabled && _quotaMinutes > 0)) {
      return (
        minutes: requested,
        basis: (!_enabled && _quotaMinutes > 0)
            ? 'disabled — all as fine'
            : 'not configured — all as fine',
      );
    }

    final effectiveRemaining =
        (_quotaMinutes - _consumedMinutes - _pendingMinutes).clamp(
          0.0,
          _quotaMinutes,
        );
    if (_quotaMinutes > 0 && requested > effectiveRemaining) {
      final excess = requested - effectiveRemaining.toInt();
      return (minutes: excess, basis: '$excess min over your monthly quota');
    }
    return (minutes: 0, basis: '');
  }

  /// Formats a minute count as "Xh Ym", omitting zero parts (e.g. 90 -> "1h 30m").
  String _formatMinutesAsHm(int minutes) {
    final m = minutes < 0 ? 0 : minutes;
    final h = m ~/ 60;
    final rem = m % 60;
    if (h > 0 && rem > 0) return '${h}h ${rem}m';
    if (h > 0) return '${h}h';
    return '${rem}m';
  }

  /// Tooltip message describing how the requested duration will be split
  /// between permission and fine, based on the remaining monthly quota.
  /// - Partial overflow (some quota left): "[allowed] will be considered as
  ///   permission and the remaining [excess] will be applied as a fine."
  /// - Quota already exhausted: the full requested duration is counted as fine.
  String? _permissionFineSplitMessage() {
    final requested = int.tryParse(_minutesController.text.trim()) ?? 0;
    if (requested <= 0) return null;

    // Disabled with quota > 0 — all as fine (Scenario 3).
    if (!_enabled && _quotaMinutes > 0) {
      return 'Permission is disabled for your shift. Contact HR to enable.\n'
          'The requested duration (${_formatMinutesAsHm(requested)}) will be processed as Fine.';
    }

    // Enabled but no quota configured — entire amount is fine (Scenario 2).
    if (_quotaMinutes <= 0) {
      return 'Permission is not configured for your shift. Contact HR.\n'
          'The requested duration (${_formatMinutesAsHm(requested)}) will be processed as Fine.';
    }

    final effectiveRemaining =
        (_quotaMinutes - _consumedMinutes - _pendingMinutes)
            .clamp(0.0, _quotaMinutes)
            .toInt();

    if (effectiveRemaining <= 0) {
      return 'Your available permission limit has been exceeded. '
          'The full requested duration (${_formatMinutesAsHm(requested)}) will be counted as a fine.';
    }

    if (requested > effectiveRemaining) {
      final finePart = requested - effectiveRemaining;
      return '${_formatMinutesAsHm(effectiveRemaining)} will be considered as permission and '
          'the remaining ${_formatMinutesAsHm(finePart)} will be applied as a fine.';
    }

    return null;
  }

  /// Info tooltip showing the permission/fine split for the current input.
  /// Hidden when the request fits fully within the remaining quota.
  Widget _buildPermissionFineSplitNotice() {
    final msg = _permissionFineSplitMessage();
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Orange info banner showing the estimated fine for the current input. Hidden
  /// when no fine applies or the per-day salary is not yet known.
  Widget _buildFineEstimate() {
    final fined = _finedMinutesForInput();
    if (fined.minutes <= 0) return const SizedBox.shrink();
    if (_netPerDaySalary == null || _netPerDaySalary! <= 0) {
      return const SizedBox.shrink();
    }
    final fine = _estimateFine(fined.minutes);
    if (fine <= 0) return const SizedBox.shrink();

    final formatted = NumberFormat('#,##0.00').format(fine);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                  children: [
                    const TextSpan(text: 'Estimated fine: '),
                    TextSpan(
                      text: '₹$formatted',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: '  (${fined.basis}).'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_configured) {
      SnackBarUtils.showSnackBar(
        context,
        'Permission is not configured for your shift. Contact HR.',
        isError: true,
      );
      return;
    }
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
    // 'both' captures a planned out/in window; require both ends.
    if (_type == 'both' && (_fromTime == null || _toTime == null)) {
      SnackBarUtils.showSnackBar(
        context,
        'Select both From and To time',
        isError: true,
      );
      return;
    }

    // A permission must be requested before its time period begins; reject a
    // same-day request whose window has already started (e.g. already arrived late).
    final periodError = _periodAlreadyStartedError(minutes);
    if (periodError != null) {
      SnackBarUtils.showSnackBar(context, periodError, isError: true);
      return;
    }

    // Disabled with quota > 0 → entire amount is fine (warn then allow, Scenario 3).
    if (!_enabled && _quotaMinutes > 0) {
      final fineText = () {
        final f = _estimateFine(minutes);
        return f > 0
            ? ' Estimated fine: ₹${NumberFormat('#,##0.00').format(f)}.'
            : '';
      }();
      final msg =
          'Permission is disabled for your shift. Contact HR to enable.\n'
          'The requested duration (${_formatMinutesAsHm(minutes)}) '
          'will be processed as Fine.$fineText';
      if (!_showLimitWarning) {
        setState(() {
          _showLimitWarning = true;
          _limitWarningMsg = msg;
        });
        return;
      }
      // User acknowledged the banner — fall through to submit.
    }

    // No quota configured → entire amount is fine (warn then allow). Covers S2
    // (enabled, no quota) and S4 (disabled, no quota); S3 (disabled + quota) is
    // handled by the disabled branch above.
    if (_quotaMinutes <= 0) {
      final fineText = () {
        final f = _estimateFine(minutes);
        return f > 0
            ? ' Estimated fine: ₹${NumberFormat('#,##0.00').format(f)}.'
            : '';
      }();
      final msg =
          'Permission is not configured for your shift. Contact HR.\n'
          'The requested duration (${_formatMinutesAsHm(minutes)}) '
          'will be processed as Fine.$fineText';
      if (!_showLimitWarning) {
        setState(() {
          _showLimitWarning = true;
          _limitWarningMsg = msg;
        });
        return;
      }
      // User acknowledged the banner — fall through to submit.
    }

    // Effective remaining = quota - consumed - pending (pending minutes may still be deducted).
    final effectiveRemaining =
        (_quotaMinutes - _consumedMinutes - _pendingMinutes).clamp(
          0.0,
          _quotaMinutes,
        );
    if (_quotaMinutes > 0 && minutes > effectiveRemaining) {
      final remainingInt = effectiveRemaining.toInt();
      final excess = minutes - remainingInt;
      final estimatedFine = _estimateFine(excess);
      final fineText = estimatedFine > 0
          ? ' Estimated fine: ₹${NumberFormat('#,##0.00').format(estimatedFine)}.'
          : '';
      final msg = remainingInt <= 0
          ? 'Your available permission limit has been exceeded. '
                'The full requested duration (${_formatMinutesAsHm(minutes)}) '
                'will be counted as a fine.$fineText'
          : '${_formatMinutesAsHm(remainingInt)} will be considered as '
                'permission and the remaining ${_formatMinutesAsHm(excess)} '
                'will be applied as a fine.$fineText';
      setState(() {
        _showLimitWarning = true;
        _limitWarningMsg = msg;
      });
      unawaited(
        FcmService.showLimitExceededLocalNotification(
          type: 'permission',
          message: msg,
        ),
      );
      unawaited(
        _requestService.notifyAdminLimitExceeded(
          type: 'permission',
          requested: minutes,
          limit: effectiveRemaining,
        ),
      );
      // Do not return — permission over-quota is submittable.
    }

    setState(() => _isSubmitting = true);
    final result = await _requestService.createPermissionRequest(
      date: _date,
      type: _type,
      requestedMinutes: minutes,
      reason: reason,
      fromTime: _type == 'both' && _fromTime != null
          ? _formatTimeHHmm(_fromTime!)
          : null,
      toTime: _type == 'both' && _toTime != null
          ? _formatTimeHHmm(_toTime!)
          : null,
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
      // Surface the exact policy notice when the permission time will be fined
      // (disabled / no-allowance shift). Request was still accepted — informational.
      final notice = result['notice'];
      if (notice is String && notice.trim().isNotEmpty) {
        SnackBarUtils.showSnackBar(context, notice);
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                        DropdownMenuItem(
                          value: 'lateArrival',
                          child: Text('Late Arrival'),
                        ),
                        DropdownMenuItem(
                          value: 'earlyExit',
                          child: Text('Early Exit'),
                        ),
                        DropdownMenuItem(value: 'both', child: Text('Custom')),
                      ],
                      onChanged: (v) =>
                          setState(() => _type = v ?? 'lateArrival'),
                    ),
                    const SizedBox(height: 20),

                    // Out/In window — only for the 'both' (custom-time) type.
                    if (_type == 'both') ...[
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionLabel('From Time'),
                                _buildTimeField(
                                  value: _fromTime,
                                  hint: 'Out',
                                  onTap: () => _pickTime(isFrom: true),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionLabel('To Time'),
                                _buildTimeField(
                                  value: _toTime,
                                  hint: 'In',
                                  onTap: () => _pickTime(isFrom: false),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Requested Minutes. For 'both' this is derived from the
                    // From/To window and shown read-only.
                    _sectionLabel(
                      _type == 'both'
                          ? 'Requested Minutes (from window)'
                          : 'Requested Minutes',
                    ),
                    TextFormField(
                      controller: _minutesController,
                      keyboardType: TextInputType.number,
                      readOnly: _type == 'both',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      decoration: _fieldDecoration(
                        hint: _type == 'both'
                            ? 'Auto from From/To'
                            : 'Enter minutes',
                      ),
                      validator: (value) {
                        final mins = int.tryParse((value ?? '').trim());
                        if (mins == null || mins <= 0) {
                          return _type == 'both'
                              ? 'Pick a valid From/To window'
                              : 'Enter valid minutes';
                        }
                        return null;
                      },
                    ),

                    // Permission/fine split tooltip for the current input.
                    _buildPermissionFineSplitNotice(),

                    // Live fine estimate (DB fine settings × this user's salary).
                    _buildFineEstimate(),
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

                    if (_showLimitWarning)
                      _buildPermissionLimitBanner(_limitWarningMsg),
                    if (_showLimitWarning) const SizedBox(height: 12),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            (_isSubmitting || !_configured)
                            ? null
                            : _submit,
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
  Widget _buildDateField({
    required DateTime date,
    required VoidCallback onTap,
  }) {
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
              'Downloading file... Check your browser downloads.',
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
            'Downloading file... Check your browser downloads.',
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

                // List Body — loader / empty / items scroll with the header.
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: const Center(child: AppTabLoader()),
                  )
                else if (_requests.isEmpty)
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
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        for (int i = 0; i < _requests.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: FadeSlideIn(
                              delay: Duration(
                                milliseconds: (i * 45).clamp(0, 270),
                              ),
                              child: _buildPayslipCard(_requests[i]),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Pagination Controls — only when there's more than one page, so a
        // single-page result doesn't show a stray lone "1" strip (pinned footer).
        if (!_isLoading && _requests.isNotEmpty && _totalPages > 1)
          _PaginationBar(
            currentPage: _currentPage,
            totalPages: _totalPages,
            onPageSelected: (page) {
              setState(() => _currentPage = page);
              _fetchRequests();
            },
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
