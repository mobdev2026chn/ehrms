// hrms/lib/screens/overtime/overtime_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../services/request_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_drawer.dart';

class OvertimeScreen extends StatefulWidget {
  const OvertimeScreen({super.key});

  @override
  State<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends State<OvertimeScreen> {
  final RequestService _requestService = RequestService();

  DateTime _selectedMonth = DateTime.now();
  String _selectedStatus = 'All';
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _requests = [];
  double _totalOtHoursWorked = 0.0;
  int _totalOtRequestsReceived = 0;

  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Accepted',
    'Rejected',
    'Expired',
  ];

  @override
  void initState() {
    super.initState();
    _fetchOvertimeData();
  }

  Future<void> _fetchOvertimeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final monthStr = DateFormat('yyyy-MM').format(_selectedMonth);
    final res = await _requestService.getMyOvertimeRequests(
      month: monthStr,
      status: _selectedStatus == 'All' ? null : _selectedStatus,
    );

    if (!mounted) return;

    if (res['success'] == true && res['data'] != null) {
      final data = res['data'];
      final rawList = data['requests'] ?? [];
      final summary = data['summary'] ?? {};

      setState(() {
        _isLoading = false;
        _requests = rawList is List
            ? rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        _totalOtHoursWorked =
            (summary['totalOtHoursWorked'] as num?)?.toDouble() ?? 0.0;
        _totalOtRequestsReceived =
            (summary['totalOtRequestsReceived'] as num?)?.toInt() ??
                _requests.length;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = ErrorMessageUtils.sanitizeForDisplay(
          res['message'],
          fallback: 'Failed to load overtime records.',
        );
      });
    }
  }

  Future<void> _respondToRequest(String id, String action) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final res = await _requestService.respondToOvertime(
      id: id,
      action: action,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Overtime request $action successfully!'),
          backgroundColor: action == 'Accepted' ? AppColors.success : AppColors.error,
        ),
      );
      _fetchOvertimeData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Failed to update overtime request.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month - 1,
      );
    });
    _fetchOvertimeData();
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
      );
    });
    _fetchOvertimeData();
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return AppColors.successBg;
      case 'pending':
        return AppColors.warningBg;
      case 'rejected':
        return AppColors.errorBg;
      case 'expired':
        return AppColors.inputFill;
      default:
        return AppColors.inputFill;
    }
  }

  Color _getStatusTextColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return AppColors.success;
      case 'pending':
        return AppColors.brandDark;
      case 'rejected':
        return AppColors.error;
      case 'expired':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  static const Color _hairline = Color(0xFFECEEF1);

  Widget _buildStatCard({
    required String label,
    required String value,
    required String caption,
    required IconData icon,
    required Color color,
    required Color tint,
  }) {
    return AppCard(
      border: Border.all(color: _hairline),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.sectionLabel
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.displayLarge.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('My Overtime'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchOvertimeData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchOvertimeData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Month Picker Bar
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              border: Border.all(color: _hairline),
              boxShadow: const [],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: AppColors.textPrimary,
                    tooltip: 'Previous month',
                    onPressed: _prevMonth,
                    splashRadius: 20,
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                        color: AppColors.primaryText,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        monthLabel,
                        style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: AppColors.textPrimary,
                    tooltip: 'Next month',
                    onPressed: _nextMonth,
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Top Stat Cards
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    label: 'TOTAL OT HOURS',
                    value: '${_totalOtHoursWorked.toStringAsFixed(1)}h',
                    caption: 'Worked this cycle',
                    icon: Icons.access_time_rounded,
                    color: AppColors.brand,
                    tint: AppColors.brandLight,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    label: 'OT REQUESTS',
                    value: '$_totalOtRequestsReceived',
                    caption: 'Assigned schedules',
                    icon: Icons.schedule_send_outlined,
                    color: AppColors.info,
                    tint: AppColors.infoBg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Status Filter Chips
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _statusFilters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final status = _statusFilters[index];
                  final isSelected = _selectedStatus == status;
                  return ChoiceChip(
                    label: Text(status),
                    selected: isSelected,
                    showCheckmark: false,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedStatus = status);
                        _fetchOvertimeData();
                      }
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.onPrimary
                          : AppColors.textSecondary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : _hairline,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // List Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'OVERTIME SCHEDULES',
                  style: AppTextStyles.sectionLabel
                      .copyWith(color: AppColors.textSecondary),
                ),
                Text(
                  '${_requests.length} Showing',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Content List
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage != null)
              AppCard(
                padding: const EdgeInsets.all(24),
                border: Border.all(color: _hairline),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.errorBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        size: 30,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchOvertimeData,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              )
            else if (_requests.isEmpty)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                border: Border.all(color: _hairline),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.brandLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.more_time_rounded,
                        size: 30,
                        color: AppColors.brand,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No Overtime Schedules',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headingSmall,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'No overtime assigned for this selection.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _requests[index];
                  final id = (item['_id'] ?? item['id'] ?? '').toString();
                  final date = (item['date'] ?? item['startDate'] ?? '').toString();
                  final requestedBy = (item['requestedBy'] ?? 'Admin').toString();
                  final notes = (item['notes'] ?? '').toString();
                  final status = (item['status'] ?? 'Pending').toString();
                  final isPending = status.toLowerCase() == 'pending';

                  String formattedDate = date;
                  try {
                    final d = DateTime.parse(date).toLocal();
                    formattedDate = DateFormat('yyyy-MM-dd (EEE)').format(d);
                  } catch (_) {}

                  return AppCard(
                    border: Border.all(color: _hairline),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.brandLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: AppColors.brand,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                formattedDate,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.headingSmall
                                    .copyWith(fontSize: 15),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusBgColor(status),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _getStatusTextColor(status),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.person_outline_rounded,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Requested by: $requestedBy',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.notes_rounded,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notes,
                                  style: AppTextStyles.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (isPending && id.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _respondToRequest(id, 'Rejected'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                                    minimumSize: const Size(0, 44),
                                  ),
                                  child: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _respondToRequest(id, 'Accepted'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 44),
                                  ),
                                  child: const Text('Accept'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
