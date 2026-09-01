// hrms/lib/services/customer_service.dart
import 'package:dio/dio.dart';
import 'package:hrms/models/customer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class CustomerService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) _api.setAuthToken(token);
  }

  Future<Customer> getCustomerById(String id) async {
    await _setToken();
    Response<dynamic>? response;
    for (final path in [
      '/staff/geo-task/customers/$id',
      '/admin/hrms-geo/customer/$id',
      '/customers/$id',
      '/customer/$id',
    ]) {
      try {
        response = await _api.dio.get<dynamic>(path);
        if (response.statusCode == 200 && response.data != null) {
          break;
        }
      } catch (_) {}
    }
    final data = response?.data;
    if (data == null) throw Exception('Failed to load customer');
    final payload = data is Map && data['data'] is Map ? data['data'] as Map<String, dynamic> : data as Map<String, dynamic>;
    return Customer.fromJson(payload);
  }

  Future<List<Customer>> getAllCustomers() async {
    try {
      await _setToken();
      Response<dynamic>? response;
      for (final path in [
        '/staff/geo-task/customers',
        '/admin/hrms-geo/customer',
        '/customers',
        '/customer',
      ]) {
        try {
          response = await _api.dio.get<dynamic>(path);
          if (response.statusCode == 200 && response.data != null) {
            break;
          }
        } catch (_) {}
      }
      final body = response?.data;
      if (body is List) {
        return body
            .whereType<Map<String, dynamic>>()
            .map((e) => Customer.fromJson(e))
            .toList();
      }
      if (body is Map && body['data'] != null) {
        final list = body['data'] as List?;
        if (list != null) {
          return list
              .whereType<Map<String, dynamic>>()
              .map((e) => Customer.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
      return <Customer>[];
    } catch (_) {
      return <Customer>[];
    }
  }

  Future<Customer> createCustomer(Customer customer) async {
    await _setToken();
    final raw = Map<String, dynamic>.from(customer.toJson());
    raw.removeWhere(
      (k, v) =>
          v == null || (v is String && v.trim().isEmpty),
    );
    Response<dynamic>? response;
    DioException? lastError;
    for (final path in [
      '/admin/hrms-geo/customer',
      '/staff/geo-task/customer',
      '/customers',
      '/customer',
    ]) {
      try {
        response = await _api.dio.post<dynamic>(
          path,
          data: raw,
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          break;
        }
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode == 404 || e.response?.statusCode == 405) {
          continue;
        }
        rethrow;
      } catch (_) {}
    }
    final data = response?.data;
    if (data == null) {
      if (lastError != null) throw lastError;
      throw Exception('Failed to create customer');
    }
    if (data is Map) {
      final payload = data['data'] is Map ? data['data'] as Map<String, dynamic> : Map<String, dynamic>.from(data);
      return Customer.fromJson(payload);
    }
    return customer;
  }

  Future<Customer> updateCustomer(String id, Customer customer) async {
    await _setToken();
    Response<Map<String, dynamic>>? response;
    for (final path in [
      '/staff/geo-task/customer/$id',
      '/admin/hrms-geo/customer/$id',
      '/customers/$id',
      '/customer/$id',
    ]) {
      try {
        response = await _api.dio.put<Map<String, dynamic>>(
          path,
          data: customer.toJson(),
        );
        if (response.statusCode == 200) {
          break;
        }
      } catch (_) {}
    }
    final data = response?.data;
    if (data == null) throw Exception('Failed to update customer');
    final payload = data['data'] is Map ? data['data'] as Map<String, dynamic> : data;
    return Customer.fromJson(payload);
  }

  Future<void> deleteCustomer(String id) async {
    await _setToken();
    for (final path in [
      '/staff/geo-task/customer/$id',
      '/admin/hrms-geo/customer/$id',
      '/customers/$id',
      '/customer/$id',
    ]) {
      try {
        final response = await _api.dio.delete(path);
        if (response.statusCode == 204 || response.statusCode == 200) {
          return;
        }
      } catch (_) {}
    }
  }
}
