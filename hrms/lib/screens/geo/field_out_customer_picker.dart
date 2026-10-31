// "Select Customer" section of a self-logged journey's Field Out - the mobile counterpart of
// the block in the web Field Out Verification dialog (HRMSfrontend staff/GEOtask
// submissionModal), on the same screen as the Description / Proof Photo fields:
//   All Customer - every company customer (GET /staff/geo-task/customers?scope=all), badged
//                  Assigned (already this staff member's) or New (Field Out assigns them).
//   New Customer - quick add (POST /staff/geo-task/customers with quickAdd) pinned at the
//                  current location; the server assigns the creator. Saved from its own
//                  button, or together with the Field Out on Submit.
// FieldOutFormScreen drives it through a GlobalKey, as AddCustomerScreen does CustomFieldsForm.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/screens/geo/pin_destination_map_screen.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/snackbar_utils.dart';

class FieldOutCustomerPicker extends StatefulWidget {
  /// Called when a customer is selected from the list or saved as a new one.
  final ValueChanged<Customer>? onSelected;

  /// False while the Field Out is submitting.
  final bool enabled;

  const FieldOutCustomerPicker({super.key, this.onSelected, this.enabled = true});

  @override
  State<FieldOutCustomerPicker> createState() => FieldOutCustomerPickerState();
}

class FieldOutCustomerPickerState extends State<FieldOutCustomerPicker> {
  final _service = CustomerService();
  bool _newTab = false;

  // All Customer
  List<Customer> _customers = const [];
  bool _loading = true;
  String? _loadError;
  final _search = TextEditingController();
  Customer? _selected;

  // New Customer
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  double? _lat;
  double? _lng;
  String _address = '';
  String _city = '';
  String _state = '';
  String _pinCode = '';
  bool _locating = false;
  bool _saving = false;

