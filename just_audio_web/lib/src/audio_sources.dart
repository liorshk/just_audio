import 'dart:async';
import 'dart:html';
import 'dart:math';

import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'html5_audio_player.dart';
import 'play_pause_queue.dart';

/// A player for a single audio source.
abstract class AudioSourcePlayer {
  /// The [Html5AudioPlayer] responsible for audio I/O.
  Html5AudioPlayer html5AudioPlayer;

  /// The ID of the underlying audio source.
  final String id;

  AudioSourcePlayer(this.html5AudioPlayer, this.id);

  /// The sequence of players for the indexed items nested in this player.
  List<IndexedAudioSourcePlayer> get sequence;

  /// The order to use over [sequence] when in shuffle mode.
  List<int> get shuffleIndices;

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
          other is AudioSourcePlayer &&
          other.id == id;
}

/// A player for an [IndexedAudioSourceMessage].
abstract class IndexedAudioSourcePlayer extends AudioSourcePlayer {
  IndexedAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id)
      : super(html5AudioPlayer, id);

  /// Loads the audio for the underlying audio source.
  Future<Duration?> load([int? initialPosition]);

  /// Plays the underlying audio source.
  Future<void> play();

  /// Pauses playback of the underlying audio source.
  Future<void> pause();

  /// Seeks to [position] milliseconds.
  Future<void> seek(int position);

  /// Called when playback reaches the end of the underlying audio source.
  Future<void> complete();

  /// Called when the playback position of the underlying HTML5 player changes.
  Future<void> timeUpdated(double seconds) async {}

  /// The duration of the underlying audio source.
  Duration? get duration;

  /// The current playback position.
  Duration get position;

  /// The current buffered position.
  Duration get bufferedPosition;

  /// The audio element that renders the audio.
  AudioElement get _audioElement => html5AudioPlayer.audioElement;

  PlayPauseQueue get _playPauseQueue => html5AudioPlayer.playPauseQueue;

  @override
  String toString() => "$runtimeType";
}

/// A player for an [UriAudioSourceMessage].
abstract class UriAudioSourcePlayer extends IndexedAudioSourcePlayer {
  /// The URL to play.
  final Uri uri;

  /// The headers to include in the request (unsupported).
  final Map<String, String>? headers;
  double? _resumePos;
  Duration? _duration;
  Completer<dynamic>? _completer;
  int? _initialPos;

  UriAudioSourcePlayer(
      Html5AudioPlayer html5AudioPlayer, String id, this.uri, this.headers)
      : super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence => [this];

  @override
  List<int> get shuffleIndices => [0];

  @override
  Future<Duration?> load([int? initialPosition]) async {
    _initialPos = initialPosition;
    _resumePos = (initialPosition ?? 0) / 1000.0;
    _duration = await html5AudioPlayer.loadUri(
        uri,
        initialPosition != null
            ? Duration(milliseconds: initialPosition)
            : null);
    _initialPos = null;
    return _duration;
  }

  @override
  Future<void> play() async {
    _audioElement.currentTime = _resumePos ?? 0;
    await _playPauseQueue.play();
    _completer = Completer<dynamic>();
    await _completer!.future;
    _completer = null;
  }

  @override
  Future<void> pause() async {
    _resumePos = _audioElement.currentTime as double?;
    _playPauseQueue.pause();
    _interruptPlay();
  }

  @override
  Future<void> seek(int position) async {
    _audioElement.currentTime = _resumePos = position / 1000.0;
  }

  @override
  Future<void> complete() async {
    _interruptPlay();
    html5AudioPlayer.onEnded();
  }

  void _interruptPlay() {
    if (_completer?.isCompleted == false) {
      _completer!.complete();
    }
  }

  @override
  Duration? get duration {
    return _duration;
    //final seconds = _audioElement.duration;
    //return seconds.isFinite
    //    ? Duration(milliseconds: (seconds * 1000).toInt())
    //    : null;
  }

  @override
  Duration get position {
    if (_initialPos != null) return Duration(milliseconds: _initialPos!);
    final seconds = _audioElement.currentTime as double;
    return Duration(milliseconds: (seconds * 1000).toInt());
  }

