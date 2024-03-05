import 'dart:async';
import 'dart:html';
import 'dart:js_interop';
import 'dart:ui_web' as ui;

import 'package:flutter/services.dart';
import 'package:js/js.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'audio_sources.dart';
import 'base_just_audio_player.dart';
import 'extra.dart';
import 'hls.dart';
import 'logger.dart';
import 'play_pause_queue.dart';

/// An HTML5-specific implementation of [JustAudioPlayer].
class Html5AudioPlayer extends JustAudioPlayer {
  final audioElement = AudioElement();
  late final playPauseQueue = PlayPauseQueue(audioElement);
  Completer<dynamic>? _durationCompleter;
  AudioSourcePlayer? _audioSourcePlayer;
  LoopModeMessage _loopMode = LoopModeMessage.off;
  bool _shuffleModeEnabled = false;
  bool recoverAttempt = false;
  final Map<String, AudioSourcePlayer> _audioSourcePlayers = {};
  Hls? _hls;
  String? _currentUrl;

  /// Creates an [Html5AudioPlayer] with the given [id].
  Html5AudioPlayer({required String id}) : super(id: id) {
    audioElement.addEventListener('durationchange', (event) {
      logHLS('audioElement durationchange');
      _durationCompleter?.complete();
      broadcastPlaybackEvent();
    });
    audioElement.addEventListener('error', (Event event) {
      logHLS('audioElement event ERROR');
      _durationCompleter?.completeError(audioElement.error!);
    });
    audioElement.addEventListener('ended', (event) async {
      logHLS('audioElement ended');
      _currentAudioSourcePlayer?.complete();
    });
    audioElement.addEventListener('timeupdate', (event) {
      logHLS('audioElement timeupdate');
      _currentAudioSourcePlayer
          ?.timeUpdated(audioElement.currentTime as double);
    });
    audioElement.addEventListener('loadstart', (event) {
      logHLS('audioElement loadstart');
      transition(ProcessingStateMessage.buffering);
    });
    audioElement.addEventListener('waiting', (event) {
      logHLS('audioElement waiting');
      transition(ProcessingStateMessage.buffering);
    });
    audioElement.addEventListener('stalled', (event) {
      logHLS('audioElement stalled');
      transition(ProcessingStateMessage.buffering);
    });
    audioElement.addEventListener('canplaythrough', (event) {
      logHLS('audioElement canplaythrough');
      audioElement.playbackRate = speed;
      transition(ProcessingStateMessage.ready);
    });
    audioElement.addEventListener('progress', (event) {
      logHLS('audioElement progress');
      broadcastPlaybackEvent();
    });
    audioElement.onCanPlay.listen((dynamic _) {
      logHLS('audioElement onCanPlay');
      _durationCompleter?.complete();
    });
  }

  Future<bool> shouldUseHlsLibrary(Uri uri) async {
    return isSupported() && (uri.toString().contains('m3u8'));
  }

  /// The current playback order, depending on whether shuffle mode is enabled.
  List<int> get order {
    logHLS('Html5AudioPlayer order');
    final sequence = _audioSourcePlayer!.sequence;
    return _shuffleModeEnabled
        ? _audioSourcePlayer!.shuffleIndices
        : List.generate(sequence.length, (i) => i);
  }

  /// gets the inverted order for the given order.
  List<int> getInv(List<int> order) {
    logHLS('Html5AudioPlayer getInv');
    final orderInv = List<int>.filled(order.length, 0);
    for (var i = 0; i < order.length; i++) {
      orderInv[order[i]] = i;
    }
    return orderInv;
  }

