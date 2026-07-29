import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/mine/account/bilibili/web_login_controller.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos_webview;

class BiliBiliWebLoginPage extends GetView<BiliBiliWebLoginController> {
  const BiliBiliWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('哔哩哔哩账号登录'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: controller.reload,
            icon: const Icon(Icons.refresh),
          ),
          TextButton.icon(
            onPressed: () => controller.logined(),
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
          TextButton.icon(
            onPressed: controller.toQRLogin,
            icon: const Icon(Icons.qr_code),
            label: const Text('二维码'),
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
                      userAgent:
                          'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
                          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      sharedCookiesEnabled: true,
                      thirdPartyCookiesEnabled: true,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
