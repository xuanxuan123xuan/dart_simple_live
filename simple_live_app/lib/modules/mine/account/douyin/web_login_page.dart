import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/mine/account/douyin/web_login_controller.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos_webview;

class DouyinWebLoginPage extends GetView<DouyinWebLoginController> {
  const DouyinWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('抖音网页登录'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: controller.reload,
            icon: const Icon(Icons.refresh),
          ),
          TextButton.icon(
            onPressed: () => controller.saveCookie(),
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Obx(() {
            final value = controller.progress.value;
            return value >= 1
                ? const SizedBox(height: 3)
                : LinearProgressIndicator(minHeight: 3, value: value);
          }),
        ),
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.qr_code_scanner),
              title: Text('用抖音 App 扫码或验证码登录，登录成功后会自动保存，也可以点右上角保存。'),
            ),
          ),
          Obx(() {
            final error = controller.errorMessage.value;
            if (error.isEmpty) {
              return const SizedBox.shrink();
            }
            return Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('登录网页加载失败'),
                subtitle: Text(error),
                trailing: TextButton(
                  onPressed: controller.reload,
                  child: const Text('重试'),
                ),
              ),
            );
          }),
          Expanded(
            child: Utils.isOhos
                ? ohos_webview.WebViewWidget(
                    controller: controller.ohosWebViewController!,
                  )
                : InAppWebView(
                    onWebViewCreated: controller.onWebViewCreated,
                    onLoadStart: controller.onLoadStart,
                    onLoadStop: controller.onLoadStop,
                    onProgressChanged: controller.onProgressChanged,
                    onReceivedError: controller.onReceivedError,
                    initialSettings: InAppWebViewSettings(
                      userAgent: controller.userAgent,
                      useShouldOverrideUrlLoading: true,
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      sharedCookiesEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      supportMultipleWindows: true,
                    ),
                    onCreateWindow: (webController, action) async {
                      final url = action.request.url;
                      if (url != null) {
                        await webController.loadUrl(
                          urlRequest: URLRequest(url: url),
                        );
                      }
                      return false;
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
