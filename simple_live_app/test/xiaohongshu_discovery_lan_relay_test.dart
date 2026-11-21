import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:simple_live_app/services/xiaohongshu_discovery_lan_relay.dart';
import 'package:simple_live_core/simple_live_core.dart';

const _sessionId = '11111111-1111-4111-8111-111111111111';

void main() {
  group('XiaohongshuDiscoveryLanRelay', () {
    test('requires the current six-digit pairing code and disables caching',
        () async {
      final relay = _createRelay();
      relay.start();
      relay.setPageVisible(true);
      relay.setForeground(true);

      final rejected = await _send(
          relay.categoriesRequest, XiaohongshuDiscoveryLanRelay.categoriesPath,
          code: '654321');
      expect(rejected.statusCode, 401);
      expect((await _decode(rejected))['message'], contains('连接码'));
      expect(rejected.headers['cache-control'], 'no-store');

      final accepted = await _send(
        relay.categoriesRequest,
        XiaohongshuDiscoveryLanRelay.categoriesPath,
      );
      expect(accepted.statusCode, 200);
      expect(await _decode(accepted), {
        'categories': [
          {'id': '123', 'name': '游戏'},
        ],
      });
      expect(accepted.headers['cache-control'], 'no-store');
    });

    test('flattens an empty category result and reports upstream failures',
        () async {
      final relay = _createRelay(
        categories: const [],
        failCategories: true,
      );
      relay.start();
      relay.setPageVisible(true);
      relay.setForeground(true);

      final emptyRelay = _createRelay(categories: const []);
      emptyRelay.start();
      emptyRelay.setPageVisible(true);
      emptyRelay.setForeground(true);
      final empty = await _send(
        emptyRelay.categoriesRequest,
        XiaohongshuDiscoveryLanRelay.categoriesPath,
      );
      expect(empty.statusCode, 200);
      expect(await _decode(empty), {'categories': []});

      final failed = await _send(
        relay.categoriesRequest,
        XiaohongshuDiscoveryLanRelay.categoriesPath,
      );
      expect(failed.statusCode, 502);
      final failure = await _decode(failed);
      expect(failure['message'], isA<String>());
      expect(failure['message'], isNot(contains('raw upstream')));
      expect(failed.headers['cache-control'], 'no-store');
    });

    test('maps recommended rooms and caches a repeated successful page',
        () async {
      var roomRequests = 0;
      final relay = _createRelay(
        onRequest: (path, query) async {
          if (path == XiaohongshuDiscoveryClient.squareFeedPath) {
            roomRequests++;
          }
        },
      );
      relay.start();
      relay.setPageVisible(true);
      relay.setForeground(true);

      final first = await _sendRooms(relay, page: 1);
      final retry = await _sendRooms(relay, page: 1);
      expect(first.statusCode, 200);
      expect(retry.statusCode, 200);
      final firstPage = await _decode(first);
      expect(firstPage, {
        'rooms': [
          {
            'roomId': '12345678',
            'title': '晚间游戏直播',
            'cover': 'https://example.test/cover.jpg',
            'userName': '主播甲',
          },
        ],
        'hasMore': true,
      });
      expect(await _decode(retry), firstPage);
      expect(roomRequests, 1);
      expect(first.headers['cache-control'], 'no-store');
    });

    test('rejects skipped pages, category changes, and upstream input',
        () async {
      var roomRequests = 0;
      final relay = _createRelay(
        onRequest: (path, query) async {
          if (path == XiaohongshuDiscoveryClient.squareFeedPath) {
            roomRequests++;
          }
        },
      );
      relay.start();
      relay.setPageVisible(true);
      relay.setForeground(true);

      final skipped = await _sendRooms(relay, page: 2);
      expect(skipped.statusCode, 409);
      expect((await _decode(skipped))['message'], contains('刷新'));

      final first = await _sendRooms(relay, page: 1);
      expect(first.statusCode, 200);
      final changedCategory = await _sendRooms(
        relay,
        page: 2,
        category: '123',
      );
      expect(changedCategory.statusCode, 409);

      final arbitrary = await _sendRooms(
        relay,
        page: 1,
        category: 'https://example.test',
        sessionId: '22222222-2222-4222-8222-222222222222',
      );
      expect(arbitrary.statusCode, 400);
      expect(roomRequests, 1);
      expect(arbitrary.headers['cache-control'], 'no-store');
    });

    test('keeps the cursor when an upstream page fails and is retried',
        () async {
      final cursors = <String>[];
      final relay = _createRelay(
        onRequest: (path, query) async {
          if (path != XiaohongshuDiscoveryClient.squareFeedPath) return;
          cursors.add(query['cursorScore'] as String);
          if (cursors.length == 2) {
            throw StateError('temporary upstream failure');
          }
        },
      );
      relay
        ..start()
        ..setPageVisible(true)
        ..setForeground(true);

      expect((await _sendRooms(relay, page: 1)).statusCode, 200);
      expect((await _sendRooms(relay, page: 2)).statusCode, 502);
      final retried = await _sendRooms(relay, page: 2);
      expect(retried.statusCode, 200);
      expect((await _decode(retried))['hasMore'], isFalse);
      expect(cursors, ['0', 'next-cursor', 'next-cursor']);
    });

    test('returns 409 for expired sessions and invalidates on background',
        () async {
      var now = DateTime.utc(2026, 11, 21);
      final relay = _createRelay(
        now: () => now,
        sessionLifetime: const Duration(minutes: 1),
      );
      final code = relay.start();
      expect(RegExp(r'^[0-9]{6}$').hasMatch(code), isTrue);
      relay.setPageVisible(true);
      relay.setForeground(true);
      expect((await _sendRooms(relay, page: 1)).statusCode, 200);

      now = now.add(const Duration(minutes: 2));
      final expired = await _sendRooms(relay, page: 1);
      expect(expired.statusCode, 409);

      const nextSession = '33333333-3333-4333-8333-333333333333';
      expect(
          (await _sendRooms(relay, page: 1, sessionId: nextSession)).statusCode,
          200);
      relay.setForeground(false);
      expect(relay.pairingCode, code);
      relay.setForeground(true);
      final afterBackground =
          await _sendRooms(relay, page: 1, sessionId: nextSession);
      expect(afterBackground.statusCode, 409);
    });

    test('discards a page that completes after the phone is backgrounded',
        () async {
      final requested = Completer<void>();
      final release = Completer<void>();
      final relay = _createRelay(
        onRequest: (path, query) async {
          if (query['cursorScore'] == 'next-cursor') {
            requested.complete();
            await release.future;
          }
        },
      );
      relay
        ..start()
        ..setPageVisible(true)
        ..setForeground(true);

      expect((await _sendRooms(relay, page: 1)).statusCode, 200);
      final pending = _sendRooms(relay, page: 2);
      await requested.future;
      relay
        ..setForeground(false)
        ..setForeground(true);
      release.complete();
      expect((await pending).statusCode, 503);
      expect((await _sendRooms(relay, page: 2)).statusCode, 409);
    });

    test('returns 503 when hidden and uses a different code on reopen',
        () async {
      final codes = ['123456', '654321'];
      final relay = _createRelay(
        pairingCodeGenerator: () => codes.removeAt(0),
      );
      final firstCode = relay.start();
      relay.setPageVisible(true);
      relay.setForeground(true);
      relay.setPageVisible(false);

      final hidden = await _send(
        relay.categoriesRequest,
        XiaohongshuDiscoveryLanRelay.categoriesPath,
      );
      expect(hidden.statusCode, 503);
      expect((await _decode(hidden))['message'], isA<String>());

      relay.stop();
      final secondCode = relay.start();
      expect(secondCode, '654321');
      expect(secondCode, isNot(firstCode));
    });
  });
}

