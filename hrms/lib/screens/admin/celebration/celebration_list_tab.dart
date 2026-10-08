// One celebration list (birthdays or anniversaries): summary tiles, auto-send status,
// range filter with per-range counts, search, paging, and single / bulk "Send wishes".

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_celebration_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'celebration_shared.dart';
import 'send_wishes_sheet.dart';

const _rangeLabels = {'today': 'Today', 'week': 'This Week', 'month': 'This Month', 'all': 'All'};

class CelebrationListTab extends StatefulWidget {
  const CelebrationListTab({super.key, required this.kind, required this.store});
  final String kind;
  final CelebrationStore store;

  @override
  State<CelebrationListTab> createState() => _CelebrationListTabState();
}

class _CelebrationListTabState extends State<CelebrationListTab> with AutomaticKeepAliveClientMixin {
  static const int _limit = 24;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _range = 'month';
  String _search = '';
  int _page = 1;

  CelebrationPage? _data;
  String? _error;
  bool _loading = false;
  int _requestSeq = 0;

  final Set<String> _selected = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() => _loading = true);
    try {
      final page = await widget.store.api.list(
        kind: widget.kind,
        range: _range,
        search: _search,
        page: _page,
        limit: _limit,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _data = page;
        _error = null;
        _loading = false;
        // A selection must never carry onto rows that are no longer on screen.
        final visible = page.items.where((e) => e.status != 'sent').map((e) => e.id).toSet();
        _selected.removeWhere((id) => !visible.contains(id));
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = ErrorMessageUtils.toUserFriendlyMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => Future.wait([_load(), widget.store.loadSummary(), widget.store.loadSettings()]);

  void _setRange(String r) {
    if (r == _range) return;
    setState(() {
      _range = r;
      _page = 1;
      _selected.clear();
    });
    _load();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search = q;
      _page = 1;
      _selected.clear();
      _load();
    });
  }

  void _goToPage(int p) {
    setState(() {
      _page = p;
      _selected.clear();
    });
    _load();
  }

  Future<void> _send(List<CelebrationEntry> entries) async {
    if (entries.isEmpty) return;
    if (widget.store.templates == null) await widget.store.loadTemplates();
    if (!mounted) return;
    if (widget.store.templates == null) {
      showCelebrationSnack(context, widget.store.templatesError ?? 'Could not load templates', error: true);
      return;
    }
    final message = await showSendWishesSheet(
      context,
      store: widget.store,
      kind: widget.kind,
      entries: entries,
    );
    if (message == null || !mounted) return;
    showCelebrationSnack(context, message);
    setState(_selected.clear);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _data?.items ?? const <CelebrationEntry>[];
    final selectable = items.where((e) => e.status != 'sent').toList();
    final selectedEntries = items.where((e) => _selected.contains(e.id)).toList();
    final allSelected = selectable.isNotEmpty && selectedEntries.length == selectable.length;

    return Column(
      children: [
        _filters(),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: _body(items, selectable, allSelected),
          ),
        ),
        if (selectedEntries.isNotEmpty)
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${selectedEntries.length} selected',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                  TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.surfaceDark, foregroundColor: Colors.white),
                    onPressed: () => _send(selectedEntries),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send Wishes'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _filters() {
    final counts = _data?.counts;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: Color(0xFFECEEF1))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search name, ID, department...',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final r in kCelebrationRanges)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(counts == null ? _rangeLabels[r]! : '${_rangeLabels[r]} (${counts[r] ?? 0})'),
                      selected: _range == r,
                      onSelected: (_) => _setRange(r),
                      selectedColor: AppColors.surfaceDark,
                      backgroundColor: AppColors.surface,
                      side: BorderSide(color: _range == r ? AppColors.surfaceDark : const Color(0xFFE2E5EA)),
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _range == r ? Colors.white : AppColors.textSecondary,
                      ),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<CelebrationEntry> items, List<CelebrationEntry> selectable, bool allSelected) {
    if (_error != null && _data == null) return CelebrationErrorView(message: _error!, onRetry: _load);
    if (_data == null) {
      return ListView(children: const [SizedBox(height: 120), Center(child: AppTabLoader())]);
    }
    final data = _data!;
    final noun = widget.kind == 'birthday' ? 'birthdays' : 'work anniversaries';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SummaryTiles(store: widget.store),
        const SizedBox(height: 12),
        _AutomationBanner(store: widget.store, kind: widget.kind),
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 2),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12.5))),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ]),
          ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          CelebrationEmptyView(
            icon: widget.kind == 'birthday' ? Icons.cake_outlined : Icons.celebration_outlined,
            title: 'No $noun in this range',
            subtitle: _search.isNotEmpty
                ? 'Nothing matches your search. Try a different name or widen the date range.'
                : 'Try a wider date range, or check that staff profiles carry the dates this reads from.',
          )
        else ...[
          Row(
            children: [
              Text('${data.total} ${data.total == 1 ? 'person' : 'people'}',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 13)),
              const Spacer(),
              TextButton.icon(
                onPressed: selectable.isEmpty
                    ? null
                    : () => setState(() {
                          if (allSelected) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(selectable.map((e) => e.id));
                          }
                        }),
                icon: Icon(allSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 18),
                label: Text(allSelected ? 'Deselect all' : 'Select all (${selectable.length})'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final e in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EntryCard(
                entry: e,
                selected: _selected.contains(e.id),
                onToggle: e.status == 'sent'
                    ? null
                    : () => setState(() => _selected.contains(e.id) ? _selected.remove(e.id) : _selected.add(e.id)),
                onSend: e.status == 'sent' ? null : () => _send([e]),
              ),
            ),
          if (data.pages > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  tooltip: 'Previous page',
                  onPressed: data.page > 1 && !_loading ? () => _goToPage(data.page - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                const SizedBox(width: 12),
                Text('Page ${data.page} of ${data.pages}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppColors.textPrimary)),
                const SizedBox(width: 12),
                IconButton.outlined(
                  tooltip: 'Next page',
                  onPressed: data.page < data.pages && !_loading ? () => _goToPage(data.page + 1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.store});
  final CelebrationStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.summary;
        if (s == null && store.summaryError != null) {
          return CelebrationCard(
            child: Row(children: [
              Expanded(child: Text(store.summaryError!, style: const TextStyle(color: AppColors.error, fontSize: 12.5))),
              TextButton(onPressed: store.loadSummary, child: const Text('Retry')),
            ]),
          );
        }
        // The "today" tile is the dark brand celebration card; the rest are white surface tiles.
        Widget tile(IconData icon, String label, int? value, String hint, {bool dark = false}) => Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dark ? AppColors.surfaceDark : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: dark ? null : Border.all(color: const Color(0xFFECEEF1)),
                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 12,
                                color: dark ? Colors.white70 : AppColors.textSecondary,
                                fontWeight: FontWeight.w500)),
                      ),
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: dark ? Colors.white.withValues(alpha: 0.10) : AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 16, color: dark ? AppColors.primary : AppColors.primaryText),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(value == null ? '-' : '$value',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700, color: dark ? Colors.white : AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(hint,
                        style: TextStyle(fontSize: 11.5, color: dark ? Colors.white60 : AppColors.textSecondary)),
                  ],
                ),
              ),
            );
        return Column(children: [
          Row(children: [
            tile(Icons.calendar_today_outlined, 'Celebrations Today', s?.todayCount, 'Across both kinds', dark: true),
            const SizedBox(width: 12),
            tile(Icons.cake_outlined, 'Birthdays This Month', s?.birthdaysThisMonth, 'Next 31 days'),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            tile(Icons.celebration_outlined, 'Anniversaries This Month', s?.anniversariesThisMonth, 'Next 31 days'),
            const SizedBox(width: 12),
            tile(Icons.dashboard_customize_outlined, 'Templates', s?.templateCount,
                s == null ? 'One default per kind' : '${s.defaultCount} set as default'),
          ]),
        ]);
      },
    );
  }
}

