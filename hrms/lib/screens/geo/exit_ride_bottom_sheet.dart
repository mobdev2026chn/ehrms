// Shared Exit Ride bottom sheet – exit type (Hold ride / Exit full ride) + reason required.
// Used by LiveTrackingScreen and ArrivedScreen.
import 'package:flutter/material.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Hold ride or Exit full ride'),
        ),
      );
      return;
    }
    String reason;
    if (_selectedReason == 'Other') {
      reason = _reasonController.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please enter a reason')));
        return;
      }
    } else if (_selectedReason != null && _selectedReason!.isNotEmpty) {
      reason = _selectedReason!;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter a reason')),
      );
      return;
    }
    final exitType = _selectedExitType!;
    if (widget.onSubmit == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(
          context,
        ).pop(<String, String>{'exitType': exitType, 'reason': reason});
      });
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit!(exitType, reason);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      var message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring(11);
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.exit_to_app_rounded,
                      size: 40,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Exit Task',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tracking will stop. Hold ride: you can resume later. Exit full ride: only admin can reopen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Exit type (required)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedExitType,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  hint: Text(
                    'Select Hold ride or Exit full ride',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  items: _exitTypeOptions
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e['value'] as String,
                          child: Text(e['label'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _selectedExitType = v),
                ),
                const SizedBox(height: 16),
                Text(
                  'Reason (required)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedReason,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  hint: Text(
                    'Select a reason',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  items: _presetReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
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
                    decoration: InputDecoration(
                      hintText: 'Enter your reason',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
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
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          shadowColor: Colors.orange.withOpacity(0.4),
                        ),
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.exit_to_app_rounded, size: 18),
                        label: Text(
                          _submitting ? 'Exiting...' : 'Exit Task',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
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
