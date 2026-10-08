// Admin chat groups: list (GET /admin/interaction/chat/groups), create
// (POST .../chat/groups with members from GET .../chat/staff) and details (members plus the
// group's read-only message history via GET .../chat/conversations[/:id/messages]).
// Sending messages goes over the chat socket on the web, so it is not offered here.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_interaction_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'interaction_widgets.dart';

class AdminGroupsTab extends StatefulWidget {
  const AdminGroupsTab({super.key});

  @override
  State<AdminGroupsTab> createState() => _AdminGroupsTabState();
}

class _AdminGroupsTabState extends State<AdminGroupsTab> {
  List<ChatGroup>? _items;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AdminInteractionService().groups();
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
        .push<ChatGroup>(MaterialPageRoute(builder: (_) => const AdminCreateGroupScreen()));
    if (created != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = (_items ?? const <ChatGroup>[])
        .where((g) => q.isEmpty || g.name.toLowerCase().contains(q) || g.description.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-groups-fab',
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _create,
        icon: const Icon(Icons.group_add_outlined),
        label: Text('New Group', style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: interactionInput('Search groups...', prefixIcon: const Icon(Icons.search_rounded, size: 20)),
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
                                icon: Icons.groups_outlined,
                                title: _items!.isEmpty ? 'No groups yet' : 'No groups match your search',
                                subtitle: _items!.isEmpty ? 'Create a group channel to chat with a team.' : null,
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (_, i) => _GroupCard(
                                  group: items[i],
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => AdminGroupDetailsScreen(group: items[i]))),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});
  final ChatGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InteractionCard(
      onTap: onTap,
      child: Row(
        children: [
          InteractionAvatar(name: group.name, url: group.avatar, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (group.description.isNotEmpty)
                  Text(group.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  '${group.membersCount} members${group.createdBy.isNotEmpty ? ' · by ${group.createdBy}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
        ],
      ),
    );
  }
}

// ── Create ──────────────────────────────────────────────────────────────

class AdminCreateGroupScreen extends StatefulWidget {
  const AdminCreateGroupScreen({super.key});

  @override
  State<AdminCreateGroupScreen> createState() => _AdminCreateGroupScreenState();
}

class _AdminCreateGroupScreenState extends State<AdminCreateGroupScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _tags = TextEditingController();
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
    _name.dispose();
    _desc.dispose();
    _tags.dispose();
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

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final tags = _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      final group = await AdminInteractionService().createGroup(
        name: name,
        description: _desc.text.trim(),
        memberIds: _selected.toList(),
        tags: tags,
      );
      if (!mounted) return;
      showInteractionSuccess(context, 'Group "${group.name}" created');
      Navigator.of(context).pop(group);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showInteractionError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: interactionAppBar('New Group'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const InteractionSectionLabel('Group name *'),
          TextField(controller: _name, decoration: interactionInput('e.g. Marketing Team')),
          const InteractionSectionLabel('Description (optional)'),
          TextField(controller: _desc, maxLines: 2, decoration: interactionInput('What is this group for?')),
          const InteractionSectionLabel('Tags (optional, comma separated)'),
          TextField(controller: _tags, decoration: interactionInput('e.g. sales, north')),
          InteractionSectionLabel('Members (${_selected.length} selected)'),
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
            ),
          const SizedBox(height: 20),
          InteractionSubmitButton(label: 'Create Group', busy: _saving, onPressed: _submit),
        ],
      ),
    );
  }
}

// ── Details ─────────────────────────────────────────────────────────────

class AdminGroupDetailsScreen extends StatefulWidget {
  const AdminGroupDetailsScreen({super.key, required this.group});
  final ChatGroup group;

  @override
  State<AdminGroupDetailsScreen> createState() => _AdminGroupDetailsScreenState();
}

class _AdminGroupDetailsScreenState extends State<AdminGroupDetailsScreen> {
  List<AdminChatMessage>? _messages;
  bool _noConversation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _error = null;
      _messages = null;
    });
    try {
      final svc = AdminInteractionService();
      final convId = await svc.conversationIdForGroup(widget.group.id);
      if (convId == null) {
        if (mounted) setState(() => _noConversation = true);
        return;
      }
      final list = await svc.conversationMessages(convId);
      if (mounted) setState(() => _messages = list);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(g.name),
          bottom: TabBar(
            tabs: [Tab(text: 'Members (${g.members.length})'), const Tab(text: 'Messages')],
          ),
        ),
        body: TabBarView(children: [_members(g), _messagesView()]),
      ),
    );
  }

  Widget _members(ChatGroup g) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InteractionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (g.description.isNotEmpty) ...[
                Text(g.description, style: const TextStyle(fontSize: 13.5)),
                const SizedBox(height: 8),
              ],
              Text('Created by ${g.createdBy.isEmpty ? '-' : g.createdBy} · ${interactionDate(g.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              if (g.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final t in g.tags) InteractionChip('#$t')]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (g.members.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No members.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
          ),
        for (final m in g.members)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InteractionCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  InteractionAvatar(name: m.name, radius: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                        if (m.department.isNotEmpty)
                          Text(m.department, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (m.role == 'Admin')
                    const InteractionChip('Admin', fg: AppColors.warning, bg: AppColors.warningBg),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _messagesView() {
    if (_error != null) {
      return RefreshIndicator(
          onRefresh: _loadMessages, child: InteractionErrorView(message: _error!, onRetry: _loadMessages));
    }
    if (_noConversation) {
      return const InteractionEmptyView(icon: Icons.forum_outlined, title: 'No conversation found for this group');
    }
    final msgs = _messages;
    if (msgs == null) return const Center(child: AppTabLoader());
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadMessages,
      child: msgs.isEmpty
          ? const InteractionEmptyView(icon: Icons.chat_bubble_outline, title: 'No messages yet')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: msgs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final m = msgs[i];
                final isAdmin = m.senderType == 'admin';
                return Align(
                  alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isAdmin ? AppColors.surfaceDark : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: isAdmin ? null : Border.all(color: const Color(0xFFECEEF1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.senderName,
                              style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: isAdmin ? AppColors.primary : AppColors.primaryText)),
                          const SizedBox(height: 4),
                          Text(m.content.isEmpty ? '(attachment)' : m.content,
                              style: TextStyle(fontSize: 14, height: 1.4, color: isAdmin ? Colors.white : AppColors.textPrimary)),
                          const SizedBox(height: 6),
                          Text(interactionDateTime(m.createdAt),
                              style: TextStyle(fontSize: 11, color: isAdmin ? Colors.white60 : AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
