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

const oldHostId = '5eafa4cc0000000001005613';
const otherHostId = '64afa4cc0000000001005613';
const oldRoomId = '570493541297105186';
const currentRoomId = '570493541297105187';

String roomHtml(
  String roomId, {
  String? hostId,
  required bool live,
}) {
  final state = fixture();
  final liveStream = state['liveStream'] as Map<String, dynamic>;
  final roomData = liveStream['roomData'] as Map<String, dynamic>;
  final roomInfo = roomData['roomInfo'] as Map<String, dynamic>;
  roomInfo['roomId'] = roomId;
  roomInfo['status'] = live ? 2 : 0;
  roomInfo['deeplink'] = 'xhsdiscover://live_audience?room_id=$roomId'
      '${hostId == null ? '' : '&host_id=$hostId'}';
  liveStream['liveStatus'] = live ? 'success' : 'end';
  return 'window.__INITIAL_STATE__=${jsonEncode(state)};';
}

class _HostBridge
    implements XiaohongshuRequestBridge, XiaohongshuHostRequestBridge {
  _HostBridge(this.response, {this.error});

  final dynamic response;
  final Object? error;
  int hostCalls = 0;
  final hostRooms = <String>[];

  @override
  Future<dynamic> requestHost({
    required String hostId,
    required String roomId,
  }) async {
    hostCalls++;
    hostRooms.add('$hostId:$roomId');
    if (error case final error?) throw error;
    return response;
  }

  @override
  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    dynamic body,
  }) async =>
      throw StateError('Unexpected signed H5 request: $path');
}

class _XhsHttpFixture {
  _XhsHttpFixture({
    required this.rooms,
    this.profile,
    this.profileStatusCode = 200,
    this.cancelRooms = const {},
  });

  final Map<String, String> rooms;
  final dynamic profile;
  final int profileStatusCode;
  final Set<String> cancelRooms;
  final requests = <RequestOptions>[];
  InterceptorsWrapper? interceptor;

  void install() {
    interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      if (options.uri.path.startsWith('/livestream/')) {
        final roomId = options.uri.path.substring('/livestream/'.length);
        if (cancelRooms.contains(roomId)) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ));
          return;
        }
        final html = rooms[roomId];
        if (html == null) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ));
        } else {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: html,
          ));
        }
        return;
      }
      if (options.uri.host == 'edith.xiaohongshu.com' &&
          options.uri.path == XiaohongshuSite.hostProfilePath) {
        if (profileStatusCode != 200) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: profileStatusCode,
              data: const <String, dynamic>{},
            ),
          ));
        } else {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: profile,
          ));
        }
        return;
      }
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ));
    });
    HttpClient.instance.dio.interceptors.add(interceptor!);
  }

  void remove() {
    final value = interceptor;
    if (value != null) HttpClient.instance.dio.interceptors.remove(value);
  }

  List<RequestOptions> get profileRequests => requests
      .where((request) => request.uri.host == 'edith.xiaohongshu.com')
      .toList();

  List<RequestOptions> get roomRequests => requests
      .where((request) => request.uri.path.startsWith('/livestream/'))
      .toList();
}

