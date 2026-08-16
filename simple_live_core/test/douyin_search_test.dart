import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/scripts/douyin_sign.dart';
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

    final result = await _testSite().searchAnchors('anchor');

    expect(result.metadata.origin, SearchOrigin.derived);
    expect(result.metadata.continuation, SearchContinuation.done);
    expect(result.hasMore, isFalse);
    expect(
        result.metadata.fieldSources['avatar'], SearchFieldSource.unavailable);
    expect(
        result.metadata.fieldSources['liveStatus'], SearchFieldSource.derived);
    expect(result.items, hasLength(1));
    expect(result.items.single.roomId, 'room-1');
    expect(result.items.single.userName, 'anchor');
    expect(result.items.single.avatar, isEmpty);
    expect(interceptor.requests, [
      _DouyinSearchInterceptor.headRequest,
      _DouyinSearchInterceptor.searchRequest,
    ]);
  });

  test('ranks matching anchors first and removes duplicate live rooms',
      () async {
    interceptor.respondToHead();
    interceptor.respondToSearchWith(
      _searchResponse(
        rooms: [
          _searchRoom('room-1', 'other', online: 100),
          _searchRoom('room-2', 'target anchor', online: 20),
          _searchRoom('room-2', 'target anchor', online: 20),
        ],
      ),
    );

    final result = await _testSite().searchAnchors('target');

    expect(result.items.map((item) => item.roomId), ['room-2', 'room-1']);
  });

  group('search authentication failure', () {
    final cases = <String, (String, DouyinSearchAuthFailureReason)>{
      'missing cookie': ('', DouyinSearchAuthFailureReason.missingCookie),
      'ttwid with a trailing semicolon': (
        'ttwid=user-ttwid;',
        DouyinSearchAuthFailureReason.onlyTtwid,
      ),
      'cookie without a login session': (
        'ttwid=user-ttwid; __ac_nonce=nonce',
        DouyinSearchAuthFailureReason.incompleteCookie,
      ),
      'expired cookie': (
        'sessionid=session; sid_guard=hash%7C0%7C1',
        DouyinSearchAuthFailureReason.expired,
      ),
      'configured cookie rejected by Douyin': (
        'sessionid=session',
        DouyinSearchAuthFailureReason.rejected,
      ),
    };

    for (final entry in cases.entries) {
      test('classifies ${entry.key}', () async {
        interceptor.respondToHead();
        interceptor.respondToSearchWith({'status_code': 2483});
        final site = _testSite()..cookie = entry.value.$1;

        final error = await _captureAuthError(site);

        expect(error.reason, entry.value.$2);
        expect(error.kind, CoreErrorKind.search);
        expect(error.message, isNot(contains('user-ttwid')));
        expect(error.message, isNot(contains('sessionid=session')));
      });
    }
  });

  test('keeps non-2483 search failures generic', () async {
    interceptor.respondToHead();
    interceptor.respondToSearchWith({'status_code': 1});

    await expectLater(
      _testSite().searchRooms('restricted'),
      throwsA(
        isA<CoreError>()
            .having((error) => error.kind, 'kind', CoreErrorKind.search)
            .having(
              (error) => error.message,
              'message',
              '抖音直播搜索被限制，请稍后再试',
            )
            .having(
              (error) => error is DouyinSearchAuthError,
              'is auth error',
              isFalse,
            ),
      ),
    );
  });

  test('decodes a text response with a UTF-8 BOM', () async {
    interceptor.respondToSearchWithText(
      '\ufeff${jsonEncode(_searchResponse())}',
    );
    final site = _testSite()..cookie = 'sessionid=user-session';

    final result = await site.searchRooms('bom');

    expect(result.items, hasLength(1));
    expect(result.items.single.roomId, 'room-1');
  });

  test('classifies an HTML challenge instead of a network failure', () async {
    interceptor.respondToSearchWithText(
      '<!doctype html><html><script>window.__ac_nonce="nonce"</script></html>',
    );
    final site = _testSite()..cookie = 'sessionid=user-session';

    await expectLater(
      site.searchRooms('challenge'),
      throwsA(
        isA<CoreError>()
            .having((error) => error.kind, 'kind', CoreErrorKind.search)
            .having(
              (error) => error.message,
              'message',
              contains('验证页面'),
            ),
      ),
    );
  });

  test('signs the search URL after HEAD with the same user agent', () async {
    interceptor.respondToHead();
    interceptor.respondToSearchWith(_searchResponse());
    String? signerUserAgent;
    final site = DouyinSite(abogusSigner: (url, userAgent) {
      signerUserAgent = userAgent;
      return _signedSearchUrl(url, userAgent);
    });

    await site.searchRooms('signed');

    expect(signerUserAgent, DouyinSite.kSearchUserAgent);
    expect(interceptor.searchOptions?.uri.queryParameters['msToken'], 'token');
    expect(
      interceptor.searchOptions?.uri.queryParameters['a_bogus'],
      'signature',
    );
    expect(
      interceptor.searchOptions?.headers['user-agent'],
      signerUserAgent,
    );
    expect(
      interceptor.searchOptions?.uri.queryParameters['browser_name'],
      'Edge',
    );
    expect(
      interceptor.searchOptions?.uri.queryParameters['browser_version'],
      '125.0.0.0',
    );
  });

  test('uses a standalone live-search context', () async {
    interceptor.respondToSearchWith(_searchResponse());
    final site = _testSite()..cookie = 'sessionid=user-session';

    await site.searchRooms('standalone');

    final query = interceptor.searchOptions!.uri.queryParameters;
    expect(query['search_channel'], 'aweme_live');
    expect(query['search_source'], 'switch_tab');
    expect(query.containsKey('search_id'), isFalse);
    expect(query['from_group_id'], isEmpty);
    expect(query['need_filter_settings'], '1');
    expect(query['list_type'], 'single');
    expect(query['version_code'], '170400');
    expect(query['version_name'], '17.4.0');
  });

  test('a_bogus URL preparation preserves one browser msToken', () {
    final prepared = DouyinSign.prepareAbogusUri(
      'https://www.douyin.com/aweme/v1/web/live/search/'
      '?aid=6383&msToken=browser-session-token',
      generatedMsToken: 'unrelated-generated-token',
    );

    expect(prepared.queryParametersAll['msToken'], ['browser-session-token']);
  });

  test('a_bogus URL preparation adds a generated token when absent', () {
    final prepared = DouyinSign.prepareAbogusUri(
      'https://www.douyin.com/aweme/v1/web/live/search/?aid=6383',
      generatedMsToken: 'generated-token',
    );

    expect(prepared.queryParametersAll['msToken'], ['generated-token']);
  });

  test('reuses browser session tokens when signing configured Cookie search',
      () async {
    interceptor.respondToSearchWith(_searchResponse());
    String? unsignedUrl;
    final site = DouyinSite(abogusSigner: (url, userAgent) {
      unsignedUrl = url;
      return _signedSearchUrl(url, userAgent);
    })
      ..cookie = 'sessionid=user-session; ttwid=user-ttwid; '
          'msToken=browser-ms-token; tt_webid=7399999999999999999; '
          's_v_web_id=verify_browser_session';

    await site.searchRooms('session');

    final unsignedQuery = Uri.parse(unsignedUrl!).queryParameters;
    expect(unsignedQuery['msToken'], 'browser-ms-token');
    expect(unsignedQuery['webid'], '7399999999999999999');
    expect(unsignedQuery['verifyFp'], 'verify_browser_session');
    expect(unsignedQuery['fp'], 'verify_browser_session');
    expect(
      interceptor.searchOptions?.uri.queryParameters['msToken'],
      'browser-ms-token',
    );
    expect(
      interceptor.searchOptions?.headers['user-agent'],
      DouyinSite.kSearchUserAgent,
    );
    expect(
        interceptor.searchOptions?.headers['origin'], 'https://www.douyin.com');
  });

  test('uses a stable per-site fallback webid instead of the shared constant',
      () async {
    interceptor.respondToSearchWith(_searchResponse());
    final unsignedUrls = <String>[];
    final site = DouyinSite(abogusSigner: (url, userAgent) {
      unsignedUrls.add(url);
      return _signedSearchUrl(url, userAgent);
    })
      ..cookie = 'sessionid=user-session';

    await site.searchRooms('first');
    await site.searchRooms('second');

    final firstWebId = Uri.parse(unsignedUrls[0]).queryParameters['webid'];
    final secondWebId = Uri.parse(unsignedUrls[1]).queryParameters['webid'];
    expect(firstWebId, matches(RegExp(r'^7\d{18}$')));
    expect(secondWebId, firstWebId);
    expect(firstWebId, isNot('7382872326016435738'));
  });

  test('uses a configured Cookie without an anonymous HEAD preflight',
      () async {
    interceptor.respondToSearchWith(_searchResponse());
    final site = _testSite()
      ..cookie = 'ttwid=user-ttwid; sessionid=user-session; '
          '__ac_nonce=user-nonce; token=value=with=equals';

    await site.searchRooms('cookie');

    final cookie = interceptor.searchOptions?.headers['cookie'] as String;
    expect(_parseCookieHeader(cookie), {
      'ttwid': 'user-ttwid',
      'sessionid': 'user-session',
      '__ac_nonce': 'user-nonce',
      'token': 'value=with=equals',
    });
    expect(RegExp(r'(^|;\s*)ttwid=').allMatches(cookie), hasLength(1));
    expect(interceptor.requests, [
      _DouyinSearchInterceptor.searchRequest,
    ]);
  });

  test('normalizes a previously saved JSON Cookie before sending', () async {
    interceptor.respondToSearchWith(_searchResponse());
    final site = _testSite()
      ..cookie = '''{
  "cookie": "ttwid=user-ttwid; sessionid=user-session"
}''';

    await site.searchRooms('json-cookie');

    final cookie = _searchCookie(interceptor);
    expect(_parseCookieHeader(cookie), {
      'ttwid': 'user-ttwid',
      'sessionid': 'user-session',
    });
    expect(cookie, isNot(contains('{')));
    expect(cookie, isNot(contains('\n')));
    expect(interceptor.requests, [
      _DouyinSearchInterceptor.searchRequest,
    ]);
  });

  test('uses the response has_more flag instead of the first-page size',
      () async {
    interceptor.respondToSearchWith({
      ..._searchResponse(),
      'has_more': 1,
    });
    final site = _testSite()..cookie = 'sessionid=user-session';

    final result = await site.searchRooms('more');

    expect(result.items, hasLength(1));
    expect(result.hasMore, isTrue);
  });

  test('uses upstream compatibility only after a successful empty response',
      () async {
    interceptor.respondToHeadWithCookies([
      'ttwid=head-ttwid; Path=/',
      '__ac_nonce=head-nonce; Path=/',
    ]);
    interceptor.respondToSearchSequence([
      {'status_code': 0, 'data': [], 'has_more': 0},
      _searchResponse(),
    ]);
    final site = _testSite()
      ..cookie = 'sessionid=user-session; ttwid=user-ttwid';

    final result = await site.searchRooms('compatibility');

    expect(result.items, hasLength(1));
    expect(interceptor.requests, [
      _DouyinSearchInterceptor.searchRequest,
      _DouyinSearchInterceptor.headRequest,
      _DouyinSearchInterceptor.searchRequest,
    ]);
    final primary = interceptor.searchOptionsHistory[0];
    final fallback = interceptor.searchOptionsHistory[1];
    expect(primary.uri.queryParameters['a_bogus'], 'signature');
    expect(fallback.uri.queryParameters.containsKey('a_bogus'), isFalse);
    expect(fallback.uri.queryParameters.containsKey('msToken'), isFalse);
    expect(fallback.uri.queryParameters['webid'], '7382872326016435738');
    expect(fallback.uri.queryParameters.containsKey('list_type'), isFalse);
    expect(fallback.headers['user-agent'], DouyinSite.kDefaultUserAgent);
    expect(_parseCookieHeader(fallback.headers['cookie'] as String), {
      'sessionid': 'user-session',
      'ttwid': 'head-ttwid',
      '__ac_nonce': 'head-nonce',
    });
  });

  test('keeps a genuinely empty result when both strategies are empty',
      () async {
    interceptor.respondToHead();
    interceptor.respondToSearchSequence([
      {'status_code': 0, 'data': [], 'has_more': 0},
      {'status_code': 0, 'data': [], 'has_more': 0},
    ]);
    final site = _testSite()..cookie = 'sessionid=user-session';

    final result = await site.searchRooms('empty');

    expect(result.items, isEmpty);
    expect(interceptor.searchOptionsHistory, hasLength(2));
  });

  test('lets a HEAD ttwid replace the built-in default cookie', () async {
    interceptor.respondToHeadWithCookies([
      'ttwid=head-ttwid; Path=/',
      'foo_ttwid=must-not-be-copied; Path=/',
    ]);
    interceptor.respondToSearchWith(_searchResponse());

    await _testSite().searchRooms('default-cookie');

    expect(_parseCookieHeader(_searchCookie(interceptor)), {
      'ttwid': 'head-ttwid',
    });
  });

  test('continues to the signed GET when the cookie HEAD fails', () async {
    interceptor.failHead();
    interceptor.respondToSearchWith(_searchResponse());

    await _testSite().searchRooms('head-failure');

    expect(interceptor.requests, [
      _DouyinSearchInterceptor.headRequest,
      _DouyinSearchInterceptor.searchRequest,
    ]);
    expect(
      interceptor.searchOptions?.uri.queryParameters['a_bogus'],
      'signature',
    );
  });

  test('does not issue the GET when cancellation happens during signing',
      () async {
    interceptor.respondToHead();
    final cancellation = CoreCancellationToken();
    final site = DouyinSite(abogusSigner: (url, userAgent) {
      cancellation.cancel();
      return _signedSearchUrl(url, userAgent);
    });

    await expectLater(
      site.searchRooms('cancel-sign', cancellation: cancellation),
      throwsA(isA<CoreCancelledError>()),
    );

    expect(interceptor.requests, [_DouyinSearchInterceptor.headRequest]);
  });

  test('wraps signer failures as search errors without exposing details',
      () async {
    interceptor.respondToHead();
    final site = DouyinSite(abogusSigner: (url, userAgent) {
      throw StateError('secret-token');
    });

    await expectLater(
      site.searchRooms('sign-failure'),
      throwsA(
        isA<CoreError>()
            .having((error) => error.kind, 'kind', CoreErrorKind.search)
            .having(
              (error) => error.message,
              'message',
              '抖音直播搜索请求签名失败',
            )
            .having(
              (error) => error.message,
              'secret is not exposed',
              isNot(contains('secret-token')),
            ),
      ),
    );
  });
}

