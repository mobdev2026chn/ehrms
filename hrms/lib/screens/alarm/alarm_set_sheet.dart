import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../services/alarm_service.dart';
import '../../services/fcm_service.dart';

/// Bottom sheet to set an alarm. Alarm will ring and show a notification even when app is closed.
class AlarmSetSheet extends StatefulWidget {
  const AlarmSetSheet({super.key});

  @override
  State<AlarmSetSheet> createState() => _AlarmSetSheetState();
}

class _AlarmSetSheetState extends State<AlarmSetSheet> {
  TimeOfDay _selectedTime = TimeOfDay.now();
  DateTime? _nextAlarm;
  final TextEditingController _noteController = TextEditingController();
  static String? _lastNote;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (_lastNote != null) _noteController.text = _lastNote!;
    _loadNextAlarm();
  }

  Future<void> _loadNextAlarm() async {
    final next = await AlarmService.getNextAlarm();
    if (mounted) setState(() => _nextAlarm = next);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _setAlarm() async {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, _selectedTime.hour, _selectedTime.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    _lastNote = _noteController.text.trim();
    final note = _lastNote?.isNotEmpty == true ? _lastNote! : 'Your alarm is ringing';

    // Try to request exact alarm permission (user can ignore if toggle is disabled)
    await AlarmService.requestExactAlarmPermission(FcmService.localNotifications);

    final ok = await AlarmService.scheduleAlarm(
      scheduled,
      plugin: FcmService.localNotifications,
      title: 'Alarm',
      body: note,
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm set for ${DateFormat.jm().format(scheduled)}'),
          backgroundColor: AppColors.primary,
        ),
      );
    } else {
      _showAlarmFailedDialog();
    }
  }

  void _showAlarmFailedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Could not set alarm'),
        content: const Text(
          'Please allow "Alarms & reminders" for this app:\n\n'
          'Settings → Apps → ektaHr → Alarms & reminders → Turn ON',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await AlarmService.requestExactAlarmPermission(FcmService.localNotifications);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelAlarm() async {
    await AlarmService.cancelAllAlarms(FcmService.localNotifications);
    if (mounted) {
      setState(() => _nextAlarm = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm canceled')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeStr = _selectedTime.format(context);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.alarm_rounded, color: AppColors.primary, size: 28),
              const SizedBox(width: 12),
              Text(
                'Set Alarm',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time_rounded, color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Add a reminder note...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.note_outlined),
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          if (_nextAlarm != null) ...[
            const SizedBox(height: 16),
            Text(
              'Next alarm: ${DateFormat.jm().format(_nextAlarm!)}',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cancelAlarm,
              child: const Text('Cancel alarm'),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _setAlarm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Set Alarm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
