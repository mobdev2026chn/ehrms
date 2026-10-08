import 'package:dio/dio.dart';
import 'api_client.dart';

/// Admin dashboard (HRMSbackend GET /api/admin/dashboard). Admin / superAdmin only.
///
/// One call feeds the whole screen: attendance (today + 7 days), approval queues,
/// upcoming birthdays / anniversaries, totals and the department split.
class AdminDashboardService {
  AdminDashboardService._();
  static final AdminDashboardService instance = AdminDashboardService._();
  final ApiClient _api = ApiClient();

  String _msg(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return d['message'].toString();
      return e.message ?? 'Network error';
    }
    return e.toString();
  }

  /// GET /admin/dashboard -> `{success, data: {attendance, approvals, birthdays,
  /// anniversaries, totals, byDepartment, generatedAt}}`.
  Future<Map<String, dynamic>> getDashboard() async {
    try {
      final res = await _api.request<Map<String, dynamic>>('/admin/dashboard');
      final body = res.data;
      if (body == null || body['success'] != true || body['data'] is! Map) {
        return {
          'success': false,
          'message': body?['message']?.toString() ?? 'Failed to load dashboard',
        };
      }
      return {
        'success': true,
        'data': AdminDashboardData.fromJson(Map<String, dynamic>.from(body['data'] as Map)),
      };
    } catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
  }
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class DashboardAttendance {
  final int activeStaff;
  final int present;
  final int late;
  final int absent;
  final int pending;

  const DashboardAttendance({
    this.activeStaff = 0,
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.pending = 0,
  });

  factory DashboardAttendance.fromJson(dynamic j) {
    if (j is! Map) return const DashboardAttendance();
    return DashboardAttendance(
      activeStaff: _int(j['activeStaff']),
      present: _int(j['present']),
      late: _int(j['late']),
      absent: _int(j['absent']),
      pending: _int(j['pending']),
    );
  }
}

class DashboardQueue {
  /// Backend key: punch | leave | permission | fine | reimbursement | payslip
  final String key;
  final String label;
  final int count;

  const DashboardQueue({required this.key, required this.label, required this.count});

  factory DashboardQueue.fromJson(dynamic j) {
    final m = j is Map ? j : const {};
    return DashboardQueue(
      key: (m['key'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
      count: _int(m['count']),
    );
  }
}

class DashboardCelebration {
  final String id;
  final String name;
  final String employeeId;
  final String department;
  final String date;
  final int inDays;
  final int? years;

  const DashboardCelebration({
    required this.id,
    required this.name,
    required this.employeeId,
    required this.department,
    required this.date,
    required this.inDays,
    this.years,
  });

  factory DashboardCelebration.fromJson(dynamic j) {
    final m = j is Map ? j : const {};
    return DashboardCelebration(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      employeeId: (m['employeeId'] ?? '').toString(),
      department: (m['department'] ?? '').toString(),
      date: (m['date'] ?? '').toString(),
      inDays: _int(m['inDays']),
      years: m['years'] == null ? null : _int(m['years']),
    );
  }
}

class DashboardDeptRow {
  final String label;
  final int count;
  const DashboardDeptRow(this.label, this.count);

  factory DashboardDeptRow.fromJson(dynamic j) {
    final m = j is Map ? j : const {};
    return DashboardDeptRow((m['label'] ?? '').toString(), _int(m['count']));
  }
}

class AdminDashboardData {
  final DashboardAttendance today;
  final DashboardAttendance week;
  final int approvalsTotal;
  final DashboardQueue punch;
  final List<DashboardQueue> queues;
  final List<DashboardCelebration> birthdays;
  final List<DashboardCelebration> anniversaries;
  final int totalEmployees;
  final int activeEmployees;
  final int inactiveEmployees;
  final int recentOnboardings;
  final List<DashboardDeptRow> deptTotal;
  final List<DashboardDeptRow> deptOnboarding;
  final DateTime? generatedAt;

  const AdminDashboardData({
    required this.today,
    required this.week,
    required this.approvalsTotal,
    required this.punch,
    required this.queues,
    required this.birthdays,
    required this.anniversaries,
    required this.totalEmployees,
    required this.activeEmployees,
    required this.inactiveEmployees,
    required this.recentOnboardings,
    required this.deptTotal,
    required this.deptOnboarding,
    this.generatedAt,
  });

  static List<T> _list<T>(dynamic v, T Function(dynamic) f) => v is List ? v.map(f).toList() : <T>[];

  factory AdminDashboardData.fromJson(Map<String, dynamic> j) {
    final attendance = j['attendance'] is Map ? j['attendance'] as Map : const {};
    final approvals = j['approvals'] is Map ? j['approvals'] as Map : const {};
    final totals = j['totals'] is Map ? j['totals'] as Map : const {};
    final byDept = j['byDepartment'] is Map ? j['byDepartment'] as Map : const {};
    return AdminDashboardData(
      today: DashboardAttendance.fromJson(attendance['today']),
      week: DashboardAttendance.fromJson(attendance['week']),
      approvalsTotal: _int(approvals['total']),
      punch: approvals['punch'] is Map
          ? DashboardQueue.fromJson(approvals['punch'])
          : const DashboardQueue(key: 'punch', label: 'Pending Punch Approvals', count: 0),
      queues: _list(approvals['queues'], DashboardQueue.fromJson),
      birthdays: _list(j['birthdays'], DashboardCelebration.fromJson),
      anniversaries: _list(j['anniversaries'], DashboardCelebration.fromJson),
      totalEmployees: _int(totals['totalEmployees']),
      activeEmployees: _int(totals['activeEmployees']),
      inactiveEmployees: _int(totals['inactiveEmployees']),
      recentOnboardings: _int(totals['recentOnboardings']),
      deptTotal: _list(byDept['total'], DashboardDeptRow.fromJson),
      deptOnboarding: _list(byDept['onboarding'], DashboardDeptRow.fromJson),
      generatedAt: DateTime.tryParse('${j['generatedAt'] ?? ''}'),
    );
  }
}
