import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';

void main() {
  group('LiveRoomLinkParser www.douyin.com live links', () {
    test('parses /live/<roomId>', () async {
      final parser = LiveRoomLinkParser();

      final target = await parser.parse('https://www.douyin.com/live/24680');

      expect(target, isNotNull);
      expect(target!.site.id, Constant.kDouyin);
      expect(target.roomId, '24680');
    });

    test('parses /follow/live/<roomId>', () async {
      final parser = LiveRoomLinkParser();

      final target =
          await parser.parse('https://www.douyin.com/follow/live/13579');

      expect(target, isNotNull);
      expect(target!.site.id, Constant.kDouyin);
      expect(target.roomId, '13579');
    });

    test('accepts dotted and underscored room ids', () async {
      final parser = LiveRoomLinkParser();

      expect(
        (await parser.parse('https://www.douyin.com/live/LM.060313'))?.roomId,
        'LM.060313',
      );
      expect(
        (await parser.parse('https://www.douyin.com/follow/live/room_1-2'))
            ?.roomId,
        'room_1-2',
      );
    });

    test('normalizes an upper-case host', () async {
      final parser = LiveRoomLinkParser();

      final target = await parser.parse('https://WWW.DOUYIN.COM/live/24680');

      expect(target?.roomId, '24680');
      expect(target?.site.id, Constant.kDouyin);
    });

    test('trims Chinese punctuation appended by prose', () async {
      final parser = LiveRoomLinkParser();

      expect(
        (await parser.parse('地址 https://www.douyin.com/live/24680，欢迎观看'))
            ?.roomId,
        '24680',
      );
    });

    test('does not treat other Douyin web pages as live rooms', () async {
      final parser = LiveRoomLinkParser();

      for (final url in <String>[
        'https://www.douyin.com/',
        'https://www.douyin.com/live',
        'https://www.douyin.com/live/',
        'https://www.douyin.com/search/%E7%9B%B4%E6%92%AD',
        'https://www.douyin.com/user/MS4wLjABAAAA',
        'https://www.douyin.com/video/7300000000000000000',
        'https://www.douyin.com/discover',
        'https://www.douyin.com/follow',
        'https://www.douyin.com/foo/live/24680',
        'https://www.douyin.com/follow/foo/live/24680',
      ]) {
        expect(await parser.parse(url), isNull, reason: url);
      }
    });

    test('rejects lookalike hosts', () async {
      final parser = LiveRoomLinkParser();

      for (final url in <String>[
        'https://www.douyin.com.evil.test/live/24680',
        'https://douyin.com.evil.test/live/24680',
        'https://evil-douyin.com/live/24680',
      ]) {
        expect(await parser.parse(url), isNull, reason: url);
      }
    });

    test('keeps the existing live.douyin.com behaviour', () async {
      final parser = LiveRoomLinkParser();

      expect(
        (await parser.parse('https://live.douyin.com/24680'))?.roomId,
        '24680',
      );
    });
  });
}
