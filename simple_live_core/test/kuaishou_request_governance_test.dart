import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  group('Kuaishou public category governance', () {
    late _PublicApiInterceptor interceptor;

    setUp(() {
      interceptor = _PublicApiInterceptor();
      HttpClient.instance.dio.interceptors.add(interceptor);
    });

    tearDown(() {
      HttpClient.instance.dio.interceptors.remove(interceptor);
    });

    test('uses size 50, data.hasMore, deduplication, and complete snapshots',
        () async {
      final store = _MemoryCategoryStore();
      interceptor.categoryResponder = (type, page, size) {
        expect(size, 50);
        if (type == '1') {
          if (page == 1) return _categoryPage(type, 1, 50, hasMore: true);
          if (page == 2) {
            final result = _categoryPage(type, 51, 50, hasMore: true);
            (result['data']['list'] as List).add({
              'id': '1-1',
              'name': 'duplicate',
              'poster': 'duplicate',
            });
            return result;
          }
          return _categoryPage(type, 101, 33, hasMore: false);
        }
        return _categoryPage(type, 1, 1, hasMore: false);
      };
      final site = _site(store: store);

      final categories = await site.refreshCategories();

      expect(categories, hasLength(8));
      expect(categories.first.children, hasLength(133));
      expect(interceptor.categoryPagesFor('1'), [1, 2, 3]);
      expect(store.value?['version'], 1);
      expect((store.value?['categories'] as List), hasLength(8));

      final cachedSite = _site(store: store);
      interceptor.requests.clear();
      final cached = await cachedSite.getCategores();
      expect(cached.first.children, hasLength(133));
      expect(interceptor.requests, isEmpty);
    });

    test('room pages use parent category endpoint and server hasMore',
        () async {
      interceptor.roomResponder = (path, page) => {
            'data': {
              'hasMore': false,
              'list': List.generate(20, (index) => _room(index)),
            },
          };
      final site = _site();
      final category = LiveSubCategory(
        id: 'short-or-long-does-not-matter',
        name: 'game',
        parentId: '5',
      );

      final first = await site.getCategoryRooms(category);
      final second = await site.getCategoryRooms(category);

      expect(first.items, hasLength(20));
      expect(first.hasMore, isFalse);
      expect(second.items, hasLength(20));
      expect(
          interceptor.paths.where((path) => path.endsWith('/gameboard/list')),
          hasLength(2));
    });

    test('business code 400010 starts host cooldown', () async {
      interceptor.homeResponse = {
        'result': 400010,
        'message': '访问太快，请稍候再试',
      };
      final site = _site();

      await expectLater(
        site.getRecommendRooms(),
        throwsA(
          isA<CoreError>().having((error) => error.statusCode, 'status', 429),
        ),
      );
      expect(site.coordinator.inCooldown, isTrue);
    });
  });

  group('Kuaishou anonymous session governance', () {
    test('stores only server cookies and performs one warm retry', () async {
      var requests = 0;
      final requestCookies = <String>[];
      final dio = Dio();
      final anonymousJar = CookieJar();
      final site = KuaishouSite(
        anonymousDio: dio,
        anonymousCookieJar: anonymousJar,
        coordinator: _coordinator(),
      )..customCookie = 'kuaishou.live.web_st=account-secret';
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests++;
          final cookieHeaders = options.headers.entries
              .where((entry) => entry.key.toLowerCase() == 'cookie')
              .map((entry) => entry.value?.toString() ?? '')
              .toList(growable: false);
          requestCookies.add(cookieHeaders.isEmpty ? '' : cookieHeaders.first);
          if (requests == 1) {
            await anonymousJar.saveFromResponse(
              options.uri,
              [Cookie('did', 'temporary-device')],
            );
          }
          handler.resolve(Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: requests == 1
                ? _anonymousStatePage({'caption': 'insufficient'})
                : _anonymousStatePage({'isLiving': false}),
          ));
        },
      ));

      final state = await KuaishouRequestTrace.run(
        KuaishouRequestSource.followStatus,
        () => site.getAnonymousLiveStatusState(roomId: 'room-warm'),
        forceNetwork: true,
      );

      expect(state, LiveStatusState.offline);
      expect(requests, 2);
      expect(requestCookies.first, isEmpty);
      expect(requestCookies.last, contains('did=temporary-device'));
      expect(requestCookies.last, isNot(contains('account-secret')));
      expect(
        site.anonymousCookieJarIdentity,
        isNot(same(site.cookieJarIdentityFor('legacy'))),
      );
    });

    test('three structurally valid unknown pages degrade the refresh round',
        () async {
      var requests = 0;
      final dio = Dio();
      final site = KuaishouSite(
        anonymousDio: dio,
        coordinator: _coordinator(),
      )..beginAnonymousStatusRefresh();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.resolve(Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: _anonymousStatePage({'caption': 'insufficient'}),
          ));
        },
      ));

      for (var index = 0; index < 3; index++) {
        expect(
          await KuaishouRequestTrace.run(
            KuaishouRequestSource.followStatus,
            () => site.getAnonymousLiveStatusState(roomId: 'room-$index'),
            scopeId: 'kuaishou:follow-refresh',
            forceNetwork: true,
          ),
          LiveStatusState.unknown,
        );
      }
      expect(site.anonymousCapability, KuaishouAnonymousCapability.degraded);
      expect(
        await site.getAnonymousLiveStatusState(roomId: 'room-four'),
        LiveStatusState.unknown,
      );
      expect(requests, 3);
    });

    test('400010 stops anonymous status with an explicit limited error',
        () async {
      final dio = Dio();
      final site = KuaishouSite(
        anonymousDio: dio,
        coordinator: _coordinator(),
      );
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: '{"result":400010,"message":"访问太快，请稍候再试"}',
        )),
      ));

      await expectLater(
        site.getAnonymousLiveStatusState(roomId: 'limited-room'),
        throwsA(
          isA<CoreError>().having((error) => error.statusCode, 'status', 429),
        ),
      );
      expect(site.coordinator.inCooldown, isTrue);
    });
  });
}

