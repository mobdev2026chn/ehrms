// Admin broadcast channels: list (GET /admin/interaction/chat/broadcasts), create with an
// audience (POST .../chat/broadcasts, targetType 'all' | 'specific' with staff from
// GET .../chat/staff) and details (recipients + notices with read counts), like the web.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_interaction_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'interaction_widgets.dart';

class AdminBroadcastsTab extends StatefulWidget {
  const AdminBroadcastsTab({super.key});

  @override
  State<AdminBroadcastsTab> createState() => _AdminBroadcastsTabState();
}

class _AdminBroadcastsTabState extends State<AdminBroadcastsTab> {
  List<ChatBroadcast>? _items;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AdminInteractionService().broadcasts();
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
    final created = await Navigator.of(context)
        .push<ChatBroadcast>(MaterialPageRoute(builder: (_) => const AdminCreateBroadcastScreen()));
    if (created != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = (_items ?? const <ChatBroadcast>[])
        .where((b) => q.isEmpty || b.title.toLowerCase().contains(q) || b.description.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-broadcasts-fab',
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _create,
        icon: const Icon(Icons.campaign_outlined),
        label: Text('New Broadcast', style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: interactionInput('Search broadcasts...', prefixIcon: const Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) => setState(() => _q = v),
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
                                icon: Icons.campaign_outlined,
                                title: _items!.isEmpty ? 'No broadcasts yet' : 'No broadcasts match your search',
                                subtitle: _items!.isEmpty ? 'Create a broadcast channel to send official notices.' : null,
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (_, i) => _BroadcastCard(
                                  broadcast: items[i],
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => AdminBroadcastDetailsScreen(broadcast: items[i]))),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _BroadcastCard extends StatelessWidget {
  const _BroadcastCard({required this.broadcast, required this.onTap});
  final ChatBroadcast broadcast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = broadcast;
    return InteractionCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined, color: AppColors.primaryText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              InteractionChip.status(b.status),
            ],
          ),
          if (b.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(b.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (b.targetLabel.isNotEmpty) InteractionChip(b.targetLabel, fg: AppColors.info, bg: AppColors.infoBg),
              InteractionChip('${b.recipientsCount} recipients'),
              InteractionChip('${b.messages.length} notices'),
            ],
          ),
          const SizedBox(height: 6),
          Text('Last sent ${interactionDate(b.lastBroadcastDate ?? b.createdAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Create ──────────────────────────────────────────────────────────────

class AdminCreateBroadcastScreen extends StatefulWidget {
  const AdminCreateBroadcastScreen({super.key});

  @override
  State<AdminCreateBroadcastScreen> createState() => _AdminCreateBroadcastScreenState();
}

class _AdminCreateBroadcastScreenState extends State<AdminCreateBroadcastScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _notice = TextEditingController();
  String _targetType = 'all';
  List<InteractionStaff>? _staff;
  String? _staffError;
  Set<String> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _notice.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _staffError = null);
    try {
      final list = await AdminInteractionService().chatStaff();
      if (mounted) setState(() => _staff = list);
    } catch (e) {
      if (mounted) setState(() => _staffError = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  // Same labels the web sends (CreateBroadcastModal.getTargetLabel).
  String get _targetLabel => _targetType == 'all'
      ? (_staff == null ? 'All Company Staff' : 'All Company Staff (${_staff!.length})')
      : '${_selected.length} Selected Staff Members';

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Channel name is required')));
      return;
    }
    if (_targetType == 'specific' && _selected.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select at least 1 staff member')));
      return;
    }
    setState(() => _saving = true);
    try {
      final desc = _desc.text.trim();
      final b = await AdminInteractionService().createBroadcast(
        title: title,
        description: desc.isEmpty ? 'Official Broadcast Announcement Channel' : desc,
        targetType: _targetType,
        targetLabel: _targetLabel,
        recipientIds: _selected.toList(),
        initialNoticeContent: _notice.text.trim(),
      );
      if (!mounted) return;
      showInteractionSuccess(context, 'Broadcast channel "${b.title}" created');
      Navigator.of(context).pop(b);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showInteractionError(context, e);
    }
  }

  Widget _audienceOption(String value, IconData icon, String title, String subtitle) {
    final sel = _targetType == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _targetType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary.withValues(alpha: 0.10) : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sel ? AppColors.primary : const Color(0xFFE2E5EA), width: sel ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 20, color: AppColors.primaryText),
                const Spacer(),
                if (sel) Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primaryText),
              ]),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: interactionAppBar('New Broadcast Channel'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const InteractionSectionLabel('Channel name *'),
          TextField(controller: _title, decoration: interactionInput('e.g. Q3 Company Announcements')),
          const InteractionSectionLabel('Description (optional)'),
          TextField(controller: _desc, decoration: interactionInput('Brief summary of what this channel is used for')),
          const InteractionSectionLabel('Target audience'),
          Row(children: [
            _audienceOption('all', Icons.groups_outlined, 'All Employees', 'Broadcast to all active staff'),
            const SizedBox(width: 10),
            _audienceOption('specific', Icons.send_outlined, 'Specific Staff', 'Target selected staff'),
          ]),
          if (_targetType == 'specific') ...[
            InteractionSectionLabel('Select staff members (${_selected.length})'),
            if (_staffError != null)
              Column(children: [
                Text(_staffError!, textAlign: TextAlign.center),
                TextButton(onPressed: _loadStaff, child: const Text('Retry')),
              ])
            else if (_staff == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: AppTabLoader()))
            else
              StaffMultiSelect(
                staff: _staff!,
                selected: _selected,
                onChanged: (s) => setState(() => _selected = s),
                maxHeight: 260,
              ),
          ] else if (_staffError != null) ...[
            const SizedBox(height: 6),
            Text('Could not count staff: $_staffError',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
          const InteractionSectionLabel('Initial announcement notice (optional)'),
          TextField(
            controller: _notice,
            maxLines: 4,
            decoration: interactionInput('Write the first notice to send to the audience...'),
          ),
          const SizedBox(height: 20),
          InteractionSubmitButton(label: 'Create Broadcast', busy: _saving, onPressed: _submit),
        ],
      ),
    );
  }
}

