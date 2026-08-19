import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  group('KuaishouSite.resolveRoomTitle', () {
    test('prefers the room caption over the author name', () {
      expect(
        KuaishouSite.resolveRoomTitle({
          'caption': '今晚冲榜',
          'author': {'name': '测试主播'},
          'gameInfo': {'name': '王者荣耀'},
        }),
        '今晚冲榜',
      );
    });

    test('falls back through stream, game, and author fields', () {
      expect(
        KuaishouSite.resolveRoomTitle({
          'liveStream': {'caption': '直播流标题'},
          'author': {'name': '测试主播'},
        }),
        '直播流标题',
      );
      expect(
        KuaishouSite.resolveRoomTitle({
          'gameInfo': {'name': '主机游戏'},
          'author': {'name': '测试主播'},
        }),
        '主机游戏',
      );
      expect(
        KuaishouSite.resolveRoomTitle({
          'author': {'name': '测试主播'},
        }),
        '测试主播',
      );
    });
  });

  group('KuaishouSite.resolveLiveStatus', () {
    test('accepts explicit live flags', () {
      expect(KuaishouSite.resolveLiveStatus({'isLiving': true}), isTrue);
      expect(KuaishouSite.resolveLiveStatus({'living': 1}), isTrue);
    });

    test('uses playable stream evidence when the flag is stale', () {
      expect(
        KuaishouSite.resolveLiveStatus({
          'isLiving': false,
          'liveStream': {
            'id': 'stream-id',
            'playUrls': {
              'h264': {
                'adaptationSet': {
                  'representation': [
                    {'url': 'https://example.com/live.flv'},
                  ],
                },
              },
            },
          },
        }),
        isTrue,
      );
    });

    test('uses playable urls even when stream id and live flag are stale', () {
      expect(
        KuaishouSite.resolveLiveState({
          'isLiving': false,
          'liveStream': {
            'id': '',
            'playUrls': {
              'h264': {
                'adaptationSet': {
                  'representation': [
                    {'url': 'https://example.com/live.flv'},
                  ],
                },
              },
            },
          },
        }),
        LiveStatusState.live,
      );
    });

    test('accepts the flat room-list stream shape used by the live API', () {
      expect(
        KuaishouSite.resolveLiveStatus({
          'id': 'stream-id',
          'living': false,
          'playUrls': [
            {
              'adaptationSet': {
                'representation': [
                  {'url': 'https://example.com/live.flv'},
                ],
              },
            },
          ],
        }),
        isTrue,
      );
    });

    test('does not mark an empty stream as live', () {
      expect(
        KuaishouSite.resolveLiveStatus({
          'isLiving': false,
          'liveStream': {'id': '', 'playUrls': const {}},
        }),
        isFalse,
      );
    });
  });

  test('parses qualities from the flat room-list playUrls payload', () async {
    final detail = LiveRoomDetail(
      roomId: 'author-id',
      title: '直播间',
      cover: '',
      userName: '主播',
      userAvatar: '',
      online: 1,
      status: true,
      url: 'stream-id',
      data: [
        {
          'type': 'dynamic',
          'adaptationSet': {
            'representation': [
              {
                'name': '高清',
                'level': 30,
                'url': 'https://example.com/sd.flv',
              },
              {
                'name': '蓝光',
                'level': 70,
                'url': 'https://example.com/hd.flv',
              },
            ],
          },
        },
      ],
    );

    final qualities = await KuaishouSite().getPlayQualites(detail: detail);

    expect(qualities.map((item) => item.quality), ['蓝光', '高清']);
    expect(qualities.first.data, ['https://example.com/hd.flv']);
  });

  test('falls back when advertised h264 group has no stream', () async {
    final detail = LiveRoomDetail(
      roomId: 'room-id',
      title: '直播间',
      cover: '',
      userName: '主播',
      userAvatar: '',
      online: 1,
      status: true,
      url: 'stream-id',
      data: {
        'h264': const [],
        'hevc': [
          {
            'name': '蓝光',
            'level': 70,
            'url': 'https://example.com/hevc.flv',
          },
        ],
      },
    );

    final qualities = await KuaishouSite().getPlayQualites(detail: detail);

    expect(qualities, hasLength(1));
    expect(qualities.first.quality, '蓝光');
    expect(qualities.first.data, ['https://example.com/hevc.flv']);
  });

  group('KuaishouSite live-state aggregation', () {
    test('stream id is live even while playback url is delayed', () {
      expect(
        KuaishouSite.resolveLiveState({
          'liveStream': {'id': 'stream-id', 'playUrls': const {}},
        }),
        LiveStatusState.live,
      );
    });

    test('distinguishes explicit offline and missing evidence', () {
      expect(
        KuaishouSite.resolveLiveState({'isLiving': false}),
        LiveStatusState.offline,
      );
      expect(
        KuaishouSite.resolveLiveState({'caption': '风控或不完整响应'}),
        LiveStatusState.unknown,
      );
    });

    test('treats an HTTP 200 room error snapshot as unknown', () {
      expect(
        KuaishouSite.resolveLiveState({
          'isLiving': false,
          'liveStream': const {},
          'author': const {},
          'errorType': const {
            'type': 2,
            'title': '请求过快，请稍后重试',
            'content': '浏览其他内容',
          },
        }),
        LiveStatusState.unknown,
      );
    });

    test('live stream evidence wins even when an error object is present', () {
      expect(
        KuaishouSite.resolveLiveState({
          'isLiving': false,
          'liveStream': {'id': 'active-stream'},
          'errorType': const {
            'type': 2,
            'title': '请求过快，请稍后重试',
          },
        }),
        LiveStatusState.live,
      );
    });

    test('scans every playList item and live evidence wins', () {
      expect(
        KuaishouSite.resolvePlayListState([
          {'isLiving': false},
          {
            'liveStream': {'id': 'second-live-stream'},
          },
        ]),
        LiveStatusState.live,
      );
    });

    test('mixed offline and unknown remains unknown', () {
      expect(
        KuaishouSite.resolvePlayListState([
          {'isLiving': false},
          {'caption': '字段缺失'},
        ]),
        LiveStatusState.unknown,
      );
    });
  });

  test('extracts nested playable urls and rejects non-stream values', () {
    expect(
      KuaishouSite.extractPlayableUrls({
        'url': {
          'primary': 'https://example.com/live.flv',
          'backup': [
            'rtmp://example.com/live',
            'https://example.com/live.flv',
            'ftp://example.com/not-supported',
          ],
        },
        'label': '高清',
      }),
      [
        'https://example.com/live.flv',
        'rtmp://example.com/live',
      ],
    );
  });

  test('does not stringify a nested url object as a playback address',
      () async {
    final detail = LiveRoomDetail(
      roomId: 'room-id',
      title: '直播间',
      cover: '',
      userName: '主播',
      userAvatar: '',
      online: 1,
      status: true,
      url: 'https://live.kuaishou.com/u/room-id',
      data: {
        'h264': [
          {
            'name': '蓝光',
            'level': 70,
            'url': {
              'primary': 'https://example.com/live.flv',
            },
          },
        ],
      },
    );

    final qualities = await KuaishouSite().getPlayQualites(detail: detail);
    expect(qualities, hasLength(1));
    expect(qualities.single.data, ['https://example.com/live.flv']);
  });

  group('KuaishouSite.isImageUrl', () {
    test('无扩展名的 http(s) URL 视为图片（快手实时截图）', () {
      expect(
        KuaishouSite.isImageUrl(
          'https://live3.static.yximgs.com/live/game/screenshot/9tFQiiOLSg8~1785822457911~1',
        ),
        isTrue,
      );
    });

    test('常规图片扩展名视为图片', () {
      expect(KuaishouSite.isImageUrl('https://x.com/a.png'), isTrue);
      expect(KuaishouSite.isImageUrl('https://x.com/a.jpg'), isTrue);
      expect(KuaishouSite.isImageUrl('https://x.com/a.jpg?v=1'), isTrue);
    });

    test('非图片扩展名与空串不是图片', () {
      expect(KuaishouSite.isImageUrl('https://x.com/a.html'), isFalse);
      expect(KuaishouSite.isImageUrl('https://x.com/a.js'), isFalse);
      expect(KuaishouSite.isImageUrl(''), isFalse);
    });
  });

  group('KuaishouSite Cookie 会话重置', () {
    test('resetCookieSession 清空共享 Cookie 字段与 DID 去重状态', () {
      final site = KuaishouSite();
      site.customCookie = 'kuaishou.live.web_st=abc; did=d1';
      site.cookie = 'did=d1; server_session=x';
      site.cookieObj = {'did': 'd1', 'server_session': 'x'};

      site.resetCookieSession();

      expect(site.cookie, '');
      expect(site.cookieObj, isEmpty);
      // 长期会话应重建（当前为 null，下次 _getCookie 懒初始化）。
      // 注：_sessionDio 是私有字段，通过再次 reset 幂等性间接验证。
      site.resetCookieSession();
      expect(site.cookie, '');
    });
  });

  group('KuaishouSite room detail cache policy', () {
    test('playback recovery bypasses detail cache like status polling', () {
      expect(
        KuaishouSite.roomDetailCacheTtlForSource(
          KuaishouRequestSource.playbackRecovery,
        ),
        isNull,
      );
      expect(
        KuaishouSite.roomDetailCacheTtlForSource(
          KuaishouRequestSource.roomStatusPolling,
        ),
        isNull,
      );
      expect(
        KuaishouSite.roomDetailCacheTtlForSource(
          KuaishouRequestSource.userEnter,
        ),
        const Duration(seconds: 15),
      );
    });
  });

  group('KuaishouSite follow status', () {
    test('uses anonymous public-page parsing instead of the account Cookie',
        () async {
      final seenHeaders = <Map<String, dynamic>>[];
      final anonymousDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              seenHeaders.add(Map<String, dynamic>.from(options.headers));
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _kuaishouOfflinePage(roomId: 'room-1'),
                ),
              );
            },
          ),
        );
      final authenticatedDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _kuaishouRateLimitedPage(roomId: 'room-1'),
                ),
              );
            },
          ),
        );
      final site = KuaishouSite(
        anonymousDio: anonymousDio,
        authenticatedDioFactory: () => authenticatedDio,
      )..activateAccountSession(
          sessionKey: 'primary',
          cookie: 'kuaishou.live.web_st=secret',
          kww: '',
        );

      final state = await site.getFollowLiveStatusState(roomId: 'room-1');

      expect(state, LiveStatusState.offline);
      expect(seenHeaders, hasLength(1));
      expect(seenHeaders.single['cookie'], isNull);
    });

    test('follow status returns unknown when anonymous parsing fails',
        () async {
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _kuaishouRateLimitedPage(roomId: 'limited-room'),
                ),
              );
            },
          ),
        );
      final site = KuaishouSite(anonymousDio: dio);

      final state = await site.getFollowLiveStatusState(roomId: 'limited-room');

      expect(requests, 1);
      expect(state, LiveStatusState.unknown);
    });

    test('follow status forceNetwork bypasses anonymous logical cache',
        () async {
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              final roomId = options.uri.pathSegments.last;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _kuaishouOfflinePage(roomId: roomId),
                ),
              );
            },
          ),
        );
      final site = KuaishouSite(anonymousDio: dio);

      final first = await KuaishouRequestTrace.run(
        KuaishouRequestSource.followStatus,
        () => site.getFollowLiveStatusState(roomId: 'cache-room'),
        scopeId: 'kuaishou:follow-refresh',
        forceNetwork: true,
      );
      final second = await KuaishouRequestTrace.run(
        KuaishouRequestSource.followStatus,
        () => site.getFollowLiveStatusState(roomId: 'cache-room'),
        scopeId: 'kuaishou:follow-refresh',
        forceNetwork: true,
      );

      expect(first, LiveStatusState.offline);
      expect(second, LiveStatusState.offline);
      expect(requests, 2);
    });

    test('follow status propagates challenge pages instead of swallowing them',
        () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: '<html><body>安全验证 captcha</body></html>',
                ),
              );
            },
          ),
        );
      final site = KuaishouSite(anonymousDio: dio);

      await expectLater(
        () => KuaishouRequestTrace.run(
          KuaishouRequestSource.followStatus,
          () => site.getFollowLiveStatusState(roomId: 'challenge-room'),
          scopeId: 'kuaishou:follow-refresh',
          forceNetwork: true,
        ),
        throwsA(
          isA<CoreError>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having(
                (error) => error.message,
                'message',
                contains('安全验证'),
              ),
        ),
      );
    });

    test('follow status physical requests can run concurrently', () async {
      var requests = 0;
      final anonymousDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              requests++;
              final roomId = options.uri.pathSegments.last;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _kuaishouOfflinePage(roomId: roomId),
                ),
              );
            },
          ),
        );
      final site = KuaishouSite(anonymousDio: anonymousDio);

      final states = await Future.wait([
        site.getFollowLiveStatusState(roomId: 'room-a'),
        site.getFollowLiveStatusState(roomId: 'room-b'),
      ]);

      expect(states, everyElement(LiveStatusState.offline));
      expect(requests, 2);
    });

    test('follow status accepts live response without playback urls', () async {
      var requests = 0;
      final anonymousDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _kuaishouLivePage(
                    roomId: 'status-only-live',
                    includePlayback: false,
                  ),
                ),
              );
            },
          ),
        );
      final site = KuaishouSite(anonymousDio: anonymousDio);

      final state =
          await site.getFollowLiveStatusState(roomId: 'status-only-live');

      expect(state, LiveStatusState.live);
      expect(requests, 1);
    });
  });

  group('KuaishouSite account transport isolation', () {
    test('keeps Dio, CookieJar, credentials, and detail cache per slot',
        () async {
      final createdDios = <Dio>[];
      final seenCookies = <String>[];
      Dio createAuthenticatedDio() {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                seenCookies.add(options.headers['cookie']?.toString() ?? '');
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: 200,
                    data: _kuaishouLivePage(roomId: 'room-isolated'),
                  ),
                );
              },
            ),
          );
        createdDios.add(dio);
        return dio;
      }

      final site = KuaishouSite(
        authenticatedDioFactory: createAuthenticatedDio,
        coordinator: KuaishouRequestCoordinator(
          minInterval: Duration.zero,
          maxJitter: Duration.zero,
        ),
      );

      site.activateAccountSession(
        sessionKey: 'primary',
        cookie: 'kuaishou.live.web_st=primary-token',
        kww: 'primary-kww',
      );
      final primaryDetail = await site.getRoomDetail(roomId: 'room-isolated');
      final primaryDio = site.authenticatedDioIdentityFor('primary');
      final primaryJar = site.cookieJarIdentityFor('primary');

      site.activateAccountSession(
        sessionKey: 'secondary',
        cookie: 'kuaishou.live.web_st=secondary-token',
        kww: 'secondary-kww',
      );
      final secondaryDetail = await site.getRoomDetail(roomId: 'room-isolated');
      final secondaryDio = site.authenticatedDioIdentityFor('secondary');
      final secondaryJar = site.cookieJarIdentityFor('secondary');

      site.activateAccountSession(
        sessionKey: 'primary',
        cookie: 'kuaishou.live.web_st=primary-token',
        kww: 'primary-kww',
      );
      final cachedPrimary = await site.getRoomDetail(roomId: 'room-isolated');

      expect(primaryDetail.roomId, 'room-isolated');
      expect(secondaryDetail.roomId, 'room-isolated');
      expect(cachedPrimary.roomId, 'room-isolated');
      expect(createdDios, hasLength(2));
      expect(primaryDio, isNot(same(secondaryDio)));
      expect(primaryJar, isNot(same(secondaryJar)));
      expect(site.authenticatedDioIdentityFor('primary'), same(primaryDio));
      expect(seenCookies, [
        contains('primary-token'),
        contains('secondary-token'),
      ]);
    });

    for (final scenario in [
      (
        name: 'cookie invalidation',
        statusCode: 200,
        body: '<html>登录状态已失效，请重新登录</html>',
        event: KuaishouAccountHealthEvent.credentialInvalid,
      ),
    ]) {
      test('retries one user operation on secondary after ${scenario.name}',
          () async {
        var transportIndex = 0;
        final requestCounts = <int, int>{};
        Dio createAuthenticatedDio() {
          final index = transportIndex++;
          return Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  requestCounts[index] = (requestCounts[index] ?? 0) + 1;
                  handler.resolve(
                    Response<String>(
                      requestOptions: options,
                      statusCode: index == 0 ? scenario.statusCode : 200,
                      data: index == 0
                          ? scenario.body
                          : _kuaishouLivePage(roomId: 'fallback-room'),
                    ),
                  );
                },
              ),
            );
        }

        late final KuaishouSite site;
        final events = <KuaishouAccountHealthEvent>[];
        site = KuaishouSite(
          authenticatedDioFactory: createAuthenticatedDio,
          coordinator: KuaishouRequestCoordinator(
            minInterval: Duration.zero,
            maxJitter: Duration.zero,
          ),
        )
          ..activateAccountSession(
            sessionKey: 'primary',
            cookie: 'kuaishou.live.web_st=primary',
            kww: '',
          )
          ..onAccountHealthEvent = (event) {
            events.add(event);
            site.activateAccountSession(
              sessionKey: 'secondary',
              cookie: 'kuaishou.live.web_st=secondary',
              kww: '',
            );
          };

        final detail = await KuaishouRequestTrace.run(
          KuaishouRequestSource.userEnter,
          () => site.getRoomDetail(roomId: 'fallback-room'),
        );

        expect(detail.roomId, 'fallback-room');
        expect(events, [scenario.event]);
        expect(site.activeAccountSessionKey, 'secondary');
        expect(requestCounts, {0: 1, 1: 1});
      });
    }
  });

  group('KuaishouSite authenticated room warm-up', () {
    late Interceptor roomPageInterceptor;

    tearDown(() {
      HttpClient.instance.dio.interceptors.remove(roomPageInterceptor);
    });

    test('retries a live handshake page without playback using account Cookie',
        () async {
      var handshakeRequests = 0;
      var authenticatedPageRequests = 0;
      String? fallbackCookie;
      final authenticatedDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handshakeRequests += 1;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _kuaishouLivePage(
                    roomId: 'warm-room',
                    includePlayback: false,
                  ),
                ),
              );
            },
          ),
        );
      roomPageInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path != '/u/warm-room') {
            handler.next(options);
            return;
          }
          authenticatedPageRequests += 1;
          fallbackCookie = options.headers['cookie']?.toString();
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: _kuaishouLivePage(
                roomId: 'warm-room',
                includePlayback: authenticatedPageRequests > 1,
              ),
            ),
          );
        },
      );
      HttpClient.instance.dio.interceptors.add(roomPageInterceptor);
      final site = KuaishouSite(
        authenticatedDioFactory: () => authenticatedDio,
        coordinator: KuaishouRequestCoordinator(
          minInterval: Duration.zero,
          maxJitter: Duration.zero,
        ),
      )..activateAccountSession(
          sessionKey: 'primary',
          cookie: 'kuaishou.live.web_st=primary-token',
          kww: '',
        );

      final detail = await site.getRoomDetail(roomId: 'warm-room');

      expect(KuaishouSite.extractPlayableUrls(detail.data), isNotEmpty);
      expect(handshakeRequests, 1);
      expect(authenticatedPageRequests, 2);
      expect(fallbackCookie, contains('primary-token'));
    });

    test('does not cache a live detail that still has no playback', () async {
      var handshakeRequests = 0;
      var authenticatedPageRequests = 0;
      final incompletePage = _kuaishouLivePage(
        roomId: 'incomplete-room',
        includePlayback: false,
      );
      final authenticatedDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handshakeRequests += 1;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: incompletePage,
                ),
              );
            },
          ),
        );
      roomPageInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path != '/u/incomplete-room') {
            handler.next(options);
            return;
          }
          authenticatedPageRequests += 1;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: incompletePage,
            ),
          );
        },
      );
      HttpClient.instance.dio.interceptors.add(roomPageInterceptor);
      final site = KuaishouSite(
        authenticatedDioFactory: () => authenticatedDio,
        coordinator: KuaishouRequestCoordinator(
          minInterval: Duration.zero,
          maxJitter: Duration.zero,
        ),
      )..activateAccountSession(
          sessionKey: 'primary',
          cookie: 'kuaishou.live.web_st=primary-token',
          kww: '',
        );

      await expectLater(
        site.getRoomDetail(roomId: 'incomplete-room'),
        throwsA(isA<CoreError>()),
      );
      await expectLater(
        site.getRoomDetail(roomId: 'incomplete-room'),
        throwsA(isA<CoreError>()),
      );

      expect(handshakeRequests, 2);
      expect(authenticatedPageRequests, 4);
    });
  });

  group('KuaishouSite HTTP 200 rate limiting', () {
    test('tries the backup account without starting host-wide cooldown',
        () async {
      var handshakeRequests = 0;
      var fallbackRequests = 0;
      final accountEvents = <KuaishouAccountHealthEvent>[];
      final authenticatedDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handshakeRequests += 1;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: handshakeRequests == 1
                      ? _kuaishouRateLimitedPage(roomId: 'limited-room')
                      : _kuaishouLivePage(roomId: 'limited-room'),
                ),
              );
            },
          ),
        );
      final site = KuaishouSite(
        authenticatedDioFactory: () => authenticatedDio,
        coordinator: KuaishouRequestCoordinator(
          minInterval: Duration.zero,
          maxJitter: Duration.zero,
        ),
      )
        ..activateAccountSession(
          sessionKey: 'primary',
          cookie: 'kuaishou.live.web_st=primary-token',
          kww: '',
        )
        ..accountFallbackProvider = (_) {
          fallbackRequests += 1;
          return const KuaishouAccountFallbackSession(
            sessionKey: 'secondary',
            cookie: 'kuaishou.live.web_st=secondary-token',
            kww: '',
          );
        }
        ..onAccountSessionHealthEvent = (_, event) {
          accountEvents.add(event);
        };

      final recovered = await KuaishouRequestTrace.run(
        KuaishouRequestSource.userEnter,
        () => site.getRoomDetail(roomId: 'limited-room'),
      );

      expect(recovered.resolvedLiveStatus, LiveStatusState.live);
      expect(site.coordinator.inCooldown, isFalse);
      expect(site.activeAccountSessionKey, 'primary');
      expect(handshakeRequests, 2);
      expect(fallbackRequests, 1);
      expect(accountEvents, isEmpty);
    });
  });

  group('KuaishouSite foreground account fallback', () {
    test('uses the secondary account after the primary request fails',
        () async {
      var transportIndex = 0;
      final authenticatedRequests = <int, int>{};
      Dio createAuthenticatedDio() {
        final index = transportIndex++;
        return Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                authenticatedRequests[index] =
                    (authenticatedRequests[index] ?? 0) + 1;
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: 200,
                    data: index == 0
                        ? _kuaishouRateLimitedPage(roomId: 'fallback-live-room')
                        : _kuaishouLivePage(
                            roomId: 'fallback-live-room',
                            includeDanmakuCredentials: true,
                          ),
                  ),
                );
              },
            ),
          );
      }

      final site = KuaishouSite(
        authenticatedDioFactory: createAuthenticatedDio,
        coordinator: KuaishouRequestCoordinator(
          minInterval: Duration.zero,
          maxJitter: Duration.zero,
        ),
      )
        ..activateAccountSession(
          sessionKey: 'primary',
          cookie: 'kuaishou.live.web_st=primary-token',
          kww: '',
        )
        ..accountFallbackProvider = (_) => const KuaishouAccountFallbackSession(
              sessionKey: 'secondary',
              cookie: 'kuaishou.live.web_st=secondary-token',
              kww: '',
            );

      final detail = await KuaishouRequestTrace.run(
        KuaishouRequestSource.userEnter,
        () => site.getRoomDetail(roomId: 'fallback-live-room'),
      );
      final danmaku = detail.danmakuData as KuaishouDanmakuArgs;

      expect(detail.resolvedLiveStatus, LiveStatusState.live);
      expect(danmaku.hasConnectionInfo, isTrue);
      expect(authenticatedRequests, {0: 1, 1: 1});
    });

    test('does not use anonymous playback after both accounts fail', () async {
      var transportIndex = 0;
      final authenticatedRequests = <int, int>{};
      Dio createAuthenticatedDio() {
        final index = transportIndex++;
        return Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                authenticatedRequests[index] =
                    (authenticatedRequests[index] ?? 0) + 1;
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: 200,
                    data: _kuaishouRateLimitedPage(
                      roomId: 'anonymous-fallback-room',
                    ),
                  ),
                );
              },
            ),
          );
      }

      final site = KuaishouSite(
        authenticatedDioFactory: createAuthenticatedDio,
        coordinator: KuaishouRequestCoordinator(
          minInterval: Duration.zero,
          maxJitter: Duration.zero,
        ),
      )
        ..activateAccountSession(
          sessionKey: 'primary',
          cookie: 'kuaishou.live.web_st=primary-token',
          kww: '',
        )
        ..accountFallbackProvider = (_) => const KuaishouAccountFallbackSession(
              sessionKey: 'secondary',
              cookie: 'kuaishou.live.web_st=secondary-token',
              kww: '',
            );

      await expectLater(
        KuaishouRequestTrace.run(
          KuaishouRequestSource.userEnter,
          () => site.getRoomDetail(roomId: 'anonymous-fallback-room'),
        ),
        throwsA(isA<CoreError>()),
      );

      expect(authenticatedRequests, {0: 1, 1: 1});
    });
  });

  test('room detail requires an account Cookie', () async {
    var authenticatedSessions = 0;
    final site = KuaishouSite(
      authenticatedDioFactory: () {
        authenticatedSessions += 1;
        return Dio();
      },
      coordinator: KuaishouRequestCoordinator(
        minInterval: Duration.zero,
        maxJitter: Duration.zero,
      ),
    );

    site.activateAnonymousMode();
    await expectLater(
      KuaishouRequestTrace.run(
        KuaishouRequestSource.userEnter,
        () => site.getRoomDetail(roomId: 'anonymous-room'),
      ),
      throwsA(
        isA<CoreError>().having((error) => error.statusCode, 'status', 401),
      ),
    );

    expect(site.getDanmaku(), isNot(isA<KuaishouDanmaku>()));
    expect(authenticatedSessions, 0);
  });

  group('KuaishouSite 弹幕冷却注入', () {
    test('getDanmaku 注入协调器冷却检查，冷却时返回 true', () {
      final site = KuaishouSite();
      final danmaku = site.getDanmaku();
      expect(danmaku, isA<KuaishouDanmaku>());

      // 注入的 credentialCooldownCheck 应联动站点协调器冷却状态。
      final check = (danmaku as KuaishouDanmaku).credentialCooldownCheck;
      expect(check, isNotNull);
      expect(check!(), isFalse, reason: '未冷却时不应暂停凭证重试');

      site.coordinator.beginCooldown(const Duration(minutes: 5));
      expect(check(), isTrue, reason: '协调器冷却时凭证重试应感知并暂停');
      site.coordinator.endCooldown();
    });
  });

  group('KuaishouSite challenge page detection', () {
    test('detects the HTTP 200 request-too-fast payload', () {
      expect(
        KuaishouSite.looksLikeExplicitRateLimitText(
          _kuaishouRateLimitedPage(roomId: 'limited-room'),
        ),
        isTrue,
      );
    });

    test('detects verification pages without initial state', () {
      expect(
        KuaishouSite.looksLikeChallengePage('<html>请完成人机验证</html>'),
        isTrue,
      );
      expect(
        KuaishouSite.looksLikeChallengePage('<div id="captcha"></div>'),
        isTrue,
      );
      expect(
        KuaishouSite.looksLikeChallengePage('<html>请求频繁</html>'),
        isTrue,
      );
    });

    test('does not classify a normal room page as challenge', () {
      expect(
        KuaishouSite.looksLikeChallengePage(
          '<script>window.__INITIAL_STATE__={};</script>',
        ),
        isFalse,
      );
    });
  });
}

