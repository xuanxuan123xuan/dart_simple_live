import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/event_bus.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/modules/sync/webdav/webdav_client.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/bulk_data_import_service.dart';
import 'package:simple_live_tv_app/services/douyu_account_service.dart';
import 'package:simple_live_tv_app/services/douyin_account_service.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_tv_app/services/profile_backup_service.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';
import 'package:simple_live_tv_app/widgets/sync_progress_dialog.dart';

class WebDavController extends BaseController {
  static const _profileJsonName = 'SimpleLive_Profile_v4.json';
  static const _legacyProfileJsonNames = {
    'SimpleLive_Profile_v3.json',
    'SimpleLive_Profile_v2.json',
  };

  static bool archiveContainsProfile(Iterable<String> fileNames) =>
      fileNames.any(
        (name) =>
            name == _profileJsonName || _legacyProfileJsonNames.contains(name),
      );

  final isSyncFollows = true.obs;
  final isSyncHistories = true.obs;
  final isSyncBlockWord = true.obs;
  final isSyncBilibiliAccount = true.obs;
  final isSyncDouyinAccount = true.obs;
  final isSyncKuaishouAccount = true.obs;
  final isSyncDouyuAccount = true.obs;
  final isSyncXiaohongshuAccount = true.obs;
  final passwordVisible = true.obs;
  final user = "--".obs;
  final lastRecoverTime = "--".obs;
  final lastUploadTime = "--".obs;
  final lastRecoverSummary = "".obs;

  late DAVClient davClient;

  final _userFollowJsonName = 'SimpleLive_follows.json';
  final _userHistoriesJsonName = 'SimpleLive_histories.json';
  final _userBlockedWordJsonName = 'SimpleLive_blocked_word.json';
  final _userBilibiliAccountJsonName = 'SimpleLive_bilibili_account.json';
  final _userDouyinAccountJsonName = 'SimpleLive_douyin_account.json';
  final _userDouyuAccountJsonName = 'SimpleLive_douyu_account.json';
  final _userXiaohongshuAccountJsonName = 'SimpleLive_xiaohongshu_account.json';
  final _userSettingsJsonName = 'SimpleLive_Settings.json';

  Set<String> get _selectedAccountSiteIds => {
        if (isSyncBilibiliAccount.value) Constant.kBiliBili,
        if (isSyncDouyinAccount.value) Constant.kDouyin,
        if (isSyncKuaishouAccount.value) Constant.kKuaishou,
        if (isSyncDouyuAccount.value) Constant.kDouyu,
        if (isSyncXiaohongshuAccount.value) Constant.kXiaohongshu,
      };

  @override
  void onInit() {
    doWebDAVInit();
    super.onInit();
  }

