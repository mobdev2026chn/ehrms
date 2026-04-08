// hrms/lib/screens/interaction/interaction_poll_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../services/interaction_service.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose at least one option')));
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(r['message']?.toString() ?? 'Could not submit vote')),
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
      appBar: AppBar(title: const Text('Poll')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  if (desc != null && desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(desc, style: TextStyle(color: Colors.grey.shade800)),
                  ],
                  if (start != null || end != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      [
                        if (start != null) 'Starts: ${DateFormat.yMMMd().add_jm().format(start)}',
                        if (end != null) 'Ends: ${DateFormat.yMMMd().add_jm().format(end)}',
                      ].join('\n'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                  if (_cannotVote) ...[
                    const SizedBox(height: 16),
                    Material(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Admin-side roles can manage polls on web and cannot vote in app (web parity).',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_results != null && _results!.isNotEmpty) ...[
                    Text('Results', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._results!.map((r) {
                      final label = r['optionText']?.toString() ?? '';
                      final pct = (r['percentage'] as num?)?.toInt() ?? 0;
                      final count = (r['voteCount'] as num?)?.toInt() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(label)),
                                Text('$pct% ($count)'),
                              ],
                            ),
                            LinearProgressIndicator(
                              value: pct / 100,
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else if (!_closed && !_cannotVote && !_alreadyVoted) ...[
                    Text('Your vote', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_pollType == 'single')
                      ..._options.map((o) {
                        final id = o['_id']?.toString() ?? '';
                        return RadioListTile<String>(
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
                          title: Text(o['optionText']?.toString() ?? ''),
                        );
                      })
                    else
                      ..._options.map((o) {
                        final id = o['_id']?.toString() ?? '';
                        return CheckboxListTile(
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
                          title: Text(o['optionText']?.toString() ?? ''),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Submit vote'),
                    ),
                  ] else if (_alreadyVoted && (_results == null || _results!.isEmpty))
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Thanks — your vote was recorded.')),
                    ),
                ],
              ),
            ),
    );
  }
}