DouyinSite _testSite() => DouyinSite(abogusSigner: _signedSearchUrl);

String _signedSearchUrl(String url, String userAgent) {
  final uri = Uri.parse(url);
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    'msToken': uri.queryParameters['msToken'] ?? 'token',
    'a_bogus': 'signature',
  }).toString();
}

Future<DouyinSearchAuthError> _captureAuthError(DouyinSite site) async {
  try {
    await site.searchRooms('auth');
  } on DouyinSearchAuthError catch (error) {
    return error;
  }
  throw StateError('Expected a DouyinSearchAuthError');
}

String _searchCookie(_DouyinSearchInterceptor interceptor) {
  return interceptor.searchOptions?.headers['cookie'] as String;
}

Map<String, String> _parseCookieHeader(String cookie) {
  return {
    for (final part in cookie.split(';'))
      if (part.trim().contains('='))
        part.substring(0, part.indexOf('=')).trim():
            part.substring(part.indexOf('=') + 1).trim(),
  };
}

Map<String, dynamic> _searchResponse({List<Map<String, dynamic>>? rooms}) {
  return {
    'status_code': 0,
    'data': (rooms ?? [_searchRoom('room-1', 'anchor', online: 42)])
        .map(
          (room) => {
            'lives': {'rawdata': jsonEncode(room)},
          },
        )
        .toList(),
  };
}

