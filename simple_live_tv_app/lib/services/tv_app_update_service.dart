import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/models/version_model.dart';
import 'package:simple_live_tv_app/requests/common_request.dart';
import 'package:simple_live_tv_app/requests/http_client.dart';
import 'package:simple_live_tv_app/modules/settings/tv_update_dialog.dart';
import 'package:url_launcher/url_launcher_string.dart';

class TvAppDownloadAsset {
  const TvAppDownloadAsset({required this.name, required this.url});

  final String name;
  final String url;
}

class TvAppUpdateService extends GetxService {
  static TvAppUpdateService get instance => Get.find<TvAppUpdateService>();

  static const String repository = 'xuanxuan123xuan/dart_simple_live';
  static const String _githubApi = 'https://api.github.com/repos/$repository';

  final checking = false.obs;
  final downloading = false.obs;
  final downloadProgress = 0.0.obs;
  final updateAvailable = false.obs;
  final latestVersion = Rxn<VersionModel>();
  final downloadedFilePath = RxnString();
  final errorMessage = RxnString();

  CancelToken? _downloadToken;
  Future<VersionModel>? _checkFuture;
  bool _startupCheckStarted = false;
  bool _startupDialogShown = false;

  int get currentBuildNumber =>
      int.tryParse(Utils.packageInfo.buildNumber) ??
      _parseVersion(Utils.packageInfo.version);

  int _parseVersion(String value) {
    try {
      return Utils.parseVersion(value);
    } catch (_) {
      return 0;
    }
  }

  String get currentVersion => Utils.packageInfo.version;

  @override
  void onClose() {
    _downloadToken?.cancel('服务已关闭');
    super.onClose();
  }

  bool isNewer(VersionModel version) => version.versionNum > currentBuildNumber;

  Future<VersionModel> checkForUpdates() {
    final ongoing = _checkFuture;
    if (ongoing != null) return ongoing;
    final future = _performCheck();
    _checkFuture = future;
    unawaited(future.then((_) {
      if (identical(_checkFuture, future)) _checkFuture = null;
    }, onError: (Object _, StackTrace __) {
      if (identical(_checkFuture, future)) _checkFuture = null;
    }));
    return future;
  }

  Future<VersionModel> _performCheck() async {
    checking.value = true;
    errorMessage.value = null;
    try {
      final version = await CommonRequest().checkUpdate();
      latestVersion.value = version;
      updateAvailable.value = isNewer(version);
      return version;
    } catch (e, stackTrace) {
      errorMessage.value = e.toString();
      Log.logPrint('TV 检查更新失败: $e\n$stackTrace');
      rethrow;
    } finally {
      checking.value = false;
    }
  }

  Future<void> checkAtStartup() async {
    if (_startupCheckStarted) return;
    _startupCheckStarted = true;
    try {
      final version = await checkForUpdates();
      if (!isNewer(version) ||
          _startupDialogShown ||
          Get.isDialogOpen == true) {
        return;
      }
      _startupDialogShown = true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (Get.context != null && Get.isDialogOpen != true) {
        await Get.dialog(const TvUpdateDialog());
      }
    } catch (_) {
      // Automatic checks must never block startup or show an error dialog.
    }
  }

