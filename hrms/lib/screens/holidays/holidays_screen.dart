import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/holiday_model.dart';
import '../../services/holiday_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import '../../widgets/app_tab_loader.dart';

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
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late TabController _tabController;
  String _searchQuery = '';
  Timer? _debounce;

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
    _selectedDay = _focusedDay;
    _fetchHolidays();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounce?.cancel();
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

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchQuery != query) {
        setState(() {
          _searchQuery = query;
        });
        _fetchHolidays();
      }
    });
  }

  void _onYearChanged(int? year) {
    if (year != null && _selectedYear != year) {
      setState(() {
        _selectedYear = year;
        _focusedDay = DateTime(year, _focusedDay.month, 1);
      });
      _fetchHolidays();
    }
  }

  bool _canShiftCalendarMonth(int deltaMonths) {
    final next = DateTime(
      _focusedDay.year,
      _focusedDay.month + deltaMonths,
      1,
    );
    final minBound = DateTime(_years.first, 1, 1);
    final maxBound = DateTime(_years.last, 12, 1);
    return !next.isBefore(minBound) && !next.isAfter(maxBound);
  }

  void _goToCalendarMonth(DateTime monthStart) {
    final y = monthStart.year;
    final m = monthStart.month;
    if (y != _selectedYear) {
      setState(() {
        _selectedYear = y;
        _focusedDay = DateTime(y, m, 1);
        _selectedDay = _focusedDay;
      });
      _fetchHolidays();
    } else {
      setState(() {
        _focusedDay = DateTime(y, m, 1);
        _selectedDay = _focusedDay;
      });
    }
  }

  void _shiftCalendarMonth(int deltaMonths) {
    if (!_canShiftCalendarMonth(deltaMonths)) return;
    final next = DateTime(
      _focusedDay.year,
      _focusedDay.month + deltaMonths,
      1,
    );
    _goToCalendarMonth(next);
  }

  Future<void> _showMonthPickerSheet(BuildContext context) async {
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
                color: Colors.black.withOpacity(0.12),
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
                      'Select month · $_selectedYear',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                ...List.generate(12, (index) {
                  final m = index + 1;
                  final selected = m == _focusedDay.month &&
                      _selectedYear == _focusedDay.year;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: Material(
                      color: selected
                          ? AppColors.primary.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(ctx, m),
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
                                DateFormat('MMMM')
                                    .format(DateTime(_selectedYear, m)),
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
    if (picked != null) {
      _goToCalendarMonth(DateTime(_selectedYear, picked, 1));
    }
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
                color: Colors.black.withOpacity(0.12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Material(
                      color: selected
                          ? AppColors.primary.withOpacity(0.12)
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

  Widget _buildYearSelectorPill(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withOpacity(0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showYearPickerSheet(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '$_selectedYear',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSelectorPill(BuildContext context) {
    final label = DateFormat('MMMM').format(_focusedDay);
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withOpacity(0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showMonthPickerSheet(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthWiseFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.divider.withOpacity(0.6)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _canShiftCalendarMonth(-1)
                ? () => _shiftCalendarMonth(-1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.primary,
              disabledForegroundColor:
                  AppColors.textSecondary.withOpacity(0.35),
            ),
          ),
          Expanded(
            flex: 5,
            child: _buildMonthSelectorPill(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: _buildYearSelectorPill(context),
          ),
          IconButton(
            onPressed: _canShiftCalendarMonth(1)
                ? () => _shiftCalendarMonth(1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 28),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.primary,
              disabledForegroundColor:
                  AppColors.textSecondary.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  List<Holiday> _getHolidaysForMonth(int month) {
    return _holidays
        .where((h) => h.date.year == _selectedYear && h.date.month == month)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text(
          'Holidays',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.black,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          indicator: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          tabs: const [
            Tab(text: 'Year wise'),
            Tab(text: 'Month wise'),
          ],
        ),
      ),
      drawer: AppDrawer(
        currentIndex: widget.dashboardTabIndex ?? 3,
        onNavigateToIndex: widget.onNavigateToIndex,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildYearWiseTab(), _buildMonthWiseTab()],
      ),
    );
  }

  Widget _buildYearWiseTab() {
    return Column(
      children: [
        _buildFilterHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchHolidays,
            child: _isLoading
                ? const Center(
                    child: AppTabLoader(),
                  )
                : _errorMessage != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: _buildErrorWidget(),
                      ),
                    ],
                  )
                : _holidays.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: _buildEmptyWidget(),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _holidays.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final holiday = _holidays[index];
                      return _buildHolidayCard(holiday);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: AppColors.surface,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search holidays...',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _buildYearSelectorPill(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthWiseTab() {
    final holidaysInMonth = _getHolidaysForMonth(_focusedDay.month);

    return Column(
      children: [
        _buildMonthWiseFilterBar(context),

        // Calendar (header hidden — month/year live in filter bar above)
        TableCalendar(
          firstDay: DateTime(_years.first, 1, 1),
          lastDay: DateTime(_years.last, 12, 31),
          focusedDay: _focusedDay,
          headerVisible: false,
          onPageChanged: (focusedDay) {
            final yChanged = focusedDay.year != _selectedYear;
            setState(() {
              _focusedDay = focusedDay;
              if (yChanged) _selectedYear = focusedDay.year;
            });
            if (yChanged) _fetchHolidays();
          },
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            markerDecoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          eventLoader: (day) {
            return _holidays.where((h) => isSameDay(h.date, day)).toList();
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isNotEmpty) {
                return Positioned(
                  bottom: 1,
                  right: 1,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: const Text(
                      'h',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return null;
            },
          ),
        ),

        const Divider(),

        // Holidays in selected month
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchHolidays,
            child: _isLoading
                ? const Center(
                    child: AppTabLoader(),
                  )
                : holidaysInMonth.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Text(
                            'No holidays in ${DateFormat('MMMM').format(_focusedDay)}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: holidaysInMonth.length,
                    itemBuilder: (context, index) {
                      final holiday = holidaysInMonth[index];
                      return _buildHolidayRow(holiday);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildHolidayRow(Holiday holiday) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('dd').format(holiday.date),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    fontSize: 18,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(holiday.date),
                  style: TextStyle(color: AppColors.primary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holiday.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  holiday.dayName,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          _buildTypeBadge(holiday.type),
        ],
      ),
    );
  }

  Widget _buildHolidayCard(Holiday holiday) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        holiday.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        holiday.formattedDate,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(holiday),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      holiday.dayName,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                _buildTypeBadge(holiday.type),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(Holiday holiday) {
    final isPast = holiday.isPast;
    final color = isPast ? AppColors.textSecondary : AppColors.success;
    final bgColor = isPast
        ? AppColors.background
        : AppColors.success.withOpacity(0.1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        isPast ? 'Past' : 'Upcoming',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    Color bgColor;
    Color textColor;

    switch (type.toLowerCase()) {
      case 'national':
        bgColor = AppColors.primary.withOpacity(0.1);
        textColor = AppColors.primary;
        break;
      case 'regional':
        bgColor = AppColors.accent.withOpacity(0.1);
        textColor = AppColors.accent;
        break;
      default:
        bgColor = Colors.purple.withOpacity(0.1);
        textColor = Colors.purple;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
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
