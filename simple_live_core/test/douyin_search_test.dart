import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  late _DouyinSearchInterceptor interceptor;

  setUp(() {
    interceptor = _DouyinSearchInterceptor();
    HttpClient.instance.dio.interceptors.add(interceptor);
  });

  tearDown(() {
    HttpClient.instance.dio.interceptors.remove(interceptor);
  });

  test('does not issue the search GET when the cookie HEAD is cancelled',
      () async {
    interceptor.cancelHead();

    await expectLater(
      DouyinSite().searchRooms('risk-test'),
      throwsA(isA<CoreCancelledError>()),
    );

    expect(interceptor.requests, [
      _DouyinSearchInterceptor.headRequest,
    ]);
  });

  test('derives anchors and preserves the room search continuation', () async {
    interceptor.respondToHead();
    interceptor.respondToSearchWith(_searchResponse());

    final result = await DouyinSite().searchAnchors('anchor');

    expect(result.metadata.origin, SearchOrigin.derived);
    expect(result.metadata.continuation, SearchContinuation.done);
    expect(result.hasMore, isFalse);
    expect(result.metadata.fieldSources['avatar'],
        SearchFieldSource.unavailable);
    expect(result.metadata.fieldSources['liveStatus'], SearchFieldSource.derived);
    expect(result.items, hasLength(1));
    expect(result.items.single.roomId, 'room-1');
    expect(result.items.single.userName, 'anchor');
    expect(result.items.single.avatar, isEmpty);
    expect(interceptor.requests, [
      _DouyinSearchInterceptor.headRequest,
      _DouyinSearchInterceptor.searchRequest,
    ]);
  });
}

Map<String, dynamic> _searchResponse() {
  return {
    'status_code': 0,
    'data': [
      {
        'lives': {
          'rawdata': jsonEncode({
            'owner': {'web_rid': 'room-1', 'nickname': 'anchor'},
            'title': 'A test room',
            'cover': {
              'url_list': ['https://example.invalid/cover.jpg'],
            },
            'stats': {'total_user': '42'},
          }),
        },
      },
    ],
  };
}

class _DouyinSearchInterceptor extends Interceptor {
  static const headRequest = 'HEAD https://live.douyin.com';
  static const searchRequest =
      'GET https://www.douyin.com/aweme/v1/web/live/search/';

  final List<String> requests = [];
  bool _cancelHead = false;
  Object? _searchResponse;

  void cancelHead() {
    _cancelHead = true;
  }

  void respondToHead() {
    _cancelHead = false;
  }

  void respondToSearchWith(Object response) {
    _searchResponse = response;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final request =
        '${options.method} ${options.uri.scheme}://${options.uri.host}'
        '${options.uri.path}';
    requests.add(request);

    if (request == headRequest) {
      if (_cancelHead) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ),
        );
      } else {
        handler.resolve(Response<void>(
          requestOptions: options,
          statusCode: 200,
        ));
      }
      return;
    }

    if (request == searchRequest && _searchResponse != null) {
      handler.resolve(Response<Object>(
        requestOptions: options,
        statusCode: 200,
        data: _searchResponse,
      ));
      return;
    }

    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: StateError('Unexpected external request: ${options.uri}'),
      ),
    );
  }
}