// ── Details ─────────────────────────────────────────────────────────────

class AdminBroadcastDetailsScreen extends StatelessWidget {
  const AdminBroadcastDetailsScreen({super.key, required this.broadcast});
  final ChatBroadcast broadcast;

  @override
  Widget build(BuildContext context) {
    final b = broadcast;
    final notices = [...b.messages]..sort((x, y) =>
        (y.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(x.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: interactionAppBar(b.title),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InteractionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(b.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                  InteractionChip.status(b.status),
                ]),
                if (b.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(b.description, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (b.targetLabel.isNotEmpty) InteractionChip(b.targetLabel, fg: AppColors.info, bg: AppColors.infoBg),
                  InteractionChip('${b.recipientsCount} staff'),
                  InteractionChip('${b.messages.length} notices'),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Created by ${b.createdBy.isEmpty ? '-' : b.createdBy} · ${interactionDate(b.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const InteractionSectionLabel('Notices'),
          if (notices.isEmpty)
            const InteractionCard(
              child: Text('No notices sent yet.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          for (final n in notices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InteractionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.content, style: const TextStyle(fontSize: 13.5)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text(interactionDateTime(n.sentAt),
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const Spacer(),
                      Icon(Icons.visibility_outlined, size: 14, color: AppColors.primaryText),
                      const SizedBox(width: 4),
                      Text(
                        'Read: ${n.readCount} / ${b.recipientsCount}'
                        '${b.recipientsCount > 0 ? ' (${(n.readCount * 100 / b.recipientsCount).round()}%)' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          if (b.recipients.isNotEmpty) ...[
            InteractionSectionLabel('Target staff members (${b.recipients.length})'),
            InteractionCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final r in b.recipients)
                    ListTile(
                      dense: true,
                      leading: InteractionAvatar(name: r.name, radius: 15),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [r.department, r.branch].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
