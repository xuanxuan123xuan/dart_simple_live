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

  /// Volume fallback for unmute when no audible volume is remembered.
  ///
  /// Desktop volume gestures and shortcuts persist the player volume, so a user
  /// who drags to 0 relaunches with both the persisted intent and the remembered
  /// audible volume at 0. Unmute has to land on something audible.
  static const double fallbackUnmuteVolume = 100.0;

  static double volumeToRestoreAfterMute({
    required double lastAudibleVolume,
    required double userIntentVolume,
  }) {
    final previousAudible = normalize(lastAudibleVolume);
    if (previousAudible > 0) {
      return previousAudible;
    }
    final intent = normalize(userIntentVolume);
    return intent > 0 ? intent : fallbackUnmuteVolume;
  }
}
