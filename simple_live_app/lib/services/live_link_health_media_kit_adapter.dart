import 'live_link_health_models.dart';

final _audioDeviceUnderrunPattern = RegExp(
  r'^audio device underrun detected\.?$',
  caseSensitive: false,
);

/// Converts reliable libmpv log messages into backend-independent events.
///
/// The health tracker never parses backend log text itself.
LiveLinkEventType? classifyMpvLiveLinkLog({
  required String prefix,
  required String text,
}) {
  final normalizedPrefix = prefix.trim().toLowerCase();
  if ((normalizedPrefix == 'ao' || normalizedPrefix.startsWith('ao/')) &&
      _audioDeviceUnderrunPattern.hasMatch(text.trim())) {
    return LiveLinkEventType.audioUnderrun;
  }
  return null;
}
