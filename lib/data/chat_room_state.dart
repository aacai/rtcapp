import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatRoomState {
  final String url;
  final String token;
  final bool isConnected;

  ChatRoomState({
    required this.url,
    required this.token,
    required this.isConnected,
  });
  ChatRoomState copyWith({
    String? url,
    String? token,
    bool? isConnected,
  }) {
    return ChatRoomState(
      url: url ?? this.url,
      token: token ?? this.token,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatRoomState> {
  ChatNotifier()
      : super(ChatRoomState(
          url: 'wss://example.com/socket',
          token: 'abc123',
          isConnected: true,
        ));

  void updateConnection(bool newStatus) {
    state = state.copyWith(isConnected: newStatus);
  }

  void setState(ChatRoomState newState) {
    state = newState;
  }

  void updateToken(String newToken) {
    state = state.copyWith(token: newToken);
  }
}
