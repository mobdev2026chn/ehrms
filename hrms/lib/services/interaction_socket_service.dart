// hrms/lib/services/interaction_socket_service.dart
// Socket.IO for Interaction chat — matches backend `socket.service.ts` (auth.token handshake).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/constants.dart';
import 'api_client.dart';
import 'interaction_service.dart';

class InteractionSocketService {
  InteractionSocketService._();
  static final InteractionSocketService instance = InteractionSocketService._();

  io.Socket? _socket;
  final _newMessage = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNewMessage => _newMessage.stream;

  bool get isConnected => _socket?.connected ?? false;

  Future<void> connect() async {
    if (_socket?.connected == true) return;

    final prefs = await SharedPreferences.getInstance();
    var token = InteractionService.normalizeAccessToken(
      prefs.getString(AppConstants.interactionAccessTokenPrefsKey),
    );
    token ??= InteractionService.normalizeAccessToken(prefs.getString('token'));
    if (token == null || token.isEmpty) {
      final auth = ApiClient().dio.options.headers['Authorization'];
      if (auth is String) {
        token = InteractionService.normalizeAccessToken(
          auth.startsWith('Bearer ') ? auth.substring(7) : auth,
        );
      }
    }
    if (token == null || token.isEmpty) return;

    final origin = AppConstants.interactionSocketOrigin;

    _socket?.dispose();
    _socket = io.io(
      origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );

    _socket!.on('new_message', (data) {
      if (data is! Map) return;
      final m = <String, dynamic>{};
      data.forEach((k, v) => m[k.toString()] = v);
      _newMessage.add(m);
    });

    _socket!.onConnect((_) {
      if (kDebugMode) debugPrint('[InteractionSocket] connected');
    });
    _socket!.onDisconnect((_) {
      if (kDebugMode) debugPrint('[InteractionSocket] disconnected');
    });
    _socket!.onConnectError((e) {
      if (kDebugMode) debugPrint('[InteractionSocket] connect_error: $e');
    });

    _socket!.connect();
  }

  void joinGroupChats(Iterable<String> groupIds) {
    for (final id in groupIds) {
      final g = id.trim();
      if (g.isEmpty || g == 'personal') continue;
      _socket?.emit('join_chat', {'groupId': g});
    }
  }

  /// DM thread: join `interaction:user:sortedPair` room.
  void joinDirectChat(String peerUserId) {
    final p = peerUserId.trim();
    if (p.isEmpty) return;
    _socket?.emit('join_chat', {'userId': p});
  }

  void emitTyping({String? groupId, String? receiverId}) {
    _socket?.emit('typing', {
      if (groupId != null) 'groupId': groupId,
      if (receiverId != null) 'receiverId': receiverId,
    });
  }

  void emitStopTyping({String? groupId, String? receiverId}) {
    _socket?.emit('stop_typing', {
      if (groupId != null) 'groupId': groupId,
      if (receiverId != null) 'receiverId': receiverId,
    });
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
