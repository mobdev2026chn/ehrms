import 'package:country_code_picker/country_code_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:hrms/widgets/app_card.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:hrms/screens/geo/pin_destination_map_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/widgets/custom_fields_form.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  /// Admin custom customer fields (Settings → Custom Fields).
  final _customFieldsKey = GlobalKey<CustomFieldsFormState>();
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _stateController = TextEditingController();
  bool _submitting = false;

  /// Customer location from "Select on Map". Field In / Field Out are checked against
  /// it, so a customer is not saved without one.
  double? _pinnedLat;
  double? _pinnedLng;

  /// Geofence radius for staff-added customers. The backend default (10 m) is tighter
  /// than phone GPS accuracy and would refuse genuine Field In attempts.
  static const double _defaultCustomerRadiusM = 100;

  /// E.164 digits only (no leading +), for API `countryCode`.
  String _dialDigits = '91';

  /// ISO-3166 alpha-2 of the selected country, used to validate the national
  /// mobile number against libphonenumber metadata.
  IsoCode _iso = IsoCode.IN;

  static String _digitsOnlyDial(String dial) =>
      dial.replaceAll(RegExp(r'\D'), '');

  /// Maps a country_code_picker ISO string (e.g. "IN") to an [IsoCode]; returns
  /// null when the code is unknown so callers can keep the previous value.
  static IsoCode? _isoFromCode(String? code) {
    if (code == null) return null;
    try {
      return IsoCode.values.byName(code.toUpperCase());
    } catch (_) {
      return null;
    }
  }

  /// Valid national mobile-number lengths for the selected country, taken from
  /// libphonenumber metadata (e.g. India -> [10], UAE -> [9]).
  List<int> get _mobileLengths =>
      metadataLenghtsByIsoCode[_iso]?.mobile ?? const [];

  /// Largest valid mobile length; caps how many digits the field accepts so a
  /// user physically cannot enter more than the country allows. Falls back to
  /// 15 (E.164 maximum) when metadata has no mobile length.
  int get _maxMobileDigits {
    final lengths = _mobileLengths;
    if (lengths.isEmpty) return 15;
    return lengths.reduce((a, b) => a > b ? a : b);
  }

  /// Smallest valid mobile length, used to keep the field hint accurate.
  int get _minMobileDigits {
    final lengths = _mobileLengths;
    if (lengths.isEmpty) return 0;
    return lengths.reduce((a, b) => a < b ? a : b);
  }

  String get _mobileHint {
    if (_mobileLengths.isEmpty) return 'Mobile number';
    return _minMobileDigits == _maxMobileDigits
        ? '$_maxMobileDigits digits'
        : '$_minMobileDigits–$_maxMobileDigits digits';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  String? _validateMobile(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Enter a valid mobile number';
    try {
      // Interpret the entry as a national number dialed inside the selected
      // country, then validate length + prefix against libphonenumber metadata.
      final phone = PhoneNumber.parse(digits, callerCountry: _iso);
      if (!phone.isValid(type: PhoneNumberType.mobile)) {
        return 'Enter a valid mobile number for the selected country';
      }
    } catch (_) {
      // Metadata lookup failed for this locale — fall back to a loose E.164
      // subscriber-number range so a valid number is never wrongly rejected.
      if (digits.length < 4 || digits.length > 15) {
        return 'Enter a valid mobile number';
      }
    }
    return null;
  }

  String? _validatePincode(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Required';
    if (RegExp(r'\D').hasMatch(value)) return 'Digits only';
    if (value.length != 6) return 'Enter a valid 6-digit PIN code';
    return null;
  }

  Future<void> _submit() async {
    SnackBarUtils.dismiss(context);
    if (!_formKey.currentState!.validate()) return;
    final customError = _customFieldsKey.currentState?.validate();
    if (customError != null) {
      SnackBarUtils.showSnackBar(context, customError, isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final rawDigits = _numberController.text.replaceAll(RegExp(r'\D'), '');
      final company = _companyController.text.trim();

      // Location: the pinned point, else the typed address looked up on the phone (free).
      var lat = _pinnedLat;
      var lng = _pinnedLng;
      if (lat == null || lng == null) {
        try {
          final found = await locationFromAddress(
            '${_addressController.text.trim()}, ${_cityController.text.trim()} ${_pincodeController.text.trim()}',
          );
          if (found.isNotEmpty) {
            lat = found.first.latitude;
            lng = found.first.longitude;
          }
        } catch (_) {}
      }
      if (lat == null || lng == null) {
        if (!mounted) return;
        setState(() => _submitting = false);
        SnackBarUtils.showSnackBar(
          context,
          'Could not find this address on the map. Use "Select on Map" to pin the customer location.',
          isError: true,
        );
        return;
      }
      final customer = Customer(
        customerName: _nameController.text.trim(),
        customerNumber: rawDigits,
        companyName: company.isEmpty ? null : company,
        emailId: _emailController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        pincode: _pincodeController.text.trim(),
        state: _stateController.text.trim(),
        countryCode: _dialDigits,
        latitude: lat,
        longitude: lng,
        radius: _defaultCustomerRadiusM,
      );

      await CustomerService().createCustomer(
        customer,
        customFields: _customFieldsKey.currentState?.values,
      );
      if (!mounted) return;
      // Success: app-wide tooltip toast, then close after a short beat.
      SnackBarUtils.showSnackBar(
        context,
        'Customer Added Successfully',
        isError: false,
      );
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final parsed = ErrorMessageUtils.messageFromResponseData(e.response?.data);
        final displayMsg = ErrorMessageUtils.sanitizeForDisplay(
          parsed,
          fallback: ErrorMessageUtils.toUserFriendlyMessage(e),
        );
        // Duplicate phone / email and other API errors as a black error toast.
        SnackBarUtils.showSnackBar(context, displayMsg, isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.toUserFriendlyMessage(e),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Add New Customer'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: AppCard(
                      padding: const EdgeInsets.all(16),
                      border: Border.all(color: const Color(0xFFECEEF1)),
                      child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration(
                        'Customer Name *',
                        Icons.person_rounded,
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 148,
                          child: IgnorePointer(
                            ignoring: _submitting,
                            child: CountryCodePicker(
                            initialSelection: 'IN',
                            favorite: const ['IN', 'US', 'AE', 'GB'],
                            pickerStyle: PickerStyle.bottomSheet,
                            showFlag: false,
                            showFlagDialog: true,
                            showDropDownButton: true,
                            enabled: !_submitting,
                            hideSearch: false,
                            onInit: (cc) {
                              final dial = cc?.dialCode;
                              if (dial != null) {
                                _dialDigits = _digitsOnlyDial(dial);
                              }
                              _iso = _isoFromCode(cc?.code) ?? _iso;
                            },
                            onChanged: (cc) {
                              final dial = cc.dialCode;
                              if (dial == null) return;
                              setState(() {
                                _dialDigits = _digitsOnlyDial(dial);
                                _iso = _isoFromCode(cc.code) ?? _iso;
                                // Trim any digits beyond the new country's max
                                // so the field never shows an over-length value.
                                final max = _maxMobileDigits;
                                if (_numberController.text.length > max) {
                                  _numberController.text =
                                      _numberController.text.substring(0, max);
                                }
                              });
                            },
                            searchDecoration: const InputDecoration(
                              labelText: 'Search',
                              hintText: 'Country name, code, or +dial',
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                              isDense: true,
                            ),
                            builder: (cc) {
                              final code = cc?.code;
                              final dial = cc?.dialCode;
                              final label = (code != null && dial != null)
                                  ? '$code $dial'
                                  : 'Code';
                              return InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Code',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  suffixIcon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    label,
                                    style: AppTextStyles.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            },
                          ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _numberController,
                            decoration: _inputDecoration(
                              'Mobile Number *',
                              Icons.phone_rounded,
                              hint: _mobileHint,
                            ),
                            keyboardType: TextInputType.phone,
                            // Digits only + hard cap at the country's longest
                            // valid mobile length (e.g. 10 for India).
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(_maxMobileDigits),
                            ],
                            validator: _validateMobile,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _companyController,
                      decoration: _inputDecoration(
                        'Company Name *',
                        Icons.business_rounded,
                      ),
                      textCapitalization: TextCapitalization.words,
                      // HRMSbackend rejects a customer without a company name.
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: _inputDecoration(
                        'Email ID *',
                        Icons.email_rounded,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!v.contains('@')) return 'Enter valid email';
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cityController,
                            decoration: _inputDecoration(
                              'City *',
                              Icons.location_city_rounded,
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _pincodeController,
                            decoration: _inputDecoration(
                              'Pincode *',
                              Icons.pin_drop_rounded,
                              hint: 'Numbers only',
                            ),
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            buildCounter: (
                              context, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) =>
                                null,
                            validator: _validatePincode,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _stateController,
                      decoration: _inputDecoration(
                        'State *',
                        Icons.map_rounded,
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _addressController,
                      decoration: _inputDecoration(
                        'Address *',
                        Icons.home_rounded,
                      ),
                      maxLines: 4,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      textInputAction: TextInputAction.newline,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _submitting
                          ? null
                          : () async {
                              Position? pos;
                              try {
                                pos = await Geolocator.getCurrentPosition(
                                  desiredAccuracy: LocationAccuracy.high,
                                );
                              } catch (_) {}
                              if (!mounted) return;
                              final result =
                                  await Navigator.of(context).push<PinDestinationResult>(
                                MaterialPageRoute(
                                  builder: (context) => PinDestinationMapScreen(
                                    initialCenter: pos != null
                                        ? LatLng(pos.latitude, pos.longitude)
                                        : null,
                                  ),
                                ),
                              );
                              if (result != null && mounted) {
                                setState(() {
                                  _pinnedLat = result.lat;
                                  _pinnedLng = result.lng;
                                  if (result.address.isNotEmpty) {
                                    _addressController.text = result.address;
                                  }
                                  if (result.city != null &&
                                      result.city!.isNotEmpty) {
                                    _cityController.text = result.city!;
                                  }
                                  if (result.pincode != null &&
                                      result.pincode!.isNotEmpty) {
                                    _pincodeController.text = result.pincode!;
                                  }
                                });
                              }
                            },
                      icon: Icon(
                        Icons.pin_drop_outlined,
                        size: 18,
                        color: AppColors.primaryText,
                      ),
                      label: Text(
                        'Select on Map',
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryText,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryText,
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 0,
                        ),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Required fields the admin set up (e.g. Company Registration Number).
                    CustomFieldsForm(key: _customFieldsKey, category: 'customer'),
                  ],
                ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : const Text('Add Customer'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
