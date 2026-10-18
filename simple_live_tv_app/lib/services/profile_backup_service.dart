import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/event_bus.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/bulk_data_import_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/douyu_account_service.dart';
import 'package:simple_live_tv_app/services/douyin_account_service.dart';
import 'package:simple_live_tv_app/services/kuaishou_account_service.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';

class ProfileBackupService extends GetxService {
  static ProfileBackupService get instance => Get.find<ProfileBackupService>();

  static const schema = "simple_live_profile";
  static const schemaVersion = 4;
  static const Set<int> _supportedSchemaVersions = {2, 3, 4};
  static bool isSupportedSchemaVersion(int version) =>
      _supportedSchemaVersions.contains(version);
  static const Set<String> _supportedSiteIds = {
    Constant.kBiliBili,
    Constant.kDouyu,
    Constant.kHuya,
    Constant.kDouyin,
    Constant.kKuaishou,
    "xiaohongshu",
  };
  static const Set<String> _platformSpecificSettings = {
    LocalStorageService.kMpvAdvancedOptions,
    LocalStorageService.kCustomPlayerOutput,
    LocalStorageService.kAudioOutputDriver,
    LocalStorageService.kVideoOutputDriver,
    LocalStorageService.kVideoHardwareDecoder,
    LocalStorageService.kPlayerCompatMode,
  };

  static const Set<String> _excludedSettings = {
    LocalStorageService.kFirstRun,
    LocalStorageService.kWebDAVUri,
    LocalStorageService.kWebDAVUser,
    LocalStorageService.kWebDAVPassword,
    LocalStorageService.kWebDAVLastUploadTime,
    LocalStorageService.kWebDAVLastRecoverTime,
    LocalStorageService.kBilibiliCookie,
    LocalStorageService.kDouyinCookie,
    "DouyuCookie",
    "XiaohongshuCookie",
    LocalStorageService.kKuaishouCookie,
    LocalStorageService.kKuaishouKww,
    LocalStorageService.kKuaishouCookieExpiresAt,
    LocalStorageService.kKuaishouSecondaryCookie,
    LocalStorageService.kKuaishouSecondaryKww,
    LocalStorageService.kKuaishouSecondaryCookieExpiresAt,
    LocalStorageService.kKuaishouAccountPoolState,
  };

  Map<String, dynamic> exportProfileMap() {
    final settingsPayload = _exportSettings();
    final accountsPayload = _exportAccounts();
    final shieldPayload = _exportShieldValues();
    final followUsers = DBService.instance
        .getFollowList()
        .map((item) => item.toJson())
        .toList();
    final histories =
        DBService.instance.getHistores().map((item) => item.toJson()).toList();
    return {
      "schema": schema,
      "schemaVersion": schemaVersion,
      "appVersion": Utils.packageInfo.version,
      "platform": Platform.operatingSystem,
      "exportedAt": DateTime.now().toIso8601String(),
      "settings": settingsPayload,
      "accounts": accountsPayload,
      "danmuShield": shieldPayload,
      "followUsers": followUsers,
      "histories": histories,
      "summary": {
        "settingCount": settingsPayload.length,
        "keywordShieldCount": (shieldPayload["keywords"] as List).length,
        "followUserCount": followUsers.length,
        "historyCount": histories.length,
        "accountCount": _countConfiguredAccounts(accountsPayload["items"]),
      },
    };
  }

  String exportProfileJson() {
    return const JsonEncoder.withIndent("  ").convert(exportProfileMap());
  }

  Future<ProfileImportSummary> importProfileJson(
    String content, {
    bool overwrite = false,
    ProfileImportOptions options = const ProfileImportOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    onProgress?.call(const SyncProgress(stage: "解析配置包"));
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException("不是 Simple Live 配置包");
    }
    final payload = decoded.cast<String, dynamic>();
    if (payload["schema"] == schema) {
      final version = (payload["schemaVersion"] as num?)?.toInt() ?? 2;
      if (!isSupportedSchemaVersion(version)) {
        throw const FormatException("暂不支持该配置包版本");
      }
      return importProfileMap(
        payload,
        overwrite: overwrite,
        options: options,
        allowLegacyAccountSettings: version < schemaVersion,
        onProgress: onProgress,
      );
    }
    if (payload["type"] == "simple_live") {
      return importLegacyProfileMap(
        payload,
        overwrite: overwrite,
        options: options,
        onProgress: onProgress,
      );
    }
    if (_looksLikeLegacyDataFile(payload)) {
      return importLegacyDataFileMap(
        payload,
        overwrite: overwrite,
        options: options,
        onProgress: onProgress,
      );
    }
    throw const FormatException("不是 Simple Live 配置包");
  }

