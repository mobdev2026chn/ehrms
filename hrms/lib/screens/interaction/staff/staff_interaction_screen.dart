// Staff Interaction hub: Chats · Polls & Surveys, on HRMSbackend
// (/api/staff/interaction/chat, /api/staff/interaction/polls). Announcements are their
// own module (screens/announcements/announcements_screen.dart).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/staff_interaction_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/bottom_navigation_bar.dart';
import 'staff_chat_thread_screen.dart';
import 'staff_interaction_widgets.dart';
import 'staff_new_chat_screen.dart';

class StaffInteractionScreen extends StatefulWidget {
  const StaffInteractionScreen({super.key, this.initialTab = 0});

  /// 0 = Chats, 1 = Polls & Surveys.
  final int initialTab;

  @override
  State<StaffInteractionScreen> createState() => _StaffInteractionScreenState();
}

class _StaffInteractionScreenState extends State<StaffInteractionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 1),
  );

  @override
  void initState() {
    super.initState();
    StaffInteractionService.instance.connect();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Interaction'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: StaffInteractionService.instance.connected,
            builder: (_, live, _) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: live ? 'Live' : 'Updating periodically',
                child: Icon(Icons.circle, size: 9, color: live ? AppColors.success : AppColors.textHint),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: kInteractionInk,
          unselectedLabelColor: kInteractionMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Polls & Surveys'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_ChatsTab(), _PollsTab()],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }
}

// ── Chats ─────────────────────────────────────────────────────────────────────

