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

  test('getRoomDetail forwards secUserId through a recovered room lookup',
      () async {
    final recoveredWebRid = webRid;
    responses.reflowSequence.addAll([
      {'status_code': 0, 'data': <String, dynamic>{}},
      _endedRoomResponse(recoveredWebRid, includeStatusCode: false),
    ]);
    _setOfflineRoomResponse(responses, recoveredWebRid);

    final detail = await site.getRoomDetail(
      roomId: '7376429659866598196',
      secUserId: 'sec_user_for_test',
    );

    expect(detail.roomId, recoveredWebRid);
    expect(
      responses.requests
          .where((request) => request.uri.path.contains('/reflow/info/'))
          .map((request) => request.uri.queryParameters['sec_user_id'])
          .toList(),
      ['sec_user_for_test', 'sec_user_for_test'],
    );
    expect(responses.reflowRequestCount, 2);
  });

  for (final entry in <String, Object?>{
    'missing data': {'status_code': 0},
    'null data': {'status_code': 0, 'data': null},
    'empty room map': {
      'status_code': 0,
      'data': {'room': <String, dynamic>{}},
    },
    'null room': {
      'status_code': 0,
      'data': {'room': null},
    },
  }.entries) {
    test('${entry.key} response recovers when the retry has a room',
        () async {
      responses.reflowSequence.addAll([
        entry.value,
        _endedRoomResponse(webRid, includeStatusCode: false),
      ]);
      _setOfflineRoomResponse(responses, webRid);

      final detail = await site.getRoomDetail(
        roomId: '7376429659866598196',
      );

      expect(detail.roomId, webRid);
      expect(responses.reflowRequestCount, 2);
    });
  }

  test('getRoomDetailByRoomId forwards optional secUserId', () async {
    _setOfflineRoomResponse(responses, webRid);
    responses.reflow = _endedRoomResponse(webRid);

    final detail = await site.getRoomDetailByRoomId(
      '7376429659866598196',
      secUserId: 'sec_user_for_test',
    );

    expect(detail.roomId, webRid);
    expect(
      responses.requests
          .singleWhere((request) =>
              request.uri.path.contains('/reflow/info/'))
          .uri
          .queryParameters['sec_user_id'],
      'sec_user_for_test',
    );
    expect(responses.reflowRequestCount, 1);
  });

  test('empty room response is retried once then returns the retry hint',
      () async {
    responses.reflow = {'status_code': 0, 'data': <String, dynamic>{}};

    await expectLater(
      site.getRoomDetail(roomId: '7376429659866598196'),
      throwsA(
        isA<CoreError>()
            .having((error) => error.message, 'message',
                '抖音暂未返回直播间数据，请稍后重试，或通过主播固定直播间链接重新进入')
            .having((error) => error.kind, 'kind', CoreErrorKind.response),
      ),
    );

    expect(responses.reflowRequestCount, 2);
  });

  for (final statusCode in [444, 1234]) {
    test('business status_code $statusCode is preserved without retry',
        () async {
      responses.reflow = {
        'status_code': statusCode,
        'data': {'room': <String, dynamic>{}},
      };

      await expectLater(
        site.getRoomDetail(roomId: '7376429659866598196'),
        throwsA(isA<CoreError>().having(
          (error) => error.statusCode,
          'statusCode',
          statusCode,
        )),
      );

      expect(responses.reflowRequestCount, 1);
    });
  }

  test('HTTP failure is not retried', () async {
    responses.reflowHttpErrorStatus = 503;

    await expectLater(
      site.getRoomDetail(roomId: '7376429659866598196'),
      throwsA(isA<CoreError>().having(
        (error) => error.statusCode,
        'statusCode',
        503,
      )),
    );

    expect(responses.reflowRequestCount, 1);
  });

  test('cancelled room lookup is not retried', () async {
    responses.cancelReflow = true;

    await expectLater(
      site.getRoomDetail(roomId: '7376429659866598196'),
      throwsA(isA<CoreCancelledError>()),
    );

    expect(responses.reflowRequestCount, 1);
  });

  for (final entry in <String, Object?>{
    'non-map response': 'invalid response',
    'malformed status code': {
      'status_code': 'not-a-number',
      'data': {'room': <String, dynamic>{}},
    },
    'non-map data': {'status_code': 0, 'data': <dynamic>[]},
    'non-map room': {
      'status_code': 0,
      'data': {'room': 'invalid room'},
    },
  }.entries) {
    test('${entry.key} is a response error without retry', () async {
      responses.reflow = entry.value;

      await expectLater(
        site.getRoomDetail(roomId: '7376429659866598196'),
        throwsA(isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.response,
        )),
      );

      expect(responses.reflowRequestCount, 1);
    });
  }

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

Map<String, dynamic> _endedRoomResponse(
  String webRid, {
  bool includeStatusCode = true,
}) => {
      if (includeStatusCode) 'status_code': 0,
      'data': {
        'room': {
          'status': 4,
          'owner': {'web_rid': webRid}
        }
      }
    };

void _setOfflineRoomResponse(_Responses responses, String webRid) {
  responses.apiByWebRid[webRid] = {
    'status_code': 0,
    'data': {
      'data': <dynamic>[],
      'user': _anchor()..['web_rid'] = webRid,
    }
  };
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
  Object? reflow = const {};
  final List<Object?> reflowSequence = [];
  int reflowRequestCount = 0;
  int? reflowHttpErrorStatus;
  bool cancelReflow = false;
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
    if (isReflow) {
      reflowRequestCount++;
      if (cancelReflow) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ),
        );
        return;
      }
      final httpErrorStatus = reflowHttpErrorStatus;
      if (httpErrorStatus != null) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: httpErrorStatus,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        return;
      }
      final payload = reflowSequence.isNotEmpty
          ? reflowSequence.removeAt(0)
          : reflow;
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: payload,
        ),
      );
      return;
    }
    final payload = isApi
        ? apiByWebRid[options.uri.queryParameters['web_rid']] ?? api
        : html;
    handler.resolve(Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: isApi ? payload : payload.toString(),
    ));
  }
}