  Future<ProfileImportSummary> importProfileMap(
    Map<String, dynamic> payload, {
    bool overwrite = false,
    ProfileImportOptions options = const ProfileImportOptions(),
    bool allowLegacyAccountSettings = false,
    SyncProgressCallback? onProgress,
  }) async {
    final summary = ProfileImportSummary();
    if (options.settings) {
      onProgress?.call(const SyncProgress(stage: "导入设置"));
      await _importSettings(
        payload["settings"],
        summary,
        overwrite,
        sourcePlatform: payload["platform"],
      );
    }
    if (options.shields) {
      await _importShields(
        payload["danmuShield"],
        summary,
        overwrite,
        onProgress,
      );
    }
    if (options.accounts) {
      summary.accounts += await _importAccounts(
        payload["accounts"],
        summary: summary,
        legacySettings: payload["settings"],
        allowLegacySettings: allowLegacyAccountSettings,
        accountSiteIds: options.accountSiteIds,
      );
    }
    if (options.follows) {
      await _importFollowUsers(
        _readPayloadList(payload, const [
          "followUsers",
          "follows",
          "favorites",
        ]),
        summary,
        overwrite,
        onProgress,
      );
    }
    if (options.histories) {
      await _importHistories(
        _readPayloadList(payload, const ["histories", "history"]),
        summary,
        overwrite,
        onProgress,
      );
    }

    if (options.settings || options.shields) {
      AppSettingsController.instance.onInit();
    }
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    EventBus.instance.emit(Constant.kUpdateHistory, 0);
    return summary;
  }

