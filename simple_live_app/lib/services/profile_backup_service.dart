import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
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

  /// 无论源平台是什么都不该跨设备恢复的设置。
  ///
  /// 与 [_excludedSettings] 的区别：那张表挡的是身份与凭证，这张表挡的是
  /// "在别的机器上不可能成立"的值。导出和导入两侧都跳过。
  static const Set<String> _deviceLocalSettings = {
    // 本机绝对路径，换机后必然指向不存在的文件；parseConfFile 读不到会静默
    // 返回空 map，用户看到设置里挂着一个路径却毫无效果。
    LocalStorageService.kImportedMpvConfPath,
  };

  /// 只在源平台与当前平台相同时才恢复的设置。
  ///
  /// 这些键的值是platform-specific 的播放器调优：`ao=audiotrack` 这类安卓专属
  /// 输出驱动落到 Windows 上会让 libmpv 音频初始化直接失败、全程无声。但同平台
  /// 之间（安卓→安卓）迁移调优是正常需求，所以按源平台判断而不是一律排除。
  static const Set<String> _platformSpecificSettings = {
    LocalStorageService.kMpvAdvancedOptions,
    LocalStorageService.kCustomPlayerOutput,
    LocalStorageService.kAudioOutputDriver,
    LocalStorageService.kVideoOutputDriver,
    LocalStorageService.kVideoHardwareDecoder,
    LocalStorageService.kPlayerCompatMode,
  };

  Map<String, dynamic> exportProfileMap({
    ProfileExportOptions options = const ProfileExportOptions(),
  }) {
    if (options.upstreamMode == UpstreamExportMode.dataAndSync) {
      return _exportUpstreamProfileMap(options);
    }
    if (options.upstreamMode == UpstreamExportMode.followList) {
      throw StateError("上游关注列表格式是顶层数组，不能作为 Map 导出");
    }
    final shieldPayload = options.shields
        ? _exportShieldValues()
        : {
            "raw": const [],
            "keywords": const [],
            "users": const [],
            "userGroups": const <String, List<String>>{},
          };
    final settingsPayload = options.settings
        ? _exportSettings()
        : <String, dynamic>{};
    final accountsPayload = options.accounts
        ? _exportAccounts()
        : {"items": const []};
    final shieldPresetsPayload = options.shieldPresets
        ? _exportShieldPresets()
        : const [];
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
        ? DBService.instance.getHistores().map((item) => item.toJson()).toList()
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
        "rawShieldCount": (shieldPayload["raw"] as List).length,
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

  /// 返回配置包的实际 JSON 根对象。上游关注列表格式是顶层数组，
  /// 因此不能复用只返回 Map 的 [exportProfileMap]。
  Object exportProfilePayload({
    ProfileExportOptions options = const ProfileExportOptions(),
  }) {
    if (options.upstreamMode == UpstreamExportMode.followList) {
      return _exportUpstreamFollowList();
    }
    return exportProfileMap(options: options);
  }

  List<Map<String, dynamic>> _exportUpstreamFollowList() {
    return DBService.instance.getFollowList().map((item) {
      // 保持与上游关注页导出字段一致，避免新字段导致老版本解析差异。
      return <String, dynamic>{
        "siteId": item.siteId,
        "id": item.id,
        "roomId": item.roomId,
        "userName": item.userName,
        "face": item.face,
        "addTime": item.addTime.toString(),
        "tag": item.tag,
        "isSpecialFollow": item.isSpecialFollow,
      };
    }).toList();
  }

  /// 上游「我的 - 数据与同步」的旧配置包格式。
  ///
  /// 该格式只支持设置和关键词屏蔽词；关注列表由上游关注页单独导出为顶层数组，
  /// 导入时由 [inspectProfileJson] 自动识别。
  Map<String, dynamic> _exportUpstreamProfileMap(ProfileExportOptions options) {
    final settings = options.settings ? _exportSettings() : <String, dynamic>{};
    final shieldValues = options.shields
        ? (AppSettingsControllerSafe.keywordValues()..sort())
        : <String>[];
    return {
      "type": "simple_live",
      "platform": Platform.operatingSystem,
      "version": 1,
      "time": DateTime.now().millisecondsSinceEpoch,
      "config": settings,
      "shield": {for (final value in shieldValues) value: value},
    };
  }

  String exportProfileJson({
    ProfileExportOptions options = const ProfileExportOptions(),
  }) {
    return const JsonEncoder.withIndent(
      "  ",
    ).convert(exportProfilePayload(options: options));
  }

  Future<TemporaryProfilePackage> createTemporaryProfilePackage({
    ProfileExportOptions options = const ProfileExportOptions(),
  }) async {
    final payload = exportProfilePayload(options: options);
    final content = const JsonEncoder.withIndent("  ").convert(payload);
    final dir = await Directory.systemTemp.createTemp("simple_live_profile_");
    final file = File("${dir.path}${Platform.pathSeparator}profile.json");
    await file.writeAsString(content);
    return TemporaryProfilePackage(
      file: file,
      directory: dir,
      summary: _exportSummary(payload),
      options: options,
      byteLength: utf8.encode(content).length,
    );
  }

  Map<String, dynamic> _exportSummary(Object payload) {
    if (payload is List) {
      return {
        "settingCount": 0,
        "rawShieldCount": 0,
        "keywordShieldCount": 0,
        "userShieldCount": 0,
        "followUserCount": payload.length,
        "followTagCount": 0,
        "historyCount": 0,
        "shieldPresetCount": 0,
        "accountCount": 0,
      };
    }
    if (payload is! Map) {
      return const {};
    }
    final summary = payload["summary"];
    if (summary is Map) {
      return Map<String, dynamic>.from(summary);
    }
    final settings = payload["config"];
    final shields = _legacyShieldValues(payload["shield"]);
    return {
      "settingCount": settings is Map ? settings.length : 0,
      "rawShieldCount": shields.length,
      "keywordShieldCount": shields.length,
      "userShieldCount": 0,
      "followUserCount": 0,
      "followTagCount": 0,
      "historyCount": 0,
      "shieldPresetCount": 0,
      "accountCount": 0,
    };
  }

  Future<ProfileImportSummary> importProfileJson(
    String content, {
    bool overwrite = false,
    ProfileImportOptions options = const ProfileImportOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    onProgress?.call(const SyncProgress(stage: "解析配置包"));
    return importInspectedProfile(
      inspectProfileJson(content),
      overwrite: overwrite,
      options: options,
      onProgress: onProgress,
    );
  }

  /// 解析配置包并识别包内实际包含的分类，供导入前按包内容勾选。
  /// 解析失败会抛 [FormatException]，与 [importProfileJson] 的提示一致。
  ProfileInspection inspectProfileJson(String content) {
    final decoded = jsonDecode(content);
    // 上游「导出关注列表」写出的是顶层数组，没有任何包裹对象，
    // 统一包成 {"data": [...]} 后走旧版数据文件那条分支。
    if (decoded is List) {
      return ProfileInspection(
        kind: ProfilePackageKind.legacyDataFile,
        payload: {"data": decoded},
        categories: _inspectLegacyDataFileCategories({"data": decoded}),
      );
    }
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
      return ProfileInspection(
        kind: ProfilePackageKind.profile,
        payload: payload,
        schemaVersion: version,
        appVersion: payload["appVersion"]?.toString(),
        exportedAt: payload["exportedAt"]?.toString(),
        categories: _inspectProfileCategories(payload),
      );
    }
    if (payload["type"] == "simple_live") {
      return ProfileInspection(
        kind: ProfilePackageKind.legacyProfile,
        payload: payload,
        categories: _inspectLegacyProfileCategories(payload),
      );
    }
    if (_looksLikeLegacyDataFile(payload)) {
      return ProfileInspection(
        kind: ProfilePackageKind.legacyDataFile,
        payload: payload,
        categories: _inspectLegacyDataFileCategories(payload),
      );
    }
    throw const FormatException("不是 Simple Live 配置包");
  }

  /// 按已解析的配置包导入，避免二次解析 JSON。
  Future<ProfileImportSummary> importInspectedProfile(
    ProfileInspection inspection, {
    bool overwrite = false,
    ProfileImportOptions options = const ProfileImportOptions(),
    SyncProgressCallback? onProgress,
  }) {
    switch (inspection.kind) {
      case ProfilePackageKind.profile:
        return importProfileMap(
          inspection.payload,
          overwrite: overwrite,
          options: options,
          onProgress: onProgress,
        );
      case ProfilePackageKind.legacyProfile:
        return importLegacyProfileMap(
          inspection.payload,
          overwrite: overwrite,
          options: options,
          onProgress: onProgress,
        );
      case ProfilePackageKind.legacyDataFile:
        return importLegacyDataFileMap(
          inspection.payload,
          overwrite: overwrite,
          options: options,
          onProgress: onProgress,
        );
    }
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
      await _importSettings(
        payload["config"],
        summary,
        overwrite,
        sourcePlatform: payload["platform"],
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

  Map<ProfileCategory, ProfileCategoryInfo> _inspectProfileCategories(
    Map<String, dynamic> payload,
  ) {
    final result = <ProfileCategory, ProfileCategoryInfo>{};
    final settings = payload["settings"];
    if (settings is Map && settings.isNotEmpty) {
      final count = settings.keys
          .where((key) => !_excludedSettings.contains(key.toString()))
          .length;
      if (count > 0) {
        result[ProfileCategory.settings] = ProfileCategoryInfo(
          count: count,
          detail: "$count 项",
        );
      }
    }

    final accountCount = _countAccounts(payload["accounts"]);
    if (accountCount > 0) {
      result[ProfileCategory.accounts] = ProfileCategoryInfo(
        count: accountCount,
        detail: "$accountCount 个平台",
      );
    }

    final shieldInfo = _inspectShieldPayload(payload["danmuShield"]);
    if (shieldInfo != null) {
      result[ProfileCategory.shields] = shieldInfo;
    }

    final presets = payload["shieldPresets"];
    if (presets is List && presets.isNotEmpty) {
      result[ProfileCategory.shieldPresets] = ProfileCategoryInfo(
        count: presets.length,
        detail: "${presets.length} 个",
      );
    }

    final followInfo = _inspectFollowPayload(payload);
    if (followInfo != null) {
      result[ProfileCategory.follows] = followInfo;
    }

    final histories = _readPayloadList(payload, ["histories", "history"]);
    if (histories is List && histories.isNotEmpty) {
      result[ProfileCategory.histories] = ProfileCategoryInfo(
        count: histories.length,
        detail: "${histories.length} 条",
      );
    }
    return result;
  }

  Map<ProfileCategory, ProfileCategoryInfo> _inspectLegacyProfileCategories(
    Map<String, dynamic> payload,
  ) {
    final result = <ProfileCategory, ProfileCategoryInfo>{};
    final config = payload["config"];
    if (config is Map) {
      final count = config.keys
          .where((key) => !_excludedSettings.contains(key.toString()))
          .length;
      if (count > 0) {
        result[ProfileCategory.settings] = ProfileCategoryInfo(
          count: count,
          detail: "$count 项",
        );
      }
    }
    final shields = _legacyShieldValues(payload["shield"]);
    if (shields.isNotEmpty) {
      result[ProfileCategory.shields] = ProfileCategoryInfo(
        count: shields.length,
        detail: "${shields.length} 项",
      );
    }
    return result;
  }

  Map<ProfileCategory, ProfileCategoryInfo> _inspectLegacyDataFileCategories(
    Map<String, dynamic> payload,
  ) {
    final result = <ProfileCategory, ProfileCategoryInfo>{};
    final rawList = payload["data"];
    if (rawList is List) {
      // 老版本单一数组文件：按首个元素的字段猜测类型，与导入逻辑保持一致。
      if (rawList.isEmpty) {
        return result;
      }
      final firstMap = rawList.whereType<Map>().firstOrNull;
      if (firstMap != null) {
        // 顺序必须与 _importLegacyDataList 一致，且按「独有字段」判别：
        // updateTime 只有历史有，userId 数组只有标签有，
        // roomId/siteId 是历史和关注共有的，只能放最后兜底。
        if (firstMap.containsKey("updateTime")) {
          result[ProfileCategory.histories] = ProfileCategoryInfo(
            count: rawList.length,
            detail: "${rawList.length} 条",
          );
        } else if (firstMap["userId"] is List) {
          result[ProfileCategory.follows] = ProfileCategoryInfo(
            count: rawList.length,
            detail: "${rawList.length} 个标签",
          );
        } else if (firstMap.containsKey("roomId") ||
            firstMap.containsKey("siteId")) {
          result[ProfileCategory.follows] = ProfileCategoryInfo(
            count: rawList.length,
            detail: "${rawList.length} 个关注",
          );
        }
        return result;
      }
      if (rawList.every((item) => item is String)) {
        result[ProfileCategory.shields] = ProfileCategoryInfo(
          count: rawList.length,
          detail: "${rawList.length} 项",
        );
      }
      return result;
    }

    final followInfo = _inspectFollowPayload(payload);
    if (followInfo != null) {
      result[ProfileCategory.follows] = followInfo;
    }
    final histories = _readPayloadList(payload, ["histories", "history"]);
    if (histories is List && histories.isNotEmpty) {
      result[ProfileCategory.histories] = ProfileCategoryInfo(
        count: histories.length,
        detail: "${histories.length} 条",
      );
    }
    return result;
  }

  ProfileCategoryInfo? _inspectFollowPayload(Map<String, dynamic> payload) {
    final users = _readPayloadList(payload, [
      "followUsers",
      "follows",
      "favorites",
    ]);
    final tags = _readPayloadList(payload, ["followUserTags", "tags"]);
    final userCount = users is List ? users.length : 0;
    final tagCount = tags is List ? tags.length : 0;
    if (userCount == 0 && tagCount == 0) {
      return null;
    }
    final parts = [
      if (userCount > 0) "$userCount 个关注",
      if (tagCount > 0) "$tagCount 个标签",
    ];
    return ProfileCategoryInfo(
      count: userCount + tagCount,
      detail: parts.join("，"),
    );
  }

  ProfileCategoryInfo? _inspectShieldPayload(dynamic rawShield) {
    if (rawShield is! Map) {
      return null;
    }
    final raw = rawShield["raw"];
    if (raw is List && raw.isNotEmpty) {
      return ProfileCategoryInfo(count: raw.length, detail: "${raw.length} 项");
    }
    final keywords = rawShield["keywords"];
    final keywordCount = keywords is List ? keywords.length : 0;
    var userCount = 0;
    final groups = rawShield["userGroups"];
    if (groups is Map) {
      for (final value in groups.values) {
        if (value is List) {
          userCount += value.length;
        }
      }
    }
    if (keywordCount == 0 && userCount == 0) {
      return null;
    }
    final parts = [
      if (keywordCount > 0) "$keywordCount 个关键词",
      if (userCount > 0) "$userCount 个用户",
    ];
    return ProfileCategoryInfo(
      count: keywordCount + userCount,
      detail: parts.join("，"),
    );
  }

  /// 只统计真正带登录态的平台，空 Cookie 的占位项不算。
  int _countAccounts(dynamic rawAccounts) {
    if (rawAccounts is! Map || rawAccounts["items"] is! List) {
      return 0;
    }
    var count = 0;
    for (final item in rawAccounts["items"] as List) {
      if (item is! Map) {
        continue;
      }
      final cookie = item["cookie"]?.toString().trim() ?? "";
      if (cookie.isNotEmpty) {
        count++;
        continue;
      }
      // 快手把 Cookie 放在 slots 里，需要单独看槽位。
      final slots = item["slots"];
      if (slots is Map &&
          slots.values.any(
            (slot) =>
                slot is Map &&
                (slot["cookie"]?.toString().trim() ?? "").isNotEmpty,
          )) {
        count++;
      }
    }
    return count;
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
        final rawTags = _readPayloadList(payload, ["followUserTags", "tags"]);
        await _importFollowUsers(
          _readPayloadList(payload, ["followUsers", "follows", "favorites"]),
          summary,
          overwrite,
          onProgress,
          // 没带独立标签列表时，按关注项内的 tag 字段重建分组。
          syncTagsFromUserField: rawTags is! List || rawTags.isEmpty,
        );
        await _importFollowTags(rawTags, summary, overwrite, onProgress);
      }
      if (options.histories) {
        await _importHistories(
          _readPayloadList(payload, ["histories", "history"]),
          summary,
          overwrite,
          onProgress,
        );
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
        legacySettings: payload["settings"],
      );
    }
    if (options.shieldPresets) {
      onProgress?.call(const SyncProgress(stage: "导入屏蔽预设"));
      await _importShieldPresets(payload["shieldPresets"], summary, overwrite);
    }
    if (options.follows) {
      await _importFollowUsers(
        _readPayloadList(payload, ["followUsers", "follows", "favorites"]),
        summary,
        overwrite,
        onProgress,
      );
      await _importFollowTags(
        _readPayloadList(payload, ["followUserTags", "tags"]),
        summary,
        overwrite,
        onProgress,
      );
    }
    if (options.histories) {
      await _importHistories(
        _readPayloadList(payload, ["histories", "history"]),
        summary,
        overwrite,
        onProgress,
      );
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
      if (_excludedSettings.contains(key) ||
          _deviceLocalSettings.contains(key)) {
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
    final raw =
        LocalStorageService.instance.shieldBox.values
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

  /// 判断配置包是否来自当前平台。
  ///
  /// 老包（schema 1-4 之前的导出）可能没有 `platform` 字段，一律按"来源未知"
  /// 处理：保守起见视为跨平台，宁可丢掉调优也不要写进一个会导致无声的 ao。
  static bool isSamePlatformPackage(dynamic rawPlatform) {
    if (rawPlatform is! String || rawPlatform.trim().isEmpty) {
      return false;
    }
    return rawPlatform.trim().toLowerCase() ==
        Platform.operatingSystem.toLowerCase();
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
    if (overwrite) {
      await _clearImportableSettings();
    }
    final samePlatform = isSamePlatformPackage(sourcePlatform);
    final values = <dynamic, dynamic>{};
    final droppedPlatformKeys = <String>[];
    for (final entry in rawSettings.entries) {
      final key = entry.key.toString();
      if (_excludedSettings.contains(key) ||
          _deviceLocalSettings.contains(key)) {
        continue;
      }
      if (!samePlatform && _platformSpecificSettings.contains(key)) {
        droppedPlatformKeys.add(key);
        continue;
      }
      values[key] = entry.value;
    }
    await LocalStorageService.instance.settingsBox.putAll(values);
    summary.settings = values.length;
    summary.droppedPlatformSettings = droppedPlatformKeys.length;
    if (droppedPlatformKeys.isNotEmpty) {
      Log.d(
        "配置导入：跳过 ${droppedPlatformKeys.length} 项平台专属设置"
        "（来源=${sourcePlatform ?? '未知'} 当前=${Platform.operatingSystem}）"
        "：${droppedPlatformKeys.join(', ')}",
      );
    }
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
        KuaishouAccountService.instance.importBackupMap({
          'cookie': legacySettings[LocalStorageService.kKuaishouCookie],
          'kww': legacySettings[LocalStorageService.kKuaishouKww],
          'cookieExpiresAt':
              legacySettings[LocalStorageService.kKuaishouCookieExpiresAt],
        }, legacySettings: legacySettings);
        importedCount++;
      }
    }
    return importedCount;
  }

  Future<void> _importFollowUsers(
    dynamic rawUsers,
    ProfileImportSummary summary,
    bool overwrite,
    SyncProgressCallback? onProgress, {
    bool syncTagsFromUserField = false,
  }) async {
    final result = await BulkDataImportService.importFollowUsers(
      rawUsers,
      overwrite: overwrite,
      syncTagsFromUserField: syncTagsFromUserField,
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
      // 按「独有字段」判别，顺序不能随意调整：
      // updateTime 只有历史有；userId 数组只有标签有；
      // roomId/siteId 是历史和关注共有的，只能放最后兜底。
      // 旧实现先判 tag，导致上游关注列表（每项都带 tag 字符串）
      // 被整份误认成标签，写进标签表且关注一个都不进。
      if (firstMap.containsKey("updateTime")) {
        if (options.histories) {
          await _importHistories(rawList, summary, overwrite, onProgress);
        }
        return;
      }
      if (firstMap["userId"] is List) {
        if (options.follows) {
          await _importFollowTags(rawList, summary, overwrite, onProgress);
        }
        return;
      }
      if (firstMap.containsKey("roomId") || firstMap.containsKey("siteId")) {
        if (options.follows) {
          await _importFollowUsers(
            rawList,
            summary,
            overwrite,
            onProgress,
            // 上游把标签放在每个关注项的 tag 字段里，没有独立标签列表，
            // 需要据此重建标签，否则分组信息全丢。
            syncTagsFromUserField: true,
          );
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

enum UpstreamExportMode { none, dataAndSync, followList }

class ProfileExportOptions {
  final bool settings;
  final bool accounts;
  final bool shields;
  final bool shieldPresets;
  final bool follows;
  final bool histories;
  final UpstreamExportMode upstreamMode;

  const ProfileExportOptions({
    this.settings = true,
    this.accounts = true,
    this.shields = true,
    this.shieldPresets = true,
    this.follows = true,
    this.histories = true,
    this.upstreamMode = UpstreamExportMode.none,
  });

  bool get hasSelection =>
      upstreamMode == UpstreamExportMode.followList ||
      settings ||
      accounts ||
      shields ||
      shieldPresets ||
      follows ||
      histories;

  Map<String, dynamic> toJson() {
    return {
      "settings": settings,
      "accounts": accounts,
      "shields": shields,
      "shieldPresets": shieldPresets,
      "follows": follows,
      "histories": histories,
      "upstreamMode": upstreamMode.name,
    };
  }
}

class TemporaryProfilePackage {
  final File file;
  final Directory directory;
  final Map<String, dynamic> summary;
  final ProfileExportOptions options;
  final int byteLength;

  const TemporaryProfilePackage({
    required this.file,
    required this.directory,
    required this.summary,
    required this.options,
    required this.byteLength,
  });

  Future<String> readAsString() {
    return file.readAsString();
  }

  Future<void> delete() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
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

  /// 只导入勾选的分类，其余一律关闭。
  factory ProfileImportOptions.fromCategories(Set<ProfileCategory> selected) {
    return ProfileImportOptions(
      settings: selected.contains(ProfileCategory.settings),
      accounts: selected.contains(ProfileCategory.accounts),
      shields: selected.contains(ProfileCategory.shields),
      shieldPresets: selected.contains(ProfileCategory.shieldPresets),
      follows: selected.contains(ProfileCategory.follows),
      histories: selected.contains(ProfileCategory.histories),
    );
  }

  bool get hasSelection =>
      settings || accounts || shields || shieldPresets || follows || histories;
}

/// 配置包分类，顺序即导入界面的展示顺序。
enum ProfileCategory {
  settings("设置", "播放、显示、刷新等偏好设置"),
  follows("关注列表与标签", "关注主播、标签和特别关注标记"),
  histories("观看历史", "直播间观看记录"),
  shields("弹幕屏蔽规则", "关键词和用户屏蔽规则"),
  shieldPresets("屏蔽预设", "已保存的屏蔽规则预设"),
  accounts("账号登录信息", "平台 Cookie，默认不勾选");

  const ProfileCategory(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class ProfileCategoryInfo {
  /// 条目数量，仅用于提示，不参与导入逻辑。
  final int count;

  /// 面向界面的数量描述，如「12 个关注，3 个标签」。
  final String detail;

  const ProfileCategoryInfo({required this.count, required this.detail});
}

enum ProfilePackageKind { profile, legacyProfile, legacyDataFile }

/// 一次配置包解析的结果：包类型、原始内容和包内实际存在的分类。
class ProfileInspection {
  final ProfilePackageKind kind;
  final Map<String, dynamic> payload;
  final int? schemaVersion;
  final String? appVersion;
  final String? exportedAt;
  final Map<ProfileCategory, ProfileCategoryInfo> categories;

  const ProfileInspection({
    required this.kind,
    required this.payload,
    required this.categories,
    this.schemaVersion,
    this.appVersion,
    this.exportedAt,
  });

  bool get isEmpty => categories.isEmpty;

  /// 按枚举声明顺序返回包内可导入的分类。
  List<ProfileCategory> get availableCategories => ProfileCategory.values
      .where((category) => categories.containsKey(category))
      .toList();
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

  /// 因源平台与当前平台不同而跳过的播放器调优项数量。
  int droppedPlatformSettings = 0;

  String get message {
    final base =
        "设置 $settings 项，账号 $accounts 个，屏蔽 $shields 项，预设 $shieldPresets 个，关注 $followUsers 个，标签 $followTags 个，历史 $histories 条";
    final parts = [
      base,
      if (skipped > 0) "跳过异常 $skipped 条",
      if (droppedPlatformSettings > 0)
        "跳过其他平台的播放器设置 $droppedPlatformSettings 项",
    ];
    return parts.join("，");
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
