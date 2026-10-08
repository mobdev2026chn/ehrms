// Template library grouped by kind (web: TemplatesPanel). Create / edit open
// CelebrationTemplateEditorScreen; duplicate, set default and delete call the backend directly.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_celebration_service.dart';
import '../../../widgets/app_tab_loader.dart';
import 'celebration_shared.dart';
import 'celebration_template_editor_screen.dart';

class CelebrationTemplatesTab extends StatefulWidget {
  const CelebrationTemplatesTab({super.key, required this.store});
  final CelebrationStore store;

  @override
  State<CelebrationTemplatesTab> createState() => _CelebrationTemplatesTabState();
}

class _CelebrationTemplatesTabState extends State<CelebrationTemplatesTab> {
  /// Id of the template an action is running on, so its buttons can be disabled.
  String? _busyId;

  CelebrationStore get _store => widget.store;

  Future<void> _afterChange(String message, {bool settingsToo = false}) async {
    if (!mounted) return;
    showCelebrationSnack(context, message);
    await Future.wait([
      _store.loadTemplates(),
      _store.loadSummary(),
      if (settingsToo) _store.loadSettings(),
    ]);
  }

  Future<void> _run(CelebrationTemplate t, Future<String> Function() action, {bool settingsToo = false}) async {
    setState(() => _busyId = t.id);
    try {
      final msg = await action();
      await _afterChange(msg, settingsToo: settingsToo);
    } catch (e) {
      if (mounted) showCelebrationError(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openEditor({CelebrationTemplate? template, required String kind}) async {
    final msg = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => CelebrationTemplateEditorScreen(
        api: _store.api,
        template: template,
        kind: kind,
        isOnlyOfKind: template != null && _store.templatesOf(template.kind).length == 1,
      ),
    ));
    if (msg != null) await _afterChange(msg);
  }

  Future<void> _delete(CelebrationTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${t.name}"?'),
        content: const Text('This template will be removed and can no longer be sent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Deleting can repoint the automation at the default, so settings are refreshed too.
    await _run(t, () => _store.api.deleteTemplate(t.id), settingsToo: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final templates = _store.templates;
        if (templates == null && _store.templatesError != null) {
          return CelebrationErrorView(message: _store.templatesError!, onRetry: _store.loadTemplates);
        }
        if (templates == null) return const Center(child: AppTabLoader());

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => Future.wait([_store.loadTemplates(), _store.loadSummary()]),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (_store.templatesError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_store.templatesError!, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
                ),
              for (final kind in kCelebrationKinds) ..._group(kind, _store.templatesOf(kind)),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _group(String kind, List<CelebrationTemplate> list) {
    final isBirthday = kind == 'birthday';
    return [
      Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(isBirthday ? Icons.cake_outlined : Icons.celebration_outlined, color: AppColors.primaryText, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isBirthday ? 'Birthday Templates' : 'Anniversary Templates',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary)),
              Text(
                isBirthday
                    ? 'Sent on the day itself, to the employee and optionally the wider team.'
                    : 'Sent on the joining-date anniversary, with the completed years filled in.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
            ]),
          ),
          TextButton.icon(
            onPressed: () => _openEditor(kind: kind),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        CelebrationEmptyView(
          icon: Icons.dashboard_customize_outlined,
          title: 'No ${isBirthday ? 'birthday' : 'anniversary'} templates',
          subtitle: 'Create one to start sending wishes.',
        )
      else
        for (final t in list)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(t)),
      const SizedBox(height: 24),
    ];
  }

  Widget _card(CelebrationTemplate t) {
    final busy = _busyId == t.id;
    final undeletableReason = t.isDefault
        ? 'The default cannot be deleted - make another template the default first'
        : t.isSystem
            ? 'A built-in template cannot be deleted, but you can edit it'
            : null;

    return CelebrationCard(
      highlighted: t.isDefault,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
            ),
            if (t.isDefault) _badge(Icons.star_rounded, 'Default', AppColors.surfaceDark, AppColors.primary),
            if (t.isSystem) ...[
              const SizedBox(width: 6),
              _badge(Icons.lock_outline, 'Built-in', AppColors.inputFill, AppColors.textSecondary),
            ],
          ]),
          if (t.subject.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(t.subject, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppColors.textPrimary)),
          ],
          const SizedBox(height: 4),
          Text(t.message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45)),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => _openEditor(template: t, kind: t.kind),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => _run(t, () => _store.api.duplicateTemplate(t.id)),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Duplicate'),
              ),
              if (!t.isDefault)
                TextButton.icon(
                  onPressed: busy ? null : () => _run(t, () => _store.api.setDefaultTemplate(t.id)),
                  icon: const Icon(Icons.star_outline, size: 16),
                  label: const Text('Set default'),
                ),
              if (undeletableReason == null)
                TextButton.icon(
                  onPressed: busy ? null : () => _delete(t),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete'),
                )
              else
                Tooltip(
                  message: undeletableReason,
                  triggerMode: TooltipTriggerMode.tap,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textCaption),
                  ),
                ),
              if (busy) const Padding(padding: EdgeInsets.only(left: 6), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );
}
