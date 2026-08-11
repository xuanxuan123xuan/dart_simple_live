class PlayerVolumeSessionState {
  const PlayerVolumeSessionState({
    required this.outputVolume,
    required this.muted,
    required this.lastAudibleVolume,
  });

  final double outputVolume;
  final bool muted;
  final double lastAudibleVolume;
}

/// Keeps persisted user intent separate from transient session mute state.
class PlayerVolumeSessionPolicy {
  const PlayerVolumeSessionPolicy._();

  static double normalize(double volume) =>
      volume.clamp(0.0, 100.0).toDouble();

  static PlayerVolumeSessionState forNewRoom({
    required double userIntentVolume,
    required double lastAudibleVolume,
  }) {
    final output = normalize(userIntentVolume);
    final previousAudible = normalize(lastAudibleVolume);
    return PlayerVolumeSessionState(
      outputVolume: output,
      muted: output <= 0,
      lastAudibleVolume: output > 0 ? output : previousAudible,
    );
  }

  static double volumeToRestoreAfterMute({
    required double lastAudibleVolume,
    required double userIntentVolume,
  }) {
    final previousAudible = normalize(lastAudibleVolume);
    if (previousAudible > 0) {
      return previousAudible;
    }
    return normalize(userIntentVolume);
  }
}
