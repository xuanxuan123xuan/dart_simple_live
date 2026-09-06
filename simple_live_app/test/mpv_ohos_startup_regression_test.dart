import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _controllerPath = 'lib/modules/live_room/player/mpv_ohos_controller.dart';
const _playerPath = 'lib/modules/live_room/player/mpv_ohos_player.dart';
const _nativePath = 'ohos/entry/src/main/cpp/mpv_napi.cpp';

String _read(String path) => File(path).readAsStringSync();

String _section(String source, String start, String end) {
  final startAt = source.indexOf(start);
  if (startAt < 0) {
    return '';
  }
  final endAt = source.indexOf(end, startAt + start.length);
  return source.substring(startAt, endAt < 0 ? source.length : endAt);
}

void main() {
  test('controller exposes a native visual-ready gate', () {
    final source = _read(_controllerPath);
    final eventHandler = _section(
      source,
      'void _handleEvent(dynamic event)',
      '  void _handleProperty',
    );
    final propertyHandler = _section(
      source,
      '  void _handleProperty',
      '  Future<void> _refreshSize',
    );
    final timePosition = _section(
      propertyHandler,
      "case 'time-pos':",
      "case 'demuxer-cache-duration':",
    );
    final coreIdle = _section(
      propertyHandler,
      "case 'core-idle':",
      "case 'paused-for-cache':",
    );
    final visualReady = _section(
      source,
      '  void _markVisualReady()',
      '  @override\n  Future<void> initialize',
    );

    expect(source, contains('bool _visualReady = false;'));
    expect(source, contains('bool get visualReady => _visualReady;'));
    expect(eventHandler, contains("name == 'video-frame-presented'"));
    expect(eventHandler, contains('_markVisualReady();'));
    expect(timePosition, isNot(contains('_visualReady')));
    expect(timePosition, isNot(contains('onFirstFrameDecoded')));
    expect(coreIdle, isNot(contains('_visualReady')));
    expect(coreIdle, isNot(contains('onFirstFrameDecoded')));

    expect(visualReady, contains('_visualReady = true;'));
    expect(visualReady, contains('notifyListeners();'));
    expect(visualReady, contains('onFirstFrameDecoded?.call();'));

    final load = _section(
      source,
      '  Future<void> mpvLoad(',
      '  /// Waits until mpv finished opening',
    );
    expect(load, contains('_visualReady = false;'));
    expect(load, contains('notifyListeners();'));
  });

  test('player rebuilds for visual state and geometry, not every heartbeat',
      () {
    final source = _read(_playerPath);
    final valueHandler = _section(
      source,
      '  void _handleValueChanged(MpvOhosVideoController controller)',
      '  void _resetPlaybackHealth()',
    );
    final rebuildInputs = _section(
      valueHandler,
      '    final shouldRebuild =',
      '    _lastRenderedSize =',
    );

    expect(source, contains('Size? _lastRenderedSize;'));
    expect(source, contains('Size? _lastRenderedSurfaceSize;'));
    expect(source, contains('bool _lastRenderedVisualReady = false;'));
    expect(source, contains('String? _lastRenderedError;'));
    expect(rebuildInputs, contains('_lastRenderedSize != value.size'));
    expect(rebuildInputs,
        contains('_lastRenderedSurfaceSize != controller.surfaceSize'));
    expect(rebuildInputs,
        contains('_lastRenderedVisualReady != controller.visualReady'));
    expect(rebuildInputs,
        contains('_lastRenderedError != value.errorDescription'));
    expect(rebuildInputs, isNot(contains('position')));
    expect(rebuildInputs, isNot(contains('isPlaying')));
    expect(rebuildInputs, isNot(contains('isBuffering')));
    expect(
      valueHandler,
      matches(RegExp(r'if \(shouldRebuild && mounted\)\s*\{\s*setState')),
    );
    expect(source, contains('controller.visualReady;'));
    expect(source, contains('Texture(textureId: controller.textureId)'));
  });

  test('native tick emits one visual-ready event for each active generation',
      () {
    final source = _read(_nativePath);
    final firstFrame = _section(
      source,
      'void TryPresentFirstFrame()',
      '\nstd::string LowerAscii',
    );
    final generation = _section(
      source,
      'int32_t ActivateNextGeneration()',
      '\nstd::string ReadPropertyString',
    );
    final tick = _section(
      source,
      'case MPV_EVENT_VIDEO_RECONFIG:',
      'case MPV_EVENT_IDLE:',
    );
    final startFile = _section(
      source,
      'case MPV_EVENT_START_FILE:',
      'case MPV_EVENT_VIDEO_RECONFIG:',
    );

    expect(source, contains('case MPV_EVENT_TICK:'));
    expect(tick, contains('TryPresentFirstFrame();'));
    expect(tick, isNot(contains('"video-frame-presented"')));

    expect(firstFrame,
        contains('const int32_t generation = g_activeGeneration.load();'));
    expect(firstFrame, contains('g_activePlayback.load()'));
    expect(firstFrame, contains('g_fileLoaded.load()'));
    expect(firstFrame, contains('g_coreIdle.load()'));
    expect(firstFrame, contains('g_videoWidth.load() < 16'));
    expect(firstFrame, contains('g_videoHeight.load() < 16'));
    // The guard must compare a frame/presentation generation before emitting,
    // then remember it so repeated ticks do not retrigger the first-frame UI.
    expect(firstFrame, contains('expected == generation'));
    expect(firstFrame, contains('g_framePresentedGeneration.load()'));
    expect(firstFrame, contains('compare_exchange_strong'));
    expect(firstFrame, contains('"video-frame-presented"'));
    expect(firstFrame, contains('QueueEvent(payload, generation)'));

    // A new active generation clears the one-shot marker before its first
    // frame, so a room switch can emit exactly one event again.
    expect(generation, contains('g_activeGeneration.store(next);'));
    expect(generation, contains('if (next != previous)'));
    expect(generation, contains('g_framePresentedGeneration.store(-1);'));

    // A load request only supplies the pending generation. It becomes active
    // when mpv confirms START_FILE, preventing late events from the old file
    // from being relabelled as the new stream.
    expect(startFile,
        contains('const int32_t generation = ActivateNextGeneration();'));
    expect(startFile, contains('g_videoWidth.store(0);'));
    expect(startFile, contains('g_videoHeight.store(0);'));
    expect(startFile, contains('g_fileLoaded.store(false);'));
    expect(startFile, contains('g_coreIdle.store(true);'));
    expect(startFile, contains('g_activePlayback.store(generation > 0);'));
  });

  test('native mpv mutations use the shared command promise queue', () {
    final source = _read(_nativePath);

    const promiseFunctionEnds = <String, String>{
      'napi_value SetGeometry': 'napi_value ReconfigureSurface',
      'napi_value ReconfigureSurface': 'napi_value SwitchSurface',
      'napi_value SwitchSurface': 'napi_value LoadFile',
      'napi_value SetPropertyString': 'napi_value GetPropertyString',
    };
    for (final entry in promiseFunctionEnds.entries) {
      final body = _section(source, entry.key, entry.value);
      expect(
        body,
        contains('CreateCommandPromise'),
        reason: '${entry.key} must use the shared command promise',
      );
    }

    final loadFile =
        _section(source, 'napi_value LoadFile', 'napi_value SetPropertyString');
    expect(
        loadFile, contains('g_latestRequestedGeneration.store(generation);'));
    expect(loadFile, contains('QueueCommand(std::move(command));'));

    final commandString =
        _section(source, 'napi_value CommandString', 'napi_value Destroy');
    expect(commandString, contains('QueueCommand(std::move(command));'));

    final commandPromise = _section(
      source,
      'napi_value CreateCommandPromise',
      '\nbool ReadStringArgument',
    );
    final asyncCommand = _section(
      source,
      'void ExecuteAsyncCommand',
      '\nvoid CompleteAsyncCommand',
    );
    expect(commandPromise, contains('ExecuteAsyncCommand'));
    expect(commandPromise, contains('napi_queue_async_work'));
    expect(commandPromise, contains('QueueCommand('));
    expect(asyncCommand, isNot(contains('QueueCommand(')));
    expect(
      source,
      matches(RegExp(r'(?:std::queue|std::deque|condition_variable|Serial)')),
    );
  });

  test('loadfile logging never passes the complete source command', () {
    final source = _read(_nativePath);
    final load =
        _section(source, 'napi_value LoadFile', 'napi_value SetPropertyString');
    final executeLoad = _section(
      source,
      'case CommandType::LOAD_FILE:',
      'case CommandType::SET_PROPERTY:',
    );
    final logCalls = RegExp(r'(?:LogMpv|OH_LOG_Print)\([^;]+\);')
        .allMatches('$load\n$executeLoad');

    for (final match in logCalls) {
      final call = match.group(0)!;
      expect(call, isNot(contains('cmd.c_str()')));
      expect(call, isNot(contains('url.c_str()')));
      expect(call, isNot(contains('headers.c_str()')));
      expect(call, isNot(contains('command.url.c_str()')));
      expect(call, isNot(contains('command.headers.c_str()')));
    }
  });
}
