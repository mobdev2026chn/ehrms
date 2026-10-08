// hrms/lib/screens/interaction/interaction_poll_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../utils/snackbar_utils.dart';
import '../../services/interaction_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';

class InteractionPollDetailScreen extends StatefulWidget {
  const InteractionPollDetailScreen({
    super.key,
    required this.pollId,
    this.previewTitle,
  });

  final String pollId;
  final String? previewTitle;

  @override
  State<InteractionPollDetailScreen> createState() => _InteractionPollDetailScreenState();
}

class _InteractionPollDetailScreenState extends State<InteractionPollDetailScreen> {
  Map<String, dynamic>? _poll;
  List<Map<String, dynamic>> _options = [];
  List<dynamic>? _myOptionIds;
  List<Map<String, dynamic>>? _results;
  bool _loading = true;
  bool _submitting = false;
  String? _role;
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _role = await InteractionService.currentUserRole();
      final pollRes = await InteractionService.instance.getPoll(widget.pollId);
      final raw = pollRes['data'];
      if (raw is Map) {
        final m = <String, dynamic>{};
        raw.forEach((k, v) => m[k.toString()] = v);
        _poll = m;
        final opts = m['options'];
        _options = [];
        if (opts is List) {
          for (final e in opts) {
            if (e is Map) {
              final o = <String, dynamic>{};
              e.forEach((k, v) => o[k.toString()] = v);
              _options.add(o);
            }
          }
        }
      }

      final listRes = await InteractionService.instance.getPolls();
      final data = listRes['data'];
      if (data is List) {
        for (final e in data) {
          if (e is Map && (e['_id']?.toString() ?? e['id']?.toString()) == widget.pollId) {
            _myOptionIds = e['myOptionIds'] as List<dynamic>?;
            break;
          }
        }
      }

      if ((_myOptionIds != null && _myOptionIds!.isNotEmpty) ||
          _poll?['isClosed'] == true ||
          InteractionService.roleCannotVote(_role)) {
        final res = await InteractionService.instance.getPollResults(widget.pollId);
        final d = res['data'];
        if (d is List) {
          _results = [];
          for (final e in d) {
            if (e is Map) {
              final r = <String, dynamic>{};
              e.forEach((k, v) => r[k.toString()] = v);
              _results!.add(r);
            }
          }
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Choose at least one option');
      return;
    }
    setState(() => _submitting = true);
    try {
      final r = await InteractionService.instance.votePoll(
        widget.pollId,
        optionIds: _selected.toList(),
      );
      if (r['success'] == false) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            r['message']?.toString() ?? 'Could not submit vote',
          );
        }
        return;
      }
      _selected.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static const Color _kHairline = Color(0xFFECEEF1);

  bool get _cannotVote => InteractionService.roleCannotVote(_role);

  bool get _alreadyVoted => _myOptionIds != null && _myOptionIds!.isNotEmpty;

  bool get _closed => _poll?['isClosed'] == true;

  String get _pollType => _poll?['pollType']?.toString() ?? 'single';

  @override
  Widget build(BuildContext context) {
    final title = _poll?['title']?.toString() ?? widget.previewTitle ?? 'Poll';
    final desc = _poll?['description']?.toString();
    final start = DateTime.tryParse(_poll?['startDate']?.toString() ?? '')?.toLocal();
    final end = DateTime.tryParse(_poll?['endDate']?.toString() ?? '')?.toLocal();

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('Poll'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    border: Border.all(color: _kHairline),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.poll_outlined, size: 22, color: AppColors.primaryText),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(title, style: AppTextStyles.headingMedium)),
                    ],
                  ),
                  if (desc != null && desc.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      desc,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.45),
                    ),
                  ],
                  if (start != null || end != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.schedule_rounded, size: 16, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                      [
                        if (start != null) 'Starts: ${DateFormat.yMMMd().add_jm().format(start)}',
                        if (end != null) 'Ends: ${DateFormat.yMMMd().add_jm().format(end)}',
                      ].join('\n'),
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                      ],
                    ),
                  ),
                  if (_cannotVote) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                          'Admin-side roles can manage polls on web and cannot vote in app (web parity).',
                              style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_results != null && _results!.isNotEmpty) ...[
                    const Text('Results', style: AppTextStyles.headingSmall),
                    const SizedBox(height: 8),
                    AppCard(
                      border: Border.all(color: _kHairline),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    ..._results!.map((r) {
                      final label = r['optionText']?.toString() ?? '';
                      final pct = (r['percentage'] as num?)?.toInt() ?? 0;
                      final count = (r['voteCount'] as num?)?.toInt() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$pct% ($count)',
                                  style: AppTextStyles.caption.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                              value: pct / 100,
                              minHeight: 8,
                              backgroundColor: const Color(0xFFEDEFF2),
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                        ],
                      ),
                    ),
                  ] else if (!_closed && !_cannotVote && !_alreadyVoted) ...[
                    const Text('Your vote', style: AppTextStyles.headingSmall),
                    const SizedBox(height: 8),
                    if (_pollType == 'single')
                      ..._options.map((o) {
                        final id = o['_id']?.toString() ?? '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          child: RadioListTile<String>(
                          value: id,
                          groupValue: _selected.length == 1 ? _selected.first : null,
                          onChanged: id.isEmpty
                              ? null
                              : (v) {
                                  setState(() {
                                    _selected
                                      ..clear()
                                      ..add(v!);
                                  });
                                },
                          title: Text(
                            o['optionText']?.toString() ?? '',
                            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                          ),
                          ),
                        );
                      })
                    else
                      ..._options.map((o) {
                        final id = o['_id']?.toString() ?? '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          child: CheckboxListTile(
                          value: _selected.contains(id),
                          onChanged: id.isEmpty
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(id);
                                    } else {
                                      _selected.remove(id);
                                    }
                                  });
                                },
                          title: Text(
                            o['optionText']?.toString() ?? '',
                            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                            )
                          : const Text('Submit vote'),
                    ),
                  ] else if (_alreadyVoted && (_results == null || _results!.isEmpty))
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                color: AppColors.successBg,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded, size: 28, color: AppColors.success),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Thanks — your vote was recorded.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.headingSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }
}
