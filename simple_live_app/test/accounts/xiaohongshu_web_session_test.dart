import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/xiaohongshu_desktop_web_session_host.dart';
import 'package:simple_live_app/services/xiaohongshu_desktop_webview_window_host.dart';
import 'package:simple_live_app/services/xiaohongshu_web_session_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  const room = '570493541297105186';
  Future<dynamic> request(XiaohongshuWebSessionService service) =>
      service.request(
          method: 'GET',
          path: XiaohongshuSite.interactionPath,
          query: {'roomId': room, 'startTimestamp': 0});
  Map<String, dynamic> args(String script) =>
      jsonDecode(RegExp(r'const args = (.*);').firstMatch(script)!.group(1)!);
  void attach(XiaohongshuWebSessionService service, {int status = 200}) {
    service.evaluate = (script) async {
      final payload = args(script);
      expect(payload['path'], XiaohongshuSite.interactionPath);
      expect(payload['query']['startTimestamp'], 0);
      service.receive({
        'id': payload['id'],
        'status': status,
        'ok': status == 200,
        'data': {
          'success': true,
          'data': {'comments': []}
        }
      });
    };
    service.loaded();
  }

  test('restricts navigation to XHS HTTPS origins', () {
    expect(
        XiaohongshuWebSessionService.isAllowedNavigation(
            'https://www.xiaohongshu.com/livestream/$room'),
        isTrue);
    for (final url in [
      'https://xiaohongshu.com.evil.test/',
      'https://user@www.xiaohongshu.com/',
      'http://www.xiaohongshu.com/',
      'https://www.xiaohongshu.com:8443/',
      'file:///etc/passwd'
    ]) {
      expect(XiaohongshuWebSessionService.isAllowedNavigation(url), isFalse);
    }
  });
  test('mock page signs a read request and resolves JSON', () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final future = request(service);
    await Future<void>.delayed(Duration.zero);
    attach(service);
    expect(await future, {
      'success': true,
      'data': {'comments': []}
    });
    await service.releaseRoom(room);
    expect(service.pageUrl.value, isNull);
  });
  test('406 rebuilds once and uses the new session', () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final future = request(service);
    await Future<void>.delayed(Duration.zero);
    attach(service, status: 406);
    await Future<void>.delayed(Duration.zero);
    expect(service.revision.value, 1);
    attach(service);
    expect(await future, isMap);
    await service.releaseRoom(room);
  });
  test('write methods and unknown paths are rejected before page creation',
      () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    await expectLater(
        service.request(
            method: 'POST',
            path: XiaohongshuSite.interactionPath,
            query: {'roomId': room}),
        throwsA(isA<CoreError>()));
    await expectLater(
        service.request(
            method: 'GET', path: '/api/send_comment', query: {'roomId': room}),
        throwsA(isA<CoreError>()));
    expect(service.pageUrl.value, isNull);
  });
  test('unavailable WebView returns an explicit error', () async {
    final service =
        XiaohongshuWebSessionService(platformSupported: () => false);
    await expectLater(request(service), throwsA(isA<CoreError>()));
    expect(service.pageUrl.value, isNull);
  });
  test('two rooms share the signer and closing one preserves the other',
      () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final first = request(service);
    await Future<void>.delayed(Duration.zero);
    attach(service);
    await first;
    const secondRoom = '570321613446566013';
    final originalPage = service.pageUrl.value;
    await service.request(
        method: 'GET',
        path: XiaohongshuSite.interactionPath,
        query: {'roomId': secondRoom, 'startTimestamp': 0});
    expect(service.pageUrl.value, originalPage);
    await service.releaseRoom(room);
    expect(service.pageUrl.value, originalPage);
    await service.releaseRoom(secondRoom);
    expect(service.pageUrl.value, isNull);
  });

  test('stop cancels queued requests before they create another page',
      () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final first = request(service);
    final firstError = expectLater(first, throwsA(isA<CoreCancelledError>()));
    await Future<void>.delayed(Duration.zero);
    service.evaluate = (_) async {};
    service.loaded();
    await Future<void>.delayed(Duration.zero);
    final second = request(service);
    final secondError = expectLater(second, throwsA(isA<CoreCancelledError>()));
    await service.releaseRoom(room);
    await firstError;
    await secondError;
    expect(service.pageUrl.value, isNull);
  });

  test('release prevents a pending signed response from completing the room',
      () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final future = request(service);
    final error = expectLater(future, throwsA(isA<CoreCancelledError>()));
    await Future<void>.delayed(Duration.zero);
    service.evaluate = (_) async {};
    service.loaded();
    await Future<void>.delayed(Duration.zero);
    await service.releaseRoom(room);
    await error;
  });

  test('PC profile uses a separate embedded context and preserves H5 room',
      () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final live = request(service);
    await Future<void>.delayed(Duration.zero);
    attach(service);
    await live;
    final roomUrl = service.pageUrl.value;
    const hostId = '5a422f5ce8ac2b3f2b4e3b42';
    final profile = service.requestHost(hostId: hostId, roomId: room);
    await Future<void>.delayed(Duration.zero);
    expect(service.profilePageUrl.value,
        '${XiaohongshuSite.webBaseUrl}/user/profile/$hostId');
    expect(service.pageUrl.value, roomUrl);
    expect(XiaohongshuWebSessionService.userAgentFor(profile: true),
        XiaohongshuWebSessionService.pcProfileUserAgent);
    expect(XiaohongshuWebSessionService.userAgentFor(profile: false),
        XiaohongshuSite.defaultUserAgent);
    service.evaluateProfile = (script) async {
      final payload = args(script);
      expect(payload['hostId'], hostId);
      expect(script, contains('window._webmsxyw(path, undefined)'));
      final response = {
        'id': payload['id'],
        'status': 200,
        'ok': true,
        'data': {'success': true, 'data': <String, dynamic>{}}
      };
      service.receive({
        ...response,
        'data': {'success': false}
      }); // A room page cannot satisfy a PC request.
      service.receiveProfile(response);
    };
    service.loadedProfile();
    expect((await profile as Map)['success'], true);
    expect(service.profilePageUrl.value, isNull);
    expect(service.pageUrl.value, roomUrl);
    await service.releaseRoom(room);
  });

  test('HTTP 200 logged-out business response does not rebuild PC profile',
      () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final profile =
        service.requestHost(hostId: '5a422f5ce8ac2b3f2b4e3b42', roomId: room);
    await Future<void>.delayed(Duration.zero);
    service.evaluateProfile = (script) async {
      service.receiveProfile({
        'id': args(script)['id'],
        'status': 200,
        'ok': true,
        'data': {'success': false, 'code': -101, 'msg': '无登录信息'}
      });
    };
    service.loadedProfile();
    expect((await profile as Map)['code'], -101);
    expect(service.profileRevision.value, 2);
    expect(service.profilePageUrl.value, isNull);
  });

  test('PC 406 rebuilds exactly once and uses the second page', () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final profile =
        service.requestHost(hostId: '5a422f5ce8ac2b3f2b4e3b42', roomId: room);
    await Future<void>.delayed(Duration.zero);
    service.evaluateProfile = (script) async => service.receiveProfile({
          'id': args(script)['id'],
          'status': 406,
          'ok': false,
        });
    service.loadedProfile();
    for (var i = 0; i < 100 && service.profileRevision.value < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(service.profileRevision.value, 3);
    service.evaluateProfile = (script) async => service.receiveProfile({
          'id': args(script)['id'],
          'status': 200,
          'ok': true,
          'data': {'success': true}
        });
    service.loadedProfile();
    expect((await profile as Map)['success'], true);
    expect(service.profileRevision.value, 4);
    expect(service.profilePageUrl.value, isNull);
  });

  test('closing a room cancels its pending PC profile without a room page',
      () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final profile =
        service.requestHost(hostId: '5a422f5ce8ac2b3f2b4e3b42', roomId: room);
    final cancelled = expectLater(profile, throwsA(isA<CoreCancelledError>()));
    await Future<void>.delayed(Duration.zero);
    expect(service.profilePageUrl.value, isNotNull);
    await service.releaseRoom(room);
    await cancelled;
    expect(service.profilePageUrl.value, isNull);
    expect(service.pageUrl.value, isNull);
  });

  test('transient status request releases H5 context without releaseRoom',
      () async {
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true, desktopEnabled: false);
    final status = service.request(
        method: 'GET',
        path: XiaohongshuSite.statusPath,
        query: {'roomId': room});
    await Future<void>.delayed(Duration.zero);
    service.evaluate = (script) async {
      service.receive({
        'id': args(script)['id'],
        'status': 200,
        'ok': true,
        'data': {'success': true}
      });
    };
    service.loaded();
    expect((await status as Map)['success'], true);
    expect(service.pageUrl.value, isNull);
  });

  test('desktop PC and room sessions are separate and close independently',
      () async {
    final factory = _ReplyingDesktopFactory();
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true,
        desktopEnabled: true,
        desktopFactory: factory,
        cookieProvider: () => 'a=%2F+==');
    expect(await request(service), isMap);
    expect(
        await service.requestHost(
            hostId: '5a422f5ce8ac2b3f2b4e3b42', roomId: room),
        isMap);
    expect(factory.sessions, hasLength(2));
    expect(factory.sessions[0].closed, false);
    expect(factory.sessions[1].closed, true);
    expect(factory.urls[0], contains('/livestream/$room'));
    expect(factory.urls[1], contains('/user/profile/'));
    expect(factory.cookies, everyElement('a=%2F+=='));
    await service.releaseRoom(room);
    expect(factory.sessions[0].closed, true);
  });

  test('desktop profile creation timeout closes a late native session',
      () async {
    final factory = _DeferredDesktopFactory();
    final service = XiaohongshuWebSessionService(
        platformSupported: () => true,
        desktopEnabled: true,
        desktopFactory: factory,
        requestTimeout: const Duration(milliseconds: 30));
    final lookup =
        service.requestHost(hostId: '5a422f5ce8ac2b3f2b4e3b42', roomId: room);
    await expectLater(lookup, throwsA(isA<CoreError>()));
    final lateSession = _ReplyingDesktopSession((_) {});
    factory.complete(lateSession);
    await Future<void>.delayed(Duration.zero);
    expect(lateSession.closed, true);
  });

  test('document-start cookie script preserves percent, plus and equals', () {
    final script =
        XiaohongshuDesktopWebviewWindowFactory.buildDocumentStartScript(
            'a=%2F+==; b=plain');
    expect(script, contains(r'[["a","%2F+=="],["b","plain"]]'));
    expect(script, contains("document.cookie = pair[0] + '=' + pair[1]"));
    expect(script, isNot(contains('encodeURIComponent(pair[1])')));
    expect(script, contains("type: 'xhs_document_ready'"));
  });

  test('PC script signs the fixed GET endpoint and passes headers untouched',
      () async {
    final script = XiaohongshuWebSessionService.buildHostRequestScript(
        id: '42', hostId: '5a422f5ce8ac2b3f2b4e3b42');
    final harness = '''
      const signedHeaders = {'X-s': 'signed', 'X-t': 'timestamp'};
      let signedPath;
      let signedBody;
      let fetched;
      global.window = {
        _webmsxyw: (path, body) => { signedPath = path; signedBody = body; return signedHeaders; },
        chrome: { webview: { postMessage: (message) => {
          const result = JSON.parse(message);
          process.stdout.write(JSON.stringify({signedPath, bodyWasUndefined: signedBody === undefined,
            fetched, result}));
        } } }
      };
      global.fetch = async (url, options) => {
        fetched = {url, method: options.method, credentials: options.credentials,
          redirect: options.redirect, sameHeaders: options.headers === signedHeaders};
        return {ok: true, status: 200, json: async () => ({success: false, code: -101})};
      };
      $script
    ''';
    final result = await Process.run('node', ['-e', harness]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final actual = jsonDecode('${result.stdout}') as Map;
    expect(actual['signedPath'],
        '/api/sns/web/v1/user/hover_card?target_user_id=5a422f5ce8ac2b3f2b4e3b42&image_formats=jpg%2Cwebp&xsec_source=pc_hovercard&xsec_token=');
    expect(actual['bodyWasUndefined'], true);
    expect(actual['fetched'], {
      'url': 'https://edith.xiaohongshu.com${actual['signedPath']}',
      'method': 'GET',
      'credentials': 'include',
      'redirect': 'error',
      'sameHeaders': true,
    });
    expect((actual['result'] as Map)['data']['code'], -101);
  });
}

