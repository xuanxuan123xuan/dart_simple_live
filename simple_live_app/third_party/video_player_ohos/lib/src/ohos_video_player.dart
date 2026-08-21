// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'messages.g.dart';

/// A native HarmonyOS AVPlayer video frame has reached its texture surface.
class OhosFirstFrameEvent {
  const OhosFirstFrameEvent({required this.textureId});

  final int textureId;
}

/// Which native signal produced an [OhosPlaybackTelemetryEvent].
enum OhosPlaybackTelemetryKind {
  /// The AVPlayer clock ticked. Arrival proves the player is alive even when
  /// no position accompanies it.
  playbackTime,

  /// Read-ahead cache depth in milliseconds.
  cachedDuration,

  /// Read-ahead cache fill in the range 0..100.
  bufferingPercent,
}

/// Out-of-band playback telemetry from the native HarmonyOS AVPlayer.
///
/// [VideoEventType] is fixed by `video_player_platform_interface`, so signals
/// it has no case for travel on this side channel instead of being flattened
/// into [VideoEventType.unknown].
class OhosPlaybackTelemetryEvent {
  const OhosPlaybackTelemetryEvent({
    required this.kind,
    required this.textureId,
    this.position,
    this.cacheDuration,
    this.cachePercent,
  });

  final OhosPlaybackTelemetryKind kind;

  final int textureId;

  /// The AVPlayer clock at the time of the heartbeat.
  ///
  /// Null when AVPlayer declines to expose a timeline, which it does for some
  /// live sources. The event still arriving is itself the liveness signal, so
  /// treat a null position as "alive but unpositioned", not as a stall.
  final Duration? position;

  /// Depth of the native read-ahead cache, when reported.
  final Duration? cacheDuration;

  /// Cache fill in the range 0..100, when reported.
  final double? cachePercent;
}

/// An Android implementation of [VideoPlayerPlatform] that uses the
/// Pigeon-generated [VideoPlayerApi].
class OhosVideoPlayer extends VideoPlayerPlatform {
  static final StreamController<OhosFirstFrameEvent>
      _firstFrameEventController =
      StreamController<OhosFirstFrameEvent>.broadcast(sync: true);

  /// Native first-frame notifications for HarmonyOS texture players.
  static Stream<OhosFirstFrameEvent> get firstFrameEvents =>
      _firstFrameEventController.stream;

  static final StreamController<OhosPlaybackTelemetryEvent>
      _playbackTelemetryController =
      StreamController<OhosPlaybackTelemetryEvent>.broadcast(sync: true);

  /// Native playback heartbeat and cache telemetry for HarmonyOS players.
  static Stream<OhosPlaybackTelemetryEvent> get playbackTelemetryEvents =>
      _playbackTelemetryController.stream;

  final OhosVideoPlayerApi _api = OhosVideoPlayerApi();

  /// Registers this class as the default instance of [PathProviderPlatform].
  static void registerWith() {
    VideoPlayerPlatform.instance = OhosVideoPlayer();
  }

  @override
  Future<void> init() {
    return _api.initialize();
  }

  @override
  Future<void> dispose(int textureId) {
    return _api.dispose(TextureMessage(textureId: textureId));
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    String? asset;
    String? packageName;
    String? uri;
    String? formatHint;
    Map<String, String> httpHeaders = <String, String>{};
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        asset = dataSource.asset;
        packageName = dataSource.package;
        break;
      case DataSourceType.network:
        uri = dataSource.uri;
        formatHint = _videoFormatStringMap[dataSource.formatHint];
        httpHeaders = dataSource.httpHeaders;
        break;
      case DataSourceType.file:
        uri = dataSource.uri;
        httpHeaders = dataSource.httpHeaders;
        break;
      case DataSourceType.contentUri:
        uri = dataSource.uri;
        break;
    }
    final CreateMessage message = CreateMessage(
      asset: asset,
      packageName: packageName,
      uri: uri,
      httpHeaders: httpHeaders,
      formatHint: formatHint,
    );

