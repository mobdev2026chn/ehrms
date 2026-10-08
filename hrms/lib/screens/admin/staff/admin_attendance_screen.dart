// lib/screens/admin/staff/admin_attendance_screen.dart
//
// Admin "Employee Attendance" register. Mirrors the web admin page
// (HRMSfrontend features/admin/staff/Attendance/pages/Attendance.tsx) and its modals:
// Present, Half Day, Absent, Leave, Week Off, Fine, Overtime, Note and Logs.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_staff_attendance_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

/// Field border and card hairline (match the global theme).
const _kLine = Color(0xFFE2E5EA);
const _kCardBorder = Color(0xFFECEEF1);
/// Fine accent (rose) - distinct from the Absent red.
const _kRose = Color(0xFFE11D48);

/// Paid and Unpaid are always offered to an admin; they draw on no balance (web parity).
const List<String> _kDefaultLeaveTypes = ['Paid', 'Unpaid'];

Map<String, dynamic>? _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// One row of GET /admin/staff/attendance/all-staff.
class AdminAttendanceRecord {
  final String id;
  final String staffId;
  final String name;
  final String department;
  final String date;
  final String shiftId;
  final String shiftName;
  final String shiftStartTime;
  final String shiftEndTime;
  final String checkIn;
  final String checkOut;
  final String hours;
  /// Backend status: 'On Time' | 'Late' | 'Absent' | 'On Leave'.
  final String status;
  final bool isApproved;
  final bool isWeekOff;
  final bool isHoliday;
  final String holidayName;
  final bool isLocked;
  final String lockMessage;
  final Map<String, dynamic>? leaveDetails;
  final Map<String, dynamic>? fineAdjustment;
  final Map<String, dynamic>? overtimeAdjustment;
  final String note;
  final List<Map<String, dynamic>> activityLogs;

  AdminAttendanceRecord({
    required this.id,
    required this.staffId,
    required this.name,
    required this.department,
    required this.date,
    required this.shiftId,
    required this.shiftName,
    required this.shiftStartTime,
    required this.shiftEndTime,
    required this.checkIn,
    required this.checkOut,
    required this.hours,
    required this.status,
    required this.isApproved,
    required this.isWeekOff,
    required this.isHoliday,
    required this.holidayName,
    required this.isLocked,
    required this.lockMessage,
    required this.leaveDetails,
    required this.fineAdjustment,
    required this.overtimeAdjustment,
    required this.note,
    required this.activityLogs,
  });

