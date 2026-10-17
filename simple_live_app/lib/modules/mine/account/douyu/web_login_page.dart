import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/mine/account/douyu/web_login_controller.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos_webview;

class DouyuWebLoginPage extends GetView<DouyuWebLoginController> {
  const DouyuWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('斗鱼网页登录'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: controller.reload,
            icon: const Icon(Icons.refresh),
          ),
          Obx(
            () => TextButton.icon(
              onPressed: controller.checking.value
                  ? null
                  : () => controller.saveCookie(),
              icon: controller.checking.value
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
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
              leading: Icon(Icons.info_outline),
              title: Text('请在此完成斗鱼登录，检测到登录态后会自动保存。'),
              subtitle: Text('自动续期需要同一会话的 LTP0 和设备 ID；也可以点右上角手动保存。'),
            ),
          ),
          Obx(() {
            final error = controller.errorMessage.value;
            if (error.isEmpty) return const SizedBox.shrink();
            return Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('登录网页加载失败或会话已变化'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(error),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: controller.fallbackToCookieLogin,
                          child: const Text('手动粘贴 Cookie'),
                        ),
                        TextButton(
                          onPressed: controller.reload,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ],
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
                    onReceivedHttpError: controller.onReceivedHttpError,
                    onUpdateVisitedHistory: (webController, uri, isReload) {
                      controller.onHistoryChanged();
                    },
                    initialSettings: InAppWebViewSettings(
                      userAgent: controller.userAgent,
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
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
