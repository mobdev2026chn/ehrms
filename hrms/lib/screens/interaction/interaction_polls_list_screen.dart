// hrms/lib/screens/interaction/interaction_polls_list_screen.dart
// Web-style "Polls & Surveys" rows (title, type chips, status, responses, ends, action).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
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
        ? AppColors.textSecondary
        : (active ? AppColors.success : AppColors.info);
    final bg = closed
        ? AppColors.inputFill
        : (active ? AppColors.successBg : AppColors.infoBg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: closed ? AppColors.textCaption : color,
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
              _emptyIcon(Icons.wifi_off_rounded, fg: AppColors.error, bg: AppColors.errorBg),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_polls.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _emptyIcon(Icons.poll_outlined),
                    const SizedBox(height: 12),
                    const Text(
                      'No polls available right now.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
                                      style: AppTextStyles.headingSmall,
                                    ),
                                    if (desc.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          desc,
                                          style: AppTextStyles.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
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
                                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                              ),
                              const Spacer(),
                              Text(
                                targets > 0 ? '$responses / $targets' : '$responses',
                                style: AppTextStyles.label.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: targets > 0 ? progress : null,
                              minHeight: 6,
                              backgroundColor: const Color(0xFFEDEFF2),
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
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
                                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      end != null
                                          ? DateFormat.yMd().add_jm().format(end)
                                          : '—',
                                      style: AppTextStyles.label.copyWith(
                                        fontSize: 13,
                                        color: AppColors.textPrimary,
                                      ),
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
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E5EA)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _emptyIcon(IconData icon, {Color? fg, Color? bg}) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: bg ?? AppColors.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 28, color: fg ?? AppColors.primaryText),
    );
  }
}
