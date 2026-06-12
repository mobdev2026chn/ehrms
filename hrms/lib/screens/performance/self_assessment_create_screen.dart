// hrms/lib/screens/performance/self_assessment_create_screen.dart
// Create a self-assessment - employee picks a review cycle/type/period and submits
// their own self review (POST /api/performance/reviews/self-assessment).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../services/performance_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_tab_loader.dart';

class SelfAssessmentCreateScreen extends StatefulWidget {
  const SelfAssessmentCreateScreen({super.key});

  @override
  State<SelfAssessmentCreateScreen> createState() =>
      _SelfAssessmentCreateScreenState();
}

class _SelfAssessmentCreateScreenState
    extends State<SelfAssessmentCreateScreen> {
  final PerformanceService _performanceService = PerformanceService();
  final _formKey = GlobalKey<FormState>();

  static const List<String> _reviewTypes = [
    'Quarterly',
    'Half-Yearly',
    'Annual',
    'Probation',
    'Custom',
  ];

  List<dynamic> _cycles = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  String? _selectedCycle;
  String _selectedType = 'Quarterly';
  DateTime? _startDate;
  DateTime? _endDate;
  int _overallRating = 0;

  final List<TextEditingController> _strengthsControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _areasControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _achievementsControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _challengesControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _goalsAchievedControllers = [
    TextEditingController(),
  ];
  final TextEditingController _commentsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCycles();
  }

  @override
  void dispose() {
    for (final list in [
      _strengthsControllers,
      _areasControllers,
      _achievementsControllers,
      _challengesControllers,
      _goalsAchievedControllers,
    ]) {
      for (final c in list) {
        c.dispose();
      }
    }
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _fetchCycles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _performanceService.getReviewCycles(
        page: 1,
        limit: 100,
        status: null,
      );
      if (mounted) {
        final data = result['data'];
        setState(() {
          _cycles = data?['cycles'] as List? ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  List<String> _values(List<TextEditingController> list) => list
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _submit() async {
    if (_selectedCycle == null || _selectedCycle!.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Please select a review cycle',
          isError: true);
      return;
    }
    if (_startDate == null || _endDate == null) {
      SnackBarUtils.showSnackBar(context, 'Please select the review period',
          isError: true);
      return;
    }
    if (_overallRating == 0) {
      SnackBarUtils.showSnackBar(context, 'Please provide an overall rating',
          isError: true);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _performanceService.createSelfAssessment(
        reviewCycle: _selectedCycle!,
        reviewType: _selectedType,
        startDate: _startDate!.toIso8601String(),
        endDate: _endDate!.toIso8601String(),
        overallRating: _overallRating,
        strengths: _values(_strengthsControllers),
        areasForImprovement: _values(_areasControllers),
        achievements: _values(_achievementsControllers),
        challenges: _values(_challengesControllers),
        goalsAchieved: _values(_goalsAchievedControllers),
        comments: _commentsController.text.trim(),
      );
      if (mounted) {
        SnackBarUtils.showSnackBar(context, 'Self assessment created');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.toUserFriendlyMessage(e),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _addItem(List<TextEditingController> list) {
    setState(() => list.add(TextEditingController()));
  }

  void _removeItem(List<TextEditingController> list, int index) {
    if (list.length > 1) {
      setState(() {
        list[index].dispose();
        list.removeAt(index);
      });
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Self Assessment',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _error != null
              ? _buildErrorState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCycleSection(),
                        const SizedBox(height: 16),
                        _buildRatingSection(),
                        _buildListSection('Strengths', _strengthsControllers),
                        _buildListSection(
                            'Areas for Improvement', _areasControllers),
                        _buildListSection(
                            'Achievements', _achievementsControllers),
                        _buildListSection('Challenges', _challengesControllers),
                        _buildListSection(
                            'Goals Achieved', _goalsAchievedControllers),
                        _buildCommentsSection(),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Submit Self Assessment'),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error ?? 'Failed to load cycles',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchCycles,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCycleSection() {
    final cycleItems = <DropdownMenuItem<String>>[
      for (final c in _cycles)
        if ((c['name'] ?? '').toString().trim().isNotEmpty)
          DropdownMenuItem<String>(
            value: c['name'].toString(),
            child: Text(c['name'].toString(),
                overflow: TextOverflow.ellipsis),
          ),
    ];
    return _sectionCard(
      title: 'Review Cycle',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedCycle,
            isExpanded: true,
            decoration: _inputDecoration(
              cycleItems.isEmpty ? 'No cycles available' : 'Select cycle',
            ),
            items: cycleItems,
            onChanged: (v) => setState(() => _selectedCycle = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            isExpanded: true,
            decoration: _inputDecoration('Review type'),
            items: [
              for (final t in _reviewTypes)
                DropdownMenuItem<String>(value: t, child: Text(t)),
            ],
            onChanged: (v) =>
                setState(() => _selectedType = v ?? 'Quarterly'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildDateBox(
                  label: 'Start date',
                  value: _startDate,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateBox(
                  label: 'End date',
                  value: _endDate,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildDateBox({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _inputDecoration(label),
        child: Text(
          value != null ? DateFormat('MMM dd, yyyy').format(value) : label,
          style: TextStyle(
            fontSize: 14,
            color: value != null
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRatingSection() {
    return _sectionCard(
      title: 'Overall Rating',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(5, (i) {
              final rating = i + 1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _overallRating = rating),
                  child: Icon(
                    Icons.star_rounded,
                    size: 40,
                    color: rating <= _overallRating
                        ? AppColors.primary
                        : AppColors.divider,
                  ),
                ),
              );
            }),
          ),
          Text('$_overallRating/5',
              style:
                  TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildListSection(
      String title, List<TextEditingController> controllers) {
    return _sectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(controllers.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controllers[i],
                      decoration: _inputDecoration('Enter ${title.toLowerCase()}'),
                    ),
                  ),
                  if (controllers.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: () => _removeItem(controllers, i),
                      color: AppColors.error,
                    ),
                ],
              ),
            );
          }),
          TextButton.icon(
            onPressed: () => _addItem(controllers),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection() {
    return _sectionCard(
      title: 'Additional Comments',
      child: TextFormField(
        controller: _commentsController,
        maxLines: 5,
        decoration: _inputDecoration(
            'Add any additional comments about your performance...'),
      ),
    );
  }
}