Map<String, dynamic> _searchRoom(
  String roomId,
  String userName, {
  required int online,
}) {
  return {
    'owner': {'web_rid': roomId, 'nickname': userName},
    'title': 'A test room',
    'cover': {
      'url_list': ['https://example.invalid/cover.jpg'],
    },
    'stats': {'total_user': '$online'},
  };
}

class _DouyinSearchInterceptor extends Interceptor {
  static const headRequest = 'HEAD https://live.douyin.com';
  static const searchRequest =
      'GET https://www.douyin.com/aweme/v1/web/live/search/';

  final List<String> requests = [];
  bool _cancelHead = false;
  bool _failHead = false;
  List<String> _headCookies = const [];
  String? _searchResponse;
  final List<String> _searchResponseSequence = [];
  RequestOptions? searchOptions;
  final List<RequestOptions> searchOptionsHistory = [];

  void cancelHead() {
    _cancelHead = true;
  }

  void respondToHead() {
    _cancelHead = false;
    _failHead = false;
    _headCookies = const [];
  }

  void respondToHeadWithCookies(List<String> cookies) {
    respondToHead();
    _headCookies = cookies;
  }

  void failHead() {
    _cancelHead = false;
    _failHead = true;
  }

  void respondToSearchWith(Object response) {
    _searchResponse = jsonEncode(response);
    _searchResponseSequence.clear();
  }

  void respondToSearchWithText(String response) {
    _searchResponse = response;
    _searchResponseSequence.clear();
  }

  void respondToSearchSequence(List<Object> responses) {
    _searchResponse = null;
    _searchResponseSequence
      ..clear()
      ..addAll(responses.map(jsonEncode));
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
      } else if (_failHead) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        );
      } else {
        handler.resolve(Response<void>(
          requestOptions: options,
          statusCode: 200,
          headers: Headers.fromMap({'set-cookie': _headCookies}),
        ));
      }
      return;
    }

    if (request == searchRequest &&
        (_searchResponseSequence.isNotEmpty || _searchResponse != null)) {
      searchOptions = options;
      searchOptionsHistory.add(options);
      handler.resolve(Response<String>(
        requestOptions: options,
        statusCode: 200,
        data: _searchResponseSequence.isNotEmpty
            ? _searchResponseSequence.removeAt(0)
            : _searchResponse,
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
