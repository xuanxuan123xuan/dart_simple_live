/// Platform-neutral contract for an isolated desktop browser context used by
/// the Xiaohongshu PC website.
///
/// The production implementation lives in
/// `xiaohongshu_desktop_webview_window_host.dart`; keeping this seam small lets
/// session lifecycle and signing behavior be tested without native WebViews.
abstract interface class XiaohongshuDesktopWebSession {
  Future<void> evaluateJavaScript(String script);

  Future<void> close();
}

abstract interface class XiaohongshuDesktopWebSessionFactory {
  Future<XiaohongshuDesktopWebSession> create({
    required String initialUrl,
    required String cookie,
    required void Function(dynamic message) onMessage,
  });
}

class XiaohongshuDesktopWebSessionUnavailable implements Exception {
  const XiaohongshuDesktopWebSessionUnavailable([
    this.message = '此设备未提供小红书桌面网页签名能力',
  ]);

  final String message;

  @override
  String toString() => message;
}
