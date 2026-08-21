import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/bulk_data_import_service.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class ProfileBackupService extends GetxService {
  static ProfileBackupService get instance => Get.find<ProfileBackupService>();

  static const schema = "simple_live_profile";
  static const schemaVersion = 4;
  static const Set<int> _supportedSchemaVersions = {1, 2, 3, 4};

  static const Set<String> _excludedSettings = {
    LocalStorageService.kFirstRun,
    LocalStorageService.kLastLiveRoom,
    LocalStorageService.kLastLiveRoomResumePending,
    LocalStorageService.kWebDAVUri,
    LocalStorageService.kWebDAVUser,
    LocalStorageService.kWebDAVPassword,
    LocalStorageService.kWebDAVLastUploadTime,
    LocalStorageService.kWebDAVLastRecoverTime,
    LocalStorageService.kBilibiliCookie,
    LocalStorageService.kDouyinCookie,
    LocalStorageService.kKuaishouCookie,
    LocalStorageService.kKuaishouKww,
    LocalStorageService.kKuaishouCookieExpiresAt,
    LocalStorageService.kKuaishouSecondaryCookie,
    LocalStorageService.kKuaishouSecondaryKww,
    LocalStorageService.kKuaishouSecondaryCookieExpiresAt,
    LocalStorageService.kKuaishouAccountPoolState,
  };

  Map<String, dynamic> exportProfileMap({
    ProfileExportOptions options = const ProfileExportOptions(),
  }) {
    final shieldPayload = options.shields
        ? _exportShieldValues()
        : {
            "raw": const [],
            "keywords": const [],
            "users": const [],
            "userGroups": const <String, List<String>>{},
          };
    final settingsPayload =
        options.settings ? _exportSettings() : <String, dynamic>{};
    final accountsPayload =
        options.accounts ? _exportAccounts() : {"items": const []};
    final shieldPresetsPayload =
        options.shieldPresets ? _exportShieldPresets() : const [];
    final followUsers = options.follows
        ? DBService.instance
            .getFollowList()
            .map((item) => item.toJson())
            .toList()
        : const [];
    final followUserTags = options.follows
        ? DBService.instance
            .getFollowTagList()
            .map((item) => item.toJson())
            .toList()
        : const [];
    final histories = options.histories
        ? DBService.instance
            .getHistores()
            .map((item) => item.toJson())
            .toList()
        : const [];
    return {
      "schema": schema,
      "schemaVersion": schemaVersion,
      "appVersion": Utils.packageInfo.version,
      "platform": Platform.operatingSystem,
      "exportedAt": DateTime.now().toIso8601String(),
      "included": options.toJson(),
      if (options.settings) "settings": settingsPayload,
      if (options.accounts) "accounts": accountsPayload,
      if (options.shields) "danmuShield": shieldPayload,
      if (options.shieldPresets) "shieldPresets": shieldPresetsPayload,
      if (options.follows) "followUsers": followUsers,
      if (options.follows) "followUserTags": followUserTags,
      if (options.histories) "histories": histories,
      "summary": {
        "settingCount": settingsPayload.length,
        "keywordShieldCount": (shieldPayload["keywords"] as List).length,
        "userShieldCount": (shieldPayload["users"] as List).length,
        "followUserCount": followUsers.length,
        "followTagCount": followUserTags.length,
        "historyCount": histories.length,
        "shieldPresetCount": shieldPresetsPayload.length,
        "accountCount": (accountsPayload["items"] as List).length,
      },
    };
  }

  String exportProfileJson({
    ProfileExportOptions options = const ProfileExportOptions(),
  }) {
    return const JsonEncoder.withIndent("  ")
        .convert(exportProfileMap(options: options));
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
    final schemaName = payload["schema"]?.toString() ?? "";
    final version = (payload["schemaVersion"] as num?)?.toInt() ?? 1;
    if (schemaName == schema || schemaName == "simple_live_profile") {
      if (!_supportedSchemaVersions.contains(version)) {
        throw const FormatException("暂不支持该配置包版本");
      }
      return importProfileMap(
        payload,
        overwrite: overwrite,
        options: options,
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
    if (options.shields) {
      await _importShields(
        {"raw": _legacyShieldValues(payload["shield"])},
        summary,
        overwrite,
        onProgress,
      );
    }

    if (options.settings || options.shields || options.shieldPresets) {
      AppSettingsController.instance.reloadFromStorage();
    }
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    EventBus.instance.emit(Constant.kUpdateHistory, 0);
    return summary;
  }

  bool isSupportedProfileMap(dynamic payload) {
    if (payload is! Map) {
      return false;
    }
    final schemaName = payload["schema"]?.toString() ?? "";
    final version = (payload["schemaVersion"] as num?)?.toInt() ?? 1;
    return (schemaName == schema || schemaName == "simple_live_profile") &&
            _supportedSchemaVersions.contains(version) ||
        payload["type"] == "simple_live" ||
        _looksLikeLegacyDataFile(payload);
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
      "followUserTags",
      "tags",
      "histories",
      "history",
    };
    return keys.any((key) {
      final value = payload[key];
      return value is List || (value is Map && value["data"] is List);
    });
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
            _readPayloadList(payload, [
              "followUsers",
              "follows",
              "favorites",
            ]),
            summary,
            overwrite,
            onProgress);
        await _importFollowTags(
            _readPayloadList(payload, [
              "followUserTags",
              "tags",
            ]),
            summary,
            overwrite,
            onProgress);
      }
      if (options.histories) {
        await _importHistories(
            _readPayloadList(payload, [
              "histories",
              "history",
            ]),
            summary,
            overwrite,
            onProgress);
      }
    }

    if (options.follows) {
      await FollowService.instance.loadData(updateStatus: false);
    }
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    EventBus.instance.emit(Constant.kUpdateHistory, 0);
    return summary;
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

  Future<ProfileImportSummary> importProfileMap(
    Map<String, dynamic> payload, {
    bool overwrite = false,
    ProfileImportOptions options = const ProfileImportOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    final summary = ProfileImportSummary();
    if (options.settings) {
      onProgress?.call(const SyncProgress(stage: "导入设置"));
      await _importSettings(payload["settings"], summary, overwrite);
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
        legacySettings: payload["settings"],
      );
    }
    if (options.shieldPresets) {
      onProgress?.call(const SyncProgress(stage: "导入屏蔽预设"));
      await _importShieldPresets(
        payload["shieldPresets"],
        summary,
        overwrite,
      );
    }
    if (options.follows) {
      await _importFollowUsers(
          _readPayloadList(payload, [
            "followUsers",
            "follows",
            "favorites",
          ]),
          summary,
          overwrite,
          onProgress);
      await _importFollowTags(
          _readPayloadList(payload, [
            "followUserTags",
            "tags",
          ]),
          summary,
          overwrite,
          onProgress);
    }
    if (options.histories) {
      await _importHistories(
          _readPayloadList(payload, [
            "histories",
            "history",
          ]),
          summary,
          overwrite,
          onProgress);
    }

    if (options.settings || options.shields || options.shieldPresets) {
      AppSettingsController.instance.reloadFromStorage();
    }
    if (options.follows) {
      await FollowService.instance.loadData(updateStatus: false);
    }
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    EventBus.instance.emit(Constant.kUpdateHistory, 0);
    return summary;
  }

  Map<String, dynamic> _exportSettings() {
    final result = <String, dynamic>{};
    for (final entry
        in LocalStorageService.instance.settingsBox.toMap().entries) {
      final key = entry.key.toString();
      if (_excludedSettings.contains(key)) {
        continue;
      }
      result[key] = _safeJsonValue(entry.value);
    }
    return result;
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
          "siteId": Constant.kKuaishou,
          ...KuaishouAccountService.instance.exportBackupMap(),
        },
      ],
    };
  }

  Map<String, dynamic> _exportShieldValues() {
    final raw = LocalStorageService.instance.shieldBox.values
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort();
    final keywords = AppSettingsControllerSafe.keywordValues()..sort();
    final userGroups = AppSettingsControllerSafe.userGroups();
    final users = userGroups.values.expand((e) => e).toSet().toList()..sort();
    return {
      "raw": raw,
      "keywords": keywords,
      "users": users,
      "userGroups": userGroups,
    };
  }

  List<Map<String, dynamic>> _exportShieldPresets() {
    final result = <Map<String, dynamic>>[];
    for (final entry
        in LocalStorageService.instance.shieldPresetBox.toMap().entries) {
      dynamic value = entry.value;
      try {
        value = jsonDecode(entry.value.toString());
      } catch (_) {}
      result.add({
        "name": entry.key.toString(),
        "value": _safeJsonValue(value),
      });
    }
    result.sort((a, b) => a["name"].toString().compareTo(b["name"].toString()));
    return result;
  }

  Future<void> _importSettings(
    dynamic rawSettings,
    ProfileImportSummary summary,
    bool overwrite,
  ) async {
    if (rawSettings is! Map) {
      return;
    }
    if (overwrite) {
      await _clearImportableSettings();
    }
    final values = <dynamic, dynamic>{};
    for (final entry in rawSettings.entries) {
      final key = entry.key.toString();
      if (_excludedSettings.contains(key)) {
        continue;
      }
      values[key] = entry.value;
    }
    await LocalStorageService.instance.settingsBox.putAll(values);
    summary.settings = values.length;
  }

  Future<void> _clearImportableSettings() async {
    final keys = LocalStorageService.instance.settingsBox.keys
        .where((key) => !_excludedSettings.contains(key.toString()))
        .toList();
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
    if (overwrite) {
      await AppSettingsControllerSafe.clearShieldValues();
    }
    if (rawShield is Map) {
      final rawValues = rawShield["raw"];
      if (rawValues is List && rawValues.isNotEmpty) {
        final result = await BulkDataImportService.importShieldValues(
          rawValues,
          overwrite: false,
          onProgress: onProgress,
        );
        summary.shields += result.imported;
        summary.skipped += result.skipped;
        return;
      }
      final keywords = rawShield["keywords"];
      if (keywords is List) {
        for (final keyword in keywords) {
          AppSettingsControllerSafe.addKeyword(keyword.toString());
          summary.shields++;
        }
      }
      final groups = rawShield["userGroups"];
      if (groups is Map) {
        for (final entry in groups.entries) {
          final users = entry.value;
          if (users is! List) {
            continue;
          }
          for (final user in users) {
            AppSettingsControllerSafe.addUser(
              user.toString(),
              siteId: entry.key.toString(),
            );
            summary.shields++;
          }
        }
      }
    }
  }

  Future<void> _importShieldPresets(
    dynamic rawPresets,
    ProfileImportSummary summary,
    bool overwrite,
  ) async {
    if (overwrite) {
      await LocalStorageService.instance.shieldPresetBox.clear();
    }
    if (rawPresets is! List) {
      return;
    }
    for (final item in rawPresets) {
      if (item is! Map) {
        continue;
      }
      final name = item["name"]?.toString().trim() ?? "";
      if (name.isEmpty) {
        continue;
      }
      final value = item["value"];
      await LocalStorageService.instance.shieldPresetBox.put(
        name,
        value is String ? value : jsonEncode(value),
      );
      summary.shieldPresets++;
    }
    AppSettingsControllerSafe.reloadShields();
  }

  Future<int> _importAccounts(
    dynamic rawAccounts, {
    dynamic legacySettings,
  }) async {
    var importedCount = 0;
    final items = rawAccounts is Map && rawAccounts["items"] is List
        ? rawAccounts["items"] as List
        : const [];
    var importedKuaishou = false;
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final siteId = item["siteId"]?.toString() ?? "";
      final cookie = item["cookie"]?.toString() ?? "";
      switch (siteId) {
        case Constant.kBiliBili:
          BiliBiliAccountService.instance.setCookie(cookie);
          importedCount++;
          break;
        case Constant.kDouyin:
          if (cookie.isEmpty) {
            DouyinAccountService.instance.clearCookie();
          } else {
            DouyinAccountService.instance.setCookie(cookie);
          }
          importedCount++;
          break;
        case Constant.kKuaishou:
          importedKuaishou = true;
          KuaishouAccountService.instance.importBackupMap(
            item,
            legacySettings: legacySettings,
          );
          importedCount++;
          break;
      }
    }
    if (!importedKuaishou && legacySettings is Map) {
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
        KuaishouAccountService.instance.importBackupMap(
          {
            'cookie': legacySettings[LocalStorageService.kKuaishouCookie],
            'kww': legacySettings[LocalStorageService.kKuaishouKww],
            'cookieExpiresAt':
                legacySettings[LocalStorageService.kKuaishouCookieExpiresAt],
          },
          legacySettings: legacySettings,
        );
        importedCount++;
      }
    }
    return importedCount;
  }

  Future<void> _importFollowUsers(
    dynamic rawUsers,
    ProfileImportSummary summary,
    bool overwrite,
    SyncProgressCallback? onProgress,
  ) async {
    final result = await BulkDataImportService.importFollowUsers(
      rawUsers,
      overwrite: overwrite,
      onProgress: onProgress,
    );
    summary.followUsers += result.imported;
    summary.skipped += result.skipped;
  }

  Future<void> _importFollowTags(
    dynamic rawTags,
    ProfileImportSummary summary,
    bool overwrite,
    SyncProgressCallback? onProgress,
  ) async {
    final result = await BulkDataImportService.importFollowTags(
      rawTags,
      overwrite: overwrite,
      onProgress: onProgress,
    );
    summary.followTags += result.imported;
    summary.skipped += result.skipped;
  }

  Future<void> _importHistories(
    dynamic rawHistories,
    ProfileImportSummary summary,
    bool overwrite,
    SyncProgressCallback? onProgress,
  ) async {
    final result = await BulkDataImportService.importHistories(
      rawHistories,
      overwrite: overwrite,
      onProgress: onProgress,
    );
    summary.histories += result.imported;
    summary.skipped += result.skipped;
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
    final firstMap = rawList.whereType<Map>().firstOrNull;
    if (firstMap != null) {
      if (firstMap.containsKey("userId") || firstMap.containsKey("tag")) {
        if (options.follows) {
          await _importFollowTags(rawList, summary, overwrite, onProgress);
        }
        return;
      }
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

class ProfileExportOptions {
  final bool settings;
  final bool accounts;
  final bool shields;
  final bool shieldPresets;
  final bool follows;
  final bool histories;

  const ProfileExportOptions({
    this.settings = true,
    this.accounts = true,
    this.shields = true,
    this.shieldPresets = true,
    this.follows = true,
    this.histories = true,
  });

  bool get hasSelection =>
      settings || accounts || shields || shieldPresets || follows || histories;

  Map<String, bool> toJson() {
    return {
      "settings": settings,
      "accounts": accounts,
      "shields": shields,
      "shieldPresets": shieldPresets,
      "follows": follows,
      "histories": histories,
    };
  }
}

class ProfileImportOptions {
  final bool settings;
  final bool accounts;
  final bool shields;
  final bool shieldPresets;
  final bool follows;
  final bool histories;

  const ProfileImportOptions({
    this.settings = true,
    this.accounts = true,
    this.shields = true,
    this.shieldPresets = true,
    this.follows = true,
    this.histories = true,
  });

  bool get hasSelection =>
      settings || accounts || shields || shieldPresets || follows || histories;
}

class ProfileImportSummary {
  int settings = 0;
  int accounts = 0;
  int shields = 0;
  int shieldPresets = 0;
  int followUsers = 0;
  int followTags = 0;
  int histories = 0;
  int skipped = 0;

  String get message {
    final base =
        "设置 $settings 项，账号 $accounts 个，屏蔽 $shields 项，预设 $shieldPresets 个，关注 $followUsers 个，标签 $followTags 个，历史 $histories 条";
    return skipped > 0 ? "$base，跳过异常 $skipped 条" : base;
  }
}

class AppSettingsControllerSafe {
  static List<String> keywordValues() {
    return AppSettingsController.instance.shieldList.toList();
  }

  static Map<String, List<String>> userGroups() {
    return AppSettingsController.instance.getUserShieldGroupSnapshot();
  }

  static void importShieldValue(String value) {
    AppSettingsController.instance.importShieldValue(value);
  }

  static void addKeyword(String value) {
    AppSettingsController.instance.addShieldList(value);
  }

  static void addUser(String value, {String? siteId}) {
    AppSettingsController.instance.addUserShieldList(value, siteId: siteId);
  }

  static Future<void> clearShieldValues() {
    return AppSettingsController.instance.clearShieldList();
  }

  static void reloadShields() {
    AppSettingsController.instance.refreshShieldData();
  }
}
