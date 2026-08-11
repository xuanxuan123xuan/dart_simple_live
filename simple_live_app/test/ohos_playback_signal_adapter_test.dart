import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_playback_signal_adapter.dart';
import 'package:video_player/video_player.dart';

VideoPlayerValue _value({
  bool initialized = true,
  bool playing = false,
  bool buffering = false,
  Duration position = Duration.zero,
  String? error,
}) {
  return VideoPlayerValue(
    duration: Duration.zero,
    isInitialized: initialized,
    isPlaying: playing,
    isBuffering: buffering,
    position: position,
    errorDescription: error,
  );
}

void main() {
  test('rejects stale room and player generations', () {
    final adapter = OhosPlaybackSignalAdapter();
    adapter.beginSource(
      roomGeneration: 3,
      playerGeneration: 7,
      source: 'https://cdn.example/live.flv?token=secret',
    );

    expect(
      adapter.update(
        roomGeneration: 2,
        playerGeneration: 7,
        value: _value(playing: true),
      ),
      isEmpty,
    );
    expect(
      adapter.update(
        roomGeneration: 3,
        playerGeneration: 6,
        value: _value(playing: true),
      ),
      isEmpty,
    );
  });

  test('emits buffering edges and first frame once', () {
    final adapter = OhosPlaybackSignalAdapter();
    adapter.beginSource(
      roomGeneration: 1,
      playerGeneration: 1,
      source: 'https://cdn.example/live.flv',
    );

    final buffering = adapter.update(
      roomGeneration: 1,
      playerGeneration: 1,
      value: _value(buffering: true),
    );
    expect(
      buffering.map((signal) => signal.type),
      containsAll([
        OhosPlaybackSignalType.initialized,
        OhosPlaybackSignalType.bufferingStarted,
      ]),
    );

    final playing = adapter.update(
      roomGeneration: 1,
      playerGeneration: 1,
      value: _value(
        playing: true,
        position: const Duration(milliseconds: 40),
      ),
    );
    expect(
      playing.map((signal) => signal.type),
      containsAll([
        OhosPlaybackSignalType.bufferingEnded,
        OhosPlaybackSignalType.playing,
        OhosPlaybackSignalType.positionAdvanced,
        OhosPlaybackSignalType.firstFrame,
      ]),
    );

    final next = adapter.update(
      roomGeneration: 1,
      playerGeneration: 1,
      value: _value(
        playing: true,
        position: const Duration(milliseconds: 80),
      ),
    );
    expect(
      next.where((signal) => signal.type == OhosPlaybackSignalType.firstFrame),
      isEmpty,
    );
  });

  test('fingerprint excludes query credentials and errors are sanitized', () {
    final first = fingerprintOhosPlaybackSource(
      'https://cdn.example/live.flv?token=one',
    );
    final second = fingerprintOhosPlaybackSource(
      'https://cdn.example/live.flv?token=two',
    );

    expect(first, second);
    expect(first, isNot(contains('cdn.example')));
    expect(
      sanitizeOhosNativeError(
        'failed https://cdn.example/live.flv?token=secret code 5400102',
      ),
      '5400102',
    );
  });

  test('reports unsupported OHOS metrics explicitly', () {
    const metrics = OhosPlaybackSupportedMetrics();
    expect(metrics.cacheDepth, isFalse);
    expect(metrics.throughput, isFalse);
    expect(metrics.audioUnderrun, isFalse);
    expect(metrics.position, isTrue);
  });
}
