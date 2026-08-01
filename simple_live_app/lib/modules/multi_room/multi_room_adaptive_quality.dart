import 'dart:math' as math;

const mpvCacheSpeedProperty = 'cache-speed';
const mpvVideoWidthProperty = 'video-params/w';
const mpvVideoHeightProperty = 'video-params/h';
const mpvEstimatedFpsProperty = 'estimated-vf-fps';

class MultiRoomNativeTelemetryProperties {
  const MultiRoomNativeTelemetryProperties({
    this.bandwidthBytesPerSecond,
    this.width,
    this.height,
    this.framesPerSecond,
  });

  final double? bandwidthBytesPerSecond;
  final int? width;
  final int? height;
  final double? framesPerSecond;
}

/// Parses the string values returned by libmpv. Unsupported properties often
/// return an empty string or `N/A`; malformed and non-finite values remain
/// unknown instead of being converted to zero.
MultiRoomNativeTelemetryProperties parseMpvTelemetryProperties(
  Map<String, String?> properties,
) {
  return MultiRoomNativeTelemetryProperties(
    bandwidthBytesPerSecond: _parseNonNegativeFiniteDouble(
      properties[mpvCacheSpeedProperty],
    ),
    width: _parsePositiveInt(properties[mpvVideoWidthProperty]),
    height: _parsePositiveInt(properties[mpvVideoHeightProperty]),
    framesPerSecond: _parsePositiveFiniteDouble(
      properties[mpvEstimatedFpsProperty],
    ),
  );
}

double? _parseNonNegativeFiniteDouble(String? raw) {
  final value = double.tryParse(raw?.trim() ?? '');
  return value != null && value.isFinite && value >= 0 ? value : null;
}

double? _parsePositiveFiniteDouble(String? raw) {
  final value = double.tryParse(raw?.trim() ?? '');
  return value != null && value.isFinite && value > 0 ? value : null;
}

int? _parsePositiveInt(String? raw) {
  final value = int.tryParse(raw?.trim() ?? '');
  return value != null && value > 0 ? value : null;
}

/// One player's cumulative playback telemetry at [sampledAt].
///
/// A null [bandwidthBytesPerSecond] means the backend cannot expose a rate.
/// It must never be interpreted as zero bandwidth.
class MultiRoomPlaybackTelemetry {
  const MultiRoomPlaybackTelemetry({
    required this.roomKey,
    required this.sampledAt,
    required this.paused,
    required this.isBuffering,
    required this.bufferingCount,
    required this.bufferingDuration,
    required this.qualityIndex,
    required this.qualityCount,
    this.userTargetQualityIndex,
    this.bandwidthBytesPerSecond,
    this.width,
    this.height,
    this.framesPerSecond,
    this.lastOpenedAt,
    this.isQualityLocked = false,
    this.isPrimary = false,
    this.isFocused = false,
    this.isChatTarget = false,
  });

  final String roomKey;
  final DateTime sampledAt;
  final bool paused;
  final bool isBuffering;
  final int bufferingCount;
  final Duration bufferingDuration;
  final int qualityIndex;
  final int qualityCount;
  final int? userTargetQualityIndex;
  final double? bandwidthBytesPerSecond;
  final int? width;
  final int? height;
  final double? framesPerSecond;
  final DateTime? lastOpenedAt;
  final bool isQualityLocked;
  final bool isPrimary;
  final bool isFocused;
  final bool isChatTarget;

  bool isInWarmup(DateTime now, Duration warmup) {
    final openedAt = lastOpenedAt;
    return openedAt != null && now.difference(openedAt) < warmup;
  }
}

enum MultiRoomQualityActionType { degrade, restore }

class MultiRoomQualityAction {
  const MultiRoomQualityAction({
    required this.roomKey,
    required this.type,
    required this.targetQualityIndex,
    required this.reason,
  });

  final String roomKey;
  final MultiRoomQualityActionType type;
  final int targetQualityIndex;
  final String reason;
}

class MultiRoomAdaptiveDecision {
  const MultiRoomAdaptiveDecision({
    required this.pressureScore,
    required this.bandwidthKnown,
    required this.totalBandwidthBytesPerSecond,
    this.action,
  });

  final double pressureScore;
  final bool bandwidthKnown;
  final double? totalBandwidthBytesPerSecond;
  final MultiRoomQualityAction? action;
}

/// Stateful, timer-free adaptive quality policy.
///
/// The page supplies a sample about every five seconds. Keeping time outside
/// this class makes the hysteresis and priority rules deterministic in tests.
class MultiRoomAdaptiveQualityController {
  MultiRoomAdaptiveQualityController({
    this.window = const Duration(seconds: 30),
    this.warmup = const Duration(seconds: 8),
    this.pressureHold = const Duration(seconds: 10),
    this.stableHold = const Duration(seconds: 90),
    this.degradeCooldown = const Duration(seconds: 30),
    this.restoreCooldown = const Duration(seconds: 120),
    this.perRoomAdjustmentInterval = const Duration(seconds: 15),
  });

