import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/sync/profile_backup/profile_import_dialog.dart';
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

  /// 从关注页进入时只预勾选关注数据，其余分类仍按包内实际内容展示。
  Set<ProfileCategory>? importPreselection;

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

    importPreselection = {ProfileCategory.follows};
  }

  ProfileExportOptions get exportOptions => ProfileExportOptions(
        settings: exportSettings.value,
        follows: exportFollows.value,
        histories: exportHistories.value,
        shields: exportShields.value,
        shieldPresets: exportShieldPresets.value,
        accounts: exportAccounts.value,
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

  /// 先选配置包，解析出包内实际含有的分类后再让用户勾选确认。
  Future<void> importProfile() async {
    try {
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("没有存储权限");
        return;
      }
      final content = await _pickProfileContent();
      if (content == null) {
        return; // 用户取消选择
      }

      final ProfileInspection inspection;
      try {
        inspection = ProfileBackupService.instance.inspectProfileJson(content);
      } on FormatException catch (e) {
        SmartDialog.showToast(e.message);
        return;
      }
      if (inspection.isEmpty) {
        SmartDialog.showToast("配置包里没有可导入的内容");
        return;
      }

      final decision = await ProfileImportDialog.show(
        inspection,
        preselected: importPreselection,
      );
      if (decision == null) {
        return; // 用户取消导入
      }

      SyncProgressDialog.show(const SyncProgress(stage: "正在导入配置包"));
      final summary =
          await ProfileBackupService.instance.importInspectedProfile(
        inspection,
        overwrite: decision.overwrite,
        options: decision.options,
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

  /// 返回 null 表示用户取消了选择。
  Future<String?> _pickProfileContent() async {
    if (Utils.isOhos) {
      // 与导出一致：调用鸿蒙文件管理器选择配置包，而非粘贴 JSON。
      final content = await OhosDocumentService.pickText();
      if (content == null || content.trim().isEmpty) {
        return null;
      }
      return content;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["json"],
    );
    if (picked == null || picked.files.single.path == null) {
      return null;
    }
    return File(picked.files.single.path!).readAsString();
  }
}
