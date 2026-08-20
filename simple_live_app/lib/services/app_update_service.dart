import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/generated/app_update_channel.g.dart';
import 'package:simple_live_app/generated/app_version.g.dart';
import 'package:simple_live_app/models/app_update_model.dart';
import 'package:simple_live_app/requests/http_error.dart';
import 'package:simple_live_app/requests/http_client.dart' as requests;
import 'package:simple_live_app/services/local_storage_service.dart';

class AppUpdateService {
  AppUpdateService({
    requests.HttpClient? httpClient,
    DeviceInfoPlugin? deviceInfo,
  })  : _httpClient = httpClient ?? requests.HttpClient.instance,
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  static const repository = 'xuanxuan123xuan/dart_simple_live';
  static const releasesApiUrl =
      'https://api.github.com/repos/$repository/releases';
  static const releasesPageUrl = 'https://github.com/$repository/releases';
  static const _preferredChannelKey = 'AppUpdatePreferredChannel';
  static const _preferredPackageKeyPrefix = 'AppUpdatePreferredPackage:';
  static const _autoCheckEnabledKey = 'AppUpdateAutoCheckEnabled';
  static final instance = AppUpdateService();

  final requests.HttpClient _httpClient;
  final DeviceInfoPlugin _deviceInfo;

  final RxBool autoCheckEnabled = true.obs;
  final RxBool backgroundChecking = false.obs;
  final RxBool updateAvailable = false.obs;
  final RxnString updateVersion = RxnString();
  final Rxn<DateTime> lastCheckedAt = Rxn<DateTime>();
  final Rxn<AppUpdateCatalog> latestCatalog = Rxn<AppUpdateCatalog>();
  final Rxn<AppUpdateRelease> latestRelease = Rxn<AppUpdateRelease>();
  final RxnString lastErrorMessage = RxnString();

  Future<void> init() async {
    autoCheckEnabled.value = LocalStorageService.instance.getValue(
      _autoCheckEnabledKey,
      true,
    );
  }

  AppUpdateChannel get defaultChannel => AppUpdateChannel.fromValue(
        GeneratedAppUpdateChannel.channel,
      );

  int get currentBuildNumber =>
      int.tryParse(GeneratedAppVersion.buildNumber) ??
      int.tryParse(Utils.packageInfo.buildNumber) ??
      0;

  String get currentVersion => GeneratedAppVersion.fullVersion;

  AppUpdateChannel get preferredChannel {
    final value = LocalStorageService.instance.getValue<String>(
      _preferredChannelKey,
      defaultChannel.label,
    );
    return AppUpdateChannel.fromValue(value);
  }

  Future<void> setPreferredChannel(AppUpdateChannel channel) {
    return LocalStorageService.instance.setValue(
      _preferredChannelKey,
      channel.label,
    );
  }

  Future<void> setPreferredSelection(AppUpdateSelection selection) {
    return LocalStorageService.instance.setValue(
      _preferredPackageKeyPrefix + selection.platform.name,
      selection.key,
    );
  }

  String? preferredSelectionKey(AppUpdatePlatform platform) {
    final value = LocalStorageService.instance.getValue<String>(
      _preferredPackageKeyPrefix + platform.name,
      '',
    );
    return value.isEmpty ? null : value;
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    autoCheckEnabled.value = enabled;
    await LocalStorageService.instance.setValue(
      _autoCheckEnabledKey,
      enabled,
    );
  }

  bool isNewerThanCurrent(AppUpdateRelease release) {
    return release.buildNumber > currentBuildNumber;
  }

  Future<AppUpdateCheckResult> checkForUpdates({
    AppUpdateChannel? channel,
  }) async {
    final selectedChannel = channel ?? preferredChannel;
    final catalog = await fetchCatalog();
    final release = catalog.releaseForChannel(selectedChannel);
    recordCheckResult(
      catalog: catalog,
      release: release,
      checkedAt: DateTime.now(),
    );
    return AppUpdateCheckResult(
      catalog: catalog,
      selectedChannel: selectedChannel,
      release: release,
      hasUpdate: release != null && isNewerThanCurrent(release),
    );
  }

  Future<void> checkUpdatesInBackground() async {
    if (!autoCheckEnabled.value || backgroundChecking.value) {
      return;
    }
    backgroundChecking.value = true;
    lastErrorMessage.value = null;
    try {
      final result = await checkForUpdates();
      if (result.hasUpdate) {
        Log.i('发现新版本 ${result.release!.version}');
      }
    } catch (e, stackTrace) {
      Log.logPrint('自动检查更新失败: $e\n$stackTrace');
      lastErrorMessage.value = e.toString();
    } finally {
      backgroundChecking.value = false;
    }
  }

