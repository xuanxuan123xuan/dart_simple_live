import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';

void main() {
  group('LiveRoomLinkParser.extractHttpUrl', () {
    test('extracts a Douyin short URL from share text', () {
      const shareText =
          '正在直播，复制链接打开抖音 https://v.douyin.com/GiurKu1HX_I/ 5@9.com';

      expect(
        LiveRoomLinkParser.extractHttpUrl(shareText),
        'https://v.douyin.com/GiurKu1HX_I/',
      );
    });

    test('removes punctuation appended by prose', () {
      expect(
        LiveRoomLinkParser.extractHttpUrl(
          '直播地址：https://live.douyin.com/123456，欢迎观看',
        ),
        'https://live.douyin.com/123456',
      );
    });

    test('returns empty text when no URL exists', () {
      expect(LiveRoomLinkParser.extractHttpUrl('没有链接'), isEmpty);
    });
  });

  group('LiveRoomLinkParser Kuaishou links', () {
    test('parses desktop and mobile links', () async {
      final parser = LiveRoomLinkParser();

      expect(
        (await parser.parse('https://live.kuaishou.com/u/desktop123'))?.roomId,
        'desktop123',
      );
      expect(
        (await parser.parse(
          'https://m.chenzhongtech.com/fw/live/mobile_123',
        ))
            ?.roomId,
        'mobile_123',
      );
    });

    test('resolves an official short link and validates its target', () async {
      final parser = LiveRoomLinkParser(
        locationResolver: (_) async =>
            'https://live.kuaishou.com/u/resolved-room',
      );

      expect(
        (await parser.parse('https://v.kuaishou.com/AbCdEf'))?.roomId,
        'resolved-room',
      );
    });

    test('rejects forged hosts and malicious short-link targets', () async {
      final directParser = LiveRoomLinkParser();
      expect(
        await directParser.parse(
          'https://live.kuaishou.com.evil.test/u/room123',
        ),
        isNull,
      );

      final shortParser = LiveRoomLinkParser(
        locationResolver: (_) async => 'https://evil.test/u/room123',
      );
      expect(
        await shortParser.parse('https://v.kuaishou.com/AbCdEf'),
        isNull,
      );
    });
  });

  group('LiveRoomLinkParser direct live links', () {
    test('parses supported platform room links', () async {
      final parser = LiveRoomLinkParser();

      expect(
        (await parser.parse('https://live.bilibili.com/12345'))?.roomId,
        '12345',
      );
      expect(
        (await parser.parse('https://www.huya.com/room_name'))?.roomId,
        'room_name',
      );
      expect(
        (await parser.parse('https://www.douyu.com/67890'))?.roomId,
        '67890',
      );
      expect(
        (await parser.parse('https://live.douyin.com/24680'))?.roomId,
        '24680',
      );
      expect(
        (await parser.parse(
          'https://webcast.amemv.com/webcast/reflow/13579',
        ))
            ?.roomId,
        '13579',
      );
      expect(
        (await parser.parse('https://live.kuaishou.com/u/kuaishou_1'))?.roomId,
        'kuaishou_1',
      );
      expect(
        (await parser.parse('https://www.douyu.com/topic/event?rid=11223'))
            ?.roomId,
        '11223',
      );
    });

    test('rejects lookalike hosts for every supported platform', () async {
      final parser = LiveRoomLinkParser();

      for (final url in <String>[
        'https://live.bilibili.com.evil.test/12345',
        'https://www.huya.com.evil.test/room_name',
        'https://www.douyu.com.evil.test/67890',
        'https://live.douyin.com.evil.test/24680',
        'https://webcast.amemv.com.evil.test/webcast/reflow/24680',
        'https://live.kuaishou.com.evil.test/u/room123',
      ]) {
        expect(await parser.parse(url), isNull, reason: url);
      }
    });

    test('returns a strongly typed target with the matching site', () async {
      final parser = LiveRoomLinkParser();
      final target = await parser.parse('https://www.huya.com/room_name');

      expect(target, isA<LiveRoomLinkTarget>());
      expect(target?.site.id, 'huya');
      expect(target?.roomId, 'room_name');
    });
  });
}
