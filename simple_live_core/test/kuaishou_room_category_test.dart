import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  group('Kuaishou room category resolver', () {
    late _CategoryInterceptor interceptor;

    setUp(() {
      interceptor = _CategoryInterceptor();
      HttpClient.instance.dio.interceptors.add(interceptor);
    });

    tearDown(() {
      HttpClient.instance.dio.interceptors.remove(interceptor);
    });

    test('routes game and non-game categories using the directory parent',
        () async {
      interceptor.categoriesByParent = {
        '3': [
          {'id': 'game-id', 'name': '动作游戏'},
        ],
        '6': [
          {'id': 'non-game-id', 'name': '户外'},
        ],
      };
      final site = _site();

      final gameCategory = await site.resolveRoomCategory(_detail('game-id'));
      final nonGameCategory =
          await site.resolveRoomCategory(_detail('non-game-id'));
      expect(gameCategory?.parentId, '3');
      expect(nonGameCategory?.parentId, '6');

      await site.getCategoryRooms(gameCategory!);
      await site.getCategoryRooms(nonGameCategory!);

      expect(
        interceptor.paths.where((path) => path.endsWith('/gameboard/list')),
        hasLength(1),
      );
      expect(
        interceptor.paths.where((path) => path.endsWith('/non-gameboard/list')),
        hasLength(1),
      );
      expect(
        interceptor.requests
            .where((request) => request.path.endsWith('/gameboard/list'))
            .map((request) => request.queryParameters['gameId']),
        ['game-id'],
      );
    });

    test('keeps concurrent room requests for different parents separate',
        () async {
      final site = _site();

      await Future.wait([
        site.getCategoryRooms(
          LiveSubCategory(id: 'shared-id', name: '游戏', parentId: '3'),
        ),
        site.getCategoryRooms(
          LiveSubCategory(id: 'shared-id', name: '娱乐', parentId: '6'),
        ),
      ]);

      expect(
        interceptor.paths.where((path) => path.endsWith('/gameboard/list')),
        hasLength(1),
      );
      expect(
        interceptor.paths.where((path) => path.endsWith('/non-gameboard/list')),
        hasLength(1),
      );
    });

    test('normalizes surrounding whitespace and matches the full category id',
        () async {
      interceptor.categoriesByParent = {
        '3': [
          {'id': 'game-id', 'name': '正式标签'},
          {'id': 'game-id-extra', 'name': '扩展标签'},
        ],
      };
      final site = _site(store: _MemoryCategoryStore());

      final resolved = await site.resolveRoomCategory(_detail(' \tgame-id\n '));

      expect(resolved?.id, 'game-id');
      expect(resolved?.name, '正式标签');
      expect(resolved?.parentId, '3');
      expect(await site.resolveRoomCategory(_detail('game')), isNull);
      expect(await site.resolveRoomCategory(_detail('正式标签')), isNull);
      expect(interceptor.categoryRequests, hasLength(8));
    });

    test('resolves a popular-only match using its directory parent', () async {
      interceptor.categoriesByParent = {
        '1': [
          {'id': 'popular-id', 'name': '热门标签'},
        ],
      };
      final site = _site();

      final resolved = await site.resolveRoomCategory(
        _detail('popular-id', parentId: '6'),
      );

      expect(resolved?.id, 'popular-id');
      expect(resolved?.parentId, '1');
    });

    test('prefers the only formal parent over a duplicate popular entry',
        () async {
      interceptor.categoriesByParent = {
        '1': [
          {'id': 'shared-id', 'name': '热门展示名'},
        ],
        '2': [
          {'id': 'shared-id', 'name': '正式游戏名'},
        ],
      };
      final site = _site();

      final resolved = await site.resolveRoomCategory(
        _detail('shared-id', parentId: '1'),
      );

      expect(resolved?.parentId, '2');
      expect(resolved?.name, '正式游戏名');
    });

    test(
        'returns null for unresolved formal conflicts and validates reported parent',
        () async {
      interceptor.categoriesByParent = {
        '1': [
          {'id': 'ambiguous-id', 'name': '热门标签'},
        ],
        '3': [
          {'id': 'ambiguous-id', 'name': '网游标签'},
        ],
        '4': [
          {'id': 'ambiguous-id', 'name': '手游标签'},
        ],
      };
      final site = _site();

      expect(
        await site.resolveRoomCategory(_detail('ambiguous-id')),
        isNull,
      );
      expect(
        await site.resolveRoomCategory(
          _detail('ambiguous-id', parentId: '8'),
        ),
        isNull,
      );
      expect(
        await site.resolveRoomCategory(
          _detail('ambiguous-id', parentId: '1'),
        ),
        isNull,
      );
      expect(
        (await site.resolveRoomCategory(
          _detail('ambiguous-id', parentId: '4'),
        ))
            ?.parentId,
        '4',
      );
    });

    test('missing tag avoids directory access and an unknown tag returns null',
        () async {
      final site = _site();

      expect(await site.resolveRoomCategory(_detail(null)), isNull);
      expect(await site.resolveRoomCategory(_detail('')), isNull);
      expect(await site.resolveRoomCategory(_detail(' \t\n ')), isNull);
      expect(interceptor.requests, isEmpty);

      expect(await site.resolveRoomCategory(_detail('unknown-id')), isNull);
      expect(interceptor.categoryRequests, hasLength(8));
    });

    test('uses the fresh persisted category snapshot without network access',
        () async {
      final now = DateTime.utc(2026, 10, 25, 8);
      final store = _MemoryCategoryStore()
        ..value = _snapshot(now, {
          '6': [
            {'id': 'cached-id', 'name': '缓存标签'},
          ],
        });
      final site = _site(
        store: store,
        nowProvider: () => now.add(const Duration(hours: 11)),
      );

      final resolved = await site.resolveRoomCategory(_detail('cached-id'));

      expect(resolved?.parentId, '6');
      expect(resolved?.name, '缓存标签');
      expect(interceptor.requests, isEmpty);
    });

    test('coalesces concurrent category reads and refreshes', () async {
      interceptor.categoriesByParent = {
        '5': [
          {'id': 'parallel-id', 'name': '棋牌标签'},
        ],
      };
      final site = _site();

      final results = await Future.wait([
        site.getCategores(),
        site.refreshCategories(),
        site.resolveRoomCategory(_detail('parallel-id')),
      ]);

      expect(results[2], isA<LiveSubCategory>());
      expect(interceptor.categoryRequests, hasLength(8));
    });

    test('preserves CoreError and permits retry after directory failure',
        () async {
      interceptor.failNextCategoryRequest = true;
      final site = _site();

      await expectLater(
        site.resolveRoomCategory(_detail('retry-id')),
        throwsA(isA<CoreError>()),
      );
      expect(await site.resolveRoomCategory(_detail('retry-id')), isNull);
      expect(interceptor.categoryRequests, hasLength(9));
    });

    test('directory refresh stays behind the shared coordinator cooldown',
        () async {
      final site = _site();
      site.coordinator.beginCooldown(const Duration(minutes: 1));

      await expectLater(
        site.resolveRoomCategory(_detail('cooldown-id')),
        throwsA(isA<CoreError>()),
      );
      expect(interceptor.requests, isEmpty);
      expect(site.coordinator.inCooldown, isTrue);
    });
  });
}