class _AutomationBanner extends StatelessWidget {
  const _AutomationBanner({required this.store, required this.kind});
  final CelebrationStore store;
  final String kind;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final setting = store.settings?.of(kind);
        if (setting == null) return const SizedBox.shrink();
        final on = setting.enabled;
        final tplName = store.defaultOf(kind)?.name;
        String? stored;
        if (setting.templateId != null) {
          for (final t in store.templatesOf(kind)) {
            if (t.id == setting.templateId) stored = t.name;
          }
        }
        final name = stored ?? tplName;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: on ? AppColors.successBg : AppColors.warningBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(on ? Icons.bolt_rounded : Icons.schedule_rounded, size: 20, color: on ? AppColors.success : AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                on
                    ? 'Auto-send is on - wishes go out at ${setting.sendTime}${name != null ? ' using "$name"' : ''}.'
                    : 'Auto-send is off - send wishes by hand, or turn it on in Automation.',
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.selected, required this.onToggle, required this.onSend});
  final CelebrationEntry entry;
  final bool selected;
  final VoidCallback? onToggle;
  final VoidCallback? onSend;

  String get _when {
    if (entry.daysAway == 0) return 'Today';
    if (entry.daysAway == 1) return 'Tomorrow';
    return 'In ${entry.daysAway} days';
  }

  @override
  Widget build(BuildContext context) {
    final initials = entry.staffName.trim().isEmpty
        ? '?'
        : entry.staffName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    final sub = [entry.employeeId, entry.department, entry.designation].where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(16),
      child: CelebrationCard(
        highlighted: selected || entry.daysAway == 0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onToggle != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggle!(),
                    activeColor: AppColors.surfaceDark,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary.withValues(alpha: 0.14),
              foregroundImage: (entry.profilePic ?? '').startsWith('http') ? NetworkImage(entry.profilePic!) : null,
              onForegroundImageError: (entry.profilePic ?? '').startsWith('http') ? (_, __) {} : null,
              child: Text(initials,
                  style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.staffName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _pill(Icons.event_outlined, '${formatOccasionDate(entry.date)} · $_when',
                          entry.daysAway == 0 ? AppColors.warningBg : AppColors.inputFill,
                          entry.daysAway == 0 ? AppColors.warning : AppColors.textSecondary),
                      if (entry.kind == 'anniversary' && entry.yearsOfService != null)
                        _pill(Icons.workspace_premium_outlined,
                            '${entry.yearsOfService} ${entry.yearsOfService == 1 ? 'year' : 'years'}', AppColors.indigoBg, AppColors.indigo),
                      _status(entry.status),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            onSend == null
                ? const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
                  )
                : IconButton.filled(
                    tooltip: 'Send wish',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: onSend,
                    icon: const Icon(Icons.send_rounded, size: 18),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _status(String status) {
    switch (status) {
      case 'sent':
        return _pill(Icons.check_circle_outline_rounded, 'Sent', AppColors.successBg, AppColors.success);
      case 'scheduled':
        return _pill(Icons.schedule_rounded, 'Scheduled', AppColors.infoBg, AppColors.info);
      default:
        return _pill(Icons.radio_button_unchecked_rounded, 'Not sent', AppColors.inputFill, AppColors.textSecondary);
    }
  }

  Widget _pill(IconData icon, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );
}
