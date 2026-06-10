// hrms/lib/screens/salary/request_payslip_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/request_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/request_success_dialog.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/profile_app_bar_actions.dart';
import 'all_payslips_screen.dart';

/// Figma "Request Payslip": pick a fiscal year and a completed month, then
/// generate a payslip request. Below the picker is a list of recently
/// requested / generated payslips with quick download.
///
/// Reuses the existing payslip request logic ([RequestService.requestPayslip],
/// allowed-period rules derived from the joining date, duplicate guarding and
/// [RequestService.getPayslipRequests]) — only the presentation is new.
class RequestPayslipScreen extends StatefulWidget {
  const RequestPayslipScreen({super.key});

  @override
  State<RequestPayslipScreen> createState() => _RequestPayslipScreenState();
}

class _RequestPayslipScreenState extends State<RequestPayslipScreen> {
  final RequestService _requestService = RequestService();
  final AuthService _authService = AuthService();

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  DateTime? _joiningDate;
  int _selectedYear = DateTime.now().year;
  String? _selectedMonth; // full month name
  List<dynamic> _existingRequests = [];
  List<dynamic> _recent = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

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

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _authService.getProfile(),
      _requestService.getPayslipRequests(limit: 20),
    ]);

    DateTime? joining;
    final profileResult = results[0];
    if (profileResult['success'] == true && profileResult['data'] is Map) {
      final data = profileResult['data'] as Map<String, dynamic>;
      final staffData = data['staffData'];
      if (staffData is Map && staffData['joiningDate'] != null) {
        joining = _parseJoiningDate(staffData['joiningDate']);
      }
      joining ??= _parseJoiningDate(data['joiningDate']);
    }

    final List<dynamic> existing = _extractRequests(results[1]);

    if (!mounted) return;
    setState(() {
      _joiningDate = joining;
      _existingRequests = existing;
      _recent = existing;
      _clampSelection();
      _loading = false;
    });
  }

  List<dynamic> _extractRequests(Map<String, dynamic> result) {
    if (result['success'] != true || result['data'] == null) return const [];
    final data = result['data'];
    if (data is Map) return (data['requests'] as List?) ?? const [];
    if (data is List) return data;
    return const [];
  }

  Future<void> _refresh() async {
    final result = await _requestService.getPayslipRequests(limit: 20);
    if (!mounted) return;
    setState(() {
      _existingRequests = _extractRequests(result);
      _recent = _existingRequests;
    });
  }

  // ── Allowed period rules (joining date → now) ────────────────────────────────

  int get _currentYear => DateTime.now().year;
  int get _currentMonth => DateTime.now().month;
  int get _joiningYear => _joiningDate?.year ?? _currentYear;
  int get _joiningMonth => _joiningDate?.month ?? 1;

  /// Years from joining year up to the current year, most-recent first.
  List<int> get _allowedYears {
    final start = _joiningYear;
    final end = _currentYear;
    if (start > end) return [end];
    return [for (int y = end; y >= start; y--) y];
  }

  /// Completed months for [_selectedYear], most-recent first (current month is
  /// excluded — its payslip is not generated yet).
  List<String> get _allowedMonthsDesc {
    int first = 1;
    int last = 12;
    if (_selectedYear == _joiningYear) first = _joiningMonth;
    if (_selectedYear == _currentYear) last = _currentMonth - 1;
    if (first > last) return const [];
    return [for (int m = last; m >= first; m--) _months[m - 1]];
  }

  void _clampSelection() {
    final years = _allowedYears;
    if (years.isNotEmpty && !years.contains(_selectedYear)) {
      _selectedYear = years.first;
    }
    final months = _allowedMonthsDesc;
    if (months.isEmpty) {
      _selectedMonth = null;
    } else if (_selectedMonth == null || !months.contains(_selectedMonth)) {
      _selectedMonth = months.first;
    }
  }

  bool _isDuplicate(String month, int year) {
    final monthNumber = _months.indexOf(month) + 1;
    return _existingRequests.any((req) {
      final reqMonth = req['month'];
      final reqMonthNumber = reqMonth is int
          ? reqMonth
          : (reqMonth is String ? _months.indexOf(reqMonth) + 1 : 0);
      return reqMonthNumber == monthNumber && req['year'] == year;
    });
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _onRequestPressed() async {
    final month = _selectedMonth;
    if (month == null) {
      SnackBarUtils.showSnackBar(context, 'Please select a month',
          isError: true);
      return;
    }
    if (_isDuplicate(month, _selectedYear)) {
      SnackBarUtils.showSnackBar(
        context,
        'A payslip request for $month $_selectedYear already exists',
        isError: true,
      );
      return;
    }
    final reason = await _askReason(month, _selectedYear);
    if (reason == null) return; // cancelled

    setState(() => _submitting = true);
    final result = await _requestService.requestPayslip({
      'month': _months.indexOf(month) + 1,
      'year': _selectedYear,
      'reason': reason.trim().isEmpty
          ? 'Payslip request for $month $_selectedYear'
          : reason.trim(),
    });
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result['success'] == true) {
      await _refresh();
      if (!mounted) return;
      final overlay = Navigator.of(context, rootNavigator: true).overlay;
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

  /// Lightweight confirmation sheet collecting an optional reason. Returns the
  /// reason string on confirm, or `null` if the user cancels.
  Future<String?> _askReason(String month, int year) {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request payslip',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Generate the payslip for $month $year.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Reason (optional)',
                filled: true,
                fillColor: AppColors.inputFill,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Confirm',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPayslip(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      SnackBarUtils.showSnackBar(context, 'Unable to open payslip',
          isError: true);
    }
  }

  void _openAllRequests() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AllPayslipsScreen()),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Request Payslip',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: const [ProfileAppBarActions()],
      ),
      body: _loading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  // Text(
                  //   'Request Payslip',
                  //   style: TextStyle(
                  //     fontSize: 20,
                  //     fontWeight: FontWeight.bold,
                  //     color: AppColors.textPrimary,
                  //   ),
                  // ),
                  // const SizedBox(height: 4),
                  Text(
                    'Select the period to generate your financial document.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildYearCard(),
                  const SizedBox(height: 16),
                  _buildMonthCard(),
                  const SizedBox(height: 24),
                  _buildRecentHeader(),
                  const SizedBox(height: 12),
                  ..._buildRecentList(),
                ],
              ),
            ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _cardHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildYearCard() {
    final years = _allowedYears;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.calendar_today_outlined, 'Year'),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: years.contains(_selectedYear)
                    ? _selectedYear
                    : (years.isNotEmpty ? years.first : _selectedYear),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                borderRadius: BorderRadius.circular(12),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                items: years
                    .map((y) =>
                        DropdownMenuItem(value: y, child: Text('$y')))
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedYear = val;
                    _selectedMonth = null;
                    _clampSelection();
                  });
                },
              ),
            ),
          ),
