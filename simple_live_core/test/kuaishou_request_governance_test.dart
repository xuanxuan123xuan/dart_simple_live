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
      expect(
        interceptor.requests,
        everyElement(
          isA<RequestOptions>().having(
            (request) => request.headers['cookie']?.toString(),
            'Cookie header',
            contains('test-token'),
          ),
        ),
      );
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

    test('business code 400010 is reported without host-wide cooldown',
        () async {
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
      expect(site.coordinator.inCooldown, isFalse);
    });
  });

  test('legacy follow-status entry point uses the configured Cookie', () async {
    String? seenCookie;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          seenCookie = options.headers['cookie']?.toString();
          handler.resolve(Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: _anonymousStatePage({'isLiving': false}),
          ));
        },
      ));
    final site = KuaishouSite(
      authenticatedDioFactory: () => dio,
      coordinator: _coordinator(),
    )..activateAccountSession(
        sessionKey: 'primary',
        cookie: 'kuaishou.live.web_st=account-secret',
        kww: '',
      );

    final state = await site.getAnonymousLiveStatusState(roomId: 'room');

    expect(state, LiveStatusState.offline);
    expect(seenCookie, contains('account-secret'));
  });
}

KuaishouSite _site({_MemoryCategoryStore? store}) => KuaishouSite(
      coordinator: _coordinator(),
      categorySnapshotStore: store,
    )..activateAccountSession(
        sessionKey: 'primary',
        cookie: 'kuaishou.live.web_st=test-token',
        kww: '',
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
