import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asset_model.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class AssetService {
  final ApiClient _api = ApiClient();
  static const String _cacheAssetTypesKey = 'cached_asset_types';
  static const String _cacheBranchesKey = 'cached_branches';
  static const String _cacheTimestampKey = 'cache_timestamp';
  static const Duration _cacheValidDuration = Duration(minutes: 30);

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
      token = token.replaceAll('"', '');
    }
    if (token != null && token.isNotEmpty) _api.setAuthToken(token);
  }

  Future<Map<String, dynamic>> getAssets({
    String? status,
    String? search,
    String? type,
    String? branchId,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/assets',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (status != null && status.isNotEmpty && status != 'All Assets') 'status': status,
          if (search != null && search.isNotEmpty) 'search': search,
          if (type != null && type.isNotEmpty) 'type': type,
          if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
        },
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        final data = body['data'];
        List<Asset> assets = [];
        if (data != null && data['assets'] != null) {
          assets = (data['assets'] as List)
              .map((json) => Asset.fromJson(json as Map<String, dynamic>))
              .toList();
        }
        return {
          'success': true,
          'data': assets,
          'pagination': data?['pagination'] ?? {},
        };
      }
      return {'success': true, 'data': [], 'pagination': {}};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getAssetById(String assetId) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>('/assets/$assetId');
      final body = response.data;
      if (body != null && body['success'] == true && body['data']?['asset'] != null) {
        final asset = Asset.fromJson(body['data']['asset'] as Map<String, dynamic>);
        return {'success': true, 'data': asset};
      }
      return {'success': false, 'message': 'Invalid response format'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getAssetTypes({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh) {
        final cached = await _getCachedAssetTypes();
        if (cached != null) return {'success': true, 'data': cached};
      }
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>('/assets/types');
      final body = response.data;
      if (body != null && body['success'] == true) {
        final data = body['data'];
        List<Map<String, dynamic>> items = [];
        if (data != null && data['assetTypes'] != null) {
          items = (data['assetTypes'] as List).map((e) => e as Map<String, dynamic>).toList();
        }
        await _cacheAssetTypes(items);
        return {'success': true, 'data': items};
      }
      final cached = await _getCachedAssetTypes();
      if (cached != null) return {'success': true, 'data': cached, 'fromCache': true};
      return {'success': false, 'message': 'Failed to fetch asset types'};
    } on DioException catch (e) {
      final cached = await _getCachedAssetTypes();
      if (cached != null) return {'success': true, 'data': cached, 'fromCache': true};
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      final cached = await _getCachedAssetTypes();
      if (cached != null) return {'success': true, 'data': cached, 'fromCache': true};
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getBranches({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh) {
        final cached = await _getCachedBranches();
        if (cached != null) return {'success': true, 'data': cached};
      }
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>('/assets/branches/list');
      final body = response.data;
      if (body != null && body['success'] == true) {
        final data = body['data'];
        List<Map<String, dynamic>> items = [];
        if (data != null && data['branches'] != null) {
          items = (data['branches'] as List).map((e) => e as Map<String, dynamic>).toList();
        }
        await _cacheBranches(items);
        return {'success': true, 'data': items};
      }
      final cached = await _getCachedBranches();
      if (cached != null) return {'success': true, 'data': cached, 'fromCache': true};
      return {'success': false, 'message': 'Failed to fetch branches'};
    } on DioException catch (e) {
      final cached = await _getCachedBranches();
      if (cached != null) return {'success': true, 'data': cached, 'fromCache': true};
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      final cached = await _getCachedBranches();
      if (cached != null) return {'success': true, 'data': cached, 'fromCache': true};
      return {'success': false, 'message': _handleException(e)};
    }
  }

  String _dioMessage(DioException e) {
    return ErrorMessageUtils.messageFromDioException(e);
  }

  String _handleException(dynamic error) {
    if (error is SocketException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('failed host lookup') || msg.contains('name resolution')) {
        return 'Unable to reach server. Please check your internet connection or contact support.';
      }
      if (msg.contains('connection refused') || msg.contains('connection reset')) {
        return 'Server is not responding. Please try again in a moment or contact support.';
      }
      return 'Connection error. Please check your internet connection and try again.';
    }
    if (error is TimeoutException) {
      return 'Connection timed out. The server is taking too long to respond. Please try again.';
    }
    if (error is FormatException) {
      return 'Invalid response format from server. Please try again.';
    }
    return error.toString();
  }

  Future<void> _cacheAssetTypes(List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheAssetTypesKey, jsonEncode(list));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> _getCachedAssetTypes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheAssetTypesKey);
      final timestamp = prefs.getInt(_cacheTimestampKey);
      if (cachedJson != null && timestamp != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        if (DateTime.now().difference(cacheTime) < _cacheValidDuration) {
          final decoded = jsonDecode(cachedJson) as List;
          return decoded.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _cacheBranches(List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheBranchesKey, jsonEncode(list));
      await prefs.setInt('${_cacheTimestampKey}_branches', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> _getCachedBranches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheBranchesKey);
      final timestamp = prefs.getInt('${_cacheTimestampKey}_branches');
      if (cachedJson != null && timestamp != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        if (DateTime.now().difference(cacheTime) < _cacheValidDuration) {
          final decoded = jsonDecode(cachedJson) as List;
          return decoded.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (_) {}
    return null;
  }
}
