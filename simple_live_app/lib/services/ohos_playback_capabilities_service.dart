import 'package:flutter/services.dart';
import 'package:simple_live_app/app/utils.dart';

/// Capabilities exposed by the HarmonyOS playback bridge.
class OhosPlaybackCapabilities {
  const OhosPlaybackCapabilities({
    required this.lowLatencyExperimentalSupported,
  });

  static const unsupported = OhosPlaybackCapabilities(
    lowLatencyExperimentalSupported: false,
  );

  factory OhosPlaybackCapabilities.fromMap(Map<String, dynamic>? values) {
    return OhosPlaybackCapabilities(
      lowLatencyExperimentalSupported:
          values?['lowLatencyExperimentalSupported'] == true,
    );
  }

  final bool lowLatencyExperimentalSupported;
}

/// Reads optional playback capabilities from the HarmonyOS native bridge.
///
/// The service is intentionally fail-closed: a missing plugin, an older
/// HarmonyOS API, or any bridge failure leaves the experimental profile
/// unavailable. The result is cached for the lifetime of this service and can
/// be refreshed when the settings page is opened again.
class OhosPlaybackCapabilitiesService {
  OhosPlaybackCapabilitiesService({
    MethodChannel? capabilitiesChannel,
    bool Function()? isOhos,
  })  : _capabilitiesChannel = capabilitiesChannel ??
            const MethodChannel('simple_live/ohos_capabilities'),
        _isOhos = isOhos ?? (() => Utils.isOhos);

  static final OhosPlaybackCapabilitiesService instance =
      OhosPlaybackCapabilitiesService();

  final MethodChannel _capabilitiesChannel;
  final bool Function() _isOhos;
  Future<OhosPlaybackCapabilities>? _capabilitiesFuture;

  Future<OhosPlaybackCapabilities> getCapabilities({bool refresh = false}) {
    if (!_isOhos()) {
      return Future<OhosPlaybackCapabilities>.value(
        OhosPlaybackCapabilities.unsupported,
      );
    }
    if (refresh) {
      _capabilitiesFuture = null;
    }
    return _capabilitiesFuture ??= _loadCapabilities();
  }

  Future<OhosPlaybackCapabilities> _loadCapabilities() async {
    try {
      final values =
          await _capabilitiesChannel.invokeMapMethod<String, dynamic>(
        'getPlaybackCapabilities',
      );
      return OhosPlaybackCapabilities.fromMap(values);
    } catch (_) {
      return OhosPlaybackCapabilities.unsupported;
    }
  }
}
