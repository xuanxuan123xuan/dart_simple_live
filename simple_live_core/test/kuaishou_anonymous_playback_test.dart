import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  group('Kuaishou anonymous public playback snapshots', () {
    test('recommend is cookie-free and opens a cached room without danmaku',
        () async {
      final seenHeaders = <Map<String, dynamic>>[];
      var roomPageRequests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              seenHeaders.add(Map<String, dynamic>.from(options.headers));
              if (options.path.endsWith('/live_api/home/list')) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'data': {
                        'list': [
                          {
                            'gameLiveInfo': [
                              {
                                'liveInfo': [
                                  _publicRoom('recommend-room'),
                                ],
                              },
                            ],
                          },
                        ],
                      },
                    },
                  ),
                );
                return;
              }
              roomPageRequests += 1;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _unknownRoomPage('recommend-room'),
                ),
              );
            },
          ),
        );
      var authenticatedSessions = 0;
      final site = _anonymousSite(
        dio,
        authenticatedDioFactory: () {
          authenticatedSessions += 1;
          return Dio();
        },
      );

      final rooms = await site.getRecommendRooms();
      final detail = await site.getRoomDetail(roomId: 'recommend-room');
      final qualities = await site.getPlayQualites(detail: detail);

      expect(rooms.items.single.roomId, 'recommend-room');
      expect(detail.title, '直播 recommend-room');
      expect(detail.danmakuData, isNull);
      expect(qualities, isNotEmpty);
      expect(
        KuaishouSite.extractPlayableUrls(detail.data),
        ['https://example.com/recommend-room.flv'],
      );
      expect(roomPageRequests, 0,
          reason: 'fresh list snapshot should be reused');
      expect(authenticatedSessions, 0);
      expect(
        seenHeaders.expand((headers) => headers.keys),
        everyElement(isNot(equalsIgnoringCase('cookie'))),
      );
      expect(site.getDanmaku(), isNot(isA<KuaishouDanmaku>()));
    });

    test('category and native search both populate anonymous snapshots',
        () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path.endsWith('/live_api/gameboard/list')) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'data': {
                        'list': [_publicRoom('category-room')],
                        'hasMore': false,
                      },
                    },
                  ),
                );
                return;
              }
              if (options.path.endsWith('/live_api/search/liveStream')) {
                final searchRoom = _publicRoom('search-room')
                  ..['authorId'] = 'search-room'
                  ..['author'] = {
                    'id': '',
                    'name': '搜索主播',
                  };
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'data': {
                        'result': 1,
                        'list': [searchRoom],
                        'hasMore': false,
                      },
                    },
                  ),
                );
                return;
              }
              fail('unexpected anonymous request: ${options.path}');
            },
          ),
        );
      final site = _anonymousSite(dio);

      final category = await site.getCategoryRooms(
        LiveSubCategory(id: '10', name: '游戏', parentId: '1'),
      );
      final search = await site.searchRooms('测试');
      final categoryDetail = await site.getRoomDetail(roomId: 'category-room');
      final searchDetail = await site.getRoomDetail(roomId: 'search-room');

      expect(category.items.single.roomId, 'category-room');
      expect(search.items.single.roomId, 'search-room');
      expect(categoryDetail.danmakuData, isNull);
      expect(searchDetail.danmakuData, isNull);
      expect(
        KuaishouSite.extractPlayableUrls(categoryDetail.data),
        isNotEmpty,
      );
      expect(KuaishouSite.extractPlayableUrls(searchDetail.data), isNotEmpty);
    });

    test('overview fallback retains anonymous provenance for its snapshot',
        () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path.endsWith('/live_api/search/liveStream')) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'data': {'result': 0, 'message': 'use overview'},
                    },
                  ),
                );
                return;
              }
              if (options.path.endsWith('/live_api/search/overview')) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'data': {
                        'list': [
                          {
                            'type': 'liveStreams',
                            'list': [_publicRoom('overview-room')],
                          },
                        ],
                      },
                    },
                  ),
                );
                return;
              }
              fail('unexpected anonymous request: ${options.path}');
            },
          ),
        );
      final site = _anonymousSite(dio);

      final result = await site.searchRooms('备用');
      final detail = await site.getRoomDetail(roomId: 'overview-room');

      expect(result.items.single.roomId, 'overview-room');
      expect(result.metadata.origin, SearchOrigin.fallback);
      expect(KuaishouSite.extractPlayableUrls(detail.data), isNotEmpty);
      expect(detail.danmakuData, isNull);
    });

    test('snapshot expires after the short TTL and unknown HTML is rejected',
        () async {
      var now = DateTime.utc(2026, 8, 23, 8);
      var roomPageRequests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path.endsWith('/live_api/home/list')) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'data': {
                        'list': [
                          {
                            'gameLiveInfo': [
                              {
                                'liveInfo': [_publicRoom('expiring-room')],
                              },
                            ],
                          },
                        ],
                      },
                    },
                  ),
                );
                return;
              }
              roomPageRequests += 1;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _unknownRoomPage('expiring-room'),
                ),
              );
            },
          ),
        );
      final site = _anonymousSite(dio, nowProvider: () => now);

      await site.getRecommendRooms();
      now = now.add(const Duration(seconds: 61));

      await expectLater(
        site.getRoomDetail(roomId: 'expiring-room'),
        throwsA(
          isA<CoreError>().having(
            (error) => error.message,
            'message',
            contains('游客播放地址'),
          ),
        ),
      );
      expect(roomPageRequests, 1);
    });

    test('authenticated catalog payload does not survive into anonymous mode',
        () async {
      late Interceptor authenticatedCatalogInterceptor;
      String? authenticatedCookie;
      authenticatedCatalogInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!options.path.endsWith('/live_api/home/list')) {
            handler.next(options);
            return;
          }
          authenticatedCookie = options.headers.entries
              .where((entry) => entry.key.toLowerCase() == 'cookie')
              .map((entry) => entry.value.toString())
              .firstOrNull;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'list': [
                    {
                      'gameLiveInfo': [
                        {
                          'liveInfo': [_publicRoom('account-only-room')],
                        },
                      ],
                    },
                  ],
                },
              },
            ),
          );
        },
      );
      HttpClient.instance.dio.interceptors.add(authenticatedCatalogInterceptor);
      final anonymousDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(
                options.headers.keys,
                everyElement(isNot(equalsIgnoringCase('cookie'))),
              );
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _unknownRoomPage('account-only-room'),
                ),
              );
            },
          ),
        );
      final site = KuaishouSite(
        anonymousDio: anonymousDio,
        coordinator: _coordinator(),
        searchCoordinator: _coordinator(),
      )..activateAccountSession(
          sessionKey: 'account',
          cookie: 'kuaishou.live.web_st=account-token',
          kww: '',
        );

      try {
        final rooms = await site.getRecommendRooms();
        expect(rooms.items.single.roomId, 'account-only-room');
        expect(authenticatedCookie, contains('account-token'));

        site.activateAnonymousMode();
        await expectLater(
          site.getRoomDetail(roomId: 'account-only-room'),
          throwsA(isA<CoreError>()),
        );
      } finally {
        HttpClient.instance.dio.interceptors
            .remove(authenticatedCatalogInterceptor);
      }
    });
  });
}

