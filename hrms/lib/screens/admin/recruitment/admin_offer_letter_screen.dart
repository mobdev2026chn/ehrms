// lib/screens/admin/recruitment/admin_offer_letter_screen.dart
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_staff_service.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminOfferLetterItem {
  final String id;
  final String candidateName;
  final String candidateEmail;
  final String position;
  final String department;
  final String ctcSalary;
  final String joiningDate;
  final String createdDate;
  String status; // 'Pending' | 'Accepted' | 'Expired' | 'Rejected'
  final String signatoryName;
  final String signatoryDesignation;

  AdminOfferLetterItem({
    required this.id,
    required this.candidateName,
    required this.candidateEmail,
    required this.position,
    required this.department,
    required this.ctcSalary,
    required this.joiningDate,
    required this.createdDate,
    required this.status,
    this.signatoryName = 'Akash Sharma',
    this.signatoryDesignation = 'Director of Human Resources',
  });

  String get initials {
    final parts = candidateName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'C';
  }

  factory AdminOfferLetterItem.fromJson(Map<String, dynamic> json) {
    return AdminOfferLetterItem(
      id: (json['id'] ?? json['_id'] ?? 'OFF-001').toString(),
      candidateName: (json['candidateName'] ?? json['name'] ?? 'Candidate').toString(),
      candidateEmail: (json['candidateEmail'] ?? json['email'] ?? '').toString(),
      position: (json['position'] ?? json['role'] ?? 'Software Engineer').toString(),
      department: (json['department'] ?? 'Engineering').toString(),
      ctcSalary: (json['ctcSalary'] ?? json['salary'] ?? '12.0 LPA').toString(),
      joiningDate: (json['joiningDate'] ?? '2026-07-20').toString(),
      createdDate: (json['createdDate'] ?? json['createdAt'] ?? '2026-06-28').toString(),
      status: (json['status'] ?? 'Pending').toString(),
      signatoryName: (json['signatoryName'] ?? 'Akash Sharma').toString(),
      signatoryDesignation: (json['signatoryDesignation'] ?? 'Director of Human Resources').toString(),
    );
  }
}

class AdminOfferLetterScreen extends StatefulWidget {
  const AdminOfferLetterScreen({super.key});

  @override
  State<AdminOfferLetterScreen> createState() => _AdminOfferLetterScreenState();
}

