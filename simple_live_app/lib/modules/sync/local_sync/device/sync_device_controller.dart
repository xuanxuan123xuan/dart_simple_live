import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/sync_client_info_model.dart';
import 'package:simple_live_app/requests/sync_client_request.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_app/widgets/sync_progress_dialog.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SyncDeviceController extends BaseController {
  final SyncClinet client;
  final SyncClientInfoModel info;
  SyncDeviceController({required this.client, required this.info});
  SyncClientRequest request = SyncClientRequest();

  Future<bool> _syncTemporaryProfile({
    required bool overlay,
    required String label,
    required ProfileExportOptions options,
  }) async {
    TemporaryProfilePackage? package;
    try {
      SyncProgressDialog.update(SyncProgress(stage: "生成$label配置包"));
      package = await ProfileBackupService.instance
          .createTemporaryProfilePackage(options: options);
      final itemCount = _selectedProfileItemCount(package);
      final summary = _profileSummaryMessage(package);
      Log.i(
        "本地发送$label配置包：$summary bytes=${package.byteLength} path=${package.file.path}",
      );
      if (itemCount <= 0) {
        SmartDialog.showToast("本机没有可同步的$label，已取消发送");
        return false;
      }
      SyncProgressDialog.update(SyncProgress(
        stage: "发送$label配置包",
        current: 0,
        total: package.byteLength,
        message: summary,
      ));
      await request.syncProfile(
        client,
        await package.readAsString(),
        overlay: overlay,
      );
      return true;
    } finally {
      try {
        await package?.delete();
      } catch (e) {
        Log.w("删除临时同步配置包失败：$e");
      }
    }
  }

  int _selectedProfileItemCount(TemporaryProfilePackage package) {
    final summary = package.summary;
    final options = package.options;
    var count = 0;
    if (options.settings) {
      count += _summaryInt(summary, "settingCount");
    }
    if (options.accounts) {
      count += _summaryInt(summary, "accountCount");
    }
    if (options.shields) {
      count += _profileShieldCount(summary);
    }
    if (options.shieldPresets) {
      count += _summaryInt(summary, "shieldPresetCount");
    }
    if (options.follows) {
      count += _summaryInt(summary, "followUserCount");
      count += _summaryInt(summary, "followTagCount");
    }
    if (options.histories) {
      count += _summaryInt(summary, "historyCount");
    }
    return count;
  }

  int _summaryInt(Map<String, dynamic> summary, String key) {
    return (summary[key] as num?)?.toInt() ?? 0;
  }

  String _profileSummaryMessage(TemporaryProfilePackage package) {
    final summary = package.summary;
    final options = package.options;
    final parts = <String>[];
    if (options.settings) {
      parts.add("设置 ${_summaryInt(summary, "settingCount")} 项");
    }
    if (options.follows) {
      parts.add("关注 ${_summaryInt(summary, "followUserCount")} 个");
      parts.add("标签 ${_summaryInt(summary, "followTagCount")} 个");
    }
    if (options.histories) {
      parts.add("历史 ${_summaryInt(summary, "historyCount")} 条");
    }
    if (options.shields) {
      parts.add("屏蔽 ${_profileShieldCount(summary)} 项");
    }
    if (options.shieldPresets) {
      parts.add("预设 ${_summaryInt(summary, "shieldPresetCount")} 个");
    }
    if (options.accounts) {
      parts.add("账号 ${_summaryInt(summary, "accountCount")} 个");
    }
    if (parts.isEmpty) {
      return "没有选择同步内容";
    }
    return "将发送：${parts.join("，")}";
  }

  int _profileShieldCount(Map<String, dynamic> summary) {
    final rawCount = _summaryInt(summary, "rawShieldCount");
    if (rawCount > 0) {
      return rawCount;
    }
    return _summaryInt(summary, "keywordShieldCount") +
        _summaryInt(summary, "userShieldCount");
  }

  Future<void> _sendProfilePackage({
    required String label,
    required String successMessage,
    required ProfileExportOptions options,
  }) async {
    try {
      var overlay = await showOverlayDialog();
      SyncProgressDialog.show(SyncProgress(stage: "准备同步$label"));
      final sent = await _syncTemporaryProfile(
        overlay: overlay,
        label: label,
        options: options,
      );
      if (sent) {
        SmartDialog.showToast(successMessage);
      }
    } catch (e) {
      SmartDialog.showToast("同步失败：${exceptionToString(e)}");
      Log.e("同步$label失败：$e", StackTrace.current);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void _sendCompleteProfilePackage() async {
    try {
      var overlay = await showOverlayDialog();
      SyncProgressDialog.show(const SyncProgress(stage: "同步配置包"));
      final sent = await _syncTemporaryProfile(
        overlay: overlay,
        label: "完整",
        options: const ProfileExportOptions(),
      );
      if (sent) {
        SmartDialog.showToast("已同步配置包");
      }
    } catch (e) {
      SmartDialog.showToast("同步失败：${exceptionToString(e)}");
      Log.e("同步配置包失败：$e", StackTrace.current);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  Future<bool> showOverlayDialog() async {
    var overlay = await Utils.showAlertDialog(
      "是否覆盖对方设备上的同类数据？选择“不覆盖”会合并同步。",
      title: "数据覆盖",
      confirm: "覆盖",
      cancel: "不覆盖",
    );
    return overlay;
  }

  void syncFollowAndTag() {
    _sendProfilePackage(
      label: "关注",
      successMessage: "已同步关注列表和标签",
      options: const ProfileExportOptions(
        settings: false,
        accounts: false,
        shields: false,
        shieldPresets: false,
        follows: true,
        histories: false,
      ),
    );
  }

  void syncProfile() {
    _sendCompleteProfilePackage();
  }

  void syncHistory() {
    _sendProfilePackage(
      label: "历史",
      successMessage: "已同步历史记录",
      options: const ProfileExportOptions(
        settings: false,
        accounts: false,
        shields: false,
        shieldPresets: false,
        follows: false,
        histories: true,
      ),
    );
  }

  void syncBlockedWord() {
    _sendProfilePackage(
      label: "屏蔽词",
      successMessage: "已同步屏蔽词",
      options: const ProfileExportOptions(
        settings: false,
        accounts: false,
        shields: true,
        shieldPresets: false,
        follows: false,
        histories: false,
      ),
    );
  }

  void syncBiliAccount() async {
    try {
      if (!BiliBiliAccountService.instance.logined.value) {
        SmartDialog.showToast("未登录哔哩哔哩");
        return;
      }
      SyncProgressDialog.show(const SyncProgress(stage: "同步哔哩哔哩账号"));

      await request.syncBiliAccount(
          client, BiliBiliAccountService.instance.cookie);
      SmartDialog.showToast("已同步哔哩哔哩账号");
    } catch (e) {
      SmartDialog.showToast("同步失败：${exceptionToString(e)}");
      Log.e("同步哔哩哔哩账号失败：$e", StackTrace.current);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void syncDouyinAccount() async {
    try {
      if (!DouyinAccountService.instance.hasCookie.value) {
        SmartDialog.showToast("未配置抖音 Cookie");
        return;
      }
      SyncProgressDialog.show(const SyncProgress(stage: "同步抖音账号"));

      await request.syncDouyinAccount(
          client, DouyinAccountService.instance.cookie);
      SmartDialog.showToast("已同步抖音账号");
    } catch (e) {
      SmartDialog.showToast("同步失败：${exceptionToString(e)}");
      Log.e("同步抖音账号失败：$e", StackTrace.current);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }
}