  /// Called when playback reaches the end of an item.
  Future<void> onEnded() async {
    logHLS('Html5AudioPlayer onEnded');
    if (_loopMode == LoopModeMessage.one) {
      await _seek(0, null);
      _play();
    } else {
      final order = this.order;
      final orderInv = getInv(order);
      if (orderInv[index!] + 1 < order.length) {
        // move to next item
        index = order[orderInv[index!] + 1];
        await _currentAudioSourcePlayer!.load();
        // Should always be true...
        if (playing) {
          _play();
        }
      } else {
        // reached end of playlist
        if (_loopMode == LoopModeMessage.all) {
          // Loop back to the beginning
          if (order.length == 1) {
            await _seek(0, null);
            _play();
          } else {
            index = order[0];
            await _currentAudioSourcePlayer!.load();
            // Should always be true...
            if (playing) {
              _play();
            }
          }
        } else {
          await _currentAudioSourcePlayer?.pause();
          transition(ProcessingStateMessage.completed);
        }
      }
    }
  }

  // TODO: Improve efficiency.
  IndexedAudioSourcePlayer? get _currentAudioSourcePlayer =>
      _audioSourcePlayer != null &&
              index != null &&
              _audioSourcePlayer!.sequence.isNotEmpty &&
              index! < _audioSourcePlayer!.sequence.length
          ? _audioSourcePlayer!.sequence[index!]
          : null;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      dataEventController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    logHLS('Html5AudioPlayer load');
    _currentAudioSourcePlayer?.pause();
    _audioSourcePlayer = getAudioSource(request.audioSourceMessage);
    index = request.initialIndex ?? 0;
    final duration = await _currentAudioSourcePlayer!
        .load(request.initialPosition?.inMilliseconds);
    if (request.initialPosition != null) {
      await _currentAudioSourcePlayer!
          .seek(request.initialPosition!.inMilliseconds);
    }
    if (playing) {
      _currentAudioSourcePlayer!.play();
    }
    return LoadResponse(duration: duration);
  }

  /// Loads audio from [uri] and returns the duration of the loaded audio if
  /// known.

  Future<Duration?> loadUri(
    final Uri uri,
    final Duration? initialPosition,
  ) async {
    logHLS('Html5AudioPlayer loadUri');
    transition(ProcessingStateMessage.loading);
    final src = uri.toString();
    if (_currentUrl == null || src != _currentUrl) {
      _currentUrl = src;
      logHLS('Html5AudioPlayer loadUri src != audioElement.src');
      logHLS('Html5AudioPlayer loadUri url: $src');
      logHLS('Html5AudioPlayer loadUri: ${audioElement.src}');
      if (await shouldUseHlsLibrary(uri)) {
        logHLS('Html5AudioPlayer shouldUseHlsLibrary');
        if (_hls != null) {
          _hls!.detachMedia();
          _hls!.destroy();
          _hls = null;
        }
        _durationCompleter = Completer<dynamic>();
        audioElement.id = 'audioPlayer-$id';
        audioElement.src = src;
        audioElement.playbackRate = speed;
        audioElement.preload = 'auto';
        ui.platformViewRegistry.registerViewFactory(
            'audioPlayer-$id', (int viewId) => audioElement);
        _hls = Hls(
          HlsConfig(
            debug: false,
            enableWorker: true,
            progressive: false,
            appendErrorMaxRetry: 5,
            lowLatencyMode: true,
            xhrSetup: allowInterop(
              (HttpRequest xhr, String _) {
                xhr.withCredentials = false;
              },
            ),
          ),
        );
        _hls!.loadSource(src);
        _hls!.attachMedia(audioElement);
        _hls!.on('hlsMediaAttached', allowInterop((dynamic _, dynamic __) {
          logHLS('on hlsMediaAttached');
        }));
        _hls!.on('hlsError', allowInterop((dynamic _, dynamic data) {
          logHLS('Html5AudioPlayer on hlsError');
          try {
            final ErrorData errorData = ErrorData(data);
            logHLS(
                'error: ${errorData.type} ${errorData.fatal} ${errorData.details}');
            if (errorData.fatal) {
              if (!recoverAttempt) {
                _hls!.recoverMediaError();
                recoverAttempt = true;
              } else {
                _hls!.swapAudioCodec();
                _hls!.recoverMediaError();
                recoverAttempt = false; // reset after second recovery attempt
              }
              throw PlatformException(
                code: kErrorValueToErrorName[2]!,
                message: errorData.type,
                details: '${errorData.details}',
              );
            }
          } catch (e) {
            logHLS('error not parsed: $e');
            _hls!.recoverMediaError();
          }
          // TODO: better communicate this error to the just_audio client
        }));
      } else {
        logHLS('Html5AudioPlayer NOT shouldUseHlsLibrary');
        _durationCompleter = Completer<dynamic>();
        audioElement.id = 'audioPlayer-$id';
        audioElement.src = src;
        audioElement.playbackRate = speed;
        audioElement.preload = 'auto';
        ui.platformViewRegistry.registerViewFactory(
          'audioPlayer-$id',
          (int viewId) => audioElement,
        );
        logHLS('Not playing HLS');
        audioElement.src = uri.toString();
        audioElement.load();
      }

      logHLS('loadUri next after hls handling');
      if (initialPosition != null) {
        logHLS('loadUri initialPosition != null');
        audioElement.currentTime = initialPosition.inMilliseconds / 1000.0;
      }
      try {
        logHLS('loadUri try _durationCompleter!.future');
        await _durationCompleter!.future;
      } on MediaError catch (e) {
        logHLS('loadUri error MediaError: $e');
        throw PlatformException(
            code: "${e.code}", message: "Failed to load URL");
      } catch (e) {
        logHLS('loadUri error unknown: $e');
      } finally {
        logHLS('loadUri finally');
        _durationCompleter = null;
      }
    }
    logHLS('loadUri 5');
    transition(ProcessingStateMessage.ready);
    logHLS('loadUri finally 6');
    final seconds = audioElement.duration;
    logHLS('loadUri finally 7');
    return seconds.isFinite
        ? Duration(milliseconds: (seconds * 1000).toInt())
        : null;
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    logHLS('Html5AudioPlayer play');
    if (playing) return PlayResponse();
    playing = true;
    await _play();
    return PlayResponse();
  }

  Future<void> _play() async {
    logHLS('Html5AudioPlayer _play');
    await _currentAudioSourcePlayer?.play();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    logHLS('Html5AudioPlayer pause');
    if (!playing) return PauseResponse();
    playing = false;
    _currentAudioSourcePlayer?.pause();
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    logHLS('Html5AudioPlayer setVolume');
    audioElement.volume = request.volume;
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    logHLS('Html5AudioPlayer setSpeed');
    audioElement.playbackRate = speed = request.speed;
    return SetSpeedResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    logHLS('Html5AudioPlayer setLoopMode');
    _loopMode = request.loopMode;
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    logHLS('Html5AudioPlayer setShuffleMode');
    _shuffleModeEnabled = request.shuffleMode == ShuffleModeMessage.all;
    return SetShuffleModeResponse();
  }

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
      SetShuffleOrderRequest request) async {
    logHLS('Html5AudioPlayer setShuffleOrder');
    void internalSetShuffleOrder(AudioSourceMessage sourceMessage) {
      final audioSourcePlayer = _audioSourcePlayers[sourceMessage.id];
      if (audioSourcePlayer == null) return;
      if (sourceMessage is ConcatenatingAudioSourceMessage &&
          audioSourcePlayer is ConcatenatingAudioSourcePlayer) {
        audioSourcePlayer.setShuffleOrder(sourceMessage.shuffleOrder);
        for (var childMessage in sourceMessage.children) {
          internalSetShuffleOrder(childMessage);
        }
      } else if (sourceMessage is LoopingAudioSourceMessage) {
        internalSetShuffleOrder(sourceMessage.child);
      }
    }

    internalSetShuffleOrder(request.audioSourceMessage);
    return SetShuffleOrderResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    logHLS('Html5AudioPlayer seek');
    await _seek(request.position?.inMilliseconds ?? 0, request.index);
    return SeekResponse();
  }

  Future<void> _seek(int position, int? newIndex) async {
    logHLS('Html5AudioPlayer _seek');
    var index = newIndex ?? this.index;
    if (_currentAudioSourcePlayer == null) {
      logHLS('Html5AudioPlayer _seek _currentAudioSourcePlayer == null');
      return;
    }
    if (index != this.index) {
      await _currentAudioSourcePlayer?.pause();
      this.index = index;
      await _currentAudioSourcePlayer?.load(position);
      if (playing) {
        await _currentAudioSourcePlayer?.play();
      }
    } else {
      await _currentAudioSourcePlayer?.seek(position);
    }
  }

  ConcatenatingAudioSourcePlayer? _concatenating(String playerId) =>
      _audioSourcePlayers[playerId] as ConcatenatingAudioSourcePlayer?;

  // todo revert?
  /*@override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    final wasNotEmpty = _audioSourcePlayer?.sequence.isNotEmpty ?? false;
    _concatenating(request.id)!.setShuffleOrder(request.shuffleOrder);
    _concatenating(request.id)!
        .insertAll(request.index, getAudioSources(request.children));
    if (_index != null && wasNotEmpty && request.index <= _index!) {
      _index = _index! + request.children.length;
    }
    await _currentAudioSourcePlayer!.load();
    broadcastPlaybackEvent();
    return ConcatenatingInsertAllResponse();
  }*/

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    final wasNotEmpty = _audioSourcePlayer?.sequence.isNotEmpty ?? false;
    _concatenating(request.id)?.setShuffleOrder(request.shuffleOrder);
    _concatenating(request.id)
        ?.insertAll(request.index, getAudioSources(request.children));
    if (index != null && wasNotEmpty && request.index <= index!) {
      index = index! + request.children.length;
    }
    await _currentAudioSourcePlayer?.load();
    broadcastPlaybackEvent();
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    logHLS('Html5AudioPlayer concatenatingRemoveRange');
    if (index != null &&
        index! >= request.startIndex &&
        index! < request.endIndex &&
        playing) {
      // Pause if removing current item
      _currentAudioSourcePlayer!.pause();
    }
    _concatenating(request.id)!.setShuffleOrder(request.shuffleOrder);
    _concatenating(request.id)!
        .removeRange(request.startIndex, request.endIndex);
    if (index != null) {
      if (index! >= request.startIndex && index! < request.endIndex) {
        // Skip backward if there's nothing after this
        if (request.startIndex >= _audioSourcePlayer!.sequence.length) {
          index = request.startIndex - 1;
          if (index! < 0) index = 0;
        } else {
          index = request.startIndex;
        }
        // Resume playback at the new item (if it exists)
        if (_currentAudioSourcePlayer != null) {
          await _currentAudioSourcePlayer!.load();
          if (playing) {
            _currentAudioSourcePlayer!.play();
          }
        }
      } else if (request.endIndex <= index!) {
        // Reflect that the current item has shifted its position
        index = index! - (request.endIndex - request.startIndex);
      }
    }
    broadcastPlaybackEvent();
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    logHLS('Html5AudioPlayer concatenatingMove');
    _concatenating(request.id)!.setShuffleOrder(request.shuffleOrder);
    _concatenating(request.id)!.move(request.currentIndex, request.newIndex);
    if (index != null) {
      if (request.currentIndex == index) {
        index = request.newIndex;
      } else if (request.currentIndex < index! && request.newIndex >= index!) {
        index = index! - 1;
      } else if (request.currentIndex > index! && request.newIndex <= index!) {
        index = index! + 1;
      }
    }
    broadcastPlaybackEvent();
    return ConcatenatingMoveResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    logHLS('Html5AudioPlayer setAndroidAudioAttributes');
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async {
    logHLS('Html5AudioPlayer setAutomaticallyWaitsToMinimizeStalling');
    return SetAutomaticallyWaitsToMinimizeStallingResponse();
  }

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest
              request) async {
    logHLS(
        'Html5AudioPlayer setCanUseNetworkResourcesForLiveStreamingWhilePaused');
    return SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
  }

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
      SetPreferredPeakBitRateRequest request) async {
    logHLS('Html5AudioPlayer setPreferredPeakBitRate');
    return SetPreferredPeakBitRateResponse();
  }

  @override
  Duration getCurrentPosition() {
    return _currentAudioSourcePlayer?.position ?? Duration.zero;
  }

  @override
  Duration getBufferedPosition() {
    return _currentAudioSourcePlayer?.bufferedPosition ?? Duration.zero;
  }

  @override
  Duration? getDuration() {
    return _currentAudioSourcePlayer?.duration;
  }

  @override
  Future<void> release() async {
    logHLS('Html5AudioPlayer release');
    _currentAudioSourcePlayer?.pause();
    audioElement.removeAttribute('src');
    audioElement.load();
    _hls?.stopLoad();
    transition(ProcessingStateMessage.idle);
    return await super.release();
  }

  /// Converts a list of audio source messages to players.
  List<AudioSourcePlayer> getAudioSources(List<AudioSourceMessage> messages) {
    logHLS('Html5AudioPlayer getAudioSourceS');
    return messages.map((message) => getAudioSource(message)).toList();
  }

  /// Converts an audio source message to a player, using the cache if it is
  /// already cached.
  AudioSourcePlayer getAudioSource(AudioSourceMessage audioSourceMessage) {
    logHLS('Html5AudioPlayer getAudioSource');
    final id = audioSourceMessage.id;
    var audioSourcePlayer = _audioSourcePlayers[id];
    if (audioSourcePlayer == null) {
      logHLS('Html5AudioPlayer getAudioSource == null');
      audioSourcePlayer = decodeAudioSource(audioSourceMessage);
      _audioSourcePlayers[id] = audioSourcePlayer;
    }
    return audioSourcePlayer;
  }

  /// Converts an audio source message to a player.
  AudioSourcePlayer decodeAudioSource(AudioSourceMessage audioSourceMessage) {
    if (audioSourceMessage is ProgressiveAudioSourceMessage) {
      logHLS(
          'Html5AudioPlayer decodeAudioSource audioSourceMessage is ${audioSourceMessage.runtimeType}');
      return ProgressiveAudioSourcePlayer(this, audioSourceMessage.id,
          Uri.parse(audioSourceMessage.uri), audioSourceMessage.headers);
    } else if (audioSourceMessage is DashAudioSourceMessage) {
      return DashAudioSourcePlayer(this, audioSourceMessage.id,
          Uri.parse(audioSourceMessage.uri), audioSourceMessage.headers);
    } else if (audioSourceMessage is HlsAudioSourceMessage) {
      return HlsAudioSourcePlayer(this, audioSourceMessage.id,
          Uri.parse(audioSourceMessage.uri), audioSourceMessage.headers);
    } else if (audioSourceMessage is ConcatenatingAudioSourceMessage) {
      return ConcatenatingAudioSourcePlayer(
          this,
          audioSourceMessage.id,
          getAudioSources(audioSourceMessage.children),
          audioSourceMessage.useLazyPreparation,
          audioSourceMessage.shuffleOrder);
    } else if (audioSourceMessage is ClippingAudioSourceMessage) {
      return ClippingAudioSourcePlayer(
          this,
          audioSourceMessage.id,
          getAudioSource(audioSourceMessage.child) as UriAudioSourcePlayer,
          audioSourceMessage.start,
          audioSourceMessage.end);
    } else if (audioSourceMessage is LoopingAudioSourceMessage) {
      return LoopingAudioSourcePlayer(this, audioSourceMessage.id,
          getAudioSource(audioSourceMessage.child), audioSourceMessage.count);
    } else {
      throw Exception("Unknown AudioSource type: $audioSourceMessage");
    }
  }
}
