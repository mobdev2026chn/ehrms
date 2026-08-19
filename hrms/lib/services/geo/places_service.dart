// Google Places Autocomplete (legacy) + Place Details for destination search.
// Requires: Places API enabled, billing enabled on the project, API key unrestricted
// or with HTTP referrer / Android/iOS app restriction that allows these endpoints.

import 'package:dio/dio.dart';
import 'package:hrms/config/constants.dart';
import 'package:hrms/services/api_client.dart';

class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}

class PlaceDetails {
  final double lat;
  final double lng;
  final String? formattedAddress;
  final String? pincode;

  const PlaceDetails({
    required this.lat,
    required this.lng,
    this.formattedAddress,
    this.pincode,
  });
}

class PlacesService {
  static final _dio = ApiClient().dio;

  /// Autocomplete predictions for destination search (Uber-style).
  /// Use types=geocode so cities/regions (e.g. "madurai") and addresses both return results.
  static Future<List<PlacePrediction>> autocomplete(
    String input, {
    double? lat,
    double? lng,
  }) async {
    final key = AppConstants.googleMapsApiKey;
    if (key.isEmpty || input.trim().isEmpty) return [];

    try {
      // Full URL – no types restriction for full coverage: cities, areas,
      // streets, landmarks, businesses, pincodes (Google Maps–like).
      var url =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(input.trim())}'
          '&key=$key';
      if (lat != null && lng != null) {
        url += '&location=$lat,$lng&radius=50000';
      }
      final res = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final data = res.data;
      if (data == null) return [];
      final status = data['status'] as String?;

      if (status != 'OK' && status != 'ZERO_RESULTS') return [];
      final predictions = data['predictions'] as List<dynamic>?;
      if (predictions == null) return [];

      final list = <PlacePrediction>[];
      for (final p in predictions) {
        if (p is! Map<String, dynamic>) continue;
        final placeId = p['place_id'] as String?;
        final description = p['description'] as String? ?? '';
        final structured = p['structured_formatting'] as Map<String, dynamic>?;
        final mainText = structured?['main_text'] as String? ?? description;
        final secondaryText = structured?['secondary_text'] as String? ?? '';
        if (placeId != null) {
          list.add(
            PlacePrediction(
              placeId: placeId,
              description: description,
              mainText: mainText,
              secondaryText: secondaryText,
            ),
          );
        }
      }
      return list;
    } on DioException catch (_) {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get lat/lng and formatted address for a place_id (e.g. from autocomplete).
  static Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    final key = AppConstants.googleMapsApiKey;
    if (key.isEmpty) return null;

    try {
      final url =
          'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=${Uri.encodeComponent(placeId)}'
          '&fields=geometry,formatted_address,address_components'
          '&key=$key';
      final res = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final data = res.data;
      if (data == null) return null;
      final status = data['status'] as String?;
      if (status != 'OK') return null;
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) return null;
      final geometry = result['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      if (location == null) return null;
      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final formattedAddress = result['formatted_address'] as String?;
      String? pincode;
      final components = result['address_components'] as List<dynamic>?;
      if (components != null) {
        for (final c in components) {
          if (c is Map &&
              (c['types'] as List?)?.contains('postal_code') == true) {
            pincode = c['long_name'] as String?;
            break;
          }
        }
      }
      return PlaceDetails(
        lat: lat,
        lng: lng,
        formattedAddress: formattedAddress,
        pincode: pincode,
      );
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }
}