  void recordCheckResult({
    required AppUpdateCatalog catalog,
    required AppUpdateRelease? release,
    required DateTime checkedAt,
  }) {
    latestCatalog.value = catalog;
    latestRelease.value = release;
    lastCheckedAt.value = checkedAt;
    final hasNewVersion = release != null && isNewerThanCurrent(release);
    updateAvailable.value = hasNewVersion;
    updateVersion.value = hasNewVersion ? release.version : null;
  }

  Future<AppUpdateCatalog> fetchCatalog() async {
    final result = await _fetchReleasesJson();
    if (result is! List) {
      throw const FormatException('GitHub Releases 响应格式异常');
    }

    AppUpdateRelease? stable;
    AppUpdateRelease? dev;
    for (final item in result.whereType<Map>()) {
      final release = parseRelease(Map<String, dynamic>.from(item));
      if (release == null) {
        continue;
      }
      switch (release.channel) {
        case AppUpdateChannel.stable:
          stable ??= release;
          break;
        case AppUpdateChannel.dev:
          dev ??= release;
          break;
      }
      if (stable != null && dev != null) {
        break;
      }
    }

    return AppUpdateCatalog(stable: stable, dev: dev);
  }

  Future<dynamic> _fetchReleasesJson() async {
    try {
      return await _httpClient.getJson(
        releasesApiUrl,
        queryParameters: {'per_page': 50},
        header: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
    } on HttpError catch (error) {
      throw AppUpdateException(_formatFetchError(error));
    }
  }

  String _formatFetchError(HttpError error) {
    if (error.statusCode == 403) {
      return 'GitHub API 暂时拒绝访问，可能是请求频率限制或网络代理拦截。';
    }
    if (error.statusCode == 404) {
      return '没有找到 GitHub Releases，请确认仓库地址是否正确。';
    }
    final message = error.toString();
    if (message.contains('连接失败') ||
        message.contains('连接超时') ||
        message.contains('接收超时') ||
        message.contains('发送GET请求失败')) {
      return '无法连接 GitHub Releases，请检查网络、代理或稍后重试。';
    }
    return '获取 GitHub Releases 失败：$message';
  }

  Future<AppUpdatePlatform?> detectCurrentPlatform() async {
    if (Platform.operatingSystem == 'ohos') {
      return AppUpdatePlatform.ohos;
    }
    if (Platform.isAndroid) {
      return AppUpdatePlatform.android;
    }
    if (Platform.isWindows) {
      return AppUpdatePlatform.windows;
    }
    if (Platform.isLinux) {
      return AppUpdatePlatform.linux;
    }
    if (Platform.isMacOS) {
      return AppUpdatePlatform.macos;
    }
    return null;
  }

  Future<List<String>> detectAndroidAbis() async {
    if (!Platform.isAndroid) {
      return const [];
    }
    try {
      final info = await _deviceInfo.androidInfo;
      return info.supportedAbis;
    } catch (_) {
      return const [];
    }
  }

  Future<AppUpdateAsset?> pickRecommendedAsset(
    AppUpdateRelease release, {
    AppUpdatePlatform? platform,
  }) async {
    final currentPlatform = platform ?? await detectCurrentPlatform();
    if (currentPlatform == null) {
      return null;
    }
    final candidates = release.assets
        .where((asset) => asset.platform == currentPlatform)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }

    final preferredKey = preferredSelectionKey(currentPlatform);
    if (preferredKey != null) {
      final preferred = candidates.where((asset) {
        final selection = AppUpdateSelection(
          platform: asset.platform,
          packageKind: asset.kind,
          abi: asset.abi,
        );
        return selection.key == preferredKey;
      }).firstOrNull;
      if (preferred != null) {
        return preferred;
      }
    }

    if (currentPlatform == AppUpdatePlatform.android) {
      return _pickAndroidAsset(candidates);
    }
    return switch (currentPlatform) {
      AppUpdatePlatform.windows => _pickByKind(candidates, const [
          AppUpdatePackageKind.exe,
          AppUpdatePackageKind.zip,
        ]),
      AppUpdatePlatform.linux => _pickByKind(candidates, const [
          AppUpdatePackageKind.appImage,
          AppUpdatePackageKind.deb,
        ]),
      AppUpdatePlatform.macos => _pickByKind(candidates, const [
          AppUpdatePackageKind.dmg,
        ]),
      AppUpdatePlatform.ohos => _pickByKind(candidates, const [
          AppUpdatePackageKind.hap,
        ]),
      AppUpdatePlatform.tv => _pickByKind(candidates, const [
          AppUpdatePackageKind.apk,
        ]),
      AppUpdatePlatform.android => candidates.firstOrNull,
    };
  }

  static AppUpdateRelease? parseRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final channel = channelFromTag(tag);
    if (channel == null) {
      return null;
    }
    final version = versionFromTag(tag);
    if (version == null) {
      return null;
    }
    final body = json['body'] as String? ?? '';
    final sha256 = parseSha256(body);
    final assetsJson = json['assets'];
    final assets = <AppUpdateAsset>[];
    if (assetsJson is List) {
      for (final item in assetsJson.whereType<Map>()) {
        final asset = parseAsset(
          Map<String, dynamic>.from(item),
          sha256: sha256,
        );
        if (asset != null && asset.platform != AppUpdatePlatform.tv) {
          assets.add(asset);
        }
      }
    }
    assets.sort(compareAssets);

