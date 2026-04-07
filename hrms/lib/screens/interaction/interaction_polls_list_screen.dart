// hrms/lib/screens/interaction/interaction_polls_list_screen.dart
// Web-style "Polls & Surveys" rows (title, type chips, status, responses, ends, action).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../utils/error_message_utils.dart';
import '../../services/interaction_service.dart';
import 'interaction_poll_detail_screen.dart';

class InteractionPollsListScreen extends StatefulWidget {
  const InteractionPollsListScreen({super.key});

  @override
  State<InteractionPollsListScreen> createState() => _InteractionPollsListScreenState();
}

class _InteractionPollsListScreenState extends State<InteractionPollsListScreen> {
  List<Map<String, dynamic>> _polls = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await InteractionService.instance.getPolls();
      final data = res['data'];
      final list = <Map<String, dynamic>>[];
      if (data is List) {
        for (final e in data) {
          if (e is Map) {
            final m = <String, dynamic>{};
            e.forEach((k, v) => m[k.toString()] = v);
            list.add(m);
          }
        }
      }
      if (mounted) {
        setState(() {
          _polls = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = InteractionService.isInteractionApiUnavailable(e)
              ? InteractionService.kInteractionMissingOnServerMessage
              : ErrorMessageUtils.toUserFriendlyMessage(e);
          _loading = false;
        });
      }
    }
  }

  String _pollId(Map<String, dynamic> p) {
    return p['_id']?.toString() ?? p['id']?.toString() ?? '';
  }

  String _pollTypeLabel(Map<String, dynamic> p) {
    final t = (p['pollType']?.toString() ?? 'single').toLowerCase();
    return t == 'multiple' ? 'Multiple' : 'Single';
  }

  String _modeLabel(Map<String, dynamic> p) {
    final anon = p['isAnonymous'] == true;
    return anon ? 'Anonymous' : 'Normal';
  }

  Widget _statusPill(Map<String, dynamic> p) {
    final closed = p['isClosed'] == true;
    final active = p['isActive'] == true;
    final label = closed ? 'Closed' : (active ? 'Active' : 'Scheduled');
    final color = closed
        ? Colors.grey.shade600
        : (active ? const Color(0xFF16A34A) : Colors.blue.shade700);
    final bg = closed
        ? Colors.grey.shade200
        : (active ? const Color(0xFFDCFCE7) : Colors.blue.shade50);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: closed ? Colors.grey.shade500 : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _polls.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _polls.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: const Color(0xFFF5F5F5),
      child: RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Polls & Surveys',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
              ),
            ),
          ),
          if (_polls.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No polls available right now.')),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final p = _polls[i];
                  final title = p['title']?.toString() ?? 'Poll';
                  final desc = p['description']?.toString() ?? '';
                  final end = DateTime.tryParse(p['endDate']?.toString() ?? '')?.toLocal();
                  final responses = (p['responseCount'] as num?)?.toInt() ?? 0;
                  final targets = (p['targetCount'] as num?)?.toInt() ?? 0;
                  final progress = targets > 0 ? (responses / targets).clamp(0.0, 1.0) : 0.0;
                  final id = _pollId(p);
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (desc.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          desc,
                                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              _statusPill(p),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chipGrey(_pollTypeLabel(p)),
                              _chipGrey(_modeLabel(p)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'Responses',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const Spacer(),
                              Text(
                                targets > 0 ? '$responses / $targets' : '$responses',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: targets > 0 ? progress : null,
                              minHeight: 6,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ends',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      end != null
                                          ? DateFormat.yMd().add_jm().format(end)
                                          : '—',
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                onPressed: id.isEmpty
                                    ? null
                                    : () async {
                                        await Navigator.push<void>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => InteractionPollDetailScreen(pollId: id),
                                          ),
                                        );
                                        _load();
                                      },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2563EB),
                                  side: BorderSide(color: Colors.grey.shade400),
                                ),
                                child: const Text('View Results'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: _polls.length,
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _chipGrey(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
    );
  }
}
