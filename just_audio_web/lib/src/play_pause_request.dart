
import 'dart:async';

class PlayPauseRequest {
  final bool playing;
  final completer = Completer<void>();

  PlayPauseRequest(this.playing);
}