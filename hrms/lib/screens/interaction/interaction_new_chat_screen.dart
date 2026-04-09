// hrms/lib/screens/interaction/interaction_new_chat_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/interaction_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import 'interaction_chat_thread_screen.dart';

class InteractionNewChatScreen extends StatefulWidget {
  const InteractionNewChatScreen({super.key});

  @override
  State<InteractionNewChatScreen> createState() => _InteractionNewChatScreenState();
}

class _InteractionNewChatScreenState extends State<InteractionNewChatScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetch(String q) async {
    setState(() => _loading = true);
    try {
      final res = await InteractionService.instance.getChatSuggestions(query: q.isEmpty ? null : q);
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
      if (mounted) setState(() => _users = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetch(v.trim()));
  }

  @override
  void initState() {
    super.initState();
    _fetch('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('New chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Search colleagues',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, i) {
                final u = _users[i];
                final id = u['_id']?.toString() ?? '';
                final name = u['name']?.toString() ?? 'User';
                final role = u['role']?.toString() ?? '';
                final avatar = u['avatar']?.toString();
                final url = avatar != null && avatar.startsWith('http') ? avatar : null;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    backgroundImage: url != null ? NetworkImage(url) : null,
                    child: url == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  title: Text(name),
                  subtitle: Text(role, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: id.isEmpty
                      ? null
                      : () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => InteractionChatThreadScreen(
                                chatId: 'personal',
                                receiverId: id,
                                title: name,
                                avatarUrl: url,
                                isGroup: false,
                                peerIsOnline: null,
                              ),
                            ),
                          );
                        },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }
}
