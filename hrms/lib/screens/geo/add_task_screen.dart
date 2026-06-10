// Add Task – full-screen form, Request module UI patterns.
// Fields: Task Title, Customer (searchable), completion-date range, Description,
// Source. Destination is derived from the selected customer's address.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/screens/geo/pin_destination_map_screen.dart';
import 'package:hrms/screens/notifications/notifications_screen.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/snackbar_utils.dart';
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
  final _customerSearchController = TextEditingController();

  Customer? _selectedCustomer;
  List<Customer> _allCustomers = [];
  List<Customer> _filteredCustomers = [];
  bool _loadingCustomers = true;
  bool _submitting = false;
  bool _showCustomerDropdown = false;
  final FocusNode _customerFocusNode = FocusNode();
  DateTime? _earliestCompletionDate;
  DateTime? _latestCompletionDate;
  // Source can be resolved two ways: true = automatic current GPS, false =
  // manual address typed into _sourceController (geocoded on submit).
  bool _useCurrentLocationForSource = true;
  // Destination can be resolved two ways: true = automatic from the selected
  // customer's address, false = manual address typed into _destinationController.
  bool _useCustomerAddressForDest = true;
  // When a manual source/destination is chosen from the map picker, these hold
  // the exact pinned coordinates so submit uses them directly instead of
  // re-geocoding the text. Cleared when the user edits the address by hand.
  LatLng? _manualSourceLatLng;
  LatLng? _manualDestLatLng;
  String? _manualDestPincode;
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
                // const Text(
                //   'Keep the momentum',
                //   style: TextStyle(
                //     fontSize: 22,
                //     fontWeight: FontWeight.bold,
                //     color: Colors.white,
                //     height: 1.2,
                //   ),
                // ),
                // const SizedBox(height: 8),
                // Text(
                //   'Organize your workflow by adding a clear title and priority.',
                //   style: TextStyle(
                //     fontSize: 14,
                //     color: Colors.white.withValues(alpha: 0.9),
                //     height: 1.35,
                //   ),
                // ),
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

  /// Description: only user-entered text. Source/destination are stored in sourceLocation/destinationLocation.
  String _buildDescription() {
    return _descriptionController.text.trim();
  }

  void _onCustomerSelected(Customer c) {
    setState(() {
      _selectedCustomer = c;
      _customerSearchController.text = c.customerName;
      _showCustomerDropdown = false;
    });
  }

  /// Destination text built from the selected customer's address.
  String _customerDestinationAddress(Customer c) {
    return [
      c.address,
      c.city,
      c.pincode,
    ].where((p) => p.trim().isNotEmpty).join(', ').trim();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null || _selectedCustomer!.id == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a customer')));
      return;
    }
    if (_earliestCompletionDate == null || _latestCompletionDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select earliest and latest completion dates',
          ),
        ),
      );
      return;
    }
    if (_latestCompletionDate!.isBefore(_earliestCompletionDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Latest completion date must be on or after the earliest date',
          ),
        ),
      );
      return;
    }
    // Destination: Auto = selected customer's address, Manual = typed address.
    final String destAddr;
    if (_useCustomerAddressForDest) {
      destAddr = _customerDestinationAddress(_selectedCustomer!);
      if (destAddr.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected customer has no address on file'),
          ),
        );
        return;
      }
    } else {
      destAddr = _destinationController.text.trim();
      if (destAddr.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a destination address')),
        );
        return;
      }
    }
    // Manual source must have an address typed in before we try to geocode it.
    if (!_useCurrentLocationForSource && _sourceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a source address')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      // Resolve the source (pickup) according to the chosen mode:
      //  • Auto   → current GPS position + the reverse-geocoded address.
      //  • Manual → forward-geocode the typed address into coordinates.
      final LatLng pickup;
      final String sourceAddress;
      if (_useCurrentLocationForSource) {
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
        pickup = LatLng(position.latitude, position.longitude);
        sourceAddress = _currentLocationAddress.isNotEmpty
            ? _currentLocationAddress
            : 'Current location (GPS)';
      } else {
        final typedSource = _sourceController.text.trim();
        if (_manualSourceLatLng != null) {
          // Exact pin from the map picker — use it directly, don't re-geocode.
          pickup = _manualSourceLatLng!;
          sourceAddress = typedSource.isNotEmpty ? typedSource : 'Dropped pin';
        } else {
          List<Location> srcLocs = [];
          try {
            srcLocs = await locationFromAddress(typedSource);
          } catch (_) {}
          if (srcLocs.isEmpty) {
            if (mounted) {
              setState(() => _submitting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not locate the source address on the map',
                  ),
                ),
              );
            }
            return;
          }
          pickup = LatLng(srcLocs.first.latitude, srcLocs.first.longitude);
          sourceAddress = typedSource;
        }
      }

      final LatLng dropoff;
      // Customer pincode only applies when the destination is the customer's
      // address; for a manual address we let the reverse-geocode fallback fill it.
      String? destPincode =
          (_useCustomerAddressForDest && _selectedCustomer!.pincode.isNotEmpty)
          ? _selectedCustomer!.pincode
          : null;
      if (!_useCustomerAddressForDest && _manualDestLatLng != null) {
        // Exact pin from the map picker — use it directly, don't re-geocode.
        dropoff = _manualDestLatLng!;
        destPincode ??= _manualDestPincode;
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
                content: Text(
                  'Could not locate the destination address on the map',
                ),
              ),
            );
          }
          return;
        }
        dropoff = LatLng(destLocs.first.latitude, destLocs.first.longitude);
      }
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
        // Latest date is the hard deadline → keep it as expectedCompletionDate
        // so existing task views keep showing a due date.
        expectedCompletionDate: _latestCompletionDate!,
        earliestCompletionDate: _earliestCompletionDate!,
        latestCompletionDate: _latestCompletionDate!,
        status: 'assigned',
        sourceLocation: {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'address': sourceAddress,
        },
        destinationLocation: destLocation,
      );
      if (!mounted) return;
      // Creation only assigns the task (status 'assigned'); it does NOT auto-start
      // the ride. The new task now shows up in the staff's task list — they open
      // it from there and tap "Start Ride", running TaskDetailScreen's existing
      // flow. Pop back to the list (which refreshes on return) so it appears.
      // Show the confirmation at the TOP of the screen using the project's
      // standard animated top toast (see [SnackBarUtils]).
      SnackBarUtils.showSnackBar(
        context,
        'Task "${task.taskTitle}" assigned successfully',
      );
      Navigator.of(context).pop(true);
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
            icon: Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textPrimary,
              size: 26,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 4),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Icon(
                Icons.person_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        // Whole page scrolls as one: form fields and the Create Task button
        // share a single scroll view instead of the button being pinned.
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
            //  _buildMomentumBanner(),
           //   const SizedBox(height: 20),
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
              _buildCompletionDateRangeFields(),
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
            //  const SizedBox(height: 16),
             // _buildDestinationField(),
              const SizedBox(height: 24),
              // Create Task button scrolls with the form rather than being
              // pinned to the bottom of the screen.
              SizedBox(
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
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Earliest + Latest completion date range (replaces the single Due Date).
  Widget _buildCompletionDateRangeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCompletionDateField(
          label: 'Earliest Completion Date',
          value: _earliestCompletionDate,
          firstDate: DateTime.now(),
          onPicked: (picked) {
            setState(() {
              _earliestCompletionDate = picked;
              // Keep the range valid: bump latest forward if it now precedes earliest.
              if (_latestCompletionDate != null &&
                  _latestCompletionDate!.isBefore(picked)) {
                _latestCompletionDate = picked;
              }
            });
          },
        ),
        const SizedBox(height: 16),
        _buildCompletionDateField(
          label: 'Latest Completion Date',
          value: _latestCompletionDate,
          firstDate: _earliestCompletionDate ?? DateTime.now(),
          onPicked: (picked) {
            setState(() => _latestCompletionDate = picked);
          },
        ),
      ],
    );
  }

  Widget _buildCompletionDateField({
    required String label,
    required DateTime? value,
    required DateTime firstDate,
    required ValueChanged<DateTime> onPicked,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final initial = value != null && !value.isBefore(firstDate)
                ? value
                : firstDate;
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: firstDate,
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null && mounted) {
              onPicked(picked);
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
              value == null
                  ? ''
                  : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
              style: TextStyle(
                fontSize: 14,
                color: value == null ? Colors.grey.shade500 : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Pre-fills the manual source field with the reverse-geocoded current
  /// location, fetching it first if it hasn't been resolved yet.
  Future<void> _fillSourceFromCurrentLocation() async {
    if (_currentLocationAddress.isEmpty ||
        _currentLocationAddress == 'Location permission denied') {
      await _fetchCurrentLocationAddress();
    }
    if (!mounted) return;
    final addr = _currentLocationAddress;
    if (addr.isNotEmpty &&
        addr != 'Location permission denied' &&
        addr != 'Current location (GPS)') {
      // Address now comes from current GPS, not a map pin — drop any stale pin
      // so submit re-geocodes this address.
      setState(() {
        _sourceController.text = addr;
        _manualSourceLatLng = null;
      });
    }
  }

  /// Opens the full-screen map picker and returns the chosen pin, if any.
  Future<PinDestinationResult?> _openMapPicker({LatLng? initialPin}) {
    return Navigator.of(context).push<PinDestinationResult>(
      MaterialPageRoute(
        builder: (_) => PinDestinationMapScreen(initialPin: initialPin),
      ),
    );
  }

  /// Lets the user drop an exact pin for the source on the map.
  Future<void> _pickSourceOnMap() async {
    final result = await _openMapPicker(initialPin: _manualSourceLatLng);
    if (result == null || !mounted) return;
    setState(() {
      _manualSourceLatLng = LatLng(result.lat, result.lng);
      _sourceController.text = result.address;
    });
  }

  /// Lets the user drop an exact pin for the destination on the map.
  Future<void> _pickDestinationOnMap() async {
    final result = await _openMapPicker(initialPin: _manualDestLatLng);
    if (result == null || !mounted) return;
    setState(() {
      _manualDestLatLng = LatLng(result.lat, result.lng);
      _manualDestPincode = result.pincode;
      _destinationController.text = result.address;
    });
  }

  /// One segment in a two-way Auto/Manual toggle.
  Widget _segmentOption(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pill container that holds the two [_segmentOption]s of a toggle.
  Widget _segmentedContainer(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: children),
    );
  }

  /// Shared decoration for the manual source/destination address fields.
  InputDecoration _addressInputDecoration({
    required IconData prefixIcon,
    required Color prefixColor,
    required Widget suffix,
    required String hint,
  }) {
    return InputDecoration(
      prefixIcon: Icon(prefixIcon, size: 20, color: prefixColor),
      suffixIcon: suffix,
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

  Widget _buildSourceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Source',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _buildSourceModeToggle(),
        const SizedBox(height: 10),
        if (_useCurrentLocationForSource)
          _buildAutoSourceCard()
        else
          _buildManualSourceField(),
      ],
    );
  }

  /// Auto / Manual segmented switch for how the source is resolved.
  Widget _buildSourceModeToggle() {
    return _segmentedContainer([
      _segmentOption(
        'Auto (GPS)',
        Icons.gps_fixed_rounded,
        _useCurrentLocationForSource,
        () {
          if (_useCurrentLocationForSource) return;
          setState(() => _useCurrentLocationForSource = true);
          if (_currentLocationAddress.isEmpty) _fetchCurrentLocationAddress();
        },
      ),
      _segmentOption(
        'Manual',
        Icons.edit_location_alt_rounded,
        !_useCurrentLocationForSource,
        () {
          if (!_useCurrentLocationForSource) return;
          setState(() => _useCurrentLocationForSource = false);
        },
      ),
    ]);
  }

  /// Read-only card showing the auto-resolved current GPS address.
  Widget _buildAutoSourceCard() {
    return Container(
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
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  )
                : Text(
                    _currentLocationAddress.isEmpty
                        ? 'Current location (GPS)'
                        : _currentLocationAddress,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          IconButton(
            tooltip: 'Refresh location',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.refresh_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            onPressed: _loadingCurrentLocation
                ? null
                : _fetchCurrentLocationAddress,
          ),
        ],
      ),
    );
  }

  /// Outlined "Pick on map" button used under the manual source/destination
  /// fields to open the full-screen pin picker.
  Widget _buildPickOnMapButton(VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.map_rounded, size: 18, color: AppColors.primary),
        label: Text(
          'Pick on map',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Free-text source address (geocoded on submit) with shortcuts to fill it
  /// from the current GPS location or to drop an exact pin on the map.
  Widget _buildManualSourceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _sourceController,
          minLines: 1,
          maxLines: 2,
          textInputAction: TextInputAction.newline,
          // User typed by hand → any pin chosen earlier is stale, so submit
          // re-geocodes the typed text instead of using the old coordinates.
          onChanged: (_) {
            if (_manualSourceLatLng != null) {
              setState(() => _manualSourceLatLng = null);
            }
          },
          decoration: _addressInputDecoration(
            prefixIcon: Icons.edit_location_alt_rounded,
            prefixColor: AppColors.primary,
            hint: 'Enter source address',
            suffix: IconButton(
              tooltip: 'Use my current location',
              icon: _loadingCurrentLocation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.my_location_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
              onPressed: _loadingCurrentLocation
                  ? null
                  : _fillSourceFromCurrentLocation,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildPickOnMapButton(_pickSourceOnMap),
      ],
    );
  }

  /// Copies the selected customer's address into the manual destination field.
  void _fillDestinationFromCustomer() {
    final c = _selectedCustomer;
    if (c == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer first')),
      );
      return;
    }
    final addr = _customerDestinationAddress(c);
    if (addr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected customer has no address on file'),
        ),
      );
      return;
    }
    // Address now comes from the customer record, not a map pin — drop any
    // stale pin so submit re-geocodes this address.
    setState(() {
      _destinationController.text = addr;
      _manualDestLatLng = null;
      _manualDestPincode = null;
    });
  }

  Widget _buildDestinationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Destination',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _buildDestinationModeToggle(),
        const SizedBox(height: 10),
        if (_useCustomerAddressForDest)
          _buildCustomerDestinationCard()
        else
          _buildManualDestinationField(),
      ],
    );
  }

  /// Customer / Manual segmented switch for how the destination is resolved.
  Widget _buildDestinationModeToggle() {
    return _segmentedContainer([
      _segmentOption(
        'Customer',
        Icons.person_pin_circle_rounded,
        _useCustomerAddressForDest,
        () {
          if (_useCustomerAddressForDest) return;
          setState(() => _useCustomerAddressForDest = true);
        },
      ),
      _segmentOption(
        'Manual',
        Icons.edit_location_alt_rounded,
        !_useCustomerAddressForDest,
        () {
          if (!_useCustomerAddressForDest) return;
          setState(() => _useCustomerAddressForDest = false);
        },
      ),
    ]);
  }

  /// Read-only card showing the destination derived from the selected customer.
  Widget _buildCustomerDestinationCard() {
    final c = _selectedCustomer;
    final addr = c != null ? _customerDestinationAddress(c) : '';
    final placeholder = c == null
        ? 'Select a customer above'
        : 'Selected customer has no address on file';
    final isPlaceholder = c == null || addr.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded, size: 20, color: Colors.pink.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isPlaceholder ? placeholder : addr,
              style: TextStyle(
                fontSize: 13,
                color: isPlaceholder
                    ? Colors.grey.shade600
                    : AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Free-text destination address (geocoded on submit) with shortcuts to fill
  /// it from the selected customer's address or to drop an exact pin on the map.
  Widget _buildManualDestinationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _destinationController,
          minLines: 1,
          maxLines: 2,
          textInputAction: TextInputAction.newline,
          // User typed by hand → any pin chosen earlier is stale, so submit
          // re-geocodes the typed text instead of using the old coordinates.
          onChanged: (_) {
            if (_manualDestLatLng != null || _manualDestPincode != null) {
              setState(() {
                _manualDestLatLng = null;
                _manualDestPincode = null;
              });
            }
          },
          decoration: _addressInputDecoration(
            prefixIcon: Icons.location_on_rounded,
            prefixColor: Colors.pink.shade400,
            hint: 'Enter destination address',
            suffix: IconButton(
              tooltip: 'Use customer address',
              icon: Icon(
                Icons.person_pin_circle_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              onPressed: _fillDestinationFromCustomer,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildPickOnMapButton(_pickDestinationOnMap),
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
