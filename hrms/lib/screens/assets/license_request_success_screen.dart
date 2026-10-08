import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_card.dart';

/// Figma "Request Submitted!" confirmation screen, shown after a software
/// licence request is submitted from [LicenseRequestScreen].
class LicenseRequestSuccessScreen extends StatelessWidget {
  final String softwareName;
  final String licenseType;
  final String referenceNo;
  final String dateLabel;

  const LicenseRequestSuccessScreen({
    super.key,
    required this.softwareName,
    required this.licenseType,
    required this.referenceNo,
    required this.dateLabel,
  });

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
        title: const Text('Submit Request'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              FadeSlideIn(
                child: Column(
                  children: [
                    // Success check with soft halo.
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.12),
                      ),
                      child: Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                          child: Icon(Icons.check_rounded,
                              color: AppColors.onPrimary, size: 36),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Request Submitted!',
                      style: AppTextStyles.headingLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your request for $softwareName has been sent for '
                      "approval. You'll receive an update within 48 hours.",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: SizedBox(
                  width: double.infinity,
                  child: AppCard(
                  padding: const EdgeInsets.all(20),
                  border: Border.all(color: const Color(0xFFECEEF1)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.auto_awesome,
                                color: AppColors.primaryText, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Request Summary',
                                  style: AppTextStyles.headingSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'REF: $referenceNo',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _summaryRow('Software', softwareName),
                      const Divider(height: 24),
                      _summaryRow('Type', licenseType),
                      const Divider(height: 24),
                      _summaryRow('Date', dateLabel),
                    ],
                  ),
                ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Back to My Assets'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
