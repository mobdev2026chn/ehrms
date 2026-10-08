import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import 'license_request_success_screen.dart';

/// Figma "License Request" form. Lets an employee request a new software
/// licence (software name, billing frequency and a business justification).
///
/// There is no licence-request backend endpoint, so submission generates a
/// local reference number and routes to the confirmation screen.
class LicenseRequestScreen extends StatefulWidget {
  /// Optionally pre-fills the software name (e.g. when requesting a renewal of
  /// an existing subscription).
  final String? prefillSoftwareName;

  const LicenseRequestScreen({super.key, this.prefillSoftwareName});

  @override
  State<LicenseRequestScreen> createState() => _LicenseRequestScreenState();
}

class _LicenseRequestScreenState extends State<LicenseRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final TextEditingController _justificationController =
      TextEditingController();
  String? _licenseType;
  bool _submitting = false;

  static const List<String> _frequencies = [
    'Monthly',
    'Quarterly',
    'Annual',
    'Perpetual',
  ];

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.prefillSoftwareName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _justificationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    // Simulate a short submit so the button state is perceptible.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final now = DateTime.now();
    final ref =
        'SL-${now.year}-${now.millisecondsSinceEpoch % 1000}'.toUpperCase();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LicenseRequestSuccessScreen(
          softwareName: _nameController.text.trim(),
          licenseType: _licenseType ?? 'Annual',
          referenceNo: '#$ref',
          dateLabel: DateFormat('MMM d, yyyy').format(now),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('License Request'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderBanner(),
              const SizedBox(height: 16),
              _buildFormCard(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.textSecondary),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Submit Request'),
                            SizedBox(width: 8),
                            Icon(Icons.send_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: -8,
            child: Icon(
              Icons.workspace_premium_outlined,
              size: 80,
              color: AppColors.onPrimary.withValues(alpha: 0.14),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Empower your\nproductivity.',
                style: AppTextStyles.headingLarge.copyWith(
                  color: AppColors.onPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Submit your software needs below.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onPrimary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return AppCard(
      padding: const EdgeInsets.all(20),
      border: Border.all(color: const Color(0xFFECEEF1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('SOFTWARE NAME'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please enter the software name'
                : null,
            decoration: _inputDecoration(
              hint: 'e.g. Adobe Creative Cloud',
              suffixIcon: const Icon(Icons.apps_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 20),
          _label('LICENSE TYPE'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _licenseType,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            borderRadius: BorderRadius.circular(12),
            decoration: _inputDecoration(hint: ''),
            hint: const Text('Select frequency',
                style: TextStyle(color: AppColors.textCaption)),
            validator: (v) =>
                v == null ? 'Please select a licence frequency' : null,
            items: _frequencies
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _licenseType = v),
          ),
          const SizedBox(height: 20),
          _label('JUSTIFICATION / BUSINESS NEED'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _justificationController,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please describe the business need'
                : null,
            decoration: _inputDecoration(
              hint:
                  'Describe how this software supports your workflow and department goals...',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _infoChip(
                  icon: Icons.info_outline_rounded,
                  text: 'Requests are reviewed within 48 hours.',
                  bg: AppColors.primary.withValues(alpha: 0.1),
                  fg: AppColors.primaryText,
                  iconBg: AppColors.primary,
                  iconFg: AppColors.onPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoChip(
                  icon: Icons.shield_outlined,
                  text: 'IT Compliance check required.',
                  bg: AppColors.inputFill,
                  fg: AppColors.textSecondary,
                  iconBg: AppColors.surfaceDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: AppTextStyles.sectionLabel.copyWith(
          color: AppColors.textSecondary,
        ),
      );

  // Field chrome (fill, radius, borders, focus) comes from the app-wide
  // InputDecorationTheme.
  InputDecoration _inputDecoration({required String hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String text,
    required Color bg,
    required Color fg,
    required Color iconBg,
    Color iconFg = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
            child: Icon(icon, size: 16, color: iconFg),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: AppTextStyles.caption
                .copyWith(color: fg, height: 1.35, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