KuaishouSite _anonymousSite(
  Dio dio, {
  Dio Function()? authenticatedDioFactory,
  DateTime Function()? nowProvider,
}) {
  return KuaishouSite(
    anonymousDio: dio,
    authenticatedDioFactory: authenticatedDioFactory,
    coordinator: _coordinator(),
    searchCoordinator: _coordinator(),
    nowProvider: nowProvider,
  )..activateAnonymousMode();
}

KuaishouRequestCoordinator _coordinator() => KuaishouRequestCoordinator(
      minInterval: Duration.zero,
      maxJitter: Duration.zero,
    );

Map<String, dynamic> _publicRoom(String roomId) => {
      'isLiving': true,
      'caption': '直播 $roomId',
      'poster': 'https://example.com/$roomId.jpg',
      'watchingCount': 123,
      'author': {
        'id': roomId,
        'name': '主播 $roomId',
        'avatar': 'https://example.com/$roomId-avatar.jpg',
      },
      'gameInfo': {'id': 'game-1', 'name': '测试游戏'},
      'liveStream': {
        'id': 'stream-$roomId',
        'playUrls': {
          'h264': {
            'adaptationSet': {
              'representation': [
                {
                  'name': '高清',
                  'level': 2,
                  'url': 'https://example.com/$roomId.flv',
                },
              ],
            },
          },
        },
      },
    };

String _unknownRoomPage(String roomId) =>
    '<script>window.__INITIAL_STATE__={"liveroom":{"playList":['
    '{"author":{"id":"$roomId","name":"主播"},'
    '"liveStream":{"id":"","playUrls":{}}}]}};</script>';
