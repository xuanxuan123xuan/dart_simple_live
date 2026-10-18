import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_web_session_service.dart';

/// A hidden Android WebView used only to sign read-only Xiaohongshu JSON.
/// Video playback stays on the regular native player path.
class XiaohongshuWebSessionHost extends StatelessWidget {
  const XiaohongshuWebSessionHost({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid ||
        !Get.isRegistered<XiaohongshuWebSessionService>()) {
      return const SizedBox.shrink();
    }
    final service = XiaohongshuWebSessionService.instance;
    return Obx(() {
      final url = service.pageUrl.value;
      final revision = service.revision.value;
      if (url == null) return const SizedBox.shrink();
      return ExcludeSemantics(
        child: IgnorePointer(
          child: Opacity(
            opacity: 0,
            child: SizedBox(
              width: 1,
              height: 1,
              child: _SessionView(
                key: ValueKey('$url:$revision'),
                url: url,
                revision: revision,
                service: service,
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _SessionView extends StatefulWidget {
  const _SessionView({
    super.key,
    required this.url,
    required this.revision,
    required this.service,
  });

  final String url;
  final int revision;
  final XiaohongshuWebSessionService service;

  @override
  State<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<_SessionView> {
  static const _blockMedia = '''
    HTMLMediaElement.prototype.play = function() { return Promise.resolve(); };
    new MutationObserver(() => document.querySelectorAll('video,audio').forEach(element => {
      element.pause(); element.removeAttribute('src');
    })).observe(document, {childList: true, subtree: true});
    document.querySelectorAll('video,audio').forEach(element => {
      element.pause(); element.removeAttribute('src'); element.load();
    });
  ''';

  final _cookiesReady = Completer<void>();

  @override
  void initState() {
    super.initState();
    _prepareCookies();
  }

  Future<void> _prepareCookies() async {
    try {
      final site =
          Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite;
      final cookie = site.cookie;
      for (final part in cookie.split(';')) {
        if (!mounted || widget.revision != widget.service.revision.value) {
          return;
        }
        final separator = part.indexOf('=');
        if (separator <= 0) continue;
        await CookieManager.instance().setCookie(
          url: WebUri(XiaohongshuSite.webBaseUrl),
          name: part.substring(0, separator).trim(),
          value: part.substring(separator + 1).trim(),
          domain: '.xiaohongshu.com',
          path: '/',
          isSecure: true,
        );
      }
    } catch (_) {
      // Public SSR playback still works if the platform Cookie API is absent.
    } finally {
      if (!_cookiesReady.isCompleted) _cookiesReady.complete();
    }
  }

  @override
  void dispose() {
    widget.service.hostDetached(widget.revision);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _cookiesReady.future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return InAppWebView(
            initialUserScripts: UnmodifiableListView([
              UserScript(
                  source: _blockMedia,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
            ]),
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              userAgent: XiaohongshuSite.defaultUserAgent,
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: true,
              needInitialFocus: false,
              javaScriptCanOpenWindowsAutomatically: false,
              supportMultipleWindows: false,
              allowFileAccess: false,
              allowContentAccess: false,
            ),
            onWebViewCreated: (controller) {
              if (!mounted ||
                  widget.revision != widget.service.revision.value) {
                return;
              }
              controller.addJavaScriptHandler(
                handlerName: XiaohongshuWebSessionService.javascriptChannelName,
                callback: (args) {
                  if (args.isNotEmpty) widget.service.receive(args.first);
                  return null;
                },
              );
              widget.service.evaluate = (script) async {
                await controller.evaluateJavascript(source: script);
              };
            },
            shouldOverrideUrlLoading: (controller, action) async =>
                XiaohongshuWebSessionService.isAllowedNavigation(
                        '${action.request.url}')
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL,
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _blockMedia);
              if (mounted &&
                  XiaohongshuWebSessionService.isAllowedNavigation('$url')) {
                widget.service.loaded(
                  url: widget.url,
                  sessionRevision: widget.revision,
                );
              }
            },
          );
        },
      );
}