  void doWebDAVInit() {
    final uri = LocalStorageService.instance
        .getValue(LocalStorageService.kWebDAVUri, "");
    if (uri.isEmpty) {
      notLogin.value = true;
      return;
    }
    user.value = LocalStorageService.instance
        .getValue(LocalStorageService.kWebDAVUser, "");
    final password = LocalStorageService.instance
        .getValue(LocalStorageService.kWebDAVPassword, "");
    davClient = DAVClient(uri, user.value, password);
    lastRecoverTime.value = Utils.parseTime(
      DateTime.fromMillisecondsSinceEpoch(
        LocalStorageService.instance.getValue(
          LocalStorageService.kWebDAVLastRecoverTime,
          DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
    lastUploadTime.value = Utils.parseTime(
      DateTime.fromMillisecondsSinceEpoch(
        LocalStorageService.instance.getValue(
          LocalStorageService.kWebDAVLastUploadTime,
          DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
    checkIsLogin();
  }

  Future<void> checkIsLogin() async {
    try {
      notLogin.value = !await davClient.pingCompleter.future;
    } catch (e) {
      Log.e("$e", StackTrace.current);
      notLogin.value = true;
    }
  }

  void changePasswordVisible() {
    passwordVisible.value = !passwordVisible.value;
  }

  void changeIsSyncFollows() {
    isSyncFollows.value = !isSyncFollows.value;
  }

  void changeIsSyncHistories() {
    isSyncHistories.value = !isSyncHistories.value;
  }

  void changeIsSyncBlockWord() {
    isSyncBlockWord.value = !isSyncBlockWord.value;
  }

  void changeIsSyncBilibiliAccount() {
    isSyncBilibiliAccount.value = !isSyncBilibiliAccount.value;
  }

  void doWebDAVLogin(
    String webDAVUri,
    String webDAVUser,
    String webDAVPassword,
  ) async {
    if (!webDAVUri.startsWith("http://") && !webDAVUri.startsWith("https://")) {
      SmartDialog.showToast("WebDAV服务器地址需要以 http:// 或 https:// 开头");
      return;
    }
    davClient = DAVClient(webDAVUri, webDAVUser, webDAVPassword);
    await checkIsLogin();
    if (!notLogin.value) {
      await LocalStorageService.instance
          .setValue(LocalStorageService.kWebDAVUri, webDAVUri);
      await LocalStorageService.instance
          .setValue(LocalStorageService.kWebDAVUser, webDAVUser);
      await LocalStorageService.instance
          .setValue(LocalStorageService.kWebDAVPassword, webDAVPassword);
      user.value = webDAVUser;
      Get.back();
      SmartDialog.showToast("登录成功");
    } else {
      SmartDialog.showToast("WebDAV账号密码验证失败，请重新输入");
    }
  }

  @override
  Future<void> onLogout() async {
    await LocalStorageService.instance
        .setValue(LocalStorageService.kWebDAVUri, "");
    await LocalStorageService.instance
        .setValue(LocalStorageService.kWebDAVUser, "");
    await LocalStorageService.instance
        .setValue(LocalStorageService.kWebDAVPassword, "");
    notLogin.value = true;
    SmartDialog.showToast("已退出登录");
  }

  Future<void> doWebDAVUpload() async {
    SyncProgressDialog.show(const SyncProgress(stage: "正在打包备份"));
    try {
      final data = _backupData();
      SyncProgressDialog.update(const SyncProgress(stage: "正在上传到云端"));
      final result = await davClient.backup(Uint8List.fromList(data));
      if (!result) {
        SmartDialog.showToast("上传失败");
        return;
      }
      final uploadTime = DateTime.now();
      lastUploadTime.value = Utils.parseTime(uploadTime);
      await LocalStorageService.instance.setValue(
        LocalStorageService.kWebDAVLastUploadTime,
        uploadTime.millisecondsSinceEpoch,
      );
      SmartDialog.showToast("上传成功");
    } catch (e) {
      Log.e("WebDAV 上传失败：$e", StackTrace.current);
      SmartDialog.showToast("上传失败：${exceptionToString(e)}");
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  List<int> _backupData() {
    final archive = Archive();
    final profileMap = ProfileBackupService.instance.exportProfileMap();
    archive.addFile(
      ArchiveFile.string(
        _profileJsonName,
        const JsonEncoder.withIndent("  ").convert(profileMap),
      ),
    );
    _addJsonFile(archive, _userFollowJsonName, {
      'data': profileMap['followUsers'] ?? const [],
    });
    _addJsonFile(archive, _userHistoriesJsonName, {
      'data': profileMap['histories'] ?? const [],
    });
    _addJsonFile(
      archive,
      _userBlockedWordJsonName,
      {'data': AppSettingsControllerSafe.keywordValues()},
    );
    // Credentials are represented only by profile.accounts.items.
    _addJsonFile(archive, _userSettingsJsonName, {
      'data': ProfileBackupService.instance.filterTransportSettings(
        LocalStorageService.instance.settingsBox.toMap(),
      ),
    });
    return ZipEncoder().encode(archive);
  }

  void _addJsonFile(Archive archive, String name, Map<String, dynamic> data) {
    archive.addFile(ArchiveFile.string(name, jsonEncode(data)));
  }

  void doWebDAVRecovery() async {
    SyncProgressDialog.show(const SyncProgress(stage: "正在下载备份"));
    final tempDir = await getTemporaryDirectory();
    final downloadPath = join(tempDir.path, "simple_live_tv_webdav_backup.zip");
    final downloadFile = File(downloadPath);
    try {
      if (downloadFile.existsSync()) {
        downloadFile.deleteSync();
      }
      await davClient.client.read2File(davClient.backupFile, downloadPath);
      if (!downloadFile.existsSync() || downloadFile.lengthSync() <= 0) {
        throw const FormatException("WebDAV 备份文件下载失败");
      }
      SyncProgressDialog.update(const SyncProgress(stage: "正在解压备份"));
      final archive =
          ZipDecoder().decodeBytes(await downloadFile.readAsBytes());
      ArchiveFile? profileFile;
      for (final file in archive) {
        if (file.isFile && archiveContainsProfile([file.name])) {
          profileFile = file;
          break;
        }
      }
      if (profileFile != null) {
        final summary = await ProfileBackupService.instance.importProfileJson(
          utf8.decode(profileFile.content),
          overwrite: true,
          options: ProfileImportOptions(
            settings: true,
            accounts: _selectedAccountSiteIds.isNotEmpty,
            accountSiteIds: _selectedAccountSiteIds,
            follows: isSyncFollows.value,
            histories: isSyncHistories.value,
            shields: isSyncBlockWord.value,
          ),
          onProgress: SyncProgressDialog.update,
        );
        lastRecoverSummary.value = summary.message;
        Log.i("已恢复完整配置包：${summary.message}");
      } else {
        final results = <String>[];
        for (final file in archive) {
          final result = await _recovery(file);
          if (result != null && result.isNotEmpty) {
            results.add(result);
          }
        }
        lastRecoverSummary.value = results.join('；');
      }
      final recoverTime = DateTime.now();
      lastRecoverTime.value = Utils.parseTime(recoverTime);
      await LocalStorageService.instance.setValue(
        LocalStorageService.kWebDAVLastRecoverTime,
        recoverTime.millisecondsSinceEpoch,
      );
      SmartDialog.showToast(
        lastRecoverSummary.value.isEmpty
            ? "恢复完成"
            : "恢复完成：${lastRecoverSummary.value}",
      );
    } catch (e) {
      Log.e("WebDAV 恢复失败：${e.runtimeType}", StackTrace.current);
      lastRecoverSummary.value = "恢复失败，请检查备份文件后重试";
      SmartDialog.showToast(lastRecoverSummary.value);
    } finally {
      SyncProgressDialog.dismiss();
      try {
        if (downloadFile.existsSync()) {
          downloadFile.deleteSync();
        }
      } catch (_) {}
    }
  }

  Future<String?> _recovery(ArchiveFile file) async {
    if (!file.isFile || !file.name.endsWith(".json")) {
      return null;
    }
    final jsonData = json.decode(utf8.decode(file.content))['data'];
    if (file.name == _userFollowJsonName && isSyncFollows.value) {
      final result = await BulkDataImportService.importFollowUsers(
        jsonData,
        overwrite: true,
        onProgress: SyncProgressDialog.update,
      );
      EventBus.instance.emit(Constant.kUpdateFollow, 0);
      Log.i('已恢复关注用户列表：${result.logSummary}');
      return '关注：${result.logSummary}';
    } else if (file.name == _userHistoriesJsonName && isSyncHistories.value) {
      final result = await BulkDataImportService.importHistories(
        jsonData,
        overwrite: true,
        onProgress: SyncProgressDialog.update,
      );
      EventBus.instance.emit(Constant.kUpdateHistory, 0);
      Log.i('已恢复观看历史记录：${result.logSummary}');
      return '历史：${result.logSummary}';
    } else if (file.name == _userBlockedWordJsonName && isSyncBlockWord.value) {
      final result = await BulkDataImportService.importShieldValues(
        jsonData,
        overwrite: true,
        onProgress: SyncProgressDialog.update,
      );
      Log.i('已恢复屏蔽词：${result.logSummary}');
      return '屏蔽词：${result.logSummary}';
    } else if (file.name == _userBilibiliAccountJsonName &&
        isSyncBilibiliAccount.value) {
      final cookie =
          jsonData is Map ? jsonData['cookie']?.toString() ?? "" : "";
      if (cookie.trim().isEmpty) {
        return null;
      }
      BiliBiliAccountService.instance.setCookie(cookie);
      await BiliBiliAccountService.instance.loadUserInfo();
      Log.i('已恢复哔哩哔哩账号');
      return '哔哩哔哩账号：已导入';
    } else if (file.name == _userDouyinAccountJsonName &&
        isSyncDouyinAccount.value) {
      final cookie =
          jsonData is Map ? jsonData['cookie']?.toString() ?? "" : "";
      if (cookie.isEmpty) {
        return null;
      }
      DouyinAccountService.instance.setCookie(cookie);
      Log.i('已恢复抖音账号');
      return '抖音账号：已导入';
    } else if (file.name == _userDouyuAccountJsonName &&
        isSyncDouyuAccount.value) {
      final cookie =
          jsonData is Map ? jsonData['cookie']?.toString() ?? "" : "";
      if (cookie.trim().isEmpty ||
          !await DouyuAccountService.instance.setCookie(cookie)) {
        return null;
      }
      return '斗鱼账号：已导入';
    } else if (file.name == _userXiaohongshuAccountJsonName &&
        isSyncXiaohongshuAccount.value) {
      final cookie =
          jsonData is Map ? jsonData['cookie']?.toString() ?? "" : "";
      if (cookie.trim().isEmpty ||
          !await XiaohongshuAccountService.instance.setCookie(cookie)) {
        return null;
      }
      return '小红书账号：已导入';
    } else if (file.name == _userSettingsJsonName && jsonData is Map) {
      final summary =
          await ProfileBackupService.instance.importLegacySettingsMap(jsonData);
      return '设置：导入 ${summary.settings} 项';
    }
    return null;
  }

  void changeIsSyncDouyinAccount() {
    isSyncDouyinAccount.value = !isSyncDouyinAccount.value;
  }

  void changeIsSyncKuaishouAccount() {
    isSyncKuaishouAccount.value = !isSyncKuaishouAccount.value;
  }

  void changeIsSyncDouyuAccount() {
    isSyncDouyuAccount.value = !isSyncDouyuAccount.value;
  }

  void changeIsSyncXiaohongshuAccount() {
    isSyncXiaohongshuAccount.value = !isSyncXiaohongshuAccount.value;
  }
}

class AppSettingsControllerSafe {
  static List<String> keywordValues() {
    return AppSettingsController.instance.shieldList.toList()..sort();
  }
}
