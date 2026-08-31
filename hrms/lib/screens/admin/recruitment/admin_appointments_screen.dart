// lib/screens/admin/recruitment/admin_appointments_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminInterviewAppointment {
  final String id;
  final String candidateName;
  final String candidateEmail;
  final String position;
  final String interviewerName;
  String interviewDate; // YYYY-MM-DD
  String interviewTime; // HH:MM
  final String mode; // 'Google Meet' | 'Zoom' | 'Phone' | 'In-Person'
  String status; // 'Scheduled' | 'Completed' | 'Rescheduled' | 'Cancelled'
  final String round;
  String? cancelReason;
  String? rescheduleReason;

  AdminInterviewAppointment({
    required this.id,
    required this.candidateName,
    required this.candidateEmail,
    required this.position,
    required this.interviewerName,
    required this.interviewDate,
    required this.interviewTime,
    required this.mode,
    required this.status,
    required this.round,
    this.cancelReason,
    this.rescheduleReason,
  });

  factory AdminInterviewAppointment.fromJson(Map<String, dynamic> json) {
    return AdminInterviewAppointment(
      id: (json['id'] ?? json['_id'] ?? 'INT-001').toString(),
      candidateName: (json['candidateName'] ?? json['name'] ?? 'Candidate').toString(),
      candidateEmail: (json['candidateEmail'] ?? json['email'] ?? '').toString(),
      position: (json['position'] ?? json['jobTitle'] ?? 'Software Engineer').toString(),
      interviewerName: (json['interviewerName'] ?? json['interviewer'] ?? 'Interviewer').toString(),
      interviewDate: (json['interviewDate'] ?? json['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now())).toString(),
      interviewTime: (json['interviewTime'] ?? json['time'] ?? '11:00').toString(),
      mode: (json['mode'] ?? 'Zoom').toString(),
      status: (json['status'] ?? 'Scheduled').toString(),
      round: (json['round'] ?? 'Technical Round').toString(),
      cancelReason: json['cancelReason']?.toString(),
      rescheduleReason: json['rescheduleReason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'candidateName': candidateName,
        'candidateEmail': candidateEmail,
        'position': position,
        'interviewerName': interviewerName,
        'interviewDate': interviewDate,
        'interviewTime': interviewTime,
        'mode': mode,
        'status': status,
        'round': round,
        'cancelReason': cancelReason,
        'rescheduleReason': rescheduleReason,
      };
}

class AdminAppointmentsScreen extends StatefulWidget {
  const AdminAppointmentsScreen({super.key});

  @override
  State<AdminAppointmentsScreen> createState() => _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState extends State<AdminAppointmentsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _viewMode = 'List'; // 'List' | 'Calendar'
  String _statusFilter = 'All Statuses'; // 'All Statuses' | 'Scheduled' | 'Completed' | 'Rescheduled' | 'Cancelled'
  String _searchQuery = '';

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  List<AdminInterviewAppointment> _appointments = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchAppointments();
  }

  Future<void> _fetchAppointments({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _api.request('/admin/recruitment/appointments');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['appointments'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _appointments = list.map((e) => AdminInterviewAppointment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        } else {
          _setMockAppointments();
        }
      } else {
        _setMockAppointments();
      }
    } catch (_) {
      _setMockAppointments();
    }

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  void _setMockAppointments() {
    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd');

    _appointments = [
      AdminInterviewAppointment(
        id: 'INT-001',
        candidateName: 'Amit Sharma',
        candidateEmail: 'amit.sharma@example.com',
        position: 'Senior Full-Stack Engineer',
        interviewerName: 'Sanjay Patel (Tech Lead)',
        interviewDate: fmt.format(now),
        interviewTime: '10:00',
        mode: 'Google Meet',
        status: 'Scheduled',
        round: 'Technical Round 1',
      ),
      AdminInterviewAppointment(
        id: 'INT-002',
        candidateName: 'Priya Patel',
        candidateEmail: 'priya.patel@example.com',
        position: 'React Developer',
        interviewerName: 'Ananya Rao (Senior Engineer)',
        interviewDate: fmt.format(now),
        interviewTime: '14:30',
        mode: 'Google Meet',
        status: 'Completed',
        round: 'Technical Round 2',
      ),
      AdminInterviewAppointment(
        id: 'INT-003',
        candidateName: 'Rohan Mehta',
        candidateEmail: 'rohan.mehta@example.com',
        position: 'Product Designer',
        interviewerName: 'Vikram Malhotra (UX Director)',
        interviewDate: fmt.format(now.add(const Duration(days: 1))),
        interviewTime: '11:00',
        mode: 'Zoom',
        status: 'Scheduled',
        round: 'Portfolio Review',
      ),
      AdminInterviewAppointment(
        id: 'INT-004',
        candidateName: 'Sneha Reddy',
        candidateEmail: 'sneha.reddy@example.com',
        position: 'DevOps Engineer',
        interviewerName: 'Karan Singh (DevOps Lead)',
        interviewDate: fmt.format(now.add(const Duration(days: 2))),
        interviewTime: '16:00',
        mode: 'Google Meet',
        status: 'Scheduled',
        round: 'Infrastructure Round',
      ),
      AdminInterviewAppointment(
        id: 'INT-005',
        candidateName: 'Kabir Verma',
        candidateEmail: 'kabir.verma@example.com',
        position: 'QA Automation Engineer',
        interviewerName: 'Neha Gupta (QA Manager)',
        interviewDate: fmt.format(now.subtract(const Duration(days: 1))),
        interviewTime: '09:30',
        mode: 'Phone',
        status: 'Completed',
        round: 'Technical Screening',
      ),
    ];
  }

  List<AdminInterviewAppointment> get _filteredAppointments {
    return _appointments.where((apt) {
      final matchesSearch = _searchQuery.isEmpty ||
          apt.candidateName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          apt.position.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          apt.interviewerName.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _statusFilter == 'All Statuses' || apt.status == _statusFilter;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  List<AdminInterviewAppointment> _getAppointmentsForDay(DateTime day) {
    final dayStr = DateFormat('yyyy-MM-dd').format(day);
    return _filteredAppointments.where((apt) => apt.interviewDate == dayStr).toList();
  }

  // ── Action: Reschedule Modal ──
  void _showRescheduleModal(AdminInterviewAppointment apt) {
    DateTime pickedDate = DateTime.tryParse(apt.interviewDate) ?? DateTime.now();
    TimeOfDay pickedTime = TimeOfDay.now();
    try {
      final parts = apt.interviewTime.split(':');
      if (parts.length >= 2) {
        pickedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    } catch (_) {}

    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: Color(0xFFD97706), size: 20),
                  const SizedBox(width: 8),
                  const Text('Reschedule Interview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Candidate: ${apt.candidateName}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          Text('Position: ${apt.position}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                          Text('Current Date/Time: ${apt.interviewDate} at ${apt.interviewTime}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('NEW DATE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: pickedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setDialogState(() => pickedDate = d);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('MM/dd/yyyy').format(pickedDate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text('NEW TIME', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: pickedTime);
                        if (t != null) setDialogState(() => pickedTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(pickedTime.format(context), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text('REASON FOR RESCHEDULING *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'e.g. Interviewer availability, candidate request, etc.',
                        hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEFAA1F))),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (reasonCtrl.text.trim().isEmpty) {
                      SnackBarUtils.showSnackBar(context, 'Please enter reason for rescheduling', isError: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    setState(() {
                      apt.interviewDate = DateFormat('yyyy-MM-dd').format(pickedDate);
                      apt.interviewTime = '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
                      apt.status = 'Rescheduled';
                      apt.rescheduleReason = reasonCtrl.text.trim();
                    });
                    try {
                      await _api.request(
                        '/admin/recruitment/appointments/${apt.id}/reschedule',
                        method: 'POST',
                        data: {
                          'date': apt.interviewDate,
                          'time': apt.interviewTime,
                          'reason': reasonCtrl.text.trim(),
                        },
                      );
                    } catch (_) {}
                    if (mounted) SnackBarUtils.showSnackBar(context, 'Interview rescheduled successfully');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEFAA1F),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Confirm Reschedule', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Action: Cancel Modal ──
  void _showCancelModal(AdminInterviewAppointment apt) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 22),
              const SizedBox(width: 8),
              const Text('Cancel Interview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to cancel the interview for ${apt.candidateName} scheduled on ${apt.interviewDate} at ${apt.interviewTime}?',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 14),
              const Text('REASON FOR CANCELLATION *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'e.g. Candidate requested reschedule, role filled, etc.',
                  hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEF4444))),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('No, Keep it', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonCtrl.text.trim().isEmpty) {
                  SnackBarUtils.showSnackBar(context, 'Please enter cancellation reason', isError: true);
                  return;
                }
                Navigator.pop(ctx);
                setState(() {
                  apt.status = 'Cancelled';
                  apt.cancelReason = reasonCtrl.text.trim();
                });
                try {
                  await _api.request(
                    '/admin/recruitment/appointments/${apt.id}/cancel',
                    method: 'POST',
                    data: {'reason': reasonCtrl.text.trim()},
                  );
                } catch (_) {}
                if (mounted) SnackBarUtils.showSnackBar(context, 'Interview cancelled');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text('Yes, Cancel it', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );
  }

  // ── Action: View Details Modal ──
  void _showDetailsModal(AdminInterviewAppointment apt) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(apt.candidateName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Email', apt.candidateEmail),
              _detailRow('Position', apt.position),
              _detailRow('Round', apt.round),
              _detailRow('Interviewer', apt.interviewerName),
              _detailRow('Date & Time', '${apt.interviewDate} at ${apt.interviewTime}'),
              _detailRow('Mode', apt.mode),
              _detailRow('Status', apt.status),
              if (apt.rescheduleReason != null) _detailRow('Reschedule Reason', apt.rescheduleReason!),
              if (apt.cancelReason != null) _detailRow('Cancel Reason', apt.cancelReason!),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEFAA1F),
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Interview Appointments',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _fetchAppointments(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchAppointments(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Search, Status & View Toggle Header ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Schedule and monitor candidate recruitment rounds.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 12),

                        // Search Bar
                        Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: const InputDecoration(
                              hintText: 'Search candidate, position, or interviewer...',
                              hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Status Filter & List / Calendar View Toggle
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _statusFilter,
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                    items: const [
                                      'All Statuses',
                                      'Scheduled',
                                      'Completed',
                                      'Rescheduled',
                                      'Cancelled',
                                    ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _statusFilter = v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // View Toggle
                            Container(
                              height: 40,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  _viewToggleBtn('List', Icons.format_list_bulleted_rounded),
                                  _viewToggleBtn('Calendar', Icons.calendar_month_outlined),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Content View ──
                  if (_viewMode == 'List') ...[
                    if (_filteredAppointments.isEmpty)
                      _buildEmptyCard()
                    else
                      ..._filteredAppointments.map((apt) => _buildAppointmentCard(apt)),
                  ] else ...[
                    _buildCalendarView(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _viewToggleBtn(String mode, IconData icon) {
    final isSelected = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B)),
            const SizedBox(width: 4),
            Text(
              mode,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(AdminInterviewAppointment apt) {
    Color stBg;
    Color stFg;
    if (apt.status == 'Completed') {
      stBg = const Color(0xFFDCFCE7);
      stFg = const Color(0xFF16A34A);
    } else if (apt.status == 'Cancelled') {
      stBg = const Color(0xFFFEE2E2);
      stFg = const Color(0xFFDC2626);
    } else if (apt.status == 'Rescheduled') {
      stBg = const Color(0xFFFEF3C7);
      stFg = const Color(0xFFD97706);
    } else {
      stBg = const Color(0xFFE0E7FF);
      stFg = const Color(0xFF4338CA);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(apt.id, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: stBg, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  apt.status.toUpperCase(),
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: stFg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(apt.candidateName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(apt.candidateEmail, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('POSITION & ROUND', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 1),
                          Text('${apt.position} • ${apt.round}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('INTERVIEWER', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 1),
                          Text(apt.interviewerName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDBEAFE)),
                      ),
                      child: Text(
                        apt.mode,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF2563EB)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              Text(
                '${apt.interviewDate} at ${apt.interviewTime}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
              ),
              const Spacer(),
              // Actions
              IconButton(
                icon: const Icon(Icons.edit_calendar_rounded, size: 18, color: Color(0xFF2563EB)),
                onPressed: () => _showRescheduleModal(apt),
                tooltip: 'Reschedule',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 14),
              IconButton(
                icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFEF4444)),
                onPressed: () => _showCancelModal(apt),
                tooltip: 'Cancel',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 14),
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF64748B)),
                onPressed: () => _showDetailsModal(apt),
                tooltip: 'View Details',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarView() {
    final dayAppointments = _selectedDay != null ? _getAppointmentsForDay(_selectedDay!) : [];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: TableCalendar(
            firstDay: DateTime.now().subtract(const Duration(days: 90)),
            lastDay: DateTime.now().add(const Duration(days: 180)),
            focusedDay: _focusedDay,
            currentDay: DateTime.now(),
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(color: const Color(0xFFFFFBEB), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFEFAA1F))),
              todayTextStyle: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w800),
              selectedDecoration: const BoxDecoration(color: Color(0xFFEFAA1F), shape: BoxShape.circle),
              selectedTextStyle: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900),
            ),
            eventLoader: (day) => _getAppointmentsForDay(day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
          ),
        ),
        const SizedBox(height: 16),

        // Selected Day Appointments
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INTERVIEWS: ${_selectedDay != null ? DateFormat('EEE, MMM d, yyyy').format(_selectedDay!).toUpperCase() : ''}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              if (dayAppointments.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  alignment: Alignment.center,
                  child: Column(
                    children: const [
                      Icon(Icons.event_busy_rounded, size: 36, color: Color(0xFFCBD5E1)),
                      SizedBox(height: 8),
                      Text('No interviews scheduled for this date', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    ],
                  ),
                )
              else
                ...dayAppointments.map((apt) => _buildAppointmentCard(apt)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      padding: const EdgeInsets.all(36),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        children: const [
          Icon(Icons.calendar_today_outlined, size: 40, color: Color(0xFF94A3B8)),
          SizedBox(height: 10),
          Text(
            'No interview appointments found',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}
