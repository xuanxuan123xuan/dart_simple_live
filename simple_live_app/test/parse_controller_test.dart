import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/parse/parse_controller.dart';

void main() {
  group('ParseController.extractHttpUrl', () {
    test('extracts a Douyin short URL from share text', () {
      const shareText =
          '正在直播，复制链接打开抖音 https://v.douyin.com/GiurKu1HX_I/ 5@9.com';

      expect(
        ParseController.extractHttpUrl(shareText),
        'https://v.douyin.com/GiurKu1HX_I/',
      );
    });

    test('removes punctuation appended by prose', () {
      expect(
        ParseController.extractHttpUrl(
          '直播地址：https://live.douyin.com/123456，欢迎观看',
        ),
        'https://live.douyin.com/123456',
      );
    });

    test('returns empty text when no URL exists', () {
      expect(ParseController.extractHttpUrl('没有链接'), isEmpty);
    });
  });

  group('ParseController Kuaishou links', () {
    test('parses desktop and mobile links', () async {
      final controller = ParseController();
      addTearDown(controller.dispose);

      expect(
        (await controller.parse('https://live.kuaishou.com/u/desktop123'))
            .first,
        'desktop123',
      );
      expect(
        (await controller.parse(
          'https://m.chenzhongtech.com/fw/live/mobile_123',
        ))
            .first,
        'mobile_123',
      );
    });

    test('resolves an official short link and validates its target', () async {
      final controller = ParseController(
        locationResolver: (_) async =>
            'https://live.kuaishou.com/u/resolved-room',
      );
      addTearDown(controller.dispose);

      expect(
        (await controller.parse('https://v.kuaishou.com/AbCdEf')).first,
        'resolved-room',
      );
    });

    test('rejects forged hosts and malicious short-link targets', () async {
      final directController = ParseController();
      addTearDown(directController.dispose);
      expect(
        await directController.parse(
          'https://live.kuaishou.com.evil.test/u/room123',
        ),
        isEmpty,
      );

      final shortController = ParseController(
        locationResolver: (_) async => 'https://evil.test/u/room123',
      );
      addTearDown(shortController.dispose);
      expect(
        await shortController.parse('https://v.kuaishou.com/AbCdEf'),
        isEmpty,
      );
    });
  });
}
