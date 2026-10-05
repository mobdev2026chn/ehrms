// Staff Announcements module — same data and rules as the web staff page
// (uat.ektahr.com/staff/announcements): HRMSbackend GET /api/staff/announcements,
// status per row (Draft / Expired / Scheduled / Published), All · Published ·
// Scheduled · Draft · Expired tabs with counts, search and sort.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/staff_interaction_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../interaction/staff/staff_announcement_detail_screen.dart';
import '../interaction/staff/staff_interaction_widgets.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

enum _Sort { newest, oldest, title }

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  static const _tabs = ['All', 'Published', 'Scheduled', 'Draft', 'Expired'];

  /// Last list, so reopening the screen shows it at once while it refreshes.
  static List<StaffAnnouncement>? _cache;

  final _svc = StaffInteractionService.instance;
  List<StaffAnnouncement> _items = _cache ?? [];
  bool _loading = _cache == null;
  String? _error;
  String _tab = 'All';
  String _search = '';
  _Sort _sort = _Sort.newest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _svc.getAnnouncements(page: 1, limit: 100);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _items = r.data!.items;
        _cache = _items;
        _error = null;
      } else {
        _error = r.error;
      }
    });
  }

  List<StaffAnnouncement> get _searched {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where((a) => [a.title, a.subject, a.audience, a.from].any((t) => t.toLowerCase().contains(q)))
        .toList();
  }

  List<StaffAnnouncement> get _visible {
    final list = _searched.where((a) => _tab == 'All' || a.status == _tab).toList();
    int byCreated(StaffAnnouncement a, StaffAnnouncement b) =>
        (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => byCreated(b, a));
      case _Sort.oldest:
        list.sort(byCreated);
      case _Sort.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: kInteractionInk,
        centerTitle: true,
        title: const Text('Announcements', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          PopupMenuButton<_Sort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.newest, child: Text('Newest first')),
              PopupMenuItem(value: _Sort.oldest, child: Text('Oldest first')),
              PopupMenuItem(value: _Sort.title, child: Text('Title A–Z')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _header(),
          Expanded(child: _body()),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _header() {
    final counts = <String, int>{'All': _searched.length};
    for (final a in _searched) {
      counts[a.status] = (counts[a.status] ?? 0) + 1;
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search announcements...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = _tabs[i];
                final selected = t == _tab;
                final n = counts[t] ?? 0;
                return ChoiceChip(
                  selected: selected,
                  onSelected: (_) => setState(() => _tab = t),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selectedColor: kInteractionAccent,
                  backgroundColor: const Color(0xFFF1F5F9),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  label: Text(
                    n > 0 ? '$t  $n' : t,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : kInteractionInk,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    if (_error != null && _items.isEmpty) {
      return InteractionEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load announcements',
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
              children: const [
                SizedBox(
                  height: 360,
                  child: InteractionEmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No announcements',
                    message: 'Company announcements will show here.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: list.length,
              itemBuilder: (_, i) => _card(list[i]),
            ),
    );
  }

  static const _statusColors = <String, (Color, Color)>{
    'Published': (Color(0xFFDCFCE7), Color(0xFF15803D)),
    'Scheduled': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
    'Draft': (Color(0xFFF1F5F9), Color(0xFF475569)),
    'Expired': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  };

  Widget _statusPill(String status) {
    final (bg, fg) = _statusColors[status] ?? _statusColors['Draft']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.4),
      ),
    );
  }

  Widget _card(StaffAnnouncement a) {
    final cover = mediaImageProvider(a.coverUrl);
    final myComments = a.threads.length;
    final replies = a.threads.fold<int>(0, (s, t) => s + t.replies.length);
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => StaffAnnouncementDetailScreen(announcementId: a.id, initial: a),
        ));
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kInteractionLine),
          boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != null)
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Image(image: cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign_rounded, size: 16, color: kInteractionAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          a.audience.isNotEmpty ? a.audience : (a.from.isNotEmpty ? a.from : 'Announcement'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInteractionMuted),
                        ),
                      ),
                      _statusPill(a.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    a.title,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: kInteractionInk, height: 1.3),
                  ),
                  if (a.subject.isNotEmpty || a.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      a.subject.isNotEmpty ? a.subject : a.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: kInteractionMuted, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 14, color: kInteractionMuted),
                      Text(
                        ' ${a.rawPublishDate != null ? DateFormat('d MMM yyyy').format(a.rawPublishDate!.toLocal()) : '—'}',
                        style: const TextStyle(fontSize: 12, color: kInteractionMuted),
                      ),
                      const Spacer(),
                      if (a.attachments.isNotEmpty) ...[
                        const Icon(Icons.attach_file_rounded, size: 14, color: kInteractionMuted),
                        Text(' ${a.attachments.length}', style: const TextStyle(fontSize: 12, color: kInteractionMuted)),
                        const SizedBox(width: 12),
                      ],
                      if (myComments > 0) ...[
                        const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: kInteractionMuted),
                        Text(
                          ' $myComments${replies > 0 ? ' · $replies repl${replies == 1 ? 'y' : 'ies'}' : ''}',
                          style: const TextStyle(fontSize: 12, color: kInteractionMuted),
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
    );
  }
}