  Future<ProfileImportSummary> importLegacyProfileMap(
    Map<String, dynamic> payload, {
    bool overwrite = false,
    ProfileImportOptions options = const ProfileImportOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    final summary = ProfileImportSummary();
    if (options.settings) {
      onProgress?.call(const SyncProgress(stage: "导入设置"));
      await _importSettings(payload["config"], summary, overwrite);
    }
    if (options.accounts) {
      summary.accounts += await _importAccounts(
        null,
        summary: summary,
        legacySettings: payload["config"],
        allowLegacySettings: true,
        accountSiteIds: options.accountSiteIds,
      );
    }
    if (options.shields) {
      await _importShields(
        {"raw": _legacyShieldValues(payload["shield"])},
        summary,
        overwrite,
        onProgress,
      );
    }
    if (options.settings || options.shields) {
      AppSettingsController.instance.onInit();
    }
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    EventBus.instance.emit(Constant.kUpdateHistory, 0);
    return summary;
  }

  Future<ProfileImportSummary> importLegacyDataFileMap(
    Map<String, dynamic> payload, {
    bool overwrite = false,
    ProfileImportOptions options = const ProfileImportOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    final summary = ProfileImportSummary();
    if (payload["data"] is List) {
      await _importLegacyDataList(
        payload["data"],
        summary,
        overwrite,
        options,
        onProgress,
      );
    } else {
      if (options.follows) {
        await _importFollowUsers(
          _readPayloadList(payload, const [
            "followUsers",
            "follows",
            "favorites",
          ]),
          summary,
          overwrite,
          onProgress,
        );
      }
      if (options.histories) {
        await _importHistories(
          _readPayloadList(payload, const ["histories", "history"]),
          summary,
          overwrite,
          onProgress,
        );
      }
    }
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    EventBus.instance.emit(Constant.kUpdateHistory, 0);
    return summary;
  }

  bool _looksLikeLegacyDataFile(dynamic payload) {
    if (payload is! Map) {
      return false;
    }
    if (payload["data"] is List) {
      return true;
    }
    const keys = {
      "followUsers",
      "follows",
      "favorites",
      "histories",
      "history",
    };
    return keys.any((key) {
      final value = payload[key];
      return value is List || (value is Map && value["data"] is List);
    });
  }

  Map<String, dynamic> _exportSettings() {
    return filterTransportSettings(
      LocalStorageService.instance.settingsBox.toMap(),
    );
  }

  /// Removes identity, credentials, and device-local values from settings
  /// JSON files in older WebDAV archives.
  Map<String, dynamic> filterTransportSettings(
    Map<dynamic, dynamic> settings,
  ) =>
      {
        for (final entry in settings.entries)
          if (!_excludedSettings.contains(entry.key.toString()))
            entry.key.toString(): _safeJsonValue(entry.value),
      };

  Future<ProfileImportSummary> importLegacySettingsMap(
    dynamic rawSettings, {
    bool overwrite = true,
  }) async {
    final summary = ProfileImportSummary();
    await _importSettings(rawSettings, summary, overwrite);
    AppSettingsController.instance.onInit();
    return summary;
  }

  Map<String, dynamic> _exportAccounts() {
    return {
      "items": [
        {
          "siteId": Constant.kBiliBili,
          "cookie": LocalStorageService.instance.getValue(
            LocalStorageService.kBilibiliCookie,
            "",
          ),
        },
        {
          "siteId": Constant.kDouyin,
          "cookie": LocalStorageService.instance.getValue(
            LocalStorageService.kDouyinCookie,
            "",
          ),
        },
        {
          "siteId": Constant.kDouyu,
          "cookie": DouyuAccountService.instance.cookie,
        },
        {
          "siteId": "xiaohongshu",
          "cookie": XiaohongshuAccountService.instance.cookie,
        },
        {
          "siteId": Constant.kKuaishou,
          ...KuaishouAccountService.instance.exportBackupMap(),
        },
      ],
    };
  }

  int _countConfiguredAccounts(dynamic rawItems) {
    if (rawItems is! List) {
      return 0;
    }
    return rawItems.where((item) {
      if (item is! Map) {
        return false;
      }
      if (item["siteId"] == Constant.kKuaishou) {
        final slots = item["slots"];
        return slots is Map &&
            slots.values.any(
              (slot) =>
                  slot is Map &&
                  (slot["cookie"]?.toString().trim().isNotEmpty ?? false),
            );
      }
      return item["cookie"]?.toString().trim().isNotEmpty ?? false;
    }).length;
  }

  Map<String, dynamic> _exportShieldValues() {
    final keywords = AppSettingsController.instance.shieldList.toList()..sort();
    final raw = LocalStorageService.instance.shieldBox.values
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort();
    return {
      "raw": raw,
      "keywords": keywords,
      "users": const [],
      "userGroups": const <String, List<String>>{},
    };
  }

  Future<void> _importSettings(
    dynamic rawSettings,
    ProfileImportSummary summary,
    bool overwrite, {
    dynamic sourcePlatform,
  }) async {
    if (rawSettings is! Map) {
      return;
    }
    final samePlatform = _isSamePlatform(sourcePlatform);
    if (overwrite) {
      await _clearImportableSettings(preservePlatformSettings: !samePlatform);
    }
    final values = <dynamic, dynamic>{};
    for (final entry in rawSettings.entries) {
      final key = entry.key.toString();
      if (_excludedSettings.contains(key)) {
        continue;
      }
      if (!samePlatform && _platformSpecificSettings.contains(key)) {
        summary.droppedPlatformSettings++;
        continue;
      }
      values[key] = entry.value;
    }
    await LocalStorageService.instance.settingsBox.putAll(values);
    summary.settings = values.length;
  }

  bool _isSamePlatform(dynamic sourcePlatform) =>
      sourcePlatform is String &&
      sourcePlatform.trim().isNotEmpty &&
      sourcePlatform.trim().toLowerCase() == Platform.operatingSystem;

  Future<void> _clearImportableSettings({
    required bool preservePlatformSettings,
  }) async {
    final keys = LocalStorageService.instance.settingsBox.keys.where((key) {
      final name = key.toString();
      return !_excludedSettings.contains(name) &&
          (!preservePlatformSettings ||
              !_platformSpecificSettings.contains(name));
    }).toList();
    if (keys.isNotEmpty) {
      await LocalStorageService.instance.settingsBox.deleteAll(keys);
    }
  }

  Future<void> _importShields(
    dynamic rawShield,
    ProfileImportSummary summary,
    bool overwrite,
    SyncProgressCallback? onProgress,
  ) async {
    if (rawShield is! Map) {
      return;
    }
    final rawValues = rawShield["raw"];
    final keywords = rawShield["keywords"];
    final values = <String>[
      if (rawValues is List) ...rawValues.map((e) => e.toString()),
      if (keywords is List) ...keywords.map((e) => e.toString()),
    ];
    if (values.isEmpty) {
      return;
    }
    final result = await BulkDataImportService.importShieldValues(
      values,
      overwrite: overwrite,
      onProgress: onProgress,
    );
    summary.shields += result.imported;
    summary.skipped += result.skipped;
  }

  Future<int> _importAccounts(
    dynamic rawAccounts, {
    required ProfileImportSummary summary,
    dynamic legacySettings,
    bool allowLegacySettings = false,
    Set<String>? accountSiteIds,
  }) async {
    var imported = 0;
    final items = rawAccounts is Map && rawAccounts["items"] is List
        ? rawAccounts["items"] as List
        : const [];
    var importedKuaishou = false;
    final importedSites = <String>{};
    for (final item in items) {
      if (item is! Map) {
        summary.skipped++;
        continue;
      }
      final siteId = item["siteId"]?.toString().trim().toLowerCase() ?? "";
      if (!_supportedSiteIds.contains(siteId) ||
          (accountSiteIds != null && !accountSiteIds.contains(siteId))) {
        if (!_supportedSiteIds.contains(siteId)) {
          summary.skipped++;
        }
        continue;
      }
      if (!item.containsKey("cookie") && siteId != Constant.kKuaishou) {
        summary.skipped++;
        continue;
      }
      final cookie = item["cookie"]?.toString() ?? "";
      switch (siteId) {
        case Constant.kBiliBili:
          if (cookie.isEmpty) {
            break;
          }
          BiliBiliAccountService.instance.setCookie(cookie);
          imported++;
          importedSites.add(siteId);
          break;
        case Constant.kDouyin:
          if (cookie.isEmpty) {
            break;
          }
          DouyinAccountService.instance.setCookie(cookie);
          imported++;
          importedSites.add(siteId);
          break;
        case Constant.kDouyu:
          if (cookie.isEmpty) {
            break;
          }
          if (!await DouyuAccountService.instance.setCookie(cookie)) {
            throw const FormatException("斗鱼 Cookie 格式无效");
          }
          imported++;
          importedSites.add(siteId);
          break;
        case Constant.kXiaohongshu:
          if (cookie.isEmpty) {
            break;
          }
          if (!await XiaohongshuAccountService.instance.setCookie(cookie)) {
            throw const FormatException("小红书 Cookie 格式无效");
          }
          imported++;
          importedSites.add(siteId);
          break;
        case Constant.kKuaishou:
          if (!_hasKuaishouCredentials(item)) {
            break;
          }
          importedKuaishou = true;
          KuaishouAccountService.instance.importBackupMap(
            _mergeKuaishouBackupPreservingMissingSlots(
              item,
              legacySettings: allowLegacySettings ? legacySettings : null,
            ),
          );
          imported++;
          importedSites.add(siteId);
          break;
      }
    }
    if (allowLegacySettings && legacySettings is Map) {
      final legacyCookies = <String, String>{
        Constant.kBiliBili: LocalStorageService.kBilibiliCookie,
        Constant.kDouyin: LocalStorageService.kDouyinCookie,
        Constant.kDouyu: "DouyuCookie",
        "xiaohongshu": "XiaohongshuCookie",
      };
      for (final entry in legacyCookies.entries) {
        if (importedSites.contains(entry.key) ||
            (accountSiteIds != null && !accountSiteIds.contains(entry.key)) ||
            !legacySettings.containsKey(entry.value)) {
          continue;
        }
        final cookie = legacySettings[entry.value]?.toString() ?? "";
        if (cookie.isEmpty) {
          continue;
        }
        switch (entry.key) {
          case Constant.kBiliBili:
            BiliBiliAccountService.instance.setCookie(cookie);
            imported++;
            break;
          case Constant.kDouyin:
            DouyinAccountService.instance.setCookie(cookie);
            imported++;
            break;
          case Constant.kDouyu:
            if (!await DouyuAccountService.instance.setCookie(cookie)) {
              throw const FormatException("斗鱼 Cookie 格式无效");
            }
            imported++;
            break;
          case Constant.kXiaohongshu:
            if (!await XiaohongshuAccountService.instance.setCookie(cookie)) {
              throw const FormatException("小红书 Cookie 格式无效");
            }
            imported++;
            break;
        }
      }
    }
    if (allowLegacySettings &&
        !importedKuaishou &&
        (accountSiteIds == null ||
            accountSiteIds.contains(Constant.kKuaishou)) &&
        legacySettings is Map) {
      final hasLegacyKuaishou = const {
        LocalStorageService.kKuaishouCookie,
        LocalStorageService.kKuaishouKww,
        LocalStorageService.kKuaishouCookieExpiresAt,
        LocalStorageService.kKuaishouSecondaryCookie,
        LocalStorageService.kKuaishouSecondaryKww,
        LocalStorageService.kKuaishouSecondaryCookieExpiresAt,
        LocalStorageService.kKuaishouAccountPoolState,
      }.any(legacySettings.containsKey);
      if (hasLegacyKuaishou) {
        final legacyKuaishou = {
          'cookie': legacySettings[LocalStorageService.kKuaishouCookie],
          'kww': legacySettings[LocalStorageService.kKuaishouKww],
          'cookieExpiresAt':
              legacySettings[LocalStorageService.kKuaishouCookieExpiresAt],
        };
        if (_hasKuaishouCredentials(legacyKuaishou) ||
            _hasKuaishouCredentials(legacySettings)) {
          KuaishouAccountService.instance.importBackupMap(
            _mergeKuaishouBackupPreservingMissingSlots(
              legacyKuaishou,
              legacySettings: legacySettings,
            ),
          );
          imported++;
        }
      }
    }
    return imported;
  }

  bool _hasKuaishouCredentials(dynamic item) {
    if (item is! Map) {
      return false;
    }
    bool hasCookie(dynamic value) =>
        value is Map &&
        (value['cookie']?.toString().trim().isNotEmpty ?? false);
    if (hasCookie(item)) {
      return true;
    }
    final slots = item['slots'];
    if (slots is Map && slots.values.any(hasCookie)) {
      return true;
    }
    return const {
      LocalStorageService.kKuaishouCookie,
      LocalStorageService.kKuaishouSecondaryCookie,
    }.any((key) => item[key]?.toString().trim().isNotEmpty ?? false);
  }

  Map<String, dynamic> _mergeKuaishouBackupPreservingMissingSlots(
    dynamic raw, {
    dynamic legacySettings,
  }) {
    final incoming = migrateKuaishouAccountBackup(
      raw,
      legacySettings: legacySettings,
    );
    final incomingSlots = incoming['slots'];
    final currentSlots =
        KuaishouAccountService.instance.exportBackupMap()['slots'];
    if (incomingSlots is! Map || currentSlots is! Map) {
      return incoming;
    }

    final mergedSlots = <String, dynamic>{};
    for (final slot in const ['primary', 'secondary']) {
      final incomingSlot = incomingSlots[slot];
      mergedSlots[slot] = _hasKuaishouCredentials(incomingSlot)
          ? incomingSlot
          : currentSlots[slot];
    }
    return {...incoming, 'slots': mergedSlots};
  }

  Future<void> _importFollowUsers(
    dynamic rawUsers,
    ProfileImportSummary summary,
    bool overwrite,
    SyncProgressCallback? onProgress,
  ) async {
    if (rawUsers is! List) {
      return;
    }
    final knownUsers = _filterKnownSiteItems(rawUsers, summary);
    if (knownUsers.isEmpty && rawUsers.isNotEmpty) {
      return;
    }
    final result = await BulkDataImportService.importFollowUsers(
      knownUsers,
      overwrite: overwrite && knownUsers.length == rawUsers.length,
      onProgress: onProgress,
    );
    summary.followUsers += result.imported;
    summary.skipped += result.skipped;
  }

  Future<void> _importHistories(
    dynamic rawHistories,
    ProfileImportSummary summary,
    bool overwrite,
    SyncProgressCallback? onProgress,
  ) async {
    if (rawHistories is! List) {
      return;
    }
    final knownHistories = _filterKnownSiteItems(rawHistories, summary);
    if (knownHistories.isEmpty && rawHistories.isNotEmpty) {
      return;
    }
    final result = await BulkDataImportService.importHistories(
      knownHistories,
      overwrite: overwrite && knownHistories.length == rawHistories.length,
      onProgress: onProgress,
    );
    summary.histories += result.imported;
    summary.skipped += result.skipped;
  }

  List<dynamic> _filterKnownSiteItems(
    List<dynamic> items,
    ProfileImportSummary summary,
  ) {
    final filtered = <dynamic>[];
    for (final item in items) {
      if (item is Map &&
          _supportedSiteIds.contains(
            item["siteId"]?.toString().trim().toLowerCase(),
          )) {
        filtered.add(item);
      } else {
        summary.skipped++;
      }
    }
    return filtered;
  }

  dynamic _readPayloadList(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is List) {
        return value;
      }
      if (value is Map && value["data"] is List) {
        return value["data"];
      }
    }
    return null;
  }

