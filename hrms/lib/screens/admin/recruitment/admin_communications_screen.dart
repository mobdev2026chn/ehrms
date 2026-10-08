// lib/screens/admin/recruitment/admin_communications_screen.dart
// Recruitment Communications: channel switches (Email / WhatsApp / SMS) and the message
// history - every candidate with a summary, then one candidate's messages.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'rec_widgets.dart';

class AdminCommunicationsScreen extends StatelessWidget {
  const AdminCommunicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kRecBg,
        appBar: recAppBar(
          context,
          'Communications',
          bottom: const TabBar(
            tabs: [Tab(text: 'Channels'), Tab(text: 'History')],
          ),
        ),
        body: const TabBarView(children: [_ChannelsTab(), _HistoryTab()]),
      ),
    );
  }
}

class _ChannelsTab extends StatefulWidget {
  const _ChannelsTab();
  @override
  State<_ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends State<_ChannelsTab> with AutomaticKeepAliveClientMixin {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  bool _loading = true;
  String? _error;
  List<RecCommChannel> _channels = [];
  String? _saving;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c = await _service.getCommunicationChannels();
      if (!mounted) return;
      setState(() {
        _channels = c;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggle(RecCommChannel ch, bool enabled) async {
    if (!enabled) {
      final ok = await recConfirm(context,
          title: 'Switch ${ch.label} off?',
          message: 'No recruitment messages are sent by ${ch.label} while it is off.'
              '${ch.channel == 'email' ? ' Offer letters cannot be sent either.' : ''}',
          confirmLabel: 'Switch off',
          destructive: true);
      if (!ok) return;
    }
    setState(() => _saving = ch.channel);
    try {
      final updated = await _service.updateCommunicationChannel(ch.channel, enabled);
      if (!mounted) return;
      setState(() {
        if (updated.isNotEmpty) _channels = updated;
      });
      recShowSuccess(context, '${ch.label} switched ${enabled ? 'on' : 'off'}');
      if (updated.isEmpty) _load();
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  IconData _icon(String ch) => ch == 'email' ? Icons.email_outlined : (ch == 'whatsapp' ? Icons.chat_outlined : Icons.sms_outlined);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RecAsyncBody(
      loading: _loading,
      error: _error,
      isEmpty: _channels.isEmpty,
      emptyText: 'No channels available',
      onRetry: _load,
      builder: () => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('Choose how candidates and evaluators are notified about recruitment events.',
                style: TextStyle(fontSize: 12.5, color: kRecMuted)),
          ),
          ..._channels.map((ch) => RecCard(
                child: Row(children: [
                  RecIconTile(_icon(ch.channel), size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ch.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                        const SizedBox(height: 2),
                        Text(ch.description, style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                        if (!ch.available)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text('Not connected for recruitment yet',
                                style: TextStyle(fontSize: 12, color: AppColors.brandDark, fontWeight: FontWeight.w500)),
                          ),
                      ],
                    ),
                  ),
                  _saving == ch.channel
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Switch(
                          value: ch.enabled,
                          onChanged: !ch.available || _saving != null ? null : (v) => _toggle(ch, v),
                        ),
                ]),
              )),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> with AutomaticKeepAliveClientMixin {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<RecCommCandidate> _rows = [];
  int _total = 0;
  int _page = 1;
  bool _messagedOnly = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => more ? _loadingMore = true : _loading = true);
    try {
      final page = more ? _page + 1 : 1;
      final res = await _service.getCommunicationCandidates(
          search: _searchCtrl.text.trim(), messaged: _messagedOnly, page: page, limit: 25);
      if (!mounted) return;
      setState(() {
        _rows = more ? [..._rows, ...res.rows] : res.rows;
        _total = res.total;
        _page = page;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (more) {
        recShowError(context, e);
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: RecSearchField(
            controller: _searchCtrl,
            hint: 'Search candidate name or email',
            onChanged: (_) {},
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            FilterChip(
              label: const Text('Messaged only', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              selected: _messagedOnly,
              selectedColor: AppColors.brandLight,
              checkmarkColor: AppColors.brandDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              onSelected: (v) {
                setState(() => _messagedOnly = v);
                _load();
              },
            ),
            const Spacer(),
            TextButton.icon(onPressed: () => _load(), icon: const Icon(Icons.search_rounded, size: 18), label: const Text('Search')),
          ]),
        ),
        Expanded(
          child: RecAsyncBody(
            loading: _loading,
            error: _error,
            isEmpty: _rows.isEmpty,
            emptyText: 'No messages yet',
            emptyIcon: Icons.forum_outlined,
            onRetry: _load,
            builder: () => RefreshIndicator(
              onRefresh: () => _load(),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  ..._rows.map((c) => RecCard(
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => AdminCandidateCommunicationScreen(candidate: c))),
                        child: Row(children: [
                          RecAvatar(c.name),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                                const SizedBox(height: 2),
                                Text('${c.position} • ${c.status}', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                                if (c.lastAt.isNotEmpty)
                                  Text('${c.lastEventLabel.isNotEmpty ? c.lastEventLabel : c.lastSubject} • ${recFormatDateTime(c.lastAt)}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kRecMuted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('${c.total}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kRecInk)),
                            const SizedBox(height: 4),
                            if (c.failed > 0) RecBadge('${c.failed} failed', colorKey: 'failed'),
                          ]),
                        ]),
                      )),
                  if (_rows.length < _total)
                    Center(
                      child: _loadingMore
                          ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                          : TextButton(onPressed: () => _load(more: true), child: Text('Load more (${_total - _rows.length})')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AdminCandidateCommunicationScreen extends StatefulWidget {
  final RecCommCandidate candidate;
  const AdminCandidateCommunicationScreen({super.key, required this.candidate});

  @override
  State<AdminCandidateCommunicationScreen> createState() => _AdminCandidateCommunicationScreenState();
}

class _AdminCandidateCommunicationScreenState extends State<AdminCandidateCommunicationScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<RecCommLog> _logs = [];
  int _total = 0;
  int _page = 1;
  String _status = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => more ? _loadingMore = true : _loading = true);
    try {
      final page = more ? _page + 1 : 1;
      final res = await _service.getCommunicationHistory(
          candidateId: widget.candidate.id, status: _status == 'All' ? null : _status, page: page, limit: 25);
      if (!mounted) return;
      setState(() {
        _logs = more ? [..._logs, ...res.rows] : res.rows;
        _total = res.total;
        _page = page;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (more) {
        recShowError(context, e);
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, c.name, onRefresh: () => _load()),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: RecFilterChips(
              options: const ['All', 'Delivered', 'Failed', 'Skipped'],
              selected: _status,
              onSelected: (s) {
                setState(() => _status = s);
                _load();
              },
            ),
          ),
          Expanded(
            child: RecAsyncBody(
              loading: _loading,
              error: _error,
              isEmpty: _logs.isEmpty,
              emptyText: 'No messages',
              emptyIcon: Icons.forum_outlined,
              onRetry: _load,
              builder: () => ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  ..._logs.map((l) => RecCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(l.channel == 'email' ? Icons.email_outlined : (l.channel == 'whatsapp' ? Icons.chat_outlined : Icons.sms_outlined),
                                  size: 18, color: kRecMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(l.eventLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
                              ),
                              const SizedBox(width: 8),
                              RecBadge(l.status),
                            ]),
                            if (l.subject.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(l.subject, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kRecInk)),
                              const SizedBox(height: 2),
                            ],
                            if (l.preview.isNotEmpty)
                              Text(l.preview, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                            const SizedBox(height: 4),
                            Text(
                              'To ${l.recipientName.isNotEmpty ? '${l.recipientName} ' : ''}<${l.recipient}> (${l.recipientType}) • ${recFormatDateTime(l.sentAt)}',
                              style: const TextStyle(fontSize: 12.5, color: kRecMuted),
                            ),
                            if (l.reason.isNotEmpty) Text(l.reason, style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                            if (l.attachments.isNotEmpty)
                              Text('Attachments: ${l.attachments.join(', ')}', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                            if (l.error.isNotEmpty) Text(l.error, style: const TextStyle(fontSize: 12, color: AppColors.error)),
                          ],
                        ),
                      )),
                  if (_logs.length < _total)
                    Center(
                      child: _loadingMore
                          ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                          : TextButton(onPressed: () => _load(more: true), child: Text('Load more (${_total - _logs.length})')),
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
