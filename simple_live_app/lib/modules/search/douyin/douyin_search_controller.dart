import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos_webview;

class DouyinSearchController extends BaseController {
  InAppWebViewController? webViewController;
  ohos_webview.WebViewController? ohosWebViewController;

  @override
  void onInit() {
    super.onInit();
    if (Utils.isOhos) {
      _initializeOhosWebView();
    }
  }

  void _initializeOhosWebView() {
    final controller = ohos_webview.WebViewController()
      ..setJavaScriptMode(ohos_webview.JavaScriptMode.unrestricted)
      ..setUserAgent(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 "
        "Mobile/15E148 Safari/604.1",
      )
      ..setNavigationDelegate(
        ohos_webview.NavigationDelegate(
          onPageStarted: (_) => pageLoadding.value = true,
          onPageFinished: (_) => pageLoadding.value = false,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              pageLoadding.value = false;
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.host == "live.douyin.com") {
              _openDouyinRoom(uri);
              return ohos_webview.NavigationDecision.prevent;
            }
            return ohos_webview.NavigationDecision.navigate;
          },
        ),
      );
    ohosWebViewController = controller;
    controller.loadRequest(Uri.parse(searchUrl));
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
  }

  RxList<LiveRoomItem> list = <LiveRoomItem>[].obs;

  String keyword = "";

  /// 搜索模式，0=直播间，1=主播
  var searchMode = 0.obs;
  final Site site;
  DouyinSearchController(
    this.site,
  );

  var searchUrl = "https://www.douyin.com/search/dnf?type=live";

  void reloadWebView() {
    if (keyword.isEmpty) {
      return;
    }
    searchUrl =
        "https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?type=live";
    if (Utils.isOhos) {
      ohosWebViewController?.loadRequest(Uri.parse(searchUrl));
    } else if (Platform.isAndroid || Platform.isIOS) {
      webViewController?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(searchUrl),
        ),
      );
    }
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) async {
    pageLoadding.value = false;
  }

  void onLoadStart(InAppWebViewController controller, Uri? uri) async {
    pageLoadding.value = true;
  }

  Future<bool?> onCreateWindow(InAppWebViewController controller,
      CreateWindowAction createWindowAction) async {
    if (createWindowAction.request.url?.host == "live.douyin.com") {
      _openDouyinRoom(createWindowAction.request.url!);
      return false;
    }

    return false;
  }

  void openDouyinRoom(Uri uri) {
    _openDouyinRoom(uri);
  }

  void _openDouyinRoom(Uri uri) {
    final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
    final id = segments.isEmpty ? null : segments.first;
    if (id == null || id.isEmpty) {
      return;
    }
    AppNavigator.toLiveRoomDetail(site: site, roomId: id);
  }

  void openBrowser() {
    launchUrlString(searchUrl);
    Get.offAndToNamed(RoutePath.kTools);
  }
}
