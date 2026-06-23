import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:geocoding/geocoding.dart';
import 'package:hrms/config/constants.dart';
import 'package:hrms/services/api_client.dart';

/// Address resolved for the given coordinates. When [fromGoogleApi] is true,
/// [formattedAddress] is Google’s formatted address for that lat/lng — this is
/// what should be sent to the backend (`address` / `fullAddress`).
class ResolvedAddress {
  final String formattedAddress;
  final String? area;
  final String? city;
  final String? pincode;
  final String? state;
  final String? country;
  final bool fromGoogleApi;

  const ResolvedAddress({
    required this.formattedAddress,
    this.area,
    this.city,
    this.pincode,
    this.state,
    this.country,
    required this.fromGoogleApi,
  });
}

/// A place suggestion from Google Places Autocomplete.
class PlaceSuggestion {
  final String placeId;
  final String description;
  final String? primaryText;
  final String? secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    this.primaryText,
    this.secondaryText,
  });
}

/// Resolved coordinates + address for a selected place.
class PlaceLocation {
  final double lat;
  final double lng;
  final ResolvedAddress address;

  const PlaceLocation({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

class AddressResolutionService {
  static final Dio _dio = ApiClient().dio;

  /// Reverse-geocode via **Google Geocoding API** first (best address for lat/lng),
  /// then device placemark if the key is missing or Google returns an error.
  static Future<ResolvedAddress?> reverseGeocode(double lat, double lng) async {
    final googleResult = await reverseGeocodeWithGoogle(lat, lng);
    if (googleResult != null) return googleResult;
    return _reverseGeocodeWithPlacemark(lat, lng);
  }

  /// Faster reverse-geocode for attendance/check-in UI where responsiveness
  /// matters more than waiting a long time for a perfect network result.
  static Future<ResolvedAddress?> reverseGeocodeForUi(
    double lat,
    double lng,
  ) async {
    final googleResult = await reverseGeocodeWithGoogle(
      lat,
      lng,
      receiveTimeout: const Duration(seconds: 4),
    );
    if (googleResult != null) return googleResult;
    try {
      return await _reverseGeocodeWithPlacemark(
        lat,
        lng,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  /// Google Geocoding API only. Use when you must send the same address the user
  /// sees from Google to the backend. Returns null if the key is invalid / API error.
  static Future<ResolvedAddress?> reverseGeocodeWithGoogle(
    double lat,
    double lng, {
    Duration receiveTimeout = const Duration(seconds: 12),
  }) async {
    final key = AppConstants.googleMapsApiKey.trim();
    if (key.isEmpty) return null;

    try {
      // No result_type filter: strict filters often yield ZERO_RESULTS; Google
      // returns most-specific matches first. We then pick best geometry.location_type.
      final lang =
          SchedulerBinding.instance.platformDispatcher.locale.languageCode;
      final langParam =
          lang.isNotEmpty ? '&language=${Uri.encodeQueryComponent(lang)}' : '';
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=$lat,$lng'
          '$langParam'
          '&key=$key';

      final response = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(receiveTimeout: receiveTimeout),
      );
      final data = response.data;
      if (data == null) return null;

      final status = data['status'] as String?;
      if (status != 'OK') {
        if (kDebugMode) {
          debugPrint(
            '[AddressResolution] Google Geocoding status=$status '
            'error_message=${data['error_message']}',
          );
        }
        return null;
      }

      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final best = _pickBestGoogleResult(results);
      if (best == null) return null;

      final formattedAddress =
          (best['formatted_address'] as String?)?.trim();
      if (formattedAddress == null || formattedAddress.isEmpty) return null;

      final components =
          (best['address_components'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const <Map<String, dynamic>>[];

      return ResolvedAddress(
        formattedAddress: formattedAddress,
        area:
            _componentValue(components, const [
              'sublocality_level_1',
              'sublocality',
              'neighborhood',
              'premise',
            ]) ??
            _componentValue(components, const ['route']),
        city: _componentValue(components, const [
          'locality',
          'postal_town',
          'administrative_area_level_2',
          'administrative_area_level_1',
        ]),
        pincode: _componentValue(components, const ['postal_code']),
        state: _componentValue(
          components,
          const ['administrative_area_level_1'],
        ),
        country: _componentValue(components, const ['country']),
        fromGoogleApi: true,
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[AddressResolution] Google Geocoding network: $e');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[AddressResolution] Google Geocoding: $e');
      return null;
    }
  }

  /// Prefer ROOFTOP / interpolated street over approximate area centroids.
  static Map<String, dynamic>? _pickBestGoogleResult(List<dynamic> results) {
    final maps = <Map<String, dynamic>>[];
    for (final e in results) {
      if (e is Map<String, dynamic>) maps.add(e);
    }
    if (maps.isEmpty) return null;
    maps.sort((a, b) {
      final ta = _locationTypeRank(_geometryLocationType(a));
      final tb = _locationTypeRank(_geometryLocationType(b));
      if (ta != tb) return ta.compareTo(tb);
      final pa = a['partial_match'] == true ? 1 : 0;
      final pb = b['partial_match'] == true ? 1 : 0;
      if (pa != pb) return pa.compareTo(pb);
      return 0;
    });
    return maps.first;
  }

  static String? _geometryLocationType(Map<String, dynamic> r) {
    final g = r['geometry'];
    if (g is! Map) return null;
    return g['location_type'] as String?;
  }

  /// Google precision rank for the snapped point (lower = closer to exact lat/lng).
  static int _locationTypeRank(String? t) {
    switch (t) {
      case 'ROOFTOP':
        return 0;
      case 'RANGE_INTERPOLATED':
        return 1;
      case 'GEOMETRIC_CENTER':
        return 2;
      case 'APPROXIMATE':
        return 3;
      default:
        return 4;
    }
  }

  static Future<ResolvedAddress?> _reverseGeocodeWithPlacemark(
    double lat,
    double lng,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;
      final parts = <String>[
        if (p.name != null && p.name!.isNotEmpty) p.name!,
        if (p.street != null && p.street!.isNotEmpty && p.street != p.name)
          p.street!,
        if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
        if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
          p.administrativeArea!,
        if (p.postalCode != null && p.postalCode!.isNotEmpty) p.postalCode!,
        if (p.country != null && p.country!.isNotEmpty) p.country!,
      ];

      final formattedAddress = parts.join(', ').trim();
      if (formattedAddress.isEmpty) return null;

      return ResolvedAddress(
        formattedAddress: formattedAddress,
        area: p.subLocality ?? p.locality ?? p.name,
        city: p.locality ?? p.administrativeArea,
        pincode: p.postalCode,
        state: p.administrativeArea,
        country: p.country,
        fromGoogleApi: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Forward search via **Google Places Autocomplete**. Returns place
  /// suggestions for the typed [query]. Returns an empty list if the key is
  /// missing or the API errors.
  ///
  /// Pass a [sessionToken] (a stable random string per typing session) to group
  /// autocomplete + details calls for cheaper Google billing. Optionally bias
  /// results around [lat]/[lng].
  static Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    String? sessionToken,
    double? lat,
    double? lng,
    Duration receiveTimeout = const Duration(seconds: 8),
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final key = AppConstants.googleMapsApiKey.trim();
    if (key.isEmpty) return const [];

    try {
      final lang =
          SchedulerBinding.instance.platformDispatcher.locale.languageCode;
      final langParam =
          lang.isNotEmpty ? '&language=${Uri.encodeQueryComponent(lang)}' : '';
      final sessionParam = (sessionToken != null && sessionToken.isNotEmpty)
          ? '&sessiontoken=${Uri.encodeQueryComponent(sessionToken)}'
          : '';
      final biasParam = (lat != null && lng != null)
          ? '&location=$lat,$lng&radius=50000'
          : '';
      final url =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeQueryComponent(trimmed)}'
          '$langParam'
          '$sessionParam'
          '$biasParam'
          '&key=$key';

      final response = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(receiveTimeout: receiveTimeout),
      );
      final data = response.data;
      if (data == null) return const [];

      final status = data['status'] as String?;
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        if (kDebugMode) {
          debugPrint(
            '[AddressResolution] Places Autocomplete status=$status '
            'error_message=${data['error_message']}',
          );
        }
        return const [];
      }

      final predictions = data['predictions'] as List<dynamic>?;
      if (predictions == null || predictions.isEmpty) return const [];

      final out = <PlaceSuggestion>[];
      for (final p in predictions) {
        if (p is! Map<String, dynamic>) continue;
        final placeId = (p['place_id'] as String?)?.trim();
        final description = (p['description'] as String?)?.trim();
        if (placeId == null || placeId.isEmpty) continue;
        if (description == null || description.isEmpty) continue;
        final structured = p['structured_formatting'];
        out.add(
          PlaceSuggestion(
            placeId: placeId,
            description: description,
            primaryText: structured is Map
                ? (structured['main_text'] as String?)?.trim()
                : null,
            secondaryText: structured is Map
                ? (structured['secondary_text'] as String?)?.trim()
                : null,
          ),
        );
      }
      return out;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[AddressResolution] Places Autocomplete network: $e');
      }
      return const [];
    } catch (e) {
      if (kDebugMode) debugPrint('[AddressResolution] Places Autocomplete: $e');
      return const [];
    }
  }

  /// Resolve a [placeId] (from [searchPlaces]) to coordinates + address via
  /// **Google Place Details**. Returns null if the key is missing or it errors.
  static Future<PlaceLocation?> placeDetails(
    String placeId, {
    String? sessionToken,
    Duration receiveTimeout = const Duration(seconds: 8),
  }) async {
    final id = placeId.trim();
    if (id.isEmpty) return null;

    final key = AppConstants.googleMapsApiKey.trim();
    if (key.isEmpty) return null;

    try {
      final lang =
          SchedulerBinding.instance.platformDispatcher.locale.languageCode;
      final langParam =
          lang.isNotEmpty ? '&language=${Uri.encodeQueryComponent(lang)}' : '';
      final sessionParam = (sessionToken != null && sessionToken.isNotEmpty)
          ? '&sessiontoken=${Uri.encodeQueryComponent(sessionToken)}'
          : '';
      final url =
          'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=${Uri.encodeQueryComponent(id)}'
          '&fields=geometry,formatted_address,address_component,name'
          '$langParam'
          '$sessionParam'
          '&key=$key';

      final response = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(receiveTimeout: receiveTimeout),
      );
      final data = response.data;
      if (data == null) return null;

      final status = data['status'] as String?;
      if (status != 'OK') {
        if (kDebugMode) {
          debugPrint(
            '[AddressResolution] Place Details status=$status '
            'error_message=${data['error_message']}',
          );
        }
        return null;
      }

      final result = data['result'];
      if (result is! Map<String, dynamic>) return null;

      final geometry = result['geometry'];
      final location = geometry is Map ? geometry['location'] : null;
      if (location is! Map) return null;
      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final components =
          (result['address_components'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const <Map<String, dynamic>>[];

      final formattedAddress =
          (result['formatted_address'] as String?)?.trim() ??
          (result['name'] as String?)?.trim() ??
          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

      final address = ResolvedAddress(
        formattedAddress: formattedAddress,
        area:
            _componentValue(components, const [
              'sublocality_level_1',
              'sublocality',
              'neighborhood',
              'premise',
            ]) ??
            _componentValue(components, const ['route']),
        city: _componentValue(components, const [
          'locality',
          'postal_town',
          'administrative_area_level_2',
          'administrative_area_level_1',
        ]),
        pincode: _componentValue(components, const ['postal_code']),
        state: _componentValue(
          components,
          const ['administrative_area_level_1'],
        ),
        country: _componentValue(components, const ['country']),
        fromGoogleApi: true,
      );

      return PlaceLocation(lat: lat, lng: lng, address: address);
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[AddressResolution] Place Details network: $e');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[AddressResolution] Place Details: $e');
      return null;
    }
  }

  static String? _componentValue(
    List<Map<String, dynamic>> components,
    List<String> desiredTypes,
  ) {
    for (final component in components) {
      final types = (component['types'] as List<dynamic>?)?.cast<String>() ?? [];
      for (final type in desiredTypes) {
        if (types.contains(type)) {
          final value = (component['long_name'] as String?)?.trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }
    }
    return null;
  }
}
