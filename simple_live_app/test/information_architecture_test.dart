import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mine page exposes the seven agreed first-level entries', () {
    final mine = File('lib/modules/mine/mine_page.dart').readAsStringSync();

    for (final label in <String>[
      'Simple Live',
      '观看记录',
      '账号管理',
      '数据与同步',
      '清理缓存',
      '设置',
      '帮助与排障',
    ]) {
      expect(mine, contains(label), reason: label);
    }
    for (final oldFirstLevelEntry in <String>[
      '链接解析',
      '外观设置',
      '主页设置',
      '播放页设置',
      '直播设置',
      '多开设置',
      '弹幕设置',
      '关注设置',
      '定时关闭',
      '其他设置',
    ]) {
      expect(mine, isNot(contains(oldFirstLevelEntry)));
    }
  });

  test('mine page logo follows the active brightness', () {
    final mine = File('lib/modules/mine/mine_page.dart').readAsStringSync();

    expect(mine, contains('Theme.of(context).brightness == Brightness.dark'));
    expect(mine, contains("'assets/images/logo_dark.png'"));
    expect(mine, contains("'assets/images/logo.png'"));
    expect(File('assets/images/logo_dark.png').existsSync(), isTrue);
  });

  test('settings, support and sync destinations have dedicated routes', () {
    final paths = File('lib/routes/route_path.dart').readAsStringSync();
    final pages = File('lib/routes/app_pages.dart').readAsStringSync();

    for (final route in <String>[
      'kAbout',
      'kSettings',
      'kHelp',
      'kSupportTools',
      'kSyncAdvancedConnection',
    ]) {
      expect(paths, contains(route));
      expect(pages, contains('RoutePath.$route'));
    }
  });

  test('data migration entries converge on data and sync', () {
    final follow = File('lib/modules/follow_user/follow_user_page.dart')
        .readAsStringSync();
    final shields = File(
      'lib/modules/settings/danmu_shield/danmu_shield_page.dart',
    ).readAsStringSync();
    final sync = File('lib/modules/sync/sync_page.dart').readAsStringSync();

    // 关注页的入口改名为「数据管理」，并直接带 kFollowDataArgument 跳到
    // 配置包页的关注分类，不再走 kSync 总入口。守的仍是同一条：
    // 关注页只留一个数据入口，不散落导入/导出文本。
    expect(follow, contains('数据管理'));
    expect(follow, contains('RoutePath.kProfileBackup'));
    expect(follow, contains('ProfileBackupController.kFollowDataArgument'));
    expect(follow, isNot(contains('导出文本')));
    expect(follow, isNot(contains('导入文本')));
    expect(shields, contains('管理备份'));
    expect(sync, contains('高级连接设置'));
    expect(sync, contains('配置包导入导出'));
    expect(sync, contains('WebDAV'));
    expect(sync, contains('局域网同步'));
  });

  test('real-time speech subtitles and their dependency are removed', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final room =
        File('lib/modules/live_room/live_room_page.dart').readAsStringSync();
    final playSettings =
        File('lib/modules/settings/play_settings_page.dart').readAsStringSync();

    expect(pubspec, isNot(contains('sherpa_onnx')));
    expect(room, isNot(contains('实时字幕')));
    expect(playSettings, isNot(contains('实时字幕')));
    expect(
        File('lib/services/live_subtitle_service.dart').existsSync(), isFalse);
  });

  test('live room settings stay focused and own current diagnostics', () {
    final room =
        File('lib/modules/live_room/live_room_page.dart').readAsStringSync();
    final help =
        File('lib/modules/mine/help/help_page.dart').readAsStringSync();

    expect(room, contains('title: "网络诊断与播放信息"'));
    expect(room, contains('title: const Text("播放调整")'));
    expect(room, contains('title: const Text("分享与链接")'));
    for (final advancedLabel in <String>[
      '动态统计跨度',
      '动态展示时间',
      '动态起显次数',
      '动态保留数量',
      '过滤窗口',
      '过滤步长',
    ]) {
      expect(room, isNot(contains(advancedLabel)), reason: advancedLabel);
    }
    expect(
      help,
      isNot(contains('title: const Text("网络诊断与播放信息")')),
    );
  });

  test('empty search page tells users that live links are supported', () {
    final search =
        File('lib/modules/search/search_page.dart').readAsStringSync();
    final aggregateView = File(
      'lib/modules/search/search_aggregate_view.dart',
    ).readAsStringSync();

    expect(search, contains('hintText: "搜点什么吧"'));
    expect(aggregateView, contains('支持粘贴直播链接并直接进入直播间'));
  });

  test('fullscreen setting copy stays concise', () {
    final controls = File(
      'lib/modules/live_room/player/player_controls.dart',
    ).readAsStringSync();

    expect(controls, contains('开启后竖屏直播也会强制横屏'));
    expect(controls, isNot(contains('iPad 更易隐藏状态栏')));
  });
}