//const SizedBox(height: 16),
          // Container(
          //   width: double.infinity,
          //   padding: const EdgeInsets.all(14),
          //   decoration: BoxDecoration(
          //     color: AppColors.primary.withValues(alpha: 0.08),
          //     borderRadius: BorderRadius.circular(12),
          //   ),
          //   child: Text(
          //     'Fiscal year tracking is active. All records are verified by HR.',
          //     style: TextStyle(
          //       fontSize: 13,
          //       height: 1.45,
          //       fontWeight: FontWeight.w500,
          //       color: AppColors.primaryDark,
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildMonthCard() {
    final months = _allowedMonthsDesc;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.calendar_month_outlined, 'Select Month'),
          const SizedBox(height: 18),
          if (months.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No completed months are available to request for $_selectedYear yet.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final itemWidth = (constraints.maxWidth - spacing * 3) / 4;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: months
                      .map((m) => _monthChip(m, itemWidth))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _onRequestPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.description_outlined, size: 20),
                label: Text(
                  _submitting ? 'Submitting...' : 'Request Payslip',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _monthChip(String month, double width) {
    final selected = month == _selectedMonth;
    return GestureDetector(
      onTap: () => setState(() => _selectedMonth = month),
      child: Container(
        width: width,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          month.substring(0, 3),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildRecentHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Recent Payslips',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        GestureDetector(
          onTap: _openAllRequests,
          child: Text(
            'VIEW ALL',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRecentList() {
    if (_recent.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'No payslip requests yet.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ),
      ];
    }
    final items = _recent.take(5).toList();
    return [
      for (final req in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PayslipRequestCard(req: req, onDownload: _onRecentDownload),
        ),
    ];
  }

  void _onRecentDownload(String? url) {
    if (url != null) {
      _openPayslip(url);
    } else {
      SnackBarUtils.showSnackBar(context, 'Payslip is not generated yet');
    }
  }
}