XiaohongshuDiscoveryLanRelay _createRelay({
  List<dynamic> categories = const [
    {'id': '123', 'desc': '游戏'},
  ],
  bool failCategories = false,
  Future<void> Function(String path, Map<String, dynamic> query)? onRequest,
  DateTime Function()? now,
  Duration sessionLifetime = const Duration(minutes: 10),
  String Function()? pairingCodeGenerator,
}) =>
    XiaohongshuDiscoveryLanRelay(
      requestDiscovery: (
          {required String path, Map<String, dynamic> query = const {}}) async {
        if (onRequest != null) await onRequest(path, query);
        if (path == XiaohongshuDiscoveryClient.categoryPath) {
          if (failCategories) throw StateError('raw upstream failure');
          return {
            'success': true,
            'data': {'categories': categories},
          };
        }
        if (path == XiaohongshuDiscoveryClient.squareFeedPath) {
          if (query['cursorScore'] == '0') {
            return {
              'success': true,
              'data': {
                'feeds': [
                  {
                    'cursorScore': 'next-cursor',
                    'live': {
                      'tRoomInfo': {
                        'roomIdStr': '12345678',
                        'name': '晚间游戏直播',
                        'coverInfo': {
                          'coverImage': 'https://example.test/cover.jpg',
                        },
                        'displayCount': '42',
                      },
                      'tLiveHostInfo': {'nickname': '主播甲'},
                    },
                  },
                ],
              },
            };
          }
          return {
            'success': true,
            'data': {'feeds': []},
          };
        }
        throw StateError('unexpected discovery path');
      },
      isAvailable: () => true,
      now: now,
      sessionLifetime: sessionLifetime,
      pairingCodeGenerator: pairingCodeGenerator ?? () => '123456',
    );

Future<shelf.Response> _send(
  Future<shelf.Response> Function(shelf.Request) handler,
  String path, {
  String code = '123456',
}) =>
    handler(
      shelf.Request(
        'GET',
        Uri.parse('http://127.0.0.1$path'),
        headers: {XiaohongshuDiscoveryLanRelay.pairingCodeHeader: code},
      ),
    );

Future<shelf.Response> _sendRooms(
  XiaohongshuDiscoveryLanRelay relay, {
  required int page,
  String category = '0',
  String sessionId = _sessionId,
}) =>
    _send(
      relay.roomsRequest,
      '${XiaohongshuDiscoveryLanRelay.roomsPath}'
      '?category=$category&page=$page&session=$sessionId',
    );

Future<Map<String, dynamic>> _decode(shelf.Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;
