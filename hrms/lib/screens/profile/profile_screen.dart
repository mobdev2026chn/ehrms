// hrms/lib/screens/profile/profile_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/staff_custom_fields_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/avatar_orientation.dart';
import '../../utils/attendance_selfie_compress.dart';
import '../../utils/rotational_shift_util.dart';
import '../../widgets/app_tab_loader.dart';
import '../notifications/notifications_screen.dart';
import 'face_enroll_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  const ProfileScreen({
    super.key,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final OnboardingService _onboardingService = OnboardingService();
  final StaffCustomFieldsService _staffCustomFieldsService =
      StaffCustomFieldsService();
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _onboardingData;         
  List<dynamic> _documents = [];
  List<Map<String, dynamic>> _activeStaffCustomFields = [];
  bool _isLoading = true;
  bool _isLoadingDocs = false;
  bool _profileImageError = false;
  String? _cachedAvatarUrl;
  // Some devices stored the first-punch selfie upside-down; flip on display when
  // the image's detected orientation says so (resolved once per URL).
  bool _avatarNeedsFlip = false;
  String? _flipResolvedForUrl;
  late TabController _tabController;

  /// Two font sizes for entire profile: heading and value
  static const double _profileHeadingSize = 14;
  static const double _profileValueSize = 13;

  Map<String, dynamic> _formData = {};
  final Map<String, bool> _editingSections = {
    'personal': false,
    'contact': false,
    'address': false,
    'bank': false,
  };
  bool _isSavingSection = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        // Rebuild so AppBar actions can react to tab changes
        if (mounted) {
          setState(() {});
        }
      });
    _loadProfile();
    _loadDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final loaded = await Future.wait<dynamic>([
      _authService.getProfile(),
      _authService.getToken(),
    ]);
    final result = loaded[0] as Map<String, dynamic>;
    final token = loaded[1] as String?;
    List<Map<String, dynamic>> customFields = [];
    if (token != null && token.trim().isNotEmpty) {
      customFields = await _staffCustomFieldsService.fetchActiveStaffCustomFields(
        token: token,
      );
    }
    String? cachedUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final user = jsonDecode(userStr) as Map<String, dynamic>?;
        if (user != null) {
          cachedUrl = (user['avatar'] ?? user['photoUrl'])?.toString();
          if (cachedUrl != null) cachedUrl = cachedUrl.trim();
          if (cachedUrl != null && cachedUrl.isEmpty) cachedUrl = null;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _profileImageError = false;
        _cachedAvatarUrl = cachedUrl;
        _activeStaffCustomFields = customFields;
        if (result['success']) {
          final data = result['data'];
          if (data is Map) {
            _userData = Map<String, dynamic>.from(data);
            _formData = _mapDataToForm(_userData);
            // Update stored user with branchName so app drawer shows branch
            final branchName =
                data['branchName']?.toString() ??
                (data['staffData'] is Map
                    ? ((data['staffData'] as Map)['branchId'] is Map
                          ? ((data['staffData'] as Map)['branchId']
                                    as Map)['branchName']
                                ?.toString()
                          : null)
                    : null);
            if (branchName != null && branchName.isNotEmpty) {
              _updateStoredUserBranchName(branchName);
            }
          } else {
            _userData = null;
            _formData = {};
          }
        } else {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'Error loading profile'),
            isError: true,
          );
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStoredUserBranchName(String branchName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final user = jsonDecode(userStr) as Map<String, dynamic>?;
        if (user != null) {
          user['branchName'] = branchName;
          await prefs.setString('user', jsonEncode(user));
        }
      }
    } catch (_) {}
  }

  Map<String, dynamic>? get _profile {
    final profile = _userData?['profile'];
    if (profile == null) return null;
    return Map<String, dynamic>.from(profile as Map);
  }

  Map<String, dynamic>? get _staffData {
    final staffData = _userData?['staffData'];
    if (staffData == null) return null;
    return Map<String, dynamic>.from(staffData as Map);
  }

  /// Detect whether the avatar at [url] is stored upside-down (cached per-URL)
  /// and flip it on display if so. Guarded so it runs at most once per URL.
  void _resolveAvatarFlip(String? url) {
    final key = url?.trim();
    if (key == null || key.isEmpty || !key.startsWith('http')) return;
    if (key == _flipResolvedForUrl) return;
    _flipResolvedForUrl = key;
    AvatarOrientation.resolveNeedsFlip(key).then((resolved) {
      if (!mounted || resolved == null || resolved == _avatarNeedsFlip) return;
      setState(() => _avatarNeedsFlip = resolved);
    });
  }

  Map<String, dynamic>? get _candidateData {
    final candidateId = _staffData?['candidateId'];
    if (candidateId == null) return null;
    if (candidateId is Map) {
      return Map<String, dynamic>.from(candidateId);
    }
    return null;
  }

  Future<void> _refreshProfile() async {
    await Future.wait([_loadProfile(), _loadDocuments()]);
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoadingDocs = true);

    final result = await _onboardingService.getMyOnboarding();

    if (mounted) {
      setState(() {
        if (result['success'] && result['data'] != null) {
          final data = result['data'];

          if (data is Map && data.containsKey('onboarding')) {
            final onboarding = data['onboarding'];
            _onboardingData = onboarding;

            if (onboarding is Map && onboarding.containsKey('documents')) {
              _documents = onboarding['documents'] as List? ?? [];
            } else {
              _documents = [];
            }
          } else {
            _documents = [];
          }
        } else {
          _documents = [];
        }

        _isLoadingDocs = false;
      });
    }
  }

  Future<void> _viewDocument(String? url) async {
    if (url == null || url.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Document URL not available',
        isError: true,
      );

      return;
    }
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Could not open document',
          isError: true,
        );
      }
    }
  }

  Future<void> _downloadDocument(String? url) async {
    if (url == null || url.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Document URL not available',
        isError: true,
      );

      return;
    }

    String downloadUrl = url;
    // For Cloudinary URLs, we can force download by adding fl_attachment
    if (url.contains('res.cloudinary.com')) {
      if (!url.contains('fl_attachment')) {
        // Find /upload/ and insert /fl_attachment/
        downloadUrl = url.replaceFirst('/upload/', '/upload/fl_attachment/');
      }
    }

    try {
      final Uri uri = Uri.parse(downloadUrl);

      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Starting download...',
          backgroundColor: AppColors.primary,
        );
      }

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $downloadUrl';
      }
    } catch (e) {
      if (mounted) {
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
      drawer: AppDrawer(
        currentIndex: widget.dashboardTabIndex ?? 3,
        onNavigateToIndex: widget.onNavigateToIndex,
      ),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('My Profile',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, size: 26),
            color: AppColors.textPrimary,
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'Personal'),
            Tab(text: 'Exp & Edu'),
            Tab(text: 'Documents'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _userData == null
          ? const Center(child: Text('Failed to load profile'))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPersonalInfoTab(),
                _buildExpAndEduTab(),
                _buildDocumentsTab(),
              ],
            ),
      bottomNavigationBar: widget.onNavigateToIndex != null
          ? null
          : const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Map<String, dynamic> _mapDataToForm(Map<String, dynamic>? data) {
    if (data == null) return {};
    final mapped = <String, dynamic>{};
    final staffData = data['staffData'] is Map
        ? Map<String, dynamic>.from(data['staffData'] as Map)
        : <String, dynamic>{};
    final profile = data['profile'] is Map
        ? Map<String, dynamic>.from(data['profile'] as Map)
        : <String, dynamic>{};

    // Employee ID
    mapped['employeeId'] = staffData['employeeId'] ??
        profile['employeeId'] ??
        data['employeeId'] ??
        '';

    // First & Last Name
    final combinedName = (profile['name'] ?? staffData['name'] ?? data['name'] ?? '').toString().trim();
    final nameParts = combinedName.isNotEmpty ? combinedName.split(' ') : <String>[];
    mapped['firstName'] = staffData['firstName'] ??
        profile['firstName'] ??
        data['firstName'] ??
        (nameParts.isNotEmpty ? nameParts.first : '');
    mapped['lastName'] = staffData['lastName'] ??
        profile['lastName'] ??
        data['lastName'] ??
        (nameParts.length > 1 ? nameParts.skip(1).join(' ') : '');

    // DOB
    final rawDob = staffData['dob'] ??
        staffData['dateOfBirth'] ??
        profile['dob'] ??
        profile['dateOfBirth'] ??
        data['dob'] ??
        data['dateOfBirth'];
    if (rawDob != null) {
      try {
        final parsed = DateTime.tryParse(rawDob.toString());
        if (parsed != null) {
          mapped['dob'] = DateFormat('yyyy-MM-dd').format(parsed);
        } else {
          mapped['dob'] = rawDob.toString();
        }
      } catch (_) {
        mapped['dob'] = rawDob.toString();
      }
    } else {
      mapped['dob'] = '';
    }

    // Gender, Blood Group, Father Name
    mapped['gender'] = staffData['gender'] ?? profile['gender'] ?? data['gender'] ?? '';
    mapped['bloodGroup'] = staffData['bloodGroup'] ?? profile['bloodGroup'] ?? data['bloodGroup'] ?? '';
    mapped['fatherName'] = staffData['fatherName'] ?? profile['fatherName'] ?? data['fatherName'] ?? '';

    // Marital Status & Spouse Name
    final rawMarital = staffData['maritalStatus'] ?? profile['maritalStatus'] ?? data['maritalStatus'];
    if (rawMarital is Map) {
      mapped['maritalStatus'] = 'Married';
      mapped['spouseName'] = rawMarital['spouseName'] ?? '';
    } else if (rawMarital != null && rawMarital.toString().toLowerCase() == 'married') {
      mapped['maritalStatus'] = 'Married';
      mapped['spouseName'] = staffData['spouseName'] ?? profile['spouseName'] ?? data['spouseName'] ?? '';
    } else {
      mapped['maritalStatus'] = 'Single';
      mapped['spouseName'] = '';
    }

    // Contact
    mapped['contact'] = profile['email'] ?? staffData['email'] ?? data['email'] ?? data['contact'] ?? '';
    mapped['phone'] = staffData['phone'] ??
        staffData['phoneNumber'] ??
        profile['phone'] ??
        profile['phoneNumber'] ??
        data['phone'] ??
        '';
    mapped['altPhone'] = staffData['altPhone'] ??
        staffData['alternatePhoneNumber'] ??
        profile['altPhone'] ??
        data['altPhone'] ??
        '';

    // Current Address
    final currAddr = staffData['currentAddress'] ?? data['currentAddress'];
    if (currAddr is Map) {
      mapped['currentAddress'] = currAddr['address'] ?? currAddr['line1'] ?? '';
      mapped['currentCountry'] = currAddr['country'] ?? '';
      mapped['currentState'] = currAddr['state'] ?? '';
      mapped['currentPincode'] = currAddr['pincode'] ?? currAddr['postalCode'] ?? '';
    } else {
      mapped['currentAddress'] = staffData['address']?.toString() ?? data['address']?.toString() ?? '';
      mapped['currentCountry'] = '';
      mapped['currentState'] = '';
      mapped['currentPincode'] = '';
    }

    // Permanent Address
    final permAddr = staffData['permanentAddress'] ?? data['permanentAddress'];
    if (permAddr is Map) {
      mapped['permanentAddress'] = permAddr['address'] ?? permAddr['line1'] ?? '';
      mapped['permanentCountry'] = permAddr['country'] ?? '';
      mapped['permanentState'] = permAddr['state'] ?? '';
      mapped['permanentPincode'] = permAddr['pincode'] ?? permAddr['postalCode'] ?? '';
    } else {
      mapped['permanentAddress'] = '';
      mapped['permanentCountry'] = '';
      mapped['permanentState'] = '';
      mapped['permanentPincode'] = '';
    }

    // Disability
    final phys = staffData['physicallyChallenged'] ?? data['physicallyChallenged'];
    if (phys is Map) {
      mapped['isPhysicallyChallenged'] = 'Yes';
      mapped['disabilityType'] = phys['disabilityType'] ?? '';
      mapped['disabilityPercentage'] = phys['disabilityPercentage']?.toString() ?? '';
      mapped['disabilityCertNo'] = phys['certificateNumber'] ?? '';
    } else if (phys != null && (phys.toString().toLowerCase() == 'yes' || phys == true)) {
      mapped['isPhysicallyChallenged'] = 'Yes';
      mapped['disabilityType'] = staffData['disabilityType'] ?? '';
      mapped['disabilityPercentage'] = staffData['disabilityPercentage']?.toString() ?? '';
      mapped['disabilityCertNo'] = staffData['disabilityCertNo'] ?? '';
    } else {
      mapped['isPhysicallyChallenged'] = 'No';
      mapped['disabilityType'] = '';
      mapped['disabilityPercentage'] = '';
      mapped['disabilityCertNo'] = '';
    }

    // Role & Org Setup
    mapped['department'] = staffData['department'] ?? data['department'] ?? '';
    mapped['employmentType'] = staffData['employmentType'] ?? staffData['staffType'] ?? data['employmentType'] ?? 'Full Time';
    mapped['joiningDate'] = _formatDateStr(staffData['joiningDate'] ?? data['joiningDate']);
    mapped['onboardingDate'] = _formatDateStr(staffData['onboardingDate'] ?? data['onboardingDate']);
    mapped['designation'] = staffData['designation'] ?? data['designation'] ?? '';
    mapped['jobRole'] = staffData['jobRole'] ?? data['jobRole'] ?? '';

    // Reporting Manager
    final repMgr = staffData['reportingManager'] ?? data['reportingManager'];
    if (repMgr is Map) {
      final rmName = repMgr['name'] ?? '${repMgr['firstName'] ?? ''} ${repMgr['lastName'] ?? ''}'.trim();
      final rmRole = repMgr['designation'] != null ? ' (${repMgr['designation']})' : '';
      mapped['reportingManager'] = '$rmName$rmRole'.trim();
    } else {
      mapped['reportingManager'] = repMgr?.toString() ?? '';
    }

    // Branch
    final br = staffData['branchId'] ?? data['branchId'] ?? staffData['branch'] ?? data['branch'];
    if (br is Map) {
      mapped['branch'] = br['branchName'] ?? br['name'] ?? br['_id'] ?? '';
    } else {
      mapped['branch'] = br?.toString() ?? '';
    }

    // Work Mode
    mapped['workMode'] = staffData['workMode'] ?? data['workMode'] ?? 'WFH';

    // WFH Location
    final wfhLoc = staffData['wfhLocation'] ?? staffData['workFromHomeLocation'] ?? data['workFromHomeLocation'];
    if (wfhLoc is Map) {
      mapped['wfhLocation'] = wfhLoc['address'] ?? wfhLoc['name'] ?? '';
      mapped['latitude'] = wfhLoc['latitude']?.toString() ?? '';
      mapped['longitude'] = wfhLoc['longitude']?.toString() ?? '';
      mapped['radius'] = wfhLoc['radius']?.toString() ?? '';
    } else {
      mapped['wfhLocation'] = staffData['wfhAddress'] ?? '';
      String lat = staffData['latitude']?.toString() ?? '';
      String lng = staffData['longitude']?.toString() ?? '';
      if (lat.isEmpty && staffData['location'] is Map) {
        final loc = staffData['location'] as Map;
        final coords = loc['coordinates'];
        if (coords is List && coords.length >= 2) {
          lat = coords[1]?.toString() ?? '';
          lng = coords[0]?.toString() ?? '';
        }
      }
      mapped['latitude'] = lat;
      mapped['longitude'] = lng;
      mapped['radius'] = staffData['geofenceRadius']?.toString() ?? '';
    }

    // Bank Details
    final bank = staffData['bankDetails'] ?? data['bankDetails'] ?? {};
    mapped['pan'] = staffData['panNumber'] ?? bank['pan'] ?? data['panNumber'] ?? '';
    mapped['aadhaar'] = staffData['aadhaarNumber'] ?? bank['aadhaar'] ?? data['aadhaarNumber'] ?? '';
    mapped['bankName'] = bank['bankName'] ?? staffData['bankName'] ?? data['bankName'] ?? '';
    mapped['accountHolderName'] = bank['accountHolderName'] ?? staffData['accountHolderName'] ?? data['accountHolderName'] ?? '';
    mapped['accountNumber'] = bank['accountNumber'] ?? staffData['accountNumber'] ?? data['accountNumber'] ?? '';
    mapped['ifscCode'] = bank['ifscCode'] ?? staffData['ifscCode'] ?? data['ifscCode'] ?? '';
    mapped['bankBranch'] = bank['branchName'] ?? bank['bankBranch'] ?? staffData['bankBranch'] ?? data['bankBranch'] ?? '';
    mapped['upiId'] = bank['upiId'] ?? staffData['upiId'] ?? data['upiId'] ?? '';

    // Statutory
    final empIds = staffData['employmentIds'] ?? data['employmentIds'] ?? {};
    mapped['uanNumber'] = empIds['uan'] ?? staffData['uanNumber'] ?? data['uanNumber'] ?? '';
    mapped['pfNumber'] = empIds['pf'] ?? staffData['pfNumber'] ?? data['pfNumber'] ?? '';
    mapped['pfStartDate'] = _formatDateStr(staffData['pfStartDate'] ?? data['pfStartDate']);
    mapped['esiNumber'] = empIds['esi'] ?? staffData['esiNumber'] ?? data['esiNumber'] ?? '';
    mapped['esiStartDate'] = _formatDateStr(staffData['esiStartDate'] ?? data['esiStartDate']);

    // Templates
    mapped['salaryTemplate'] = _extractTemplateName(staffData['salaryTemplate'] ?? data['salaryTemplate']);
    mapped['shiftTemplate'] = _extractTemplateName(staffData['shiftTemplate'] ?? data['shiftTemplate']);
    mapped['leaveTemplate'] = _extractTemplateName(staffData['leaveTemplate'] ?? data['leaveTemplate']);
    mapped['holidayTemplate'] = _extractTemplateName(staffData['holidayTemplate'] ?? data['holidayTemplate']);
    mapped['permissionTemplate'] = _extractTemplateName(staffData['permissionTemplate'] ?? data['permissionTemplate']);
    mapped['overtimeTemplate'] = _extractTemplateName(staffData['overtimeTemplate'] ?? data['overtimeTemplate']);
    mapped['breakTemplate'] = _extractTemplateName(staffData['breakTemplate'] ?? data['breakTemplate']);
    mapped['attendanceTemplate'] = _extractTemplateName(staffData['attendanceTemplate'] ?? data['attendanceTemplate']);
    mapped['weeklyOffTemplate'] = _extractTemplateName(staffData['weeklyOffTemplate'] ?? data['weeklyOffTemplate']);
    mapped['geofenceTemplate'] = _extractTemplateName(staffData['geofenceTemplate'] ?? data['geofenceTemplate']);

    return mapped;
  }

  String _formatDateStr(dynamic raw) {
    if (raw == null) return 'N/A';
    try {
      final str = raw.toString().trim();
      if (str.isEmpty || str == 'N/A') return 'N/A';
      final dt = DateTime.tryParse(str);
      if (dt != null) {
        return '${dt.month}/${dt.day}/${dt.year}';
      }
      return str;
    } catch (_) {
      return raw.toString();
    }
  }

  String _extractTemplateName(dynamic val) {
    if (val == null) return 'None (Not Assigned)';
    if (val is Map) {
      return val['templateName']?.toString() ??
          val['name']?.toString() ??
          val['title']?.toString() ??
          val['_id']?.toString() ??
          'None (Not Assigned)';
    }
    final s = val.toString().trim();
    if (s.isEmpty) return 'None (Not Assigned)';
    return s;
  }

  void _handleCancelEdit(String sectionKey) {
    final original = _mapDataToForm(_userData);
    setState(() {
      _editingSections[sectionKey] = false;
      _formData = original;
    });
  }

  Future<void> _handleSaveSection(String sectionKey) async {
    setState(() => _isSavingSection = true);
    try {
      final payload = <String, dynamic>{};
      if (sectionKey == 'personal') {
        final fn = _formData['firstName']?.toString().trim() ?? '';
        final ln = _formData['lastName']?.toString().trim() ?? '';
        if (fn.isEmpty || ln.isEmpty) {
          SnackBarUtils.showSnackBar(context, 'First Name and Last Name are required.', isError: true);
          setState(() => _isSavingSection = false);
          return;
        }
        payload['firstName'] = fn;
        payload['lastName'] = ln;
        payload['dob'] = _formData['dob'];
        payload['gender'] = _formData['gender'];
        payload['bloodGroup'] = _formData['bloodGroup'];
        payload['fatherName'] = _formData['fatherName'];
        payload['maritalStatus'] = _formData['maritalStatus'];
        payload['spouseName'] = _formData['spouseName'];
      } else if (sectionKey == 'contact') {
        final email = _formData['contact']?.toString().trim() ?? '';
        final phone = _formData['phone']?.toString().trim() ?? '';
        if (email.isEmpty || phone.isEmpty) {
          SnackBarUtils.showSnackBar(context, 'Email and Phone Number are required.', isError: true);
          setState(() => _isSavingSection = false);
          return;
        }
        payload['contact'] = email;
        payload['email'] = email;
        payload['phone'] = phone;
        payload['phoneNumber'] = phone;
        payload['altPhone'] = _formData['altPhone'];
        payload['alternatePhoneNumber'] = _formData['altPhone'];
      } else if (sectionKey == 'address') {
        payload['currentAddress'] = _formData['currentAddress'];
        payload['currentCountry'] = _formData['currentCountry'];
        payload['currentState'] = _formData['currentState'];
        payload['currentPincode'] = _formData['currentPincode'];
        payload['permanentAddress'] = _formData['permanentAddress'];
        payload['permanentCountry'] = _formData['permanentCountry'];
        payload['permanentState'] = _formData['permanentState'];
        payload['permanentPincode'] = _formData['permanentPincode'];
      } else if (sectionKey == 'bank') {
        payload['pan'] = _formData['pan'];
        payload['panNumber'] = _formData['pan'];
        payload['aadhaar'] = _formData['aadhaar'];
        payload['aadhaarNumber'] = _formData['aadhaar'];
        payload['bankName'] = _formData['bankName'];
        payload['accountHolderName'] = _formData['accountHolderName'];
        payload['accountNumber'] = _formData['accountNumber'];
        payload['ifscCode'] = _formData['ifscCode'];
        payload['bankBranch'] = _formData['bankBranch'];
        payload['branchName'] = _formData['bankBranch'];
        payload['upiId'] = _formData['upiId'];
      }

      final res = await _authService.updateProfile(payload);
      if (res['success'] == true) {
        SnackBarUtils.showSnackBar(context, 'Profile section updated successfully.', isError: false);
        setState(() {
          _editingSections[sectionKey] = false;
        });
        await _refreshProfile();
      } else {
        SnackBarUtils.showSnackBar(context, res['message']?.toString() ?? 'Failed to update profile section.', isError: true);
      }
    } catch (e) {
      SnackBarUtils.showSnackBar(context, 'Error saving profile: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingSection = false);
    }
  }

  Future<void> _handleImageUpload() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;

      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 2 * 1024 * 1024) {
        if (mounted) {
          SnackBarUtils.showSnackBar(context, 'Profile image size must be less than 2MB.', isError: true);
        }
        return;
      }

      final base64String = await AttendanceSelfieCompress.compressRawBytesToDataUrl(bytes);
      final res = await _authService.updateProfile({'profilePic': base64String});
      if (res['success'] == true) {
        if (mounted) {
          SnackBarUtils.showSnackBar(context, 'Profile picture updated successfully.', isError: false);
        }
        await _refreshProfile();
      } else {
        // Fallback: try multipart photo upload
        final res2 = await _authService.updateProfilePhoto(file);
        if (res2['success'] == true) {
          if (mounted) {
            SnackBarUtils.showSnackBar(context, 'Profile picture updated successfully.', isError: false);
          }
          await _refreshProfile();
        } else {
          if (mounted) {
            SnackBarUtils.showSnackBar(context, res['message']?.toString() ?? 'Failed to update profile picture.', isError: true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, 'Failed to upload profile picture: $e', isError: true);
      }
    }
  }

  Future<void> _pickDobDate() async {
    final curr = DateTime.tryParse(_formData['dob']?.toString() ?? '') ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: curr,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _formData['dob'] = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Widget _buildPersonalInfoTab() {
    return RefreshIndicator(
      onRefresh: _refreshProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Title
            const Text(
              'My Profile',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your personal and contact details, as recorded by your administrator',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),

            // Profile Hero Card
            _buildWebProfileHeroCard(),
            const SizedBox(height: 16),

            // 1. Personal Information Card
            _buildWebPersonalSection(),

            // 2. Contact Details Card
            _buildWebContactSection(),

            // 3. Address Details Card
            _buildWebAddressSection(),

            // 4. Disability Information Card
            _buildWebDisabilitySection(),

            // 5. Role & Organization Setup Card
            _buildWebRoleSection(),

            // 6. Bank & Statutory Details Card
            _buildWebBankSection(),

            // 7. Policy & Template Configurations Card
            _buildWebPolicySection(),

            // Custom fields if any
            if (_activeStaffCustomFields.isNotEmpty) ...[
              _buildWebCustomFieldsSection(),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildWebProfileHeroCard() {
    final fn = _formData['firstName']?.toString().trim() ?? '';
    final ln = _formData['lastName']?.toString().trim() ?? '';
    final fullName = ('$fn $ln').trim().isNotEmpty
        ? ('$fn $ln').trim()
        : (_profile?['name']?.toString() ?? 'Staff Member');
    final initials = (fn.isNotEmpty ? fn[0] : (fullName.isNotEmpty ? fullName[0] : 'U')).toUpperCase() +
        (ln.isNotEmpty ? ln[0] : '');
    final empId = _formData['employeeId']?.toString() ?? _staffData?['employeeId'] ?? 'EMP-XXX';
    final designation = (_formData['designation']?.toString() ?? _staffData?['designation'] ?? 'EMPLOYEE').toUpperCase();
    final department = (_formData['department']?.toString() ?? _staffData?['department'] ?? 'DEPARTMENT').toUpperCase();

    final photoUrl = _profile?['avatar'] ??
        _profile?['photoUrl'] ??
        _profile?['profilePic'] ??
        _staffData?['avatar'] ??
        _cachedAvatarUrl;
    final photoUrlStr = photoUrl?.toString().trim();
    final showPhoto = photoUrlStr != null &&
        photoUrlStr.isNotEmpty &&
        (photoUrlStr.startsWith('http://') || photoUrlStr.startsWith('https://')) &&
        !_profileImageError;
    if (showPhoto) _resolveAvatarFlip(photoUrlStr);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular Avatar with edit prompt
          GestureDetector(
            onTap: _handleImageUpload,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: showPhoto
                      ? RotatedBox(
                          quarterTurns: _avatarNeedsFlip ? 2 : 0,
                          child: CachedNetworkImage(
                            imageUrl: photoUrlStr,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) {
                              return Center(
                                child: Text(
                                  initials.isEmpty ? 'U' : initials,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFEFAA1F),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : Center(
                          child: Text(
                            initials.isEmpty ? 'U' : initials,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEFAA1F),
                            ),
                          ),
                        ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFAA1F),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Name, Emp ID, Pill Tags
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Emp ID: $empId',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (designation.isNotEmpty && designation != 'N/A')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          designation,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF475569),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    if (department.isNotEmpty && department != 'N/A')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          department,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF475569),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 1. Personal Information Section
  Widget _buildWebPersonalSection() {
    final isEditing = _editingSections['personal'] ?? false;
    return _buildWebSectionCard(
      title: 'Personal Information',
      icon: Icons.person_outline_rounded,
      sectionKey: 'personal',
      isEditable: true,
      children: [
        _buildFieldRow(
          _buildWebField(label: 'Employee ID', fieldKey: 'employeeId', isReadOnly: true),
          _buildWebField(label: 'First Name', fieldKey: 'firstName', isEditing: isEditing),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Last Name', fieldKey: 'lastName', isEditing: isEditing),
          isEditing
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Date of Birth (DOB)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickDobDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                (_formData['dob']?.toString().trim().isNotEmpty == true)
                                    ? _formData['dob'].toString()
                                    : 'Select DOB',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: (_formData['dob']?.toString().trim().isNotEmpty == true)
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                              const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF64748B)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : _buildWebField(label: 'Date of Birth (DOB)', fieldKey: 'dob', isEditing: false),
        ),
        _buildFieldRow(
          _buildGenderDropdown(isEditing),
          _buildWebField(label: 'Blood Group', fieldKey: 'bloodGroup', isEditing: isEditing),
        ),
        _buildFieldRow(
          _buildWebField(label: "Father's Name", fieldKey: 'fatherName', isEditing: isEditing),
          _buildMaritalStatusDropdown(isEditing),
        ),
        if (_formData['maritalStatus'] == 'Married')
          _buildWebField(label: 'Spouse Name', fieldKey: 'spouseName', isEditing: isEditing),
      ],
    );
  }

  // 2. Contact Details Section
  Widget _buildWebContactSection() {
    final isEditing = _editingSections['contact'] ?? false;
    return _buildWebSectionCard(
      title: 'Contact Details',
      icon: Icons.shield_outlined,
      sectionKey: 'contact',
      isEditable: true,
      children: [
        _buildWebField(
          label: 'Email ID',
          fieldKey: 'contact',
          isEditing: isEditing,
          keyboardType: TextInputType.emailAddress,
        ),
        _buildFieldRow(
          _buildWebField(
            label: 'Phone Number',
            fieldKey: 'phone',
            isEditing: isEditing,
            keyboardType: TextInputType.phone,
          ),
          _buildWebField(
            label: 'Alternate Phone',
            fieldKey: 'altPhone',
            isEditing: isEditing,
            keyboardType: TextInputType.phone,
          ),
        ),
      ],
    );
  }

  // 3. Address Details Section
  Widget _buildWebAddressSection() {
    final isEditing = _editingSections['address'] ?? false;
    return _buildWebSectionCard(
      title: 'Address Details',
      icon: Icons.location_on_outlined,
      sectionKey: 'address',
      isEditable: true,
      children: [
        _buildWebField(label: 'Current Address', fieldKey: 'currentAddress', isEditing: isEditing),
        _buildFieldRow3(
          _buildWebField(label: 'Country', fieldKey: 'currentCountry', isEditing: isEditing),
          _buildWebField(label: 'State', fieldKey: 'currentState', isEditing: isEditing),
          _buildWebField(label: 'Pincode', fieldKey: 'currentPincode', isEditing: isEditing),
        ),
        const SizedBox(height: 6),
        _buildWebField(label: 'Permanent Address', fieldKey: 'permanentAddress', isEditing: isEditing),
        _buildFieldRow3(
          _buildWebField(label: 'Country', fieldKey: 'permanentCountry', isEditing: isEditing),
          _buildWebField(label: 'State', fieldKey: 'permanentState', isEditing: isEditing),
          _buildWebField(label: 'Pincode', fieldKey: 'permanentPincode', isEditing: isEditing),
        ),
      ],
    );
  }

  // 4. Disability Information Section
  Widget _buildWebDisabilitySection() {
    final isPhysicallyChallenged = _formData['isPhysicallyChallenged'] == 'Yes';
    return _buildWebSectionCard(
      title: 'Disability Information',
      icon: Icons.accessibility_new_rounded,
      sectionKey: 'disability',
      isEditable: false,
      children: [
        _buildWebField(label: 'Physically Challenged?', fieldKey: 'isPhysicallyChallenged', isEditing: false),
        if (isPhysicallyChallenged) ...[
          _buildFieldRow(
            _buildWebField(label: 'Disability Type', fieldKey: 'disabilityType', isEditing: false),
            _buildWebField(label: 'Disability Percentage', fieldKey: 'disabilityPercentage', isEditing: false),
          ),
          _buildWebField(label: 'Certificate Number', fieldKey: 'disabilityCertNo', isEditing: false),
        ],
      ],
    );
  }

  // 5. Role & Organization Setup Section
  Widget _buildWebRoleSection() {
    return _buildWebSectionCard(
      title: 'Role & Organization Setup',
      icon: Icons.business_outlined,
      sectionKey: 'role',
      isEditable: false,
      children: [
        _buildFieldRow(
          _buildWebField(label: 'Department', fieldKey: 'department', isEditing: false),
          _buildWebField(label: 'Employment Type', fieldKey: 'employmentType', isEditing: false),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Joining Date', fieldKey: 'joiningDate', isEditing: false),
          _buildWebField(label: 'Onboarding Date', fieldKey: 'onboardingDate', isEditing: false),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Designation', fieldKey: 'designation', isEditing: false),
          _buildWebField(label: 'Job Role', fieldKey: 'jobRole', isEditing: false),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Reporting Manager', fieldKey: 'reportingManager', isEditing: false),
          _buildWebField(label: 'Branch', fieldKey: 'branch', isEditing: false),
        ),
        _buildWebField(label: 'Work Mode', fieldKey: 'workMode', isEditing: false),
        _buildWebField(label: 'Work From Home Location', fieldKey: 'wfhLocation', isEditing: false),
        _buildFieldRow3(
          _buildWebField(label: 'Latitude', fieldKey: 'latitude', isEditing: false),
          _buildWebField(label: 'Longitude', fieldKey: 'longitude', isEditing: false),
          _buildWebField(label: 'Radius (Meters)', fieldKey: 'radius', isEditing: false),
        ),
      ],
    );
  }

  // 6. Bank & Statutory Details Section
  Widget _buildWebBankSection() {
    final isEditing = _editingSections['bank'] ?? false;
    return _buildWebSectionCard(
      title: 'Bank & Statutory Details',
      icon: Icons.credit_card_outlined,
      sectionKey: 'bank',
      isEditable: true,
      children: [
        _buildFieldRow(
          _buildWebField(label: 'PAN Number', fieldKey: 'pan', isEditing: isEditing),
          _buildWebField(label: 'Aadhaar Number', fieldKey: 'aadhaar', isEditing: isEditing),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Bank Name', fieldKey: 'bankName', isEditing: isEditing),
          _buildWebField(label: 'Account Holder Name', fieldKey: 'accountHolderName', isEditing: isEditing),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Account Number', fieldKey: 'accountNumber', isEditing: isEditing),
          _buildWebField(label: 'IFSC Code', fieldKey: 'ifscCode', isEditing: isEditing),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Branch Name', fieldKey: 'bankBranch', isEditing: isEditing),
          _buildWebField(label: 'UPI ID', fieldKey: 'upiId', isEditing: isEditing),
        ),
        _buildFieldRow(
          _buildWebField(label: 'UAN Number', fieldKey: 'uanNumber', isReadOnly: true),
          _buildWebField(label: 'PF Number', fieldKey: 'pfNumber', isReadOnly: true),
        ),
        _buildFieldRow(
          _buildWebField(label: 'PF Start Date', fieldKey: 'pfStartDate', isReadOnly: true),
          _buildWebField(label: 'ESI Number', fieldKey: 'esiNumber', isReadOnly: true),
        ),
        _buildWebField(label: 'ESI Start Date', fieldKey: 'esiStartDate', isReadOnly: true),
      ],
    );
  }

  // 7. Policy & Template Configurations Section
  Widget _buildWebPolicySection() {
    return _buildWebSectionCard(
      title: 'Policy & Template Configurations',
      icon: Icons.settings_outlined,
      sectionKey: 'policy',
      isEditable: false,
      children: [
        _buildFieldRow(
          _buildWebField(label: 'Salary Template', fieldKey: 'salaryTemplate', isEditing: false),
          _buildWebField(label: 'Shift Template', fieldKey: 'shiftTemplate', isEditing: false),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Leave Template', fieldKey: 'leaveTemplate', isEditing: false),
          _buildWebField(label: 'Holiday Template', fieldKey: 'holidayTemplate', isEditing: false),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Permission Template', fieldKey: 'permissionTemplate', isEditing: false),
          _buildWebField(label: 'Overtime Template', fieldKey: 'overtimeTemplate', isEditing: false),
        ),
        _buildFieldRow(
          _buildWebField(label: 'Break Template', fieldKey: 'breakTemplate', isEditing: false),
          _buildWebField(label: 'Attendance Template', fieldKey: 'attendanceTemplate', isEditing: false),
        ),
        _buildWebField(label: 'Weekly Off Template', fieldKey: 'weeklyOffTemplate', isEditing: false),
        _buildWebField(label: 'Geofence Template', fieldKey: 'geofenceTemplate', isEditing: false),
      ],
    );
  }

  // Custom Fields Section
  Widget _buildWebCustomFieldsSection() {
    return _buildWebSectionCard(
      title: 'Additional Information',
      icon: Icons.info_outline_rounded,
      sectionKey: 'custom',
      isEditable: false,
      children: [
        _buildCustomFieldColumnForCard(_activeStaffCustomFields),
      ],
    );
  }

  // Generic Card Container with Left Amber Indicator
  Widget _buildWebSectionCard({
    required String title,
    required IconData icon,
    required String sectionKey,
    bool isEditable = true,
    required List<Widget> children,
  }) {
    final isEditing = _editingSections[sectionKey] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Amber Accent Strip
            Container(
              width: 4,
              color: const Color(0xFFEFAA1F),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 18, color: const Color(0xFFEFAA1F)),
                            const SizedBox(width: 8),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        if (isEditable) ...[
                          if (isEditing)
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: _isSavingSection ? null : () => _handleCancelEdit(sectionKey),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF64748B)),
                                  label: const Text(
                                    'Cancel',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: _isSavingSection ? null : () => _handleSaveSection(sectionKey),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: const Color(0xFFEFAA1F),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: _isSavingSection
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                  label: Text(
                                    _isSavingSection ? 'Saving...' : 'Save',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ),
                              ],
                            )
                          else
                            InkWell(
                              onTap: () => setState(() => _editingSections[sectionKey] = true),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_outlined, size: 13, color: Color(0xFF475569)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Edit',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 14),
                    // Section Children
                    ...children,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Field box
  Widget _buildWebField({
    required String label,
    required String fieldKey,
    bool isEditing = false,
    TextInputType keyboardType = TextInputType.text,
    bool isReadOnly = false,
    Widget? customInput,
  }) {
    final rawVal = _formData[fieldKey];
    final displayVal = (rawVal == null || rawVal.toString().trim().isEmpty) ? 'N/A' : rawVal.toString().trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          if (isEditing && !isReadOnly)
            customInput ??
                TextFormField(
                  initialValue: rawVal?.toString() ?? '',
                  keyboardType: keyboardType,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
                    ),
                  ),
                  onChanged: (val) => _formData[fieldKey] = val,
                )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                displayVal,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: displayVal == 'N/A' || displayVal == 'None (Not Assigned)'
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF1E293B),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildFieldRow3(Widget left, Widget middle, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: middle),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildGenderDropdown(bool isEditing) {
    if (!isEditing) {
      return _buildWebField(label: 'Gender', fieldKey: 'gender', isEditing: false);
    }
    final current = ['Male', 'Female', 'Other'].contains(_formData['gender']) ? _formData['gender'] : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gender',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: current,
            hint: const Text('Select Gender', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
            items: const [
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
              ),
            ),
            onChanged: (val) {
              if (val != null) setState(() => _formData['gender'] = val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMaritalStatusDropdown(bool isEditing) {
    if (!isEditing) {
      return _buildWebField(label: 'Marital Status', fieldKey: 'maritalStatus', isEditing: false);
    }
    final current = ['Single', 'Married'].contains(_formData['maritalStatus']) ? _formData['maritalStatus'] : 'Single';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Marital Status',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: current,
            items: const [
              DropdownMenuItem(value: 'Single', child: Text('Single')),
              DropdownMenuItem(value: 'Married', child: Text('Married')),
            ],
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEFAA1F), width: 1.5),
              ),
            ),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _formData['maritalStatus'] = val;
                  if (val == 'Single') _formData['spouseName'] = '';
                });
              }
            },
          ),
        ],
      ),
    );
  }

  String _maskBankAccount(String? account) {
    if (account == null || account.trim().isEmpty) return 'N/A';
    final a = account.trim();
    if (a.length <= 4) return a;
    return '**** **** ${a.substring(a.length - 4)}';
  }

  String _maskAadhaar(String? a) {
    if (a == null || a.trim().isEmpty) return 'N/A';
    final s = a.replaceAll(' ', '');
    if (s.length <= 4) return a;
    return 'XXXX XXXX ${s.substring(s.length - 4)}';
  }

  /// Figma "Joined" / "Location" stat cards row beneath the header.
  Widget _buildStatCardsRow() {
    final joiningDate = _staffData?['joiningDate'];
    
    final resolvedBranchName =
        _userData?['branchName']?.toString() ??
        (_staffData?['branchId'] is Map
            ? (_staffData!['branchId'] as Map)['branchName']?.toString()
            : null);
    final branchName = (resolvedBranchName != null && resolvedBranchName.isNotEmpty)
        ? resolvedBranchName
        : 'Not assigned';
    final joined = joiningDate != null ? _formatDateShort(joiningDate) : '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildStatCard(
              Icons.calendar_today_outlined,
              'Joined',
              joined.isEmpty ? 'N/A' : joined,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatCard(
              Icons.location_on_outlined,
              'Location',
              branchName,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatDateShort(dynamic date) {
    try {
      final d = date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('dd MMM yyyy').format(d);
    } catch (_) { return ''; }
  }

  Widget _buildHeaderInfoRow(IconData icon, String text, TextStyle textStyle, {int maxLines = 1}) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: textStyle,
            maxLines: maxLines,
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBadge(String text, Color color, {double? fontSize, TextStyle? textStyle}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white30),
      ),
      child: Text(
        text,
        style: textStyle ?? TextStyle(
          color: Colors.white,
          fontSize: fontSize ?? 10,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  List<Map<String, dynamic>> _fieldsForCategory(String category) {
    return _activeStaffCustomFields
        .where((f) => (f['category']?.toString() ?? '') == category)
        .toList();
  }

  dynamic _rawCustomFieldValue(String name) {
    final staff = _staffData;
    if (staff == null) return null;
    final nested = staff['customFields'] ?? staff['custom_fields'];
    if (nested is Map && nested[name] != null) {
      return nested[name];
    }
    return staff[name];
  }

  String _displayCustomFieldValue(Map<String, dynamic> field) {
    final name = field['name']?.toString() ?? '';
    final type = field['type']?.toString() ?? 'text';
    final raw = _rawCustomFieldValue(name);
    if (raw == null) return 'N/A';
    switch (type) {
      case 'boolean':
        if (raw == true ||
            raw == 'true' ||
            raw == 1 ||
            raw == '1' ||
            raw == 'yes' ||
            raw == 'Yes') {
          return 'Yes';
        }
        if (raw == false ||
            raw == 'false' ||
            raw == 0 ||
            raw == '0' ||
            raw == 'no' ||
            raw == 'No') {
          return 'No';
        }
        return raw.toString();
      case 'date':
        return _formatDate(raw);
      case 'number':
        return raw.toString();
      default:
        final s = raw.toString().trim();
        return s.isEmpty ? 'N/A' : s;
    }
  }

  Widget _buildCustomFieldColumnForCard(List<Map<String, dynamic>> fields) {
    if (fields.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final left = fields[i];
      final right = i + 1 < fields.length ? fields[i + 1] : null;
      rows.add(
        _buildInfoGrid([
          _buildInfoItem(
            left['label']?.toString() ?? left['name']?.toString() ?? '',
            _displayCustomFieldValue(left),
          ),
          if (right != null)
            _buildInfoItem(
              right['label']?.toString() ?? right['name']?.toString() ?? '',
              _displayCustomFieldValue(right),
            )
          else
            // _buildInfoGrid already wraps each child in an Expanded — pass a
            // bare SizedBox, not an Expanded, or two Expandeds compete for the
            // same RenderObject's parent data.
            const SizedBox(),
        ]),
      );
      if (i + 2 < fields.length) {
        rows.add(const SizedBox(height: 20));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  /// Converts a 24-hour "HH:mm" time to a 12-hour label, e.g. "18:00" → "6:00 PM".
  /// Returns the input unchanged if it isn't "HH:mm".
  String _formatTime12(String time24) {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return time24;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = m.toString().padLeft(2, '0');
    return '$h12:$mm $period';
  }

  /// Resolves the staff's assigned shift template into a label/value pair for the
  /// General Information card. Standard shifts show their timing window
  /// (e.g. "10:00 AM to 6:00 PM"); rotational shifts—whose window varies by day—
  /// show "Rotational Shift" instead, matching the requirement.
  ({String label, String value}) _shiftTimingInfo() {
    final company = _staffData?['businessId'];
    final companyDoc =
        company is Map ? Map<String, dynamic>.from(company) : null;
    final shifts = shiftsListFromCompany(companyDoc);
    if (companyDoc == null || shifts == null || shifts.isEmpty) {
      return (label: 'Shift Timing', value: 'Not Assigned');
    }

    final key = staffShiftKeyFromProfileMap(_staffData ?? {}) ?? '';
    final raw = key.trim().isEmpty
        ? (shifts.first is Map ? shifts.first as Map : null)
        : findShiftByStaffKey(shifts, key);
    final wrapper = raw is Map ? Map<String, dynamic>.from(raw) : null;
    if (wrapper == null) {
      return (label: 'Shift Timing', value: 'Not Assigned');
    }

    // Rotational templates have no single fixed window — surface the template.
    if (isRotationalShiftWrapper(wrapper)) {
      return (label: 'Shift Template', value: 'Rotational Shift');
    }

    // Standard shift → format the configured start/end window.
    final win = resolveStandardShiftWindowFromCompany(companyDoc, wrapper);
    if (win.start != null && win.end != null) {
      return (
        label: 'Shift Timing',
        value: '${_formatTime12(win.start!)} to ${_formatTime12(win.end!)}',
      );
    }

    // Open shift (required hours, no fixed window) or unconfigured timing.
    final st = (wrapper['shiftType'] ?? '').toString().toLowerCase().trim();
    if (st == 'open' || st == 'open shift') {
      final hours = _openShiftHoursLabel(wrapper['workHours']);
      return (
        label: 'Shift Timing',
        value: hours != null ? 'Open Shift · $hours' : 'Open Shift',
      );
    }
    return (label: 'Shift Timing', value: 'N/A');
  }

  /// Required-hours label for an open shift, e.g. 9 → "9h/day", 8.5 → "8.5h/day".
  /// Null when no positive [workHours] is configured.
  String? _openShiftHoursLabel(dynamic workHours) {
    final h = workHours is num
        ? workHours.toDouble()
        : double.tryParse(workHours?.toString().trim() ?? '');
    if (h == null || h <= 0) return null;
    final hStr = h == h.roundToDouble() ? h.toInt().toString() : h.toString();
    return '${hStr}h/day';
  }

  /// General Information card — shows the employee's Shift Timing (from the
  /// assigned shift template) plus any admin-defined "General Information"
  /// custom fields.
  Widget _buildGeneralInfoSection() {
    final shift = _shiftTimingInfo();
    final customFields = _fieldsForCategory('General Information');

    return _buildCardSection(
      icon: Icons.info_outline,
      title: 'General Information',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoGrid([
            _buildInfoItem(shift.label, shift.value),
            const SizedBox(),
          ]),
          if (customFields.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildCustomFieldColumnForCard(customFields),
          ],
        ],
      ),
    );
  }

  Widget _buildPersonalSection() {
    final name = _profile?['name']?.toString() ?? 'N/A';
    final empId = _staffData?['employeeId']?.toString() ?? 'N/A';
    final email = _profile?['email']?.toString() ?? 'N/A';
    final phone = _profile?['phone']?.toString() ?? _staffData?['phone']?.toString() ?? 'N/A';

    return _buildCardSection(
      icon: Icons.person_outline,
      title: 'Personal Information',
      content: Column(
        children: [
          _buildInfoGrid([
            _buildInfoItem('Full Name', name),
            _buildInfoItem('Employee ID', empId),
          ]),
          const SizedBox(height: 20),
          _buildInfoGrid([
            _buildInfoItem('Email', email),
            _buildInfoItem('Phone', phone),
          ]),
          const SizedBox(height: 20),
          _buildInfoGrid([
            _buildInfoItem('Gender', _staffData?['gender'] ?? 'N/A'),
            _buildInfoItem('Date of Birth', _formatDate(_staffData?['dob'])),
          ]),
          const SizedBox(height: 20),
          _buildInfoGrid([
            _buildInfoItem(
              'Marital Status',
              _staffData?['maritalStatus'] ?? 'N/A',
            ),
            _buildInfoItem('Blood Group', _staffData?['bloodGroup'] ?? 'N/A'),
          ]),
          if (_fieldsForCategory('Personal Information').isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildCustomFieldColumnForCard(
              _fieldsForCategory('Personal Information'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmploymentInfoSection() {
    final designation = _staffData?['designation']?.toString() ?? '';
    final department = _staffData?['department']?.toString() ?? '';
    final staffType = _staffData?['staffType']?.toString() ?? '';

    return _buildCardSection(
      icon: Icons.work_outline,
      title: 'Employment Information',
      content: Column(
        children: [
          _buildInfoGrid([
            _buildInfoItem('Designation', designation.isEmpty ? 'N/A' : designation),
            _buildInfoItem('Department', department.isEmpty ? 'N/A' : department),
          ]),
          const SizedBox(height: 20),
          _buildInfoGrid([
            _buildInfoItem('Employee Type', staffType.isEmpty ? 'N/A' : staffType),
          ]),
        ],
      ),
    );
  }

  Widget _buildIdentityAndBankSection() {
    final empIds = _staffData?['employmentIds'] ?? {};
    final employmentCustom = _fieldsForCategory('Employment Information');
    final bankCustom = _fieldsForCategory('Bank Details');
    final customCategory = _fieldsForCategory('Custom');

    return Column(
      children: [
        _buildCardSection(
          icon: Icons.badge_outlined,
          title: 'Employment IDs',
          content: Column(
            children: [
              _buildInfoGrid([
                _buildInfoItem('UAN Number', empIds['uan']),
                _buildInfoItem('PF Number', empIds['pfNumber']),
              ]),
             // const SizedBox(height: 20),
             // _buildInfoGrid([
               // _buildInfoItem('Aadhaar Number', empIds['aadhaar']),
//_buildInfoItem('PF Number', empIds['pfNumber']),
//]),
              const SizedBox(height: 20),
              _buildInfoGrid([
                _buildInfoItem('ESI Number', empIds['esiNumber']),
                // _buildInfoGrid wraps each child in an Expanded; pass a bare
                // SizedBox so we don't end up with two competing Expandeds.
                const SizedBox(),
              ]),
              if (employmentCustom.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildCustomFieldColumnForCard(employmentCustom),
              ],
            ],
          ),
        ),
        if (bankCustom.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildCardSection(
            icon: Icons.account_balance_outlined,
            title: 'Bank Details',
            content: _buildCustomFieldColumnForCard(bankCustom),
          ),
        ],
        if (customCategory.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildCardSection(
            icon: Icons.tune_outlined,
            title: 'Custom',
            content: _buildCustomFieldColumnForCard(customCategory),
          ),
        ],
      ],
    );
  }

  Widget _buildContactCard() {
    final email = _profile?['email']?.toString() ?? '';
    final phone = _profile?['phone']?.toString() ?? '';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(Icons.contact_phone_outlined, color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                Text(
                  'Contact Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey.shade100, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                _buildContactRow(Icons.email_outlined, 'EMAIL ADDRESS', email),
                const SizedBox(height: 18),
                _buildContactRow(Icons.phone_outlined, 'PHONE NUMBER', phone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    final addr = _staffData?['address'];
    String line1 = '', city = '', state = '', postalCode = '', country = '';
    if (addr is Map) {
      line1 = addr['line1']?.toString().trim() ?? '';
      city = addr['city']?.toString().trim() ?? '';
      state = addr['state']?.toString().trim() ?? '';
      postalCode = addr['postalCode']?.toString().trim() ?? '';
      country = addr['country']?.toString().trim() ?? '';
    }

    return _buildCardSection(
      icon: Icons.location_on_outlined,
      title: 'Address',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (line1.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoItem('Address Line 1', line1),
                const SizedBox(height: 20),
              ],
            ),
          _buildInfoGrid([
            _buildInfoItem('City', city.isEmpty ? 'N/A' : city),
            _buildInfoItem('State', state.isEmpty ? 'N/A' : state),
          ]),
          const SizedBox(height: 20),
          _buildInfoGrid([
            _buildInfoItem('Postal Code', postalCode.isEmpty ? 'N/A' : postalCode),
            _buildInfoItem('Country', country.isEmpty ? 'N/A' : country),
          ]),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value.trim().isEmpty ? 'N/A' : value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Figma PAN / Aadhaar highlighted mini-cards row.
  Widget _buildIdQuickCards() {
    final empIds = _staffData?['employmentIds'];
    final pan =
        (empIds is Map ? empIds['pan']?.toString() : null)?.trim() ?? '';
    final aadhaar =
        (empIds is Map ? empIds['aadhaar']?.toString() : null)?.trim() ?? '';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildIdMiniCard(
              Icons.badge_outlined,
              'PAN CARD',
              pan.isEmpty ? 'N/A' : pan,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildIdMiniCard(
              Icons.fingerprint,
              'AADHAR NO.',
              _maskAadhaar(aadhaar),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdMiniCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildExpAndEduTab() {
    final education = _candidateData?['education'] as List? ?? [];
    final experience = _candidateData?['experience'] as List? ?? [];

    return RefreshIndicator(
      onRefresh: _refreshProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildCardSection(
              icon: Icons.school_outlined,
              title: 'Education',
              trailing: null,
              content: education.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Text(
                          'No education details found.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : Column(
                      children: education
                          .map(
                            (edu) => _buildEduItem(edu as Map<String, dynamic>),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 24),
            _buildCardSection(
              icon: Icons.business_center_outlined,
              title: 'Experience',
              trailing: null,
              content: experience.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Text(
                          'No experience details found.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : Column(
                      children: experience
                          .map(
                            (exp) => _buildExpItem(exp as Map<String, dynamic>),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEduItem(Map<String, dynamic> edu) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  edu['qualification'] ?? 'N/A',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (edu['yearOfPassing'] != null)
                Text(
                  edu['yearOfPassing'].toString(),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoItem('Course', edu['courseName'] ?? edu['course']),
          const SizedBox(height: 12),
          _buildInfoItem('Institution', edu['institution']),
          const SizedBox(height: 12),
          _buildInfoGrid([
            _buildInfoItem('University', edu['university']),
            _buildInfoItem(
              'Score',
              edu['percentage'] ?? edu['cgpa'] ?? edu['score'],
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildExpItem(Map<String, dynamic> exp) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.work, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exp['designation'] ?? exp['role'] ?? 'N/A',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoItem('Company', exp['company']),
          const SizedBox(height: 12),
          _buildInfoGrid([
            _buildInfoItem('From', _formatDate(exp['durationFrom'])),
            _buildInfoItem('To', _formatDate(exp['durationTo'])),
          ]),
          if (exp['keyResponsibilities'] != null &&
              exp['keyResponsibilities'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildInfoItem('Responsibilities', exp['keyResponsibilities']),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentsTab() {
    // Show loading while documents are being fetched
    if (_isLoadingDocs) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: AppTabLoader(),
        ),
      );
    }

    // Use documents from onboarding service
    final docs = _documents;

    // Calculate progress
    int completedCount = 0;
    int totalRequired = 0;
    String overallStatus = 'NOT STARTED';

    for (var doc in docs) {
      final docMap = doc as Map<String, dynamic>;
      if (docMap['required'] == true) {
        totalRequired++;
        if (docMap['status'] == 'COMPLETED') {
          completedCount++;
        }
      }
    }

    final progress = totalRequired > 0
        ? (completedCount / totalRequired * 100).round()
        : 0;

    // Determine overall status
    if (docs.isEmpty) {
      overallStatus = 'NOT STARTED';
    } else {
      final hasPending = docs.any((doc) => (doc as Map)['status'] == 'PENDING');
      final hasCompleted = docs.any(
        (doc) => (doc as Map)['status'] == 'COMPLETED',
      );

      if (hasPending) {
        overallStatus = 'IN PROGRESS';
      } else if (hasCompleted && progress == 100) {
        overallStatus = 'COMPLETED';
      } else if (hasCompleted) {
        overallStatus = 'IN PROGRESS';
      } else {
        overallStatus = 'NOT STARTED';
      }
    }

    return RefreshIndicator(
      onRefresh: _refreshProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with progress
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Documents',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Put progress text on its own line to avoid overflow
                  Text(
                    'Progress: $progress% • Status: $overallStatus',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Overall Progress',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            '$progress%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress == 100 ? Colors.green : AppColors.primary,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Documents list
            docs.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 40,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No documents found.',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Documents will appear here for viewing once they are available.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Once HR/Admin verifies them, they will show as Verified.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: docs
                        .map(
                          (doc) => _buildDocTile(doc as Map<String, dynamic>),
                        )
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocTile(Map<String, dynamic> doc) {
    final status = doc['status'] ?? 'NOT_STARTED';
    final docName = doc['name'] ?? doc['type'] ?? 'Document';
    final docType = doc['type'] ?? 'document';
    final isRequired = doc['required'] == true;
    final hasUrl = doc['url'] != null && doc['url'].toString().isNotEmpty;
    final isPending = status == 'PENDING';
    final isCompleted = status == 'COMPLETED';
    final isRejected = status == 'REJECTED';
    final uploadedAt = doc['uploadedAt'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  docType == 'form'
                      ? Icons.description_outlined
                      : Icons.file_present_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      docName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (isRequired)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Required',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        _buildStatusBadge(status),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Type: ${docType == 'form' ? 'form' : 'document'}',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (uploadedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Uploaded: ${_formatDate(uploadedAt)}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action buttons - view only (no upload/replace)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            children: [
              if (hasUrl && (isPending || isCompleted || isRejected)) ...[
                // View, Download buttons (always shown)
                TextButton.icon(
                  onPressed: () => _viewDocument(doc['url']),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _downloadDocument(doc['url']),
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Download', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    String displayText;
    Color badgeColor;
    IconData? icon;

    switch (status) {
      case 'PENDING':
        displayText = 'Under Review';
        badgeColor = Colors.orange;
        icon = Icons.access_time;
        break;
      case 'COMPLETED':
        displayText = 'Verified';
        badgeColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'REJECTED':
        displayText = 'Rejected';
        badgeColor = Colors.red;
        icon = Icons.cancel;
        break;
      default:
        displayText = 'Not Started';
        badgeColor = Colors.grey;
        icon = Icons.radio_button_unchecked;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...[
            Icon(icon, size: 10, color: badgeColor),
            const SizedBox(width: 3),
          ],
          Text(
            displayText,
            style: TextStyle(
              color: badgeColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSection({
    required IconData icon,
    required String title,
    required Widget content,
    bool showProgress = false,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade100, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: _profileHeadingSize,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (trailing != null) trailing,
                if (showProgress)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'COMPLETED 100%',
                      style: TextStyle(
                        fontSize: _profileValueSize,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(20), child: content),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(List<Widget> children) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.map((c) => Expanded(child: c)).toList(),
    );
  }

  Widget _buildInfoItem(String label, dynamic value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: _profileHeadingSize,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value?.toString() ?? 'N/A',
          style: TextStyle(
            fontSize: _profileValueSize,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildMultilineInfoItem(String label, String value) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: _profileHeadingSize,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: double.infinity,
            child: Text(
              value,
              style: TextStyle(
                fontSize: _profileValueSize,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.left,
              softWrap: true,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      if (date is String) {
        return DateFormat('dd-MM-yyyy').format(DateTime.parse(date));
      }
      if (date is DateTime) return DateFormat('dd-MM-yyyy').format(date);
      return date.toString();
    } catch (e) {
      return date.toString();
    }
  }

  void _showPhotoFullScreen(String photoUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: RotatedBox(
              quarterTurns: _avatarNeedsFlip ? 2 : 0,
              child: Image.network(
              photoUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 64,
                  color: Colors.white70,
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditEducationSheet() {
    final education = _candidateData?['education'] as List? ?? [];
    final list = education
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditEducationSheet(
        initialEducation: list,
        onSave: (updated) async {
          final result = await _authService.updateEducation(updated);
          if (!mounted) return;
          Navigator.of(context).pop();
          if (result['success']) {
            SnackBarUtils.showSnackBar(
              context,
              'Education updated successfully',
              backgroundColor: AppColors.primary,
            );
            _loadProfile();
          } else {
            SnackBarUtils.showSnackBar(
              context,
              ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'Failed to update education'),
              isError: true,
            );
          }
        },
      ),
    );
  }

  void _showEditExperienceSheet() {
    final experience = _candidateData?['experience'] as List? ?? [];
    final list = experience
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditExperienceSheet(
        initialExperience: list,
        onSave: (updated) async {
          final result = await _authService.updateExperience(updated);
          if (!mounted) return;
          Navigator.of(context).pop();
          if (result['success']) {
            SnackBarUtils.showSnackBar(
              context,
              'Experience updated successfully',
              backgroundColor: AppColors.primary,
            );
            _loadProfile();
          } else {
            SnackBarUtils.showSnackBar(
              context,
              ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'Failed to update experience'),
              isError: true,
            );
          }
        },
      ),
    );
  }
}

class _EditEducationSheet extends StatefulWidget {
  final List<Map<String, dynamic>> initialEducation;
  final Function(List<Map<String, dynamic>>) onSave;

  const _EditEducationSheet({
    required this.initialEducation,
    required this.onSave,
  });

  @override
  State<_EditEducationSheet> createState() => _EditEducationSheetState();
}

class _EditEducationSheetState extends State<_EditEducationSheet> {
  late List<Map<String, dynamic>> _education;

  @override
  void initState() {
    super.initState();
    _education = widget.initialEducation.isEmpty
        ? [_emptyEduEntry()]
        : widget.initialEducation
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
  }

  void _onEducationChanged(int index, Map<String, dynamic> updated) {
    setState(() {
      _education[index] = updated;
    });
  }

  Map<String, dynamic> _emptyEduEntry() {
    return {
      'qualification': '',
      'courseName': '',
      'institution': '',
      'university': '',
      'yearOfPassing': '',
      'percentage': '',
      'cgpa': '',
    };
  }

  void _addEntry() {
    // Check if previous entry has all required fields filled
    if (_education.isNotEmpty) {
      final lastEntry = _education.last;
      final qualification = (lastEntry['qualification'] ?? '')
          .toString()
          .trim();
      final courseName = (lastEntry['courseName'] ?? lastEntry['course'] ?? '')
          .toString()
          .trim();
      final institution = (lastEntry['institution'] ?? '').toString().trim();
      final university = (lastEntry['university'] ?? '').toString().trim();
      final yearOfPassing = (lastEntry['yearOfPassing'] ?? '')
          .toString()
          .trim();
      final percentage = (lastEntry['percentage'] ?? '').toString().trim();
      final cgpa = (lastEntry['cgpa'] ?? '').toString().trim();

      // Qualification is required, check if it's empty
      if (qualification.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Please fill all fields in Education ${_education.length} before adding a new entry',
          isError: true,
        );
        return;
      }

      // Check if any other field is empty
      if (courseName.isEmpty ||
          institution.isEmpty ||
          university.isEmpty ||
          yearOfPassing.isEmpty ||
          (percentage.isEmpty && cgpa.isEmpty)) {
        SnackBarUtils.showSnackBar(
          context,
          'Please fill all fields in Education ${_education.length} before adding a new entry',
          isError: true,
        );
        return;
      }
    }
    setState(() => _education.add(_emptyEduEntry()));
  }

  void _removeAt(int index) {
    setState(() {
      _education.removeAt(index);
      if (_education.isEmpty) _education.add(_emptyEduEntry());
    });
  }

  bool _validateEducation() {
    for (var i = 0; i < _education.length; i++) {
      final e = _education[i];
      final qualification = (e['qualification'] ?? '').toString().trim();
      final courseName = (e['courseName'] ?? e['course'] ?? '')
          .toString()
          .trim();
      final institution = (e['institution'] ?? '').toString().trim();
      final university = (e['university'] ?? '').toString().trim();
      final yearOfPassing = (e['yearOfPassing'] ?? '').toString().trim();
      final percentage = (e['percentage'] ?? '').toString().trim();
      final cgpa = (e['cgpa'] ?? '').toString().trim();

      // Qualification is required
      if (qualification.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Qualification is required for Education ${i + 1}',
          isError: true,
        );
        return false;
      }

      // All other fields must be filled
      if (courseName.isEmpty ||
          institution.isEmpty ||
          university.isEmpty ||
          yearOfPassing.isEmpty ||
          (percentage.isEmpty && cgpa.isEmpty)) {
        SnackBarUtils.showSnackBar(
          context,
          'Please fill all fields for Education ${i + 1}',
          isError: true,
        );
        return false;
      }
    }
    return true;
  }

  List<Map<String, dynamic>> _collectEducation() {
    return _education
        .map(
          (e) => {
            'qualification': (e['qualification'] ?? '').toString().trim(),
            'courseName': (e['courseName'] ?? e['course'] ?? '')
                .toString()
                .trim(),
            'institution': (e['institution'] ?? '').toString().trim(),
            'university': (e['university'] ?? '').toString().trim(),
            'yearOfPassing': (e['yearOfPassing'] ?? '').toString().trim(),
            'percentage': (e['percentage'] ?? '').toString().trim(),
            'cgpa': (e['cgpa'] ?? '').toString().trim(),
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    // Keep a stable, tall sheet so it doesn't visually
    // shrink when the keyboard opens; instead we let the
    // content scroll and add bottom padding for the keyboard.
    final formHeight = screenHeight * 0.95;

    return Container(
      height: formHeight,
      padding: EdgeInsets.only(
        bottom: keyboardHeight + 16,
        left: 24,
        right: 24,
        top: 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Edit Education',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add', style: TextStyle(fontSize: 14)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 24),
                  ),
                ],
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(_education.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _EditEducationTile(
                        index: index + 1,
                        entry: _education[index],
                        onChanged: (updated) =>
                            _onEducationChanged(index, updated),
                        onRemove: _education.length > 1
                            ? () => _removeAt(index)
                            : null,
                      ),
                    );
                  }),
                  const SizedBox(
                    height: 20,
                  ), // Extra bottom spacing for scrolling
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: keyboardHeight > 0 ? 8 : 0,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  if (_validateEducation()) {
                    widget.onSave(_collectEducation());
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Education',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditEducationTile extends StatefulWidget {
  final int index;
  final Map<String, dynamic> entry;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback? onRemove;

  const _EditEducationTile({
    required this.index,
    required this.entry,
    required this.onChanged,
    this.onRemove,
  });

  @override
  State<_EditEducationTile> createState() => _EditEducationTileState();
}

class _EditEducationTileState extends State<_EditEducationTile> {
  late TextEditingController _qualificationController;
  late TextEditingController _courseController;
  late TextEditingController _institutionController;
  late TextEditingController _universityController;
  late TextEditingController _yearController;
  late TextEditingController _percentageController;
  late TextEditingController _cgpaController;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _qualificationController = TextEditingController(
      text: (e['qualification'] ?? '').toString(),
    );
    _courseController = TextEditingController(
      text: (e['courseName'] ?? e['course'] ?? '').toString(),
    );
    _institutionController = TextEditingController(
      text: (e['institution'] ?? '').toString(),
    );
    _universityController = TextEditingController(
      text: (e['university'] ?? '').toString(),
    );
    _yearController = TextEditingController(
      text: (e['yearOfPassing'] ?? '').toString(),
    );
    _percentageController = TextEditingController(
      text: (e['percentage'] ?? '').toString(),
    );
    _cgpaController = TextEditingController(text: (e['cgpa'] ?? '').toString());
  }

  @override
  void dispose() {
    _qualificationController.dispose();
    _courseController.dispose();
    _institutionController.dispose();
    _universityController.dispose();
    _yearController.dispose();
    _percentageController.dispose();
    _cgpaController.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      'qualification': _qualificationController.text,
      'courseName': _courseController.text,
      'institution': _institutionController.text,
      'university': _universityController.text,
      'yearOfPassing': _yearController.text,
      'percentage': _percentageController.text,
      'cgpa': _cgpaController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Education ${widget.index}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 22,
                    ),
                    onPressed: widget.onRemove,
                    tooltip: 'Remove',
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _qualificationController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Qualification *',
                prefixIcon: Icon(
                  Icons.school,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _courseController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Course',
                prefixIcon: Icon(
                  Icons.book,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _institutionController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Institution',
                prefixIcon: Icon(
                  Icons.business,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _universityController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'University',
                prefixIcon: Icon(
                  Icons.account_balance,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            // Year field - full width for better visibility
            TextField(
              controller: _yearController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Year of Passing',
                prefixIcon: Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            // Percentage and CGPA in a row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _percentageController,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Percentage',
                      prefixIcon: Icon(
                        Icons.percent,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      labelStyle: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _cgpaController,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'CGPA',
                      prefixIcon: Icon(
                        Icons.grade,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      labelStyle: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditExperienceSheet extends StatefulWidget {
  final List<Map<String, dynamic>> initialExperience;
  final Function(List<Map<String, dynamic>>) onSave;

  const _EditExperienceSheet({
    required this.initialExperience,
    required this.onSave,
  });

  @override
  State<_EditExperienceSheet> createState() => _EditExperienceSheetState();
}

class _EditExperienceSheetState extends State<_EditExperienceSheet> {
  late List<Map<String, dynamic>> _experience;

  @override
  void initState() {
    super.initState();
    _experience = widget.initialExperience.isEmpty
        ? [_emptyExpEntry()]
        : widget.initialExperience
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
  }

  void _onExperienceChanged(int index, Map<String, dynamic> updated) {
    setState(() {
      _experience[index] = updated;
    });
  }

  Map<String, dynamic> _emptyExpEntry() {
    return {
      'company': '',
      'role': '',
      'designation': '',
      'durationFrom': '',
      'durationTo': '',
      'keyResponsibilities': '',
      'reasonForLeaving': '',
    };
  }

  void _addEntry() {
    // Check if previous entry has all required fields filled
    if (_experience.isNotEmpty) {
      final lastEntry = _experience.last;
      final company = (lastEntry['company'] ?? '').toString().trim();
      final role = (lastEntry['role'] ?? '').toString().trim();
      final designation = (lastEntry['designation'] ?? '').toString().trim();
      final durationFrom = (lastEntry['durationFrom'] ?? '').toString().trim();
      final durationTo = (lastEntry['durationTo'] ?? '').toString().trim();

      // Company and role are required
      if (company.isEmpty || role.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Please fill Company and Role in Experience ${_experience.length} before adding a new entry',
          isError: true,
        );
        return;
      }

      // Check if other required fields are empty
      if (designation.isEmpty || durationFrom.isEmpty || durationTo.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Please fill all fields in Experience ${_experience.length} before adding a new entry',
          isError: true,
        );
        return;
      }
    }
    setState(() => _experience.add(_emptyExpEntry()));
  }

  void _removeAt(int index) {
    setState(() {
      _experience.removeAt(index);
      if (_experience.isEmpty) _experience.add(_emptyExpEntry());
    });
  }

  bool _validateExperience() {
    for (var i = 0; i < _experience.length; i++) {
      final e = _experience[i];
      final company = (e['company'] ?? '').toString().trim();
      final role = (e['role'] ?? '').toString().trim();
      final designation = (e['designation'] ?? '').toString().trim();
      final durationFrom = (e['durationFrom'] ?? '').toString().trim();
      final durationTo = (e['durationTo'] ?? '').toString().trim();

      // Company and role are required
      if (company.isEmpty || role.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Company and Role are required for Experience ${i + 1}',
          isError: true,
        );
        return false;
      }

      // Date fields must be filled
      if (designation.isEmpty || durationFrom.isEmpty || durationTo.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Please fill all fields for Experience ${i + 1}',
          isError: true,
        );
        return false;
      }

      // Validate date formats (accept YYYY-MM-DD, DD-MM-YYYY, or ISO; normalize to YYYY-MM-DD)
      final fromNormalized = _normalizeExperienceDate(durationFrom);
      final toNormalized = _normalizeExperienceDate(durationTo);
      if (fromNormalized.isEmpty || toNormalized.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Invalid date format for dates in Experience ${i + 1}. Use DD-MM-YYYY or YYYY-MM-DD',
          isError: true,
        );
        return false;
      }
      try {
        DateFormat('yyyy-MM-dd').parseStrict(fromNormalized);
        DateFormat('yyyy-MM-dd').parseStrict(toNormalized);
      } catch (e) {
        SnackBarUtils.showSnackBar(
          context,
          'Invalid date format for dates in Experience ${i + 1}. Use DD-MM-YYYY or YYYY-MM-DD',
          isError: true,
        );
        return false;
      }
    }
    return true;
  }

  /// Normalize experience date string to YYYY-MM-DD for API (accepts ISO, YYYY-MM-DD, DD-MM-YYYY).
  String _normalizeExperienceDate(String value) {
    final s = value.trim();
    if (s.isEmpty || s == 'Present') return s;
    try {
      return DateFormat('yyyy-MM-dd').format(DateTime.parse(s));
    } catch (_) {}
    try {
      final dt = DateFormat('yyyy-MM-dd').parseStrict(s);
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {}
    try {
      final dt = DateFormat('dd-MM-yyyy').parseStrict(s);
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {}
    return '';
  }

  List<Map<String, dynamic>> _collectExperience() {
    return _experience
        .map(
          (e) => {
            'company': (e['company'] ?? '').toString().trim(),
            'role': (e['role'] ?? '').toString().trim(),
            'designation': (e['designation'] ?? '').toString().trim(),
            'durationFrom': _normalizeExperienceDate(
              (e['durationFrom'] ?? '').toString().trim(),
            ),
            'durationTo': _normalizeExperienceDate(
              (e['durationTo'] ?? '').toString().trim(),
            ),
            'keyResponsibilities': (e['keyResponsibilities'] ?? '')
                .toString()
                .trim(),
            'reasonForLeaving': (e['reasonForLeaving'] ?? '').toString().trim(),
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    // Keep a stable, tall sheet so it doesn't visually
    // shrink when the keyboard opens; instead we let the
    // content scroll and add bottom padding for the keyboard.
    final formHeight = screenHeight * 0.95;

    return Container(
      height: formHeight,
      padding: EdgeInsets.only(
        bottom: keyboardHeight + 16,
        left: 24,
        right: 24,
        top: 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Edit Experience',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add', style: TextStyle(fontSize: 14)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 24),
                  ),
                ],
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(_experience.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _EditExperienceTile(
                        index: index + 1,
                        entry: _experience[index],
                        onChanged: (updated) =>
                            _onExperienceChanged(index, updated),
                        onRemove: _experience.length > 1
                            ? () => _removeAt(index)
                            : null,
                      ),
                    );
                  }),
                  const SizedBox(
                    height: 20,
                  ), // Extra bottom spacing for scrolling
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: keyboardHeight > 0 ? 8 : 0,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  if (_validateExperience()) {
                    widget.onSave(_collectExperience());
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Experience',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditExperienceTile extends StatefulWidget {
  final int index;
  final Map<String, dynamic> entry;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback? onRemove;

  const _EditExperienceTile({
    required this.index,
    required this.entry,
    required this.onChanged,
    this.onRemove,
  });

  @override
  State<_EditExperienceTile> createState() => _EditExperienceTileState();
}

class _EditExperienceTileState extends State<_EditExperienceTile> {
  late TextEditingController _companyController;
  late TextEditingController _roleController;
  late TextEditingController _designationController;
  late TextEditingController _fromController;
  late TextEditingController _toController;
  late TextEditingController _responsibilitiesController;
  late TextEditingController _reasonController;

  DateTime? _selectedFromDate;
  DateTime? _selectedToDate;

  /// Normalize any date string (ISO, YYYY-MM-DD, or DD-MM-YYYY) to YYYY-MM-DD for storage and API.
  static String _normalizeDateToApiFormat(dynamic date) {
    if (date == null) return '';
    if (date is DateTime) {
      return DateFormat('yyyy-MM-dd').format(date);
    }
    final s = date.toString().trim();
    if (s.isEmpty || s == 'Present') return s;
    try {
      final dt = DateTime.parse(s);
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {}
    try {
      final dt = DateFormat('yyyy-MM-dd').parseStrict(s);
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {}
    try {
      final dt = DateFormat('dd-MM-yyyy').parseStrict(s);
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {}
    return s;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.entry;

    _companyController = TextEditingController(
      text: (e['company'] ?? '').toString(),
    );
    _roleController = TextEditingController(text: (e['role'] ?? '').toString());
    _designationController = TextEditingController(
      text: (e['designation'] ?? '').toString(),
    );

    // Parse dates: normalize to YYYY-MM-DD so controller always has API format (avoids "Invalid date format" on save)
    final fromDateStr = _normalizeDateToApiFormat(e['durationFrom']);
    final toDateStr = _normalizeDateToApiFormat(e['durationTo']);

    _fromController = TextEditingController(text: fromDateStr);
    _toController = TextEditingController(text: toDateStr);

    if (fromDateStr.isNotEmpty && fromDateStr != 'Present') {
      try {
        _selectedFromDate = DateFormat('yyyy-MM-dd').parse(fromDateStr);
      } catch (_) {}
    }
    if (toDateStr.isNotEmpty && toDateStr != 'Present') {
      try {
        _selectedToDate = DateFormat('yyyy-MM-dd').parse(toDateStr);
      } catch (_) {}
    }

    _responsibilitiesController = TextEditingController(
      text: (e['keyResponsibilities'] ?? '').toString(),
    );
    _reasonController = TextEditingController(
      text: (e['reasonForLeaving'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _companyController.dispose();
    _roleController.dispose();
    _designationController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _responsibilitiesController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      'company': _companyController.text,
      'role': _roleController.text,
      'designation': _designationController.text,
      'durationFrom': _fromController.text,
      'durationTo': _toController.text,
      'keyResponsibilities': _responsibilitiesController.text,
      'reasonForLeaving': _reasonController.text,
    });
  }

  /// Display date in DD-MM-YYYY (controller stores YYYY-MM-DD for API).
  String _formatDateDisplay(String value) {
    if (value.isEmpty) return 'Tap to select date';
    try {
      final dt = DateFormat('yyyy-MM-dd').parse(value);
      return DateFormat('dd-MM-yyyy').format(dt);
    } catch (e) {
      return value;
    }
  }

  Future<void> _selectFromDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedFromDate ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedFromDate = picked;
        _fromController.text = DateFormat('yyyy-MM-dd').format(picked);
        _notify();
      });
    }
  }

  Future<void> _selectToDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedToDate ?? DateTime.now(),
      firstDate: _selectedFromDate ?? DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedToDate = picked;
        _toController.text = DateFormat('yyyy-MM-dd').format(picked);
        _notify();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Experience ${widget.index}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 22,
                    ),
                    onPressed: widget.onRemove,
                    tooltip: 'Remove',
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _companyController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Company *',
                prefixIcon: Icon(
                  Icons.business,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _roleController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Role *',
                prefixIcon: Icon(
                  Icons.work_outline,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _designationController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Designation',
                prefixIcon: Icon(
                  Icons.badge_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectFromDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'From Date *',
                        prefixIcon: Icon(
                          Icons.calendar_today,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        labelStyle: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      child: Text(
                        _formatDateDisplay(_fromController.text),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: _fromController.text.isEmpty
                              ? Colors.grey
                              : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _selectToDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'To Date *',
                        prefixIcon: Icon(
                          Icons.calendar_month,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        labelStyle: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      child: Text(
                        _formatDateDisplay(_toController.text),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: _toController.text.isEmpty
                              ? Colors.grey
                              : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _responsibilitiesController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Key Responsibilities',
                prefixIcon: Icon(
                  Icons.list_alt,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Reason for Leaving',
                prefixIcon: Icon(
                  Icons.exit_to_app,
                  size: 20,
                  color: AppColors.primary,
                ),
                labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 4), // Small spacing after last field
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onSave;
  final String? profilePhotoUrl;
  final VoidCallback? onEditProfilePhoto;
  final VoidCallback? onDeleteProfilePhoto;

  const _EditProfileSheet({
    required this.userData,
    required this.onSave,
    this.profilePhotoUrl,
    this.onEditProfilePhoto,
    this.onDeleteProfilePhoto,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _genderController;
  late TextEditingController _dobController;
  late TextEditingController _maritalStatusController;
  late TextEditingController _bloodGroupController;
  late TextEditingController _addrLine1Controller;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _postalCodeController;
  late TextEditingController _countryController;
  late TextEditingController _bankNameController;
  late TextEditingController _accNumController;
  late TextEditingController _ifscController;
  late TextEditingController _holderController;
  late TextEditingController _upiController;
  late TextEditingController _uanController;
  late TextEditingController _panController;
  late TextEditingController _aadhaarController;
  late TextEditingController _pfNumberController;
  late TextEditingController _esiNumberController;
  DateTime? _selectedDob;
  late TextEditingController _oldPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;

  bool _showOldPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10 || digitsOnly.length > 15) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  String? _validatePostalCode(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final v = value.trim();
    if (v.length < 3 || v.length > 10) {
      return 'Postal code must be 3–10 digits';
    }
    if (!RegExp(r'^\d+$').hasMatch(v)) {
      return 'Postal code must contain only numbers';
    }
    return null;
  }

  String? _validateCountry(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length < 2) {
      return 'Country must be at least 2 characters';
    }
    if (value.trim().length > 56) {
      return 'Country name too long';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final d = widget.userData;
    _nameController = TextEditingController(text: d['name']);
    _emailController = TextEditingController(text: d['email'] ?? '');
    _phoneController = TextEditingController(text: d['phone']);
    _genderController = TextEditingController(text: d['gender']);

    // Parse DOB for date picker
    if (d['dob'] != null) {
      try {
        final dobString = d['dob'].toString();
        if (dobString.contains('T')) {
          _selectedDob = DateTime.parse(dobString.split('T')[0]);
        } else {
          _selectedDob = DateTime.parse(dobString);
        }
        _dobController = TextEditingController(
          text: DateFormat('yyyy-MM-dd').format(_selectedDob!),
        );
      } catch (e) {
        _dobController = TextEditingController();
      }
    } else {
      _dobController = TextEditingController();
    }

    _maritalStatusController = TextEditingController(text: d['maritalStatus']);
    _bloodGroupController = TextEditingController(text: d['bloodGroup']);
    _addrLine1Controller = TextEditingController(text: d['address']?['line1']);
    _cityController = TextEditingController(text: d['address']?['city']);
    _stateController = TextEditingController(text: d['address']?['state']);
    _postalCodeController = TextEditingController(
      text: d['address']?['postalCode'],
    );
    _countryController = TextEditingController(text: d['address']?['country']);
    _bankNameController = TextEditingController(
      text: d['bankDetails']?['bankName'],
    );
    _accNumController = TextEditingController(
      text: d['bankDetails']?['accountNumber'],
    );
    _ifscController = TextEditingController(
      text: d['bankDetails']?['ifscCode'],
    );
    _holderController = TextEditingController(
      text: d['bankDetails']?['accountHolderName'],
    );
    _upiController = TextEditingController(text: d['bankDetails']?['upiId']);

    // Employment IDs
    final empIds = d['employmentIds'] ?? {};
    _uanController = TextEditingController(text: empIds['uan'] ?? '');
    _panController = TextEditingController(text: empIds['pan'] ?? '');
    _aadhaarController = TextEditingController(text: empIds['aadhaar'] ?? '');
    _pfNumberController = TextEditingController(text: empIds['pfNumber'] ?? '');
    _esiNumberController = TextEditingController(
      text: empIds['esiNumber'] ?? '',
    );
    _oldPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _genderController.dispose();
    _dobController.dispose();
    _maritalStatusController.dispose();
    _bloodGroupController.dispose();
    _addrLine1Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _bankNameController.dispose();
    _accNumController.dispose();
    _ifscController.dispose();
    _holderController.dispose();
    _upiController.dispose();
    _uanController.dispose();
    _panController.dispose();
    _aadhaarController.dispose();
    _pfNumberController.dispose();
    _esiNumberController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Profile',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 28),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildSectionTitle('Personal Information'),
                    if (widget.onEditProfilePhoto != null ||
                        widget.onDeleteProfilePhoto != null) ...[
                      _buildProfilePhotoRow(),
                      const SizedBox(height: 16),
                    ],
                    _buildTextField(_nameController, 'Full Name', Icons.person),
                    _buildTextField(
                      _emailController,
                      'Email',
                      Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    _buildTextField(
                      _phoneController,
                      'Phone',
                      Icons.phone,
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Gender',
                            icon: Icons.group,
                            options: const ['Male', 'Female', 'Other'],
                            value: _genderController.text.isEmpty
                                ? null
                                : _genderController.text,
                            onChanged: (val) {
                              setState(() {
                                _genderController.text = val ?? '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _buildDatePickerField()),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Marital Status',
                            icon: Icons.favorite,
                            options: const ['Single', 'Married'],
                            value: _maritalStatusController.text.isEmpty
                                ? null
                                : _maritalStatusController.text,
                            onChanged: (val) {
                              setState(() {
                                _maritalStatusController.text = val ?? '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            _bloodGroupController,
                            'Blood Group',
                            Icons.bloodtype,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Address'),
                    _buildTextField(
                      _addrLine1Controller,
                      'Address Line 1',
                      Icons.location_on,
                      maxLines: 3,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            _cityController,
                            'City',
                            Icons.location_city,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            _stateController,
                            'State',
                            Icons.map,
                          ),
                        ),
                      ],
                    ),
                    _buildTextField(
                      _postalCodeController,
                      'Postal Code',
                      Icons.markunread_mailbox,
                      keyboardType: TextInputType.number,
                      validator: _validatePostalCode,
                    ),
                    _buildTextField(
                      _countryController,
                      'Country',
                      Icons.public,
                      validator: _validateCountry,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Employment IDs'),
                    _buildTextField(
                      _uanController,
                      'UAN Number',
                      Icons.badge_outlined,
                    ),
                    _buildTextField(
                      _panController,
                      'PAN Number',
                      Icons.credit_card,
                    ),
                    _buildTextField(
                      _aadhaarController,
                      'Aadhaar Number',
                      Icons.perm_identity,
                    ),
                    _buildTextField(
                      _pfNumberController,
                      'PF Number',
                      Icons.numbers,
                    ),
                    _buildTextField(
                      _esiNumberController,
                      'ESI Number',
                      Icons.numbers,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Bank Details'),
                    _buildTextField(
                      _bankNameController,
                      'Bank Name',
                      Icons.account_balance,
                    ),
                    _buildTextField(
                      _accNumController,
                      'Account Number',
                      Icons.numbers,
                    ),
                    _buildTextField(_ifscController, 'IFSC Code', Icons.code),
                    _buildTextField(
                      _holderController,
                      'Holder Name',
                      Icons.badge,
                    ),
                    _buildTextField(_upiController, 'UPI ID', Icons.payment),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Face Registration'),
                    _buildFaceEnrollTile(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Change Password'),
                    _buildPasswordField(
                      controller: _oldPasswordController,
                      label: 'Old Password',
                    ),
                    _buildPasswordField(
                      controller: _newPasswordController,
                      label: 'New Password',
                    ),
                    _buildPasswordField(
                      controller: _confirmPasswordController,
                      label: 'Confirm New Password',
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) {
                      return;
                    }

                    final oldPwd = _oldPasswordController.text.trim();
                    final newPwd = _newPasswordController.text.trim();
                    final confirmPwd = _confirmPasswordController.text.trim();

                    Map<String, String>? passwordChange;

                    if (oldPwd.isNotEmpty ||
                        newPwd.isNotEmpty ||
                        confirmPwd.isNotEmpty) {
                      if (oldPwd.isEmpty ||
                          newPwd.isEmpty ||
                          confirmPwd.isEmpty) {
                        SnackBarUtils.showSnackBar(
                          context,
                          'Please fill all password fields',
                          isError: true,
                        );
                        return;
                      }

                      if (newPwd != confirmPwd) {
                        SnackBarUtils.showSnackBar(
                          context,
                          'New passwords do not match',
                          isError: true,
                        );
                        return;
                      }

                      if (oldPwd == newPwd) {
                        SnackBarUtils.showSnackBar(
                          context,
                          'Old password and new password should not be the same',
                          isError: true,
                        );
                        return;
                      }

                      if (newPwd.length < 6) {
                        SnackBarUtils.showSnackBar(
                          context,
                          'New password should be at least 6 characters',
                          isError: true,
                        );
                        return;
                      }

                      passwordChange = {
                        'oldPassword': oldPwd,
                        'newPassword': newPwd,
                      };
                    }

                    widget.onSave({
                      'name': _nameController.text,
                      'email': _emailController.text,
                      'phone': _phoneController.text,
                      'gender': _genderController.text,
                      'maritalStatus': _maritalStatusController.text,
                      'dob': _dobController.text,
                      'bloodGroup': _bloodGroupController.text,
                      'address': {
                        'line1': _addrLine1Controller.text,
                        'city': _cityController.text,
                        'state': _stateController.text,
                        'postalCode': _postalCodeController.text.trim(),
                        'country': _countryController.text.trim(),
                      },
                      'employmentIds': {
                        'uan': _uanController.text,
                        'pan': _panController.text,
                        'aadhaar': _aadhaarController.text,
                        'pfNumber': _pfNumberController.text,
                        'esiNumber': _esiNumberController.text,
                      },
                      'bankDetails': {
                        'bankName': _bankNameController.text,
                        'accountNumber': _accNumController.text,
                        'ifscCode': _ifscController.text,
                        'accountHolderName': _holderController.text,
                        'upiId': _upiController.text,
                      },
                      if (passwordChange != null)
                        'passwordChange': passwordChange,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Save All Changes',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1,
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

  Widget _buildProfilePhotoRow() {
    final photoUrl = widget.profilePhotoUrl;
    final hasPhoto =
        photoUrl != null &&
        photoUrl.isNotEmpty &&
        (photoUrl.startsWith('http://') || photoUrl.startsWith('https://'));
    final name = widget.userData['name']?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            backgroundImage: hasPhoto ? CachedNetworkImageProvider(photoUrl) : null,
            child: hasPhoto
                ? null
                : Text(
                    initial,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          const Spacer(),
          if (widget.onEditProfilePhoto != null)
            TextButton.icon(
              onPressed: widget.onEditProfilePhoto,
              icon: Icon(Icons.edit, size: 18, color: AppColors.primary),
              label: Text(
                'Edit',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (widget.onDeleteProfilePhoto != null)
            TextButton.icon(
              onPressed: widget.onDeleteProfilePhoto,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              label: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool obscureText = false,
    Widget? suffixIcon,
    int? maxLines,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        obscureText: obscureText,
        maxLines: maxLines ?? 1,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 24,
          ),
          suffixIcon: suffixIcon,
          labelStyle: const TextStyle(color: Colors.black, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
          alignLabelWithHint: maxLines != null && maxLines > 1,
        ),
        scrollPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      ),
    );
  }

  Widget _buildDatePickerField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: InkWell(
        onTap: () async {
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate:
                _selectedDob ??
                DateTime.now().subtract(const Duration(days: 365 * 25)),
            firstDate: DateTime(1950),
            lastDate: DateTime.now(),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: AppColors.primary,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
                ),
                child: child!,
              );
            },
          );
          if (picked != null && picked != _selectedDob) {
            setState(() {
              _selectedDob = picked;
              _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
            });
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Date of Birth',
            prefixIcon: Icon(
              Icons.calendar_today,
              size: 22,
              color: AppColors.primary,
            ),
            labelStyle: const TextStyle(color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          child: Text(
            _selectedDob != null
                ? DateFormat('dd-MM-yyyy').format(_selectedDob!)
                : 'Select Date',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: _selectedDob != null ? Colors.black : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required List<String> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: options
            .map(
              (opt) => DropdownMenuItem<String>(value: opt, child: Text(opt)),
            )
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
          labelStyle: const TextStyle(color: Colors.grey),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  /// Tile that opens the one-time face-enrollment screen. Registering a face makes
  /// every future punch match against those fixed samples (reliable), instead of the
  /// rolling-selfie reference.
  Widget _buildFaceEnrollTile() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.face_retouching_natural, color: AppColors.primary),
        title: const Text('Register your face'),
        subtitle: const Text(
          'Capture a few samples used to verify your punches.',
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final done = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const FaceEnrollScreen()),
          );
          if (done == true && mounted) {
            SnackBarUtils.showSnackBar(context, 'Face registered successfully.');
          }
        },
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
  }) {
    bool isOld = controller == _oldPasswordController;
    bool isNew = controller == _newPasswordController;

    bool visible;
    if (isOld) {
      visible = _showOldPassword;
    } else if (isNew) {
      visible = _showNewPassword;
    } else {
      visible = _showConfirmPassword;
    }

    return _buildTextField(
      controller,
      label,
      Icons.lock,
      obscureText: !visible,
      suffixIcon: IconButton(
        icon: Icon(
          visible ? Icons.visibility : Icons.visibility_off,
          color: Colors.grey,
        ),
        onPressed: () {
          setState(() {
            if (isOld) {
              _showOldPassword = !_showOldPassword;
            } else if (isNew) {
              _showNewPassword = !_showNewPassword;
            } else {
              _showConfirmPassword = !_showConfirmPassword;
            }
          });
        },
      ),
    );
  }
}
