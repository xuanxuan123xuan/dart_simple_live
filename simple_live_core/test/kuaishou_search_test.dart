import 'dart:async';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  late _KuaishouSearchInterceptor interceptor;

  setUp(() {
    interceptor = _KuaishouSearchInterceptor();
    HttpClient.instance.dio.interceptors.add(interceptor);
  });

  tearDown(() {
    HttpClient.instance.dio.interceptors.remove(interceptor);
  });

  test('uses a valid empty overview fallback after the primary request fails',
      () async {
    interceptor.respondToPrimaryWithError();
    interceptor.respondToOverviewWith({
      'data': {
        'list': [
          {'type': 'liveStreams', 'list': []},
        ],
      },
    });

    final result = await _testSite().searchRooms('risk-test');

    expect(result.items, isEmpty);
    expect(result.metadata.origin, SearchOrigin.fallback);
    expect(result.metadata.continuation, SearchContinuation.done);
    expect(interceptor.requestPaths, [
      _KuaishouSearchInterceptor.liveStreamsPath,
      _KuaishouSearchInterceptor.overviewPath,
    ]);
  });

  test('keeps a valid empty primary page without probing overview', () async {
    interceptor.respondToPrimaryWith({
      'data': {'result': 1, 'list': []},
    });

    final result = await _testSite().searchRooms('risk-test');

    expect(result.items, isEmpty);
    expect(result.metadata.origin, SearchOrigin.native);
    expect(result.metadata.continuation, SearchContinuation.unknown);
    expect(interceptor.requestPaths, [
      _KuaishouSearchInterceptor.liveStreamsPath,
    ]);
  });

  test('throws CoreError when both primary and malformed overview fail',
      () async {
    interceptor.respondToPrimaryWithError();
    interceptor.respondToOverviewWith({
      'data': {
        'list': [
          {'type': 'liveStreams', 'list': 'not-a-list'},
        ],
      },
    });

    await expectLater(
      _testSite().searchRooms('risk-test'),
      throwsA(
        isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.search,
        ),
      ),
    );
    expect(interceptor.requestPaths, [
      _KuaishouSearchInterceptor.liveStreamsPath,
      _KuaishouSearchInterceptor.overviewPath,
    ]);
  });

  test('does not request overview when the primary request is cancelled',
      () async {
    interceptor.respondToPrimaryWithCancellation();

    await expectLater(
      _testSite().searchRooms('risk-test'),
      throwsA(isA<CoreCancelledError>()),
    );
    expect(
        interceptor.requestPaths, [_KuaishouSearchInterceptor.liveStreamsPath]);
  });

  test('uses count 20 and reports more when total exceeds the first page',
      () async {
    interceptor.respondToPrimaryWith({
      'data': {
        'result': 1,
        'total': 21,
        'list': [
          {
            'author': {'id': 'room-1', 'name': '主播'},
            'caption': '直播间',
          },
        ],
      },
    });

    final result = await _testSite().searchRooms('risk-test');

    expect(result.metadata.origin, SearchOrigin.native);
    expect(result.metadata.continuation, SearchContinuation.more);
    expect(result.hasMore, isTrue);
    expect(interceptor.primaryRequestCount, 20);
    expect(
        interceptor.requestPaths, [_KuaishouSearchInterceptor.liveStreamsPath]);
  });

  test('search is not blocked by work running on the main request lane',
      () async {
    interceptor.respondToPrimaryWith({
      'data': {'result': 1, 'list': []},
    });
    final mainCoordinator = KuaishouRequestCoordinator(
      minInterval: Duration.zero,
      maxJitter: Duration.zero,
    );
    final gate = Completer<void>();
    final running = mainCoordinator.schedule<void>(
      priority: KuaishouRequestPriority.userEnter,
      key: 'busy-room-request',
      task: () => gate.future,
    );
    final site = _testSite(coordinator: mainCoordinator);

    final result = await site
        .searchRooms('foreground-search')
        .timeout(const Duration(seconds: 1));

    expect(result.items, isEmpty);
    expect(
        interceptor.requestPaths, [_KuaishouSearchInterceptor.liveStreamsPath]);
    gate.complete();
    await running;
  });
}

KuaishouSite _testSite({KuaishouRequestCoordinator? coordinator}) {
  return KuaishouSite(coordinator: coordinator)
    ..customCookie = 'did=test-device; userId=test-user';
}

class _KuaishouSearchInterceptor extends Interceptor {
  static const liveStreamsPath = '/live_api/search/liveStream';
  static const overviewPath = '/live_api/search/overview';

  final List<String> requestPaths = [];
  Object? _primaryResponse;
  Object? _overviewResponse;
  _RequestFailure? _primaryFailure;

  int? get primaryRequestCount => _primaryRequestCount;
  int? _primaryRequestCount;

  void respondToPrimaryWith(Object response) {
    _primaryResponse = response;
  }

  void respondToPrimaryWithError() {
    _primaryFailure = _RequestFailure.network;
  }

  void respondToPrimaryWithCancellation() {
    _primaryFailure = _RequestFailure.cancelled;
  }

  void respondToOverviewWith(Object response) {
    _overviewResponse = response;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requestPaths.add(options.uri.path);
    switch (options.uri.path) {
      case liveStreamsPath:
        _primaryRequestCount = options.queryParameters['count'] as int?;
        final failure = _primaryFailure;
        if (failure != null) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: failure == _RequestFailure.cancelled
                  ? DioExceptionType.cancel
                  : DioExceptionType.connectionError,
            ),
          );
          return;
        }
        handler.resolve(_response(options, _primaryResponse));
        return;
      case overviewPath:
        handler.resolve(_response(options, _overviewResponse));
        return;
      default:
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: StateError('Unexpected external request: ${options.uri}'),
          ),
        );
    }
  }

  Response<Object?> _response(RequestOptions options, Object? data) {
    if (data == null) {
      throw StateError('No mock response configured for ${options.uri.path}');
    }
    return Response<Object?>(
      requestOptions: options,
      statusCode: 200,
      data: data,
    );
  }
}

enum _RequestFailure { network, cancelled }
