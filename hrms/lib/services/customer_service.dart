// hrms/lib/services/customer_service.dart
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
    final response = await _api.dio.get<Map<String, dynamic>>('/customers/$id');
    final data = response.data;
    if (data == null) throw Exception('Failed to load customer');
    return Customer.fromJson(data);
  }

  Future<List<Customer>> getAllCustomers() async {
    await _setToken();
    final response = await _api.dio.get<dynamic>('/customers');
    final body = response.data;
    if (body is List) {
      return List<Customer>.from((body).map((e) => Customer.fromJson(e as Map<String, dynamic>)));
    }
    if (body is Map && body['data'] != null) {
      final list = body['data'] as List;
      return List<Customer>.from(list.map((e) => Customer.fromJson(e as Map<String, dynamic>)));
    }
    throw Exception('Failed to load customers');
  }

  Future<Customer> createCustomer(Customer customer) async {
    await _setToken();
    final raw = Map<String, dynamic>.from(customer.toJson());
    raw.removeWhere(
      (k, v) =>
          v == null || (v is String && v.trim().isEmpty),
    );
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/customers',
      data: raw,
    );
    final data = response.data;
    if (data == null) throw Exception('Failed to create customer');
    return Customer.fromJson(data);
  }

  Future<Customer> updateCustomer(String id, Customer customer) async {
    await _setToken();
    final response = await _api.dio.put<Map<String, dynamic>>('/customers/$id', data: customer.toJson());
    final data = response.data;
    if (data == null) throw Exception('Failed to update customer');
    return Customer.fromJson(data);
  }

  Future<void> deleteCustomer(String id) async {
    await _setToken();
    final response = await _api.dio.delete('/customers/$id');
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete customer');
    }
  }
}