  Future<void> _importLegacyDataList(
    dynamic rawList,
    ProfileImportSummary summary,
    bool overwrite,
    ProfileImportOptions options,
    SyncProgressCallback? onProgress,
  ) async {
    if (rawList is! List || rawList.isEmpty) {
      return;
    }
    Map? firstMap;
    for (final item in rawList) {
      if (item is Map) {
        firstMap = item;
        break;
      }
    }
    if (firstMap != null) {
      if (firstMap.containsKey("updateTime")) {
        if (options.histories) {
          await _importHistories(rawList, summary, overwrite, onProgress);
        }
        return;
      }
      if (firstMap.containsKey("roomId") || firstMap.containsKey("siteId")) {
        if (options.follows) {
          await _importFollowUsers(rawList, summary, overwrite, onProgress);
        }
        return;
      }
    }
    if (options.shields && rawList.every((item) => item is String)) {
      await _importShields({"raw": rawList}, summary, overwrite, onProgress);
    }
  }

  List<String> _legacyShieldValues(dynamic rawShield) {
    if (rawShield is! Map) {
      return const [];
    }
    return rawShield.values
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  dynamic _safeJsonValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Iterable) {
      return value.map(_safeJsonValue).toList();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _safeJsonValue(entry.value),
      };
    }
    return value.toString();
  }
}

class ProfileImportOptions {
  final bool settings;
  final bool accounts;
  final bool shields;
  final bool follows;
  final bool histories;
  final Set<String>? accountSiteIds;

  const ProfileImportOptions({
    this.settings = true,
    this.accounts = true,
    this.shields = true,
    this.follows = true,
    this.histories = true,
    this.accountSiteIds,
  });
}

class ProfileImportSummary {
  int settings = 0;
  int accounts = 0;
  int shields = 0;
  int followUsers = 0;
  int histories = 0;
  int skipped = 0;
  int droppedPlatformSettings = 0;

  String get message {
    final parts = <String>[
      "设置 $settings 项",
      "账号 $accounts 个",
      "屏蔽 $shields 项",
      "关注 $followUsers 个",
      "历史 $histories 条",
      if (droppedPlatformSettings > 0) "跳过其他平台播放器设置 $droppedPlatformSettings 项",
      if (skipped > 0) "跳过异常 $skipped 条",
    ];
    return parts.join("，");
  }
}
