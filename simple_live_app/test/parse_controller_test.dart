import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';

void main() {
  test('Douyin short links retain stable and one-time room targets', () async {
    for (final location in [
      'https://live.douyin.com/24680',
      'https://webcast.amemv.com/webcast/reflow/7376429659866598196',
    ]) {
      final client = Dio();
      final requests = <String>[];
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options.uri.toString());
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: options.uri.host == 'v.douyin.com' ? 302 : 200,
          headers: Headers.fromMap({
            'location': [location]
          }),
        ));
      }));
      final target = await LiveRoomLinkParser(redirectClient: client)
          .parse('https://v.douyin.com/example/');
      expect(target?.site.id, 'douyin');
      expect(target?.roomId, Uri.parse(location).pathSegments.last);
      expect(requests, ['https://v.douyin.com/example/', location]);
      client.close();
    }
  });
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

    test('preserves a trailing dot in a dotted Douyin room ID', () {
      const url = 'https://live.douyin.com/Xzh.2022.0323.';
      expect(LiveRoomLinkParser.extractHttpUrl(url), url);
      expect(
        LiveRoomLinkParser.extractHttpUrl('直播地址：$url，欢迎观看'),
        url,
      );
    });

    test('preserves a trailing dot without internal dots in a Douyin room ID',
        () {
      const url = 'https://live.douyin.com/username.';
      expect(LiveRoomLinkParser.extractHttpUrl(url), url);
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
        (await parser.parse('https://live.douyin.com/LM.060313'))?.roomId,
        'LM.060313',
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

    test('keeps dotted room ids scoped to Douyin live links', () async {
      final parser = LiveRoomLinkParser();

      expect(
        (await parser.parse('https://live.douyin.com/LM.060313，'))?.roomId,
        'LM.060313',
      );
      expect(await parser.parse('https://www.huya.com/room.name'), isNull);
      expect(await parser.parse('https://live.douyin.com/..'), isNull);
    });

    test('preserves a trailing dot in a Douyin room ID from share text',
        () async {
      final parser = LiveRoomLinkParser();
      final target = await parser.parse(
        '打开直播间：https://live.douyin.com/Xzh.2022.0323.，快来看看',
      );

      expect(target?.site.id, 'douyin');
      expect(target?.roomId, 'Xzh.2022.0323.');
    });

    test('preserves a trailing dot in a Douyin short-link destination',
        () async {
      const shortUrl = 'https://v.douyin.com/example';
      const destination = 'https://live.douyin.com/Xzh.2022.0323.';
      final client = Dio();
      client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: options.uri.host == 'v.douyin.com' ? 302 : 200,
          headers: Headers.fromMap({'location': [destination]}),
        ));
      }));
      final parser = LiveRoomLinkParser(redirectClient: client);

      expect(
        (await parser.parse(shortUrl))?.roomId,
        'Xzh.2022.0323.',
      );
      client.close();
    });

    test('preserves a trailing dot without internal dots in a Douyin room ID',
        () async {
      final target = await LiveRoomLinkParser()
          .parse('https://live.douyin.com/username.');

      expect(target?.roomId, 'username.');
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
