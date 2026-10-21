import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

const _roomId = '123456';
const _aliasRoomId = '654321';

LiveRoomDetail _detail([String roomId = _roomId]) => LiveRoomDetail(
      roomId: roomId,
      title: '',
      cover: '',
      userName: '',
      userAvatar: '',
      online: 0,
      status: true,
      url: '',
    );

String _md5(String value) => md5.convert(utf8.encode(value)).toString();

String _jwt(int expirySeconds) {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'exp': expirySeconds})))
      .replaceAll('=', '');
  return 'header.$payload.signature';
}

Map<String, dynamic> _encryptionResponse(
  DateTime now, {
  String key = 'key-secret',
  String randStr = 'random-seed',
  int encTime = 1,
  bool isSpecial = false,
  Duration serverTtl = const Duration(days: 1),
}) =>
    {
      'error': 0,
      'data': {
        'key': key,
        'rand_str': randStr,
        'enc_time': encTime,
        'expire_at': now.add(serverTtl).millisecondsSinceEpoch ~/ 1000,
        'is_special': isSpecial ? 1 : 0,
        'enc_data': 'enc+data/with=reserved',
      },
    };

Response<dynamic> _ok(
  RequestOptions options,
  dynamic data, {
  Map<String, List<String>> headers = const {},
}) =>
    Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: data,
      headers: Headers.fromMap(headers),
    );

Map<String, dynamic> _room({dynamic showStatus, dynamic videoLoop}) => {
      'room_id': int.parse(_roomId),
      'room_pic': 'https://example.com/cover.jpg',
      'room_biz_all': {'hot': '100'},
      'room_name': '标题',
      'owner_name': '主播',
      'owner_avatar': 'https://example.com/avatar.jpg',
      'show_details': '简介',
      if (showStatus != null) 'show_status': showStatus,
      if (videoLoop != null) 'videoLoop': videoLoop,
    };

class _DouyuRoomInterceptor extends Interceptor {
  dynamic roomResponse = {'room': _room(showStatus: 2, videoLoop: 0)};
  dynamic h5Response = {
    'data': {'show_time': '12:00'}
  };
  bool failRoomRequest = false;
  dynamic encryptionResponse = _encryptionResponse(DateTime.now());
  dynamic Function(RequestOptions)? encryptionResponder;
  Future<void> Function(RequestOptions)? beforeEncryptionResponse;
  dynamic Function(RequestOptions)? playbackResponder;
  Future<void> Function(RequestOptions)? beforePlaybackResponse;
  Map<String, List<String>> safeAuthHeaders = const {};
  bool failSafeAuthRequest = false;
  Completer<void>? safeAuthGate;
  Completer<void>? safeAuthStarted;
  final requests = <RequestOptions>[];

  List<Uri> get requestedUris =>
      requests.map((request) => request.uri).toList();

  List<RequestOptions> get encryptionRequests => requests
      .where((request) => request.uri.path.endsWith('/getEncryption'))
      .toList();

  List<RequestOptions> get playbackRequests => requests
      .where(
          (request) => request.uri.path.startsWith('/lapi/live/getH5PlayV1/'))
      .toList();

  List<RequestOptions> get safeAuthRequests => requests
      .where((request) => request.uri.path.endsWith('/safeAuth'))
      .toList();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (options.uri.host == 'www.douyu.com' &&
        options.uri.path == '/wgapi/livenc/liveweb/websec/getEncryption') {
      unawaited(_resolveEncryption(options, handler));
      return;
    }
    if (options.uri.host == 'passport.douyu.com' &&
        options.uri.path == '/lapi/passport/iframe/safeAuth') {
      unawaited(_resolveSafeAuth(options, handler));
      return;
    }
    if (options.uri.host == 'www.douyu.com' &&
        options.uri.path.startsWith('/lapi/live/getH5PlayV1/')) {
      unawaited(_resolvePlayback(options, handler));
      return;
    }
    if (options.uri.host == 'www.douyu.com' &&
        (options.uri.path == '/betard/$_roomId' ||
            options.uri.path == '/betard/$_aliasRoomId')) {
      if (failRoomRequest) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ));
      } else {
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: roomResponse,
        ));
      }
      return;
    }
    if (options.uri.host == 'www.douyu.com' &&
        options.uri.path == '/swf_api/h5room/$_roomId') {
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: h5Response,
      ));
      return;
    }
    handler.reject(DioException(
      requestOptions: options,
      type: DioExceptionType.unknown,
      error: StateError('Unexpected Douyu request: ${options.uri}'),
    ));
  }

  Future<void> _resolveEncryption(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await beforeEncryptionResponse?.call(options);
    handler.resolve(_ok(
      options,
      encryptionResponder?.call(options) ?? encryptionResponse,
    ));
  }

  Future<void> _resolveSafeAuth(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (safeAuthStarted != null && !safeAuthStarted!.isCompleted) {
      safeAuthStarted!.complete();
    }
    await safeAuthGate?.future;
    if (failSafeAuthRequest) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ));
      return;
    }
    handler.resolve(_ok(options, {'error': 0}, headers: safeAuthHeaders));
  }

  Future<void> _resolvePlayback(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await beforePlaybackResponse?.call(options);
    handler.resolve(_ok(
      options,
      playbackResponder?.call(options) ??
          {
            'error': 0,
            'data': {
              'rtmp_url': 'https://media.example/live',
              'rtmp_live': 'default.flv',
              'multirates': [
                {'rate': 2, 'name': '高清'},
                {'rate': 1, 'name': '流畅'},
              ],
            },
          },
    ));
  }
}