String _kuaishouLivePage({
  required String roomId,
  bool includeDanmakuCredentials = false,
  bool includePlayback = true,
}) {
  final playUrls = includePlayback
      ? '"playUrls":{"h264":{"adaptationSet":{"representation":[{"name":"高清","url":"https://example.com/$roomId.flv"}]}}}'
      : '"playUrls":{}';
  return '''<script>window.__INITIAL_STATE__={"liveroom":{"token":"${includeDanmakuCredentials ? 'secret-token' : ''}","websocketUrls":[${includeDanmakuCredentials ? '"wss://example.com/live"' : ''}],"playList":[{"isLiving":true,"author":{"id":"$roomId","name":"主播"},"liveStream":{"id":"stream-$roomId",$playUrls}}]}};</script>''';
}

String _kuaishouOfflinePage({required String roomId}) {
  return '''<script>window.__INITIAL_STATE__={"liveroom":{"playList":[{"isLiving":false,"author":{"id":"$roomId","name":"主播"},"liveStream":{"id":"","playUrls":{}}}]}};</script>''';
}

String _kuaishouRateLimitedPage({required String roomId}) {
  return '''<script>window.__INITIAL_STATE__={"liveroom":{"playList":[{"isLiving":false,"author":{},"liveStream":{},"gameInfo":{},"errorType":{"type":2,"title":"请求过快，请稍后重试","content":"浏览其他内容","url":"/u/$roomId"}}]}};</script>''';
}
