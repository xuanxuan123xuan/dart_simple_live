import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tvos_app/playback_sources.dart';
import 'package:simple_live_tvos_app/site_registry.dart';
import 'package:simple_live_tvos_app/tvos_session.dart';

void main() {
  test('HLS URLs with auth query are accepted', () {
    expect(isHlsUrl('https://cdn.example.com/a.m3u8?token=a'), isTrue);
    expect(isHlsUrl('https://cdn.example.com/live?format=hls'), isTrue);
  });

  test('FLV and malformed URLs are rejected', () {
    expect(isHlsUrl('https://cdn.example.com/a.flv'), isFalse);
    expect(isHlsUrl('file:///tmp/a.m3u8'), isFalse);
    expect(isHlsUrl('https://cdn.example.com/a.m3u8/evil'), isFalse);
  });

  test('HLS selection removes duplicate links in original order', () {
    final source = LivePlayUrl(
      urls: [
        'https://cdn.example.com/1.flv',
        'https://cdn.example.com/a.m3u8',
        'https://cdn.example.com/a.m3u8',
        'https://cdn.example.com/b.m3u8',
      ],
    );
    expect(hlsOnly(source), [
      'https://cdn.example.com/a.m3u8',
      'https://cdn.example.com/b.m3u8',
    ]);
  });

  test('room ref round trip and bad providers are rejected', () {
    const room = RoomRef(
      provider: LiveProvider.bilibili,
      roomId: '101',
      title: 'Test',
      anchor: 'user',
      cover: '',
    );
    expect(RoomRef.fromJson(room.toJson())?.key, room.key);
    expect(RoomRef.fromJson({'provider': 'invalid', 'roomId': '101'}), isNull);
  });

  test('every provider is mapped to its dev core site', () {
    for (final provider in LiveProvider.values) {
      expect(SiteRegistry.instance.get(provider).name, isNotEmpty);
    }
  });

  test(
    'provider capability labels distinguish HLS, session and unavailable',
    () {
      expect(LiveProvider.bilibili.tvosSupport, TvosProviderSupport.hls);
      expect(
        LiveProvider.xiaohongshu.tvosSupport,
        TvosProviderSupport.sessionRequired,
      );
      expect(LiveProvider.huya.tvosSupport, TvosProviderSupport.unavailable);
    },
  );

  test('memory session store normalizes and clears cookies', () async {
    final store = MemoryTvosSessionStore();
    expect(await store.readCookie(LiveProvider.bilibili), isNull);
    await store.saveCookie(LiveProvider.bilibili, '  buvid3=test  ');
    expect(await store.readCookie(LiveProvider.bilibili), 'buvid3=test');
    await store.saveCookie(LiveProvider.bilibili, '  ');
    expect(await store.readCookie(LiveProvider.bilibili), isNull);
  });
}
