// Reusable Pin Destination Map – used by Change Destination, Add Task, etc.
// Full-screen map: tap or long-press to drop pin, reverse-geocode, confirm.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/utils/snackbar_utils.dart';

class PinDestinationResult {
  final double lat;
  final double lng;
  final String address;
  final String? pincode;
  final String? city;

  const PinDestinationResult({
    required this.lat,
    required this.lng,
    required this.address,
    this.pincode,
    this.city,
  });
}

class PinDestinationMapScreen extends StatefulWidget {
  /// Initial center (e.g. current location). If null, uses default.
  final LatLng? initialCenter;

  /// Optional initial pin (e.g. existing destination).
  final LatLng? initialPin;

  const PinDestinationMapScreen({
    super.key,
    this.initialCenter,
    this.initialPin,
  });

  @override
  State<PinDestinationMapScreen> createState() =>
      _PinDestinationMapScreenState();
}

class _PinDestinationMapScreenState extends State<PinDestinationMapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  LatLng? _pinnedLocation;
  String _pinnedAddress = '';
  String? _pinnedPincode;
  String? _pinnedCity;
  bool _loadingAddress = false;
  bool _loadingCurrentLocation = true;

  // Location search.
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _resolvingPlace = false;
  String? _searchSessionToken;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    if (widget.initialPin != null) {
      _pinnedLocation = widget.initialPin;
      _reverseGeocode(
        widget.initialPin!.latitude,
        widget.initialPin!.longitude,
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    // Start a billing session on the first keystroke of a search.
    _searchSessionToken ??=
        'pin-${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : (_pinnedLocation ?? widget.initialCenter);
    final results = await AddressResolutionService.searchPlaces(
      query,
      sessionToken: _searchSessionToken,
      lat: center?.latitude,
      lng: center?.longitude,
    );
    if (!mounted) return;
    // Ignore stale results if the query changed while we were waiting.
    if (_searchController.text.trim() != query) return;
    setState(() {
      _suggestions = results;
      _searching = false;
    });
  }

  Future<void> _onSuggestionTap(PlaceSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    _searchDebounce?.cancel();
    setState(() {
      _resolvingPlace = true;
      _suggestions = const [];
      _searchController.text = suggestion.description;
    });

    final place = await AddressResolutionService.placeDetails(
      suggestion.placeId,
      sessionToken: _searchSessionToken,
    );
    // The session ends when details are fetched; start fresh next search.
    _searchSessionToken = null;

    if (!mounted) return;
    if (place == null) {
      setState(() => _resolvingPlace = false);
      SnackBarUtils.showSnackBar(context, 'Could not load that location');
      return;
    }

    final target = LatLng(place.lat, place.lng);
    setState(() {
      _resolvingPlace = false;
      _pinnedLocation = target;
      _pinnedAddress = place.address.formattedAddress;
      _pinnedPincode = place.address.pincode;
      _pinnedCity = place.address.city;
      _loadingAddress = false;
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(target, 16),
    );
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _searchController.clear();
      _suggestions = const [];
      _searching = false;
    });
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _loadingCurrentLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _loadingCurrentLocation = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _loadingCurrentLocation = false;
        });
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCurrentLocation = false);
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    setState(() => _loadingAddress = true);
    try {
      final resolved = await AddressResolutionService.reverseGeocode(lat, lng);
      if (mounted && resolved != null) {
        setState(() {
          _pinnedAddress = resolved.formattedAddress;
          _pinnedPincode = resolved.pincode;
          _pinnedCity = resolved.city;
          _loadingAddress = false;
        });
      } else if (mounted) {
        setState(() {
          _pinnedAddress =
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
          _loadingAddress = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pinnedAddress =
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
          _loadingAddress = false;
        });
      }
    }
  }

  void _onMapTap(LatLng position) {
    if (_searchFocus.hasFocus || _suggestions.isNotEmpty) {
      FocusScope.of(context).unfocus();
      setState(() => _suggestions = const []);
    }
    setState(() {
      _pinnedLocation = position;
    });
    _reverseGeocode(position.latitude, position.longitude);
  }

  void _onConfirm() {
    if (_pinnedLocation == null) {
      SnackBarUtils.showSnackBar(
        context,
        'Please tap or long-press on the map to set destination',
      );
      return;
    }
    Navigator.of(context).pop(
      PinDestinationResult(
        lat: _pinnedLocation!.latitude,
        lng: _pinnedLocation!.longitude,
        address: _pinnedAddress.isNotEmpty ? _pinnedAddress : 'Dropped pin',
        pincode: _pinnedPincode,
        city: _pinnedCity,
      ),
    );
  }

  Widget _buildSearchBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search location',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _resolvingPlace || _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clearSearch,
                        )
                      : null),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: Colors.grey.shade200,
              ),
              itemBuilder: (context, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: Colors.grey,
                  ),
                  title: Text(
                    s.primaryText ?? s.description,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: s.secondaryText != null
                      ? Text(
                          s.secondaryText!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => _onSuggestionTap(s),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : (widget.initialCenter ?? const LatLng(11.0168, 76.9558));
    final target = _pinnedLocation ?? center;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin Destination'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _loadingCurrentLocation ? null : _fetchCurrentLocation,
            child: const Text('My Location'),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: target, zoom: 15),
            onMapCreated: (c) {
              _mapController = c;
              if (_currentPosition != null) {
                _mapController?.animateCamera(
                  CameraUpdate.newLatLng(
                    LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                  ),
                );
              }
            },
            onTap: _onMapTap,
            onLongPress: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: {
              if (_currentPosition != null)
                Marker(
                  markerId: const MarkerId('current'),
                  position: LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
                  infoWindow: const InfoWindow(title: 'My Location'),
                ),
              if (_pinnedLocation != null)
                Marker(
                  markerId: const MarkerId('destination'),
                  position: _pinnedLocation!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(
                    title: _pinnedAddress.isNotEmpty
                        ? _pinnedAddress
                        : 'Destination',
                  ),
                  draggable: true,
                  onDragEnd: (LatLng pos) {
                    setState(() => _pinnedLocation = pos);
                    _reverseGeocode(pos.latitude, pos.longitude);
                  },
                ),
            },
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _buildSearchBar(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tap or long-press to drop pin',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_pinnedLocation != null) ...[
                    const SizedBox(height: 8),
                    _loadingAddress
                        ? const SizedBox(
                            height: 24,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Text(
                            _pinnedAddress,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pinnedLocation != null ? _onConfirm : null,
                    icon: const Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Confirm Destination',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
