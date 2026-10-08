// Auto-send settings per kind (web: AutomationPanel). Each change is saved immediately with
// PUT /admin/celebration/settings { <kind>: { <field> } } and shown only once the server accepts it.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_celebration_service.dart';
import '../../../widgets/app_tab_loader.dart';
import 'celebration_shared.dart';

class CelebrationAutomationTab extends StatefulWidget {
  const CelebrationAutomationTab({super.key, required this.store});
  final CelebrationStore store;

  @override
  State<CelebrationAutomationTab> createState() => _CelebrationAutomationTabState();
}

class _CelebrationAutomationTabState extends State<CelebrationAutomationTab> {
  /// Kinds with a save in flight.
  final Set<String> _saving = {};

  CelebrationStore get _store => widget.store;

  Future<void> _update(String kind, Map<String, dynamic> patch) async {
    setState(() => _saving.add(kind));
    try {
      final next = await _store.api.updateSettings(kind, patch);
      _store.setSettings(next);
      if (!mounted) return;
      if (patch['enabled'] is bool) {
        showCelebrationSnack(
          context,
          'Auto-send ${patch['enabled'] == true ? 'enabled' : 'disabled'} for ${kind == 'birthday' ? 'birthdays' : 'anniversaries'}',
        );
      } else {
        showCelebrationSnack(context, 'Settings saved');
      }
    } catch (e) {
      if (mounted) showCelebrationError(context, e);
    } finally {
      if (mounted) setState(() => _saving.remove(kind));
    }
  }

  Future<void> _pickTime(String kind, AutomationSetting s) async {
    final parts = s.sendTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (value != s.sendTime) await _update(kind, {'sendTime': value});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final settings = _store.settings;
        if (settings == null && _store.settingsError != null) {
          return CelebrationErrorView(message: _store.settingsError!, onRetry: _store.loadSettings);
        }
        if (settings == null) return const Center(child: AppTabLoader());

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => Future.wait([_store.loadSettings(), _store.loadTemplates()]),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (_store.templatesError != null && _store.templates == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Expanded(
                      child: Text(_store.templatesError!, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
                    ),
                    TextButton(onPressed: _store.loadTemplates, child: const Text('Retry')),
                  ]),
                ),
              for (final kind in kCelebrationKinds)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(kind, settings.of(kind))),
            ],
          ),
        );
      },
    );
  }

  Widget _card(String kind, AutomationSetting s) {
    final isBirthday = kind == 'birthday';
    final saving = _saving.contains(kind);
    final editable = s.enabled && !saving;
    final templates = _store.templatesOf(kind);
    final fallback = _store.defaultOf(kind);
    // A stored id can point at a deleted template; only honour it while it still resolves.
    String? selectedId;
    for (final t in templates) {
      if (t.id == s.templateId) selectedId = t.id;
    }
    selectedId ??= fallback?.id;

    return CelebrationCard(
      highlighted: s.enabled,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(isBirthday ? Icons.cake_outlined : Icons.celebration_outlined, size: 20, color: AppColors.primaryText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isBirthday ? 'Birthdays' : 'Work Anniversaries',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      isBirthday
                          ? "Goes out on the employee's birthday, every year, without anyone remembering."
                          : 'Goes out on the joining-date anniversary, with completed years filled in.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ]),
                ),
                if (saving)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  Switch(
                    value: s.enabled,
                    activeTrackColor: AppColors.surfaceDark,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => _update(kind, {'enabled': v}),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Opacity(
            opacity: s.enabled ? 1 : 0.5,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('Template'),
                  if (templates.isEmpty)
                    Text(
                      _store.templates == null ? 'Templates are not loaded.' : 'No templates for this kind yet.',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('$kind-$selectedId'),
                      initialValue: selectedId,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        for (final t in templates)
                          DropdownMenuItem(
                            value: t.id,
                            child: Text('${t.name}${t.isDefault ? ' (default)' : ''}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: editable
                          ? (v) {
                              if (v != null && v != selectedId) _update(kind, {'templateId': v});
                            }
                          : null,
                    ),
                  const SizedBox(height: 14),
                  const _Label('Send At'),
                  InkWell(
                    onTap: editable ? () => _pickTime(kind, s) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.schedule_rounded, size: 20, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(s.sendTime, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: AppColors.textPrimary)),
                        const Spacer(),
                        const Icon(Icons.edit_outlined, size: 16, color: AppColors.textCaption),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.surfaceDark,
                    value: s.notifyTeam,
                    onChanged: editable ? (v) => _update(kind, {'notifyTeam': v ?? false}) : null,
                    title: const Text('Also announce to the team',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                    subtitle: const Text(
                      'Posts the celebration to the company feed as well as messaging the employee directly.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );
}
