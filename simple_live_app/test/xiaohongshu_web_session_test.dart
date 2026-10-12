import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
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
    final service = XiaohongshuWebSessionService(platformSupported: () => true);
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
    final service = XiaohongshuWebSessionService(platformSupported: () => true);
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
    final service = XiaohongshuWebSessionService(platformSupported: () => true);
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
    final service = XiaohongshuWebSessionService(platformSupported: () => true);
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
    final service = XiaohongshuWebSessionService(platformSupported: () => true);
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
    final service = XiaohongshuWebSessionService(platformSupported: () => true);
    final future = request(service);
    final error = expectLater(future, throwsA(isA<CoreCancelledError>()));
    await Future<void>.delayed(Duration.zero);
    service.evaluate = (_) async {};
    service.loaded();
    await Future<void>.delayed(Duration.zero);
    await service.releaseRoom(room);
    await error;
  });
}
