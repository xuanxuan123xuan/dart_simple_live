import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/xiaohongshu_web_session_service.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos;

/// Lazily mounted browser used for signing and JSON only. It has no gesture
/// surface and never replaces the native live video player.
class XiaohongshuWebSessionHost extends StatelessWidget {
  const XiaohongshuWebSessionHost({super.key});

  @override
  Widget build(BuildContext context) {
    if (!XiaohongshuWebSessionService.isSupported ||
        !Get.isRegistered<XiaohongshuWebSessionService>()) {
      return const SizedBox.shrink();
    }
    // Windows/Linux own an isolated native window per web context. Rendering
    // the embedded H5 signer here would share state and can take app focus.
    if (XiaohongshuWebSessionService.usesNativeDesktopHost) {
      return const SizedBox.shrink();
    }
    final service = XiaohongshuWebSessionService.instance;
    return Obx(() {
      final roomUrl = service.pageUrl.value;
      final roomRevision = service.revision.value;
      final profileUrl = service.profilePageUrl.value;
      final profileRevision = service.profileRevision.value;
      if (roomUrl == null && profileUrl == null) {
        return const SizedBox.shrink();
      }
      return ExcludeSemantics(
          child: IgnorePointer(
              child: Opacity(
        opacity: 0,
        child: SizedBox(
            width: 1,
            height: 1,
            child: Stack(children: [
              if (roomUrl != null)
                _SessionView(
                  key: ValueKey('room:$roomUrl:$roomRevision'),
                  url: roomUrl,
                  revision: roomRevision,
                  service: service,
                  profile: false,
                ),
              if (profileUrl != null)
                _SessionView(
                  key: ValueKey('profile:$profileUrl:$profileRevision'),
                  url: profileUrl,
                  revision: profileRevision,
                  service: service,
                  profile: true,
                ),
            ])),
      )));
    });
  }
}

class _SessionView extends StatefulWidget {
  const _SessionView(
      {super.key,
      required this.url,
      required this.revision,
      required this.service,
      required this.profile});
  final String url;
  final int revision;
  final XiaohongshuWebSessionService service;
  final bool profile;
  @override
  State<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<_SessionView> {
  ohos.WebViewController? _ohosController;
  static const _blockMedia = """
    HTMLMediaElement.prototype.play = function() { return Promise.resolve(); };
    document.querySelectorAll('video,audio').forEach(element => {
      element.pause(); element.removeAttribute('src'); element.load();
    });
  """;
  final _cookiesReady = Completer<void>();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cookie =
          (Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite)
              .cookie;
      if (Utils.isOhos) {
        final manager = ohos.WebViewCookieManager();
        for (final part in cookie.split(';')) {
          final separator = part.indexOf('=');
          if (separator <= 0) continue;
          await manager.setCookie(ohos.WebViewCookie(
            name: part.substring(0, separator).trim(),
            value: part.substring(separator + 1).trim(),
            domain: '.xiaohongshu.com',
            path: '/',
          ));
        }
        if (!mounted) return;
        final controller = ohos.WebViewController();
        await controller.setJavaScriptMode(ohos.JavaScriptMode.unrestricted);
        await controller.setUserAgent(XiaohongshuSite.defaultUserAgent);
        await controller.addJavaScriptChannel('XiaohongshuBridge',
            onMessageReceived: (message) =>
                widget.service.receive(message.message));
        await controller.setNavigationDelegate(ohos.NavigationDelegate(
          onNavigationRequest: (request) =>
              XiaohongshuWebSessionService.isAllowedNavigation(request.url)
                  ? ohos.NavigationDecision.navigate
                  : ohos.NavigationDecision.prevent,
          onPageFinished: (_) async {
            await controller.runJavaScript(_blockMedia);
            if (mounted && !widget.profile) {
              widget.service
                  .loaded(url: widget.url, sessionRevision: widget.revision);
            }
          },
        ));
        if (!mounted) return;
        if (!widget.profile) widget.service.evaluate = controller.runJavaScript;
        setState(() => _ohosController = controller);
        await controller.loadRequest(Uri.parse(widget.url));
      } else {
        for (final part in cookie.split(';')) {
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
      }
    } catch (_) {
      // A missing platform plugin leaves pure Dart playback available.
    } finally {
      if (!_cookiesReady.isCompleted) _cookiesReady.complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Utils.isOhos) {
      return _ohosController == null
          ? const SizedBox.shrink()
          : ohos.WebViewWidget(controller: _ohosController!);
    }
    return FutureBuilder<void>(
        future: _cookiesReady.future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              userAgent: XiaohongshuWebSessionService.userAgentFor(
                  profile: widget.profile),
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: true,
              needInitialFocus: false,
              javaScriptCanOpenWindowsAutomatically: false,
              supportMultipleWindows: false,
              allowFileAccess: false,
              allowContentAccess: false,
            ),
            onWebViewCreated: (controller) {
              controller.addJavaScriptHandler(
                  handlerName: 'XiaohongshuBridge',
                  callback: (args) {
                    if (args.isNotEmpty) {
                      if (widget.profile) {
                        widget.service.receiveProfile(args.first);
                      } else {
                        widget.service.receive(args.first);
                      }
                    }
                    return null;
                  });
              Future<void> evaluate(String script) async {
                await controller.evaluateJavascript(source: script);
              }

              if (widget.profile) {
                widget.service.evaluateProfile = evaluate;
              } else {
                widget.service.evaluate = evaluate;
              }
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
                if (widget.profile) {
                  widget.service.loadedProfile(
                      url: widget.url, sessionRevision: widget.revision);
                } else {
                  widget.service.loaded(
                      url: widget.url, sessionRevision: widget.revision);
                }
              }
            },
          );
        });
  }
}
