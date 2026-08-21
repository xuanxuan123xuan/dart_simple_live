import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/bulk_data_import_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';

/// 上游 FollowService.generateJson() 的输出格式：顶层数组，
/// 标签内嵌在每项的 tag 字段里，没有独立标签列表。
String upstreamFollowExport() {
  return jsonEncode([
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
    {
      "siteId": "huya",
      "id": "huya_789",
      "roomId": "789",
      "userName": "主播C",
      "face": "https://example.com/c.png",
      "addTime": "2026-01-03 00:00:00.000",
      "tag": "常看",
      "isSpecialFollow": false,
    },
  ]);
}

void main() {
  late Directory hiveDirectory;
  late DBService db;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'upstream_follow_import_test_',
    );
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(FollowUserAdapter());
    Hive.registerAdapter(HistoryAdapter());
    Hive.registerAdapter(FollowUserTagAdapter());
  });

  setUp(() async {
    db = DBService();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    db.followBox = await Hive.openBox<FollowUser>('follow_$stamp');
    db.tagBox = await Hive.openBox<FollowUserTag>('tag_$stamp');
    db.historyBox = await Hive.openBox<History>('history_$stamp');
    Get.put<DBService>(db);
  });

  tearDown(() async {
    await db.followBox.deleteFromDisk();
    await db.tagBox.deleteFromDisk();
    await db.historyBox.deleteFromDisk();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      hiveDirectory.deleteSync(recursive: true);
    }
  });

  test('上游关注文件被识别为关注，并按 tag 字段重建标签', () async {
    final content = upstreamFollowExport();
    final inspection = ProfileBackupService().inspectProfileJson(content);

    // 识别侧：必须是关注，不能被误判成标签。
    expect(inspection.availableCategories, [ProfileCategory.follows]);
    expect(
      inspection.categories[ProfileCategory.follows]!.detail,
      "3 个关注",
    );

    // 落库侧：走与导入相同的批量服务，验证真的进了关注表。
    final result = await BulkDataImportService.importFollowUsers(
      jsonDecode(content),
      syncTagsFromUserField: true,
    );

    expect(result.imported, 3);
    expect(result.skipped, 0);
    expect(db.followBox.length, 3);

    final bilibili = db.followBox.get('bilibili_123');
    expect(bilibili, isNotNull);
    expect(bilibili!.userName, '主播A');
    expect(bilibili.roomId, '123');
    expect(db.followBox.get('douyu_456')!.isSpecialFollow, isTrue);

    // 「全部」不该变成一个真实标签，「常看」应该建出来并含两个成员。
    final tags = db.tagBox.values.toList();
    expect(tags.map((e) => e.tag), ['常看']);
    expect(
      tags.single.userId..sort(),
      ['douyu_456', 'huya_789'],
    );
  });

  test('关注项缺少 roomId/siteId 时被跳过而非写入脏数据', () async {
    final result = await BulkDataImportService.importFollowUsers(
      jsonDecode(jsonEncode([
        {"siteId": "bilibili", "roomId": "1", "userName": "有效"},
        {"userName": "缺少房间号"},
        {"siteId": "", "roomId": "", "userName": "空字段"},
      ])),
      syncTagsFromUserField: true,
    );

    expect(result.imported, 1);
    expect(result.skipped, 2);
    expect(db.followBox.length, 1);
    expect(db.followBox.values.single.userName, '有效');
  });

  test('顶层数组的历史文件进历史表，不会串到关注表', () async {
    final content = jsonEncode([
      {
        "id": "bilibili_1",
        "roomId": "1",
        "siteId": "bilibili",
        "userName": "主播A",
        "face": "",
        "updateTime": "2026-01-01 10:00:00.000",
      },
    ]);

    final inspection = ProfileBackupService().inspectProfileJson(content);
    expect(inspection.availableCategories, [ProfileCategory.histories]);

    final result = await BulkDataImportService.importHistories(
      jsonDecode(content),
    );

    expect(result.imported, 1);
    expect(db.historyBox.length, 1);
    expect(db.followBox.length, 0);
  });

  test('带独立标签列表的数据仍按标签表导入', () async {
    final content = jsonEncode([
      {"id": "t1", "tag": "常看", "userId": ["bilibili_1", "douyu_2"]},
    ]);

    final inspection = ProfileBackupService().inspectProfileJson(content);
    expect(
      inspection.categories[ProfileCategory.follows]!.detail,
      "1 个标签",
    );

    final result = await BulkDataImportService.importFollowTags(
      jsonDecode(content),
    );

    expect(result.imported, 1);
    expect(db.tagBox.length, 1);
    expect(db.tagBox.values.single.userId, ['bilibili_1', 'douyu_2']);
    expect(db.followBox.length, 0);
  });
}
