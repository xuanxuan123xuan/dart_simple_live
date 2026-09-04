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
      "case 'demuxer-cache-time':",
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
    expect(source, contains('bool _lastRenderedVisualReady = false;'));
    expect(source, contains('String? _lastRenderedError;'));
    expect(rebuildInputs, contains('_lastRenderedSize != value.size'));
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
    final params = _section(
      source,
      'if (prop->name == std::string("video-out-params"))',
      'if (prop->name == std::string("time-pos") ||',
    );
    final tick = _section(
      source,
      'case MPV_EVENT_TICK:',
      'case MPV_EVENT_LOG_MESSAGE:',
    );
    final startFile = _section(
      source,
      'case MPV_EVENT_START_FILE:',
      'case MPV_EVENT_IDLE:',
    );

    expect(source, contains('case MPV_EVENT_TICK:'));
    expect(tick, contains('"video-frame-presented"'));
    expect(tick, contains('QueueEvent'));
    // The guard must compare a frame/presentation generation before emitting,
    // then remember it so repeated ticks do not retrigger the first-frame UI.
    expect(tick, contains('expected == generation'));
    expect(tick, contains('compare_exchange_strong'));
    final paramsGeneration = RegExp(
      r'\bg_[A-Za-z0-9_]*(?:[Vv]ideo|[Oo]ut)[A-Za-z0-9_]*[Gg]eneration\b',
    ).firstMatch(params)?.group(0);
    expect(paramsGeneration, isNotNull);
    expect(params, matches(RegExp(r'\bdw\s*>\s*0')));
    expect(params, matches(RegExp(r'\bdh\s*>\s*0')));
    expect(params, contains('$paramsGeneration.store'));
    expect(tick, contains(paramsGeneration!));
    expect(
      tick,
      matches(RegExp(
        '${RegExp.escape(paramsGeneration)}[^;\\n]*(?:!=|==)[^;\\n]*generation',
      )),
    );
    expect(
      tick,
      matches(
          RegExp(r'(?:frame|present)[A-Za-z_]*Generation[^\n]*(?:=|store)')),
    );

    // A load request only supplies the pending generation. It becomes active
    // when mpv confirms START_FILE, preventing late events from the old file
    // from being relabelled as the new stream.
    expect(startFile, contains('Generation'));
    expect(
      startFile,
      matches(
          RegExp(r'(?:store|exchange|=|\+=)[^;\n]*(?:Generation|generation)')),
    );
  });

  test('initial geometry reconfiguration bypasses the startup debounce', () {
    final source = _read(_controllerPath);
    final geometry = _section(
      source,
      '  Future<void> _applyGeometryChange(String sizeText)',
      '  Future<void> _runGeometryReconfig()',
    );
    final pendingGeometry = geometry.indexOf('_pendingGeometry = displaySize;');
    final immediateReconfig = geometry.indexOf('_runGeometryReconfig()');

    expect(pendingGeometry, greaterThanOrEqualTo(0));
    expect(immediateReconfig, greaterThan(pendingGeometry));
    expect(
      geometry,
      isNot(contains('Timer(const Duration(milliseconds: 300))')),
    );

    // These timers belong to the first-frame and playback-health watchdogs;
    // the assertion above is deliberately limited to geometry handling.
    expect(source, contains('_firstFrameTimer = Timer('));
    expect(source, contains('_watchdogTimer = Timer.periodic('));
  });

  test('native mpv mutations share one serial queue', () {
    final source = _read(_nativePath);

    for (final declaration in const [
      'napi_value SetGeometry',
      'napi_value LoadFile',
      'napi_value SetPropertyString',
      'napi_value CommandString',
    ]) {
      final body = _section(source, declaration, 'napi_value ');
      expect(
        body,
        contains('QueueCommand'),
        reason: '$declaration must enqueue onto the shared mpv queue',
      );
    }

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

  test('stable and low-latency profiles share the audio sync baseline', () {
    final native = _read(_nativePath);
    final controller = _read(_controllerPath);
    final profile = _section(
      controller,
      '  Future<void> applyPlaybackProfile',
      '  /// Applies the user\'s own mpv tweaks',
    );
    final lowLatencyBody = _section(profile, 'if (lowLatency) {', '\n    }');

    expect(native, contains('"video-sync"'));
    expect(native, contains('"audio"'));
    expect(native, contains('"initial-audio-sync"'));
    expect(native, contains('"yes"'));
    expect(profile, contains('if (lowLatency)'));
    expect(profile, contains("'video-sync'"));
    expect(profile, contains("'initial-audio-sync'"));
    expect(lowLatencyBody, isNot(contains("'video-sync'")));
    expect(lowLatencyBody, isNot(contains("'initial-audio-sync'")));
  });
}