  @override
  Duration get bufferedPosition {
    if (_audioElement.buffered.length > 0) {
      return Duration(
          milliseconds:
              (_audioElement.buffered.end(_audioElement.buffered.length - 1) *
                      1000)
                  .toInt());
    } else {
      return Duration.zero;
    }
  }
}

/// A player for a [ProgressiveAudioSourceMessage].
class ProgressiveAudioSourcePlayer extends UriAudioSourcePlayer {
  ProgressiveAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      Uri uri, Map<String, String>? headers)
      : super(html5AudioPlayer, id, uri, headers);
}

/// A player for a [DashAudioSourceMessage].
class DashAudioSourcePlayer extends UriAudioSourcePlayer {
  DashAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id, Uri uri,
      Map<String, String>? headers)
      : super(html5AudioPlayer, id, uri, headers);
}

/// A player for a [HlsAudioSourceMessage].
class HlsAudioSourcePlayer extends UriAudioSourcePlayer {
  HlsAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id, Uri uri,
      Map<String, String>? headers)
      : super(html5AudioPlayer, id, uri, headers);
}

/// A player for a [ConcatenatingAudioSourceMessage].
class ConcatenatingAudioSourcePlayer extends AudioSourcePlayer {
  /// The players for each child audio source.
  final List<AudioSourcePlayer> audioSourcePlayers;

  /// Whether audio should be loaded as late as possible. (Currently ignored.)
  final bool useLazyPreparation;
  List<int> _shuffleOrder;

  ConcatenatingAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      this.audioSourcePlayers, this.useLazyPreparation, List<int> shuffleOrder)
      : _shuffleOrder = shuffleOrder,
        super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence =>
      audioSourcePlayers.expand((p) => p.sequence).toList();

  @override
  List<int> get shuffleIndices {
    final order = <int>[];
    var offset = order.length;
    final childOrders = <List<int>>[];
    for (var audioSourcePlayer in audioSourcePlayers) {
      final childShuffleIndices = audioSourcePlayer.shuffleIndices;
      childOrders.add(childShuffleIndices.map((i) => i + offset).toList());
      offset += childShuffleIndices.length;
    }
    for (var i = 0; i < childOrders.length; i++) {
      order.addAll(childOrders[_shuffleOrder[i]]);
    }
    return order;
  }

  /// Sets the current shuffle order.
  void setShuffleOrder(List<int> shuffleOrder) {
    _shuffleOrder = shuffleOrder;
  }

  /// Inserts [players] into this player at position [index].
  void insertAll(int index, List<AudioSourcePlayer> players) {
    audioSourcePlayers.insertAll(index, players);
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      if (_shuffleOrder[i] >= index) {
        _shuffleOrder[i] += players.length;
      }
    }
  }

  /// Removes the child players in the specified range.
  void removeRange(int start, int end) {
    audioSourcePlayers.removeRange(start, end);
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      if (_shuffleOrder[i] >= end) {
        _shuffleOrder[i] -= (end - start);
      }
    }
  }

  /// Moves a child player from [currentIndex] to [newIndex].
  void move(int currentIndex, int newIndex) {
    audioSourcePlayers.insert(
        newIndex, audioSourcePlayers.removeAt(currentIndex));
  }
}

/// A player for a [ClippingAudioSourceMessage].
class ClippingAudioSourcePlayer extends IndexedAudioSourcePlayer {
  final UriAudioSourcePlayer audioSourcePlayer;
  final Duration? start;
  final Duration? end;
  Completer<ClipInterruptReason>? _completer;
  double? _resumePos;
  Duration? _duration;
  int? _initialPos;

  ClippingAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      this.audioSourcePlayer, this.start, this.end)
      : super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence => [this];

  @override
  List<int> get shuffleIndices => [0];

  Duration get effectiveStart => start ?? Duration.zero;

  @override
  Future<Duration?> load([int? initialPosition]) async {
    initialPosition ??= 0;
    _initialPos = initialPosition;
    final absoluteInitialPosition =
        effectiveStart.inMilliseconds + initialPosition;
    _resumePos = absoluteInitialPosition / 1000.0;
    final fullDuration = (await html5AudioPlayer.loadUri(audioSourcePlayer.uri,
        Duration(milliseconds: absoluteInitialPosition)));
    _initialPos = null;
    if (fullDuration != null) {
      _duration = Duration(
          milliseconds: min((end ?? fullDuration).inMilliseconds,
                  fullDuration.inMilliseconds) -
              effectiveStart.inMilliseconds);
    } else if (end != null) {
      _duration = Duration(
          milliseconds: end!.inMilliseconds - effectiveStart.inMilliseconds);
    }
    return _duration;
  }

  double get remaining =>
      end!.inMilliseconds / 1000 - _audioElement.currentTime;

  @override
  Future<void> play() async {
    if (_completer != null) return;
    _completer = Completer<ClipInterruptReason>();
    _audioElement.currentTime = _resumePos!;
    await _playPauseQueue.play();
    ClipInterruptReason reason;
    while ((reason = await _completer!.future) == ClipInterruptReason.seek) {
      _completer = Completer<ClipInterruptReason>();
    }
    if (reason == ClipInterruptReason.end) {
      html5AudioPlayer.onEnded();
    }
    _completer = null;
  }

  @override
  Future<void> pause() async {
    _interruptPlay(ClipInterruptReason.pause);
    _resumePos = _audioElement.currentTime as double?;
    _playPauseQueue.pause();
  }

  @override
  Future<void> seek(int position) async {
    _interruptPlay(ClipInterruptReason.seek);
    _audioElement.currentTime =
        _resumePos = effectiveStart.inMilliseconds / 1000.0 + position / 1000.0;
  }

  @override
  Future<void> complete() async {
    _interruptPlay(ClipInterruptReason.end);
  }

  @override
  Future<void> timeUpdated(double seconds) async {
    if (end != null) {
      if (seconds >= end!.inMilliseconds / 1000) {
        _interruptPlay(ClipInterruptReason.end);
      }
    }
  }

  @override
  Duration? get duration {
    return _duration;
  }

  @override
  Duration get position {
    if (_initialPos != null) return Duration(milliseconds: _initialPos!);
    final seconds = _audioElement.currentTime as double;
    var position = Duration(milliseconds: (seconds * 1000).toInt());
    position -= effectiveStart;
    if (position < Duration.zero) {
      position = Duration.zero;
    }
    return position;
  }

  @override
  Duration get bufferedPosition {
    if (_audioElement.buffered.length > 0) {
      var seconds =
          _audioElement.buffered.end(_audioElement.buffered.length - 1);
      var position = Duration(milliseconds: (seconds * 1000).toInt());
      position -= effectiveStart;
      if (position < Duration.zero) {
        position = Duration.zero;
      }
      if (duration != null && position > duration!) {
        position = duration!;
      }
      return position;
    } else {
      return Duration.zero;
    }
  }

  void _interruptPlay(ClipInterruptReason reason) {
    if (_completer?.isCompleted == false) {
      _completer!.complete(reason);
    }
  }
}

/// Reasons why playback of a clipping audio source may be interrupted.
enum ClipInterruptReason { end, pause, seek }

/// A player for a [LoopingAudioSourceMessage].
class LoopingAudioSourcePlayer extends AudioSourcePlayer {
  /// The child audio source player to loop.
  final AudioSourcePlayer audioSourcePlayer;

  /// The number of times to loop.
  final int count;

  LoopingAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      this.audioSourcePlayer, this.count)
      : super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence =>
      List.generate(count, (i) => audioSourcePlayer)
          .expand((p) => p.sequence)
          .toList();

  @override
  List<int> get shuffleIndices {
    final order = <int>[];
    var offset = order.length;
    for (var i = 0; i < count; i++) {
      final childShuffleOrder = audioSourcePlayer.shuffleIndices;
      order.addAll(childShuffleOrder.map((i) => i + offset).toList());
      offset += childShuffleOrder.length;
    }
    return order;
  }
}
