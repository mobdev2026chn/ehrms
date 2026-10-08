// Admin polls & surveys: list with filters (GET /admin/interaction/polls), create
// (POST /admin/interaction/polls; targets from GET .../polls/staff, .../chat/groups and
// .../chat/broadcasts, like the web CreatePollModal) and results (per-option votes and voters;
// the server withholds voters of anonymous polls).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_interaction_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'interaction_widgets.dart';

class AdminPollsTab extends StatefulWidget {
  const AdminPollsTab({super.key});

  @override
  State<AdminPollsTab> createState() => _AdminPollsTabState();
}

class _AdminPollsTabState extends State<AdminPollsTab> {
  static const _filters = [('all', 'All'), ('active', 'Active'), ('completed', 'Completed'), ('chat', 'Sent to Chat')];
  List<AdminPoll>? _items;
  String? _error;
  String _q = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AdminInteractionService().polls();
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  Future<void> _create() async {
    final created =
        await Navigator.of(context).push<AdminPoll>(MaterialPageRoute(builder: (_) => const AdminCreatePollScreen()));
    if (created != null) _load();
  }

  bool _matches(AdminPoll p) {
    final q = _q.toLowerCase();
    final hit = q.isEmpty ||
        p.question.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q) ||
        p.targetLabel.toLowerCase().contains(q);
    if (!hit) return false;
    switch (_filter) {
      case 'active':
        return p.status == 'Active';
      case 'completed':
        return p.status == 'Completed';
      case 'chat':
        return p.sendAsChatAnnouncement;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (_items ?? const <AdminPoll>[]).where(_matches).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-polls-fab',
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _create,
        icon: const Icon(Icons.poll_outlined),
        label: Text('New Poll', style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: interactionInput('Search polls...', prefixIcon: const Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final (id, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(id == 'all' && _items != null ? '$label (${_items!.length})' : label),
                      selected: _filter == id,
                      selectedColor: AppColors.primary.withValues(alpha: 0.16),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _filter == id ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                      onSelected: (_) => setState(() => _filter = id),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? RefreshIndicator(onRefresh: _load, child: InteractionErrorView(message: _error!, onRetry: _load))
                : _items == null
                    ? const Center(child: AppTabLoader())
                    : RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _load,
                        child: items.isEmpty
                            ? InteractionEmptyView(
                                icon: Icons.poll_outlined,
                                title: _items!.isEmpty ? 'No polls yet' : 'No polls match this filter',
                                subtitle: _items!.isEmpty ? 'Create a poll or survey to gather staff feedback.' : null,
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (_, i) => _PollCard(
                                  poll: items[i],
                                  onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => AdminPollDetailsScreen(poll: items[i]))),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.poll, required this.onTap});
  final AdminPoll poll;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = poll;
    return InteractionCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            InteractionChip.status(p.status),
            InteractionChip(p.isMultiple ? 'Multiple choice' : 'Single choice'),
            if (p.isAnonymous) const InteractionChip('Anonymous', fg: AppColors.indigo, bg: AppColors.indigoBg),
            if (p.sendAsChatAnnouncement) const InteractionChip('Sent to Chat', fg: AppColors.info, bg: AppColors.infoBg),
          ]),
          const SizedBox(height: 8),
          Text(p.question, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (p.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(p.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 8),
          Text(
            '${p.targetLabel} · ${p.options.length} options · ${p.totalVotes} votes · Ends ${p.endDate}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Create ──────────────────────────────────────────────────────────────

class AdminCreatePollScreen extends StatefulWidget {
  const AdminCreatePollScreen({super.key});

  @override
  State<AdminCreatePollScreen> createState() => _AdminCreatePollScreenState();
}

class _AdminCreatePollScreenState extends State<AdminCreatePollScreen> {
  static const _maxOptions = 8;

  final _question = TextEditingController();
  final _desc = TextEditingController();
  final List<TextEditingController> _options = [TextEditingController(text: 'Yes'), TextEditingController(text: 'No')];
  String _choiceType = 'single';
  String _visibility = 'normal';
  String _sendTo = 'all';
  bool _sendAsChat = true;
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;

  // Targets, loaded on demand when their "send to" is picked.
  List<InteractionStaff>? _staff;
  List<ChatGroup>? _groups;
  List<ChatBroadcast>? _broadcasts;
  String? _targetError;
  bool _targetLoading = false;
  String? _staffId;
  String? _groupId;
  String? _broadcastId;

  @override
  void dispose() {
    _question.dispose();
    _desc.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTargets() async {
    if (_sendTo == 'all') return;
    setState(() {
      _targetLoading = true;
      _targetError = null;
    });
    try {
      final svc = AdminInteractionService();
      switch (_sendTo) {
        case 'single':
          final list = _staff ?? await svc.pollStaff();
          if (!mounted) return;
          setState(() {
            _staff = list;
            _staffId ??= list.isNotEmpty ? list.first.id : null;
          });
          break;
        case 'group':
          final list = _groups ?? await svc.groups();
          if (!mounted) return;
          setState(() {
            _groups = list;
            _groupId ??= list.isNotEmpty ? list.first.id : null;
          });
          break;
        case 'broadcast':
          final list = _broadcasts ?? await svc.broadcasts();
          if (!mounted) return;
          setState(() {
            _broadcasts = list;
            _broadcastId ??= list.isNotEmpty ? list.first.id : null;
          });
          break;
      }
    } catch (e) {
      if (mounted) setState(() => _targetError = ErrorMessageUtils.toUserFriendlyMessage(e));
    } finally {
      if (mounted) setState(() => _targetLoading = false);
    }
  }

  void _applyPreset(List<String> texts) {
    setState(() {
      for (final c in _options) {
        c.dispose();
      }
      _options
        ..clear()
        ..addAll(texts.map((t) => TextEditingController(text: t)));
    });
  }

  void _addOption() {
    if (_options.length >= _maxOptions) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Maximum 8 options allowed per poll')));
      return;
    }
    setState(() => _options.add(TextEditingController(text: 'Option ${_options.length + 1}')));
  }

  void _removeOption(int i) {
    if (_options.length <= 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('A poll must have at least 2 options')));
      return;
    }
    setState(() => _options.removeAt(i).dispose());
  }

  /// Label + id the web sends for each "send to" (CreatePollModal.getTargetDetails).
  ({String label, String? id})? _target() {
    switch (_sendTo) {
      case 'single':
        final s = _staff?.where((e) => e.id == _staffId).firstOrNull;
        return s == null ? null : (label: 'Staff: ${s.name}', id: s.id);
      case 'group':
        final g = _groups?.where((e) => e.id == _groupId).firstOrNull;
        return g == null ? null : (label: 'Group: ${g.name}', id: g.id);
      case 'broadcast':
        final b = _broadcasts?.where((e) => e.id == _broadcastId).firstOrNull;
        return b == null ? null : (label: 'Broadcast: ${b.title}', id: b.id);
      default:
        return (label: 'All Active Staff', id: null);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    void say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    final question = _question.text.trim();
    if (question.isEmpty) return say('Poll question is required');
    final opts = _options.map((c) => c.text.trim()).toList();
    if (opts.any((o) => o.isEmpty)) return say('All poll options must have text');
    final target = _target();
    if (target == null) return say('Please choose who to send this poll to');

    setState(() => _saving = true);
    try {
      final poll = await AdminInteractionService().createPoll(
        question: question,
        description: _desc.text.trim(),
        choiceType: _choiceType,
        visibility: _visibility,
        sendTo: _sendTo,
        targetLabel: target.label,
        targetId: target.id,
        endDate: _endDate,
        sendAsChatAnnouncement: _sendAsChat,
        options: opts,
      );
      if (!mounted) return;
      showInteractionSuccess(
          context, 'Poll created and ${_sendAsChat ? 'published to Chat & Polls' : 'published to Polls'}');
      Navigator.of(context).pop(poll);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showInteractionError(context, e);
    }
  }

  Widget _segmented<T>(List<(T, String)> items, T value, ValueChanged<T> onChanged) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primary,
        selectedForegroundColor: AppColors.onPrimary,
        side: const BorderSide(color: Color(0xFFE2E5EA)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      segments: [for (final (v, l) in items) ButtonSegment<T>(value: v, label: Text(l, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)))],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }

  Widget _targetPicker() {
    if (_sendTo == 'all') {
      return const Text('Every active staff member of the company.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary));
    }
    if (_targetLoading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: AppTabLoader()));
    if (_targetError != null) {
      return Column(children: [
        Text(_targetError!, textAlign: TextAlign.center),
        TextButton(onPressed: _loadTargets, child: const Text('Retry')),
      ]);
    }
    final List<(String, String)> entries;
    String? value;
    ValueChanged<String?> onChanged;
    String emptyText;
    switch (_sendTo) {
      case 'single':
        entries = [for (final s in _staff ?? const <InteractionStaff>[]) (s.id, '${s.name} (${s.department})')];
        value = _staffId;
        onChanged = (v) => setState(() => _staffId = v);
        emptyText = 'No staff found.';
        break;
      case 'group':
        entries = [for (final g in _groups ?? const <ChatGroup>[]) (g.id, '${g.name} (${g.membersCount} members)')];
        value = _groupId;
        onChanged = (v) => setState(() => _groupId = v);
        emptyText = 'No groups yet. Create a group first.';
        break;
      default:
        entries = [for (final b in _broadcasts ?? const <ChatBroadcast>[]) (b.id, b.title)];
        value = _broadcastId;
        onChanged = (v) => setState(() => _broadcastId = v);
        emptyText = 'No broadcast channels yet. Create one first.';
    }
    if (entries.isEmpty) {
      return Text(emptyText, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary));
    }
    return DropdownButtonFormField<String>(
      initialValue: entries.any((e) => e.$1 == value) ? value : null,
      isExpanded: true,
      decoration: interactionInput('Select target'),
      items: [
        for (final (id, label) in entries)
          DropdownMenuItem(value: id, child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: interactionAppBar('New Poll / Survey'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const InteractionSectionLabel('Question *'),
          TextField(controller: _question, maxLines: 2, decoration: interactionInput('e.g. Which day suits the team outing?')),
          const InteractionSectionLabel('Description / instructions (optional)'),
          TextField(controller: _desc, maxLines: 2, decoration: interactionInput('Add context for staff')),
          const InteractionSectionLabel('Choice type'),
          _segmented([('single', 'Single choice'), ('multiple', 'Multiple choice')], _choiceType,
              (v) => setState(() => _choiceType = v)),
          const InteractionSectionLabel('Visibility'),
          _segmented([('normal', 'Normal'), ('anonymous', 'Anonymous')], _visibility,
              (v) => setState(() => _visibility = v)),
          Row(children: [
            const Expanded(child: InteractionSectionLabel('Options')),
            TextButton(onPressed: () => _applyPreset(['Yes', 'No']), child: const Text('Yes/No')),
            TextButton(
                onPressed: () => _applyPreset(['Yes', 'No', 'Maybe / Neutral']), child: const Text('Yes/No/Maybe')),
          ]),
          for (var i = 0; i < _options.length; i++)
            Padding(
              key: ObjectKey(_options[i]),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: TextField(controller: _options[i], decoration: interactionInput('Option ${i + 1}'))),
                IconButton(
                  onPressed: () => _removeOption(i),
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: AppColors.textSecondary),
                ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add),
              label: Text('Add option (${_options.length}/$_maxOptions)'),
            ),
          ),
          const InteractionSectionLabel('Send to'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (v, l) in const [('all', 'All Staff'), ('single', 'Single Staff'), ('group', 'Group'), ('broadcast', 'Broadcast')])
              ChoiceChip(
                label: Text(l),
                selected: _sendTo == v,
                showCheckmark: false,
                onSelected: (_) {
                  setState(() => _sendTo = v);
                  _loadTargets();
                },
              ),
          ]),
          const SizedBox(height: 10),
          _targetPicker(),
          const InteractionSectionLabel('End date'),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: interactionInput('', prefixIcon: const Icon(Icons.event_outlined, size: 20)),
              child: Text(interactionDate(_endDate)),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Send as chat announcement', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
            subtitle: const Text('Also posts a notice to the selected chat target.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            value: _sendAsChat,
            onChanged: (v) => setState(() => _sendAsChat = v),
          ),
          const SizedBox(height: 12),
          InteractionSubmitButton(label: 'Create Poll', busy: _saving, onPressed: _submit),
        ],
      ),
    );
  }
}