  factory AdminAttendanceRecord.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] ?? json['_id'] ?? '').toString();
    final staffId = (json['staffId'] ?? '').toString();
    return AdminAttendanceRecord(
      id: rawId,
      staffId: staffId.isNotEmpty ? staffId : rawId.replaceFirst('TEMP-', ''),
      name: (json['name'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      shiftId: (json['shiftId'] ?? '').toString(),
      shiftName: (json['shiftName'] ?? 'General Shift').toString(),
      shiftStartTime: (json['shiftStartTime'] ?? '').toString(),
      shiftEndTime: (json['shiftEndTime'] ?? '').toString(),
      checkIn: (json['checkIn'] ?? '-').toString(),
      checkOut: (json['checkOut'] ?? '-').toString(),
      hours: (json['hours'] ?? '0.0').toString(),
      status: (json['status'] ?? 'Absent').toString(),
      isApproved: json['isApproved'] == true,
      isWeekOff: json['isWeekOff'] == true,
      isHoliday: json['isHoliday'] == true,
      holidayName: (json['holidayName'] ?? '').toString(),
      isLocked: json['attendanceLocked'] == true,
      lockMessage: (json['attendanceLockMessage'] ?? '').toString(),
      leaveDetails: _asMap(json['leaveDetails']),
      fineAdjustment: _asMap(json['fineAdjustment']),
      overtimeAdjustment: _asMap(json['overtimeAdjustment']),
      note: (json['note'] ?? '').toString(),
      activityLogs: ((json['activityLogs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }

  bool get hasPunch => checkIn != '-' && checkIn.isNotEmpty;
  bool get isPresent => status == 'On Time' || status == 'Late';
  /// A half_day record is returned as 'Late'/'On Time' with leaveDetails.isHalfDay.
  bool get isHalfDay => isPresent && leaveDetails?['isHalfDay'] == true;
  double get totalFine => _asDouble(fineAdjustment?['totalFine']);
  double get overtimeAmount => _asDouble(overtimeAdjustment?['amount']);
  String get leaveType => (leaveDetails?['leaveType'] ?? '').toString();
}

class AdminAttendanceScreen extends StatefulWidget {
  final String? initialFilter;

  const AdminAttendanceScreen({super.key, this.initialFilter});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminStaffAttendanceService _service = AdminStaffAttendanceService();

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  late String _statusFilter;
  bool _busy = false;

  List<AdminAttendanceRecord> _records = [];
  Set<String> _weekOffStaffIds = {};

  static const List<String> _baseTabs = ['All', 'Pending', 'Present', 'Half Day', 'Absent', 'On Leave', 'Holiday'];

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilter;
    if (f == null) {
      _statusFilter = 'All';
    } else if (_baseTabs.contains(f) || f == 'Late') {
      _statusFilter = f;
    } else {
      _statusFilter = 'All';
    }
    _fetchAttendance();
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  List<String> get _tabs => _statusFilter == 'Late' ? [..._baseTabs, 'Late'] : _baseTabs;

  bool _isOnWeekOff(AdminAttendanceRecord r) => _weekOffStaffIds.contains(r.staffId);

  bool _matchesTab(String tab, AdminAttendanceRecord r) {
    switch (tab) {
      case 'Pending':
        return (r.hasPunch || r.isPresent) && !r.isApproved;
      case 'Present':
        return r.isPresent;
      case 'Late':
        return r.status == 'Late' && !r.isHalfDay;
      case 'Half Day':
        return r.isHalfDay;
      case 'Absent':
        return r.status == 'Absent';
      case 'On Leave':
        return r.status == 'On Leave' && !_isOnWeekOff(r) && !r.isHoliday;
      case 'Holiday':
        return r.isHoliday || (!r.hasPunch && _isOnWeekOff(r));
      default:
        return true;
    }
  }

  List<AdminAttendanceRecord> get _searchedRecords {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _records;
    return _records
        .where((r) => r.name.toLowerCase().contains(q) || r.department.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _fetchAttendance({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await _service.getAllStaffAttendance(_dateStr);
      final list = (data['records'] as List?) ?? const [];
      final weekOffs = (data['weekOffStaffIds'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _records = list
            .whereType<Map>()
            .map((e) => AdminAttendanceRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _weekOffStaffIds = weekOffs.map((e) => e.toString()).toSet();
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = AdminStaffAttendanceService.errorMessage(e, 'Failed to load attendance');
      setState(() {
        _isLoading = false;
        _error = msg;
      });
      if (!showLoader) SnackBarUtils.showSnackBar(context, msg, isError: true);
    }
  }

  void _changeDate(DateTime d) {
    setState(() => _selectedDate = d);
    _fetchAttendance();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null && !DateUtils.isSameDay(picked, _selectedDate)) {
      _changeDate(picked);
    }
  }

  bool get _isToday => DateUtils.isSameDay(_selectedDate, DateTime.now());

  String _formatOrdinal(DateTime d) {
    final day = d.day;
    String suffix = 'th';
    if (day == 1 || day == 21 || day == 31) {
      suffix = 'st';
    } else if (day == 2 || day == 22) {
      suffix = 'nd';
    } else if (day == 3 || day == 23) {
      suffix = 'rd';
    }
    return '${DateFormat('MMMM').format(d)} $day$suffix, ${d.year}';
  }

  /// Runs a write, shows the backend message, and reloads the register only on success.
  Future<bool> _runAction(Future<String?> Function() action, String successFallback, String errorFallback) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final msg = await action();
      if (!mounted) return true;
      SnackBarUtils.showSnackBar(context, (msg == null || msg.isEmpty) ? successFallback : msg);
      await _fetchAttendance(showLoader: false);
      return true;
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, AdminStaffAttendanceService.errorMessage(e, errorFallback), isError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _guardLocked(AdminAttendanceRecord r) {
    if (r.isLocked) {
      SnackBarUtils.showSnackBar(
        context,
        r.lockMessage.isNotEmpty ? r.lockMessage : 'Attendance cannot be recorded for this day.',
        isError: true,
      );
      return true;
    }
    return false;
  }

  // ── Time helpers ──

  TimeOfDay? _parseTime(String s) {
    final clean = s.trim();
    if (clean.isEmpty || clean == '-' || clean == 'NA') return null;
    final m12 = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)$', caseSensitive: false).firstMatch(clean);
    if (m12 != null) {
      var h = int.parse(m12.group(1)!) % 12;
      if (m12.group(3)!.toUpperCase() == 'PM') h += 12;
      return TimeOfDay(hour: h, minute: int.parse(m12.group(2)!));
    }
    final m24 = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(clean);
    if (m24 != null) {
      return TimeOfDay(hour: int.parse(m24.group(1)!) % 24, minute: int.parse(m24.group(2)!));
    }
    return null;
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $p';
  }

  Widget _timeField(BuildContext ctx, String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPicked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showTimePicker(context: ctx, initialTime: value ?? const TimeOfDay(hour: 9, minute: 0));
            if (picked != null) onPicked(picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: _fieldShell,
            child: Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  value != null ? _formatTime(value) : 'Select time',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: value != null ? FontWeight.w600 : FontWeight.w400,
                    color: value != null ? AppColors.textPrimary : AppColors.textCaption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Modals ──

  Future<void> _showPresentModal(AdminAttendanceRecord r) async {
    if (_guardLocked(r)) return;
    TimeOfDay? inTime = _parseTime(r.checkIn);
    TimeOfDay? outTime = _parseTime(r.checkOut);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          return _dialog(
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
            title: 'Mark Present',
            subtitle: '${_formatOrdinal(_selectedDate)} · ${r.name}',
            children: [
              _timeField(context, 'LOGIN TIME', inTime, (t) => setModal(() => inTime = t)),
              const SizedBox(height: 12),
              _timeField(context, 'LOGOUT TIME', outTime, (t) => setModal(() => outTime = t)),
              if (r.totalFine > 0) ...[
                const SizedBox(height: 12),
                Text('Current fine: ₹${r.totalFine.toStringAsFixed(2)}',
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.error)),
              ],
            ],
            actions: [
              _cancelBtn(ctx),
              _primaryBtn('Approve', AppColors.success, () async {
                if (inTime == null) {
                  SnackBarUtils.showSnackBar(context, 'Login Time is required.', isError: true);
                  return;
                }
                if (outTime == null) {
                  SnackBarUtils.showSnackBar(context, 'Logout Time is required.', isError: true);
                  return;
                }
                if (r.shiftId.isEmpty) {
                  SnackBarUtils.showSnackBar(context, 'No shift assigned to this staff member for the selected date.', isError: true);
                  return;
                }
                Navigator.pop(ctx);
                await _runAction(
                  () => _service.markPresent(
                    staffId: r.staffId,
                    date: _dateStr,
                    shiftId: r.shiftId,
                    checkInTime: _formatTime(inTime!),
                    checkOutTime: _formatTime(outTime!),
                  ),
                  'Marked present for ${r.name}',
                  'Failed to record present attendance',
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showHalfDayModal(AdminAttendanceRecord r) async {
    if (_guardLocked(r)) return;
    final result = await showDialog<_HalfDayResult>(
      context: context,
      builder: (ctx) => _LeaveTypeDialog(
        service: _service,
        staffId: r.staffId,
        title: 'Half Day',
        subtitle: '${_formatOrdinal(_selectedDate)} · ${r.name}',
        icon: Icons.timelapse_rounded,
        color: AppColors.brandDark,
        initialLeaveType: r.leaveType,
        initialIn: _parseTime(r.checkIn) ?? _parseTime(r.shiftStartTime) ?? const TimeOfDay(hour: 9, minute: 0),
        initialOut: _parseTime(r.checkOut) ?? const TimeOfDay(hour: 13, minute: 30),
        withTimes: true,
        timeField: _timeField,
        saveLabel: 'Save Half Day',
      ),
    );
    if (result == null) return;
    await _runAction(
      () => _service.markHalfDay(
        staffId: r.staffId,
        date: _dateStr,
        shiftId: r.shiftId,
        checkInTime: _formatTime(result.inTime!),
        checkOutTime: _formatTime(result.outTime!),
        leaveType: result.leaveType,
      ),
      'Half day recorded for ${r.name}',
      'Failed to record half day attendance',
    );
  }

  Future<void> _showLeaveModal(AdminAttendanceRecord r) async {
    if (_guardLocked(r)) return;
    final result = await showDialog<_HalfDayResult>(
      context: context,
      builder: (ctx) => _LeaveTypeDialog(
        service: _service,
        staffId: r.staffId,
        title: 'Leave',
        subtitle: '${_formatOrdinal(_selectedDate)} · ${r.name}',
        icon: Icons.event_busy_rounded,
        color: AppColors.indigo,
        initialLeaveType: r.leaveType,
        withTimes: false,
        timeField: _timeField,
        saveLabel: 'Save Leave',
      ),
    );
    if (result == null) return;
    await _runAction(
      () => _service.markLeave(
        staffId: r.staffId,
        date: _dateStr,
        leaveType: result.leaveType,
        remarks: (r.leaveDetails?['remarks'] ?? '').toString(),
      ),
      'Leave recorded for ${r.name}',
      'Failed to record leave',
    );
  }

  Future<void> _showAbsentModal(AdminAttendanceRecord r) async {
    if (_guardLocked(r)) return;
    final remarksCtrl = TextEditingController(text: 'No punch recorded. System marked absent automatically.');
    String deduction = 'Deducted';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) => _dialog(
          icon: Icons.cancel_outlined,
          color: AppColors.error,
          title: 'Mark Absent',
          subtitle: '${_formatOrdinal(_selectedDate)} · ${r.name}',
          children: [
            const Text(
              'Do you want to mark this staff member as absent for this day? This will record an uninformed absence.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 12),
            _fieldLabel('REMARKS'),
            const SizedBox(height: 4),
            TextField(controller: remarksCtrl, maxLines: 2, style: AppTextStyles.bodyMedium, decoration: _inputDec('Remarks')),
            const SizedBox(height: 12),
            _fieldLabel('SALARY DEDUCTION'),
            const SizedBox(height: 4),
            _dropdown<String>(
              value: deduction,
              items: const ['Deducted', 'Waived'],
              label: (v) => v,
              onChanged: (v) => setModal(() => deduction = v ?? deduction),
            ),
          ],
          actions: [
            _cancelBtn(ctx),
            _primaryBtn('Mark Absent', AppColors.error, () async {
              Navigator.pop(ctx);
              await _runAction(
                () => _service.markAbsent(
                  staffId: r.staffId,
                  date: _dateStr,
                  remarks: remarksCtrl.text.trim(),
                  deductionStatus: deduction,
                ),
                'Marked absent for ${r.name}',
                'Failed to record absent attendance',
              );
            }),
          ],
        ),
      ),
    );
    remarksCtrl.dispose();
  }

  Future<void> _showWeekOffModal(AdminAttendanceRecord r) async {
    if (_guardLocked(r)) return;
    String type = 'Week Off';
    DateTime? alternate;
    final today = DateUtils.dateOnly(DateTime.now());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) => _dialog(
          icon: Icons.weekend_outlined,
          color: AppColors.textSecondary,
          title: 'Week Off - ${r.name}',
          subtitle: _formatOrdinal(_selectedDate),
          children: [
            _fieldLabel('TYPE'),
            const SizedBox(height: 4),
            _dropdown<String>(
              value: type,
              items: const ['Week Off', 'Comp Off'],
              label: (v) => v,
              onChanged: (v) => setModal(() => type = v ?? type),
            ),
            if (type == 'Comp Off') ...[
              const SizedBox(height: 12),
              _fieldLabel('ALTERNATE WORK DATE'),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  final first = today.add(const Duration(days: 1));
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: alternate ?? first,
                    firstDate: first,
                    lastDate: today.add(const Duration(days: 365)),
                  );
                  if (picked != null) setModal(() => alternate = picked);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: _fieldShell,
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        alternate != null ? DateFormat('dd MMM yyyy').format(alternate!) : 'Select date',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: alternate != null ? FontWeight.w600 : FontWeight.w400,
                          color: alternate != null ? AppColors.textPrimary : AppColors.textCaption,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This day will remain as Week Off. The selected alternate date will be marked as a Working Day and 1 Comp Off will be credited.',
                style: AppTextStyles.caption,
              ),
            ],
          ],
          actions: [
            _cancelBtn(ctx),
            _primaryBtn('Save', AppColors.textSecondary, () async {
              if (type == 'Comp Off' && alternate == null) {
                SnackBarUtils.showSnackBar(context, 'Please select an alternate work date for Comp Off.', isError: true);
                return;
              }
              Navigator.pop(ctx);
              await _runAction(
                () => _service.markWeekOff(
                  staffId: r.staffId,
                  date: _dateStr,
                  leaveType: type,
                  alternateWorkDate: type == 'Comp Off' ? DateFormat('yyyy-MM-dd').format(alternate!) : null,
                  policyName: r.shiftName.isNotEmpty ? r.shiftName : 'Weekly Off',
                ),
                'Week off saved for ${r.name}',
                'Failed to convert week off',
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _showNoteModal(AdminAttendanceRecord r) async {
    final noteCtrl = TextEditingController(text: r.note);
    await showDialog(
      context: context,
      builder: (ctx) => _dialog(
        icon: Icons.edit_note_rounded,
        color: AppColors.primary,
        title: r.note.isNotEmpty ? 'Edit Note' : 'Add Note',
        subtitle: '${_formatOrdinal(_selectedDate)} · ${r.name}',
        children: [
          TextField(
            controller: noteCtrl,
            maxLines: 4,
            style: AppTextStyles.bodyMedium,
            decoration: _inputDec('Enter note here (e.g. approved leave offline, half day adjustments, etc.)'),
          ),
        ],
        actions: [
          _cancelBtn(ctx),
          _primaryBtn('Save Note', AppColors.primary, () async {
            Navigator.pop(ctx);
            await _runAction(
              () => _service.saveNote(staffId: r.staffId, date: _dateStr, note: noteCtrl.text.trim()),
              'Note saved successfully.',
              'Failed to save note.',
            );
          }, fg: AppColors.onPrimary),
        ],
      ),
    );
    noteCtrl.dispose();
  }

  void _showLogsModal(AdminAttendanceRecord r) {
    showDialog(
      context: context,
      builder: (ctx) => _dialog(
        icon: Icons.history_rounded,
        color: AppColors.info,
        title: 'Activity Logs',
        subtitle: '${_formatOrdinal(_selectedDate)} · ${r.name}',
        children: [
          if (r.activityLogs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('No activity logged for this day.', style: AppTextStyles.bodySmall)),
            )
          else
            ...r.activityLogs.reversed.map((log) {
              final t = DateTime.tryParse((log['time'] ?? '').toString())?.toLocal();
              final action = (log['action'] ?? '').toString().replaceAll('_', ' ');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: _kCardBorder)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(action.isEmpty ? 'Update' : action.toUpperCase(),
                              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.4)),
                        ),
                        if (t != null)
                          Text(DateFormat('dd MMM, hh:mm a').format(t), style: AppTextStyles.caption),
                      ],
                    ),
                    if ((log['details'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(log['details'].toString(), style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary)),
                    ],
                    if ((log['performedByName'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('By ${log['performedByName']}', style: AppTextStyles.caption),
                    ],
                  ],
                ),
              );
            }),
        ],
        actions: [_primaryBtn('Close', AppColors.primary, () => Navigator.pop(ctx), fg: AppColors.onPrimary)],
      ),
    );
  }

  Future<void> _showFineModal(AdminAttendanceRecord r) async {
    if (_guardLocked(r)) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _FineDialog(
        service: _service,
        staffId: r.staffId,
        date: _dateStr,
        subtitle: '${_formatOrdinal(_selectedDate)} · ${r.name}',
        record: r,
      ),
    );
    if (saved == true) await _fetchAttendance(showLoader: false);
  }

  Future<void> _showOvertimeModal(AdminAttendanceRecord r) async {
    if (_guardLocked(r)) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _OvertimeDialog(
        service: _service,
        staffId: r.staffId,
        date: _dateStr,
        subtitle: '${_formatOrdinal(_selectedDate)} · ${r.name}',
        record: r,
      ),
    );
    if (saved == true) await _fetchAttendance(showLoader: false);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Open menu',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Employee Attendance'),
      ),
      body: Column(
        children: [
          _buildDateBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildDateBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: _kCardBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _dateNavBtn(
            tooltip: 'Previous Day',
            icon: Icons.chevron_left_rounded,
            onPressed: _isLoading ? null : () => _changeDate(_selectedDate.subtract(const Duration(days: 1))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kLine),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.primaryText),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _formatOrdinal(_selectedDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _dateNavBtn(
            tooltip: 'Next Day',
            icon: Icons.chevron_right_rounded,
            onPressed: (_isLoading || _isToday) ? null : () => _changeDate(_selectedDate.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }

  Widget _dateNavBtn({required String tooltip, required IconData icon, required VoidCallback? onPressed}) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: AppColors.textPrimary,
        disabledColor: AppColors.textHint,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _kLine),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: AppTabLoader());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
                child: const Icon(Icons.error_outline_rounded, size: 30, color: AppColors.error),
              ),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _fetchAttendance(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final searched = _searchedRecords;
    final filtered = _statusFilter == 'All' ? searched : searched.where((r) => _matchesTab(_statusFilter, r)).toList();

    return RefreshIndicator(
      onRefresh: () => _fetchAttendance(showLoader: false),
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // ── Status tabs with counts ──
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _tabs.map((t) {
                final count = t == 'All' ? searched.length : searched.where((r) => _matchesTab(t, r)).length;
                return Padding(padding: const EdgeInsets.only(right: 8), child: _tabPill(t, count));
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // ── Search & Refresh ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: AppTextStyles.bodyMedium,
                  decoration: const InputDecoration(
                    hintText: 'Search by name or department...',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Refresh',
                  onPressed: _busy ? null : () => _fetchAttendance(),
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _kLine)),
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
              ),
            ),
          const SizedBox(height: 16),

          if (filtered.isEmpty)
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              border: Border.all(color: _kCardBorder),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.event_note_outlined, size: 28, color: AppColors.primaryText),
                  ),
                  const SizedBox(height: 12),
                  const Text('No attendance records found.', textAlign: TextAlign.center, style: AppTextStyles.headingSmall),
                ],
              ),
            )
          else
            ...filtered.map(_buildAttendanceCard),
        ],
      ),
    );
  }

  Widget _tabPill(String label, int count) {
    final isSelected = _statusFilter == label;
    return InkWell(
      onTap: () => setState(() => _statusFilter = label),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? AppColors.primary : _kLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.onPrimary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.onPrimary.withValues(alpha: 0.18) : AppColors.inputFill,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard(AdminAttendanceRecord r) {
    final d = DateTime.tryParse(r.date) ?? _selectedDate;
    final onWeekOff = _isOnWeekOff(r);
    final showWeeklyOff = onWeekOff && r.status == 'On Leave';
    final statusLabel = showWeeklyOff ? 'Weekly Off' : (r.isHalfDay ? 'Half Day' : r.status);

    Color stBg;
    Color stFg;
    switch (statusLabel) {
      case 'On Time':
        final present = AppColors.statusStyle('present');
        stBg = r.isApproved ? present.fg : present.bg;
        stFg = r.isApproved ? Colors.white : present.fg;
        break;
      case 'Late':
      case 'Half Day':
        final pending = AppColors.statusStyle('pending');
        stBg = pending.bg;
        stFg = pending.fg;
        break;
      case 'On Leave':
        final leave = AppColors.statusStyle('on leave');
        stBg = leave.bg;
        stFg = leave.fg;
        break;
      case 'Weekly Off':
        final weekend = AppColors.statusStyle('weekend');
        stBg = weekend.bg;
        stFg = weekend.fg;
        break;
      default:
        final absent = AppColors.statusStyle('absent');
        stBg = absent.bg;
        stFg = absent.fg;
    }

    final otAdj = r.overtimeAdjustment;
    final otH = _asInt(_asMap(otAdj?['updatedOvertime'])?['hours']);
    final otM = _asInt(_asMap(otAdj?['updatedOvertime'])?['minutes']);
    final fineApproved = r.fineAdjustment?['status'] == 'Approved';
    final holiday = AppColors.statusStyle('holiday');

    return Opacity(
      opacity: r.isLocked ? 0.85 : 1,
      child: AppCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        border: Border.all(color: _kCardBorder),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text('${d.day}', style: AppTextStyles.headingMedium.copyWith(height: 1.1, fontWeight: FontWeight.w700)),
                      Text(
                        DateFormat('EEE').format(d).toUpperCase(),
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                      Text(
                        DateFormat('MMM yyyy').format(d).toUpperCase(),
                        style: AppTextStyles.caption.copyWith(fontSize: 8, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(r.name, style: AppTextStyles.headingSmall),
                          if (r.department.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(999)),
                              child: Text(
                                r.department,
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (r.isHoliday)
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(r.holidayName.isNotEmpty ? r.holidayName : 'Public Holiday',
                                style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                            _badge('Holiday', holiday.bg, holiday.fg),
                          ],
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.schedule_rounded, size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  r.hasPunch ? '${r.checkIn} - ${r.checkOut}' : 'No Punch Record',
                                  style: AppTextStyles.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            _badge(statusLabel, stBg, stFg),
                          ],
                        ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          if (r.hours != '0.0') Text('${r.hours} Hrs ·', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                          Text(
                            '${r.shiftName.isNotEmpty ? r.shiftName : 'General Shift'} · ${r.shiftStartTime} - ${r.shiftEndTime}',
                            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                          ),
                          if (r.totalFine > 0)
                            InkWell(
                              onTap: () => _showFineModal(r),
                              child: Text(
                                '· Fine: ₹${r.totalFine.toStringAsFixed(2)}',
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: fineApproved ? FontWeight.w700 : FontWeight.w600,
                                  color: AppColors.error,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.error,
                                ),
                              ),
                            ),
                          if (r.overtimeAmount > 0)
                            InkWell(
                              onTap: () => _showOvertimeModal(r),
                              child: Text(
                                '· OT: ${otH > 0 ? '${otH}h ' : ''}${otM}m (₹${r.overtimeAmount.toStringAsFixed(2)})',
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.success,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (r.note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Note: ${r.note}',
                            style: AppTextStyles.caption.copyWith(fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _linkAction(Icons.edit_note_rounded, r.note.isNotEmpty ? 'Edit Note' : 'Add Note', () => _showNoteModal(r)),
                          const SizedBox(width: 16),
                          _linkAction(Icons.history_rounded, 'Logs', () => _showLogsModal(r)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (r.isLocked && r.lockMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(child: Text(r.lockMessage, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary))),
                ],
              ),
            ],
            const Divider(height: 24),
            Opacity(
              opacity: r.isLocked ? 0.5 : 1,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _actionMiniBtn('P PRESENT', AppColors.success, r.isPresent || r.hasPunch, () => _showPresentModal(r)),
                  _actionMiniBtn('HD HALF DAY', AppColors.brandDark, r.isHalfDay, () => _showHalfDayModal(r)),
                  _actionMiniBtn('A ABSENT', AppColors.error, r.status == 'Absent', () => _showAbsentModal(r)),
                  _actionMiniBtn('F FINE', _kRose, r.totalFine > 0, () => _showFineModal(r)),
                  _actionMiniBtn('OT OVERTIME', AppColors.indigo, r.overtimeAmount > 0, () => _showOvertimeModal(r)),
                  _actionMiniBtn('L LEAVE', AppColors.info, r.status == 'On Leave' && !onWeekOff && !r.isHoliday, () => _showLeaveModal(r)),
                  _actionMiniBtn('WO WEEK OFF', AppColors.textSecondary, onWeekOff, () => _showWeekOffModal(r)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.info),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.info)),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _actionMiniBtn(String label, Color color, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: isSelected ? 1.0 : 0.35)),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}

// ── Shared dialog pieces ──

/// Theme-matching shell for tap-to-pick fields inside dialogs.
final BoxDecoration _fieldShell = BoxDecoration(
  color: const Color(0xFFF7F8FA),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: _kLine),
);

Widget _fieldLabel(String text) => Text(text, style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary));

InputDecoration _inputDec(String hint) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
  );
}

Widget _dropdown<T>({
  required T value,
  required List<T> items,
  required String Function(T) label,
  required ValueChanged<T?>? onChanged,
}) {
  return Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: _fieldShell,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        borderRadius: BorderRadius.circular(12),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
        items: items.map((v) => DropdownMenuItem<T>(value: v, child: Text(label(v), style: AppTextStyles.bodyMedium))).toList(),
        onChanged: onChanged,
      ),
    ),
  );
}