class _ReplyingDesktopFactory implements XiaohongshuDesktopWebSessionFactory {
  final urls = <String>[];
  final cookies = <String>[];
  final sessions = <_ReplyingDesktopSession>[];

  @override
  Future<XiaohongshuDesktopWebSession> create(
      {required String initialUrl,
      required String cookie,
      required void Function(dynamic message) onMessage}) async {
    urls.add(initialUrl);
    cookies.add(cookie);
    final session = _ReplyingDesktopSession(onMessage);
    sessions.add(session);
    return session;
  }
}

class _DeferredDesktopFactory implements XiaohongshuDesktopWebSessionFactory {
  final _creation = Completer<XiaohongshuDesktopWebSession>();

  void complete(XiaohongshuDesktopWebSession session) =>
      _creation.complete(session);

  @override
  Future<XiaohongshuDesktopWebSession> create(
          {required String initialUrl,
          required String cookie,
          required void Function(dynamic message) onMessage}) =>
      _creation.future;
}

class _ReplyingDesktopSession implements XiaohongshuDesktopWebSession {
  _ReplyingDesktopSession(this._onMessage);
  final void Function(dynamic message) _onMessage;
  bool closed = false;

  @override
  Future<void> evaluateJavaScript(String script) async {
    final payload =
        jsonDecode(RegExp(r'const args = (.*);').firstMatch(script)!.group(1)!)
            as Map;
    _onMessage({
      'id': payload['id'],
      'status': 200,
      'ok': true,
      'data': {'success': true}
    });
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