  final Duration window;
  final Duration warmup;
  final Duration pressureHold;
  final Duration stableHold;
  final Duration degradeCooldown;
  final Duration restoreCooldown;
  final Duration perRoomAdjustmentInterval;

  final Map<String, List<MultiRoomPlaybackTelemetry>> _history = {};
  final Map<String, DateTime> _lastRoomAdjustment = {};
  DateTime? _pressureSince;
  DateTime? _stableSince;
  DateTime? _lastDegradeAt;
  DateTime? _lastRestoreAt;

  void reset() {
    _history.clear();
    _lastRoomAdjustment.clear();
    _pressureSince = null;
    _stableSince = null;
    _lastDegradeAt = null;
    _lastRestoreAt = null;
  }

  MultiRoomAdaptiveDecision evaluate({
    required DateTime now,
    required List<MultiRoomPlaybackTelemetry> rooms,
    required int logicalProcessorCount,
    bool memoryEmergency = false,
    double? rssBytes,
    double? rssBudgetBytes,
    double? bandwidthBudgetBytesPerSecond,
  }) {
    final activeKeys = rooms.map((room) => room.roomKey).toSet();
    _history.removeWhere((key, _) => !activeKeys.contains(key));
    for (final room in rooms) {
      final samples = _history.putIfAbsent(room.roomKey, () => []);
      samples.add(room);
      samples
          .removeWhere((sample) => now.difference(sample.sampledAt) > window);
    }

    final active = rooms.where((room) => !room.paused).toList();
    final bandwidthKnown = active.isNotEmpty &&
        active.every((room) => room.bandwidthBytesPerSecond != null);
    final totalBandwidth = bandwidthKnown
        ? active.fold<double>(
            0,
            (sum, room) => sum + room.bandwidthBytesPerSecond!,
          )
        : null;

    var networkPressure = 0.0;
    if (totalBandwidth != null &&
        bandwidthBudgetBytesPerSecond != null &&
        bandwidthBudgetBytesPerSecond > 0) {
      networkPressure = totalBandwidth / bandwidthBudgetBytesPerSecond * 100;
    }
    final bufferingPressure = _bufferingPressure(now, active);
    final memoryPressure =
        rssBytes != null && rssBudgetBytes != null && rssBudgetBytes > 0
            ? rssBytes / rssBudgetBytes * 100
            : 0.0;
    final decodePressure = _decodePressure(active, logicalProcessorCount);
    final pressure = memoryEmergency
        ? 100.0
        : math.max(
            math.max(networkPressure, bufferingPressure),
            math.max(memoryPressure, decodePressure),
          );

    if (pressure >= 55) {
      _pressureSince ??= now;
      _stableSince = null;
    } else if (pressure <= 10 && !_hasRecentBuffering(now, active)) {
      _stableSince ??= now;
      _pressureSince = null;
    } else {
      _pressureSince = null;
      _stableSince = null;
    }

    MultiRoomQualityAction? action;
    if (memoryEmergency) {
      action = _selectDegrade(now, active, memoryEmergency: true);
    } else if (_pressureSince != null &&
        now.difference(_pressureSince!) >= pressureHold &&
        (_lastDegradeAt == null ||
            now.difference(_lastDegradeAt!) >= degradeCooldown)) {
      action = _selectDegrade(now, active, memoryEmergency: false);
    } else if (_stableSince != null &&
        now.difference(_stableSince!) >= stableHold &&
        (_lastRestoreAt == null ||
            now.difference(_lastRestoreAt!) >= restoreCooldown)) {
      action = _selectRestore(now, active);
    }

    if (action != null) {
      _lastRoomAdjustment[action.roomKey] = now;
      if (action.type == MultiRoomQualityActionType.degrade) {
        _lastDegradeAt = now;
        _pressureSince = null;
      } else {
        _lastRestoreAt = now;
        _stableSince = null;
      }
    }

    return MultiRoomAdaptiveDecision(
      pressureScore: pressure.clamp(0, 100).toDouble(),
      bandwidthKnown: bandwidthKnown,
      totalBandwidthBytesPerSecond: totalBandwidth,
      action: action,
    );
  }

