import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_web_session_service.dart';

void main() {
  const room = '570493541297105186';
  const other = '570493541297105187';
  Future<dynamic> request(XiaohongshuWebSessionService service,
          [String id = room]) =>
      service.request(
          method: 'GET',
          path: XiaohongshuSite.interactionPath,
          query: {'roomId': id});
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  Map<String, dynamic> args(String script) =>
      jsonDecode(RegExp(r'const args = (.*);').firstMatch(script)!.group(1)!);
  void attach(XiaohongshuWebSessionService service, {int status = 200}) {
    service.evaluate = (script) async {
      final payload = args(script);
      service.receive({
        'id': payload['id'],
        'ok': status == 200,
        'status': status,
        'data': payload['query']
      });
    };
    service.loaded();
  }

  XiaohongshuWebSessionService create() => XiaohongshuWebSessionService(
      site: XiaohongshuSite(), platformSupported: () => true);

  test('Windows explicitly rejects signing without starting a WebView',
      () async {
    final service = XiaohongshuWebSessionService(
        site: XiaohongshuSite(), platformSupported: () => false);
    await expectLater(request(service), throwsA(isA<CoreError>()));
    expect(service.pageUrl.value, isNull);
  });
  test('only the five GET endpoints are accepted', () async {
    final service = create();
    for (final method in ['POST', 'DELETE']) {
      await expectLater(
          service.request(
              method: method,
              path: XiaohongshuSite.interactionPath,
              query: {'roomId': room}),
          throwsA(isA<CoreError>()));
    }
    await expectLater(
        service.request(
            method: 'GET', path: '/api/other', query: {'roomId': room}),
        throwsA(isA<CoreError>()));
    await expectLater(
        service.request(
            method: 'GET',
            path: XiaohongshuSite.interactionPath,
            query: {'roomId': room},
            body: {}),
        throwsA(isA<CoreError>()));
  });
  test('navigation requires an exact HTTPS XHS host', () {
    expect(
        XiaohongshuWebSessionService.isAllowedNavigation(
            'https://www.xiaohongshu.com/livestream/$room'),
        isTrue);
    for (final url in [
      'http://www.xiaohongshu.com/',
      'https://www.xiaohongshu.com.evil.test/',
      'https://user@www.xiaohongshu.com/',
      'https://www.xiaohongshu.com:8443/'
    ]) {
      expect(XiaohongshuWebSessionService.isAllowedNavigation(url), isFalse);
    }
  });
  test('requests share a serialized session and last release closes it',
      () async {
    final service = create();
    final first = request(service);
    final second = request(service, other);
    await tick();
    var calls = 0;
    Map<String, dynamic>? firstArgs;
    service.evaluate = (script) async {
      calls++;
      firstArgs = args(script);
    };
    service.loaded();
    await tick();
    expect(calls, 1);
    service.receive(
        {'id': firstArgs!['id'], 'ok': true, 'status': 200, 'data': 1});
    expect(await first, 1);
    await tick();
    expect(calls, 2);
    service.receive(
        {'id': firstArgs!['id'], 'ok': true, 'status': 200, 'data': 2});
    expect(await second, 2);
    await service.releaseRoom(room);
    expect(service.pageUrl.value, isNotNull);
    await service.releaseRoom(other);
    expect(service.pageUrl.value, isNull);
  });
  test('406 rebuilds once and accepts only the new WebView revision', () async {
    final service = create();
    final result = request(service);
    await tick();
    attach(service, status: 406);
    await tick();
    expect(service.revision.value, 1);
    service.loaded(sessionRevision: 0);
    attach(service);
    expect(await result, {'roomId': room});
    await service.releaseRoom(room);
  });
  test('release cancels queued and waiting-ready requests promptly', () async {
    final service = create();
    final first = request(service);
    final second = request(service);
    final firstCheck = expectLater(first, throwsA(isA<CoreCancelledError>()));
    final secondCheck = expectLater(second, throwsA(isA<CoreCancelledError>()));
    await tick();
    await service.releaseRoom(room);
    await Future.wait([firstCheck, secondCheck])
        .timeout(const Duration(seconds: 1));
    expect(service.pageUrl.value, isNull);
  });
  test('one room release leaves another in-flight room usable', () async {
    final service = create();
    final first = request(service);
    final second = request(service, other);
    final firstCheck = expectLater(first, throwsA(isA<CoreCancelledError>()));
    await tick();
    await service.releaseRoom(room);
    await firstCheck;
    await tick();
    attach(service);
    expect(await second, {'roomId': other});
    await service.releaseRoom(other);
  });
  test(
      'Cookie changes cancel old queued work and host disposal cancels readiness',
      () async {
    final service = create();
    final first = request(service);
    final second = request(service, other);
    final checks = [
      expectLater(first, throwsA(isA<CoreCancelledError>())),
      expectLater(second, throwsA(isA<CoreCancelledError>()))
    ];
    await tick();
    await service.cookieChanged('');
    await Future.wait(checks);
    final next = request(service);
    final check = expectLater(next, throwsA(isA<CoreCancelledError>()));
    await tick();
    service.hostDetached(service.revision.value);
    await check;
    expect(service.pageUrl.value, isNull);
  });
  test('readiness has a bounded deadline', () async {
    final service = XiaohongshuWebSessionService(
        site: XiaohongshuSite(),
        platformSupported: () => true,
        requestTimeout: const Duration(milliseconds: 10));
    await expectLater(request(service), throwsA(isA<CoreError>()));
    await service.releaseRoom(room);
  });
}
