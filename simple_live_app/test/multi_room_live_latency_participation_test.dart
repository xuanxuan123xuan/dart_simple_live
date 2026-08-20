import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_service.dart';

void main() {
  group('multi-room live latency participation', () {
    test('focus takes priority and enables only the focused tile', () {
      expect(
        resolveMultiRoomLiveLatencyRole(
          roomKey: 'focused',
          roomIndex: 2,
          focusedRoomKey: 'focused',
          mainSubLayoutActive: true,
        ),
        MpvLiveLatencyPlaybackRole.multiRoomPrimaryVisible,
      );
      expect(
        resolveMultiRoomLiveLatencyRole(
          roomKey: 'main',
          roomIndex: 0,
          focusedRoomKey: 'focused',
          mainSubLayoutActive: true,
        ),
        MpvLiveLatencyPlaybackRole.multiRoomSecondaryOrInactive,
      );
    });

    test('focus temporarily suspends every non-focused tile', () {
      expect(
        shouldSuspendMultiRoomPlaybackForFocus(
          roomKey: 'focused',
          focusedRoomKey: 'focused',
        ),
        isFalse,
      );
      expect(
        shouldSuspendMultiRoomPlaybackForFocus(
          roomKey: 'secondary',
          focusedRoomKey: 'focused',
        ),
        isTrue,
      );
      expect(
        shouldSuspendMultiRoomPlaybackForFocus(
          roomKey: 'secondary',
          focusedRoomKey: null,
        ),
        isFalse,
      );
    });

    test('main-sub enables only index zero when no room is focused', () {
      expect(
        resolveMultiRoomLiveLatencyRole(
          roomKey: 'main',
          roomIndex: 0,
          focusedRoomKey: null,
          mainSubLayoutActive: true,
        ),
        MpvLiveLatencyPlaybackRole.multiRoomPrimaryVisible,
      );
      expect(
        resolveMultiRoomLiveLatencyRole(
          roomKey: 'secondary',
          roomIndex: 1,
          focusedRoomKey: null,
          mainSubLayoutActive: true,
        ),
        MpvLiveLatencyPlaybackRole.multiRoomSecondaryOrInactive,
      );
    });

    test('equal grid keeps every tile disabled', () {
      for (var index = 0; index < 4; index += 1) {
        expect(
          resolveMultiRoomLiveLatencyRole(
            roomKey: 'room-$index',
            roomIndex: index,
            focusedRoomKey: null,
            mainSubLayoutActive: false,
          ),
          MpvLiveLatencyPlaybackRole.multiRoomSecondaryOrInactive,
        );
      }
    });

    test('secondary and equal-grid tiles retain health sampling only', () {
      final healthEligible = shouldSampleMultiRoomLiveHealth(
        appActive: true,
        paused: false,
        playbackDesired: true,
        liveStatus: true,
        hasActiveSource: true,
      );

      expect(healthEligible, isTrue);
      expect(
        shouldChaseMultiRoomLiveLatency(
          healthSamplingEligible: healthEligible,
          role: MpvLiveLatencyPlaybackRole.multiRoomSecondaryOrInactive,
        ),
        isFalse,
      );
    });

    test('only a health-eligible primary tile may observe and accelerate', () {
      expect(
        shouldChaseMultiRoomLiveLatency(
          healthSamplingEligible: true,
          role: MpvLiveLatencyPlaybackRole.multiRoomPrimaryVisible,
        ),
        isTrue,
      );
      expect(
        shouldChaseMultiRoomLiveLatency(
          healthSamplingEligible: false,
          role: MpvLiveLatencyPlaybackRole.multiRoomPrimaryVisible,
        ),
        isFalse,
      );
    });

    test('background, pause, and missing source stop health sampling', () {
      for (final state in <({bool appActive, bool paused, bool hasSource})>[
        (appActive: false, paused: false, hasSource: true),
        (appActive: true, paused: true, hasSource: true),
        (appActive: true, paused: false, hasSource: false),
      ]) {
        expect(
          shouldSampleMultiRoomLiveHealth(
            appActive: state.appActive,
            paused: state.paused,
            playbackDesired: true,
            liveStatus: true,
            hasActiveSource: state.hasSource,
          ),
          isFalse,
        );
      }
    });

    test('adaptive snapshots reuse the unified native sampling loop', () {
      final source = File(
        'lib/modules/multi_room/multi_room_player_controller.dart',
      ).readAsStringSync();
      final snapshotStart = source.indexOf(
        'Future<MultiRoomPlaybackTelemetry> sampleTelemetry({',
      );
      final snapshotEnd = source.indexOf(
        'Duration? _nextLiveLatencySampleDelay()',
        snapshotStart,
      );
      final snapshotMethod = source.substring(snapshotStart, snapshotEnd);
      expect(snapshotMethod, isNot(contains('_readNativeProperty(')));
      expect(snapshotMethod, isNot(contains('_liveLatencyChaser.observe(')));
      expect(snapshotMethod, contains('sampledAt: latest?.sampledAt ?? now'));

      final tickStart = source.indexOf('Future<void> _sampleLiveLatencyTick()');
      final tickEnd = source.indexOf(
        'bool _isCurrentLiveLatencySamplingContext({',
        tickStart,
      );
      final tickMethod = source.substring(tickStart, tickEnd);
      expect(
        'mpvDemuxerCacheDurationProperty'.allMatches(tickMethod),
        hasLength(1),
      );
      expect(tickMethod, contains('if (_isLiveLatencyChaseEligible)'));
      expect(tickMethod, contains('if (includeHealthTelemetry)'));
    });

    test('pause and resume native mutations preserve the latest intent', () {
      final source = File(
        'lib/modules/multi_room/multi_room_player_controller.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf('Future<void> setPaused(bool value)');
      final methodEnd = source.indexOf(
        'Future<void> togglePaused()',
        methodStart,
      );
      final method = source.substring(methodStart, methodEnd);

      expect(method, contains('final intentRevision ='));
      expect(method, contains('return _enqueue(() async {'));
      expect(
        method.indexOf('return _enqueue(() async {'),
        lessThan(method.indexOf('await _stopLiveLatencySampling(')),
      );
      expect(
        'intentRevision != _playbackIntentRevision'.allMatches(method),
        hasLength(greaterThanOrEqualTo(3)),
      );
    });
  });
}