  Future<TvAppDownloadAsset?> resolveAsset(VersionModel version) async {
    final tag = _releaseTag(version.downloadUrl);
    if (tag != null) {
      try {
        final result = await HttpClient.instance.getJson(
          '$_githubApi/releases/tags/${Uri.encodeComponent(tag)}',
          header: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'SimpleLiveTV',
          },
        );
        final assets = result is Map ? result['assets'] : null;
        if (assets is List) {
          final candidates = assets
              .whereType<Map>()
              .map((item) => TvAppDownloadAsset(
                    name: item['name']?.toString() ?? '',
                    url: item['browser_download_url']?.toString() ?? '',
                  ))
              .where((asset) => asset.name.isNotEmpty && asset.url.isNotEmpty)
              .toList();
          final selected = _selectAsset(candidates, version.version);
          if (selected != null) return selected;
        }
      } catch (e) {
        Log.logPrint('TV Release 附件解析失败: $e');
      }
    }
    return _fallbackAsset(version);
  }

  Future<String?> downloadLatest({VersionModel? version}) async {
    if (downloading.value) return downloadedFilePath.value;
    final targetVersion = version ?? latestVersion.value;
    if (targetVersion == null) throw StateError('尚未获取远端版本');
    final asset = await resolveAsset(targetVersion);
    if (asset == null) throw StateError('没有找到当前平台的安装包');

    final directory = await _downloadDirectory();
    await directory.create(recursive: true);
    final filePath = p.join(directory.path, _safeFileName(asset.name));
    final file = File(filePath);
    if (await file.exists()) await file.delete();

    downloading.value = true;
    downloadProgress.value = 0;
    downloadedFilePath.value = null;
    errorMessage.value = null;
    final token = CancelToken();
    _downloadToken = token;
    try {
      await HttpClient.instance.dio.download(
        asset.url,
        filePath,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          if (total > 0) downloadProgress.value = received / total;
        },
      );
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('安装包下载为空');
      }
      if (!await _hasPackageSignature(file, asset.name)) {
        throw StateError('下载内容不是有效的安装包，可能是 Release 页面或错误响应');
      }
      downloadProgress.value = 1;
      downloadedFilePath.value = filePath;
      return filePath;
    } catch (e) {
      errorMessage.value = e.toString();
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      _downloadToken = null;
      downloading.value = false;
    }
  }

  void cancelDownload() {
    _downloadToken?.cancel('用户取消下载');
  }

  Future<void> openDownloadedFile() async {
    final path = downloadedFilePath.value;
    if (path == null) return;
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      SmartDialog.showToast(result.message);
    }
  }

  Future<void> openReleasePage() async {
    final url = latestVersion.value?.downloadUrl;
    if (url == null || url.isEmpty) return;
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  String? _releaseTag(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    return segments.isEmpty ? null : segments.last;
  }

  TvAppDownloadAsset? _selectAsset(
    List<TvAppDownloadAsset> assets,
    String version,
  ) {
    final normalized = version.trim();
    if (Platform.isAndroid) {
      return _firstByName(
            assets,
            'simple-live-tv-$normalized-android-universal.apk',
          ) ??
          _firstByExtension(assets, '.apk');
    }
    if (Platform.isWindows) {
      return _firstByName(assets, 'simple-live-$normalized-windows.exe') ??
          _firstByExtension(assets, '.exe') ??
          _firstByExtension(assets, '.zip');
    }
    return null;
  }

  TvAppDownloadAsset? _fallbackAsset(VersionModel version) {
    final tag = _releaseTag(version.downloadUrl);
    if (tag == null) return null;
    final base = 'https://github.com/$repository/releases/download/$tag';
    if (Platform.isAndroid) {
      return TvAppDownloadAsset(
        name: 'simple-live-tv-${version.version}-android-universal.apk',
        url: '$base/simple-live-tv-${version.version}-android-universal.apk',
      );
    }
    if (Platform.isWindows) {
      return TvAppDownloadAsset(
        name: 'simple-live-${version.version}-windows.exe',
        url: '$base/simple-live-${version.version}-windows.exe',
      );
    }
    return null;
  }

  TvAppDownloadAsset? _firstByName(
    List<TvAppDownloadAsset> assets,
    String name,
  ) {
    for (final asset in assets) {
      if (asset.name.toLowerCase() == name.toLowerCase()) return asset;
    }
    return null;
  }

  TvAppDownloadAsset? _firstByExtension(
    List<TvAppDownloadAsset> assets,
    String extension,
  ) {
    for (final asset in assets) {
      if (asset.name.toLowerCase().endsWith(extension)) return asset;
    }
    return null;
  }

  Future<Directory> _downloadDirectory() async {
    if (Platform.isWindows) {
      return await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    if (Platform.isAndroid) {
      return await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    return getApplicationDocumentsDirectory();
  }

  String _safeFileName(String value) {
    final name = p.basename(value).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return name.isEmpty ? 'simple-live-tv-update.apk' : name;
  }

  Future<bool> _hasPackageSignature(File file, String name) async {
    final handle = await file.open();
    try {
      final bytes = await handle.read(2);
      if (name.toLowerCase().endsWith('.exe')) {
        return bytes.length == 2 && bytes[0] == 0x4d && bytes[1] == 0x5a;
      }
      return bytes.length == 2 && bytes[0] == 0x50 && bytes[1] == 0x4b;
    } finally {
      await handle.close();
    }
  }
}
