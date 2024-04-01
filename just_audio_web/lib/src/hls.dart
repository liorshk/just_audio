@JS()
library hls.js;

import 'dart:html';

import 'package:js/js.dart';

@JS('Hls.isSupported')
external bool isSupported();

@JS()
class Hls {
  external factory Hls(HlsConfig config);

  @JS()
  external void stopLoad();

  @JS()
  external void destroy();

  @JS()
  external void recoverMediaError();

  @JS()
  external void swapAudioCodec();

  @JS()
  external void loadSource(String videoSrc);

  @JS()
  external set currentLevel(int level);

  @JS()
  external int get currentLevel;

  @JS()
  external void attachMedia(AudioElement video);

  @JS()
  external void detachMedia();

  @JS()
  external void on(String event, Function callback);

  external HlsConfig config;
}

@JS()
@anonymous
class HlsConfig {
  @JS()
  external Function get xhrSetup;

  @JS()
  external bool debug;

  @JS()
  external bool enableWorker;

  @JS()
  external int appendErrorMaxRetry;

  @JS()
  external bool progressive;

  @JS()
  external bool lowLatencyMode;

  external factory HlsConfig({
    Function xhrSetup,
    bool debug,
    bool enableWorker,
    bool progressive,
    int backBufferLength,
    int appendErrorMaxRetry,
    bool lowLatencyMode,
  });
}

class ErrorData {
  late final String? details;
  late final String? type;
  late final bool fatal;

  ErrorData.from(dynamic jsObj) {
    fatal = (() {
      try {
        return jsObj.fatal as bool;
      } catch (e) {
        return false;
      }
    }());

    details = (() {
      try {
        return jsObj.details as String;
      } catch (e) {
        return null;
      }
    }());

    type = (() {
      try {
        return jsObj.type as String;
      } catch (e) {
        return null;
      }
    }());
  }

  @override
  String toString() {
    return 'ErrorData{\n details: $details, \ntype: $type, \nfatal: $fatal\n}';
  }
}
