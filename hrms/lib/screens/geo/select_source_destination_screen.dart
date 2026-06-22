// Select Source & Destination – full-screen step before the map.
// User sees and confirms source (GPS) and destination (customer / editable), then continues to Start Ride (map).

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:hrms/services/geo/places_service.dart';
import 'package:hrms/screens/geo/start_ride_screen.dart';
import 'package:hrms/widgets/app_tab_loader.dart';

class SelectSourceDestinationScreen extends StatefulWidget {
  final Task task;

  const SelectSourceDestinationScreen({super.key, required this.task});

  @override
  State<SelectSourceDestinationScreen> createState() =>
      _SelectSourceDestinationScreenState();
}

class _SelectSourceDestinationScreenState
    extends State<SelectSourceDestinationScreen> {
  Task get _task => widget.task;

  Customer? _customer;
  bool _loadingCustomer = true;

  String _sourceAddress = 'Getting your location...';
  bool _loadingSource = true;

  String _destinationAddress = '';
  bool _loadingDestination = true;

  /// When staff changes destination via search, we keep lat/lng so StartRide uses it (no fallback to client).
  LatLng? _selectedDestinationLatLng;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_task.customer != null) {
      setState(() {
        _customer = _task.customer;
        _loadingCustomer = false;
      });
      _lockSourceAndDestination();
      return;
    }
    if (_task.customerId == null || _task.customerId!.isEmpty) {
      setState(() {
        _loadingCustomer = false;
        _destinationAddress = 'No customer address';
        _loadingDestination = false;
      });
      _lockSourceOnly();
      return;
    }
    try {
      final c = await CustomerService().getCustomerById(_task.customerId!);
      if (mounted) {
        setState(() {
          _customer = c;
          _loadingCustomer = false;
        });
        _lockSourceAndDestination();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingCustomer = false;
          _destinationAddress = 'Could not load address';
          _loadingDestination = false;
        });
        _lockSourceOnly();
      }
    }
  }

  Future<void> _lockSourceOnly() async {
    await _fetchCurrentLocation();
    if (mounted) _reverseGeocodeSource();
  }

  Future<void> _lockSourceAndDestination() async {
    await _fetchCurrentLocation();
    if (mounted) _reverseGeocodeSource();
    if (_customer != null) {
      final address =
          '${_customer!.address}, ${_customer!.city}, ${_customer!.pincode}';
      setState(() {
        _destinationAddress = address;
        _loadingDestination = true;
      });
      _geocodeDestination(address);
    } else {
      setState(() => _loadingDestination = false);
    }
  }

  Future<void> _fetchCurrentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _sourceAddress = 'Location permission denied';
          _loadingSource = false;
        });
      }
      return;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) setState(() => _loadingSource = false);
      if (mounted) {
        _reverseGeocodeSourceAt(position.latitude, position.longitude);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sourceAddress = 'Could not get location';
          _loadingSource = false;
        });
      }
    }
  }

  Future<void> _reverseGeocodeSource() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _reverseGeocodeSourceAt(position.latitude, position.longitude);
    } catch (_) {
      if (mounted) setState(() => _sourceAddress = 'Your current location');
    }
  }

  Future<void> _reverseGeocodeSourceAt(double lat, double lng) async {
    try {
      final resolved = await AddressResolutionService.reverseGeocode(lat, lng);
      if (mounted && resolved != null) {
        setState(() {
          _sourceAddress = resolved.formattedAddress;
          if (_sourceAddress.isEmpty) _sourceAddress = 'Your current location';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sourceAddress = 'Your current location');
    }
  }

  Future<void> _geocodeDestination(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isEmpty) {
        if (mounted) setState(() => _loadingDestination = false);
        return;
      }
      if (mounted) setState(() => _loadingDestination = false);
    } catch (_) {
      if (mounted) setState(() => _loadingDestination = false);
    }
  }

  void _onChangeDestinationTap() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DestinationSearchSheet(
        currentLat: null,
        currentLng: null,
        onSelect: (PlaceDetails details) {
          Navigator.pop(context);
          setState(() {
            _destinationAddress =
                details.formattedAddress ??
                '${details.lat.toStringAsFixed(5)}, ${details.lng.toStringAsFixed(5)}';
            _selectedDestinationLatLng = LatLng(details.lat, details.lng);
          });
        },
      ),
    );
  }

  void _onContinueToMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StartRideScreen(
          task: _task,
          initialDestinationAddress:
              _destinationAddress.isNotEmpty &&
                  _destinationAddress != 'No customer address' &&
                  _destinationAddress != 'Could not load address'
              ? _destinationAddress
              : null,
          initialDestinationLatLng: _selectedDestinationLatLng,
        ),
      ),
    );
  }

  bool get _canContinue {
    return _sourceAddress.isNotEmpty &&
        _sourceAddress != 'Getting your location...' &&
        _sourceAddress != 'Location permission denied' &&
        _destinationAddress.isNotEmpty &&
        _destinationAddress != 'No customer address' &&
        _destinationAddress != 'Could not load address' &&
        !_loadingSource &&
        !_loadingDestination;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          'Select Source & Destination',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top card: Source & Destination (Uber-like, at TOP).
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildTopRow(
                    icon: Icons.gps_fixed_rounded,
                    iconColor: AppColors.primary,
                    label: 'Your location',
                    value: _sourceAddress,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Auto',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 24, color: Colors.grey.shade200),
                  _buildTopRow(
                    icon: Icons.location_on_rounded,
                    iconColor: AppColors.error,
                    label: 'Destination',
                    value: _destinationAddress.isEmpty
                        ? 'Set destination'
                        : _destinationAddress,
                    trailing: TextButton.icon(
                      onPressed: _loadingDestination
                          ? null
                          : _onChangeDestinationTap,
                      icon: const Icon(Icons.swap_vert_rounded, size: 20),
                      label: const Text('Change'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Confirm your trip details',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(height: 12),
            // Taller form area for source/destination cards.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 120,
                      child: _buildCard(
                        icon: Icons.gps_fixed_rounded,
                        iconColor: AppColors.primary,
                        label: 'Source',
                        value: _sourceAddress,
                        subtitle: 'Your current location',
                        showChange: false,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 120,
                      child: _buildCard(
                        icon: Icons.location_on_rounded,
                        iconColor: AppColors.error,
                        label: 'Destination',
                        value: _destinationAddress.isEmpty
                            ? 'Set destination'
                            : _destinationAddress,
                        subtitle: _customer?.customerName ?? 'Customer',
                        showChange: true,
                        onChange: _onChangeDestinationTap,
                        loading: _loadingDestination,
                      ),
                    ),
                    if (_loadingCustomer || _loadingSource) ...[
                      const SizedBox(height: 24),
                      const Center(child: AppTabLoader()),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _canContinue ? _onContinueToMap : null,
                    icon: const Icon(
                      Icons.map_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    label: const Text(
                      'Continue to Map',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    String? subtitle,
    required bool showChange,
    VoidCallback? onChange,
    bool loading = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
          if (showChange)
            TextButton.icon(
              onPressed: loading ? null : onChange,
              icon: const Icon(Icons.search_rounded, size: 20),
              label: const Text('Change'),
            ),
        ],
      ),
    );
  }
}

// Reuse the same search sheet as Start Ride (inline copy to avoid importing from start_ride_screen).
class _DestinationSearchSheet extends StatefulWidget {
  final double? currentLat;
  final double? currentLng;
  final void Function(PlaceDetails) onSelect;

  const _DestinationSearchSheet({
    this.currentLat,
    this.currentLng,
    required this.onSelect,
  });

  @override
  State<_DestinationSearchSheet> createState() =>
      _DestinationSearchSheetState();
}

class _DestinationSearchSheetState extends State<_DestinationSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<PlacePrediction> _predictions = [];
  bool _searching = false;
  bool _fetchingPlace = false;
  int _debounce = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _debounce++;
    final current = _debounce;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _debounce != current) return;
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    setState(() => _searching = true);
    final list = await PlacesService.autocomplete(
      query,
      lat: widget.currentLat,
      lng: widget.currentLng,
    );
    if (mounted) {
      setState(() {
        _predictions = list;
        _searching = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildPredictionTile(PlacePrediction p) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.place_rounded, size: 20, color: Colors.grey.shade600),
      title: Text(
        p.mainText,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: p.secondaryText.isNotEmpty
          ? Text(
              p.secondaryText,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            )
          : null,
      onTap: () async {
        setState(() => _fetchingPlace = true);
        PlaceDetails? details;
        try {
          details = await PlacesService.getPlaceDetails(p.placeId);
        } catch (_) {
          if (mounted) {
            SnackBarUtils.showSnackBar(
              context,
              'Could not get coordinates. Try another result or set destination on the map in the next step.',
            );
          }
        }
        if (mounted) setState(() => _fetchingPlace = false);
        if (details != null && mounted) widget.onSelect(details);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Select Destination',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search cities, areas, streets, landmarks...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                autofocus: true,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _searching || _fetchingPlace
                  ? const Center(child: AppTabLoader())
                  : _predictions.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.trim().isEmpty
                            ? 'Type to search address'
                            : 'No results',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _predictions.length,
                      itemBuilder: (context, index) {
                        final p = _predictions[index];
                        return _buildPredictionTile(p);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