class _ChatsTab extends StatefulWidget {
  const _ChatsTab();

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> with AutomaticKeepAliveClientMixin {
  final _svc = StaffInteractionService.instance;
  List<ChatConversation> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _filter = 'all'; // all | unread | direct | group | broadcast
  final List<StreamSubscription> _subs = [];
  Timer? _poll;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _subs.add(_svc.onMessage.listen((_) => _load(silent: true)));
    _subs.add(_svc.onConversationUpdated.listen((_) => _load(silent: true)));
    _subs.add(_svc.onPresence.listen((_) {
      if (mounted) setState(() {});
    }));
    // Fallback while the socket isn't connected.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_svc.connected.value) _load(silent: true);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _all.isEmpty;
        _error = null;
      });
    }
    final r = await _svc.getConversations();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _all = r.data!;
        _error = null;
      } else if (!silent || _all.isEmpty) {
        _error = r.error;
      }
    });
  }

  List<ChatConversation> get _visible {
    final q = _query.trim().toLowerCase();
    return _all.where((c) {
      if (_filter == 'unread' && c.unreadCount == 0) return false;
      if (_filter == 'direct' && c.type != 'direct') return false;
      if (_filter == 'group' && c.type != 'group') return false;
      if (_filter == 'broadcast' && c.type != 'broadcast') return false;
      if (q.isEmpty) return true;
      return c.title.toLowerCase().contains(q) || c.lastMessage.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _open(ChatConversation c) async {
    setState(() => c.unreadCount = 0);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffChatThreadScreen(
        conversationId: c.id,
        title: c.title,
        avatar: c.avatar,
        type: c.type,
        subtitle: c.subtitle,
        participantId: c.participantId,
      ),
    ));
    _load(silent: true);
  }

  Future<void> _newChat() async {
    final opened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StaffNewChatScreen()),
    );
    if (opened == true) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final unreadTotal = _all.fold<int>(0, (a, c) => a + c.unreadCount);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        heroTag: 'staff-new-chat',
        onPressed: _newChat,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tooltip: 'New chat',
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: kInteractionLine)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search chats',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('all', 'All'),
                      _chip('unread', unreadTotal > 0 ? 'Unread ($unreadTotal)' : 'Unread'),
                      _chip('direct', 'Direct'),
                      _chip('group', 'Groups'),
                      _chip('broadcast', 'Broadcasts'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _chip(String key, String label) {
    final sel = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => setState(() => _filter = key),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
          color: sel ? AppColors.onPrimary : kInteractionMuted,
        ),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.background,
        side: BorderSide(color: sel ? Colors.transparent : const Color(0xFFE2E5EA)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    if (_error != null) {
      return InteractionEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load chats',
        message: _error!,
        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    final list = _visible;
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 360,
              child: InteractionEmptyState(
                icon: Icons.forum_outlined,
                title: _all.isEmpty ? 'No conversations yet' : 'No chats match',
                message: _all.isEmpty ? 'Tap the chat button to message a colleague or your admin.' : '',
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _tile(list[i]),
      ),
    );
  }

  Widget _tile(ChatConversation c) {
    final unread = c.unreadCount > 0;
    final icon = c.isBroadcast ? Icons.campaign_rounded : (c.isGroup ? Icons.groups_rounded : null);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kInteractionLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              InteractionAvatar(
                name: c.title,
                url: c.avatar,
                size: 48,
                icon: c.avatar.isEmpty ? icon : null,
                online: c.type == 'direct' && _svc.isOnline(c.participantId),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                              color: kInteractionInk,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chatListTime(c.lastMessageAt),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            color: unread ? AppColors.primaryText : kInteractionMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (c.isBroadcast)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.campaign_outlined, size: 14, color: kInteractionMuted),
                          ),
                        Expanded(
                          child: Text(
                            c.lastMessage.isNotEmpty
                                ? c.lastMessage
                                : (c.subtitle.isNotEmpty ? c.subtitle : 'Say hello 👋'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: unread ? kInteractionInk : kInteractionMuted,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: AppColors.onPrimary, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Polls & Surveys ───────────────────────────────────────────────────────────

class _PollsTab extends StatefulWidget {
  const _PollsTab();

  @override
  State<_PollsTab> createState() => _PollsTabState();
}

class _PollsTabState extends State<_PollsTab> with AutomaticKeepAliveClientMixin {
  final _svc = StaffInteractionService.instance;
  List<StaffPoll> _polls = [];
  bool _loading = true;
  String? _error;
  String _filter = 'active'; // active | voted | closed

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _polls.isEmpty;
      _error = null;
    });
    final r = await _svc.getPolls();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _polls = r.data!;
      } else {
        _error = r.error;
      }
    });
  }

  List<StaffPoll> get _visible {
    return _polls.where((p) {
      switch (_filter) {
        case 'voted':
          return p.hasVoted;
        case 'closed':
          return p.isClosed;
        default:
          return !p.isClosed;
      }
    }).toList();
  }

  void _replace(StaffPoll updated) {
    setState(() {
      _polls = [for (final p in _polls) p.id == updated.id ? updated : p];
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pending = _polls.where((p) => !p.isClosed && !p.hasVoted).length;
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: kInteractionLine)),
          ),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'active', label: Text(pending > 0 ? 'Active ($pending)' : 'Active')),
              const ButtonSegment(value: 'voted', label: Text('Voted')),
              const ButtonSegment(value: 'closed', label: Text('Closed')),
            ],
            selected: {_filter},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _filter = s.first),
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              visualDensity: VisualDensity.compact,
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.white,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? AppColors.onPrimary : kInteractionMuted,
              ),
              side: WidgetStateProperty.all(const BorderSide(color: Color(0xFFE2E5EA))),
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    if (_error != null) {
      return InteractionEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load polls',
        message: _error!,
        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    final list = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 360,
                  child: InteractionEmptyState(
                    icon: Icons.poll_outlined,
                    title: _filter == 'active'
                        ? 'No active polls'
                        : (_filter == 'voted' ? 'You haven\'t voted yet' : 'No closed polls'),
                    message: _filter == 'active' ? 'New polls and surveys from your admin will show here.' : '',
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: list.length,
              itemBuilder: (_, i) => _PollCard(
                key: ValueKey(list[i].id),
                poll: list[i],
                onUpdated: _replace,
              ),
            ),
    );
  }
}

class _PollCard extends StatefulWidget {
  const _PollCard({super.key, required this.poll, required this.onUpdated});
  final StaffPoll poll;
  final ValueChanged<StaffPoll> onUpdated;