Widget _dialog({
  required IconData icon,
  required Color color,
  required String title,
  String? subtitle,
  required List<Widget> children,
  required List<Widget> actions,
}) {
  return AlertDialog(
    titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    title: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.headingSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: double.maxFinite,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    ),
    actions: actions,
  );
}

Widget _cancelBtn(BuildContext ctx) => TextButton(
      onPressed: () => Navigator.pop(ctx),
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      child: const Text('Cancel'),
    );

Widget _primaryBtn(String label, Color bg, VoidCallback? onPressed, {Color fg = Colors.white, bool loading = false}) {
  return ElevatedButton(
    onPressed: loading ? null : onPressed,
    style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
    child: loading
        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        : Text(label),
  );
}

Widget _errorBox(String message, VoidCallback onRetry) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.errorBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
          style: TextButton.styleFrom(foregroundColor: AppColors.error, padding: EdgeInsets.zero),
        ),
      ],
    ),
  );
}

Widget _infoBox(String message) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.infoBg.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary))),
      ],
    ),
  );
}

Widget _readOnlyRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
        Text(value, style: AppTextStyles.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

Widget _numberField(TextEditingController c, String hint, ValueChanged<String> onChanged, {bool decimal = false}) {
  return TextField(
    controller: c,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    style: AppTextStyles.bodyMedium,
    decoration: _inputDec(hint),
    onChanged: onChanged,
  );
}

// ── Leave type / Half Day dialog ──

class _HalfDayResult {
  final String leaveType;
  final TimeOfDay? inTime;
  final TimeOfDay? outTime;
  _HalfDayResult(this.leaveType, this.inTime, this.outTime);
}

typedef _TimeFieldBuilder = Widget Function(BuildContext ctx, String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPicked);

class _LeaveTypeDialog extends StatefulWidget {
  final AdminStaffAttendanceService service;
  final String staffId;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String initialLeaveType;
  final TimeOfDay? initialIn;
  final TimeOfDay? initialOut;
  final bool withTimes;
  final _TimeFieldBuilder timeField;
  final String saveLabel;

  const _LeaveTypeDialog({
    required this.service,
    required this.staffId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.initialLeaveType,
    this.initialIn,
    this.initialOut,
    required this.withTimes,
    required this.timeField,
    required this.saveLabel,
  });

  @override
  State<_LeaveTypeDialog> createState() => _LeaveTypeDialogState();
}

class _LeaveTypeDialogState extends State<_LeaveTypeDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _balances = [];
  String _selected = '';
  TimeOfDay? _in;
  TimeOfDay? _out;

  @override
  void initState() {
    super.initState();
    _in = widget.initialIn;
    _out = widget.initialOut;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await widget.service.getStaffLeaveBalances(widget.staffId);
      if (!mounted) return;
      setState(() {
        _balances = b;
        _loading = false;
        final opts = _options;
        if (_selected.isEmpty || !opts.contains(_selected)) {
          _selected = widget.initialLeaveType.trim().isNotEmpty ? widget.initialLeaveType.trim() : opts.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AdminStaffAttendanceService.errorMessage(e, 'Failed to load leave balances');
      });
    }
  }

  List<String> get _options {
    final names = <String>[];
    for (final b in _balances) {
      final n = (b['leaveTypeName'] ?? '').toString().trim();
      if (n.isNotEmpty && !names.contains(n)) names.add(n);
    }
    for (final f in _kDefaultLeaveTypes) {
      if (!names.contains(f)) names.add(f);
    }
    final saved = widget.initialLeaveType.trim();
    if (saved.isNotEmpty && !names.contains(saved)) names.add(saved);
    return names;
  }

  bool get _isPredefined {
    final n = _selected.trim().toLowerCase();
    return n == 'paid' || n == 'unpaid' || n == 'paid leave' || n == 'unpaid leave';
  }

  String get _balanceText {
    final n = _selected.trim().toLowerCase();
    for (final b in _balances) {
      if ((b['leaveTypeName'] ?? '').toString().trim().toLowerCase() == n) {
        final bal = b['balance'];
        final v = bal is num ? bal : num.tryParse(bal?.toString() ?? '') ?? 0;
        return '$v ${v == 1 ? 'day' : 'days'}';
      }
    }
    return '0 days';
  }

  @override
  Widget build(BuildContext context) {
    return _dialog(
      icon: widget.icon,
      color: widget.color,
      title: widget.title,
      subtitle: widget.subtitle,
      children: [
        if (widget.withTimes) ...[
          widget.timeField(context, 'LOGIN TIME', _in, (t) => setState(() => _in = t)),
          const SizedBox(height: 12),
          widget.timeField(context, 'LOGOUT TIME', _out, (t) => setState(() => _out = t)),
          const SizedBox(height: 12),
        ],
        _fieldLabel(widget.withTimes ? 'LEAVE FOR THE OTHER HALF' : 'LEAVE TYPE'),
        const SizedBox(height: 4),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_error != null)
          _errorBox(_error!, _load)
        else ...[
          _dropdown<String>(
            value: _selected,
            items: _options,
            label: (v) => v,
            onChanged: (v) => setState(() => _selected = v ?? _selected),
          ),
          if (_balances.isEmpty) ...[
            const SizedBox(height: 6),
            Text('No leave balance allocated to this employee. Only Paid and Unpaid are available.',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          ],
          if (_selected.isNotEmpty && !_isPredefined) ...[
            const SizedBox(height: 12),
            _readOnlyRow('Leave Balance', _balanceText),
          ],
        ],
      ],
      actions: [
        _cancelBtn(context),
        _primaryBtn(widget.saveLabel, widget.color, (_loading || _error != null || _selected.trim().isEmpty)
            ? null
            : () {
                if (widget.withTimes && (_in == null || _out == null)) {
                  SnackBarUtils.showSnackBar(context, 'Login and logout times are required.', isError: true);
                  return;
                }
                Navigator.pop(context, _HalfDayResult(_selected, _in, _out));
              }),
      ],
    );
  }
}

