// lib/screens/admin/staff/admin_add_staff_screen.dart
//
// Add Staff - mirrors the web admin form
// (HRMSfrontend features/admin/staff/staff/pages/addStaff.tsx) and posts the
// same payload to POST /admin/staff (backend: staffController.createStaff ->
// staffCreationService.buildStaffPayload).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_staff_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_tab_loader.dart';

/// Hairline card border and field border (match the global theme).
const _cardBorder = Color(0xFFECEEF1);
const _fieldBorder = Color(0xFFE2E5EA);

/// Dial code -> [min, max] subscriber digits (same table as the web form).
const Map<String, List<int>> _phoneLengths = {
  '+91': [10, 10], '+1': [10, 10], '+44': [9, 10], '+971': [9, 9], '+61': [9, 9], '+65': [8, 8],
  '+49': [6, 11], '+33': [9, 9], '+81': [10, 10], '+86': [11, 11], '+55': [10, 11], '+27': [9, 9],
  '+7': [10, 10], '+966': [9, 9], '+60': [9, 10], '+94': [9, 9], '+977': [10, 10], '+880': [10, 10],
  '+92': [10, 10], '+63': [10, 10], '+62': [9, 12], '+66': [9, 9], '+84': [9, 9], '+64': [8, 10],
  '+852': [8, 8], '+31': [9, 9], '+39': [9, 10], '+34': [9, 9], '+41': [9, 9], '+46': [7, 9],
  '+47': [8, 8], '+45': [8, 8], '+358': [6, 10], '+353': [7, 9], '+52': [10, 10], '+965': [8, 8],
  '+974': [8, 8], '+968': [8, 8], '+973': [8, 8], '+20': [10, 10], '+254': [9, 9], '+234': [10, 10],
};

/// Department options exactly as the web form (value -> label).
const List<List<String>> _departmentOptions = [
  ['Engineering', 'IT'],
  ['Design', 'Marketing'],
  ['HR', 'HR'],
  ['Sales', 'Sales'],
];

const List<String> _designationOptions = ['Junior', 'Senior', 'Team Lead', 'Manager'];
const List<String> _employmentTypes = ['Full Time', 'Part Time', 'Contract', 'Intern'];
const List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];
const List<List<String>> _workModes = [
  ['In Office', 'In Office - Works from assigned office location'],
  ['WFH', 'Work From Home (WFH) - Works remotely from home'],
  ['Hybrid', 'Hybrid - Works partly from office and home'],
  ['Remote', 'Remote - Works from any location without geofence'],
];

/// Largest profile photo the API accepts (MAX_PROFILE_PICTURE_BYTES on the server).
const int _maxProfilePicBytes = 5 * 1024 * 1024;

class AdminAddStaffScreen extends StatefulWidget {
  const AdminAddStaffScreen({super.key});

  @override
  State<AdminAddStaffScreen> createState() => _AdminAddStaffScreenState();
}

class _AdminAddStaffScreenState extends State<AdminAddStaffScreen> {
  final AdminStaffService _staffService = AdminStaffService();
  static const _steps = ['Personal', 'Address & ID', 'Employment', 'Bank & Statutory'];
  int _currentStep = 0;
  bool _isLoadingSetup = true;
  String? _loadError;
  bool _isSubmitting = false;

  // Options
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _attendanceTemplates = [];
  List<Map<String, dynamic>> _weeklyOffTemplates = [];
  List<Map<String, dynamic>> _leaveTemplates = [];
  List<Map<String, dynamic>> _holidayTemplates = [];
  List<Map<String, dynamic>> _breakTemplates = [];
  List<Map<String, dynamic>> _overtimeTemplates = [];
  List<Map<String, dynamic>> _permissionTemplates = [];
  List<Map<String, dynamic>> _salaryTemplates = [];

  // Reporting managers (GET /admin/staff/reporting-managers)
  bool _isLoadingManagers = false;
  String? _managersError;
  List<String> _managerOptions = [];
  String _managerDefault = '';
  List<String> _managerReportsTo = [];
  int _managerRequestId = 0;

  // ── Personal ──
  String _profilePic = ''; // data URL sent to the API
  Uint8List? _profilePicBytes; // preview
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  String _dob = '';
  String? _gender;
  String? _bloodGroup;
  final _fatherNameController = TextEditingController();
  String _maritalStatus = 'Single';
  final _spouseNameController = TextEditingController();
  final _emailController = TextEditingController();
  String _countryCode = '+91';
  final _phoneController = TextEditingController();
  String _altCountryCode = '+91';
  final _altPhoneController = TextEditingController();
  final _passwordController = TextEditingController(text: 'User@123');
  final _confirmPasswordController = TextEditingController(text: 'User@123');
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // ── Address & identity ──
  final _currentAddressController = TextEditingController();
  final _currentStateController = TextEditingController();
  final _currentCountryController = TextEditingController();
  final _currentPincodeController = TextEditingController();
  bool _sameAddress = false;
  final _permanentAddressController = TextEditingController();
  final _permanentStateController = TextEditingController();
  final _permanentCountryController = TextEditingController();
  final _permanentPincodeController = TextEditingController();
  final _panController = TextEditingController();
  final _aadhaarController = TextEditingController();
  String _isPhysicallyChallenged = 'No';
  final _disabilityTypeController = TextEditingController();
  final _disabilityPercentageController = TextEditingController();
  final _disabilityCertNoController = TextEditingController();