void main() {
  setUpAll(() => CoreLog.requestLogType = RequestLogType.none);

  group('Douyu playback signing and sessions', () {
    late DateTime now;
    late _DouyuRoomInterceptor interceptor;
    late DouyuSite site;

    setUp(() {
      now = DateTime.utc(2026, 10, 14, 12);
      interceptor = _DouyuRoomInterceptor()
        ..encryptionResponse = _encryptionResponse(now);
      HttpClient.instance.dio.interceptors.add(interceptor);
      site = DouyuSite(clock: () => now);
    });

    tearDown(() => HttpClient.instance.dio.interceptors.remove(interceptor));

    test('uses pure MD5 signing for special and ordinary keys', () async {
      for (final isSpecial in [false, true]) {
        for (final encTime in [1, 3]) {
          interceptor.requests.clear();
          interceptor.encryptionResponse = _encryptionResponse(
            now,
            isSpecial: isSpecial,
            encTime: encTime,
          );
          final localSite = DouyuSite(clock: () => now);

          final qualities = await localSite.getPlayQualites(detail: _detail());

          expect(qualities.map((quality) => quality.quality), ['高清', '流畅']);
          expect(
            qualities.map((quality) => (quality.data as DouyuPlayData).rate),
            [2, 1],
          );
          final encryptionRequest = interceptor.encryptionRequests.single;
          expect(encryptionRequest.uri.queryParameters['did'],
              '10000000000000000000000000001501');
          expect(encryptionRequest.headers['origin'], 'https://www.douyu.com');
          expect(
            encryptionRequest.headers['referer'],
            'https://www.douyu.com/$_roomId',
          );
          expect(encryptionRequest.headers['cookie'],
              'dy_did=10000000000000000000000000001501; acf_did=10000000000000000000000000001501');

          final playRequest = interceptor.playbackRequests.single;
          expect(playRequest.uri.path, '/lapi/live/getH5PlayV1/$_roomId');
          expect(playRequest.method, 'POST');
          final body = Uri.splitQueryString(playRequest.data as String);
          final timestamp = (now.millisecondsSinceEpoch ~/ 1000).toString();
          var secret = 'random-seed';
          for (var i = 0; i < encTime; i++) {
            secret = _md5('${secret}key-secret');
          }
          final salt = isSpecial ? '' : '$_roomId$timestamp';
          expect(body['auth'], _md5('${secret}key-secret$salt'));
          expect(body['enc_data'], 'enc+data/with=reserved');
          expect(body['tt'], timestamp);
          expect(body['did'], '10000000000000000000000000001501');
          expect(body['cdn'], '');
          expect(body['rate'], '-1');
          expect(body['ver'], 'Douyu_new');
          expect(body['hevc'], '0');
          expect(body['ive'], '0');
          expect(body['fa'], '0');
          expect(playRequest.headers['origin'], 'https://www.douyu.com');
          expect(
              playRequest.headers['referer'], 'https://www.douyu.com/$_roomId');
          expect(playRequest.headers['cookie'],
              'dy_did=10000000000000000000000000001501; acf_did=10000000000000000000000000001501');
        }
      }
    });

    test('accepts authenticated encryption descriptors with 1000 rounds',
        () async {
      site.cookie =
          'dy_did=authenticated-device; acf_uid=17; acf_jwt_token=${_jwt(now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000)}';
      interceptor.encryptionResponse = _encryptionResponse(
        now,
        encTime: 1000,
        isSpecial: true,
      );

      final qualities = await site.getPlayQualites(detail: _detail());

      expect(qualities.map((quality) => quality.quality), ['高清', '流畅']);
      final encryptionRequest = interceptor.encryptionRequests.single;
      expect(encryptionRequest.uri.queryParameters['did'], 'authenticated-device');
      expect(encryptionRequest.headers['cookie'], contains('acf_uid=17'));

      final playRequest = interceptor.playbackRequests.single;
      final body = Uri.splitQueryString(playRequest.data as String);
      var secret = 'random-seed';
      for (var i = 0; i < 1000; i++) {
        secret = _md5('${secret}key-secret');
      }
      final timestamp = (now.millisecondsSinceEpoch ~/ 1000).toString();
      expect(body['auth'], _md5('${secret}key-secret'));
      expect(body['tt'], timestamp);
      expect(body['did'], 'authenticated-device');
    });

    test('keeps user cookie fields and chooses dy_did before acf_did',
        () async {
      site.cookie = 'acf_uid=17; acf_did=secondary; dy_did=preferred';

      await site.getPlayQualites(detail: _detail());

      final encryptionRequest = interceptor.encryptionRequests.single;
      expect(encryptionRequest.uri.queryParameters['did'], 'preferred');
      expect(encryptionRequest.headers['cookie'],
          'acf_uid=17; acf_did=secondary; dy_did=preferred');
      expect(interceptor.playbackRequests.single.headers['cookie'],
          'acf_uid=17; acf_did=secondary; dy_did=preferred');
    });

    test('shares encryption fetches and expires cache at the earlier deadline',
        () async {
      interceptor.encryptionResponder = (_) => _encryptionResponse(
            now,
            serverTtl: const Duration(seconds: 45),
          );
      final started = Completer<void>();
      final gate = Completer<void>();
      interceptor.beforeEncryptionResponse = (_) async {
        if (!started.isCompleted) started.complete();
        await gate.future;
      };

      final first = site.getPlayQualites(detail: _detail());
      final second = site.getPlayQualites(detail: _detail());
      await started.future;
      gate.complete();
      await Future.wait([first, second]);
      expect(interceptor.encryptionRequests, hasLength(1));

      interceptor.beforeEncryptionResponse = null;
      now = now.add(const Duration(seconds: 46));
      await site.getPlayQualites(detail: _detail());
      expect(interceptor.encryptionRequests, hasLength(2));

      now = now.add(const Duration(minutes: 5, seconds: 1));
      await site.getPlayQualites(detail: _detail());
      expect(interceptor.encryptionRequests, hasLength(3));
    });

    test('cookie changes cancel old in-flight encryption and clear its cache',
        () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      interceptor.beforeEncryptionResponse = (_) async {
        if (!started.isCompleted) started.complete();
        await gate.future;
      };

      final oldRequest = site.getPlayQualites(detail: _detail());
      await started.future;
      site.cookie = 'acf_uid=changed';
      gate.complete();
      await expectLater(oldRequest, throwsA(isA<CoreCancelledError>()));

      interceptor.beforeEncryptionResponse = null;
      await site.getPlayQualites(detail: _detail());
      expect(interceptor.encryptionRequests, hasLength(2));
    });

    test('rejects server errors and invalid encryption parameters', () async {
      for (final response in [
        {'error': 100, 'data': _encryptionResponse(now)['data']},
        for (final encTime in [0, -1, 4097])
          {
            'error': 0,
            'data': {
              ...(_encryptionResponse(now)['data'] as Map),
              'enc_time': encTime,
            },
          },
        for (final expiry in [-1, 0, 8640000000001])
          {
            'error': 0,
            'data': {
              ...(_encryptionResponse(now)['data'] as Map),
              'expire_at': expiry,
            },
          },
      ]) {
        interceptor.encryptionResponse = response;
        await expectLater(
          DouyuSite(clock: () => now).getPlayQualites(detail: _detail()),
          throwsA(isA<CoreError>().having(
            (error) => error.kind,
            'kind',
            CoreErrorKind.response,
          )),
        );
      }

      interceptor.encryptionResponse = _encryptionResponse(now);
      interceptor.playbackResponder = (_) => {'error': 100, 'data': {}};
      await expectLater(
        site.getPlayQualites(detail: _detail()),
        throwsA(isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.response,
        )),
      );
    });

    test('safeAuth merges multiple headers and preserves Expires commas',
        () async {
      final oldJwt = _jwt(
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      final saved = <String>[];
      site.onCookieRefreshed = (cookie) async => saved.add(cookie);
      site.cookie =
          'dy_did=device; LTP0=secret; acf_jwt_token=$oldJwt; remove=old';
      interceptor.safeAuthHeaders = {
        'set-cookie': [
          'acf_jwt_token=$newJwt; Expires=Thu, 15 Oct 2026 12:00:00 GMT; Path=/',
          'acf_uid=42; Path=/',
          'remove=; Max-Age=0; Path=/',
        ],
      };

      await site.getPlayQualites(detail: _detail());

      expect(saved, hasLength(1));
      expect(site.cookie, contains('acf_jwt_token=$newJwt'));
      expect(site.cookie, contains('acf_uid=42'));
      expect(site.cookie, isNot(contains('remove=')));
      expect(interceptor.encryptionRequests.single.headers['cookie'],
          contains('acf_jwt_token=$newJwt'));
      expect(
          interceptor.requests
              .where((request) => request.uri.path.endsWith('/safeAuth')),
          hasLength(1));
    });

    test('returns unchanged for an empty cookie or a JWT outside the window',
        () async {
      expect(
        await site.refreshCookieIfNeeded(),
        DouyuCookieRefreshResult.unchanged,
      );
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=${_jwt(now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000)}';

      expect(
        await site.refreshCookieIfNeeded(),
        DouyuCookieRefreshResult.unchanged,
      );
      expect(interceptor.safeAuthRequests, isEmpty);
    });

    test('refreshes inside the requested early window', () async {
      final oldJwt = _jwt(
          now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie = 'dy_did=device; LTP0=refresh-key; acf_jwt_token=$oldJwt';
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };

      expect(
        await site.refreshCookieIfNeeded(
          refreshAhead: const Duration(minutes: 10),
          proactive: true,
        ),
        DouyuCookieRefreshResult.refreshed,
      );
      expect(site.cookie, contains('acf_jwt_token=$newJwt'));
      expect(interceptor.safeAuthRequests, hasLength(1));
    });

    test('reports missing refresh credentials without making a request',
        () async {
      final expiredJwt = _jwt(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000);
      site.cookie = 'acf_jwt_token=$expiredJwt';

      expect(
        await site.refreshCookieIfNeeded(),
        DouyuCookieRefreshResult.missingCredentials,
      );
      expect(interceptor.safeAuthRequests, isEmpty);
    });

    test('deduplicates concurrent refreshes and notifies once', () async {
      final expiredJwt = _jwt(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=$expiredJwt';
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };
      final started = Completer<void>();
      final gate = Completer<void>();
      interceptor.safeAuthStarted = started;
      interceptor.safeAuthGate = gate;
      final saved = <String>[];
      site.onCookieRefreshed = (cookie) async => saved.add(cookie);

      final first = site.refreshCookieIfNeeded();
      await started.future;
      final second = site.refreshCookieIfNeeded();
      gate.complete();

      expect(await Future.wait([first, second]), [
        DouyuCookieRefreshResult.refreshed,
        DouyuCookieRefreshResult.refreshed,
      ]);
      expect(interceptor.safeAuthRequests, hasLength(1));
      expect(saved, hasLength(1));
    });

    test('returns failed during cooldown and retries after sixty seconds',
        () async {
      final expiredJwt = _jwt(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=$expiredJwt';
      interceptor.failSafeAuthRequest = true;

      expect(
        await site.refreshCookieIfNeeded(),
        DouyuCookieRefreshResult.failed,
      );
      expect(
        await site.refreshCookieIfNeeded(),
        DouyuCookieRefreshResult.failed,
      );
      expect(interceptor.safeAuthRequests, hasLength(1));

      now = now.add(const Duration(seconds: 61));
      interceptor.failSafeAuthRequest = false;
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };
      expect(
        await site.refreshCookieIfNeeded(),
        DouyuCookieRefreshResult.refreshed,
      );
      expect(interceptor.safeAuthRequests, hasLength(2));
    });

    test('rejects missing and expired JWT Set-Cookie values', () async {
      final expiredJwt = _jwt(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000);
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=$expiredJwt';

      expect(
        await site.refreshCookieIfNeeded(),
        DouyuCookieRefreshResult.failed,
      );
      expect(site.cookie, contains('acf_jwt_token=$expiredJwt'));

      now = now.add(const Duration(seconds: 61));
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$expiredJwt; Path=/'],
      };
      expect(
        await site.refreshCookieIfNeeded(),
        DouyuCookieRefreshResult.failed,
      );
      expect(site.cookie, contains('acf_jwt_token=$expiredJwt'));
      expect(interceptor.safeAuthRequests, hasLength(2));
    });

    test('clearing the cookie cancels a pending explicit refresh', () async {
      final expiredJwt = _jwt(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=$expiredJwt';
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };
      final started = Completer<void>();
      final gate = Completer<void>();
      interceptor.safeAuthStarted = started;
      interceptor.safeAuthGate = gate;

      final pending = site.refreshCookieIfNeeded();
      await started.future;
      site.cookie = '';
      gate.complete();

      await expectLater(pending, throwsA(isA<CoreCancelledError>()));
      expect(site.cookie, isEmpty);
    });

    test('proactive refresh defers while a playback request is active',
        () async {
      final expiringJwt = _jwt(
          now.add(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000);
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=$expiringJwt';
      final started = Completer<void>();
      final gate = Completer<void>();
      interceptor.beforeEncryptionResponse = (_) async {
        if (!started.isCompleted) started.complete();
        await gate.future;
      };

      final playback = site.getPlayQualites(detail: _detail());
      await started.future;
      expect(
        await site.refreshCookieIfNeeded(
          refreshAhead: const Duration(minutes: 2),
          proactive: true,
        ),
        DouyuCookieRefreshResult.deferred,
      );
      expect(interceptor.safeAuthRequests, isEmpty);

      gate.complete();
      await playback;
    });

    test('new playback waits for proactive refresh before taking a snapshot',
        () async {
      final expiringJwt = _jwt(
          now.add(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=$expiringJwt';
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };
      final started = Completer<void>();
      final gate = Completer<void>();
      interceptor.safeAuthStarted = started;
      interceptor.safeAuthGate = gate;

      final refresh = site.refreshCookieIfNeeded(
        refreshAhead: const Duration(minutes: 2),
        proactive: true,
      );
      await started.future;
      final playback = site.getPlayQualites(detail: _detail());
      expect(interceptor.encryptionRequests, isEmpty);

      gate.complete();
      expect(await refresh, DouyuCookieRefreshResult.refreshed);
      await playback;

      expect(interceptor.encryptionRequests, hasLength(1));
      expect(interceptor.encryptionRequests.single.headers['cookie'],
          contains('acf_jwt_token=$newJwt'));
    });

    test('proactive check joins a refresh already started by playback',
        () async {
      final expiredJwt = _jwt(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=$expiredJwt';
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };
      final started = Completer<void>();
      final gate = Completer<void>();
      interceptor.safeAuthStarted = started;
      interceptor.safeAuthGate = gate;

      final playback = site.getPlayQualites(detail: _detail());
      await started.future;
      final proactive = site.refreshCookieIfNeeded(proactive: true);
      gate.complete();

      expect(await proactive, DouyuCookieRefreshResult.refreshed);
      await playback;
      expect(interceptor.safeAuthRequests, hasLength(1));
      expect(interceptor.encryptionRequests.single.headers['cookie'],
          contains('acf_jwt_token=$newJwt'));
    });

    test('playback waits until refreshed cookie callback completes', () async {
      final expiredJwt = _jwt(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie =
          'dy_did=device; LTP0=refresh-key; acf_jwt_token=$expiredJwt';
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };
      final callbackStarted = Completer<void>();
      final callbackGate = Completer<void>();
      site.onCookieRefreshed = (_) async {
        callbackStarted.complete();
        await callbackGate.future;
      };

      final refresh = site.refreshCookieIfNeeded();
      await callbackStarted.future;
      final playback = site.getPlayQualites(detail: _detail());
      await Future<void>.delayed(Duration.zero);
      expect(interceptor.encryptionRequests, isEmpty);

      callbackGate.complete();
      expect(await refresh, DouyuCookieRefreshResult.refreshed);
      await playback;
      expect(interceptor.encryptionRequests.single.headers['cookie'],
          contains('acf_jwt_token=$newJwt'));
    });

    test('manual replacement during refresh callback cancels waiting playback',
        () async {
      final expiredJwt = _jwt(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie = 'dy_did=old; LTP0=old; acf_jwt_token=$expiredJwt';
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };
      final callbackStarted = Completer<void>();
      final callbackGate = Completer<void>();
      site.onCookieRefreshed = (_) async {
        callbackStarted.complete();
        await callbackGate.future;
      };

      final refresh = site.refreshCookieIfNeeded();
      await callbackStarted.future;
      final playback = site.getPlayQualites(detail: _detail());
      final refreshCancelled =
          expectLater(refresh, throwsA(isA<CoreCancelledError>()));
      final playbackCancelled =
          expectLater(playback, throwsA(isA<CoreCancelledError>()));

      site.cookie = 'dy_did=new; acf_jwt_token=$newJwt';
      callbackGate.complete();
      await Future.wait([refreshCancelled, playbackCancelled]);
      expect(site.cookie, 'dy_did=new; acf_jwt_token=$newJwt');
      expect(interceptor.encryptionRequests, isEmpty);
    });

    test('manual account replacement cancels pending safeAuth refresh',
        () async {
      final oldJwt = _jwt(
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000);
      final newJwt = _jwt(
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000);
      site.cookie = 'dy_did=old; LTP0=old; acf_jwt_token=$oldJwt';
      final started = Completer<void>();
      final gate = Completer<void>();
      interceptor.safeAuthStarted = started;
      interceptor.safeAuthGate = gate;
      interceptor.safeAuthHeaders = {
        'set-cookie': ['acf_jwt_token=$newJwt; Path=/'],
      };

      final oldRequest = site.getPlayQualites(detail: _detail());
      await started.future;
      site.cookie = 'dy_did=new; acf_jwt_token=$newJwt';
      gate.complete();
      await expectLater(oldRequest, throwsA(isA<CoreCancelledError>()));
      expect(site.cookie, 'dy_did=new; acf_jwt_token=$newJwt');
      expect(interceptor.encryptionRequests, isEmpty);

      await site.getPlayQualites(detail: _detail());
      expect(interceptor.encryptionRequests.single.uri.queryParameters['did'],
          'new');
    });

    test('uses new V1 endpoint and keeps room detail free of signer data',
        () async {
      interceptor.roomResponse = {
        'room': _room(showStatus: 1, videoLoop: 0),
      };

      final detail = await site.getRoomDetail(roomId: _roomId);
      await site.getPlayQualites(detail: detail);

      expect(detail.data, '');
      expect(
        interceptor.requestedUris.any(
          (uri) => uri.path == '/swf_api/homeH5Enc',
        ),
        isFalse,
      );
      expect(
        interceptor.playbackRequests.every(
          (request) => request.uri.path.startsWith('/lapi/live/getH5PlayV1/'),
        ),
        isTrue,
      );
    });

    test('supports parallel CDN requests, stable order, and per-line failure',
        () async {
      interceptor.beforePlaybackResponse = (request) async {
        final parameters = Uri.splitQueryString(request.data as String);
        if (parameters['cdn'] == 'slow') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      };
      interceptor.playbackResponder = (request) {
        final parameters = Uri.splitQueryString(request.data as String);
        final cdn = parameters['cdn']!;
        if (cdn.isEmpty) {
          return {
            'error': 0,
            'data': {
              'cdnsWithName': [
                {'cdn': 'fast'},
                {'cdn': 'broken'},
                {'cdn': 'slow'},
              ],
              'multirates': [
                {'rate': 2, 'name': '高清'},
                {'rate': 1, 'name': '流畅'},
              ],
            },
          };
        }
        if (cdn == 'broken') {
          return {
            'error': 0,
            'data': {
              'multirates': [
                {'rate': 2, 'name': '高清'},
              ],
            },
          };
        }
        return {
          'error': 0,
          'data': {
            'rtmp_url': 'https://media.example/$cdn/',
            'rtmp_live': '$cdn&amp;source.flv',
            'rate': 2,
            'multirates': [
              {'rate': 2, 'name': '高清'},
              {'rate': 1, 'name': '流畅'},
            ],
          },
        };
      };

      final qualities = await site.getPlayQualites(detail: _detail());
      final result = await site.getPlayUrls(
        detail: _detail(),
        quality: qualities.first,
      );

      expect(result.urls, [
        'https://media.example/fast/fast&source.flv',
        'https://media.example/slow/slow&source.flv',
      ]);
      expect(result.actualQuality?.quality, '高清');
      expect(result.actualQuality?.data, isA<DouyuPlayData>());
      expect(result.headers, isNull);
    });

    test('rate 0 response at 4 never claims original from multirates',
        () async {
      final attemptedRates = <int>[];
      interceptor.playbackResponder = (request) {
        final parameters = Uri.splitQueryString(request.data as String);
        final rate = int.parse(parameters['rate']!);
        attemptedRates.add(rate);
        return {
          'error': 0,
          'data': {
            'rtmp_url': 'https://media.example/fallback',
            'rtmp_live': 'fallback.flv',
            'rate': 4,
            'multirates': [
              {'rate': 0, 'name': '原画'},
              {'rate': 4, 'name': '蓝光4M'},
              {'rate': 2, 'name': '高清'},
            ],
          },
        };
      };

      final result = await site.getPlayUrls(
        detail: _detail(),
        quality: LivePlayQuality(
          quality: '原画',
          data: DouyuPlayData(0, ['cdn-a']),
        ),
      );

      expect(result.urls, ['https://media.example/fallback/fallback.flv']);
      expect(result.actualQuality?.quality, '蓝光4M');
      expect((result.actualQuality?.data as DouyuPlayData).rate, 4);
      expect(attemptedRates, [0]);
    });

    test('keeps only requested original CDN when other lines downgrade',
        () async {
      interceptor.playbackResponder = (request) {
        final body = Uri.splitQueryString(request.data as String);
        final cdn = body['cdn']!;
        return {
          'error': 0,
          'data': {
            'rtmp_url': 'https://media.example/$cdn',
            'rtmp_live': '$cdn.flv',
            'rate': cdn == 'original' ? 0 : 4,
            'multirates': [
              {'rate': 0, 'name': '原画'},
              {'rate': 4, 'name': '蓝光4M'},
              {'rate': 2, 'name': '蓝光2M'},
            ],
          },
        };
      };

      final result = await site.getPlayUrls(
        detail: _detail(),
        quality: LivePlayQuality(
          quality: '原画',
          data: DouyuPlayData(0, ['lower', 'original', 'lower2']),
        ),
      );

      expect(result.urls, ['https://media.example/original/original.flv']);
      expect(result.actualQuality?.quality, '原画');
      expect(interceptor.playbackRequests, hasLength(3));
      expect(
          interceptor.playbackRequests.map((request) =>
              Uri.splitQueryString(request.data as String)['rate']),
          everyElement('0'));
    });

    test('chooses highest returned fallback and preserves matching CDN order',
        () async {
      interceptor.playbackResponder = (request) {
        final cdn = Uri.splitQueryString(request.data as String)['cdn']!;
        final rate = cdn == 'two' ? 2 : 4;
        return {
          'error': 0,
          'data': {
            'rtmp_url': 'https://media.example/$cdn',
            'rtmp_live': '$cdn.flv',
            'rate': rate,
            'multirates': [
              {'rate': 0, 'name': '原画'},
              {'rate': 4, 'name': '蓝光4M'},
              {'rate': 2, 'name': '蓝光2M'},
            ],
          },
        };
      };

      final result = await site.getPlayUrls(
        detail: _detail(),
        quality: LivePlayQuality(
          quality: '原画',
          data: DouyuPlayData(0, ['four-a', 'two', 'four-b']),
        ),
      );

      expect(result.urls, [
        'https://media.example/four-a/four-a.flv',
        'https://media.example/four-b/four-b.flv',
      ]);
      expect(result.actualQuality?.quality, '蓝光4M');
      expect((result.actualQuality?.data as DouyuPlayData).rate, 4);
      expect(interceptor.playbackRequests, hasLength(3));
    });

    test('marks playable URLs unknown when server rate cannot be confirmed',
        () async {
      interceptor.playbackResponder = (request) {
        final parameters = Uri.splitQueryString(request.data as String);
        final rate = int.parse(parameters['rate']!);
        if (rate == 9) {
          return {
            'error': 0,
            'data': {
              'rtmp_url': 'https://media.example/unknown',
              'rtmp_live': 'unknown.flv',
              'multirates': [
                {'rate': 3, 'name': '原画'},
              ],
            },
          };
        }
        return {'error': 0, 'data': <String, dynamic>{}};
      };

      final result = await site.getPlayUrls(
        detail: _detail(),
        quality: LivePlayQuality(
          quality: 'requested',
          data: DouyuPlayData(9, ['cdn-a']),
        ),
      );

      expect(result.urls, ['https://media.example/unknown/unknown.flv']);
      expect(result.actualQuality?.quality, '清晰度未确认');
      expect(result.actualQuality?.data, isNull);
    });
  });

  group('Douyu room status', () {
    late _DouyuRoomInterceptor interceptor;
    late DouyuSite site;

    setUp(() {
      interceptor = _DouyuRoomInterceptor();
      HttpClient.instance.dio.interceptors.add(interceptor);
      site = DouyuSite();
    });

    tearDown(() => HttpClient.instance.dio.interceptors.remove(interceptor));

    test('integer and numeric-string live flags share the same state parser',
        () async {
      for (final room in [
        _room(showStatus: 1, videoLoop: 0),
        _room(showStatus: '1', videoLoop: '0'),
      ]) {
        interceptor.roomResponse = {'room': room};

        expect(await site.getLiveStatusState(roomId: _roomId),
            LiveStatusState.live);
        expect(await site.getLiveStatus(roomId: _roomId), isTrue);
      }
    });

    test('detail and status agree for an explicitly offline room', () async {
      interceptor.roomResponse = {
        'room': _room(showStatus: '2', videoLoop: '0'),
      };

      final state = await site.getLiveStatusState(roomId: _roomId);
      final detail = await site.getRoomDetail(roomId: _roomId);

      expect(state, LiveStatusState.offline);
      expect(await site.getLiveStatus(roomId: _roomId), isFalse);
      expect(detail.liveStatusState, state);
      expect(detail.status, isFalse);
      expect(detail.isRecord, isFalse);
      expect(
        interceptor.requestedUris
            .any((uri) => uri.path == '/swf_api/homeH5Enc'),
        isFalse,
      );
    });

    test('recordings are playable live state but keep the legacy bool false',
        () async {
      interceptor.roomResponse = {
        'room': _room(showStatus: '2', videoLoop: '1'),
      };

      expect(
          await site.getLiveStatusState(roomId: _roomId), LiveStatusState.live);
      expect(await site.getLiveStatus(roomId: _roomId), isFalse);
    });

    test('missing or unknown flags stay unknown and bool status throws',
        () async {
      for (final room in [
        _room(),
        _room(showStatus: 2),
        _room(showStatus: 2, videoLoop: 7),
        _room(showStatus: 9, videoLoop: 0),
      ]) {
        interceptor.roomResponse = {'room': room};

        expect(await site.getLiveStatusState(roomId: _roomId),
            LiveStatusState.unknown);
        await expectLater(
          site.getLiveStatus(roomId: _roomId),
          throwsA(isA<CoreError>().having(
            (error) => error.kind,
            'kind',
            CoreErrorKind.response,
          )),
        );
      }
    });

    test('unknown state is carried by room detail rather than marked offline',
        () async {
      interceptor.roomResponse = {'room': _room(showStatus: 2)};

      final detail = await site.getRoomDetail(roomId: _roomId);

      expect(detail.liveStatusState, LiveStatusState.unknown);
      expect(detail.resolvedLiveStatus, LiveStatusState.unknown);
      expect(detail.status, isFalse);
      expect(
        interceptor.requestedUris
            .any((uri) => uri.path == '/swf_api/homeH5Enc'),
        isFalse,
      );
    });

    test('numeric alias resolves to the canonical room ID', () async {
      final state = await site.getLiveStatusState(roomId: _aliasRoomId);
      final detail = await site.getRoomDetail(roomId: _aliasRoomId);

      expect(state, LiveStatusState.offline);
      expect(detail.roomId, _roomId);
      expect(detail.danmakuData, _roomId);
      expect(detail.liveStatusState, state);
      expect(
        interceptor.requestedUris.map((uri) => uri.path),
        containsAll(['/betard/$_aliasRoomId', '/swf_api/h5room/$_roomId']),
      );
    });

    test('live alias keeps the canonical room ID without signer request',
        () async {
      interceptor.roomResponse = {
        'room': _room(showStatus: 1, videoLoop: 0),
      };

      final detail = await site.getRoomDetail(roomId: _aliasRoomId);
      expect(detail.roomId, _roomId);
      expect(
        interceptor.requestedUris
            .any((uri) => uri.path == '/swf_api/homeH5Enc'),
        isFalse,
      );
    });

    test('malformed room payload and invalid IDs throw CoreError', () async {
      for (final response in <dynamic>[
        'not json',
        <String, dynamic>{},
        {'room': <dynamic>[]},
        {
          'room': _room(showStatus: 1, videoLoop: 0)..remove('room_id'),
        },
        for (final invalidId in [null, 0, '0', '', -2, 'abc'])
          {
            'room': _room(showStatus: 1, videoLoop: 0)..['room_id'] = invalidId,
          },
      ]) {
        interceptor.roomResponse = response;

        await expectLater(
          site.getLiveStatusState(roomId: _roomId),
          throwsA(isA<CoreError>().having(
            (error) => error.kind,
            'kind',
            CoreErrorKind.response,
          )),
        );
      }
    });

    test('malformed detail response stays CoreError', () async {
      interceptor.h5Response = {'data': []};
      await expectLater(
        site.getRoomDetail(roomId: _roomId),
        throwsA(isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.response,
        )),
      );
    });

    test('network failures stay CoreError instead of becoming offline',
        () async {
      interceptor.failRoomRequest = true;

      await expectLater(
        site.getLiveStatus(roomId: _roomId),
        throwsA(isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.network,
        )),
      );
    });
  });
}