// ── Fine adjustment dialog ──

const List<String> _kFineOptions = ['Auto Calculate', '1x', '2x', '3x', 'Custom Amount', 'Remove'];
const List<String> _kOtOptions = ['Auto Calculate', '1x', '1.5x', '2x', 'Custom Amount', 'Remove'];

class _FineSection {
  final String key; // 'lateFine' | 'earlyExitFine'
  final String title;
  String actualHours = '00:00';
  final TextEditingController h = TextEditingController(text: '0');
  final TextEditingController m = TextEditingController(text: '0');
  final TextEditingController custom = TextEditingController(text: '0.00');
  String option = 'Auto Calculate';
  double fallbackAmount = 0;

  _FineSection(this.key, this.title);

  int get minutes => (int.tryParse(h.text.trim()) ?? 0) * 60 + (int.tryParse(m.text.trim()) ?? 0);

  double amount(double oneMinuteSalary, bool hasCalc) {
    final base = (minutes > 0 && oneMinuteSalary > 0)
        ? double.parse((minutes * oneMinuteSalary).toStringAsFixed(2))
        : (hasCalc ? 0.0 : fallbackAmount);
    switch (option) {
      case '2x':
        return double.parse((base * 2).toStringAsFixed(2));
      case '3x':
        return double.parse((base * 3).toStringAsFixed(2));
      case 'Custom Amount':
        return double.tryParse(custom.text.trim()) ?? 0;
      case 'Remove':
        return 0;
      default:
        return base;
    }
  }

