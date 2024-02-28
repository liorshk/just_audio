import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'src/base_just_audio_player.dart';
import 'src/html5_audio_player.dart';

/// The web implementation of [JustAudioPlatform].
class JustAudioPlugin extends JustAudioPlatform {
  final Map<String, JustAudioPlayer> players = {};

  /// The entrypoint called by the generated plugin registrant.
  static void registerWith(Registrar registrar) {
    JustAudioPlatform.instance = JustAudioPlugin();
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (players.containsKey(request.id)) {
      throw PlatformException(
          code: "error",
          message: "Platform player ${request.id} already exists");
    }
    final player = Html5AudioPlayer(id: request.id);
    players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    await players[request.id]?.release();
    players.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    for (var player in players.values) {
      await player.release();
    }
    players.clear();
    return DisposeAllPlayersResponse();
  }
}