KuaishouSite _site({_MemoryCategoryStore? store}) => KuaishouSite(
      coordinator: _coordinator(),
      categorySnapshotStore: store,
    );

KuaishouRequestCoordinator _coordinator() => KuaishouRequestCoordinator(
      minInterval: Duration.zero,
      maxJitter: Duration.zero,
      publicMinInterval: Duration.zero,
      publicMaxJitter: Duration.zero,
    );

Map<String, dynamic> _categoryPage(
  String type,
  int start,
  int count, {
  required bool hasMore,
}) =>
    {
      'data': {
        'hasMore': hasMore,
        'list': List.generate(count, (index) {
          final id = start + index;
          return {'id': '$type-$id', 'name': 'category-$type-$id'};
        }),
      },
    };

Map<String, dynamic> _room(int index) => {
      'caption': 'room-$index',
      'poster': 'https://example.com/$index.jpg',
      'watchingCount': index,
      'author': {'id': 'author-$index', 'name': 'anchor-$index'},
    };

String _anonymousStatePage(Map<String, dynamic> room) {
  final body = room.entries.map((entry) {
    final value = entry.value;
    if (value is bool) return '"${entry.key}":$value';
    return '"${entry.key}":"$value"';
  }).join(',');
  return '<script>window.__INITIAL_STATE__={"liveroom":{"playList":[{$body}]}};</script>';
}

class _MemoryCategoryStore implements KuaishouCategorySnapshotStore {
  Map<String, dynamic>? value;

  @override
  Future<Map<String, dynamic>?> read() async => value;

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    value = snapshot;
  }
}

class _PublicApiInterceptor extends Interceptor {
  final requests = <RequestOptions>[];
  Map<String, dynamic> Function(String type, int page, int size)?
      categoryResponder;
  Map<String, dynamic> Function(String path, int page)? roomResponder;
  Map<String, dynamic>? homeResponse;

  Iterable<String> get paths => requests.map((request) => request.path);

  List<int> categoryPagesFor(String type) => requests
      .where((request) =>
          request.path.endsWith('/category/data') &&
          request.queryParameters['type'].toString() == type)
      .map((request) => request.queryParameters['page'] as int)
      .toList();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    dynamic data;
    if (options.path.endsWith('/category/data')) {
      data = categoryResponder?.call(
        options.queryParameters['type'].toString(),
        options.queryParameters['page'] as int,
        options.queryParameters['size'] as int,
      );
    } else if (options.path.endsWith('/gameboard/list') ||
        options.path.endsWith('/non-gameboard/list')) {
      data = roomResponder?.call(
        options.path,
        options.queryParameters['page'] as int,
      );
    } else if (options.path.endsWith('/home/list')) {
      data = homeResponse;
    }
    if (data == null) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: 500),
      ));
      return;
    }
    handler.resolve(Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: data,
    ));
  }
}
