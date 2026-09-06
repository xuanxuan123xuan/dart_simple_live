// The HarmonyOS AVPlayer platform implementation has been removed.
//
// The app plays exclusively through libmpv (MpvOhosVideoController), which
// never talks to VideoPlayerPlatform. This package is retained only as a stub
// so that the `video_player` package's ohos `default_package` reference still
// resolves during dependency resolution AND so that flutter's plugin
// validation passes (a default_package must point at a package that declares
// itself a plugin).
//
// The pubspec therefore declares `dartPluginClass: OhosVideoPlayer`, and this
// file provides that class as a pure no-op [VideoPlayerPlatform]. Every method
// inherits the base class default (which throws UnimplementedError) — nothing
// here is ever called because libmpv bypasses VideoPlayerPlatform entirely.
//
// The `OhosPlaybackProfile` enum that used to live here has moved to
// `lib/modules/live_room/player/ohos_playback_profile_policy.dart` in the app.

import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A no-op [VideoPlayerPlatform] kept only to satisfy `video_player`'s
/// `platforms: ohos: default_package: video_player_ohos` reference.
///
/// The real playback backend is libmpv (MpvOhosVideoController), which never
/// touches [VideoPlayerPlatform.instance]. This class must not be registered
/// as the platform instance: doing so would make stray `video_player` calls
/// silently no-op instead of surfacing the unsupported path.
class OhosVideoPlayer extends VideoPlayerPlatform {
  /// Present only because `dartPluginClass` requires it. The app does NOT use
  /// this platform, so callers are expected to never invoke this method.
  static void registerWith() {
    // Intentionally empty: the app plays through libmpv, not this platform.
  }
}
