// repository/attendance_repository.dart
// Single data source abstraction for attendance. Delegates to AttendanceService (data layer).
// No HTTP or JSON here; same API contract as before.

import '../services/attendance_service.dart';

class AttendanceRepository {
  AttendanceRepository({AttendanceService? attendanceService})
      : _attendance = attendanceService ?? AttendanceService();

  final AttendanceService _attendance;

  /// Check in. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> checkIn(
    double lat,
    double lng,
    String address, {
    String? area,
    String? city,
    String? pincode,
    String? selfie,
    String? movementType,
  }) async {
    return _attendance.checkIn(
      lat,
      lng,
      address,
      area: area,
      city: city,
      pincode: pincode,
      selfie: selfie,
      movementType: movementType,
    );
  }

  /// Check out. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> checkOut(
    double lat,
    double lng,
    String address, {
    String? area,
    String? city,
    String? pincode,
    String? selfie,
    String? movementType,
  }) async {
    return _attendance.checkOut(
      lat,
      lng,
      address,
      area: area,
      city: city,
      pincode: pincode,
      selfie: selfie,
      movementType: movementType,
    );
  }

  /// Get today's attendance. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> getTodayAttendance({bool forceRefresh = false}) async {
    return _attendance.getTodayAttendance(forceRefresh: forceRefresh);
  }

  /// Get attendance for a specific date. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> getAttendanceByDate(String date) async {
    return _attendance.getAttendanceByDate(date);
  }

  /// Get attendance history (paginated). Returns { success, data?, message? }.
  Future<Map<String, dynamic>> getAttendanceHistory({
    int page = 1,
    int limit = 10,
    String? date,
  }) async {
    return _attendance.getAttendanceHistory(page: page, limit: limit, date: date);
  }

  /// Get month attendance. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> getMonthAttendance(
    int year,
    int month, {
    bool forceRefresh = false,
  }) async {
    return _attendance.getMonthAttendance(year, month, forceRefresh: forceRefresh);
  }

  void clearCachesForRefresh() => _attendance.clearCachesForRefresh();
}
