import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';

void main() {
  final service = ProfileBackupService();

  ProfileInspection inspect(Map<String, dynamic> payload) {
    return service.inspectProfileJson(jsonEncode(payload));
  }

  group('配置包识别', () {
    test('只报告包内真实存在的分类，空分类不出现', () {
      final inspection = inspect({
        "schema": ProfileBackupService.schema,
        "schemaVersion": ProfileBackupService.schemaVersion,
        "appVersion": "1.2.3",
        "settings": {"playerVolume": 50, "autoExitFullScreen": true},
        "followUsers": [
          {"id": "a", "roomId": "1", "siteId": "bilibili"},
          {"id": "b", "roomId": "2", "siteId": "douyin"},
        ],
        "followUserTags": [
          {"id": "t1", "tag": "常看"},
        ],
        // 历史为空数组：不应作为可导入分类出现。
        "histories": <dynamic>[],
      });

      expect(inspection.kind, ProfilePackageKind.profile);
      expect(inspection.appVersion, "1.2.3");
      expect(
        inspection.availableCategories,
        [ProfileCategory.settings, ProfileCategory.follows],
      );
      expect(inspection.categories[ProfileCategory.histories], isNull);
      expect(
        inspection.categories[ProfileCategory.follows]!.detail,
        "2 个关注，1 个标签",
      );
      expect(inspection.categories[ProfileCategory.settings]!.count, 2);
    });

    test('分类顺序固定按枚举声明顺序，与包内键顺序无关', () {
      final inspection = inspect({
        "schema": ProfileBackupService.schema,
        "schemaVersion": ProfileBackupService.schemaVersion,
        "histories": [
          {"roomId": "1", "updateTime": 1},
        ],
        "shieldPresets": [
          {"name": "p1", "value": "{}"},
        ],
        "settings": {"a": 1},
      });

      expect(inspection.availableCategories, [
        ProfileCategory.settings,
        ProfileCategory.histories,
        ProfileCategory.shieldPresets,
      ]);
    });

    test('屏蔽规则区分 raw 与关键词/用户分组', () {
      final rawInspection = inspect({
        "schema": ProfileBackupService.schema,
        "schemaVersion": ProfileBackupService.schemaVersion,
        "danmuShield": {
          "raw": ["a", "b", "c"],
        },
      });
      expect(
        rawInspection.categories[ProfileCategory.shields]!.detail,
        "3 项",
      );

      final structured = inspect({
        "schema": ProfileBackupService.schema,
        "schemaVersion": ProfileBackupService.schemaVersion,
        "danmuShield": {
          "raw": <dynamic>[],
          "keywords": ["广告"],
          "userGroups": {
            "bilibili": ["u1", "u2"],
          },
        },
      });
      expect(
        structured.categories[ProfileCategory.shields]!.detail,
        "1 个关键词，2 个用户",
      );

      final empty = inspect({
        "schema": ProfileBackupService.schema,
        "schemaVersion": ProfileBackupService.schemaVersion,
        "danmuShield": {
          "raw": <dynamic>[],
          "keywords": <dynamic>[],
          "userGroups": <String, dynamic>{},
        },
      });
      expect(empty.categories[ProfileCategory.shields], isNull);
    });

    test('账号分类只统计真正带 Cookie 的平台', () {
      final noCookies = inspect({
        "schema": ProfileBackupService.schema,
        "schemaVersion": ProfileBackupService.schemaVersion,
        "accounts": {
          "items": [
            {"siteId": "bilibili", "cookie": ""},
            {"siteId": "douyin", "cookie": "   "},
            {
              "siteId": "kuaishou",
              "slots": {
                "primary": {"cookie": ""},
                "secondary": {"cookie": ""},
              },
            },
          ],
        },
      });
      expect(noCookies.categories[ProfileCategory.accounts], isNull);
      expect(noCookies.isEmpty, isTrue);

      final withCookies = inspect({
        "schema": ProfileBackupService.schema,
        "schemaVersion": ProfileBackupService.schemaVersion,
        "accounts": {
          "items": [
            {"siteId": "bilibili", "cookie": "SESSDATA=x"},
            {"siteId": "douyin", "cookie": ""},
            {
              "siteId": "kuaishou",
              "slots": {
                "primary": {"cookie": "did=y"},
                "secondary": {"cookie": ""},
              },
            },
          ],
        },
      });
      expect(
        withCookies.categories[ProfileCategory.accounts]!.detail,
        "2 个平台",
      );
    });

    test('识别上游关注页导出的顶层数组', () {
      // 与上游 FollowService.generateJson() 的输出逐字段对齐。
      final upstream = [
        {
          "siteId": "bilibili",
          "id": "bilibili_123",
          "roomId": "123",
          "userName": "主播A",
          "face": "https://example.com/a.png",
          "addTime": "2026-01-01 00:00:00.000",
          "tag": "全部",
          "isSpecialFollow": false,
        },
        {
          "siteId": "douyu",
          "id": "douyu_456",
          "roomId": "456",
          "userName": "主播B",
          "face": "https://example.com/b.png",
          "addTime": "2026-01-02 00:00:00.000",
          "tag": "常看",
          "isSpecialFollow": true,
        },
      ];

      final inspection = service.inspectProfileJson(jsonEncode(upstream));

      expect(inspection.kind, ProfilePackageKind.legacyDataFile);
      // 关注项同时带 roomId/siteId 和 tag，必须判为关注而不是标签。
      expect(inspection.availableCategories, [ProfileCategory.follows]);
      expect(
        inspection.categories[ProfileCategory.follows]!.detail,
        "2 个关注",
      );
    });

    test('顶层数组的历史与屏蔽词仍各归其类', () {
      final histories = service.inspectProfileJson(jsonEncode([
        {"id": "bilibili_1", "roomId": "1", "siteId": "bilibili", "updateTime": 1},
      ]));
      expect(
        histories.categories[ProfileCategory.histories]!.detail,
        "1 条",
      );

      final tags = service.inspectProfileJson(jsonEncode([
        {"id": "t1", "tag": "常看", "userId": ["bilibili_1"]},
      ]));
      expect(
        tags.categories[ProfileCategory.follows]!.detail,
        "1 个标签",
      );

      final shields = service.inspectProfileJson(jsonEncode(["广告", "刷屏"]));
      expect(
        shields.categories[ProfileCategory.shields]!.detail,
        "2 项",
      );
    });

    test('空顶层数组不产生可导入分类', () {
      final inspection = service.inspectProfileJson('[]');
      expect(inspection.isEmpty, isTrue);
    });

    test('识别旧版配置包与旧版数据文件', () {
      final legacyProfile = inspect({
        "type": "simple_live",
        "config": {"a": 1, "b": 2},
        "shield": {"0": "x", "1": "y"},
      });
      expect(legacyProfile.kind, ProfilePackageKind.legacyProfile);
      expect(legacyProfile.availableCategories, [
        ProfileCategory.settings,
        ProfileCategory.shields,
      ]);

      final legacyFollowList = inspect({
        "data": [
          {"roomId": "1", "siteId": "bilibili"},
        ],
      });
      expect(legacyFollowList.kind, ProfilePackageKind.legacyDataFile);
      expect(
        legacyFollowList.categories[ProfileCategory.follows]!.detail,
        "1 个关注",
      );

      final legacyHistoryList = inspect({
        "data": [
          {"roomId": "1", "updateTime": 123},
        ],
      });
      expect(
        legacyHistoryList.categories[ProfileCategory.histories]!.detail,
        "1 条",
      );
    });

    test('不是配置包或版本过新时抛出可读异常', () {
      // 顶层数组是上游关注导出的合法形态，不再直接判为非法；
      // 空数组由 isEmpty 分支给出「没有可导入内容」的提示。
      expect(service.inspectProfileJson('[]').isEmpty, isTrue);
      expect(
        () => service.inspectProfileJson('"just a string"'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => inspect({"foo": "bar"}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => inspect({
          "schema": ProfileBackupService.schema,
          "schemaVersion": 999,
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            "暂不支持该配置包版本",
          ),
        ),
      );
    });
  });

  group('导入选项', () {
    test('只打开勾选的分类', () {
      final options = ProfileImportOptions.fromCategories({
        ProfileCategory.follows,
        ProfileCategory.histories,
      });

      expect(options.follows, isTrue);
      expect(options.histories, isTrue);
      expect(options.settings, isFalse);
      expect(options.accounts, isFalse);
      expect(options.shields, isFalse);
      expect(options.shieldPresets, isFalse);
      expect(options.hasSelection, isTrue);
    });

    test('空勾选不构成有效选择', () {
      expect(
        ProfileImportOptions.fromCategories(const {}).hasSelection,
        isFalse,
      );
    });
  });
}
