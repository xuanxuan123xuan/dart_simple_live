# Local desktop WebView fork

Based on `desktop_webview_window` 0.3.2 from pub.dev under Apache-2.0. This
fork retains the Dart, Windows, and Linux implementations used by Simple Live;
macOS continues to use the app's existing in-app WebView.

Local changes add initially hidden Linux windows, per-window WebKitGTK data and
cache directories, Linux visibility support, and an HTTPS Xiaohongshu
navigation allowlist. The Windows implementation denies camera and microphone
permissions when configured and drops popup requests. Debug output omits
platform-channel arguments because the app passes optional cookies through a
document-start script.