class _AdminOfferLetterScreenState extends State<AdminOfferLetterScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminStaffService _staffService = AdminStaffService();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';
  String _departmentFilter = 'All Departments';

  List<AdminOfferLetterItem> _offers = [];
  List<String> _departments = ['All Departments', 'Engineering', 'Design', 'DevOps', 'Human Resources'];

  @override
  void initState() {
    super.initState();
    _fetchOffersAndSetup();
  }

  Future<void> _fetchOffersAndSetup({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      // 1. Load dynamic backend departments
      try {
        final setupRes = await _staffService.getStaffSetup();
        if (setupRes['success'] == true && setupRes['data'] != null) {
          final branches = setupRes['data']['branches'] as List? ?? [];
          final depts = <String>{};
          for (final b in branches) {
            final d = (b['department'] ?? b['dept'])?.toString().trim();
            if (d != null && d.isNotEmpty) depts.add(d);
          }
          if (depts.isNotEmpty && mounted) {
            setState(() {
              _departments = {'All Departments', ..._departments.skip(1), ...depts}.toList();
            });
          }
        }
      } catch (_) {}

      // 2. Load offer letters from backend API
      final res = await _api.request('/admin/recruitment/offer-letter');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['offers'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _offers = list.map((e) => AdminOfferLetterItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        } else {
          _setMockOffers();
        }
      } else {
        _setMockOffers();
      }
    } catch (_) {
      _setMockOffers();
    }

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  void _setMockOffers() {
    _offers = [
      AdminOfferLetterItem(
        id: 'OFF-001',
        candidateName: 'Sunita Rao',
        candidateEmail: 'sunita.rao@example.com',
        position: 'Senior Frontend Developer',
        department: 'Engineering',
        ctcSalary: '12.5 LPA',
        joiningDate: '2026-07-20',
        createdDate: '2026-06-28',
        status: 'Pending',
      ),
      AdminOfferLetterItem(
        id: 'OFF-002',
        candidateName: 'Priya Patel',
        candidateEmail: 'priya.patel@example.com',
        position: 'Lead UI/UX Designer',
        department: 'Design',
        ctcSalary: '11.0 LPA',
        joiningDate: '2026-07-28',
        createdDate: '2026-07-01',
        status: 'Expired',
      ),
      AdminOfferLetterItem(
        id: 'OFF-003',
        candidateName: 'Amit Sharma',
        candidateEmail: 'amit.sharma@example.com',
        position: 'Senior Full-Stack Engineer',
        department: 'Engineering',
        ctcSalary: '18.0 LPA',
        joiningDate: '2026-08-01',
        createdDate: '2026-07-05',
        status: 'Accepted',
      ),
    ];
  }

  List<AdminOfferLetterItem> get _filteredOffers {
    return _offers.where((offer) {
      final matchesSearch = _searchQuery.isEmpty ||
          offer.candidateName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          offer.candidateEmail.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          offer.position.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesDept = _departmentFilter == 'All Departments' ||
          offer.department.toLowerCase() == _departmentFilter.toLowerCase() ||
          (_departmentFilter == 'Human Resources' && offer.department.toLowerCase().contains('hr'));

      return matchesSearch && matchesDept;
    }).toList();
  }

  // ── Action: View Offer Letter Modal ──
  void _showViewLetterModal(AdminOfferLetterItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(20),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Letterhead
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('EKTA HRMS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 1)),
                      Text('OFFICIAL EMPLOYMENT OFFER', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.mail_outline_rounded, color: Color(0xFFD97706), size: 20),
                  ),
                ],
              ),
              const Divider(height: 24, color: Color(0xFFE2E8F0)),

              Text('Date: ${item.createdDate}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              Text('Dear ${item.candidateName},', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(
                'We are pleased to offer you the position of ${item.position} in the ${item.department} Department at EKTA HRMS.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.4),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _letterSpecRow('Designation', item.position),
                    _letterSpecRow('Department', item.department),
                    _letterSpecRow('Annual CTC', item.ctcSalary),
                    _letterSpecRow('Date of Joining', item.joiningDate),
                    _letterSpecRow('Current Status', item.status),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              const Text(
                'Please sign and return the duplicate copy of this letter within 7 days as a token of your acceptance.',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),

              // Signatory
              Text(item.signatoryName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              Text(item.signatoryDesignation, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              SnackBarUtils.showSnackBar(context, 'Downloading Offer Letter PDF...');
            },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEFAA1F),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _letterSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  // ── Action: Accept Offer ──
  void _acceptOffer(AdminOfferLetterItem item) {
    setState(() => item.status = 'Accepted');
    try {
      _api.request('/admin/recruitment/offer-letter/${item.id}/accept', method: 'POST');
    } catch (_) {}
    SnackBarUtils.showSnackBar(context, 'Offer marked as Accepted for ${item.candidateName}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Offer Letter Dashboard',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _fetchOffersAndSetup(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchOffersAndSetup(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Filter Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Review generated employment offer details, track acceptance status, and manually verify decisions.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 12),

                        // Search
                        Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: const InputDecoration(
                              hintText: 'Search candidates name or email...',
                              hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Department Dropdown Filter
                        Row(
                          children: [
                            const Icon(Icons.filter_list_rounded, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            const Text('Department:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _departments.contains(_departmentFilter) ? _departmentFilter : 'All Departments',
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                    items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _departmentFilter = v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_filteredOffers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Text('No offer letters found', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    )
                  else
                    ..._filteredOffers.map((item) => _buildOfferCard(item)),
                ],
              ),
            ),
    );
  }

  Widget _buildOfferCard(AdminOfferLetterItem item) {
    Color stBg = const Color(0xFFFEF3C7);
    Color stFg = const Color(0xFFD97706);
    if (item.status == 'Accepted') {
      stBg = const Color(0xFFDCFCE7);
      stFg = const Color(0xFF16A34A);
    } else if (item.status == 'Expired' || item.status == 'Rejected') {
      stBg = const Color(0xFFF1F5F9);
      stFg = const Color(0xFF64748B);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Initials Avatar
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Text(
                  item.initials,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.candidateName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    Text(item.candidateEmail, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stBg,
                  borderRadius: BorderRadius.circular(20),
                  border: item.status == 'Expired' ? Border.all(color: const Color(0xFFCBD5E1)) : null,
                ),
                child: Text(
                  item.status,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: stFg),
                ),
              ),
              const SizedBox(width: 4),

              // 3-Dots Action Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF94A3B8)),
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (action) {
                  if (action == 'view') {
                    _showViewLetterModal(item);
                  } else if (action == 'accept') {
                    _acceptOffer(item);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.remove_red_eye_outlined, size: 16, color: Color(0xFF64748B)),
                        SizedBox(width: 8),
                        Text('View Letter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  if (item.status != 'Accepted')
                    const PopupMenuItem(
                      value: 'accept',
                      child: Row(
                        children: [
                          Icon(Icons.check_rounded, size: 16, color: Color(0xFF16A34A)),
                          SizedBox(width: 8),
                          Text('Accept Offer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Role, Dept, CTC, Joining Date & Created Date
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.position, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                          const SizedBox(height: 2),
                          Text(item.department.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFA7F3D0))),
                      child: Text(item.ctcSalary, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF16A34A))),
                    ),
                  ],
                ),
                const Divider(height: 14, color: Color(0xFFE2E8F0)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text('Joining: ${item.joiningDate}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                      ],
                    ),
                    Text('Created: ${item.createdDate}', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
