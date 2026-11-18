# SimpleLiveTVOSCore

This Swift Package contains platform-neutral tvOS business state and protocol
models. It does not import Flutter, SwiftUI, UIKit, WebKit or KSPlayer.

The native tvOS app adapts these types to `simple_live_core`, KSPlayer,
Keychain and SwiftUI. xtool can prepare a Swift toolchain on Windows/Linux and
run this package's SwiftPM tests. The package does not build the tvOS app.
