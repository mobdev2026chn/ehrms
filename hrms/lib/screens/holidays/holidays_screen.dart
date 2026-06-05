import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/holiday_model.dart';
import '../../services/holiday_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import '../../widgets/app_tab_loader.dart';
import '../notifications/notifications_screen.dart';

class HolidaysScreen extends StatefulWidget {
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  const HolidaysScreen({
    super.key,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
  });

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen>
    with SingleTickerProviderStateMixin {
  final HolidayService _holidayService = HolidayService();
  List<Holiday> _holidays = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedYear = DateTime.now().year;
  late TabController _tabController;
  final String _searchQuery = '';

  final List<int> _years = [
    DateTime.now().year - 1,
    DateTime.now().year,
    DateTime.now().year + 1,
    DateTime.now().year + 2,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchHolidays();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchHolidays() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _holidayService.getHolidays(
      year: _selectedYear,
      search: _searchQuery,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result['success']) {
          _holidays = result['data'];
          _holidays.sort((a, b) => a.date.compareTo(b.date));
        } else {
          _errorMessage = ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to load holidays',
          );
        }
      });
    }
  }

  void _onYearChanged(int? year) {
    if (year != null && _selectedYear != year) {
      setState(() {
        _selectedYear = year;
      });
      _fetchHolidays();
    }
  }

  void _goToToday() => _onYearChanged(DateTime.now().year);

  List<Holiday> _getHolidaysForMonth(int month) {
    return _holidays
        .where((h) => h.date.year == _selectedYear && h.date.month == month)
        .toList();
  }

  /// Upcoming (not-yet-passed) holidays in the selected year.
  List<Holiday> get _upcomingHolidays =>
      _holidays.where((h) => !h.isPast).toList();

  /// Next upcoming holiday (falls back to the first holiday of the year).
  Holiday? get _nextHoliday {
    if (_upcomingHolidays.isNotEmpty) return _upcomingHolidays.first;
    if (_holidays.isNotEmpty) return _holidays.first;
    return null;
  }

  Future<void> _showYearPickerSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select year',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                ..._years.map((y) {
                  final selected = y == _selectedYear;
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Material(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(ctx, y),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                size: 22,
                              ),
                              const SizedBox(width: 14),
                              Text(
                                '$y',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) _onYearChanged(picked);
  }

  // ───────────────────────────────────────────────────────────────────────
  // Scaffold
  // ───────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('Holidays',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none_rounded,
                color: AppColors.textPrimary, size: 26),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          Builder(
            builder: (ctx) => Padding(
              padding: const EdgeInsets.only(right: 14, left: 4),
              child: GestureDetector(
                onTap: () => Scaffold.maybeOf(ctx)?.openDrawer(),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Icon(Icons.person_rounded,
                      color: AppColors.primary, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: AppDrawer(
        currentIndex: widget.dashboardTabIndex ?? 3,
        onNavigateToIndex: widget.onNavigateToIndex,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        elevation: 4,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add holiday — coming soon')),
          );
        },
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: Column(
        children: [
          _buildSegmentedToggle(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMonthlyTab(),
                _buildYearlyTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Monthly / Yearly segmented toggle
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildSegmentedToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildSegment('Monthly', 0),
          _buildSegment('Yearly', 1),
        ],
      ),
    );
  }

  Widget _buildSegment(String label, int index) {
    final selected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // MONTHLY TAB
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildMonthlyTab() {
    return RefreshIndicator(
      onRefresh: _fetchHolidays,
      child: _isLoading
          ? const Center(child: AppTabLoader())
          : _errorMessage != null
              ? _scrollableState(_buildErrorWidget())
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _buildYearRow(),
                    const SizedBox(height: 16),
                    _buildBalanceCard(),
                    const SizedBox(height: 24),
                    Text(
                      'Upcoming Holidays',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_holidays.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: _buildEmptyWidget(),
                      )
                    else
                      ..._holidays.map(
                        (h) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildHolidayCard(h),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildYearRow() {
    return Row(
      children: [
        // Year selector "2026 ⌄"
        GestureDetector(
          onTap: () => _showYearPickerSheet(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_selectedYear',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textPrimary, size: 24),
            ],
          ),
        ),
        const Spacer(),
        // TODAY
        GestureDetector(
          onTap: _goToToday,
          child: Text(
            'TODAY',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard() {
    final remaining = _upcomingHolidays.length;
    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Decorative circle
            Positioned(
              right: -30,
              top: -20,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'HOLIDAY BALANCE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$remaining',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Days Remaining',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Figma-style holiday card: date badge left, name middle, type pill, chevron.
  Widget _buildHolidayCard(Holiday holiday) {
    final monthStr = DateFormat('MMM').format(holiday.date).toUpperCase();
    final dayStr = DateFormat('dd').format(holiday.date);
    final isCompany = holiday.type.toLowerCase() == 'company';

    final badgeBg = isCompany ? AppColors.primaryLight : AppColors.inputFill;
    final monthColor =
        isCompany ? AppColors.primary : AppColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Date badge
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    monthStr,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: monthColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    dayStr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Name + type pill
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    holiday.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildTypeBadge(holiday.type),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 24),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // YEARLY TAB
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildYearlyTab() {
    return RefreshIndicator(
      onRefresh: _fetchHolidays,
      child: _isLoading
          ? const Center(child: AppTabLoader())
          : _errorMessage != null
              ? _scrollableState(_buildErrorWidget())
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _buildCalendarViewHeader(),
                    const SizedBox(height: 16),
                    _buildMonthGrid(),
                    const SizedBox(height: 16),
                    _buildLegend(),
                    const SizedBox(height: 16),
                    _buildComingSoonCard(),
                  ],
                ),
    );
  }

  Widget _buildCalendarViewHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CALENDAR VIEW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: AppColors.textCaption,
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _showYearPickerSheet(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_selectedYear',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textPrimary, size: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
        // DAYS SCHEDULED pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                '${_holidays.length}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'DAYS SCHEDULED',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 12,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final month = index + 1;
        final holidays = _getHolidaysForMonth(month);
        final isCurrentMonth = _selectedYear == DateTime.now().year &&
            month == DateTime.now().month;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: isCurrentMonth
                ? Border.all(color: AppColors.primary, width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('MMM').format(DateTime(_selectedYear, month)),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final h in holidays.take(7))
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dotColor(h.type),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _dotColor(String type) {
    switch (type.toLowerCase()) {
      case 'company':
        return AppColors.indigo;
      case 'national':
        return AppColors.primary;
      default:
        return AppColors.textHint;
    }
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _legendItem('National', AppColors.primary),
          _legendItem('Company', AppColors.indigo),
          _legendItem('Weekend', AppColors.textHint),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildComingSoonCard() {
    final next = _nextHoliday;
    if (next == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'COMING SOON',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            next.name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${DateFormat('MMM d, yyyy').format(next.date)} • ${next.dayName}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Shared widgets
  // ───────────────────────────────────────────────────────────────────────
  Widget _scrollableState(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: child,
        ),
      ],
    );
  }

  Widget _buildTypeBadge(String type) {
    Color bgColor;
    Color textColor;

    // Figma: NATIONAL = indigo, COMPANY = amber.
    switch (type.toLowerCase()) {
      case 'company':
        bgColor = AppColors.primaryLight;
        textColor = AppColors.primary;
        break;
      case 'regional':
        bgColor = AppColors.accent.withValues(alpha: 0.12);
        textColor = AppColors.accent;
        break;
      case 'national':
      default:
        bgColor = AppColors.indigoBg;
        textColor = AppColors.indigo;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          TextButton(
            onPressed: _fetchHolidays,
            child: Text(
              'Try Again',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No holidays found for $_selectedYear',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
