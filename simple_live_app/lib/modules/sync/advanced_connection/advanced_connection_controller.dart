import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/sync/advanced_connection/sync_server_picker_dialog.dart';
import 'package:simple_live_app/services/signalr_service.dart';

class AdvancedConnectionController extends BaseController {
  String get syncServerUrlLabel {
    final configured = SignalRService.configuredUrl;
    final preset = SignalRService.presetForUrl(configured);
    if (preset != null) {
      return configured == SignalRService.kDefaultUrl
          ? "默认服务（${preset.shortLabel}）"
          : preset.shortLabel;
    }
    final host = Uri.tryParse(configured)?.host ?? "";
    if (host.isEmpty) return "自定义服务";
    return "自定义: $host";
  }

  String get syncServerUrlSubtitle {
    final configured = SignalRService.configuredUrl;
    final preset = SignalRService.presetForUrl(configured);
    if (configured == SignalRService.kDefaultUrl) {
      return "远程同步使用默认 WebSocket 服务（可直连）";
    }
    if (preset != null) {
      return "${preset.note}：$configured";
    }
    return configured;
  }

  String get syncProxyUrl => SignalRService.proxyDisplayName;

  Future<void> chooseSyncServerUrl() async {
    final value = await Utils.showDialogSafe<String>(
      context: Get.context!,
      builder: (_) => const SyncServerPickerDialog(),
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