  double _bufferingPressure(
    DateTime now,
    List<MultiRoomPlaybackTelemetry> rooms,
  ) {
    var score = 0.0;
    for (final room in rooms) {
      if (room.isInWarmup(now, warmup)) continue;
      final samples = _history[room.roomKey];
      final eligible = samples?.where((sample) {
        final openedAt = sample.lastOpenedAt;
        return openedAt == null ||
            sample.sampledAt.difference(openedAt) >= warmup;
      }).toList();
      if (eligible == null || eligible.length < 2) continue;
      final first = eligible.first;
      final last = eligible.last;
      final count = last.bufferingCount - first.bufferingCount;
      final buffered = last.bufferingDuration - first.bufferingDuration;
      final elapsed = last.sampledAt.difference(first.sampledAt);
      if (count > 0) score = math.max(score, 55 + math.min(count * 10, 30));
      if (elapsed > Duration.zero) {
        score = math.max(
          score,
          buffered.inMilliseconds / elapsed.inMilliseconds * 100,
        );
      }
      if (last.isBuffering) score = math.max(score, 70);
    }
    return score;
  }

  bool _hasRecentBuffering(
    DateTime now,
    List<MultiRoomPlaybackTelemetry> rooms,
  ) {
    for (final room in rooms) {
      if (room.isInWarmup(now, warmup)) continue;
      final samples = _history[room.roomKey];
      final eligible = samples?.where((sample) {
        final openedAt = sample.lastOpenedAt;
        return openedAt == null ||
            sample.sampledAt.difference(openedAt) >= warmup;
      }).toList();
      if (room.isBuffering ||
          (eligible != null &&
              eligible.length >= 2 &&
              eligible.last.bufferingCount > eligible.first.bufferingCount)) {
        return true;
      }
    }
    return false;
  }

  double _decodePressure(
    List<MultiRoomPlaybackTelemetry> rooms,
    int logicalProcessorCount,
  ) {
    if (logicalProcessorCount <= 0) return 0;
    var pixelsPerSecond = 0.0;
    for (final room in rooms) {
      final width = room.width;
      final height = room.height;
      if (width == null || height == null || width <= 0 || height <= 0) {
        continue;
      }
      pixelsPerSecond += width * height * (room.framesPerSecond ?? 30);
    }
    final conservativeCapacity =
        logicalProcessorCount * 1920 * 1080 * 30 * 0.75;
    return pixelsPerSecond / conservativeCapacity * 100;
  }

  MultiRoomQualityAction? _selectDegrade(
    DateTime now,
    List<MultiRoomPlaybackTelemetry> rooms, {
    required bool memoryEmergency,
  }) {
    final candidates = rooms.where((room) {
      if (room.qualityIndex < 0 || room.qualityIndex >= room.qualityCount - 1) {
        return false;
      }
      if (!memoryEmergency && room.isQualityLocked) return false;
      return _canAdjust(room.roomKey, now);
    }).toList()
      ..sort((a, b) {
        final protection = _protectionRank(a).compareTo(_protectionRank(b));
        if (protection != 0) return protection;
        return a.qualityIndex.compareTo(b.qualityIndex);
      });
    if (candidates.isEmpty) return null;
    final room = candidates.first;
    return MultiRoomQualityAction(
      roomKey: room.roomKey,
      type: MultiRoomQualityActionType.degrade,
      targetQualityIndex:
          memoryEmergency ? room.qualityCount - 1 : room.qualityIndex + 1,
      reason: memoryEmergency ? 'memory' : 'pressure',
    );
  }

  MultiRoomQualityAction? _selectRestore(
    DateTime now,
    List<MultiRoomPlaybackTelemetry> rooms,
  ) {
    final candidates = rooms.where((room) {
      final target = room.userTargetQualityIndex;
      return !room.isQualityLocked &&
          target != null &&
          room.qualityIndex > target &&
          _canAdjust(room.roomKey, now);
    }).toList()
      ..sort((a, b) {
        final protection = _protectionRank(b).compareTo(_protectionRank(a));
        if (protection != 0) return protection;
        return b.qualityIndex.compareTo(a.qualityIndex);
      });
    if (candidates.isEmpty) return null;
    final room = candidates.first;
    return MultiRoomQualityAction(
      roomKey: room.roomKey,
      type: MultiRoomQualityActionType.restore,
      targetQualityIndex: math.max(
        room.userTargetQualityIndex!,
        room.qualityIndex - 1,
      ),
      reason: 'stable',
    );
  }

  int _protectionRank(MultiRoomPlaybackTelemetry room) {
    if (room.isFocused) return 3;
    if (room.isPrimary) return 2;
    if (room.isChatTarget) return 1;
    return 0;
  }

  bool _canAdjust(String roomKey, DateTime now) {
    final last = _lastRoomAdjustment[roomKey];
    return last == null || now.difference(last) >= perRoomAdjustmentInterval;
  }
}