  // ── Employment ──
  final _employeeIdController = TextEditingController();
  String _employmentType = 'Full Time';
  String _joiningDate = '';
  String _onboardingDate = '';
  String _internStartDate = '';
  String _internEndDate = '';
  String? _department;
  String? _designation;
  final _jobPositionController = TextEditingController();
  String? _reportingManager; // null -> default (company admin)
  String? _selectedBranch; // branch _id
  String? _workMode;
  final _workAddressController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController(text: '10');
  bool _isLocating = false;

  // Templates (ids)
  String? _salaryTemplate;
  String? _attendanceTemplate;
  String? _leaveTemplate;
  String? _holidayTemplate;
  String? _weeklyOffTemplate;
  String? _breakTemplate;
  String? _overtimeTemplate;
  String? _permissionTemplate;

  // ── Bank & statutory ──
  final _bankNameController = TextEditingController();
  final _accountHolderController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _ifscController = TextEditingController();
  final _bankBranchController = TextEditingController();
  final _upiController = TextEditingController();
  final _uanController = TextEditingController();
  final _pfController = TextEditingController();
  String _pfStartDate = '';
  final _esiController = TextEditingController();
  String _esiStartDate = '';

  @override
  void initState() {
    super.initState();
    _loadSetupData();
  }