Map<String, dynamic> profileResponse({
  String? identity = oldHostId,
  required int status,
  String? roomId,
  bool camelCase = false,
}) =>
    {
      'success': true,
      'data': {
        camelCase ? 'basicInfo' : 'basic_info': {
          if (identity != null) (camelCase ? 'userId' : 'user_id'): identity,
          'live': {
            camelCase ? 'liveStatus' : 'live_status': status,
            if (roomId != null) (camelCase ? 'roomId' : 'room_id'): roomId,
          },
        },
      },
    };

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
  test('old room resolves once to the matching current host room', () async {
    final http = _XhsHttpFixture(
      rooms: {
        oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false),
        currentRoomId: roomHtml(currentRoomId, hostId: oldHostId, live: true),
      },
      profileStatusCode: 406,
    )..install();
    final bridge = _HostBridge(
      profileResponse(status: 2, roomId: currentRoomId),
    );
    try {
      final room = await XiaohongshuSite(requestBridge: bridge)
          .getRoomDetail(roomId: oldRoomId);
      expect(room.roomId, currentRoomId);
      expect(room.resolvedLiveStatus, LiveStatusState.live);
      expect((room.data as XiaohongshuRoomSnapshot).hostId, oldHostId);
      expect(room.url,
          'https://www.xiaohongshu.com/livestream/$currentRoomId?host_id=$oldHostId');
      expect(bridge.hostCalls, 1);
      expect(bridge.hostRooms, ['$oldHostId:$oldRoomId']);
      expect(http.profileRequests, hasLength(1));
      expect(http.roomRequests.map((request) => request.uri.path), [
        '/livestream/$oldRoomId',
        '/livestream/$currentRoomId',
      ]);
      expect(http.profileRequests.single.queryParameters, {
        'target_user_id': oldHostId,
        'image_formats': 'jpg,webp',
        'xsec_source': 'pc_hovercard',
        'xsec_token': '',
      });
    } finally {
      http.remove();
    }
  });
  test('authoritative host offline returns offline without a replacement fetch',
      () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      profile: profileResponse(identity: null, status: 0, camelCase: true),
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.offline);
      expect(room.online, 10000);
      expect((room.data as XiaohongshuRoomSnapshot).streams, isEmpty);
      expect(http.profileRequests, hasLength(1));
      expect(http.roomRequests, hasLength(1));
    } finally {
      http.remove();
    }
  });
  test('camel-case basicInfo.live resolves the current room', () async {
    final http = _XhsHttpFixture(
      rooms: {
        oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false),
        currentRoomId: roomHtml(currentRoomId, hostId: oldHostId, live: true),
      },
      profile: profileResponse(
        identity: null,
        status: 2,
        roomId: currentRoomId,
        camelCase: true,
      ),
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.roomId, currentRoomId);
      expect(room.resolvedLiveStatus, LiveStatusState.live);
      expect(http.profileRequests, hasLength(1));
      expect(http.roomRequests, hasLength(2));
    } finally {
      http.remove();
    }
  });
  test('root live status is not mistaken for basic_info.live', () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      profile: {
        'success': true,
        'data': {
          'basic_info': {'user_id': oldHostId},
          'live_status': {'status': 0, 'room_id': currentRoomId},
        },
      },
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect(http.roomRequests, hasLength(1));
    } finally {
      http.remove();
    }
  });
  test('profile identity mismatch is unknown and does not fetch a room',
      () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      profile: profileResponse(
        identity: otherHostId,
        status: 2,
        roomId: currentRoomId,
      ),
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect((room.data as XiaohongshuRoomSnapshot).streams, isEmpty);
      expect(http.roomRequests, hasLength(1));
      expect(room.data.statusMessage, contains('不匹配'));
    } finally {
      http.remove();
    }
  });
  test('replacement room requires a matching host identity', () async {
    final replacement = roomHtml(
      currentRoomId,
      live: true,
    );
    final http = _XhsHttpFixture(
      rooms: {
        oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false),
        currentRoomId: replacement,
      },
      profile: profileResponse(status: 2, roomId: currentRoomId),
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.roomId, oldRoomId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect((room.data as XiaohongshuRoomSnapshot).streams, isEmpty);
      expect(room.data.statusMessage, contains('标识不匹配'));
      expect(http.roomRequests, hasLength(2));
    } finally {
      http.remove();
    }
  });
  test('old room cannot follow a conflicting saved host identity', () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: otherHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect(room.data.statusMessage, contains('不匹配'));
      expect(http.profileRequests, isEmpty);
    } finally {
      http.remove();
    }
  });
  test('profile live and replacement offline is an unknown contradiction',
      () async {
    final http = _XhsHttpFixture(
      rooms: {
        oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false),
        currentRoomId: roomHtml(currentRoomId, hostId: oldHostId, live: false),
      },
      profile: profileResponse(status: 2, roomId: currentRoomId),
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.roomId, oldRoomId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect(http.roomRequests, hasLength(2));
    } finally {
      http.remove();
    }
  });
  test('unidentified live room and host offline is an unknown contradiction',
      () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, live: true)},
      profile: profileResponse(status: 0),
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect((room.data as XiaohongshuRoomSnapshot).streams, isEmpty);
      expect(http.profileRequests, hasLength(1));
    } finally {
      http.remove();
    }
  });
  test('anonymous login business error tries one signed host lookup', () async {
    final http = _XhsHttpFixture(
      rooms: {
        oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false),
        currentRoomId: roomHtml(currentRoomId, hostId: oldHostId, live: true),
      },
      profile: {
        'success': false,
        'code': -101,
        'msg': '无登录信息，或登录信息为空',
      },
    )..install();
    final bridge =
        _HostBridge(profileResponse(status: 2, roomId: currentRoomId));
    try {
      final room = await XiaohongshuSite(requestBridge: bridge)
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.live);
      expect(room.roomId, currentRoomId);
      expect(bridge.hostCalls, 1);
      expect(http.roomRequests, hasLength(2));
    } finally {
      http.remove();
    }
  });
  test('anonymous login business error without a bridge stays unknown',
      () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      profile: {
        'success': false,
        'code': -101,
        'msg': '无登录信息，或登录信息为空',
      },
    )..install();
    try {
      final room = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect(http.profileRequests, hasLength(1));
      expect(http.roomRequests, hasLength(1));
    } finally {
      http.remove();
    }
  });
  test('host bridge cancellation propagates from room detail', () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      profileStatusCode: 406,
    )..install();
    final bridge = _HostBridge(null, error: CoreCancelledError());
    try {
      await expectLater(
        XiaohongshuSite(requestBridge: bridge)
            .getRoomDetail(roomId: oldRoomId, hostId: oldHostId),
        throwsA(isA<CoreCancelledError>()),
      );
      expect(bridge.hostCalls, 1);
    } finally {
      http.remove();
    }
  });
  test('replacement fetch cancellation propagates from room detail', () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      cancelRooms: {currentRoomId},
      profile: profileResponse(status: 2, roomId: currentRoomId),
    )..install();
    try {
      await expectLater(
        XiaohongshuSite().getRoomDetail(roomId: oldRoomId, hostId: oldHostId),
        throwsA(isA<CoreCancelledError>()),
      );
    } finally {
      http.remove();
    }
  });
  test('406 host bridge timeout is unknown and lookup remains bounded',
      () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      profileStatusCode: 406,
    )..install();
    final bridge = _HostBridge(
      null,
      error: CoreError('timeout', kind: CoreErrorKind.network),
    );
    try {
      final room = await XiaohongshuSite(requestBridge: bridge)
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect((room.data as XiaohongshuRoomSnapshot).streams, isEmpty);
      expect(room.data.statusMessage, isNot(contains('timeout')));
      expect(bridge.hostCalls, 1);
      expect(http.profileRequests, hasLength(1));
      expect(http.roomRequests, hasLength(1));
    } finally {
      http.remove();
    }
  });
  test('local WebView2 prerequisite message survives signed bridge failure',
      () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      profileStatusCode: 406,
    )..install();
    final bridge = _HostBridge(
      null,
      error: XiaohongshuWebSessionUnavailableError.webView2Runtime(),
    );
    try {
      final room = await XiaohongshuSite(requestBridge: bridge)
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect(room.data.statusMessage,
          '未检测到 Microsoft Edge WebView2 Runtime，请安装后重试');
      expect(bridge.hostCalls, 1);
      expect(http.roomRequests, hasLength(1));
    } finally {
      http.remove();
    }
  });
  test('local Linux runtime prerequisite survives signed bridge failure',
      () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: false)},
      profileStatusCode: 406,
    )..install();
    final bridge = _HostBridge(
      null,
      error: XiaohongshuWebSessionUnavailableError.linuxRuntime(),
    );
    try {
      final room = await XiaohongshuSite(requestBridge: bridge)
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(room.resolvedLiveStatus, LiveStatusState.unknown);
      expect(room.data.statusMessage,
          '未检测到可用的 Linux WebKitGTK 运行库，请安装后重试');
      expect((room.data as XiaohongshuRoomSnapshot).streams, isEmpty);
      expect(bridge.hostCalls, 1);
      expect(http.profileRequests, hasLength(1));
      expect(http.roomRequests, hasLength(1));
    } finally {
      http.remove();
    }
  });
  test('current live room remains anonymously playable without profile lookup',
      () async {
    final http = _XhsHttpFixture(
      rooms: {oldRoomId: roomHtml(oldRoomId, hostId: oldHostId, live: true)},
    )..install();
    try {
      final room = await XiaohongshuSite().getRoomDetail(roomId: oldRoomId);
      expect(room.resolvedLiveStatus, LiveStatusState.live);
      expect((room.data as XiaohongshuRoomSnapshot).streams, hasLength(4));
      expect(http.profileRequests, isEmpty);
      final matching = await XiaohongshuSite()
          .getRoomDetail(roomId: oldRoomId, hostId: oldHostId);
      expect(matching.resolvedLiveStatus, LiveStatusState.live);
      expect(http.profileRequests, isEmpty);
    } finally {
      http.remove();
    }
  });
  test('room parser never takes host or streams from nextRoomInfo', () {
    final state = fixture();
    final liveStream = state['liveStream'] as Map<String, dynamic>;
    final roomData = liveStream['roomData'] as Map<String, dynamic>;
    final roomInfo = roomData['roomInfo'] as Map<String, dynamic>;
    roomInfo.remove('pullConfig');
    roomInfo['deeplink'] =
        'xhsdiscover://live_audience?room_id=$oldRoomId&host_id=$oldHostId';
    roomData['hostInfo'] = {'userId': oldHostId, 'nickname': '当前主播'};
    liveStream['nextRoomInfo'] = {
      'roomData': {
        'roomInfo': {
          'roomTitle': '推荐主播',
          'status': 2,
          'pullConfig': jsonEncode({
            'h264': [
              {'master_url': 'https://cdn.example/recommend.m3u8'}
            ],
          }),
        },
        'hostInfo': {'userId': otherHostId, 'nickname': '推荐主播'},
      },
      'liveStatus': 'success',
    };
    final room = snapshot(state);
    expect(room.title, '你的情绪价值来啦！');
    expect(room.userName, '当前主播');
    expect(room.hostId, oldHostId);
    expect(room.streams, isEmpty);
  });
  test('ended old room without host identity remains unknown', () async {
    final state = fixture();
    final roomData = state['liveStream']['roomData'] as Map<String, dynamic>;
    final roomInfo = roomData['roomInfo'] as Map<String, dynamic>;
    roomInfo['status'] = 0;
    roomInfo['deeplink'] = 'xhsdiscover://live_audience?room_id=$oldRoomId';
    state['liveStream']['liveStatus'] = 'end';
    final http = _XhsHttpFixture(
      rooms: {
        oldRoomId: 'window.__INITIAL_STATE__=${jsonEncode(state)};',
      },
    )..install();
    try {
      final state =
          await XiaohongshuSite().getLiveStatusState(roomId: oldRoomId);
      expect(state, LiveStatusState.unknown);
      expect(http.profileRequests, isEmpty);
    } finally {
      http.remove();
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