// ── Details / results ───────────────────────────────────────────────────

class AdminPollDetailsScreen extends StatelessWidget {
  const AdminPollDetailsScreen({super.key, required this.poll});
  final AdminPoll poll;

  @override
  Widget build(BuildContext context) {
    final p = poll;
    final maxVotes = p.options.fold<int>(0, (m, o) => o.votes > m ? o.votes : m);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: interactionAppBar('Poll Results'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InteractionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  InteractionChip.status(p.status),
                  InteractionChip(p.isMultiple ? 'Multiple choice' : 'Single choice'),
                  if (p.isAnonymous) const InteractionChip('Anonymous', fg: AppColors.indigo, bg: AppColors.indigoBg),
                ]),
                const SizedBox(height: 10),
                Text(p.question, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p.description, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          InteractionCard(
            child: Column(children: [
              _kv('Total votes', '${p.totalVotes}'),
              _kv('Target audience', p.targetLabel.isEmpty ? '-' : p.targetLabel),
              _kv('End date', p.endDate.isEmpty ? '-' : p.endDate),
              _kv('Sent to chat', p.sendAsChatAnnouncement ? 'Yes' : 'No'),
              _kv('Created by', p.createdBy.isEmpty ? '-' : p.createdBy),
              _kv('Created on', p.createdAt.isEmpty ? '-' : p.createdAt),
            ]),
          ),
          const InteractionSectionLabel('Results'),
          if (p.options.isEmpty)
            const InteractionCard(child: Text('No options.', style: TextStyle(color: AppColors.textSecondary))),
          for (final o in p.options) _optionResult(o, p, maxVotes),
          if (p.isAnonymous)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('This is an anonymous poll: voter identities are not shown.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _optionResult(PollOption o, AdminPoll p, int maxVotes) {
    final pct = p.totalVotes > 0 ? o.votes / p.totalVotes : 0.0;
    final leading = maxVotes > 0 && o.votes == maxVotes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InteractionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(o.text,
                    style: TextStyle(fontSize: 13.5, fontWeight: leading ? FontWeight.w700 : FontWeight.w600)),
              ),
              Text('${o.votes} · ${(pct * 100).round()}%',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryText)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0).toDouble(),
                minHeight: 8,
                backgroundColor: AppColors.inputFill,
                valueColor: AlwaysStoppedAnimation(leading ? AppColors.primary : AppColors.primary.withValues(alpha: 0.45)),
              ),
            ),
            if (!p.isAnonymous && o.voters.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final v in o.voters) InteractionChip(v.name),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
