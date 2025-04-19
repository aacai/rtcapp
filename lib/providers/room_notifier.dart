import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rtcapp2/core/scope_functions.dart';
import 'package:rtcapp2/services/log_utils.dart';

import '../core/result.dart';

class RoomNotifier extends StateNotifier<Room?> {
  RoomNotifier() : super(null);

  Future<Result<Room>> connectToRoom(String url, String token) async {
    final room = Room(roomOptions: RoomOptions(adaptiveStream: true));
    try {
      await room.prepareConnection(url, token);
      await room.connect(url, token);
      state = room;
      return Result.success(room);
    } catch (e) {
      state = null;
      return Result.failure(e);
    }
  }

  void _destroy() {
    state?.apply((room) {
      LogUtils.v("room notifier destroy");
      room.localParticipant?.apply((participant) async {
        participant.trackPublications.forEach((name, publication) {
          publication.track?.stop();
        });
        await participant.setMicrophoneEnabled(false);
        await participant.setCameraEnabled(false);
        await participant.setScreenShareEnabled(false);
        await participant.unpublishAllTracks(stopOnUnpublish: true);
        await room.disconnect();
        await room.localParticipant?.dispose();
      });
    });
  }

  @override
  void dispose() {
    _destroy();
    super.dispose();
  }
}
