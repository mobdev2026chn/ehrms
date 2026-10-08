// Shared Exit Ride bottom sheet – exit type (Hold ride / Exit full ride) + reason required.
// Used by LiveTrackingScreen and ArrivedScreen.
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:hrms/utils/snackbar_utils.dart';

/// Exit type: 'hold' = staff can resume; 'exited' = only after admin reopens.
const String kExitTypeHold = 'hold';
const String kExitTypeExited = 'exited';

class ExitRideBottomSheet extends StatefulWidget {
  final Future<void> Function(String exitType, String reason)? onSubmit;

  const ExitRideBottomSheet({super.key, this.onSubmit});

  @override
  State<ExitRideBottomSheet> createState() => _ExitRideBottomSheetState();
}

class _ExitRideBottomSheetState extends State<ExitRideBottomSheet> {
  final _reasonController = TextEditingController();
  String? _selectedExitType; // 'hold' | 'exited'
  String? _selectedReason;
  bool _submitting = false;
  static const _exitTypeOptions = [
    {'label': 'Hold ride', 'value': kExitTypeHold},
    {'label': 'Exit full ride', 'value': kExitTypeExited},
  ];
  static const _presetReasons = [
    'Customer not available',
    'Wrong address',
    'Traffic / Delayed',
    'Vehicle issue',
    'Personal emergency',
    'Other',
  ];

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_selectedExitType == null || _selectedExitType!.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Please select Hold ride or Exit full ride',
        isError: true,
      );
      return;
    }
    String reason;
    if (_selectedReason == 'Other') {
      reason = _reasonController.text.trim();
      if (reason.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Please enter a reason',
          isError: true,
        );
        return;
      }
    } else if (_selectedReason != null && _selectedReason!.isNotEmpty) {
      reason = _selectedReason!;
    } else {
      SnackBarUtils.showSnackBar(
        context,
        'Please select or enter a reason',
        isError: true,
      );
      return;
    }
    final exitType = _selectedExitType!;
    if (widget.onSubmit == null) {
      if (context.mounted) {
        Navigator.of(context).pop(<String, String>{'exitType': exitType, 'reason': reason});
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit!(exitType, reason);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[ExitRideBottomSheet] submit error: $e');
      setState(() => _submitting = false);
      // The server did not hold/exit the task: stay open with its reason so the staff
      // member can retry, instead of leaving as if it had worked.
      SnackBarUtils.showSnackBar(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.exit_to_app_rounded,
                      size: 30,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Exit Task',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headingLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tracking will stop. Hold ride: you can resume later. Exit full ride: only admin can reopen.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Exit type (required)',
                  style: AppTextStyles.label,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedExitType,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  isExpanded: true,
                  hint: const Text(
                    'Select Hold ride or Exit full ride',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  items: _exitTypeOptions
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e['value'] as String,
                          child: Text(
                            e['label'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _selectedExitType = v),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Reason (required)',
                  style: AppTextStyles.label,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReason,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  isExpanded: true,
                  hint: const Text(
                    'Select a reason',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  items: _presetReasons
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(
                            r,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _selectedReason = v),
                ),
                if (_selectedReason == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reasonController,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      hintText: 'Enter your reason',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    maxLines: 2,
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _submit,
                          icon: _submitting
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.exit_to_app_rounded, size: 18),
                          label: Text(
                            _submitting ? 'Exiting...' : 'Exit Task',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
