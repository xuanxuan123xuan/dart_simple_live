import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('KuaishouLiveLink', () {
    test('builds a public room url', () {
      expect(
        KuaishouLiveLink.publicRoomUrl('abc_123-x'),
        'https://live.kuaishou.com/u/abc_123-x',
      );
    });

    test('parses desktop and mobile room urls', () {
      expect(
        KuaishouLiveLink.parseHttpUrl(
          'https://live.kuaishou.com/u/desktop123?foo=bar',
        ),
        'desktop123',
      );
      expect(
        KuaishouLiveLink.parseHttpUrl(
          'https://m.chenzhongtech.com/fw/live/mobile_123',
        ),
        'mobile_123',
      );
    });

    test('recognizes only the official short-link host', () {
      expect(
        KuaishouLiveLink.isShortLink('https://v.kuaishou.com/AbCdEf'),
        isTrue,
      );
      expect(
        KuaishouLiveLink.isShortLink('https://v.kuaishou.com.evil.test/x'),
        isFalse,
      );
    });

    test('rejects spoofed hosts, userinfo, and non-live paths', () {
      expect(
        KuaishouLiveLink.parseHttpUrl(
          'https://live.kuaishou.com.evil.test/u/room123',
        ),
        isNull,
      );
      expect(
        KuaishouLiveLink.parseHttpUrl(
          'https://live.kuaishou.com@evil.test/u/room123',
        ),
        isNull,
      );
      expect(
        KuaishouLiveLink.parseHttpUrl(
          'https://live.kuaishou.com/search?keyword=room123',
        ),
        isNull,
      );
      expect(
        KuaishouLiveLink.parseHttpUrl(
          'https://evil.chenzhongtech.com/fw/live/room123',
        ),
        isNull,
      );
    });
  });
}