  /// Geofence radius for a customer added here. Same reason as AddCustomerScreen: the
  /// backend's 10 m default is tighter than phone GPS and would refuse a genuine Field In.
  static const double _radiusM = 100;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    for (final c in [_search, _company, _name, _mobile, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Checks the section before a Field Out is submitted; shows the reason when not ready.
  bool validateForSubmit() {
    if (_newTab) return _validateNew();
    if (_selected != null) return true;
    SnackBarUtils.showSnackBar(
      context,
      'Select the customer you visited from the list, or use New Customer to add them.',
      isError: true,
    );
    return false;
  }

  /// The customer to submit with: the one selected, or on New Customer the one just saved
  /// from the form. Null when saving failed (the reason has been shown).
  Future<Customer?> commit() async => _newTab ? _saveNew() : _selected;

  static String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await _service.getStaffCustomers(all: true);
      if (mounted) setState(() => _customers = list);
    } catch (e) {
      if (mounted) setState(() => _loadError = _msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Customer> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _customers;
    return _customers
        .where((c) => [c.customerName, c.companyName, c.customerNumber, c.effectiveEmail]
            .any((v) => (v ?? '').toLowerCase().contains(q)))
        .toList();
  }

  void _setTab(bool newTab) {
    if (_newTab == newTab) return;
    setState(() => _newTab = newTab);
    // As on the web: opening New Customer pins the current location straight away.
    if (newTab && _lat == null && !_locating) _useCurrentLocation();
  }

  void _select(Customer c) {
    FocusScope.of(context).unfocus();
    setState(() => _selected = c);
    widget.onSelected?.call(c);
  }

  // ── Location ─────────────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location access is blocked. Allow location access and try again.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));
      await _setPin(pos.latitude, pos.longitude);
      if (mounted) SnackBarUtils.showSnackBar(context, 'Current location captured!');
    } catch (e) {
      if (mounted) {
        final m = _msg(e);
        SnackBarUtils.showSnackBar(
          context,
          m.contains('Location access') ? m : 'Could not read GPS location. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickOnMap() async {
    final here = (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null;
    final result = await Navigator.of(context).push<PinDestinationResult>(
      MaterialPageRoute(
        builder: (_) => PinDestinationMapScreen(initialCenter: here, initialPin: here),
      ),
    );
    if (result != null && mounted) await _setPin(result.lat, result.lng, picked: result);
  }

  /// Pins the customer at [lat],[lng] and fills address, city, state and pin code from
  /// the map pick and/or reverse geocoding (the map picker returns no state).
  Future<void> _setPin(double lat, double lng, {PinDestinationResult? picked}) async {
    setState(() {
      _lat = lat;
      _lng = lng;
      _address = picked?.address ?? '';
      _city = picked?.city ?? '';
      _pinCode = picked?.pincode ?? '';
      _state = '';
    });
    final resolved = await AddressResolutionService.reverseGeocode(lat, lng);
    if (!mounted || resolved == null || _lat != lat || _lng != lng) return;
    setState(() {
      if (_address.isEmpty) _address = resolved.formattedAddress;
      if (_city.isEmpty) _city = resolved.city ?? '';
      if (_pinCode.isEmpty) _pinCode = resolved.pincode ?? '';
      _state = resolved.state ?? '';
    });
  }

  /// HRMSbackend accepts only letters, spaces, dots, apostrophes and hyphens in a city or
  /// state, so a geocoded name is cleaned the way the web's sanitizePlaceName does.
  static String? _placeName(String value) {
    final clean = value
        .replaceAll(RegExp(r"[^\p{L}\p{M}\s.'-]", unicode: true), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return clean.isEmpty ? null : clean;
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  bool _validateNew() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      SnackBarUtils.showSnackBar(
        context,
        'Fill in the new customer\'s company, name, mobile and email.',
        isError: true,
      );
      return false;
    }
    if (_lat == null || _lng == null) {
      SnackBarUtils.showSnackBar(
        context,
        'Pin the customer location: use your current location or pick it on the map.',
        isError: true,
      );
      return false;
    }
    return true;
  }

  Future<Customer?> _saveNew() async {
    if (_saving || !_validateNew()) return null;
    setState(() => _saving = true);
    try {
      final name = _name.text.trim();
      final pin = _pinCode.replaceAll(' ', '');
      // Same fallbacks as the web quick add, so a missing geocode never blocks the save.
      final created = await _service.createCustomer(
        Customer(
          customerName: name,
          companyName: _company.text.trim(),
          customerNumber: _mobile.text.trim(),
          emailId: _email.text.trim(),
          address: _address.trim().isNotEmpty
              ? _address.trim()
              : '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
          city: _placeName(_city) ?? 'Field Office',
          state: _placeName(_state) ?? 'General',
          pincode: RegExp(r'^\d{4,6}$').hasMatch(pin) ? pin : '000000',
          latitude: _lat,
          longitude: _lng,
          radius: _radiusM,
        ),
        quickAdd: true,
      );
      if (created.id == null || created.id!.isEmpty) {
        throw Exception('The customer was saved without an ID. Refresh the list and select them.');
      }
      if (!mounted) return created;
      // Back on All Customer with the new one selected, ready for the next visit.
      setState(() {
        _customers = [created, ..._customers.where((c) => c.id != created.id)];
        _selected = created;
        _newTab = false;
        for (final c in [_company, _name, _mobile, _email]) {
          c.clear();
        }
        _lat = _lng = null;
        _address = _city = _state = _pinCode = '';
      });
      widget.onSelected?.call(created);
      SnackBarUtils.showSnackBar(context, 'Customer "$name" added and assigned to you!');
      return created;
    } on DioException catch (e) {
      if (mounted) {
        final parsed = ErrorMessageUtils.messageFromResponseData(e.response?.data);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            parsed,
            fallback: ErrorMessageUtils.toUserFriendlyMessage(e),
          ),
          isError: true,
        );
      }
      return null;
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, _msg(e), isError: true);
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: !widget.enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _segments(),
          const SizedBox(height: 10),
          if (_newTab) _newCustomer() else _allCustomers(),
        ],
      ),
    );
  }

  Widget _segments() {
    Widget segment(String label, IconData icon, bool active, VoidCallback onTap, {int? count}) {
      final color = active ? AppColors.textPrimary : AppColors.textSecondary;
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? const Color(0xFFE2E5EA) : Colors.transparent),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECEEF1)),
      ),
      child: Row(
        children: [
          segment(
            'All Customer',
            Icons.people_alt_outlined,
            !_newTab,
            () => _setTab(false),
            count: _loading ? null : _customers.length,
          ),
          const SizedBox(width: 4),
          segment('New Customer', Icons.person_add_alt_1_outlined, _newTab, () => _setTab(true)),
        ],
      ),
    );
  }

  Widget _allCustomers() {
    final list = _filtered;
    final q = _search.text.trim();
    Widget body;
    if (_loading) {
      body = Container(
        padding: const EdgeInsets.all(14),
        decoration: _boxDecoration(),
        child: const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Loading customers...', style: AppTextStyles.bodySmall),
          ],
        ),
      );
    } else if (_loadError != null) {
      body = _note(_loadError!, TextButton(onPressed: _load, child: const Text('Retry')));
    } else if (list.isEmpty) {
      body = _note(
        q.isEmpty ? 'No customers found.' : 'No customers found matching "$q".',
        TextButton.icon(
          onPressed: () => _setTab(true),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Add as a new customer'),
        ),
      );
    } else {
      // Its own scroll, like the web list, so a long customer list does not push
      // Description and Proof Photo far down the screen.
      body = Container(
        constraints: const BoxConstraints(maxHeight: 260),
        clipBehavior: Clip.antiAlias,
        decoration: _boxDecoration(),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFECEEF1)),
          itemBuilder: (_, i) => _customerRow(list[i]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selected != null) ...[
          _selectedBanner(_selected!),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search by name, company, mobile...',
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Clear',
                    onPressed: _search.clear,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        body,
        const SizedBox(height: 6),
        const Text(
          'A customer marked New is assigned to you when you Field Out with them.',
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  BoxDecoration _boxDecoration() => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E5EA)),
      );

  Widget _note(String text, Widget action) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: _boxDecoration(),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          action,
        ],
      ),
    );
  }

  Widget _selectedBanner(Customer c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('SELECTED CUSTOMER', style: AppTextStyles.sectionLabel)),
              TextButton(
                onPressed: () => setState(() => _selected = null),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Change'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _customerSummary(c),
          ),
        ],
      ),
    );
  }

  Widget _customerRow(Customer c) {
    final selected = c.id != null && c.id == _selected?.id;
    return InkWell(
      onTap: () => _select(c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandLight : null,
          border: selected
              ? const Border(left: BorderSide(color: AppColors.brand, width: 4))
              : null,
        ),
        child: _customerSummary(c, checked: selected),
      ),
    );
  }

  /// Name, "company • mobile" and the Assigned / New badge.
  Widget _customerSummary(Customer c, {bool checked = false}) {
    final subtitle = [c.companyName, c.customerNumber]
        .where((v) => v != null && v.trim().isNotEmpty)
        .join(' • ');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.customerName.isNotEmpty ? c.customerName : c.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        CustomerAssignmentBadge(assigned: c.isAssigned),
        if (checked) ...[
          const SizedBox(width: 6),
          const Icon(Icons.check_rounded, size: 18, color: AppColors.brand),
        ],
      ],
    );
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        prefixIcon: Icon(icon, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _newCustomer() {
    // Its own Form: the screen's Form validates the Field Out answers only.
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFECEEF1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('NEW CUSTOMER DETAILS', style: AppTextStyles.sectionLabel),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.how_to_reg_rounded, size: 14, color: AppColors.success),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Will be saved as your Assigned Customer',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _company,
              decoration: _decoration('Company Name *', Icons.business_rounded),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: _decoration('Customer Name *', Icons.person_rounded),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobile,
              decoration: _decoration('Mobile *', Icons.phone_rounded, hint: '10-digit mobile'),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              textInputAction: TextInputAction.next,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Required';
                if (value.length != 10) return 'Mobile number must be exactly 10 digits';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: _decoration('Email *', Icons.email_rounded, hint: 'customer@email.com'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Required';
                if (!_emailPattern.hasMatch(value)) return 'Enter a valid email, e.g. john@acme.com';
                return null;
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 18, color: AppColors.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Location Map',
                    style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: (_locating || _saving) ? null : _useCurrentLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 16),
                  label: const Text('Use Current Location'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            if (_address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: _boxDecoration(),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Pinned: ',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      TextSpan(text: _address),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _mapPreview(),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: (_saving || _locating) ? null : _saveNew,
                icon: _saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(_saving ? 'Saving & Assigning...' : 'Save Customer & Select'),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Save now, or fill in the rest of the form below and tap Submit to save and submit together.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }

  /// A small, non-interactive map of the pin; tapping it opens the full map picker.
  Widget _mapPreview() {
    final pinned = _lat != null && _lng != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 160,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (pinned)
              IgnorePointer(
                child: GoogleMap(
                  // Rebuilt per pin: lite mode cannot be moved after it is drawn.
                  key: ValueKey('$_lat,$_lng'),
                  liteModeEnabled: true,
                  initialCameraPosition: CameraPosition(target: LatLng(_lat!, _lng!), zoom: 16),
                  markers: {
                    Marker(markerId: const MarkerId('customer'), position: LatLng(_lat!, _lng!)),
                  },
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                ),
              )
            else
              Container(
                color: AppColors.surface,
                alignment: Alignment.center,
                child: _locating
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_off_outlined, color: AppColors.textCaption),
                          SizedBox(height: 6),
                          Text('No location pinned yet', style: AppTextStyles.bodySmall),
                        ],
                      ),
              ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: (_saving || _locating) ? null : _pickOnMap),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pin_drop_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        pinned ? 'Adjust pin' : 'Pick on map',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Assigned" (green) when the customer is already this staff member's, "New" (amber)
/// when Field Out with them will assign them - the same badges as the web dialog.
class CustomerAssignmentBadge extends StatelessWidget {
  final bool assigned;

  const CustomerAssignmentBadge({super.key, required this.assigned});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: assigned ? AppColors.successBg : AppColors.brandLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: assigned ? AppColors.success.withValues(alpha: 0.3) : AppColors.brandBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            assigned ? Icons.how_to_reg_rounded : Icons.auto_awesome_rounded,
            size: 12,
            color: assigned ? AppColors.success : AppColors.brand,
          ),
          const SizedBox(width: 3),
          Text(
            assigned ? 'Assigned' : 'New',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: assigned ? AppColors.success : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
