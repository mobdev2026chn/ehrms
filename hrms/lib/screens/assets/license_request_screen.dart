import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
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
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'License Request',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        elevation: 0,
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderBanner(),
              const SizedBox(height: 20),
              _buildFormCard(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Submit Request',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.send, size: 18),
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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: -8,
            child: Icon(
              Icons.workspace_premium_outlined,
              size: 80,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Empower your\nproductivity.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Submit your software needs below.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
              suffixIcon: Icon(Icons.apps,
                  color: AppColors.textCaption, size: 20),
            ),
          ),
          const SizedBox(height: 20),
          _label('LICENSE TYPE'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _licenseType,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down),
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
                  icon: Icons.info_outline,
                  text: 'Requests are reviewed within 48 hours.',
                  bg: AppColors.primary.withValues(alpha: 0.1),
                  fg: AppColors.primaryDark,
                  iconBg: AppColors.primary,
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
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: AppColors.textPrimary,
        ),
      );

  InputDecoration _inputDecoration({required String hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textCaption, fontSize: 14),
      filled: true,
      fillColor: AppColors.inputFill,
      suffixIcon: suffixIcon,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String text,
    required Color bg,
    required Color fg,
    required Color iconBg,
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
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: fg, height: 1.3),
          ),
        ],
      ),
    );
  }
}
