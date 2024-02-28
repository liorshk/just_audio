import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// The web impluementation of [AudioPlayerPlatform].
abstract class JustAudioPlayer extends AudioPlayerPlatform {
  final eventController = StreamController<PlaybackEventMessage>.broadcast();
  final dataEventController = StreamController<PlayerDataMessage>.broadcast();
  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  bool playing = false;
  int? index;
  double speed = 1.0;

  /// Creates a platform player with the given [id].
  JustAudioPlayer({required String id}) : super(id);

  @mustCallSuper
  Future<void> release() async {
    eventController.close();
    dataEventController.close();
  }

  /// Returns the current position of the player.
  Duration getCurrentPosition();

  /// Returns the current buffered position of the player.
  Duration getBufferedPosition();

  /// Returns the duration of the current player item or `null` if unknown.
  Duration? getDuration();

  /// Broadcasts a playback event from the platform side to the plugin side.
  void broadcastPlaybackEvent() {
    var updateTime = DateTime.now();
    if (!eventController.isClosed) {
      eventController.add(PlaybackEventMessage(
        processingState: _processingState,
        updatePosition: getCurrentPosition(),
        updateTime: updateTime,
        bufferedPosition: getBufferedPosition(),
        // TODO: Icy Metadata
        icyMetadata: null,
        duration: getDuration(),
        currentIndex: index,
        androidAudioSessionId: null,
      ));
    }
  }

  /// Transitions to [processingState] and broadcasts a playback event.
  void transition(ProcessingStateMessage processingState) {
    _processingState = processingState;
    broadcastPlaybackEvent();
  }
}
