// Pick a colleague (or the company admin) to start / resume a direct chat.

import 'package:flutter/material.dart';

import '../../../services/staff_interaction_service.dart';
import '../../../utils/snackbar_utils.dart';
import 'staff_chat_thread_screen.dart';
import 'staff_interaction_widgets.dart';

class StaffNewChatScreen extends StatefulWidget {
  const StaffNewChatScreen({super.key});

  @override
  State<StaffNewChatScreen> createState() => _StaffNewChatScreenState();
}

class _StaffNewChatScreenState extends State<StaffNewChatScreen> {
  final _svc = StaffInteractionService.instance;
  List<ChatContact> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _opening;

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
    final r = await _svc.getDirectory();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _all = r.data!;
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _start(ChatContact c) async {
    if (_opening != null) return;
    setState(() => _opening = c.id);
    final r = await _svc.openDirect(c.id);
    if (!mounted) return;
    setState(() => _opening = null);
    if (!r.ok) {
      SnackBarUtils.showSnackBar(context, r.error!, isError: true);
      return;
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute<bool>(
      builder: (_) => StaffChatThreadScreen(
        conversationId: r.data!,
        title: c.name,
        avatar: c.avatar,
        type: 'direct',
        subtitle: c.subtitle,
        participantId: c.id,
      ),
      settings: const RouteSettings(name: 'staff-chat-thread'),
    ), result: true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = _all
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.subtitle.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: kInteractionInk,
        title: const Text('New chat', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search people',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                : _error != null
                    ? InteractionEmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: 'Could not load people',
                        message: _error!,
                        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      )
                    : list.isEmpty
                        ? const InteractionEmptyState(icon: Icons.person_search_outlined, title: 'No one found')
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final c = list[i];
                              return ListTile(
                                onTap: () => _start(c),
                                leading: InteractionAvatar(
                                  name: c.name,
                                  url: c.avatar,
                                  icon: c.isAdmin && c.avatar.isEmpty ? Icons.admin_panel_settings_outlined : null,
                                  online: _svc.isOnline(c.id),
                                ),
                                title: Text(
                                  c.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: kInteractionInk),
                                ),
                                subtitle: c.subtitle.isEmpty
                                    ? null
                                    : Text(c.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: _opening == c.id
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : (c.isAdmin
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: kInteractionAccent.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Text(
                                              'ADMIN',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: kInteractionAccent),
                                            ),
                                          )
                                        : null),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
