import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:simple_live_core/simple_live_core.dart';

import 'xiaohongshu_desktop_web_session_host.dart';
import 'xiaohongshu_web_session_service.dart';

/// Creates a fresh native WebView and browser data directory per context.
///
/// Windows uses a private WebView2 user-data folder. Linux uses the fork's
/// private WebKitGTK website-data/cache directories and starts the native
/// window hidden, before it can flash or take focus.
class XiaohongshuDesktopWebviewWindowFactory
    implements XiaohongshuDesktopWebSessionFactory {
  const XiaohongshuDesktopWebviewWindowFactory();

  @override
  Future<XiaohongshuDesktopWebSession> create({
    required String initialUrl,
    required String cookie,
    required void Function(dynamic message) onMessage,
  }) async {
    if (!Platform.isWindows && !Platform.isLinux) {
      throw const XiaohongshuDesktopWebSessionUnavailable();
    }
    if (!await WebviewWindow.isWebviewAvailable()) {
      if (Platform.isWindows) {
        throw XiaohongshuWebSessionUnavailableError.webView2Runtime();
      }
      throw XiaohongshuWebSessionUnavailableError.linuxRuntime();
    }

    final directory = await Directory.systemTemp.createTemp('simple_live_xhs_');
    Webview? webview;
    try {
      final ready = Completer<void>();
      final expected = Uri.parse(initialUrl);
      void handleMessage(dynamic message) {
        try {
          final decoded = message is String ? jsonDecode(message) : message;
          if (decoded is Map && decoded['type'] == 'xhs_document_ready') {
            final loaded = Uri.tryParse('${decoded['url']}');
            if (loaded != null &&
                loaded.scheme == 'https' &&
                loaded.host == expected.host &&
                XiaohongshuWebSessionService.isAllowedNavigation('$loaded') &&
                !ready.isCompleted) {
              ready.complete();
            }
            return;
          }
        } catch (_) {
          // A malformed page message must not complete document readiness.
        }
        onMessage(message);
      }

      webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: 'Simple Live · 小红书网页会话',
          windowWidth: 1,
          windowHeight: 1,
          titleBarHeight: 0,
          openHidden: true,
          denyCameraAndMicrophone: Platform.isWindows,
          userDataFolderWindows: p.join(directory.path, 'webview2'),
          userDataFolderLinux: p.join(directory.path, 'webkitgtk'),
        ),
      );
      final session = _DesktopWebviewWindowSession(webview, directory);
      if (Platform.isLinux) {
        await webview.registerJavaScriptMessageHandler(
          XiaohongshuWebSessionService.javascriptChannelName,
          (_, body) => handleMessage(body),
        );
      } else {
        webview.addOnWebMessageReceivedCallback(handleMessage);
      }
      webview.setOnUrlRequestCallback(
          XiaohongshuWebSessionService.isAllowedNavigation);
      await webview.addScriptToExecuteOnDocumentCreated(
          buildDocumentStartScript(cookie));
      await webview.launch(initialUrl);
      await ready.future.timeout(const Duration(seconds: 20));
      return session;
    } catch (_) {
      webview?.close();
      if (webview != null) {
        try {
          await webview.onClose.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // The plugin does not guarantee a close acknowledgement on startup
          // failures; the directory is removed when Windows releases it.
        }
      }
      try {
        await _deleteDirectory(directory);
      } on FileSystemException {
        // A native runtime can briefly retain a profile file after close.
      }
      rethrow;
    }
  }

  @visibleForTesting
  static String buildDocumentStartScript(String cookie) {
    final entries = <List<String>>[];
    for (final part in cookie.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      final value = part.substring(separator + 1).trim();
      if (name.isEmpty ||
          name.contains(RegExp(r'[\s;,=]')) ||
          name.startsWith('__Host-') ||
          name.startsWith('__Secure-') ||
          value.contains(RegExp(r'[\r\n;]'))) {
        continue;
      }
      entries.add([name, value]);
    }
    final encoded = jsonEncode(entries);
    return '''(function() {
      const cookies = $encoded;
      for (const pair of cookies) {
        document.cookie = pair[0] + '=' + pair[1] +
          '; path=/; domain=.xiaohongshu.com; Secure; SameSite=Lax';
      }
      const blockMedia = function(root) {
        if (!root || !root.querySelectorAll) return;
        root.querySelectorAll('video,audio').forEach(function(media) {
          media.autoplay = false;
          media.pause();
        });
      };
      if (typeof HTMLMediaElement !== 'undefined') {
        HTMLMediaElement.prototype.play = function() { return Promise.resolve(); };
      }
      document.addEventListener('DOMContentLoaded', function() {
        blockMedia(document);
        new MutationObserver(function(records) {
          for (const record of records) for (const node of record.addedNodes) blockMedia(node);
        }).observe(document.documentElement, {childList: true, subtree: true});
      }, {once: true});
      const notifyReady = function() {
        const message = JSON.stringify({type: 'xhs_document_ready', url: location.href});
        if (window.chrome && window.chrome.webview && window.chrome.webview.postMessage) {
          window.chrome.webview.postMessage(message);
        } else if (window.webkit && window.webkit.messageHandlers &&
                   window.webkit.messageHandlers.XiaohongshuBridge) {
          window.webkit.messageHandlers.XiaohongshuBridge.postMessage(message);
        } else if (window.XiaohongshuBridge) {
          window.XiaohongshuBridge.postMessage(message);
        }
      };
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', notifyReady, {once: true});
      } else {
        notifyReady();
      }
    })();''';
  }

  static Future<void> _deleteDirectory(Directory directory) async {
    if (!await directory.exists()) return;
    final tempRoot =
        p.normalize(await Directory.systemTemp.resolveSymbolicLinks());
    final target = p.normalize(await directory.resolveSymbolicLinks());
    if (!p.isWithin(tempRoot, target) ||
        p.dirname(target) != tempRoot ||
        !p.basename(target).startsWith('simple_live_xhs_')) {
      throw StateError('Refusing to delete an unexpected browser profile path');
    }
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        if (await directory.exists()) {
          await Directory(target).delete(recursive: true);
        }
        return;
      } on FileSystemException {
        if (attempt == 3) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
}

class _DesktopWebviewWindowSession implements XiaohongshuDesktopWebSession {
  _DesktopWebviewWindowSession(this._webview, this._directory);

  final Webview _webview;
  final Directory _directory;
  Future<void>? _closing;

  @override
  Future<void> evaluateJavaScript(String script) async {
    await _webview.evaluateJavaScript(script);
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    final closed = _webview.onClose;
    _webview.close();
    try {
      await closed.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Native close notifications are best effort; the process can still
      // release its temporary browser data on the next startup.
    }
    try {
      await XiaohongshuDesktopWebviewWindowFactory._deleteDirectory(_directory);
    } on FileSystemException {
      // Windows may keep WebView2's final file handle briefly after close.
      // Don't turn a successful API response into a request failure for that.
    }
  }
}