    final TextureMessage response = await _api.create(message);
    return response.textureId;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) {
    return _api.setLooping(LoopingMessage(
      textureId: textureId,
      isLooping: looping,
    ));
  }

  @override
  Future<void> play(int textureId) {
    return _api.play(TextureMessage(textureId: textureId));
  }

  @override
  Future<void> pause(int textureId) {
    return _api.pause(TextureMessage(textureId: textureId));
  }

  @override
  Future<void> setVolume(int textureId, double volume) {
    return _api.setVolume(VolumeMessage(
      textureId: textureId,
      volume: volume,
    ));
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) {
    assert(speed > 0);

    return _api.setPlaybackSpeed(PlaybackSpeedMessage(
      textureId: textureId,
      speed: speed,
    ));
  }

  @override
  Future<void> seekTo(int textureId, Duration position) {
    return _api.seekTo(PositionMessage(
      textureId: textureId,
      position: position.inMilliseconds,
    ));
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    final PositionMessage response =
        await _api.position(TextureMessage(textureId: textureId));
    return Duration(milliseconds: response.position);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _eventChannelFor(textureId)
        .receiveBroadcastStream()
        .map((dynamic event) {
      final Map<dynamic, dynamic> map = event as Map<dynamic, dynamic>;
      switch (map['event']) {
        case 'initialized':
          return VideoEvent(
            eventType: VideoEventType.initialized,
            duration: Duration(milliseconds: map['duration'] as int),
            size: Size((map['width'] as num?)?.toDouble() ?? 0.0,
                (map['height'] as num?)?.toDouble() ?? 0.0),
            rotationCorrection: map['rotationCorrection'] as int? ?? 0,
          );
        case 'completed':
          return VideoEvent(
            eventType: VideoEventType.completed,
          );
        case 'bufferingUpdate':
          final List<dynamic> values = map['values'] as List<dynamic>;

          return VideoEvent(
            buffered: values.map<DurationRange>(_toDurationRange).toList(),
            eventType: VideoEventType.bufferingUpdate,
          );
        case 'bufferingStart':
          return VideoEvent(eventType: VideoEventType.bufferingStart);
        case 'bufferingEnd':
          return VideoEvent(eventType: VideoEventType.bufferingEnd);
        case 'isPlayingStateUpdate':
          return VideoEvent(
            eventType: VideoEventType.isPlayingStateUpdate,
            isPlaying: map['isPlaying'] as bool,
          );
        case 'firstFrame':
          _firstFrameEventController.add(
            OhosFirstFrameEvent(textureId: map['textureId'] as int),
          );
          return VideoEvent(eventType: VideoEventType.unknown);
        case 'playbackTime':
          final int timeMs = (map['timeMs'] as num?)?.toInt() ?? -1;
          _playbackTelemetryController.add(
            OhosPlaybackTelemetryEvent(
              kind: OhosPlaybackTelemetryKind.playbackTime,
              textureId: map['textureId'] as int,
              // AVPlayer uses -1 for "no timeline available".
              position: timeMs >= 0 ? Duration(milliseconds: timeMs) : null,
            ),
          );
          return VideoEvent(eventType: VideoEventType.unknown);
        case 'cachedDuration':
          final int durationMs = (map['durationMs'] as num?)?.toInt() ?? -1;
          _playbackTelemetryController.add(
            OhosPlaybackTelemetryEvent(
              kind: OhosPlaybackTelemetryKind.cachedDuration,
              textureId: map['textureId'] as int,
              cacheDuration:
                  durationMs >= 0 ? Duration(milliseconds: durationMs) : null,
            ),
          );
          return VideoEvent(eventType: VideoEventType.unknown);
        case 'bufferingPercent':
          final double? percent = (map['percent'] as num?)?.toDouble();
          _playbackTelemetryController.add(
            OhosPlaybackTelemetryEvent(
              kind: OhosPlaybackTelemetryKind.bufferingPercent,
              textureId: map['textureId'] as int,
              cachePercent: percent,
            ),
          );
          return VideoEvent(eventType: VideoEventType.unknown);
        default:
          return VideoEvent(eventType: VideoEventType.unknown);
      }
    });
  }

  @override
  Widget buildView(int textureId) {
    return Texture(textureId: textureId);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) {
    return _api
        .setMixWithOthers(MixWithOthersMessage(mixWithOthers: mixWithOthers));
  }

  EventChannel _eventChannelFor(int textureId) {
    return EventChannel('flutter.io/videoPlayer/videoEvents$textureId');
  }

  static const Map<VideoFormat, String> _videoFormatStringMap =
      <VideoFormat, String>{
    VideoFormat.ss: 'ss',
    VideoFormat.hls: 'hls',
    VideoFormat.dash: 'dash',
    VideoFormat.other: 'other',
  };

  DurationRange _toDurationRange(dynamic value) {
    final List<dynamic> pair = value as List<dynamic>;
    return DurationRange(
      Duration(milliseconds: pair[0] as int),
      Duration(milliseconds: pair[1] as int),
    );
  }
}
