import 'dart:async';
import 'dart:html';

import 'package:just_audio_web/src/play_pause_request.dart';

class PlayPauseQueue {
  final AudioElement audioElement;
  final _queue = StreamController<PlayPauseRequest>();

  PlayPauseQueue(this.audioElement) {
    _run();
  }

  Future<void> play() async {
    final request = PlayPauseRequest(true);
    _queue.add(request);
    await request.completer.future;
  }

  Future<void> pause() async {
    final request = PlayPauseRequest(false);
    _queue.add(request);
    await request.completer.future;
  }

  Future<void> _run() async {
    await for (var request in _queue.stream) {
      try {
        if (request.playing) {
          await audioElement.play();
        } else {
          audioElement.pause();
        }
        request.completer.complete();
      } catch (e, st) {
        request.completer.completeError(e, st);
      }
    }
  }
}