  void dispose() {
    h.dispose();
    m.dispose();
    custom.dispose();
  }
}

class _FineDialog extends StatefulWidget {
  final AdminStaffAttendanceService service;
  final String staffId;
  final String date;
  final String subtitle;
  final AdminAttendanceRecord record;

  const _FineDialog({required this.service, required this.staffId, required this.date, required this.subtitle, required this.record});

  @override
  State<_FineDialog> createState() => _FineDialogState();
}

class _FineDialogState extends State<_FineDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _calc;
  final _late = _FineSection('lateFine', 'Late Fine');
  final _early = _FineSection('earlyExitFine', 'Early Exit Fine');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _late.dispose();
    _early.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await widget.service.getFineDetails(staffId: widget.staffId, date: widget.date);
      if (!mounted) return;
      final adj = _asMap(c['fineAdjustment']) ?? widget.record.fineAdjustment;
      _apply(_late, _asMap(adj?['lateFine']), c['lateActualHours'], _asInt(c['lateMinutes']), c['lateFineAmount']);
      _apply(_early, _asMap(adj?['earlyExitFine']), c['earlyExitActualHours'], _asInt(c['earlyExitMinutes']), c['earlyExitFineAmount']);
      setState(() {
        _calc = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AdminStaffAttendanceService.errorMessage(e, 'Failed to load fine details');
      });
    }
  }

  void _apply(_FineSection s, Map<String, dynamic>? saved, dynamic actual, int calcMinutes, dynamic calcAmount) {
    s.actualHours = (actual ?? saved?['actualHours'] ?? '00:00').toString();
    final upd = _asMap(saved?['updatedHours']);
    s.h.text = '${upd != null ? _asInt(upd['hours']) : calcMinutes ~/ 60}';
    s.m.text = '${upd != null ? _asInt(upd['minutes']) : calcMinutes % 60}';
    final opt = (saved?['option'] ?? 'Auto Calculate').toString();
    s.option = _kFineOptions.contains(opt) ? opt : 'Auto Calculate';
    s.fallbackAmount = _asDouble(saved?['amount']);
    s.custom.text = (saved?['amount'] != null ? _asDouble(saved?['amount']) : _asDouble(calcAmount)).toStringAsFixed(2);
  }

  double get _oneMinute => _asDouble(_calc?['oneMinuteSalary']);

  Future<void> _save() async {
    final hasCalc = _calc != null;
    Map<String, dynamic> body(_FineSection s) => {
          'actualHours': s.actualHours,
          'updatedHours': {'hours': int.tryParse(s.h.text.trim()) ?? 0, 'minutes': int.tryParse(s.m.text.trim()) ?? 0},
          'option': s.option,
          'amount': s.amount(_oneMinute, hasCalc),
        };
    setState(() => _saving = true);
    try {
      final msg = await widget.service.updateFine(
        staffId: widget.staffId,
        date: widget.date,
        lateFine: body(_late),
        earlyExitFine: body(_early),
      );
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, (msg == null || msg.isEmpty) ? 'Fine adjustment updated successfully!' : msg);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarUtils.showSnackBar(context, AdminStaffAttendanceService.errorMessage(e, 'Failed to update fine adjustment'), isError: true);
    }
  }

  Widget _section(_FineSection s) {
    final amt = s.amount(_oneMinute, _calc != null);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _kCardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.title, style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _readOnlyRow('Actual (hh:mm)', s.actualHours),
          _fieldLabel('UPDATED HOURS / MINUTES'),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _numberField(s.h, 'Hours', (_) => setState(() {}))),
              const SizedBox(width: 8),
              Expanded(child: _numberField(s.m, 'Minutes', (_) => setState(() {}))),
            ],
          ),
          const SizedBox(height: 8),
          _fieldLabel('OPTION'),
          const SizedBox(height: 4),
          _dropdown<String>(value: s.option, items: _kFineOptions, label: (v) => v, onChanged: (v) => setState(() => s.option = v ?? s.option)),
          if (s.option == 'Custom Amount') ...[
            const SizedBox(height: 8),
            _numberField(s.custom, 'Amount', (_) => setState(() {}), decimal: true),
          ],
          const SizedBox(height: 8),
          _readOnlyRow('Amount', '₹${amt.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCalc = _calc != null;
    final total = _late.amount(_oneMinute, hasCalc) + _early.amount(_oneMinute, hasCalc);
    final noAttendance = hasCalc && _calc!['attendance'] == null;
    final checkIn = (_calc?['checkInTime'] ?? '').toString();
    final checkOut = (_calc?['checkOutTime'] ?? '').toString();

    return _dialog(
      icon: Icons.receipt_long_rounded,
      color: _kRose,
      title: 'Fine Adjustment',
      subtitle: widget.subtitle,
      children: _loading
          ? const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))]
          : _error != null
              ? [_errorBox(_error!, _load)]
              : [
                  if (noAttendance)
                    _infoBox('No attendance punch recorded for this date. No fine applicable.')
                  else if (total == 0 && _asDouble(_asMap(_calc?['fineAdjustment'])?['totalFine']) == 0)
                    _infoBox('No fine recorded for this attendance record.'),
                  const SizedBox(height: 8),
                  _readOnlyRow('Punch In', checkIn.isNotEmpty ? checkIn : '--:--'),
                  _readOnlyRow('Punch Out', checkOut.isNotEmpty ? checkOut : '--:--'),
                  _section(_late),
                  _section(_early),
                  const SizedBox(height: 12),
                  _readOnlyRow('Total Fine', '₹${total.toStringAsFixed(2)}'),
                ],
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary), child: const Text('Cancel')),
        _primaryBtn('Update', _kRose, (_loading || _error != null || noAttendance) ? null : _save, loading: _saving),
      ],
    );
  }
}

