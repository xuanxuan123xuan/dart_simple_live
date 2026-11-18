# Simple Live for tvOS

`simple_live_tvos_app/` is an independent Apple TV viewing client that shares
the repository's `simple_live_core` site adapters. It is intentionally a
read-only third-party client: it receives live chat messages but does not send
danmaku, provide chat input, or implement purchases and other interactions.

## Current scope

- Six provider entries: Bilibili, Huya, Douyu, Douyin, Kuaishou and Xiaohongshu.
- HLS playback through the tvOS AVPlayer plugin, with quality selection,
  line failover, request headers and direct HLS URL playback.
- TV-friendly recommendation, search, room-number entry, pagination, favorites,
  history, settings and D-pad focus navigation.
- Text-only danmaku overlay with enable/disable and connection status. Image
  expressions, GIFs, gifts and structured paid messages remain future display
  work; sending danmaku is outside the product scope.
- Session Cookie recovery through a tvOS Keychain method-channel boundary.
  Manual Cookie input remains available for Bilibili, Douyu, Douyin, Kuaishou
  and Xiaohongshu. The first native web-login target is Xiaohongshu.

The provider matrix is deliberately honest: Bilibili and Kuaishou can use HLS
when the source returns it; Xiaohongshu may require a web session; Huya is
usually FLV; Douyu and Douyin may require JS signing or return unsupported
protocols. An entry or room-detail response does not mean that its stream is
playable on tvOS.

The repository now also contains `simple_live_tvos_native/`, an XcodeGen-based
SwiftUI host. It starts a headless FlutterEngine for `simple_live_core`, owns
tvOS navigation and Keychain access, and defines the native playback boundary.
The Windows checkout cannot compile this target because Xcode, the tvOS SDK,
KSPlayer and FFmpeg are macOS dependencies.

The platform-neutral Swift state and protocol package lives in
`simple_live_tvos_core/`. Its SwiftPM tests can run through xtool on Windows
and Linux. This package does not build the tvOS app and does not replace the
macOS/Xcode validation path.

## Known limitations

1. The Flutter client remains HLS-only. The native host has the KSPlayer/FFmpeg
   integration boundary and AVPlayer HLS path, while the final FLV adapter
   still requires a macOS/Xcode build and device verification.
2. `dart_quickjs_stub` remains a test substitute. JS-signed Douyu/Douyin
   paths are not claimed as migrated.
3. The native Keychain and web-session method channels require a generated
   tvOS host. Windows runs with an in-memory fallback when those plugins are
   absent.
4. This checkout has not been validated with Xcode, a tvOS simulator, an Apple
   TV device, a signed IPA, or long-running production streams. Windows static
   checks and Dart tests are the current acceptance gate.

## Dependencies and layout

The app expects these existing repository paths:

```text
simple_live_tvos_app/
  lib/tvos_playback.dart       # HLS backend boundary and AVPlayer adapter
  lib/tvos_session.dart        # Keychain/WebView method-channel contracts
  lib/site_registry.dart       # provider capability and Cookie routing
  lib/live_page.dart            # room playback, failover and text danmaku
  test/playback_sources_test.dart
simple_live_core/
third_party/dart_quickjs_stub/
```

## AngelLive reference

AngelLive is used as an architectural reference for tvOS native boundaries,
playback recovery and future FLV work. Do not copy code or assets without
retaining the repository's GPL-3.0 attribution and checking compatibility with
this repository's GPL-3.0 license.

## Validation

Run the following on Windows:

```powershell
Push-Location simple_live_tvos_app
flutter pub get
flutter analyze
flutter test
Pop-Location
dart format --output=none --set-exit-if-changed simple_live_tvos_app/lib simple_live_tvos_app/test
```

These checks do not prove tvOS native compilation or real-device playback.
Those results must be recorded separately after a macOS/Xcode and Apple TV
environment is available.
