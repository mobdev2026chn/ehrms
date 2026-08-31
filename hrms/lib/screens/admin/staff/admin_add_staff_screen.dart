// lib/screens/admin/staff/admin_add_staff_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_staff_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminAddStaffScreen extends StatefulWidget {
  const AdminAddStaffScreen({super.key});

  @override
  State<AdminAddStaffScreen> createState() => _AdminAddStaffScreenState();
}

class _AdminAddStaffScreenState extends State<AdminAddStaffScreen> {
  final AdminStaffService _staffService = AdminStaffService();
  int _currentStep = 0;
  bool _isLoadingSetup = true;
  bool _isSubmitting = false;

  // Setup options from GET /admin/staff/setup
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _attendanceTemplates = [];
  List<Map<String, dynamic>> _shiftTemplates = [];
  List<Map<String, dynamic>> _weeklyOffTemplates = [];
  List<Map<String, dynamic>> _leaveTemplates = [];
  List<Map<String, dynamic>> _holidayTemplates = [];
  List<Map<String, dynamic>> _breakTemplates = [];
  List<Map<String, dynamic>> _overtimeTemplates = [];
  List<Map<String, dynamic>> _permissionTemplates = [];
  List<Map<String, dynamic>> _salaryTemplates = [];
  List<Map<String, dynamic>> _reportingManagers = [];

  // Form Controllers - Step 1: Basic Info
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _fatherNameController = TextEditingController();
  final TextEditingController _panController = TextEditingController();
  final TextEditingController _aadhaarController = TextEditingController();
  String _gender = 'Male';
  String _maritalStatus = 'Single';
  String _bloodGroup = 'O+';

  // Form Controllers - Step 2: Employment & Templates
  final TextEditingController _employeeIdController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _joiningDateController = TextEditingController();
  String _employmentType = 'Full Time';
  String? _selectedBranch;
  String? _selectedReportingManager;
  String _workMode = 'In Office';

  // Selected Templates
  String? _selectedAttendanceTemplate;
  String? _selectedShiftTemplate;
  String? _selectedWeeklyOffTemplate;
  String? _selectedLeaveTemplate;
  String? _selectedHolidayTemplate;
  String? _selectedBreakTemplate;
  String? _selectedOvertimeTemplate;
  String? _selectedPermissionTemplate;
  String? _selectedSalaryTemplate;