  @override
  State<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<_PollCard> {
  final Set<String> _selected = {};
  bool _submitting = false;

  StaffPoll get p => widget.poll;

  Future<void> _submit() async {
    if (_selected.isEmpty) return;
    setState(() => _submitting = true);
    final r = await StaffInteractionService.instance.vote(p.id, _selected.toList());
    if (!mounted) return;
    setState(() => _submitting = false);
    if (r.ok) {
      widget.onUpdated(r.data!);
      SnackBarUtils.showSnackBar(context, 'Your vote has been recorded.');
    } else {
      SnackBarUtils.showSnackBar(context, r.error!, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showResults = p.hasVoted || p.isClosed;
    final maxVotes = p.options.fold<int>(0, (a, o) => o.votes > a ? o.votes : a);
    final String statusLabel;
    final Color statusColor;
    if (p.isClosed) {
      statusLabel = 'CLOSED';
      statusColor = kInteractionMuted;
    } else if (p.hasVoted) {
      statusLabel = 'VOTED';
      statusColor = AppColors.success;
    } else {
      statusLabel = 'ACTIVE';
      statusColor = AppColors.primaryText;
    }

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      border: Border.all(color: kInteractionLine),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor, letterSpacing: 0.4),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                p.multiple ? 'Multiple choice' : 'Single choice',
                style: const TextStyle(fontSize: 12, color: kInteractionMuted, fontWeight: FontWeight.w500),
              ),
              if (p.anonymous) ...[
                const SizedBox(width: 8),
                const Icon(Icons.visibility_off_outlined, size: 14, color: kInteractionMuted),
                const SizedBox(width: 4),
                const Text('Anonymous', style: TextStyle(fontSize: 12, color: kInteractionMuted)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            p.question,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kInteractionInk, height: 1.35),
          ),
          if (p.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(p.description, style: const TextStyle(fontSize: 13, color: kInteractionMuted, height: 1.4)),
          ],
          const SizedBox(height: 12),
          for (final o in p.options)
            showResults
                ? _resultRow(o, maxVotes)
                : _choiceRow(o),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.how_to_vote_outlined, size: 16, color: AppColors.textCaption),
              const SizedBox(width: 4),
              Text(
                '${p.totalVotes} vote${p.totalVotes == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: kInteractionMuted, fontWeight: FontWeight.w500),
              ),
              if (p.endDate != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.event_outlined, size: 16, color: AppColors.textCaption),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                  '${p.isClosed ? 'Ended' : 'Ends'} ${DateFormat('d MMM yyyy').format(p.endDate!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: kInteractionMuted, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
              const Spacer(),
              if (!showResults)
                FilledButton(
                  onPressed: _selected.isEmpty || _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: _submitting
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : const Text('Vote'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choiceRow(PollOption o) {
    final sel = _selected.contains(o.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          if (p.multiple) {
            sel ? _selected.remove(o.id) : _selected.add(o.id);
          } else {
            _selected
              ..clear()
              ..add(o.id);
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary.withValues(alpha: 0.08) : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? AppColors.primary : const Color(0xFFE2E5EA), width: sel ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(
                p.multiple
                    ? (sel ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                    : (sel ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                size: 20,
                color: sel ? AppColors.primaryText : AppColors.textCaption,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  o.text,
                  style: TextStyle(fontSize: 14, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: kInteractionInk),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultRow(PollOption o, int maxVotes) {
    final total = p.totalVotes == 0 ? 1 : p.totalVotes;
    final share = o.votes / total;
    final mine = p.myOptionIds.contains(o.id);
    final leading = o.votes > 0 && o.votes == maxVotes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: AppColors.background),
            ),
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v.clamp(0.0, 1.0),
                  child: Container(
                    color: (leading ? AppColors.primary : const Color(0xFFCBD5E1)).withValues(alpha: 0.28),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      o.text,
                      style: TextStyle(fontSize: 14, fontWeight: leading ? FontWeight.w700 : FontWeight.w500, color: kInteractionInk),
                    ),
                  ),
                  if (mine)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                    ),
                  Text(
                    '${(share * 100).round()}%',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInteractionInk),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
