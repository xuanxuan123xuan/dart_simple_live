import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';

Map<String, dynamic> fixture() => jsonDecode(
    File('test/fixtures/xiaohongshu/live_ssr.json').readAsStringSync());
XiaohongshuRoomSnapshot snapshot(dynamic state) =>
    XiaohongshuSite.parseRoomSnapshotFromMap(state,
        roomId: '570493541297105186');
LiveRoomDetail detail(XiaohongshuRoomSnapshot room) => LiveRoomDetail(
    roomId: room.roomId,
    title: room.title,
    cover: room.cover,
    userName: room.userName,
    userAvatar: room.userAvatar,
    online: room.online,
    status: room.live,
    url: room.url,
    data: room);
void main() {
  test('SSR undefined tokens do not corrupt quoted title text', () {
    final state = fixture();
    state['liveStream']['roomData']['roomInfo']['roomTitle'] =
        'undefined } "text"';
    final raw = jsonEncode(state).replaceFirst('{', '{"missing":undefined,');
    final parsed = XiaohongshuSite.parseRoomSnapshot(
        'window.__INITIAL_STATE__=$raw;',
        roomId: '570493541297105186');
    expect(parsed.title, 'undefined } "text"');
  });
  test('captured SSR maps JSON pullConfig, title, CDN, count and dimensions',
      () {
    final state = fixture();
    final room = snapshot(state);
    expect(room.liveStatusState, LiveStatusState.live);
    expect(room.title, '你的情绪价值来啦！');
    expect(room.cover, startsWith('https://'));
    expect(room.userName, isNotEmpty);
    expect(room.userAvatar, startsWith('https://'));
    expect(room.online, 10000);
    expect(room.streams, hasLength(4));
    expect(room.streams.every((stream) => stream.codec == 'h264'), isTrue);
    expect(room.streams.map((stream) => Uri.parse(stream.url).host).toSet(),
        hasLength(3));
    expect(XiaohongshuSite.resolveStreamAspectRatio(room), 9 / 16);
    expect(
        XiaohongshuSite.parseRoomSnapshot(
                '<script>window.__INITIAL_STATE__ = ${jsonEncode(state)};</script>',
                roomId: room.roomId)
            .title,
        room.title);
  });
  test('prefers H264 and sorts original, HD, SD, LD', () async {
    final state = fixture();
    state['liveStream']['roomData']['roomInfo']['pullConfig'] = jsonEncode({
      'width': 720,
      'height': 1280,
      'h265': [
        {'master_url': 'https://cdn.example/hevc.m3u8', 'quality_type': 'HD'}
      ],
      'h264': [
        for (final quality in ['LD', 'SD', 'HD', '原画'])
          {
            'master_url': 'https://cdn.example/$quality.flv',
            'quality_type_name': quality
          },
        {'master_url': 'javascript:evil', 'quality_type': 'HD'}
      ],
    });
    final room = snapshot(state);
    final roomDetail = detail(room);
    final site = XiaohongshuSite()..cookie = 'a1=private';
    final qualities = await site.getPlayQualites(detail: roomDetail);
    expect(
        qualities.map((quality) => quality.quality), ['原画', 'HD', 'SD', 'LD']);
    final urls =
        await site.getPlayUrls(detail: roomDetail, quality: qualities.first);
    expect(urls.urls, ['https://cdn.example/原画.flv']);
    expect(urls.headers?['Referer'], room.url);
    expect(urls.headers?['Cookie'], 'a1=private');
  });
  test(
      'explicit end is offline, missing status unknown and malformed data fails',
      () {
    expect(() => snapshot({}), throwsA(isA<CoreError>()));
    final state = fixture();
    state['liveStream']['liveStatus'] = 'end';
    state['liveStream']['roomData']['roomInfo']['status'] = 0;
    expect(snapshot(state).liveStatusState, LiveStatusState.offline);
    state['liveStream']['liveStatus'] = 'error';
    state['liveStream']['roomData']['roomInfo'].remove('status');
    expect(snapshot(state).liveStatusState, LiveStatusState.unknown);
  });
  test('HTTP failure does not mark follow offline', () async {
    final dio = HttpClient.instance.dio;
    final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(DioException(
            requestOptions: options, type: DioExceptionType.connectionError)));
    dio.interceptors.insert(0, interceptor);
    try {
      expect(
          await XiaohongshuSite()
              .getLiveStatusState(roomId: '570493541297105186'),
          LiveStatusState.unknown);
    } finally {
      dio.interceptors.remove(interceptor);
    }
  });
  test('unverified directory returns unknown pagination without fake cards',
      () async {
    final site = XiaohongshuSite();
    expect(site.discovery.isAvailable, isFalse);
    expect(await site.getCategores(), isEmpty);
    expect((await site.getRecommendRooms()).items, isEmpty);
    final rooms = await site.searchRooms('测试');
    expect(rooms.items, isEmpty);
    expect(rooms.metadata.origin, SearchOrigin.fallback);
    expect(rooms.metadata.continuation, SearchContinuation.unknown);
  });
  test('normalizes cookie and redacts signing headers', () {
    expect(XiaohongshuSite.normalizeCookie('Cookie: a1=x== ; webId=y'),
        'a1=x==; webId=y');
    final masked = HttpLogSanitizer.redact({
      'Cookie': 'secret',
      'x-s': 'secret',
      'x-t': 'secret',
      'x-sign': 'secret',
      'f': 'secret'
    }) as Map;
    expect(masked.values.toSet(), {'<redacted>'});
  });
}