// ── Overtime adjustment dialog ──

class _OvertimeDialog extends StatefulWidget {
  final AdminStaffAttendanceService service;
  final String staffId;
  final String date;
  final String subtitle;
  final AdminAttendanceRecord record;

  const _OvertimeDialog({required this.service, required this.staffId, required this.date, required this.subtitle, required this.record});

  @override
  State<_OvertimeDialog> createState() => _OvertimeDialogState();
}

class _OvertimeDialogState extends State<_OvertimeDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _calc;
  final _h = TextEditingController(text: '0');
  final _m = TextEditingController(text: '0');
  final _custom = TextEditingController(text: '0.00');
  String _option = 'Auto Calculate';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _h.dispose();
    _m.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await widget.service.getOvertimeDetails(staffId: widget.staffId, date: widget.date);
      if (!mounted) return;
      final adj = _asMap(c['overtimeAdjustment']) ?? widget.record.overtimeAdjustment;
      final upd = _asMap(adj?['updatedOvertime']);
      int hours = 0;
      int minutes = 0;
      if (upd != null) {
        hours = _asInt(upd['hours']);
        minutes = _asInt(upd['minutes']);
      } else {
        final mins = _asInt(c['actualOvertimeMinutes']);
        hours = mins ~/ 60;
        minutes = mins % 60;
      }
      _h.text = '$hours';
      _m.text = '$minutes';
      final opt = (adj?['option'] ?? 'Auto Calculate').toString();
      _option = _kOtOptions.contains(opt) ? opt : 'Auto Calculate';
      _custom.text = _asDouble(adj?['amount']).toStringAsFixed(2);
      setState(() {
        _calc = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AdminStaffAttendanceService.errorMessage(e, 'Failed to load overtime details');
      });
    }
  }

  int get _hours => int.tryParse(_h.text.trim()) ?? 0;
  int get _minutes => int.tryParse(_m.text.trim()) ?? 0;

  double get _amount {
    final hourly = _asDouble(_calc?['hourlyBaseRate']);
    final perMin = _asDouble(_calc?['oneMinuteSalary']) > 0 ? _asDouble(_calc?['oneMinuteSalary']) : hourly / 60;
    final total = _hours * 60 + _minutes;
    switch (_option) {
      case 'Custom Amount':
        return double.tryParse(_custom.text.trim()) ?? 0;
      case 'Remove':
        return 0;
      case '1.5x':
        return double.parse((total * perMin * 1.5).toStringAsFixed(2));
      case '2x':
        return double.parse((total * perMin * 2).toStringAsFixed(2));
      default:
        return double.parse((total * perMin).toStringAsFixed(2));
    }
  }

  String get _actualStr => (_calc?['actualOvertimeHoursStr'] ?? '0h 0m').toString();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final msg = await widget.service.updateOvertime(
        staffId: widget.staffId,
        date: widget.date,
        actualOvertime: _actualStr,
        hours: _hours,
        minutes: _minutes,
        option: _option,
        amount: _amount,
      );
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, (msg == null || msg.isEmpty) ? 'Overtime adjustment updated successfully!' : msg);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarUtils.showSnackBar(context, AdminStaffAttendanceService.errorMessage(e, 'Failed to update overtime adjustment'), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = _asMap(_calc?['attendance']);
    final present = _asMap(att?['presentDetails']);
    final noAttendance = _calc != null && att == null;
    final savedAmount = _asDouble(_asMap(_calc?['overtimeAdjustment'])?['amount']);

    return _dialog(
      icon: Icons.more_time_rounded,
      color: AppColors.indigo,
      title: 'Overtime Adjustment',
      subtitle: widget.subtitle,
      children: _loading
          ? const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))]
          : _error != null
              ? [_errorBox(_error!, _load)]
              : [
                  if (noAttendance)
                    _infoBox('No attendance punch recorded for this date. No overtime applicable.')
                  else if (savedAmount == 0 && _amount == 0)
                    _infoBox('No overtime recorded for this attendance record.'),
                  const SizedBox(height: 8),
                  _readOnlyRow('Punch In', (present?['checkInTime'] ?? '—').toString()),
                  _readOnlyRow('Punch Out', (present?['checkOutTime'] ?? '—').toString()),
                  _readOnlyRow('Actual Overtime', _actualStr),
                  const SizedBox(height: 6),
                  _fieldLabel('UPDATED HOURS / MINUTES'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(child: _numberField(_h, 'Hours', (_) => setState(() {}))),
                      const SizedBox(width: 8),
                      Expanded(child: _numberField(_m, 'Minutes', (_) => setState(() {}))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _fieldLabel('OPTION'),
                  const SizedBox(height: 4),
                  _dropdown<String>(value: _option, items: _kOtOptions, label: (v) => v, onChanged: (v) => setState(() => _option = v ?? _option)),
                  if (_option == 'Custom Amount') ...[
                    const SizedBox(height: 8),
                    _numberField(_custom, 'Amount', (_) => setState(() {}), decimal: true),
                  ],
                  const SizedBox(height: 12),
                  _readOnlyRow('Overtime Amount', '₹${_amount.toStringAsFixed(2)}'),
                ],
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary), child: const Text('Cancel')),
        _primaryBtn('Update', AppColors.indigo, (_loading || _error != null || noAttendance) ? null : _save, loading: _saving),
      ],
    );
  }
}
