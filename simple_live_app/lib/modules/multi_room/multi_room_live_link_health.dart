import 'package:simple_live_app/services/live_link_health_collector.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/live_link_health_tracker.dart';

class MultiRoomLiveLinkHealthGeneration {
  const MultiRoomLiveLinkHealthGeneration({
    required this.generation,
    required this.source,
  });

  final int generation;
  final String source;
}

/// Shadow-only health session for one multi-room player.
///
/// Native sampling remains owned by the multi-room player controller. This
/// class only gates samples and events so a late read from an old source can
/// never enter the current source's health window.
class MultiRoomLiveLinkHealthCoordinator {
  MultiRoomLiveLinkHealthCoordinator({
    LiveLinkHealthShadowCollector? collector,
  }) : _collector = collector ??
            LiveLinkHealthShadowCollector(
              tracker: LiveLinkHealthTracker(
                capabilities: const LiveLinkHealthCapabilities(
                  audioUnderrunEvents: true,
                  automaticReconnectEvents: true,
                ),
              ),
            );

  final LiveLinkHealthShadowCollector _collector;
  int _generation = 0;
  MultiRoomLiveLinkHealthGeneration? _current;
  bool? _buffering;

  MultiRoomLiveLinkHealthGeneration? get current => _current;
  int get eventCount => _collector.eventCount;
  LiveLinkHealthSnapshot? snapshot({DateTime? at}) =>
      _collector.snapshot(at: at);

  MultiRoomLiveLinkHealthGeneration beginSource({
    required String target,
    required String source,
    DateTime? openedAt,
    LiveLinkEventType? userOperation,
    LiveReconnectReason? automaticReconnectReason,
  }) {
    final canonicalSource = canonicalizeLivePlaybackSource(source);
    final generation = ++_generation;
    final token = MultiRoomLiveLinkHealthGeneration(
      generation: generation,
      source: canonicalSource,
    );
    _current = token;
    _buffering = null;
    final at = openedAt ?? DateTime.now();
    _collector.startGeneration(
      generation: generation,
      target: target,
      at: at,
    );
    if (userOperation != null) {
      recordEvent(userOperation, at: at);
    }
    if (automaticReconnectReason != null) {
      recordEvent(
        LiveLinkEventType.cdnReconnect,
        at: at,
        reconnectReason: automaticReconnectReason,
      );
    }
    recordEvent(LiveLinkEventType.streamOpened, at: at);
    return token;
  }

  String? addSample({
    required MultiRoomLiveLinkHealthGeneration generation,
    required LiveLinkHealthSample sample,
  }) {
    final current = _current;
    if (current == null ||
        current.generation != generation.generation ||
        current.source != generation.source ||
        sample.generation != generation.generation) {
      return null;
    }
    return _collector.addSample(sample);
  }

  bool recordEvent(
    LiveLinkEventType type, {
    DateTime? at,
    LiveReconnectReason? reconnectReason,
  }) {
    final current = _current;
    if (current == null) return false;
    final occurredAt = at ?? DateTime.now();
    if (type == LiveLinkEventType.playbackPausedByUser ||
        type == LiveLinkEventType.appBackgrounded) {
      // Close an active buffering interval before the tracker becomes
      // ineligible, otherwise a resume could inherit the previous edge.
      recordBuffering(false, at: occurredAt);
    }
    return _collector.addEvent(
      LiveLinkHealthEvent(
        generation: current.generation,
        occurredAt: occurredAt,
        type: type,
        reconnectReason: reconnectReason,
      ),
    );
  }

  void recordBuffering(bool buffering, {DateTime? at}) {
    final previous = _buffering;
    if (previous == buffering) return;
    _buffering = buffering;
    if (previous == null && !buffering) return;
    recordEvent(
      buffering
          ? LiveLinkEventType.bufferingStarted
          : LiveLinkEventType.bufferingEnded,
      at: at,
    );
  }

  void stop() {
    _generation += 1;
    _current = null;
    _buffering = null;
    _collector.stop();
  }
}