    return AppUpdateRelease(
      channel: channel,
      tag: tag,
      version: version,
      buildNumber: buildNumberFromVersion(version),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      assets: assets,
      body: body,
      releaseUrl: json['html_url'] as String? ?? releasesPageUrl,
    );
  }

  static AppUpdateChannel? channelFromTag(String tag) {
    if (RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      return AppUpdateChannel.stable;
    }
    if (RegExp(r'^v\d+\.\d+\.\d+-dev$').hasMatch(tag)) {
      return AppUpdateChannel.dev;
    }
    return null;
  }

  static String? versionFromTag(String tag) {
    return RegExp(r'^v(\d+\.\d+\.\d+)(?:-dev)?$').firstMatch(tag)?.group(1);
  }

  static int buildNumberFromVersion(String version) {
    final parts = version.split('.').map(int.tryParse).toList();
    if (parts.length != 3 || parts.any((item) => item == null)) {
      return 0;
    }
    return parts[0]! * 10000 + parts[1]! * 100 + parts[2]!;
  }

  static Map<String, String> parseSha256(String body) {
    final values = <String, String>{};
    for (final match in RegExp(
      r'\b([a-fA-F0-9]{64})\s+([\w.\-+]+)',
    ).allMatches(body)) {
      values[match.group(2)!] = match.group(1)!.toLowerCase();
    }
    return values;
  }

  static AppUpdateAsset? parseAsset(
    Map<String, dynamic> json, {
    Map<String, String> sha256 = const {},
  }) {
    final name = json['name'] as String? ?? '';
    final platform = AppUpdatePlatform.fromAssetName(name);
    final kind = AppUpdatePackageKind.fromFileName(name);
    final url = json['browser_download_url'] as String? ?? '';
    if (platform == null || kind == null || url.isEmpty) {
      return null;
    }

    return AppUpdateAsset(
      name: name,
      url: url,
      platform: platform,
      kind: kind,
      abi: _abiFromAssetName(name),
      size: json['size'] as int?,
      sha256: sha256[name],
    );
  }

  static int compareAssets(AppUpdateAsset left, AppUpdateAsset right) {
    final platformCompare = left.platform.index.compareTo(right.platform.index);
    if (platformCompare != 0) {
      return platformCompare;
    }
    final leftScore = _kindScore(left.kind);
    final rightScore = _kindScore(right.kind);
    if (leftScore != rightScore) {
      return leftScore.compareTo(rightScore);
    }
    return left.name.compareTo(right.name);
  }

  static int _kindScore(AppUpdatePackageKind kind) => switch (kind) {
        AppUpdatePackageKind.exe => 0,
        AppUpdatePackageKind.appImage => 0,
        AppUpdatePackageKind.dmg => 0,
        AppUpdatePackageKind.hap => 0,
        AppUpdatePackageKind.apk => 1,
        AppUpdatePackageKind.deb => 2,
        AppUpdatePackageKind.zip => 3,
        AppUpdatePackageKind.aab => 9,
        AppUpdatePackageKind.ipa => 9,
      };

  AppUpdateAsset? _pickByKind(
    List<AppUpdateAsset> candidates,
    List<AppUpdatePackageKind> kinds,
  ) {
    for (final kind in kinds) {
      final asset = candidates.where((item) => item.kind == kind).firstOrNull;
      if (asset != null) {
        return asset;
      }
    }
    return candidates.firstOrNull;
  }

  Future<AppUpdateAsset?> _pickAndroidAsset(
    List<AppUpdateAsset> candidates,
  ) async {
    final abis = await detectAndroidAbis();
    for (final abi in abis) {
      final matched = candidates.where((item) => item.abi == abi).firstOrNull;
      if (matched != null) {
        return matched;
      }
    }
    return candidates.where((item) => item.abi == 'universal').firstOrNull ??
        candidates.firstOrNull;
  }

  static String? _abiFromAssetName(String name) {
    final lower = name.toLowerCase();
    for (final abi in const [
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
      'universal',
      'arm64',
    ]) {
      if (lower.contains('-$abi.')) {
        return abi;
      }
      if (lower.contains('-$abi-')) {
        return abi;
      }
    }
    return null;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String appUpdateCatalogToJson(AppUpdateCatalog catalog) {
  return jsonEncode({
    'stable': catalog.stable?.tag,
    'dev': catalog.dev?.tag,
  });
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.catalog,
    required this.selectedChannel,
    required this.release,
    required this.hasUpdate,
  });

  final AppUpdateCatalog catalog;
  final AppUpdateChannel selectedChannel;
  final AppUpdateRelease? release;
  final bool hasUpdate;
}
