import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

// Wire shapes from Dart TV ProfileBackupService and the Hive models' toJson.
void main(List<String> args) {
  final output = Directory(args.single)..createSync(recursive: true);
  final stamp = DateTime(2026, 11, 19, 9, 15, 3, 123, 456);
  final follow = {
    'id': 'bilibili_42',
    'siteId': 'bilibili',
    'roomId': '42',
    'userName': '主播',
    'face': '',
    'addTime': stamp.toString(),
    'isSpecialFollow': true,
    'roomTitle': '直播间',
    'roomCover': '',
    'previewUpdatedAt': '',
  };
  final history = {
    'id': 'douyu_17',
    'siteId': 'douyu',
    'roomId': '17',
    'userName': '斗鱼主播',
    'face': '',
    'updateTime': stamp.toUtc().toString(),
  };
  void write(String name, Object data) => File(
    '${output.path}/$name',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  final profile = {
    'schema': 'simple_live_profile',
    'schemaVersion': 4,
    'appVersion': '1.0.0',
    'platform': 'android',
    'exportedAt': stamp.toIso8601String(),
    'settings': {'DanmuEnable': false, 'VideoOutputDriver': 'gpu'},
    'accounts': {
      'items': [
        {'siteId': 'bilibili', 'cookie': 'SESSDATA=fixture'},
        {
          'siteId': 'kuaishou',
          'slots': {
            'primary': {'cookie': 'userId=fixture', 'kww': 'test'},
            'secondary': {'cookie': 'userId=fixture2'},
          },
        },
      ],
    },
    'danmuShield': {
      'raw': ['关键词', '/广告.*/'],
      'keywords': ['关键词'],
      'users': [],
      'userGroups': {},
    },
    'followUsers': [follow],
    'histories': [history],
    'summary': {
      'settingCount': 2,
      'keywordShieldCount': 1,
      'followUserCount': 1,
      'historyCount': 1,
      'accountCount': 2,
    },
  };
  write('dart-profile-v4.json', profile);
  write('dart-legacy-history.json', {
    'data': [history],
  });
  write('dart-legacy-profile.json', {
    'type': 'simple_live',
    'config': {'DouyuCookie': 'uid=fixture'},
    'shield': {'旧规则': '旧规则'},
  });
  final legacyFiles = <String, Object>{
    'SimpleLive_follows.json': {
      'data': [follow],
    },
    'SimpleLive_histories.json': {
      'data': [history],
    },
    'SimpleLive_blocked_word.json': {
      'data': ['关键词', '/广告.*/'],
    },
    'SimpleLive_Settings.json': {
      'data': {'FollowOnlyLive': true},
    },
    'SimpleLive_bilibili_account.json': {
      'data': {'cookie': 'SESSDATA=fixture'},
    },
  };
  void zip(String name, Map<String, Object> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(
        ArchiveFile.string(entry.key, jsonEncode(entry.value))
          ..lastModTime = stamp.millisecondsSinceEpoch ~/ 1000,
      );
    }
    File('${output.path}/$name').writeAsBytesSync(ZipEncoder().encode(archive));
  }

  zip('dart-backup-legacy.zip', legacyFiles);
  zip('dart-backup-v4.zip', {
    ...legacyFiles,
    'SimpleLive_Profile_v4.json': profile,
  });
}
