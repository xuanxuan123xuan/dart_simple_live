/// Behavior switches for a multi-room player. Defaults preserve the existing
/// full multi-room experience.
class MultiRoomPlayerConfiguration {
  const MultiRoomPlayerConfiguration({
    this.preferLowestQuality = false,
    this.enableDanmaku = true,
    this.enableLiveHealthSampling = true,
    this.enableAutomaticRecovery = true,
  });

  const MultiRoomPlayerConfiguration.lightweightPreview()
      : preferLowestQuality = true,
        enableDanmaku = false,
        enableLiveHealthSampling = false,
        enableAutomaticRecovery = false;

  final bool preferLowestQuality;
  final bool enableDanmaku;
  final bool enableLiveHealthSampling;
  final bool enableAutomaticRecovery;
}
