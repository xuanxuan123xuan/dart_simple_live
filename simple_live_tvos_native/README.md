# Simple Live tvOS native host

This directory is the native SwiftUI host planned for the Apple TV client.
It keeps `simple_live_core` in a headless FlutterEngine and lets SwiftUI own
focus, Siri Remote navigation, playback and Keychain storage.

## Local macOS setup

1. Install Xcode with the tvOS platform and `xcodegen`.
2. Generate the project with `xcodegen generate --spec project.yml`.
3. Build the Flutter tvOS framework from `simple_live_tvos_app` with the
   repository's Flutter-tvos toolchain and link it into the generated target.
4. Resolve the KSPlayer LGPL package and its FFmpeg dependency through SwiftPM.
5. Run the tvOS simulator before testing an Apple TV device.

The native player uses AVPlayer for HLS and the KSPlayer/KSMEPlayer path for
FLV/RTMP when the Swift package is available. The current Windows checkout can
inspect and format the Swift sources but cannot compile this target.

AngelLive is used for architecture and behavior reference. Its repository is
GPL-3.0. Copying source or assets requires preserving the corresponding
license and attribution.