  // Form Controllers - Step 3: Bank & Address
  final TextEditingController _currentAddressController = TextEditingController();
  final TextEditingController _currentPincodeController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountNumberController = TextEditingController();
  final TextEditingController _ifscController = TextEditingController();
  final TextEditingController _uanController = TextEditingController();
  final TextEditingController _pfController = TextEditingController();
  final TextEditingController _esiController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSetupData();
  }

  Future<void> _loadSetupData() async {
    setState(() => _isLoadingSetup = true);
    try {
      // 1. Fetch setup templates
      final setupRes = await _staffService.getStaffSetup();
      if (setupRes['success'] == true && setupRes['data'] != null) {
        final data = setupRes['data'];
        _branches = (data['branches'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _attendanceTemplates = (data['attendanceTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _shiftTemplates = (data['shiftTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _weeklyOffTemplates = (data['weeklyOffTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _leaveTemplates = (data['leaveTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _holidayTemplates = (data['holidayTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _breakTemplates = (data['breakTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _overtimeTemplates = (data['overtimeTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _permissionTemplates = (data['permissionTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _salaryTemplates = (data['salaryTemplates'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

        // Preselect first branch & templates if available
        if (_branches.isNotEmpty) {
          _selectedBranch = (_branches.first['branchName'] ?? _branches.first['name'] ?? '').toString();
        }
        if (_attendanceTemplates.isNotEmpty) _selectedAttendanceTemplate = (_attendanceTemplates.first['name'] ?? _attendanceTemplates.first['title'] ?? '').toString();
        if (_shiftTemplates.isNotEmpty) _selectedShiftTemplate = (_shiftTemplates.first['name'] ?? _shiftTemplates.first['title'] ?? '').toString();
        if (_weeklyOffTemplates.isNotEmpty) _selectedWeeklyOffTemplate = (_weeklyOffTemplates.first['name'] ?? _weeklyOffTemplates.first['title'] ?? '').toString();
        if (_leaveTemplates.isNotEmpty) _selectedLeaveTemplate = (_leaveTemplates.first['name'] ?? _leaveTemplates.first['title'] ?? '').toString();
        if (_holidayTemplates.isNotEmpty) _selectedHolidayTemplate = (_holidayTemplates.first['name'] ?? _holidayTemplates.first['title'] ?? '').toString();
      }

      // 2. Fetch Next Employee ID
      final nextEmpId = await _staffService.getNextEmployeeId();
      if (nextEmpId != null && nextEmpId.isNotEmpty) {
        _employeeIdController.text = nextEmpId;
      } else {
        _employeeIdController.text = 'EMP-017';
      }

      // 3. Fetch Staff list for reporting managers
      final staffRes = await _staffService.getStaffList();
      if (staffRes['success'] == true && staffRes['data'] != null) {
        final list = (staffRes['data']['staff'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _reportingManagers = list;
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingSetup = false);
  }

  Future<void> _submitAddStaff() async {
    if (_firstNameController.text.trim().isEmpty) {
      SnackBarUtils.showSnackBar(context, 'First name is required', isError: true);
      setState(() => _currentStep = 0);
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Email address is required', isError: true);
      setState(() => _currentStep = 0);
      return;
    }
    if (_designationController.text.trim().isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Designation is required', isError: true);
      setState(() => _currentStep = 1);
      return;
    }

    setState(() => _isSubmitting = true);

    final payload = {
      'employeeId': _employeeIdController.text.trim(),
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'name': '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim(),
      'contact': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'dob': _dobController.text.trim(),
      'gender': _gender,
      'maritalStatus': _maritalStatus,
      'bloodGroup': _bloodGroup,
      'fatherName': _fatherNameController.text.trim(),
      'pan': _panController.text.trim(),
      'aadhaar': _aadhaarController.text.trim(),
      'designation': _designationController.text.trim(),
      'department': _departmentController.text.trim().isNotEmpty ? _departmentController.text.trim() : 'Engineering',
      'employmentType': _employmentType,
      'branch': _selectedBranch ?? 'Main Branch',
      'joiningDate': _joiningDateController.text.trim().isNotEmpty ? _joiningDateController.text.trim() : DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'reportingManager': _selectedReportingManager,
      'attendanceTemplate': _selectedAttendanceTemplate,
      'shiftTemplate': _selectedShiftTemplate,
      'weeklyOffTemplate': _selectedWeeklyOffTemplate,
      'leaveTemplate': _selectedLeaveTemplate,
      'holidayTemplate': _selectedHolidayTemplate,
      'breakTemplate': _selectedBreakTemplate,
      'overtimeTemplate': _selectedOvertimeTemplate,
      'permissionTemplate': _selectedPermissionTemplate,
      'salaryTemplate': _selectedSalaryTemplate,
      'currentAddress': _currentAddressController.text.trim(),
      'currentPincode': _currentPincodeController.text.trim(),
      'bankName': _bankNameController.text.trim(),
      'accountNumber': _accountNumberController.text.trim(),
      'ifscCode': _ifscController.text.trim(),
      'uanNumber': _uanController.text.trim(),
      'pfNumber': _pfController.text.trim(),
      'esiNumber': _esiController.text.trim(),
      'status': 'Active',
    };

    final res = await _staffService.createStaff(payload);
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, 'Staff member created successfully!');
        Navigator.pop(context, true);
      }
    } else {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, res['message'] ?? 'Failed to create staff member', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add Staff Member',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
      ),
      body: _isLoadingSetup
          ? const Center(child: AppTabLoader())
          : Column(
              children: [
                // ── Step Navigation Bar ──
                _buildStepperHeader(),

                // ── Active Step Form ──
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_currentStep == 0) _buildStep1BasicInfo(),
                      if (_currentStep == 1) _buildStep2EmploymentAndTemplates(),
                      if (_currentStep == 2) _buildStep3BankAndAddress(),
                    ],
                  ),
                ),

                // ── Bottom Step Control Actions ──
                _buildBottomActions(),
              ],
            ),
    );
  }

  Widget _buildStepperHeader() {
    final steps = ['Basic Info', 'Employment', 'Bank & Address'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(steps.length, (idx) {
          final isDone = idx < _currentStep;
          final isCurrent = idx == _currentStep;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentStep = idx),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0xFFEFAA1F)
                          : isDone
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: isDone
                        ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                        : Text(
                            '${idx + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isCurrent ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[idx],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                        color: isCurrent ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (idx < steps.length - 1)
                    Container(
                      width: 16,
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isDone ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── STEP 1: Basic Information ──
  Widget _buildStep1BasicInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard('Personal Details', [
          _textField('First Name *', _firstNameController, hint: 'e.g. Rahul'),
          const SizedBox(height: 12),
          _textField('Last Name', _lastNameController, hint: 'e.g. Sharma'),
          const SizedBox(height: 12),
          _textField('Official Email Address *', _emailController, hint: 'rahul.sharma@ekta.hr', keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _textField('Phone Number', _phoneController, hint: '+91 9876543210', keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          _dropdownField('Gender', _gender, ['Male', 'Female', 'Other'], (val) => setState(() => _gender = val!)),
          const SizedBox(height: 12),
          _dropdownField('Blood Group', _bloodGroup, ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'], (val) => setState(() => _bloodGroup = val!)),
          const SizedBox(height: 12),
          _textField('Date of Birth (YYYY-MM-DD)', _dobController, hint: '1996-08-15'),
          const SizedBox(height: 12),
          _textField('Father / Spouse Name', _fatherNameController, hint: 'Full Name'),
        ]),
        const SizedBox(height: 14),
        _formCard('Government Identification', [
          _textField('PAN Number', _panController, hint: 'ABCDE1234F'),
          const SizedBox(height: 12),
          _textField('Aadhaar Number', _aadhaarController, hint: '1234 5678 9012', keyboardType: TextInputType.number),
        ]),
      ],
    );
  }

  // ── STEP 2: Employment & Templates ──
  Widget _buildStep2EmploymentAndTemplates() {
    final branchNames = _branches.map((b) => (b['branchName'] ?? b['name'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
    if (branchNames.isEmpty) branchNames.add('Main Branch');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard('Designation & Role', [
          _textField('Employee ID *', _employeeIdController, hint: 'EMP-017'),
          const SizedBox(height: 12),
          _textField('Designation *', _designationController, hint: 'Senior Software Engineer'),
          const SizedBox(height: 12),
          _textField('Department', _departmentController, hint: 'Engineering'),
          const SizedBox(height: 12),
          _dropdownField('Employment Type', _employmentType, ['Full Time', 'Part Time', 'Contract', 'Intern'], (val) => setState(() => _employmentType = val!)),
          const SizedBox(height: 12),
          _dropdownField('Assigned Branch *', _selectedBranch ?? branchNames.first, branchNames, (val) => setState(() => _selectedBranch = val!)),
          const SizedBox(height: 12),
          _textField('Joining Date (YYYY-MM-DD)', _joiningDateController, hint: DateFormat('yyyy-MM-dd').format(DateTime.now())),
        ]),
        const SizedBox(height: 14),
        _formCard('HR & Attendance Templates (Web Backend Parity)', [
          _templateDropdown('Attendance Template', _selectedAttendanceTemplate, _attendanceTemplates, (val) => setState(() => _selectedAttendanceTemplate = val)),
          const SizedBox(height: 12),
          _templateDropdown('Shift Template', _selectedShiftTemplate, _shiftTemplates, (val) => setState(() => _selectedShiftTemplate = val)),
          const SizedBox(height: 12),
          _templateDropdown('Weekly Off Template', _selectedWeeklyOffTemplate, _weeklyOffTemplates, (val) => setState(() => _selectedWeeklyOffTemplate = val)),
          const SizedBox(height: 12),
          _templateDropdown('Leave Template', _selectedLeaveTemplate, _leaveTemplates, (val) => setState(() => _selectedLeaveTemplate = val)),
          const SizedBox(height: 12),
          _templateDropdown('Holiday Template', _selectedHolidayTemplate, _holidayTemplates, (val) => setState(() => _selectedHolidayTemplate = val)),
        ]),
      ],
    );
  }

  // ── STEP 3: Bank & Address ──
  Widget _buildStep3BankAndAddress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard('Address Details', [
          _textField('Current Residential Address', _currentAddressController, hint: 'Flat / House No, Street, City'),
          const SizedBox(height: 12),
          _textField('Pincode', _currentPincodeController, hint: '400001', keyboardType: TextInputType.number),
        ]),
        const SizedBox(height: 14),
        _formCard('Bank Account Details', [
          _textField('Bank Name', _bankNameController, hint: 'HDFC Bank'),
          const SizedBox(height: 12),
          _textField('Account Number', _accountNumberController, hint: '50100234567890', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _textField('IFSC Code', _ifscController, hint: 'HDFC0001234'),
        ]),
        const SizedBox(height: 14),
        _formCard('Statutory & Compliance Numbers', [
          _textField('UAN Number', _uanController, hint: '100904567890'),
          const SizedBox(height: 12),
          _textField('PF Number', _pfController, hint: 'MH/BAN/0012345/000/0001'),
          const SizedBox(height: 12),
          _textField('ESI Number', _esiController, hint: '31000123450000101'),
        ]),
      ],
    );
  }

  Widget _formCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _textField(String label, TextEditingController controller, {String? hint, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownField(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _templateDropdown(String label, String? value, List<Map<String, dynamic>> items, ValueChanged<String?> onChanged) {
    final names = items.map((e) => (e['name'] ?? e['title'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
    if (names.isEmpty) names.add('Default Template');

    return _dropdownField(label, names.contains(value) ? value! : names.first, names, onChanged);
  }

  Widget _buildBottomActions() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep--),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Previous', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      if (_currentStep < 2) {
                        setState(() => _currentStep++);
                      } else {
                        _submitAddStaff();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEFAA1F),
                foregroundColor: const Color(0xFF0F172A),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                  : Text(
                      _currentStep < 2 ? 'Next Step →' : 'Create Staff Member',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
