import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_web_session_service.dart';

void main() {
  const room = '570493541297105186';
  const path = XiaohongshuDiscoveryClient.categoryPath;
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  Map<String, dynamic> args(String script) =>
      jsonDecode(RegExp(r'const args = (.*);').firstMatch(script)!.group(1)!);
  XiaohongshuWebSessionService create({bool supported = true}) =>
      XiaohongshuWebSessionService(
          site: XiaohongshuSite(), platformSupported: () => supported);
  void attachDirectory(XiaohongshuWebSessionService service,
      {int status = 200}) {
    service.evaluateDiscovery = (script) async {
      final payload = args(script);
      service.receiveDiscovery({
        'id': payload['id'],
        'ok': status == 200,
        'status': status,
        'data': {
          'success': true,
          'data': {'categories': []}
        }
      });
    };
    service.loadedDiscovery(
        url: service.discoveryPageUrl.value!,
        sessionRevision: service.discoveryRevision.value);
  }

  test('directory initializes without a room and uses an independent page',
      () async {
    final service = create();
    addTearDown(service.discoverySession.close);
    final roomWork = service.request(
        method: 'GET',
        path: XiaohongshuSite.interactionPath,
        query: {'roomId': room});
    await tick();
    service.evaluate = (script) async {
      service.receive({
        'id': args(script)['id'],
        'ok': true,
        'status': 200,
        'data': {'success': true}
      });
    };
    service.loaded();
    await roomWork;
    final playingPage = service.pageUrl.value;
    final directory = service.requestDiscovery(path: path);
    await tick();
    expect(service.discoveryPageUrl.value, XiaohongshuDiscoverySession.pageUrl);
    expect(service.pageUrl.value, playingPage);
    attachDirectory(service);
    expect((await directory as Map)['success'], true);
    await service.discoverySession.close();
    expect(service.discoveryPageUrl.value, isNull);
    expect(service.pageUrl.value, playingPage);
    await service.releaseRoom(room);
  });

  test('directory 406 rebuild does not reset a playing room', () async {
    final service = create();
    addTearDown(service.discoverySession.close);
    final directory = service.requestDiscovery(path: path);
    await tick();
    final oldRevision = service.discoveryRevision.value;
    attachDirectory(service, status: 406);
    await tick();
    expect(service.discoveryRevision.value, greaterThan(oldRevision));
    expect(service.revision.value, 0);
    attachDirectory(service);
    expect(await directory, isMap);
  });

  test('directory host detachment cancels waiting work', () async {
    final service = create();
    addTearDown(service.discoverySession.close);
    final work = service.requestDiscovery(path: path);
    final error = expectLater(work, throwsA(isA<CoreCancelledError>()));
    await tick();
    service.discoveryHostDetached(service.discoveryRevision.value);
    await error;
    expect(service.discoveryPageUrl.value, isNull);
  });

  test('cookie changes invalidate directory and old callbacks', () async {
    final service = create();
    addTearDown(service.discoverySession.close);
    final work = service.requestDiscovery(path: path);
    final error = expectLater(work, throwsA(isA<CoreCancelledError>()));
    await tick();
    final oldRevision = service.discoveryRevision.value;
    await service.cookieChanged('');
    await error;
    expect(service.discoveryPageUrl.value, isNull);
    service.loadedDiscovery(
        url: XiaohongshuDiscoverySession.pageUrl, sessionRevision: oldRevision);
    final replacement = service.requestDiscovery(path: path);
    await tick();
    attachDirectory(service);
    expect(await replacement, isMap);
  });

  test('unsupported platform and unexpected parameters create no host',
      () async {
    final service = create(supported: false);
    addTearDown(service.discoverySession.close);
    await expectLater(
        service.requestDiscovery(path: path), throwsA(isA<CoreError>()));
    await expectLater(
        service.requestDiscovery(path: path, query: {'roomId': room}),
        throwsA(isA<CoreError>()));
    expect(service.discoveryPageUrl.value, isNull);
  });
}
