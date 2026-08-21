import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';
import 'package:simple_live_app/services/ohos_document_service.dart';
import 'package:simple_live_app/widgets/sync_progress_dialog.dart';
import 'package:simple_live_core/simple_live_core.dart';

class ProfileBackupController extends BaseController {
  static const String kFollowDataArgument = "follow_data";

  final exportSettings = true.obs;
  final exportFollows = true.obs;
  final exportHistories = true.obs;
  final exportShields = true.obs;
  final exportShieldPresets = true.obs;
  final exportAccounts = false.obs;

  final importSettings = true.obs;
  final importFollows = true.obs;
  final importHistories = true.obs;
  final importShields = true.obs;
  final importShieldPresets = true.obs;
  final importAccounts = false.obs;

  @override
  void onInit() {
    super.onInit();
    if (Get.arguments == kFollowDataArgument) {
      selectFollowDataOnly();
    }
  }

  void selectFollowDataOnly() {
    exportSettings.value = false;
    exportFollows.value = true;
    exportHistories.value = false;
    exportShields.value = false;
    exportShieldPresets.value = false;
    exportAccounts.value = false;

    importSettings.value = false;
    importFollows.value = true;
    importHistories.value = false;
    importShields.value = false;
    importShieldPresets.value = false;
    importAccounts.value = false;
  }

  ProfileExportOptions get exportOptions => ProfileExportOptions(
        settings: exportSettings.value,
        follows: exportFollows.value,
        histories: exportHistories.value,
        shields: exportShields.value,
        shieldPresets: exportShieldPresets.value,
        accounts: exportAccounts.value,
      );

  ProfileImportOptions get importOptions => ProfileImportOptions(
        settings: importSettings.value,
        follows: importFollows.value,
        histories: importHistories.value,
        shields: importShields.value,
        shieldPresets: importShieldPresets.value,
        accounts: importAccounts.value,
      );

  Future<void> exportProfile() async {
    try {
      final options = exportOptions;
      if (!options.hasSelection) {
        SmartDialog.showToast("请至少选择一项导出内容");
        return;
      }
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("没有存储权限");
        return;
      }
      final content =
          ProfileBackupService.instance.exportProfileJson(options: options);
      final fileName =
          "SimpleLive_Profile_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.json";
      if (Utils.isOhos) {
        final saved = await OhosDocumentService.saveText(
          fileName: fileName,
          extension: 'json',
          content: content,
        );
        if (saved) {
          SmartDialog.showToast("已导出配置包");
        }
        return;
      }
      final inlineSave = Platform.isAndroid || Platform.isIOS || kIsWeb;
      final path = await FilePicker.platform.saveFile(
        allowedExtensions: ["json"],
        type: FileType.custom,
        fileName: fileName,
        bytes: inlineSave ? utf8.encode(content) : null,
      );
      if (path == null && !kIsWeb) {
        return;
      }
      if (!inlineSave && path != null) {
        await File(path).writeAsString(content);
      }
      SmartDialog.showToast("已导出配置包");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("导出失败：$e");
    }
  }

  Future<void> importProfile() async {
    try {
      final options = importOptions;
      if (!options.hasSelection) {
        SmartDialog.showToast("请至少选择一项导入内容");
        return;
      }
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("没有存储权限");
        return;
      }
      final overwrite = await Utils.showAlertDialog(
        "是否覆盖本地数据？选择“不覆盖”会合并导入，保留本机已有数据。",
        title: "导入配置包",
        confirm: "覆盖",
        cancel: "不覆盖",
      );
      if (Utils.isOhos) {
        // 与导出一致：调用鸿蒙文件管理器选择配置包，而非粘贴 JSON。
        final content = await OhosDocumentService.pickText();
        if (content == null || content.trim().isEmpty) {
          return; // 用户取消选择
        }
        SyncProgressDialog.show(const SyncProgress(stage: "正在导入配置包"));
        final summary = await ProfileBackupService.instance.importProfileJson(
          content,
          overwrite: overwrite,
          options: options,
          onProgress: SyncProgressDialog.update,
        );
        SyncProgressDialog.dismiss();
        SmartDialog.showToast("导入完成：${summary.message}");
        return;
      }
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["json"],
      );
      if (picked == null || picked.files.single.path == null) {
        return;
      }
      SyncProgressDialog.show(const SyncProgress(stage: "正在导入配置包"));
      final content = await File(picked.files.single.path!).readAsString();
      final summary = await ProfileBackupService.instance.importProfileJson(
        content,
        overwrite: overwrite,
        options: options,
        onProgress: SyncProgressDialog.update,
      );
      SyncProgressDialog.dismiss();
      SmartDialog.showToast("导入完成：${summary.message}");
    } catch (e) {
      SyncProgressDialog.dismiss();
      Log.logPrint(e);
      SmartDialog.showToast("导入失败：$e");
    }
  }
}
