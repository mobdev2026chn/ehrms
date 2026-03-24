// Reusable Pin Destination Map – used by Change Destination, Add Task, etc.
// Full-screen map: tap or long-press to drop pin, reverse-geocode, confirm.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';

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
    setState(() {
      _pinnedLocation = position;
    });
    _reverseGeocode(position.latitude, position.longitude);
  }

  void _onConfirm() {
    if (_pinnedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please tap or long-press on the map to set destination',
          ),
        ),
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
