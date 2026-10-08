// Manual send (web: SendWishesModal). POST /admin/celebration/send with
// { kind, templateId, staffIds }. Resolves to the server's message on success, null if closed.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_celebration_service.dart';
import 'celebration_shared.dart';

Future<String?> showSendWishesSheet(
  BuildContext context, {
  required CelebrationStore store,
  required String kind,
  required List<CelebrationEntry> entries,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _SendWishesSheet(store: store, kind: kind, entries: entries),
  );
}

class _SendWishesSheet extends StatefulWidget {
  const _SendWishesSheet({required this.store, required this.kind, required this.entries});
  final CelebrationStore store;
  final String kind;
  final List<CelebrationEntry> entries;

  @override
  State<_SendWishesSheet> createState() => _SendWishesSheetState();
}

class _SendWishesSheetState extends State<_SendWishesSheet> {
  late final List<CelebrationTemplate> _templates = widget.store.templatesOf(widget.kind);
  String? _templateId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // The default is what the automation would use, so a manual send matches it.
    final preferred = widget.store.defaultOf(widget.kind) ?? (_templates.isNotEmpty ? _templates.first : null);
    _templateId = preferred?.id;
  }

  CelebrationTemplate? get _selected {
    for (final t in _templates) {
      if (t.id == _templateId) return t;
    }
    return null;
  }

  Future<void> _send() async {
    final tpl = _selected;
    if (tpl == null) return;
    setState(() => _sending = true);
    try {
      final msg = await widget.store.api.sendWishes(
        kind: widget.kind,
        templateId: tpl.id,
        staffIds: widget.entries.map((e) => e.staffId).toList(),
      );
      if (mounted) Navigator.of(context).pop(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showCelebrationError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final preview = entries.first;
    final kindText = widget.kind == 'birthday' ? 'birthday' : 'work anniversary';
    final tpl = _selected;
    final company = widget.store.summary?.companyName ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.send_rounded, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Send Wishes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      entries.length == 1 ? '${preview.staffName} - $kindText' : '${entries.length} people - $kindText',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ]),
                ),
                IconButton(
                    tooltip: 'Close',
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  const _Label('Recipients'),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in entries)
                          Chip(
                            avatar: const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textSecondary),
                            label: Text(e.staffName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                            backgroundColor: AppColors.surface,
                            visualDensity: VisualDensity.compact,
                            side: const BorderSide(color: Color(0xFFE2E5EA)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _Label('Template'),
                  if (_templates.isEmpty)
                    const Text('No templates for this celebration yet. Create one in the Templates tab.',
                        style: TextStyle(color: AppColors.error, fontSize: 13))
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _templateId,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        for (final t in _templates)
                          DropdownMenuItem(
                            value: t.id,
                            child: Text('${t.name}${t.isDefault ? ' (default)' : ''}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _sending ? null : (v) => setState(() => _templateId = v),
                    ),
                  if (tpl != null) ...[
                    const SizedBox(height: 16),
                    const _Label('Preview'),
                    if (entries.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Showing ${preview.staffName} - each person gets their own details',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ),
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: Text(
                            renderForEntry(tpl.subject, preview, company).isEmpty
                                ? 'No subject'
                                : renderForEntry(tpl.subject, preview, company),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                          child: Text(renderForEntry(tpl.message, preview, company),
                              style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.white)),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sending ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.surfaceDark, foregroundColor: Colors.white),
                      onPressed: tpl == null || _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(_sending
                          ? 'Sending...'
                          : entries.length == 1
                              ? 'Send Wish'
                              : 'Send to ${entries.length}'),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
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