KuaishouSite _site({
  _MemoryCategoryStore? store,
  DateTime Function()? nowProvider,
}) =>
    KuaishouSite(
      coordinator: KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
        publicMinInterval: Duration.zero,
        publicMaxJitter: Duration.zero,
      ),
      categorySnapshotStore: store,
      nowProvider: nowProvider,
    )..activateAccountSession(
        sessionKey: 'test',
        cookie: 'kuaishou.live.web_st=test-token',
        kww: '',
      );

LiveRoomDetail _detail(String? categoryId, {String? parentId}) =>
    LiveRoomDetail(
      roomId: 'room-id',
      title: 'room',
      cover: '',
      userName: 'anchor',
      userAvatar: '',
      online: 0,
      status: true,
      url: '',
      categoryId: categoryId,
      categoryParentId: parentId,
    );

Map<String, dynamic> _snapshot(
  DateTime savedAt,
  Map<String, List<Map<String, dynamic>>> categoriesByParent,
) =>
    {
      'version': 1,
      'savedAt': savedAt.toUtc().toIso8601String(),
      'categories': List.generate(8, (index) {
        final parentId = '${index + 1}';
        final entries = categoriesByParent[parentId] ??
            [
              {'id': 'default-$parentId', 'name': 'default-$parentId'},
            ];
        return {
          'id': parentId,
          'name': 'root-$parentId',
          'children': entries
              .map((entry) => {
                    ...entry,
                    'parentId': parentId,
                  })
              .toList(growable: false),
        };
      }),
    };

class _MemoryCategoryStore implements KuaishouCategorySnapshotStore {
  Map<String, dynamic>? value;

  @override
  Future<Map<String, dynamic>?> read() async => value;

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    value = snapshot;
  }
}

class _CategoryInterceptor extends Interceptor {
  final requests = <RequestOptions>[];
  Map<String, List<Map<String, dynamic>>> categoriesByParent = {};
  bool failNextCategoryRequest = false;

  Iterable<String> get paths => requests.map((request) => request.path);

  List<RequestOptions> get categoryRequests => requests
      .where((request) => request.path.endsWith('/category/data'))
      .toList(growable: false);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (options.path.endsWith('/category/data')) {
      if (failNextCategoryRequest) {
        failNextCategoryRequest = false;
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'injected category network failure',
        ));
        return;
      }
      final parentId = options.queryParameters['type'].toString();
      final entries = categoriesByParent[parentId] ??
          [
            {'id': 'default-$parentId', 'name': 'default-$parentId'},
          ];
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'data': {
            'hasMore': false,
            'list': entries,
          },
        },
      ));
      return;
    }
    if (options.path.endsWith('/gameboard/list') ||
        options.path.endsWith('/non-gameboard/list')) {
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'data': {
            'hasMore': false,
            'list': <dynamic>[],
          },
        },
      ));
      return;
    }
    handler.reject(DioException(
      requestOptions: options,
      type: DioExceptionType.unknown,
      message: 'unexpected request ${options.path}',
    ));
  }
}
