import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class ChatbotService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) _api.setAuthToken(token);
  }

  Future<Map<String, dynamic>> askQuestion(String question) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/chatbot/ask',
        data: {'question': question},
      );
      final data = response.data;
      if (data != null && data['answer'] != null) {
        return {'success': true, 'answer': data['answer']};
      }
      return {'success': false, 'message': 'Failed to get answer'};
    } on DioException catch (e) {
      return {'success': false, 'message': e.response?.data?['message'] ?? 'Failed to get answer'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
