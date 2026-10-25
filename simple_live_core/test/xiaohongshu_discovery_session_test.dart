import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> args(String script) =>
    jsonDecode(RegExp(r'const args = (.*);').firstMatch(script)!.group(1)!);

void main() {
  const path = XiaohongshuDiscoveryClient.categoryPath;
  const feeds = XiaohongshuDiscoveryClient.squareFeedPath;
  const query = {'category': '0', 'cursorScore': '0', 'source': 13, 'size': 27};

  test('rejects arbitrary paths and unexpected directory parameters', () async {
    var opened = false;
    final session = XiaohongshuDiscoverySession(openPage: (_) async {
      opened = true;
      throw StateError('unexpected browser');
    });
    for (final entry in [
      ('/api/send_comment', <String, dynamic>{}),
      (path, <String, dynamic>{'roomId': '123'}),
      (feeds, <String, dynamic>{...query, 'url': 'https://example.com'}),
      (feeds, <String, dynamic>{...query, 'category': '../'}),
      (feeds, <String, dynamic>{...query, 'cursorScore': <String>[]}),
    ]) {
      await expectLater(
          session.requestDiscovery(path: entry.$1, query: entry.$2),
          throwsA(isA<CoreError>()));
    }
    expect(opened, isFalse);
    await session.close();
  });

  test('serializes categories and feeds on one reusable independent page',
      () async {
    var opened = 0;
    var closed = 0;
    final pending = <Map<String, dynamic>>[];
    late void Function(dynamic) receive;
    final session = XiaohongshuDiscoverySession(openPage: (callback) async {
      opened++;
      receive = callback;
      return XiaohongshuDiscoveryPage(evaluate: (script) async {
        pending.add(args(script));
      }, close: () async {
        closed++;
      });
    });
    final first = session.requestDiscovery(path: path);
    final second = session.requestDiscovery(path: feeds, query: query);
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(1));
    receive({'id': 'room:1', 'ok': true, 'data': 'wrong context'});
    receive({'id': pending.first['id'], 'ok': true, 'data': 'categories'});
    expect(await first, 'categories');
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(2));
    receive({'id': pending.last['id'], 'ok': true, 'data': 'feeds'});
    expect(await second, 'feeds');
    expect(opened, 1);
    expect(closed, 0);
    await session.close();
    expect(closed, 1);
  });

  test('406 replaces only the directory page and retries exactly once',
      () async {
    var opened = 0;
    var closed = 0;
    final session = XiaohongshuDiscoverySession(openPage: (receive) async {
      final attempt = ++opened;
      return XiaohongshuDiscoveryPage(evaluate: (script) async {
        receive({
          'id': args(script)['id'],
          'ok': attempt == 2,
          'status': attempt == 1 ? 406 : 200,
          'data': 'ok'
        });
      }, close: () async {
        closed++;
      });
    });
    expect(await session.requestDiscovery(path: path), 'ok');
    expect(opened, 2);
    expect(closed, 1);
    await session.close();
  });

  test('a second 406 and HTTP failures propagate without more retries',
      () async {
    for (final status in [406, 403, 500]) {
      var opened = 0;
      final session = XiaohongshuDiscoverySession(openPage: (receive) async {
        opened++;
        return XiaohongshuDiscoveryPage(
            evaluate: (script) async {
              receive(
                  {'id': args(script)['id'], 'ok': false, 'status': status});
            },
            close: () async {});
      });
      await expectLater(
          session.requestDiscovery(path: path),
          throwsA(
              isA<CoreError>().having((e) => e.statusCode, 'status', status)));
      expect(opened, status == 406 ? 2 : 1);
      await session.close();
    }
  });

  test('HTTP success leaves business errors for the directory parser',
      () async {
    var opened = 0;
    final session = XiaohongshuDiscoverySession(openPage: (receive) async {
      opened++;
      return XiaohongshuDiscoveryPage(
          evaluate: (script) async {
            receive({
              'id': args(script)['id'],
              'ok': true,
              'status': 200,
              'data': {'success': false, 'code': -101}
            });
          },
          close: () async {});
    });
    expect(await session.requestDiscovery(path: path),
        {'success': false, 'code': -101});
    expect(opened, 1);
    await session.close();
  });

  test('reset cancels queued and in-flight work and ignores late responses',
      () async {
    var opened = 0;
    var closed = 0;
    late void Function(dynamic) receive;
    late String id;
    final session = XiaohongshuDiscoverySession(openPage: (callback) async {
      opened++;
      receive = callback;
      return XiaohongshuDiscoveryPage(evaluate: (script) async {
        id = args(script)['id'];
      }, close: () async {
        closed++;
      });
    });
    final first = session.requestDiscovery(path: path);
    final queued = session.requestDiscovery(path: path);
    final checkedFirst = expectLater(first, throwsA(isA<CoreCancelledError>()));
    final checkedQueued =
        expectLater(queued, throwsA(isA<CoreCancelledError>()));
    await Future<void>.delayed(Duration.zero);
    await session.reset();
    receive({'id': id, 'ok': true, 'data': 'too late'});
    await Future.wait([checkedFirst, checkedQueued]);
    expect(opened, 1);
    expect(closed, 1);
    await session.close();
  });

  test('timeout releases the context and late browser creation is closed',
      () async {
    final creating = Completer<XiaohongshuDiscoveryPage>();
    var closed = 0;
    final session = XiaohongshuDiscoverySession(
      requestTimeout: const Duration(milliseconds: 10),
      openPage: (_) => creating.future,
    );
    await expectLater(
        session.requestDiscovery(path: path),
        throwsA(isA<CoreError>()
            .having((e) => e.kind, 'kind', CoreErrorKind.network)));
    creating.complete(XiaohongshuDiscoveryPage(
      evaluate: (_) async => fail('abandoned page evaluated'),
      close: () async {
        closed++;
      },
    ));
    await Future<void>.delayed(Duration.zero);
    expect(closed, 1);
    await session.close();
  });

  test('idle directory page is released and the next request opens a new one',
      () async {
    var opened = 0;
    var closed = 0;
    final session = XiaohongshuDiscoverySession(
      idleTimeout: Duration.zero,
      openPage: (receive) async {
        opened++;
        return XiaohongshuDiscoveryPage(evaluate: (script) async {
          receive({'id': args(script)['id'], 'ok': true, 'data': 'ok'});
        }, close: () async {
          closed++;
        });
      },
    );
    await session.requestDiscovery(path: path);
    await Future<void>.delayed(Duration.zero);
    expect(closed, 1);
    await session.requestDiscovery(path: path);
    expect(opened, 2);
    await session.close();
    await expectLater(session.requestDiscovery(path: path),
        throwsA(isA<CoreCancelledError>()));
  });
  test(
      'production PC script response reaches the site parser with its envelope',
      () async {
    final session = XiaohongshuDiscoverySession(openPage: (receive) async {
      return XiaohongshuDiscoveryPage(
          evaluate: (script) async {
            const harness = r'''
          const response = {
            categories: [{id: 0, desc: '全部'}],
            feeds: [{cursorScore: 'next', live: {
              tRoomInfo: {roomIdStr: '570493541297105186', name: '真实字段模拟直播',
                displayCount: '1234', coverInfo: {coverImage: 'https://example.test/live.jpg'}},
              tLiveHostInfo: {nickname: '测试主播'}
            }}]
          };
          const wrappers = {
            BR: function getApiSnsRedLiveWebFeedCategory() { return Promise.resolve(response); },
            i9: function getApiSnsRedLiveWebFeedV1Squarefeed() { return Promise.resolve(response); }
          };
          const runtime = () => wrappers;
          runtime.m = {76565: function() {
            return ['/api/sns/red/live/web/feed/category', '/api/sns/red/live/web/feed/v1/squarefeed'];
          }};
          global.window = {
            webpackChunkxhs_pc_web: {push: chunk => chunk[2](runtime)},
            chrome: {webview: {postMessage: message => process.stdout.write(message)}}
          };
        ''';
            final result =
                await Process.run('node', ['-e', '$harness\n$script'], stdoutEncoding: utf8, stderrEncoding: utf8);
            expect(result.exitCode, 0, reason: '${result.stderr}');
            receive('${result.stdout}');
          },
          close: () async {});
    });
    addTearDown(session.close);
    final site = XiaohongshuSite()..discoveryRequestBridge = session;
    final categories = await site.getCategores();
    expect(categories.single.children.single.name, '全部');
    final page = await site.getRecommendRooms();
    expect(page.items.single.roomId, '570493541297105186');
    expect(page.items.single.title, '真实字段模拟直播');
    expect(page.items.single.online, 1234);
    expect(page.items.single.userName, '测试主播');
    expect(page.hasMore, isTrue);
  });
}
