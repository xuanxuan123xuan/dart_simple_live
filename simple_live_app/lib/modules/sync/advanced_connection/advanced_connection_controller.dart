import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/signalr_service.dart';

class AdvancedConnectionController extends BaseController {
  String get syncServerUrlLabel {
    final configured = SignalRService.configuredUrl;
    final isDefault = configured == SignalRService.kDefaultUrl;
    final host = Uri.tryParse(configured)?.host ?? "";
    if (host.isEmpty) return isDefault ? "默认服务" : "自定义服务";
    return isDefault ? "默认服务" : "自定义: $host";
  }

  String get syncServerUrlSubtitle {
    final configured = SignalRService.configuredUrl;
    return configured == SignalRService.kDefaultUrl
        ? "远程同步使用默认 WebSocket 服务"
        : configured;
  }

  String get syncProxyUrl => SignalRService.proxyDisplayName;

  Future<void> editSyncServerUrl() async {
    final value = await Utils.showEditTextDialog(
      SignalRService.configuredUrl,
      title: "同步服务地址",
      hintText: SignalRService.kDefaultUrl,
      validate: (text) {
        final url = text.trim();
        if (url.isEmpty) return true;
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !(uri.scheme == "wss" || uri.scheme == "ws") ||
            uri.host.isEmpty) {
          SmartDialog.showToast("请输入 ws:// 或 wss:// 开头的同步服务地址");
          return false;
        }
        return true;
      },
    );
    if (value == null) return;
    await SignalRService.setConfiguredUrl(value);
    SmartDialog.showToast(value.trim().isEmpty ? "已恢复默认同步服务" : "已保存");
    update();
  }

  Future<void> editSyncProxyUrl() async {
    final value = await Utils.showEditTextDialog(
      SignalRService.configuredProxyUrl,
      title: "同步代理地址",
      hintText: "留空自动检测 ${SignalRService.kDefaultLocalProxy}",
      validate: (text) {
        final value = text.trim();
        if (!SignalRService.isValidProxyConfig(value)) {
          SmartDialog.showToast("请输入 host:port、http://host:port，或 direct 直连");
          return false;
        }
        return true;
      },
    );
    if (value == null) return;
    await SignalRService.setConfiguredProxyUrl(value);
    SmartDialog.showToast(value.trim().isEmpty ? "已恢复自动检测代理" : "已保存");
    update();
  }

  Future<void> reset() async {
    await SignalRService.setConfiguredUrl("");
    await SignalRService.setConfiguredProxyUrl("");
    SmartDialog.showToast("已恢复默认连接设置");
    update();
  }
}
