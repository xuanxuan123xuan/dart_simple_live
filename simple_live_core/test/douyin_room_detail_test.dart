import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  late _Responses responses;
  late DouyinSite site;
  var sequence = 0;
  late String webRid;
  setUp(() {
    webRid = '123456${sequence++}';
    responses = _Responses();
    HttpClient.instance.dio.interceptors.add(responses);
    site = DouyinSite(abogusSigner: (url, _) => url);
  });
  tearDown(() => HttpClient.instance.dio.interceptors.remove(responses));

  test(
      'empty API room list with identified offline user needs no cookie request',
      () async {
    responses.api = {
      'status_code': 0,
      'data': {'data': [], 'user': _anchor()}
    };
    final detail = await site.getRoomDetail(roomId: webRid);
    expect(detail.status, isFalse);
    expect(detail.roomId, webRid);
    expect(detail.userName, '主播');
    expect(detail.userAvatar, 'https://example.com/avatar.jpg');
    expect(detail.introduction, '简介');
    expect(detail.data, isEmpty);
    expect((detail.danmakuData as DouyinDanmakuArgs).cookie, isEmpty);
    expect(responses.requests, hasLength(1));
  });

  test('room ID ending in a dot retries once without the dot on failure',
      () async {
    const roomId = 'username.';
    responses.apiByWebRid[roomId] = {
      'status_code': 0,
      'data': <String, dynamic>{},
    };
    responses.apiByWebRid['username'] = {
      'status_code': 0,
      'data': {'data': [], 'user': _anchor()}
    };

    final detail = await site.getRoomDetail(roomId: roomId);

    expect(detail.roomId, 'username');
    expect(detail.userName, '主播');
    expect(
      responses.requests
          .where((request) =>
              request.uri.path.contains('/web/enter/') &&
              request.uri.queryParameters.containsKey('web_rid'))
          .map((request) => request.uri.queryParameters['web_rid'])
          .toList(),
      [roomId, 'username'],
    );
  });

  test(
      'HTML anchor without room survives failed cookie HEAD and preserves identity',
      () async {
    responses.html = _page({'anchor': _anchor()});
    responses.failHead = true;
    final detail = await site.getRoomDetail(roomId: webRid);
    expect(detail.status, isFalse);
    expect(detail.roomId, webRid);
    expect(detail.userName, '主播');
    expect((detail.danmakuData as DouyinDanmakuArgs).roomId, isEmpty);
    expect(responses.requests.where((r) => r.method == 'HEAD'), hasLength(1));
  });

  for (final entry in <String, Map>{
    'unknown status': {'data': [], 'user': _anchor()..remove('live_status')},
    'live anchor without room': {
      'data': [],
      'user': _anchor()..['live_status'] = 1
    },
    'missing identity': {'data': [], 'user': _anchor()..remove('id_str')},
    'empty response': {},
    'malformed room status': {
      'data': [
        {'status': 'invalid'}
      ],
      'user': _anchor(),
    },
    'unknown room enum': {
      'data': [
        {'status': 99}
      ],
      'user': _anchor()
    },
  }.entries) {
    test('${entry.key} never becomes an offline detail', () async {
      responses.api = {'status_code': 0, 'data': entry.value};
      await expectLater(
          site.getRoomDetail(roomId: webRid), throwsA(isA<CoreError>()));
      expect(
          responses.requests
              .any((r) => r.method == 'GET' && r.uri.path == '/$webRid'),
          isTrue);
    });
  }

  test('risk-control response is not accepted despite offline-looking payload',
      () async {
    responses.api = {
      'status_code': 444,
      'data': {'data': [], 'user': _anchor()}
    };
    await expectLater(
        site.getRoomDetail(roomId: webRid),
        throwsA(
            isA<CoreError>().having((e) => e.statusCode, 'statusCode', 444)));
    expect(responses.requests, hasLength(1));
  });

  test('offline room with owner and no user metadata is supported', () async {
    responses.api = {
      'data': {
        'data': [
          {'status': 4, 'owner': _anchor()..remove('live_status')}
        ]
      }
    };
    final detail = await site.getRoomDetail(roomId: webRid);
    expect(detail.status, isFalse);
    expect(detail.userName, '主播');
    expect(responses.requests, hasLength(1));
  });

  test('refresh after offline retrieves live streams and danmaku credentials',
      () async {
    responses.api = {
      'data': {'data': [], 'user': _anchor()}
    };
    expect((await site.getRoomDetail(roomId: webRid)).status, isFalse);
    responses.api = {
      'data': {
        'data': [
          {
            'status': '2',
            'id_str': '7376429659866598196',
            'owner': _anchor(),
            'title': '直播标题',
            'cover': {
              'url_list': ['https://example.com/cover.jpg']
            },
            'room_view_stats': {'display_value': '123'},
            'stream_url': {'test_stream': true},
          }
        ]
      }
    };
    final detail = await site.getRoomDetail(roomId: webRid);
    expect(detail.status, isTrue);
    expect(detail.online, 123);
    expect(detail.title, '直播标题');
    expect(detail.data, {'test_stream': true});
    expect((detail.danmakuData as DouyinDanmakuArgs).cookie, isNotEmpty);
    expect(responses.requests.where((r) => r.method == 'HEAD'), hasLength(1));
  });

  test('ended one-time room ID redirects to stable webRid', () async {
    responses.reflow = {
      'data': {
        'room': {
          'status': 4,
          'owner': {'web_rid': webRid}
        }
      }
    };
    responses.api = {
      'data': {'data': [], 'user': _anchor()}
    };
    final detail = await site.getRoomDetail(roomId: '7376429659866598196');
    expect(detail.roomId, webRid);
    expect(detail.status, isFalse);
  });

  for (final invalid in [
    null,
    '',
    'null',
    '0',
    'invalid',
    '7376429659866598196'
  ]) {
    test('one-time room ID rejects invalid stable ID $invalid', () async {
      responses.reflow = {
        'data': {
          'room': {
            'status': 4,
            'owner': {'web_rid': invalid}
          }
        }
      };
      await expectLater(
          site.getRoomDetail(roomId: '7376429659866598196'),
          throwsA(isA<CoreError>()
              .having((e) => e.message, 'message', contains('已失效'))));
      expect(responses.requests, hasLength(1));
    });
  }
}

Map<String, dynamic> _anchor() => {
      'id_str': '1234567890123456789',
      'nickname': '主播',
      'live_status': 0,
      'avatar_thumb': {
        'url_list': ['https://example.com/avatar.jpg']
      },
      'signature': '简介',
    };

String _page(Map info) =>
    jsonEncode({
      'state': {
        'appStore': {},
        'roomStore': {'roomInfo': info}
      }
    }).replaceAll('"', r'\"') +
    r']\n';

class _Responses extends Interceptor {
  Object api = const {};
  final Map<String, Object> apiByWebRid = {};
  Object reflow = const {};
  String html = '';
  bool failHead = false;
  final requests = <RequestOptions>[];
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (options.method == 'HEAD') {
      if (failHead) {
        handler.reject(DioException(
            requestOptions: options, type: DioExceptionType.connectionError));
      } else {
        handler.resolve(Response(requestOptions: options, statusCode: 200));
      }
      return;
    }
    final isApi = options.uri.path.contains('/web/enter/');
    final isReflow = options.uri.path.contains('/reflow/info/');
    final payload = isApi
        ? apiByWebRid[options.uri.queryParameters['web_rid']] ?? api
        : isReflow
            ? reflow
            : html;
    handler.resolve(Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: isApi || isReflow ? payload : payload.toString(),
    ));
  }
}
