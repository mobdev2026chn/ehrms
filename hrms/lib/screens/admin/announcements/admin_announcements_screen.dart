// Admin Announcements: the register with server-side status / audience / search filters and
// paging (GET /admin/announcements), like the web admin. Tap a row for its detail and
// engagement; New opens the create form. HRMSbackend /api/admin/announcements.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_announcement_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_announcement_detail_screen.dart';
import 'admin_announcement_form_screen.dart';
import 'announcement_ui.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  static const _pageSize = 10;
  static const _audienceFilters = ['All Staff', 'Individual Staff'];

  final _svc = AdminAnnouncementService.instance;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _status = 'All';
  String? _audience;
  String _search = '';

  List<Map<String, dynamic>> _items = [];
  int _page = 0;
  int _totalPages = 1;
  int _totalItems = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Loads page 1 for the current filters, replacing the list once it succeeds.
  Future<void> _reload() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    final r = await _svc.fetchPage(status: _status, audience: _audience, search: _search, page: 1, limit: _pageSize);
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _items = List<Map<String, dynamic>>.from(r['data'] as List);
        _page = 1;
        _totalPages = r['totalPages'] as int;
        _totalItems = r['totalItems'] as int;
      } else {
        _error = r['message']?.toString() ?? 'Could not load announcements.';
      }
    });
    if (r['success'] != true && _items.isNotEmpty && mounted) {
      SnackBarUtils.showSnackBar(context, _error!, isError: true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    final seq = _requestSeq;
    setState(() => _loadingMore = true);
    final r = await _svc.fetchPage(status: _status, audience: _audience, search: _search, page: _page + 1, limit: _pageSize);
    if (!mounted) return;
    if (seq != _requestSeq) {
      setState(() => _loadingMore = false);
      return;
    }
    setState(() {
      _loadingMore = false;
      if (r['success'] == true) {
        final seen = _items.map(announcementId).toSet();
        _items = [
          ..._items,
          ...List<Map<String, dynamic>>.from(r['data'] as List).where((a) => !seen.contains(announcementId(a))),
        ];
        _page = r['currentPage'] as int;
        _totalPages = r['totalPages'] as int;
        _totalItems = r['totalItems'] as int;
      }
    });
    if (r['success'] != true && mounted) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not load more.', isError: true);
    }
  }

  void _onSearchChanged(String v) {
    setState(() {}); // clear button visibility
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (v.trim() == _search) return;
      _search = v.trim();
      _items = [];
      _reload();
    });
  }

  void _setStatus(String s) {
    if (s == _status) return;
    _status = s;
    _items = [];
    _reload();
  }

  void _setAudience(String? a) {
    if (a == _audience) return;
    _audience = a;
    _items = [];
    _reload();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminAnnouncementFormScreen()),
    );
    if (created == true) _reload();
  }

  Future<void> _open(Map<String, dynamic> a) async {
    final id = announcementId(a);
    if (id.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminAnnouncementDetailScreen(announcementId: id, initial: a)),
    );
    if (changed == true) _reload();
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final id = announcementId(a);
    if (id.isEmpty) return;
    final ok = await confirmAnnouncementDelete(context, (a['title'] ?? '').toString());
    if (ok != true) return;
    final r = await _svc.delete(id);
    if (!mounted) return;
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Announcement deleted.');
      setState(() {
        _items.removeWhere((e) => announcementId(e) == id);
        if (_totalItems > 0) _totalItems--;
      });
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not delete.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Announcements'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: Column(children: [
        _filters(),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _filters() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: Color(0xFFECEEF1))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search title, subject or sender',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                          setState(() {});
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Audience',
            initialValue: _audience ?? '',
            onSelected: (v) => _setAudience(v.isEmpty ? null : v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('Any audience')),
              for (final a in _audienceFilters) PopupMenuItem(value: a, child: Text(a)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: _audience == null ? const Color(0xFFF7F8FA) : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _audience == null ? const Color(0xFFE2E5EA) : AppColors.primary.withValues(alpha: 0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.groups_2_outlined, size: 18, color: _audience == null ? AppColors.textSecondary : AppColors.primaryText),
                const SizedBox(width: 6),
                Text(
                  _audience == null ? 'Audience' : (_audience == 'Individual Staff' ? 'Individual' : _audience!),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _audience == null ? AppColors.textSecondary : AppColors.primaryText),
                ),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in ['All', ...AdminAnnouncementService.statuses])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: s == _status,
                    onSelected: (_) => _setStatus(s),
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                    label: Text(s, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: s == _status ? AppColors.onPrimary : AppColors.textSecondary)),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const Center(child: AppTabLoader());
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _reload,
      child: (_error != null && _items.isEmpty)
          ? announcementMessageView(icon: Icons.wifi_off_rounded, title: 'Could not load', message: _error!, onRetry: _reload)
          : _items.isEmpty
              ? announcementMessageView(
                  icon: Icons.campaign_outlined,
                  title: 'No announcements',
                  message: (_search.isNotEmpty || _status != 'All' || _audience != null)
                      ? 'Nothing matches these filters.'
                      : 'Tap New to post one.',
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) _loadMore();
                    return false;
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _items.length + 2,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12, left: 2),
                          child: Text('$_totalItems announcement${_totalItems == 1 ? '' : 's'}',
                              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        );
                      }
                      if (i == _items.length + 1) return _footer();
                      return _card(_items[i - 1]);
                    },
                  ),
                ),
    );
  }

  Widget _footer() {
    if (_loadingMore) return const Padding(padding: EdgeInsets.all(16), child: Center(child: AppTabLoader()));
    if (_page < _totalPages) {
      return Center(child: TextButton(onPressed: _loadMore, child: const Text('Load more')));
    }
    return const SizedBox.shrink();
  }

  Widget _card(Map<String, dynamic> a) {
    final status = announcementStatus(a);
    final title = (a['title'] ?? 'Announcement').toString();
    final subject = (a['subject'] ?? a['description'] ?? '').toString();
    final from = (a['from'] ?? '').toString();
    final engagements = a['engagements'] is List ? (a['engagements'] as List).length : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(a),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            decoration: announcementCardDecoration,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.campaign_outlined, size: 20, color: AppColors.primaryText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(announcementAudienceLabel(a),
                        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  AnnouncementStatusBadge(status),
                ]),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(title, style: AppTextStyles.headingSmall),
              ),
              if (subject.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall),
                ),
              ],
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.event_outlined, size: 14, color: AppColors.textSecondary),
                Text(' ${announcementDateLabel(a['publishDate'] ?? a['createdAt'])}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                if (from.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textSecondary),
                  Flexible(child: Text(' $from', overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary))),
                ],
                if (engagements > 0) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.forum_outlined, size: 14, color: AppColors.textSecondary),
                  Text(' $engagements', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(a),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AppColors.error),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
