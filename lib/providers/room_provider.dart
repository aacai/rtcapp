import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rtcapp2/providers/room_notifier.dart';

import '../core/result.dart';
import '../data/chat_room_state.dart';

final roomProvider =
    StateNotifierProvider<RoomNotifier, Room?>((ref) => RoomNotifier());
final chatRoomStateProvider =
    StateNotifierProvider<ChatNotifier, ChatRoomState>((ref) => ChatNotifier());
