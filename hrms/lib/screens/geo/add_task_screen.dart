// Add Task – full-screen form, Request module UI patterns.
// Fields: Task Title, Customer (searchable), Description, Source, Destination.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/geo/places_service.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/screens/geo/live_tracking_screen.dart';
import 'package:hrms/screens/geo/pin_destination_map_screen.dart';
import 'package:hrms/screens/notifications/notifications_screen.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/widgets/app_tab_loader.dart';

class AddTaskScreen extends StatefulWidget {
  final String staffId;

  const AddTaskScreen({super.key, required this.staffId});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskTitleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sourceController = TextEditingController();
  final _destinationController = TextEditingController();
  LatLng? _destinationLatLng;
  String? _destinationPincode;
  final _customerSearchController = TextEditingController();

  Customer? _selectedCustomer;
  List<Customer> _allCustomers = [];
  List<Customer> _filteredCustomers = [];
  bool _loadingCustomers = true;
  bool _submitting = false;
  bool _showCustomerDropdown = false;
  bool _showDestinationSuggestions = false;
  final FocusNode _customerFocusNode = FocusNode();
  List<PlacePrediction> _destinationPredictions = [];
  final String _sourceAddress = '';
  String _destinationAddress = '';
  DateTime? _expectedCompletionDate;
  final bool _useCurrentLocationForSource = true;
  bool _useCustomerAddressAsDestination = false;
  bool _destinationChangedByUser = false;
  String _currentLocationAddress = '';
  bool _loadingCurrentLocation = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _customerSearchController.addListener(_onCustomerSearchChanged);
    _customerFocusNode.addListener(() {
      if (!_customerFocusNode.hasFocus) {
        setState(() => _showCustomerDropdown = false);
      }
    });
    if (_useCurrentLocationForSource) _fetchCurrentLocationAddress();
  }

  Future<void> _fetchCurrentLocationAddress() async {
    setState(() => _loadingCurrentLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _currentLocationAddress = 'Location permission denied';
            _loadingCurrentLocation = false;
          });
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final resolved = await AddressResolutionService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      if (mounted && resolved != null) {
        setState(() {
          _currentLocationAddress = resolved.formattedAddress.isNotEmpty
              ? resolved.formattedAddress
              : 'Current location (GPS)';
          _loadingCurrentLocation = false;
        });
      } else if (mounted) {
        setState(() {
          _currentLocationAddress = 'Current location (GPS)';
          _loadingCurrentLocation = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _currentLocationAddress = 'Current location (GPS)';
          _loadingCurrentLocation = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _customerFocusNode.dispose();
    _taskTitleController.dispose();
    _descriptionController.dispose();
    _sourceController.dispose();
    _destinationController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _loadingCustomers = true);
    try {
      final list = await CustomerService().getAllCustomers();
      if (mounted) {
        setState(() {
          _allCustomers = list;
          _filteredCustomers = list;
          _loadingCustomers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingCustomers = false;
          _filteredCustomers = [];
        });
      }
    }
  }

  void _onCustomerSearchChanged() {
    final q = _customerSearchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredCustomers = _allCustomers;
      } else {
        _filteredCustomers = _allCustomers
            .where(
              (c) =>
                  c.customerName.toLowerCase().contains(q) ||
                  (c.address.toLowerCase().contains(q)),
            )
            .toList();
      }
    });
  }

  /// Figma "Keep the momentum" header banner.
  Widget _buildMomentumBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              bottom: -4,
              child: Icon(
                Icons.notes_rounded,
                size: 96,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Keep the momentum',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Organize your workflow by adding a clear title and priority.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Bold label above a field, matching the Figma form style.
  Widget _buildLabeledField(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
  }

  /// Clean white input (no prefix icon), label sits above via [_buildLabeledField].
  InputDecoration _cleanInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  /// Read-only "Assigned To" field — tasks are always assigned to the current
  /// staff (widget.staffId), shown as "Me" to match the Figma layout.
  Widget _buildAssignedToField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assigned To',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded,
                  size: 20, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Me',
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 22, color: Colors.grey.shade500),
            ],
          ),
        ),
      ],
    );
  }

  /// Description: only user-entered text. Source/destination are stored in sourceLocation/destinationLocation.
  String _buildDescription() {
    return _descriptionController.text.trim();
  }

  Future<void> _searchDestination(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _showDestinationSuggestions = false;
        _destinationPredictions = [];
      });
      return;
    }
    final list = await PlacesService.autocomplete(query);
    if (mounted) {
      setState(() {
        _destinationPredictions = list;
        _showDestinationSuggestions = true;
      });
    }
  }

  Future<void> _onDestinationSelected(PlaceDetails details) async {
    setState(() {
      _destinationAddress =
          details.formattedAddress ?? '${details.lat}, ${details.lng}';
      _destinationController.text = _destinationAddress;
      _destinationLatLng = LatLng(details.lat, details.lng);
      _destinationPincode = details.pincode;
      _destinationChangedByUser = true;
      _showDestinationSuggestions = false;
      _destinationPredictions = [];
    });
  }

  void _onCustomerSelected(Customer c) {
    setState(() {
      _selectedCustomer = c;
      _customerSearchController.text = c.customerName;
      _showCustomerDropdown = false;
      if (_useCustomerAddressAsDestination) {
        _applyCustomerAddressAsDestination(c);
      }
    });
  }

  void _applyCustomerAddressAsDestination(Customer c) {
    final addr = '${c.address}, ${c.city}, ${c.pincode}'.trim();
    _destinationController.text = addr;
    _destinationAddress = addr;
    _destinationPincode = c.pincode.isNotEmpty ? c.pincode : null;
    _destinationLatLng = null;
    _destinationChangedByUser = false;
  }

  Widget _buildDestinationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Destination',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        // Search location
        TextFormField(
          controller: _destinationController,
          style: TextStyle(fontSize: 13),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.pin_drop_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            hintText: 'Search address or place...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            suffixIcon: _destinationAddress.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear,
                      size: 20,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () => setState(() {
                      _destinationController.clear();
                      _destinationAddress = '';
                      _destinationLatLng = null;
                      _destinationPincode = null;
                      _destinationChangedByUser = false;
                    }),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          onChanged: (v) {
            if (v.length >= 3) {
              _searchDestination(v);
            } else {
              setState(() {
                _showDestinationSuggestions = false;
                _destinationPredictions = [];
              });
            }
          },
        ),
        if (_selectedCustomer != null) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _useCustomerAddressAsDestination,
            onChanged: (bool? value) {
              setState(() {
                _useCustomerAddressAsDestination = value ?? false;
                if (_useCustomerAddressAsDestination &&
                    _selectedCustomer != null) {
                  _applyCustomerAddressAsDestination(_selectedCustomer!);
                }
              });
            },
            title: Text(
              'Use customer address as destination',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
        if (_showDestinationSuggestions &&
            _destinationPredictions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _destinationPredictions.length,
              itemBuilder: (context, i) {
                final p = _destinationPredictions[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.pin_drop_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    p.mainText,
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  subtitle: p.secondaryText.isNotEmpty
                      ? Text(
                          p.secondaryText,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () async {
                    final details = await PlacesService.getPlaceDetails(
                      p.placeId,
                    );
                    if (details != null && mounted) {
                      await _onDestinationSelected(details);
                    }
                  },
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Select on Map - styled like Live Tracking "Change / Pin destination"
        TextButton.icon(
          onPressed: () async {
            Position? pos;
            try {
              pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              );
            } catch (_) {}
            final result = await Navigator.of(context)
                .push<PinDestinationResult>(
                  MaterialPageRoute(
                    builder: (context) => PinDestinationMapScreen(
                      initialCenter: pos != null
                          ? LatLng(pos.latitude, pos.longitude)
                          : null,
                      initialPin: _destinationLatLng,
                    ),
                  ),
                );
            if (result != null && mounted) {
              setState(() {
                _destinationLatLng = LatLng(result.lat, result.lng);
                _destinationAddress = result.address;
                _destinationController.text = result.address;
                _destinationPincode = result.pincode;
                _destinationChangedByUser = true;
              });
            }
          },
          icon: Icon(
            Icons.pin_drop_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          label: Text(
            'Select on Map',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            alignment: Alignment.centerLeft,
          ),
        ),
        if (_destinationAddress.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Selected: $_destinationAddress${_destinationPincode != null ? ' ($_destinationPincode)' : ''}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null || _selectedCustomer!.id == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a customer')));
      return;
    }
    if (_expectedCompletionDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select expected completion date')),
      );
      return;
    }
    final destAddr = _destinationAddress.isNotEmpty
        ? _destinationAddress
        : _destinationController.text.trim();
    if (destAddr.isEmpty && _destinationLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please search or pin destination')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final pickup = LatLng(position.latitude, position.longitude);

      LatLng dropoff;
      String? destPincode = _destinationPincode;
      if (_destinationLatLng != null) {
        dropoff = _destinationLatLng!;
      } else {
        List<Location> destLocs = [];
        try {
          destLocs = await locationFromAddress(destAddr);
        } catch (_) {}
        if (destLocs.isEmpty) {
          if (mounted) {
            setState(() => _submitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please search or pin destination on map'),
              ),
            );
          }
          return;
        }
        dropoff = LatLng(destLocs.first.latitude, destLocs.first.longitude);
        if (destPincode == null) {
          try {
            final resolved = await AddressResolutionService.reverseGeocode(
              dropoff.latitude,
              dropoff.longitude,
            );
            if (resolved?.pincode?.isNotEmpty == true) {
              destPincode = resolved!.pincode;
            }
          } catch (_) {}
        }
      }

      final destLocation = <String, dynamic>{
        'lat': dropoff.latitude,
        'lng': dropoff.longitude,
        'address': destAddr,
        'fullAddress': destAddr,
      };
      if (destPincode != null && destPincode.isNotEmpty) {
        destLocation['pincode'] = destPincode;
      }

      final task = await TaskService().createTask(
        taskTitle: _taskTitleController.text.trim(),
        description: _buildDescription(),
        assignedTo: widget.staffId,
        customerId: _selectedCustomer!.id!,
        expectedCompletionDate: _expectedCompletionDate!,
        status: 'assigned',
        sourceLocation: {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'address': _currentLocationAddress,
        },
        destinationLocation: destLocation,
      );
      if (!mounted) return;
      final taskWithCustomer = task.copyWith(customer: _selectedCustomer);

      await TaskService().updateTask(
        taskWithCustomer.id!,
        status: 'in_progress',
        startTime: DateTime.now(),
        startLat: pickup.latitude,
        startLng: pickup.longitude,
        sourceLocation: {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'address': _currentLocationAddress,
          'fullAddress': _currentLocationAddress,
        },
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LiveTrackingScreen(
            taskId: taskWithCustomer.taskId,
            taskMongoId: taskWithCustomer.id,
            pickupLocation: pickup,
            dropoffLocation: dropoff,
            task: taskWithCustomer,
          ),
        ),
      );
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final msg = e.response?.data is Map
            ? (e.response!.data as Map)['message'] as String?
            : null;
        final displayMsg =
            msg != null && !ErrorMessageUtils.isTechnicalMessage(msg)
            ? msg
            : ErrorMessageUtils.toUserFriendlyMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMsg),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessageUtils.toUserFriendlyMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'New Task',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none_rounded,
                color: AppColors.textPrimary, size: 26),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 4),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 22),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMomentumBanner(),
                    const SizedBox(height: 20),
                    _buildLabeledField(
                      'Task Title',
                      TextFormField(
                        controller: _taskTitleController,
                        decoration: _cleanInputDecoration(
                          'e.g., Design System Audit',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildCustomerField(),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildExpectedCompletionDateField()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildAssignedToField()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildLabeledField(
                      'Description',
                      TextFormField(
                        controller: _descriptionController,
                        decoration: _cleanInputDecoration(
                          'Briefly describe the tasks and objectives...',
                        ),
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSourceField(),
                    const SizedBox(height: 16),
                    _buildDestinationField(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.task_alt_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                    label: Text(
                      _submitting ? 'Creating...' : 'Create Task',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildExpectedCompletionDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Due Date',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _expectedCompletionDate ?? now,
              firstDate: now,
              lastDate: now.add(const Duration(days: 365)),
            );
            if (picked != null && mounted) {
              setState(() => _expectedCompletionDate = picked);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.calendar_today_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              labelText: 'Select date',
              labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            child: Text(
              _expectedCompletionDate == null
                  ? ''
                  : '${_expectedCompletionDate!.day.toString().padLeft(2, '0')}/${_expectedCompletionDate!.month.toString().padLeft(2, '0')}/${_expectedCompletionDate!.year}',
              style: TextStyle(
                fontSize: 14,
                color: _expectedCompletionDate == null
                    ? Colors.grey.shade500
                    : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Source (always current GPS)',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.gps_fixed_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: _loadingCurrentLocation
                    ? Text(
                        'Getting your location...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      )
                    : Text(
                        _currentLocationAddress,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          focusNode: _customerFocusNode,
          controller: _customerSearchController,
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.person_rounded,
              size: 22,
              color: AppColors.primary,
            ),
            hintText: 'Search customer by name or address',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          onTap: () => setState(() => _showCustomerDropdown = true),
          onChanged: (_) => setState(() => _showCustomerDropdown = true),
        ),
        if (_showCustomerDropdown) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _loadingCustomers
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: AppTabLoader()),
                  )
                : _filteredCustomers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No customers found',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredCustomers.length,
                    itemBuilder: (context, i) {
                      final c = _filteredCustomers[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          c.customerName,
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${c.address}, ${c.city}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _onCustomerSelected(c),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
}