  @override
  void dispose() {
    for (final c in [
      _firstNameController, _lastNameController, _fatherNameController, _spouseNameController, _emailController,
      _phoneController, _altPhoneController, _passwordController, _confirmPasswordController,
      _currentAddressController, _currentStateController, _currentCountryController, _currentPincodeController,
      _permanentAddressController, _permanentStateController, _permanentCountryController,
      _permanentPincodeController, _panController, _aadhaarController, _disabilityTypeController,
      _disabilityPercentageController, _disabilityCertNoController, _employeeIdController, _jobPositionController,
      _workAddressController, _latitudeController, _longitudeController, _radiusController, _bankNameController,
      _accountHolderController, _accountNumberController, _ifscController, _bankBranchController, _upiController,
      _uanController, _pfController, _esiController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static List<Map<String, dynamic>> _maps(dynamic list) => (list is List ? list : const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  Future<void> _loadSetupData() async {
    setState(() {
      _isLoadingSetup = true;
      _loadError = null;
    });

    final results = await Future.wait<dynamic>([
      _staffService.getStaffSetup(),
      _staffService.getBranches(),
      _staffService.getNextEmployeeId(),
    ]);
    if (!mounted) return;
    final setupRes = results[0] as Map<String, dynamic>;
    final branchRes = results[1] as Map<String, dynamic>;
    final nextEmpId = results[2] as String?;

    if (setupRes['success'] != true) {
      setState(() {
        _isLoadingSetup = false;
        _loadError = (setupRes['message'] ?? 'Could not load staff templates.').toString();
      });
      return;
    }
    if (branchRes['success'] != true) {
      setState(() {
        _isLoadingSetup = false;
        _loadError = (branchRes['message'] ?? 'Could not load branches.').toString();
      });
      return;
    }

    final data = setupRes['data'] is Map ? Map<String, dynamic>.from(setupRes['data'] as Map) : <String, dynamic>{};
    setState(() {
      _branches = _maps(branchRes['data']);
      _attendanceTemplates = _maps(data['attendanceTemplates']);
      _weeklyOffTemplates = _maps(data['weeklyOffTemplates']);
      _leaveTemplates = _maps(data['leaveTemplates']);
      _holidayTemplates = _maps(data['holidayTemplates']);
      _breakTemplates = _maps(data['breakTemplates']);
      _overtimeTemplates = _maps(data['overtimeTemplates']);
      _permissionTemplates = _maps(data['permissionTemplates']);
      _salaryTemplates = _maps(data['salaryTemplates']);
      // Prefilled from the server when available; otherwise the admin types one
      // (the backend also issues one when left blank).
      if (_employeeIdController.text.trim().isEmpty && nextEmpId != null && nextEmpId.isNotEmpty) {
        _employeeIdController.text = nextEmpId;
      }
      _isLoadingSetup = false;
    });
    _loadReportingManagers();
  }

  /// Re-requested whenever the designation changes (hierarchy applied server-side).
  Future<void> _loadReportingManagers() async {
    final requestId = ++_managerRequestId;
    setState(() {
      _isLoadingManagers = true;
      _managersError = null;
    });
    final res = await _staffService.getReportingManagers(designation: _designation);
    if (!mounted || requestId != _managerRequestId) return;
    if (res['success'] != true || res['data'] is! Map) {
      setState(() {
        _isLoadingManagers = false;
        _managersError = (res['message'] ?? 'Could not load reporting managers.').toString();
      });
      return;
    }
    final d = Map<String, dynamic>.from(res['data'] as Map);
    final options = (d['options'] as List? ?? const []).map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    setState(() {
      _isLoadingManagers = false;
      _managerOptions = options;
      _managerDefault = (d['defaultOption'] ?? '').toString();
      _managerReportsTo = (d['reportsTo'] as List? ?? const []).map((e) => e.toString()).toList();
      // A manager picked under the previous designation drops back to the default.
      if (_reportingManager != null && !options.contains(_reportingManager)) {
        _reportingManager = null;
      }
    });
  }

  String get _effectiveReportingManager => _reportingManager ?? _managerDefault;

  // ───────────────────────── Helpers ─────────────────────────

  static String? _phoneLengthError(String dialCode, String digits, String label) {
    final rule = _phoneLengths[dialCode] ?? const [8, 15];
    final len = digits.replaceAll(RegExp(r'\D'), '').length;
    if (len < rule[0] || len > rule[1]) {
      final what = rule[0] == rule[1] ? 'exactly ${rule[0]} digits' : 'between ${rule[0]} and ${rule[1]} digits';
      return '$label must be $what for $dialCode.';
    }
    return null;
  }

  static String? _passwordError(String p) {
    if (p.isEmpty) return 'Password is required.';
    if (p.length < 8) return 'Password must be at least 8 characters long.';
    if (!RegExp(r'[A-Z]').hasMatch(p)) return 'Password must contain at least one uppercase letter.';
    if (!RegExp(r'[a-z]').hasMatch(p)) return 'Password must contain at least one lowercase letter.';
    if (!RegExp(r'[0-9]').hasMatch(p)) return 'Password must contain at least one number.';
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(p)) {
      return 'Password must contain at least one special character (e.g., !@#\$%^&*).';
    }
    return null;
  }

  static String? _pincodeError(String pin, String country, String dialCode, String label) {
    if (pin.isEmpty) return '$label is required.';
    final c = country.trim().toLowerCase();
    final isIndia = c == 'india' || c == 'ind' || dialCode == '+91';
    if (isIndia && pin.length != 6) return '$label must be exactly 6 digits.';
    if (pin.length < 3 || pin.length > 10) return '$label must be between 3 and 10 digits.';
    return null;
  }

  Future<void> _pickDate(String current, ValueChanged<String> onPicked, {DateTime? first, DateTime? last}) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(current) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(1940),
      lastDate: last ?? DateTime(now.year + 5, 12, 31),
    );
    if (picked != null) onPicked(DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _pickProfilePic() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
      if (picked == null) return;
      final name = picked.name.toLowerCase();
      final ext = name.contains('.') ? name.split('.').last : '';
      const mimeByExt = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
        'gif': 'image/gif',
      };
      final mime = mimeByExt[ext] ?? picked.mimeType;
      if (mime == null || !mimeByExt.values.contains(mime)) {
        if (mounted) SnackBarUtils.showSnackBar(context, 'Please choose a JPG, PNG, WEBP or GIF image.', isError: true);
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxProfilePicBytes) {
        final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
        if (mounted) {
          SnackBarUtils.showSnackBar(context, 'That image is ${mb}MB. Please choose one under 5MB.', isError: true);
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _profilePic = 'data:$mime;base64,${base64Encode(bytes)}';
        _profilePicBytes = bytes;
      });
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, 'That image could not be read. Please choose another file.', isError: true);
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Location services are turned off.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw 'Location permission denied.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _latitudeController.text = pos.latitude.toStringAsFixed(6);
        _longitudeController.text = pos.longitude.toStringAsFixed(6);
      });
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, e is String ? e : 'Could not get the current location.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // ───────────────────────── Submit ─────────────────────────

  /// Returns the first validation error and the step it belongs to.
  ({String message, int step})? _validate() {
    String t(TextEditingController c) => c.text.trim();
    ({String message, int step}) e(String m, int s) => (message: m, step: s);

    // Step 0 - personal & contact
    if (t(_firstNameController).isEmpty) return e('First Name is required.', 0);
    if (t(_lastNameController).isEmpty) return e('Last Name is required.', 0);
    if (_dob.isEmpty) return e('Date of Birth is required.', 0);
    if (_gender == null) return e('Gender is required.', 0);
    if (_bloodGroup == null) return e('Blood Group is required.', 0);
    if (t(_fatherNameController).isEmpty) return e("Father's Name is required.", 0);
    if (_maritalStatus == 'Married' && t(_spouseNameController).isEmpty) return e("Spouse's Name is required.", 0);
    final email = t(_emailController);
    if (email.isEmpty) return e('Email ID is required.', 0);
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) return e('Please enter a valid Email ID.', 0);
    final phone = t(_phoneController);
    if (phone.isEmpty) return e('Phone number is required.', 0);
    final pErr = _phoneLengthError(_countryCode, phone, 'Phone number');
    if (pErr != null) return e(pErr, 0);
    final alt = t(_altPhoneController);
    if (alt.isEmpty) return e('Alternate Phone number is required.', 0);
    final aErr = _phoneLengthError(_altCountryCode, alt, 'Alternate Phone number');
    if (aErr != null) return e(aErr, 0);
    if (phone == alt && _countryCode == _altCountryCode) {
      return e('Phone number and Alternate Phone number cannot be the same.', 0);
    }
    final pwErr = _passwordError(_passwordController.text);
    if (pwErr != null) return e(pwErr, 0);
    if (_confirmPasswordController.text.isEmpty) return e('Confirm password is required.', 0);
    if (_passwordController.text != _confirmPasswordController.text) return e('Passwords do not match.', 0);

    // Step 1 - address & identity
    if (t(_currentAddressController).isEmpty) return e('Current Address is required.', 1);
    if (t(_currentCountryController).isEmpty) return e('Current Country is required.', 1);
    if (t(_currentStateController).isEmpty) return e('Current State is required.', 1);
    final cpErr = _pincodeError(t(_currentPincodeController), t(_currentCountryController), _countryCode, 'Current Pincode');
    if (cpErr != null) return e(cpErr, 1);
    if (!_sameAddress) {
      if (t(_permanentAddressController).isEmpty) return e('Permanent Address is required.', 1);
      if (t(_permanentCountryController).isEmpty) return e('Permanent Country is required.', 1);
      if (t(_permanentStateController).isEmpty) return e('Permanent State is required.', 1);
      final ppErr =
          _pincodeError(t(_permanentPincodeController), t(_permanentCountryController), _countryCode, 'Permanent Pincode');
      if (ppErr != null) return e(ppErr, 1);
    }
    final pan = t(_panController).toUpperCase();
    if (pan.isNotEmpty && !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan)) {
      return e('PAN must be in the format ABCDE1234F (5 letters, 4 digits, 1 letter).', 1);
    }
    final aadhaar = t(_aadhaarController).replaceAll(RegExp(r'\s'), '');
    if (aadhaar.isNotEmpty && !RegExp(r'^\d{12}$').hasMatch(aadhaar)) {
      return e('Aadhaar must be exactly 12 numeric digits.', 1);
    }
    if (_isPhysicallyChallenged == 'Yes') {
      final pct = t(_disabilityPercentageController);
      final v = double.tryParse(pct);
      if (pct.isNotEmpty && (v == null || v < 0 || v > 100)) {
        return e('Disability percentage must be between 0 and 100.', 1);
      }
    }

    // Step 2 - employment
    if (t(_employeeIdController).isEmpty) return e('Employee ID is required.', 2);
    if ((_employmentType == 'Full Time' || _employmentType == 'Part Time') && _onboardingDate.isEmpty) {
      return e('Onboarding Date is required.', 2);
    }
    if (_department == null) return e('Department selection is required.', 2);
    if (_designation == null) return e('Designation selection is required.', 2);
    if (t(_jobPositionController).isEmpty) return e('Job Role is required.', 2);
    if (_selectedBranch == null) {
      return e(
        _branches.isEmpty ? 'No branches are configured yet. Create a branch before adding staff.' : 'Branch is required.',
        2,
      );
    }
    if (_effectiveReportingManager.isEmpty) {
      final level = _managerReportsTo.isEmpty ? 'manager' : _managerReportsTo.join(' or ');
      return e(
        'No reporting manager can be assigned: set the Company Admin on Company Master Details, or add a $level first.',
        2,
      );
    }
    if (_workMode == null) return e('Work Mode selection is required.', 2);
    if (_workMode == 'WFH' || _workMode == 'Hybrid') {
      final lat = double.tryParse(t(_latitudeController));
      final lng = double.tryParse(t(_longitudeController));
      if (lat == null || lat < -90 || lat > 90 || lng == null || lng < -180 || lng > 180) {
        return e('Enter a valid latitude and longitude for the $_workMode location.', 2);
      }
      final r = int.tryParse(t(_radiusController));
      if (r == null || r < 1) return e('Radius must be at least 1 metre.', 2);
    }
    if (_employmentType != 'Intern') {
      if (_joiningDate.isEmpty) return e('Joining Date is required.', 2);
    } else {
      if (_internStartDate.isEmpty) return e('Intern Start Date is required.', 2);
      if (_internEndDate.isEmpty) return e('Intern End Date is required.', 2);
    }
    if (_salaryTemplate == null) return e('Salary Template selection is required.', 2);
    if (_attendanceTemplate == null) return e('Attendance Template selection is required.', 2);
    if (_leaveTemplate == null) return e('Leave Template selection is required.', 2);
    if (_holidayTemplate == null) return e('Holiday Template selection is required.', 2);
    if (_weeklyOffTemplate == null) return e('Weekly Off Template selection is required.', 2);
    if (_breakTemplate == null) return e('Break Template selection is required.', 2);
    if (_overtimeTemplate == null) return e('Overtime Template selection is required.', 2);
    if (_permissionTemplate == null) return e('Permission Template selection is required.', 2);

    // Step 3 - bank & statutory
    final acc = t(_accountNumberController);
    if (acc.isNotEmpty && !RegExp(r'^\d{9,18}$').hasMatch(acc)) {
      return e('Bank Account Number must be between 9 and 18 numeric digits.', 3);
    }
    if (t(_pfController).length > 22) return e('PF Number cannot exceed 22 characters.', 3);
    final uan = t(_uanController);
    if (uan.isNotEmpty && !RegExp(r'^\d{12}$').hasMatch(uan)) return e('UAN must be exactly 12 numeric digits.', 3);
    final esi = t(_esiController);
    if (esi.isNotEmpty && !RegExp(r'^\d{17}$').hasMatch(esi)) return e('ESI must be exactly 17 numeric digits.', 3);
    return null;
  }

  Future<void> _submitAddStaff() async {
    final err = _validate();
    if (err != null) {
      setState(() => _currentStep = err.step);
      SnackBarUtils.showSnackBar(context, err.message, isError: true);
      return;
    }

    String t(TextEditingController c) => c.text.trim();
    final first = t(_firstNameController);
    final last = t(_lastNameController);
    final married = _maritalStatus == 'Married';
    final disabled = _isPhysicallyChallenged == 'Yes';
    final mode = _workMode!;

    final payload = <String, dynamic>{
      'employeeId': t(_employeeIdController),
      'name': '$first $last'.trim(),
      'firstName': first,
      'lastName': last,
      'dob': _dob,
      'password': _passwordController.text,
      'phone': '$_countryCode ${t(_phoneController)}',
      'altPhone': t(_altPhoneController).isNotEmpty ? '$_altCountryCode ${t(_altPhoneController)}' : '',
      'fatherName': t(_fatherNameController),
      'maritalStatus': _maritalStatus,
      'spouseName': married ? t(_spouseNameController) : '',
      'bloodGroup': _bloodGroup,
      'gender': _gender,
      'currentAddress': t(_currentAddressController),
      'currentState': t(_currentStateController),
      'currentCountry': t(_currentCountryController),
      'currentPincode': t(_currentPincodeController),
      'permanentAddress': _sameAddress ? t(_currentAddressController) : t(_permanentAddressController),
      'permanentState': _sameAddress ? t(_currentStateController) : t(_permanentStateController),
      'permanentCountry': _sameAddress ? t(_currentCountryController) : t(_permanentCountryController),
      'permanentPincode': _sameAddress ? t(_currentPincodeController) : t(_permanentPincodeController),
      'pan': t(_panController).toUpperCase(),
      'aadhaar': t(_aadhaarController).replaceAll(RegExp(r'\s'), ''),
      'isPhysicallyChallenged': _isPhysicallyChallenged,
      'disabilityType': disabled ? t(_disabilityTypeController) : '',
      'disabilityPercentage': disabled ? t(_disabilityPercentageController) : '',
      'disabilityCertNo': disabled ? t(_disabilityCertNoController) : '',
      'disabilityCertFile': '',
      'designation': _designation,
      'department': _department,
      'jobPosition': t(_jobPositionController),
      'reportingManager': _effectiveReportingManager,
      'employmentType': _employmentType,
      'contact': t(_emailController),
      'joiningDate': _employmentType == 'Intern' ? '' : _joiningDate,
      'onboardingDate': (_employmentType == 'Full Time' || _employmentType == 'Part Time') ? _onboardingDate : '',
      'internStartDate': _employmentType == 'Intern' ? _internStartDate : '',
      'internEndDate': _employmentType == 'Intern' ? _internEndDate : '',
      'uanNumber': t(_uanController),
      'esiNumber': t(_esiController),
      'pfNumber': t(_pfController),
      'esiStartDate': _esiStartDate,
      'pfStartDate': _pfStartDate,
      'bankName': t(_bankNameController),
      'accountHolderName': t(_accountHolderController),
      'accountNumber': t(_accountNumberController),
      'ifscCode': t(_ifscController).toUpperCase(),
      'bankBranch': t(_bankBranchController),
      'upiId': t(_upiController),
      'profilePic': _profilePic,
      'salaryTemplate': _salaryTemplate,
      'leaveTemplate': _leaveTemplate,
      'holidayTemplate': _holidayTemplate,
      'breakTemplate': _breakTemplate,
      'overtimeTemplate': _overtimeTemplate,
      'permissionTemplate': _permissionTemplate,
      'attendanceTemplate': _attendanceTemplate,
      'weeklyOffTemplate': _weeklyOffTemplate,
      'status': 'Active',
      'branch': _selectedBranch,
      'workMode': {
        'mode': mode,
        'address': (mode == 'WFH' || mode == 'Hybrid') ? t(_workAddressController) : '',
        if (mode == 'WFH' || mode == 'Hybrid') ...{
          'latitude': double.parse(t(_latitudeController)),
          'longitude': double.parse(t(_longitudeController)),
          'radius': int.parse(t(_radiusController)),
        },
        if (mode == 'Remote') 'radius': 0,
      },
    };

    setState(() => _isSubmitting = true);
    final res = await _staffService.createStaff(payload);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'New employee added successfully!');
      Navigator.pop(context, true);
    } else {
      SnackBarUtils.showSnackBar(
        context,
        (res['message'] ?? 'Failed to create staff. Please check fields and try again.').toString(),
        isError: true,
      );
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Add Staff Member'),
      ),
      body: _isLoadingSetup
          ? const Center(child: AppTabLoader())
          : _loadError != null
              ? _buildLoadError()
              : Column(
                  children: [
                    _buildStepperHeader(),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          if (_currentStep == 0) _buildStepPersonal(),
                          if (_currentStep == 1) _buildStepAddress(),
                          if (_currentStep == 2) _buildStepEmployment(),
                          if (_currentStep == 3) _buildStepBank(),
                        ],
                      ),
                    ),
                    _buildBottomActions(),
                  ],
                ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, size: 30, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(_loadError!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadSetupData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: _cardBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Row(
        children: List.generate(_steps.length, (idx) {
          final isDone = idx < _currentStep;
          final isCurrent = idx == _currentStep;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentStep = idx),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.primary
                          : isDone
                              ? AppColors.success
                              : AppColors.background,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.primary
                            : isDone
                                ? AppColors.success
                                : _fieldBorder,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isDone
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : Text(
                            '${idx + 1}',
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isCurrent ? AppColors.onPrimary : AppColors.textSecondary,
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _steps[idx],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── STEP 1: Personal & contact ──
  Widget _buildStepPersonal() {
    final married = _maritalStatus == 'Married';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard('Profile Photo', [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  backgroundImage: _profilePicBytes != null ? MemoryImage(_profilePicBytes!) : null,
                  child: _profilePic.isEmpty
                      ? Icon(Icons.person_outline_rounded, color: AppColors.primaryText, size: 30)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('JPG, PNG, WEBP or GIF, up to 5MB. Optional.', style: AppTextStyles.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickProfilePic,
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: Text(_profilePic.isEmpty ? 'Choose photo' : 'Change'),
                        ),
                        if (_profilePic.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() {
                              _profilePic = '';
                              _profilePicBytes = null;
                            }),
                            style: TextButton.styleFrom(foregroundColor: AppColors.error),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 12),
        _formCard('Personal Information', [
          _textField('First Name *', _firstNameController, hint: 'e.g. Rahul'),
          const SizedBox(height: 12),
          _textField('Last Name *', _lastNameController, hint: 'e.g. Sharma'),
          const SizedBox(height: 12),
          _dateField('Date of Birth *', _dob, (v) => setState(() => _dob = v), last: DateTime.now()),
          const SizedBox(height: 12),
          _dropdownField('Gender *', _gender, const ['Male', 'Female', 'Other'],
              (v) => setState(() => _gender = v), hint: 'Select Gender'),
          const SizedBox(height: 12),
          _dropdownField('Blood Group *', _bloodGroup, _bloodGroups, (v) => setState(() => _bloodGroup = v),
              hint: 'Select Blood Group'),
          const SizedBox(height: 12),
          _textField("Father's Name *", _fatherNameController, hint: 'Full Name'),
          const SizedBox(height: 12),
          _segmented('Marital Status *', _maritalStatus, const ['Single', 'Married'],
              (v) => setState(() => _maritalStatus = v)),
          if (married) ...[
            const SizedBox(height: 12),
            _textField("Spouse's Name *", _spouseNameController, hint: 'Full Name'),
          ],
        ]),
        const SizedBox(height: 12),
        _formCard('Contact & Login', [
          _textField('Email ID *', _emailController,
              hint: 'rahul.sharma@company.com', keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _phoneField('Phone Number *', _countryCode, (v) => setState(() => _countryCode = v), _phoneController),
          const SizedBox(height: 12),
          _phoneField('Alternate Phone Number *', _altCountryCode, (v) => setState(() => _altCountryCode = v),
              _altPhoneController),
          const SizedBox(height: 12),
          _textField('Password *', _passwordController,
              obscure: !_showPassword,
              suffix: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20, color: AppColors.textSecondary),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              )),
          const SizedBox(height: 6),
          const Text('Min 8 characters with upper, lower, number and special character.',
              style: AppTextStyles.caption),
          const SizedBox(height: 12),
          _textField('Confirm Password *', _confirmPasswordController,
              obscure: !_showConfirmPassword,
              suffix: IconButton(
                tooltip: _showConfirmPassword ? 'Hide password' : 'Show password',
                icon: Icon(_showConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20, color: AppColors.textSecondary),
                onPressed: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
              )),
        ]),
      ],
    );
  }

  // ── STEP 2: Address & identity ──
  Widget _buildStepAddress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard('Current Address', [
          _textField('Address *', _currentAddressController, hint: 'Flat / House No, Street, City', maxLines: 2),
          const SizedBox(height: 12),
          _textField('Country *', _currentCountryController, hint: 'India'),
          const SizedBox(height: 12),
          _textField('State *', _currentStateController, hint: 'Maharashtra'),
          const SizedBox(height: 12),
          _textField('Pincode *', _currentPincodeController, hint: '400001', keyboardType: TextInputType.number),
        ]),
        const SizedBox(height: 12),
        _formCard('Permanent Address', [
          CheckboxListTile(
            value: _sameAddress,
            onChanged: (v) => setState(() => _sameAddress = v ?? false),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Same as current address', style: AppTextStyles.label),
          ),
          if (!_sameAddress) ...[
            const SizedBox(height: 8),
            _textField('Address *', _permanentAddressController, hint: 'Flat / House No, Street, City', maxLines: 2),
            const SizedBox(height: 12),
            _textField('Country *', _permanentCountryController, hint: 'India'),
            const SizedBox(height: 12),
            _textField('State *', _permanentStateController, hint: 'Maharashtra'),
            const SizedBox(height: 12),
            _textField('Pincode *', _permanentPincodeController,
                hint: '400001', keyboardType: TextInputType.number),
          ],
        ]),
        const SizedBox(height: 12),
        _formCard('Government Identification', [
          _textField('PAN Number', _panController, hint: 'ABCDE1234F'),
          const SizedBox(height: 12),
          _textField('Aadhaar Number', _aadhaarController, hint: '123456789012', keyboardType: TextInputType.number),
        ]),
        const SizedBox(height: 12),
        _formCard('Physically Challenged', [
          _segmented('Is the employee physically challenged?', _isPhysicallyChallenged, const ['No', 'Yes'],
              (v) => setState(() => _isPhysicallyChallenged = v)),
          if (_isPhysicallyChallenged == 'Yes') ...[
            const SizedBox(height: 12),
            _textField('Disability Type', _disabilityTypeController, hint: 'e.g., Visual, Hearing, Locomotor'),
            const SizedBox(height: 12),
            _textField('Disability Percentage (%)', _disabilityPercentageController,
                hint: 'e.g., 40', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            _textField('Disability Certificate Number', _disabilityCertNoController, hint: 'Certificate Number'),
          ],
        ]),
      ],
    );
  }

  // ── STEP 3: Employment & templates ──
  Widget _buildStepEmployment() {
    final isIntern = _employmentType == 'Intern';
    final needsOnboarding = _employmentType == 'Full Time' || _employmentType == 'Part Time';
    final branchItems = _branches
        .map((b) => MapEntry((b['_id'] ?? '').toString(), (b['branchName'] ?? b['_id'] ?? '').toString()))
        .where((e) => e.key.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard('Role & Organization', [
          _textField('Employee ID *', _employeeIdController, hint: 'EMP-001'),
          const SizedBox(height: 12),
          _dropdownField('Employment Type', _employmentType, _employmentTypes,
              (v) => setState(() => _employmentType = v ?? 'Full Time')),
          const SizedBox(height: 12),
          if (isIntern) ...[
            _dateField('Start Date *', _internStartDate, (v) => setState(() => _internStartDate = v)),
            const SizedBox(height: 12),
            _dateField('End Date *', _internEndDate, (v) => setState(() => _internEndDate = v)),
          ] else ...[
            _dateField('Joining Date *', _joiningDate, (v) => setState(() => _joiningDate = v)),
            if (needsOnboarding) ...[
              const SizedBox(height: 12),
              _dateField('Onboarding Date *', _onboardingDate, (v) => setState(() => _onboardingDate = v)),
            ],
          ],
          const SizedBox(height: 12),
          _keyedDropdown(
            'Department *',
            _department,
            _departmentOptions.map((d) => MapEntry(d[0], d[1])).toList(),
            (v) => setState(() => _department = v),
            hint: 'Choose',
          ),
          const SizedBox(height: 12),
          _dropdownField('Designation *', _designation, _designationOptions, (v) {
            setState(() => _designation = v);
            _loadReportingManagers();
          }, hint: 'Choose Designation'),
          const SizedBox(height: 12),
          _textField('Job Role *', _jobPositionController, hint: 'Software Engineer'),
          const SizedBox(height: 12),
          _buildReportingManagerField(),
          const SizedBox(height: 12),
          _keyedDropdown(
            'Branch *',
            _selectedBranch,
            branchItems,
            (v) => setState(() => _selectedBranch = v),
            hint: branchItems.isEmpty ? 'No Branches Configured' : 'Choose',
          ),
        ]),
        const SizedBox(height: 12),
        _formCard('Work Mode', [
          _keyedDropdown(
            'Work Mode *',
            _workMode,
            _workModes.map((m) => MapEntry(m[0], m[1])).toList(),
            (v) => setState(() => _workMode = v),
            hint: 'Choose',
          ),
          if (_workMode == 'WFH' || _workMode == 'Hybrid') ...[
            const SizedBox(height: 12),
            _textField(
              _workMode == 'WFH' ? 'Work From Home Location' : 'Additional Work Location',
              _workAddressController,
              hint: 'Enter address',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _textField('Latitude *', _latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _textField('Longitude *', _longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _textField('Radius (Meters) *', _radiusController, keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLocating ? null : _useCurrentLocation,
              icon: _isLocating
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.my_location_rounded, size: 18, color: AppColors.primaryText),
              label: const Text('Use my current location'),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        _formCard('Templates', [
          _templateDropdown('Salary Template *', _salaryTemplate, _salaryTemplates,
              (v) => setState(() => _salaryTemplate = v), nameKey: 'title'),
          const SizedBox(height: 12),
          _templateDropdown('Attendance Template *', _attendanceTemplate, _attendanceTemplates,
              (v) => setState(() => _attendanceTemplate = v)),
          const SizedBox(height: 12),
          _templateDropdown('Leave Template *', _leaveTemplate, _leaveTemplates,
              (v) => setState(() => _leaveTemplate = v)),
          const SizedBox(height: 12),
          _templateDropdown('Holiday Template *', _holidayTemplate, _holidayTemplates,
              (v) => setState(() => _holidayTemplate = v)),
          const SizedBox(height: 12),
          _templateDropdown('Weekly Off Template *', _weeklyOffTemplate, _weeklyOffTemplates,
              (v) => setState(() => _weeklyOffTemplate = v)),
          const SizedBox(height: 12),
          _templateDropdown('Break Template *', _breakTemplate, _breakTemplates,
              (v) => setState(() => _breakTemplate = v)),
          const SizedBox(height: 12),
          _templateDropdown('Overtime Template *', _overtimeTemplate, _overtimeTemplates,
              (v) => setState(() => _overtimeTemplate = v)),
          const SizedBox(height: 12),
          _templateDropdown('Permission Template *', _permissionTemplate, _permissionTemplates,
              (v) => setState(() => _permissionTemplate = v)),
        ]),
      ],
    );
  }

  Widget _buildReportingManagerField() {
    final required = _managerOptions.isNotEmpty;
    final label = 'Reporting Manager${required ? ' *' : ''}';
    if (_isLoadingManagers) {
      return _staticField(label, 'Loading reporting managers...');
    }
    if (_managersError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _staticField(label, _managersError!, color: AppColors.error),
          TextButton.icon(
            onPressed: _loadReportingManagers,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }
    final reportsTo = _managerReportsTo.join(' or ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dropdownField(
          label,
          _managerOptions.contains(_effectiveReportingManager) ? _effectiveReportingManager : null,
          _managerOptions,
          (v) => setState(() => _reportingManager = v),
          hint: 'No reporting manager available',
        ),
        if (_designation != null) ...[
          const SizedBox(height: 4),
          Text(
            reportsTo.isNotEmpty
                ? 'Defaults to the company admin. $_designation may also report to a $reportsTo.'
                : 'Defaults to the company admin. A $_designation has no level above them in the staff hierarchy.',
            style: AppTextStyles.caption,
          ),
        ],
      ],
    );
  }

  // ── STEP 4: Bank & statutory ──
  Widget _buildStepBank() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard('Bank Account Details', [
          _textField('Bank Name', _bankNameController, hint: 'HDFC Bank'),
          const SizedBox(height: 12),
          _textField('Account Holder Name', _accountHolderController, hint: 'As per bank records'),
          const SizedBox(height: 12),
          _textField('Account Number', _accountNumberController,
              hint: '9 to 18 digits', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _textField('IFSC Code', _ifscController, hint: 'HDFC0001234'),
          const SizedBox(height: 12),
          _textField('Bank Branch', _bankBranchController, hint: 'Branch name'),
          const SizedBox(height: 12),
          _textField('UPI ID', _upiController, hint: 'name@bank'),
        ]),
        const SizedBox(height: 12),
        _formCard('Statutory & Compliance', [
          _textField('UAN Number', _uanController, hint: '12 digits', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _textField('PF Number', _pfController, hint: 'Up to 22 characters'),
          const SizedBox(height: 12),
          _dateField('PF Start Date', _pfStartDate, (v) => setState(() => _pfStartDate = v), clearable: true),
          const SizedBox(height: 12),
          _textField('ESI Number', _esiController, hint: '17 digits', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _dateField('ESI Start Date', _esiStartDate, (v) => setState(() => _esiStartDate = v), clearable: true),
        ]),
      ],
    );
  }

  // ───────────────────────── Widgets ─────────────────────────

  Widget _formCard(String title, List<Widget> children) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      border: Border.all(color: _cardBorder),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppTextStyles.headingSmall)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: AppTextStyles.label.copyWith(fontSize: 13, color: AppColors.textSecondary),
        ),
      );

  /// Theme-styled field shell for non-TextField inputs (date, dropdown, static).
  InputDecoration get _shellDecoration => const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Widget _textField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }

  Widget _staticField(String label, String text, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        InputDecorator(
          decoration: _shellDecoration,
          child: Text(text, style: AppTextStyles.bodyMedium.copyWith(color: color ?? AppColors.textCaption)),
        ),
      ],
    );
  }

  Widget _dateField(
    String label,
    String value,
    ValueChanged<String> onPicked, {
    DateTime? last,
    bool clearable = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        InkWell(
          onTap: () => _pickDate(value, onPicked, last: last),
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: _shellDecoration,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isEmpty ? 'Select date' : value,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: value.isEmpty ? FontWeight.w400 : FontWeight.w500,
                      color: value.isEmpty ? AppColors.textCaption : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (clearable && value.isNotEmpty)
                  GestureDetector(
                    onTap: () => onPicked(''),
                    child: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                  )
                else
                  const Icon(Icons.calendar_today_outlined, size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneField(
    String label,
    String code,
    ValueChanged<String> onCode,
    TextEditingController controller,
  ) {
    final codes = _phoneLengths.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: InputDecorator(
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: codes.contains(code) ? code : '+91',
                    isDense: true,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                    items: codes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => onCode(v ?? '+91'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                style: AppTextStyles.bodyMedium,
                decoration: const InputDecoration(hintText: 'Phone number'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _segmented(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Row(
          children: options.map((o) {
            final selected = o == value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: o == options.last ? 0 : 8),
                child: InkWell(
                  onTap: () => onChanged(o),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppColors.primary : _fieldBorder,
                        width: selected ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) ...[
                          Icon(Icons.check_rounded, size: 16, color: AppColors.primaryText),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            o,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.label.copyWith(
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _dropdownField(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    String? hint,
  }) {
    return _keyedDropdown(label, value, items.map((e) => MapEntry(e, e)).toList(), onChanged, hint: hint);
  }

  Widget _keyedDropdown(
    String label,
    String? value,
    List<MapEntry<String, String>> items,
    ValueChanged<String?> onChanged, {
    String? hint,
  }) {
    final hasValue = value != null && items.any((e) => e.key == value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        InputDecorator(
          decoration: _shellDecoration,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: hasValue ? value : null,
              isExpanded: true,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              hint: Text(hint ?? 'Select', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textCaption)),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
              items: items
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: items.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _templateDropdown(
    String label,
    String? value,
    List<Map<String, dynamic>> items,
    ValueChanged<String?> onChanged, {
    String nameKey = 'name',
  }) {
    final entries = items
        .map((t) => MapEntry((t['_id'] ?? '').toString(), (t[nameKey] ?? t['name'] ?? t['title'] ?? '').toString()))
        .where((e) => e.key.isNotEmpty)
        .toList();
    return _keyedDropdown(label, value, entries, onChanged,
        hint: entries.isEmpty ? 'No templates configured' : 'Select Template');
  }

  Widget _buildBottomActions() {
    final isLast = _currentStep == _steps.length - 1;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: _cardBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => setState(() => _currentStep--),
                    child: const Text('Previous'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          if (!isLast) {
                            setState(() => _currentStep++);
                          } else {
                            _submitAddStaff();
                          }
                        },
                  child: _isSubmitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : Text(isLast ? 'Create Staff Member' : 'Next Step →'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
