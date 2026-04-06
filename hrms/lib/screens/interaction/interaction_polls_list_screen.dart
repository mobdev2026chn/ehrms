// hrms/lib/screens/interaction/interaction_polls_list_screen.dart

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
    if (_polls.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No polls available right now.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _polls.length,
        itemBuilder: (context, i) {
          final p = _polls[i];
          final title = p['title']?.toString() ?? 'Poll';
          final active = p['isActive'] == true;
          final closed = p['isClosed'] == true;
          final end = DateTime.tryParse(p['endDate']?.toString() ?? '')?.toLocal();
          final responses = p['responseCount'] ?? 0;
          final targets = p['targetCount'] ?? 0;
          return Card(
            child: ListTile(
              title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  if (end != null) 'Ends ${DateFormat.yMMMd().add_jm().format(end)}',
                  if (targets is num && targets > 0) 'Responses $responses / $targets',
                ].join(' · '),
                maxLines: 2,
              ),
              trailing: Chip(
                label: Text(
                  closed ? 'Closed' : (active ? 'Active' : 'Scheduled'),
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor: closed
                    ? Colors.grey.shade300
                    : (active ? AppColors.primary.withOpacity(0.2) : Colors.blue.shade50),
              ),
              onTap: () async {
                final id = _pollId(p);
                if (id.isEmpty) return;
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InteractionPollDetailScreen(pollId: id),
                  ),
                );
                _load();
              },
            ),
          );
        },
      ),
    );
  }
}
