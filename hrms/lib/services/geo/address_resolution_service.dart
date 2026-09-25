import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:hrms/config/constants.dart';
import 'package:hrms/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    try {
      final googleResult = await reverseGeocodeWithGoogle(lat, lng);
      if (googleResult != null) return googleResult;
      return await _reverseGeocodeWithPlacemark(lat, lng)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
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
      receiveTimeout: const Duration(seconds: 3),
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

  /// Check if coordinates fall within branch geofence (with an accuracy buffer)
  static bool isInsideBranchGeofence(
    double lat,
    double lng,
    Map<String, dynamic>? branchData, {
    double bufferM = 30.0,
  }) {
    if (branchData == null) return false;
    final geofenceRaw = branchData['geofence'];
    final geofence =
        geofenceRaw is Map ? Map<String, dynamic>.from(geofenceRaw) : null;

    // Check multiple locations in geofence.locations[]
    if (geofence != null && geofence['locations'] is List) {
      final locs = geofence['locations'] as List;
      for (final item in locs) {
        if (item is! Map) continue;
        final loc = Map<String, dynamic>.from(item);
        final plat = (loc['latitude'] as num?)?.toDouble();
        final plng = (loc['longitude'] as num?)?.toDouble();
        final radius = (loc['radius'] as num?)?.toDouble() ?? 100.0;
        if (plat == null || plng == null) continue;
        final d = gl.Geolocator.distanceBetween(lat, lng, plat, plng);
        if (d <= radius + bufferM) return true;
      }
    }

    // Check main circle in geofence
    if (geofence != null) {
      final plat = (geofence['latitude'] as num?)?.toDouble();
      final plng = (geofence['longitude'] as num?)?.toDouble();
      final radius = (geofence['radius'] as num?)?.toDouble() ?? 100.0;
      if (plat != null && plng != null) {
        final d = gl.Geolocator.distanceBetween(lat, lng, plat, plng);
        if (d <= radius + bufferM) return true;
      }
    }

    // Check legacy branchData top-level
    final legacyLat = (branchData['latitude'] as num?)?.toDouble();
    final legacyLng = (branchData['longitude'] as num?)?.toDouble();
    final legacyRadius = (branchData['radius'] as num?)?.toDouble() ?? 100.0;
    if (legacyLat != null && legacyLng != null) {
      final d = gl.Geolocator.distanceBetween(lat, lng, legacyLat, legacyLng);
      if (d <= legacyRadius + bufferM) return true;
    }

    return false;
  }

  /// Construct verified address snapshot from branch data
  static ResolvedAddress? resolveBranchAddress(Map<String, dynamic> branchData) {
    final branchName = branchData['branchName']?.toString().trim();
    final rawAddr = branchData['address'];
    String? street;
    String? city;
    String? state;
    String? pincode;
    String? country;

    if (rawAddr is Map) {
      final m = Map<String, dynamic>.from(rawAddr);
      street = m['street']?.toString().trim();
      city = m['city']?.toString().trim();
      state = m['state']?.toString().trim();
      pincode = (m['zip'] ?? m['pincode'])?.toString().trim();
      country = m['country']?.toString().trim();
    } else if (rawAddr is String && rawAddr.trim().isNotEmpty) {
      street = rawAddr.trim();
    }

    final parts = <String>[];
    if (branchName != null && branchName.isNotEmpty) parts.add(branchName);
    if (street != null && street.isNotEmpty) parts.add(street);
    if (city != null && city.isNotEmpty) parts.add(city);
    if (state != null && state.isNotEmpty) parts.add(state);
    if (pincode != null && pincode.isNotEmpty) parts.add(pincode);

    if (parts.isEmpty) return null;

    final formatted = parts.join(', ');
    return ResolvedAddress(
      formattedAddress: formatted,
      area: street ?? branchName,
      city: city ?? state,
      pincode: pincode,
      state: state,
      country: country,
      fromGoogleApi: false,
    );
  }

  /// Resolves punch location address. If the position is within the branch geofence,
  /// snaps to the verified office/branch address instead of drifting street coordinates.
  static Future<ResolvedAddress?> resolvePunchLocationAddress(
    double lat,
    double lng, {
    Map<String, dynamic>? branchData,
  }) async {
    if (branchData != null && isInsideBranchGeofence(lat, lng, branchData)) {
      final branchAddr = resolveBranchAddress(branchData);
      if (branchAddr != null && branchAddr.formattedAddress.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[AddressResolution] Inside branch geofence -> snapped to branch address: ${branchAddr.formattedAddress}',
          );
        }
        return branchAddr;
      }
    }
    return reverseGeocodeForUi(lat, lng);
  }

  /// Address for a GPS tracking point, from the phone's own (free) geocoder —
  /// never the billed Google Geocoding API. Tracking points only carry the
  /// address as a label, so per-point Google lookups were pure cost.
  static Future<ResolvedAddress?> reverseGeocodeForTracking(
    double lat,
    double lng,
  ) async {
    final cached = await _cacheGet(lat, lng);
    if (cached != null) return cached;
    try {
      final r = await _reverseGeocodeWithPlacemark(lat, lng)
          .timeout(const Duration(seconds: 3));
      if (r != null) await _cachePut(lat, lng, r);
      return r;
    } catch (_) {
      return null;
    }
  }

  // ── Address cache ───────────────────────────────────────────────────────────
  // Addresses don't change, and staff hit the same places daily (office, customer
  // sites). Coordinates are rounded to 4 decimals (~11 m) and kept on the phone,
  // so each spot is looked up once instead of on every punch/visit.
  static const String _cachePrefix = 'geo_addr_v1:';
  static const String _cacheIndexKey = 'geo_addr_v1_index';
  static const int _cacheMax = 400;
  static final Map<String, ResolvedAddress> _mem = {};

  static String _cacheKey(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  static Future<ResolvedAddress?> _cacheGet(double lat, double lng) async {
    final k = _cacheKey(lat, lng);
    final hit = _mem[k];
    if (hit != null) return hit;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$k');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final r = ResolvedAddress(
        formattedAddress: m['f'] as String,
        area: m['a'] as String?,
        city: m['c'] as String?,
        pincode: m['p'] as String?,
        state: m['s'] as String?,
        country: m['n'] as String?,
        fromGoogleApi: m['g'] == true,
      );
      _mem[k] = r;
      return r;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cachePut(double lat, double lng, ResolvedAddress r) async {
    final k = _cacheKey(lat, lng);
    _mem[k] = r;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_cachePrefix$k',
        jsonEncode({
          'f': r.formattedAddress,
          'a': r.area,
          'c': r.city,
          'p': r.pincode,
          's': r.state,
          'n': r.country,
          'g': r.fromGoogleApi,
        }),
      );
      final index = prefs.getStringList(_cacheIndexKey) ?? <String>[];
      index.remove(k);
      index.add(k);
      while (index.length > _cacheMax) {
        await prefs.remove('$_cachePrefix${index.removeAt(0)}');
      }
      await prefs.setStringList(_cacheIndexKey, index);
    } catch (_) {}
  }

  /// Google Geocoding API only. Use when you must send the same address the user
  /// sees from Google to the backend. Returns null if the key is invalid / API error.
  /// Answers from the on-device cache first; only a new spot is sent to Google.
  static Future<ResolvedAddress?> reverseGeocodeWithGoogle(
    double lat,
    double lng, {
    Duration receiveTimeout = const Duration(seconds: 4),
  }) async {
    final cached = await _cacheGet(lat, lng);
    if (cached != null && cached.fromGoogleApi) return cached;
    final fresh = await _reverseGeocodeWithGoogleUncached(
      lat,
      lng,
      receiveTimeout: receiveTimeout,
    );
    if (fresh != null) await _cachePut(lat, lng, fresh);
    return fresh;
  }

  static Future<ResolvedAddress?> _reverseGeocodeWithGoogleUncached(
    double lat,
    double lng, {
    Duration receiveTimeout = const Duration(seconds: 4),
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

      final response = await _dio
          .get<Map<String, dynamic>>(
            url,
            options: Options(
              sendTimeout: const Duration(seconds: 3),
              receiveTimeout: receiveTimeout,
            ),
          )
          .timeout(const Duration(seconds: 4));
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
      final placemarks = await placemarkFromCoordinates(
        lat,
        lng,
      ).timeout(const Duration(seconds: 3));
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
