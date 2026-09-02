/// User-selectable quality for the app's liquid-glass surfaces.
///
/// The [storageValue] strings are part of the local settings format. Keep
/// them stable when adding or reordering enum values; Hive stores the string,
/// rather than the enum's index, so settings remain valid across releases.
enum AppGlassMode {
  off('off', '关闭'),
  auto('auto', '自动'),
  minimal('minimal', '轻量'),
  standard('standard', '标准'),
  premium('premium', '高质量');

  const AppGlassMode(this.storageValue, this.label);

  /// Stable value persisted to Hive and included in profile settings.
  final String storageValue;

  /// User-facing label used by the appearance settings page.
  final String label;

  /// The default for new installations and settings without this key.
  static const AppGlassMode defaultMode = AppGlassMode.auto;

  /// Reads a persisted value without allowing malformed data to break start-up.
  static AppGlassMode fromStorage(Object? value) {
    if (value is AppGlassMode) {
      return value;
    }
    final storageValue = value?.toString();
    return values.firstWhere(
      (mode) => mode.storageValue == storageValue,
      orElse: () => defaultMode,
    );
  }
}
