import 'dart:convert';
import 'dart:io';

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
  void write(String name, Object data) => File('${output.path}/$name')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  write('dart-profile-v4.json', {
    'schema': 'simple_live_profile',
    'schemaVersion': 4,
    'appVersion': '1.0.0',
    'platform': 'android',
    'exportedAt': stamp.toIso8601String(),
    'settings': {},
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
      'settingCount': 0,
      'keywordShieldCount': 1,
      'followUserCount': 1,
      'historyCount': 1,
      'accountCount': 2,
    },
  });
  write('dart-legacy-history.json', {'data': [history]});
  write('dart-legacy-profile.json', {
    'type': 'simple_live',
    'config': {'DouyuCookie': 'uid=fixture'},
    'shield': {'旧规则': '旧规则'},
  });
}
