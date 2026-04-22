import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/screens/geo/pin_destination_map_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class _DialOption {
  final String title;
  final String dialDigits;
  const _DialOption(this.title, this.dialDigits);
}

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

  static const List<_DialOption> _dialOptions = [
    _DialOption('IN +91', '91'),
    _DialOption('US +1', '1'),
    _DialOption('AE +971', '971'),
    _DialOption('GB +44', '44'),
  ];

  _DialOption _selectedDial = _dialOptions.first;

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
    if (_selectedDial.dialDigits == '91') {
      if (digits.length != 10) return 'Enter 10-digit mobile number';
    } else if (digits.length < 6) {
      return 'Enter a valid number';
    }
    return null;
  }

  Future<void> _submit() async {
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
        countryCode: _selectedDial.dialDigits,
      );

      await CustomerService().createCustomer(customer);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer added successfully!')),
      );
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final parsed = ErrorMessageUtils.messageFromResponseData(e.response?.data);
        final displayMsg = ErrorMessageUtils.sanitizeForDisplay(
          parsed,
          fallback: ErrorMessageUtils.toUserFriendlyMessage(e),
        );
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
                          width: 132,
                          child: DropdownButtonFormField<_DialOption>(
                            initialValue: _selectedDial,
                            isExpanded: true,
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
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            items: _dialOptions
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o,
                                    child: Text(
                                      o.title,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _submitting
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => _selectedDial = v);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _numberController,
                            decoration: _inputDecoration(
                              'Customer Number (mobile) *',
                              Icons.phone_rounded,
                              hint: _selectedDial.dialDigits == '91'
                                  ? '10 digits'
                                  : null,
                            ),
                            keyboardType: TextInputType.phone,
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
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              if (RegExp(r'\D').hasMatch(v.trim())) {
                                return 'Digits only';
                              }
                              return null;
                            },
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
