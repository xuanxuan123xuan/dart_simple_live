import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_adaptive_quality.dart';

MultiRoomPlaybackTelemetry sample({
  required String key,
  required DateTime at,
  int bufferingCount = 0,
  Duration bufferingDuration = Duration.zero,
  bool buffering = false,
  bool paused = false,
  int qualityIndex = 0,
  int qualityCount = 3,
  int? userTarget = 0,
  double? bandwidth,
  bool locked = false,
  bool primary = false,
  bool focused = false,
  bool chat = false,
  DateTime? lastOpenedAt,
}) {
  return MultiRoomPlaybackTelemetry(
    roomKey: key,
    sampledAt: at,
    paused: paused,
    isBuffering: buffering,
    bufferingCount: bufferingCount,
    bufferingDuration: bufferingDuration,
    qualityIndex: qualityIndex,
    qualityCount: qualityCount,
    userTargetQualityIndex: userTarget,
    bandwidthBytesPerSecond: bandwidth,
    isQualityLocked: locked,
    isPrimary: primary,
    isFocused: focused,
    isChatTarget: chat,
    lastOpenedAt: lastOpenedAt,
  );
}

void main() {
  test('parses finite native telemetry properties', () {
    final parsed = parseMpvTelemetryProperties({
      mpvCacheSpeedProperty: ' 1250000.5 ',
      mpvVideoWidthProperty: '1920',
      mpvVideoHeightProperty: '1080',
      mpvEstimatedFpsProperty: '29.97003',
    });

    expect(parsed.bandwidthBytesPerSecond, 1250000.5);
    expect(parsed.width, 1920);
    expect(parsed.height, 1080);
    expect(parsed.framesPerSecond, 29.97003);
  });

  test('keeps unavailable or malformed native properties unknown', () {
    final parsed = parseMpvTelemetryProperties({
      mpvCacheSpeedProperty: 'NaN',
      mpvVideoWidthProperty: '0',
      mpvVideoHeightProperty: 'N/A',
      mpvEstimatedFpsProperty: 'Infinity',
    });

    expect(parsed.bandwidthBytesPerSecond, isNull);
    expect(parsed.width, isNull);
    expect(parsed.height, isNull);
    expect(parsed.framesPerSecond, isNull);

    final zeroBandwidth = parseMpvTelemetryProperties({
      mpvCacheSpeedProperty: '0',
    });
    expect(zeroBandwidth.bandwidthBytesPerSecond, 0);
  });

  test('unknown bandwidth remains unknown and buffering can degrade', () {
    final policy = MultiRoomAdaptiveQualityController();
    final start = DateTime(2026);

    var decision = policy.evaluate(
      now: start,
      rooms: [sample(key: 'a', at: start)],
      logicalProcessorCount: 8,
      bandwidthBudgetBytesPerSecond: 1000,
    );
    expect(decision.bandwidthKnown, isFalse);
    expect(decision.totalBandwidthBytesPerSecond, isNull);
    expect(decision.action, isNull);

    final pressureAt = start.add(const Duration(seconds: 5));
    decision = policy.evaluate(
      now: pressureAt,
      rooms: [
        sample(
          key: 'a',
          at: pressureAt,
          bufferingCount: 1,
          bufferingDuration: const Duration(seconds: 2),
        ),
      ],
      logicalProcessorCount: 8,
    );
    expect(decision.pressureScore, greaterThanOrEqualTo(55));

    final degradeAt = start.add(const Duration(seconds: 15));
    decision = policy.evaluate(
      now: degradeAt,
      rooms: [
        sample(
          key: 'a',
          at: degradeAt,
          bufferingCount: 1,
          bufferingDuration: const Duration(seconds: 2),
        ),
      ],
      logicalProcessorCount: 8,
    );
    expect(decision.action?.type, MultiRoomQualityActionType.degrade);
    expect(decision.action?.targetQualityIndex, 1);
  });

  test('known total bandwidth pressure degrades an unprotected room', () {
    final policy = MultiRoomAdaptiveQualityController();
    final start = DateTime(2026);
    final rooms = [
      sample(key: 'primary', at: start, bandwidth: 800, primary: true),
      sample(key: 'ordinary', at: start, bandwidth: 800),
    ];

    final initial = policy.evaluate(
      now: start,
      rooms: rooms,
      logicalProcessorCount: 8,
      bandwidthBudgetBytesPerSecond: 1000,
    );
    expect(initial.bandwidthKnown, isTrue);
    expect(initial.totalBandwidthBytesPerSecond, 1600);
    expect(initial.pressureScore, 100);
    expect(initial.action, isNull);

    final actionAt = start.add(const Duration(seconds: 10));
    final decision = policy.evaluate(
      now: actionAt,
      rooms: [
        sample(key: 'primary', at: actionAt, bandwidth: 800, primary: true),
        sample(key: 'ordinary', at: actionAt, bandwidth: 800),
      ],
      logicalProcessorCount: 8,
      bandwidthBudgetBytesPerSecond: 1000,
    );
    expect(decision.action?.roomKey, 'ordinary');
    expect(decision.action?.reason, 'pressure');
  });

  test('memory emergency overrides lock and protects primary room', () {
    final policy = MultiRoomAdaptiveQualityController();
    final now = DateTime(2026);
    final decision = policy.evaluate(
      now: now,
      rooms: [
        sample(key: 'primary', at: now, primary: true),
        sample(key: 'ordinary', at: now, locked: true),
      ],
      logicalProcessorCount: 8,
      memoryEmergency: true,
    );

    expect(decision.action?.roomKey, 'ordinary');
    expect(decision.action?.targetQualityIndex, 2);
    expect(decision.action?.reason, 'memory');
  });

  test('buffering during stream warmup is ignored', () {
    final policy = MultiRoomAdaptiveQualityController();
    final start = DateTime(2026);
    policy.evaluate(
      now: start,
      rooms: [sample(key: 'a', at: start, lastOpenedAt: start)],
      logicalProcessorCount: 8,
    );

    final duringWarmup = start.add(const Duration(seconds: 5));
    final warmupDecision = policy.evaluate(
      now: duringWarmup,
      rooms: [
        sample(
          key: 'a',
          at: duringWarmup,
          bufferingCount: 1,
          bufferingDuration: const Duration(seconds: 2),
          lastOpenedAt: start,
        ),
      ],
      logicalProcessorCount: 8,
    );
    expect(warmupDecision.pressureScore, 0);

    final afterWarmup = start.add(const Duration(seconds: 10));
    final afterWarmupDecision = policy.evaluate(
      now: afterWarmup,
      rooms: [
        sample(
          key: 'a',
          at: afterWarmup,
          bufferingCount: 1,
          bufferingDuration: const Duration(seconds: 2),
          lastOpenedAt: start,
        ),
      ],
      logicalProcessorCount: 8,
    );
    expect(afterWarmupDecision.pressureScore, 0);
  });

  test('paused rooms are excluded from bandwidth and adjustment', () {
    final policy = MultiRoomAdaptiveQualityController();
    final now = DateTime(2026);
    final decision = policy.evaluate(
      now: now,
      rooms: [
        sample(key: 'paused', at: now, paused: true, bandwidth: 900),
        sample(key: 'playing', at: now, bandwidth: 100),
      ],
      logicalProcessorCount: 8,
      memoryEmergency: true,
    );

    expect(decision.bandwidthKnown, isTrue);
    expect(decision.totalBandwidthBytesPerSecond, 100);
    expect(decision.action?.roomKey, 'playing');
  });

  test('stable playback restores protected room one level', () {
    final policy = MultiRoomAdaptiveQualityController();
    final start = DateTime(2026);
    policy.evaluate(
      now: start,
      rooms: [
        sample(
          key: 'primary',
          at: start,
          qualityIndex: 2,
          primary: true,
        ),
        sample(key: 'ordinary', at: start, qualityIndex: 2),
      ],
      logicalProcessorCount: 8,
    );

    final stableAt = start.add(const Duration(seconds: 90));
    final decision = policy.evaluate(
      now: stableAt,
      rooms: [
        sample(
          key: 'primary',
          at: stableAt,
          qualityIndex: 2,
          primary: true,
        ),
        sample(key: 'ordinary', at: stableAt, qualityIndex: 2),
      ],
      logicalProcessorCount: 8,
    );

    expect(decision.action?.type, MultiRoomQualityActionType.restore);
    expect(decision.action?.roomKey, 'primary');
    expect(decision.action?.targetQualityIndex, 1);
  });
}
