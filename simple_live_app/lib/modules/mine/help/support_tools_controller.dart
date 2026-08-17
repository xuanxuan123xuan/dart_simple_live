import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/ohos_document_service.dart';

class SupportToolsController extends BaseController {
  final logFiles = <SupportLogFile>[].obs;

  @override
  void onInit() {
    loadLogFiles();
    super.onInit();
  }

  void setLogEnable(bool enabled) {
    AppSettingsController.instance.setLogEnable(enabled);
    if (enabled) {
      Log.initWriter();
      Future.delayed(const Duration(milliseconds: 100), loadLogFiles);
    } else {
      unawaited(Log.disposeWriter());
    }
  }

  Future<void> loadLogFiles() async {
    final supportDir = await getApplicationSupportDirectory();
    final logDir = Directory("${supportDir.path}/log");
    if (!await logDir.exists()) await logDir.create();
    final files = <SupportLogFile>[];
    await for (final entity in logDir.list()) {
      if (entity is! File) continue;
      files.add(
        SupportLogFile(
          name: p.basename(entity.path),
          path: entity.path,
          time: await entity.lastModified(),
          size: await entity.length(),
        ),
      );
    }
    files.sort((a, b) => b.time.compareTo(a.time));
    logFiles.assignAll(files);
  }

  Future<void> cleanLog() async {
    if (AppSettingsController.instance.logEnable.value) {
      SmartDialog.showToast("请先关闭日志记录");
      return;
    }
    final supportDir = await getApplicationSupportDirectory();
    final logDir = Directory("${supportDir.path}/log");
    if (await logDir.exists()) await logDir.delete(recursive: true);
    await loadLogFiles();
  }

  Future<void> shareLogFile(
    SupportLogFile item, {
    Rect? sharePositionOrigin,
  }) async {
    if (Utils.isOhos) {
      await OhosDocumentService.shareFile(item.path, title: item.name);
      return;
    }
    final tmpDir = await getTemporaryDirectory();
    final tmpFile = await File(item.path).copy('${tmpDir.path}/${item.name}');
    await Share.shareXFiles(
      [XFile(tmpFile.path)],
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  Future<void> saveLogFile(SupportLogFile item) async {
    if (Utils.isOhos) {
      final saved = await OhosDocumentService.saveBytes(
        fileName: item.name,
        extension: 'log',
        bytes: await File(item.path).readAsBytes(),
      );
      if (saved) SmartDialog.showToast("保存成功");
      return;
    }
    final filePath = await FilePicker.platform.saveFile(
      allowedExtensions: ['log'],
      type: FileType.custom,
      fileName: item.name,
      bytes: Uint8List(0),
    );
    if (filePath == null) return;
    await File(item.path).copy(filePath);
    SmartDialog.showToast("保存成功");
  }

  Future<void> resetDefaultConfig() async {
    final confirmed = await Utils.showAlertDialog(
      "将清空应用设置和弹幕屏蔽配置，账号、关注和观看记录不会删除。",
      title: "重置配置",
      confirm: "重置",
    );
    if (!confirmed) return;
    await LocalStorageService.instance.settingsBox.clear();
    await LocalStorageService.instance.shieldBox.clear();
    AppSettingsController.instance.reloadFromStorage();
    SmartDialog.showToast("重置成功，重启后完全生效");
  }
}

class SupportLogFile {
  const SupportLogFile({
    required this.name,
    required this.path,
    required this.time,
    required this.size,
  });

  final String name;
  final String path;
  final DateTime time;
  final int size;
}
