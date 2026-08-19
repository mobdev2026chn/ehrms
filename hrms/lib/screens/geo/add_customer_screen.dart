import 'package:country_code_picker/country_code_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:hrms/screens/geo/pin_destination_map_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  bool _submitting = false;

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
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
    setState(() => _submitting = true);
    try {
      final rawDigits = _numberController.text.replaceAll(RegExp(r'\D'), '');
      final company = _companyController.text.trim();
      final customer = Customer(
        customerName: _nameController.text.trim(),
        customerNumber: rawDigits,
        companyName: company.isEmpty ? null : company,
        emailId: _emailController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        pincode: _pincodeController.text.trim(),
        countryCode: _dialDigits,
      );

      await CustomerService().createCustomer(customer);
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Add New Customer',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
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
                            searchDecoration: InputDecoration(
                              labelText: 'Search',
                              hintText: 'Country name, code, or +dial',
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                              isDense: true,
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
                                borderSide: BorderSide(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            builder: (cc) {
                              final code = cc?.code;
                              final dial = cc?.dialCode;
                              final label = (code != null && dial != null)
                                  ? '$code $dial'
                                  : 'Code';
                              return InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Code',
                                  labelStyle: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                  ),
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
                                    borderSide: BorderSide(
                                      color: AppColors.primary,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 12,
                                  ),
                                  suffixIcon: const Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.grey,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 13),
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
                              'Customer Number (mobile) *',
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
                        'Company Name',
                        Icons.business_rounded,
                      ),
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
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 0,
                        ),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Add Customer',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
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
