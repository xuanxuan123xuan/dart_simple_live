import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:video_player/video_player.dart';

class BackgroundPlaybackService {
  BackgroundPlaybackService._()
      : _channel = const MethodChannel('simple_live/background_playback'),
        _isSupported = _defaultIsSupported,
        _isOhos = _defaultIsOhos;

  @visibleForTesting
  BackgroundPlaybackService.test({
    required MethodChannel channel,
    bool supported = true,
    bool ohos = true,
  })  : _channel = channel,
        _isSupported = (() => supported),
        _isOhos = (() => ohos);

  static final BackgroundPlaybackService instance =
      BackgroundPlaybackService._();

  static bool _defaultIsSupported() => Platform.isAndroid || Utils.isOhos;
  static bool _defaultIsOhos() => Utils.isOhos;

  final MethodChannel _channel;
  final bool Function() _isSupported;
  final bool Function() _isOhos;

  bool _running = false;
  VideoPlayerController? _ohosController;
  Future<void> _transition = Future<void>.value();

  void attachOhosController(VideoPlayerController controller) {
    _ohosController = controller;
    _channel.setMethodCallHandler(_handleNativeControl);
  }

  void detachOhosController(VideoPlayerController controller) {
    if (identical(_ohosController, controller)) {
      _ohosController = null;
      // Stop routing native notification-bar play/pause events once the
      // controller is detached; leaving the handler registered would keep
      // firing _handleNativeControl even though there is nothing to control.
      _channel.setMethodCallHandler(null);
    }
  }

  Future<void> syncOhosEnabled(bool enabled) async {
    if (!_isOhos()) return;
    final controller = _ohosController;
    if (enabled && controller?.value.isPlaying == true) {
      await start();
    } else if (!enabled) {
      await stop();
    }
  }

  Future<void> _handleNativeControl(MethodCall call) async {
    final controller = _ohosController;
    if (controller == null || !controller.value.isInitialized) return;
    if (call.method == 'play') {
      await controller.play();
    } else if (call.method == 'pause') {
      await controller.pause();
    }
  }

  Future<void> start() async {
    if (!_isSupported()) {
      return;
    }
    return _enqueue(() async {
      if (_running) return;
      await _channel.invokeMethod('start');
      _running = true;
    });
  }

  Future<void> updateMetadata({
    required String assetId,
    required String siteId,
    required String roomId,
    required String title,
    required String artist,
    required String album,
    String? artwork,
  }) async {
    if (!_isOhos()) return;
    return _enqueue(() async {
      await _channel.invokeMethod('updateMetadata', {
        'assetId': assetId,
        'siteId': siteId,
        'roomId': roomId,
        'title': title,
        'artist': artist,
        'album': album,
        if (artwork != null && artwork.trim().isNotEmpty)
          'artwork': artwork.trim(),
      });
    });
  }

  Future<void> stop() async {
    if (!_isSupported()) {
      return;
    }
    return _enqueue(() async {
      if (!_running) return;
      await _channel.invokeMethod('stop');
      _running = false;
    });
  }

  Future<void> release() async {
    if (!_isOhos()) return;
    return _enqueue(() async {
      // Native release is intentionally unconditional: it also cleans up a
      // task whose successful start reply was lost during engine shutdown.
      await _channel.invokeMethod('release');
      _running = false;
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _transition = _transition.then((_) async {
      try {
        await operation();
      } catch (e) {
        Log.logPrint(e);
      }
    });
    return _transition;
  }
}
