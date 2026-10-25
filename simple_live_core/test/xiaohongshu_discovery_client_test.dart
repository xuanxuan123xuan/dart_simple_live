import 'dart:async';
import 'dart:convert';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

class _Request {
  _Request(this.path, this.query);

  final String path;
  final Map<String, dynamic> query;
}

class _DiscoveryBridge implements XiaohongshuDiscoveryRequestBridge {
  _DiscoveryBridge(this.respond);

  final FutureOr<dynamic> Function(String path, Map<String, dynamic> query)
      respond;
  final requests = <_Request>[];

  @override
  Future<dynamic> requestDiscovery({
    required String path,
    Map<String, dynamic> query = const <String, dynamic>{},
  }) async {
    final copy = Map<String, dynamic>.from(query);
    requests.add(_Request(path, copy));
    return respond(path, copy);
  }
}

Map<String, dynamic> _feed({
  required String roomId,
  required String cursorScore,
  String title = 'Live title',
  String cover = 'https://example.test/cover.jpg',
  String host = '主播',
}) =>
    {
      'cursorScore': cursorScore,
      'live': {
        'tRoomInfo': {
          'roomIdStr': roomId,
          'name': title,
          'displayCount': '321',
          'coverInfo': {'coverImage': cover},
        },
        'tLiveHostInfo': {'nickname': host},
      },
    };

Map<String, dynamic> _response(Object data) => {
      'success': true,
      'data': data,
    };

// Synthetic fixtures follow the official web bundle contract; they are not
// captured successful production API responses.
void main() {
  test('rejects business errors and malformed response schemas', () async {
    for (final response in <dynamic>[
      null,
      {
        'success': false,
        'data': {'feeds': []}
      },
      {
        'code': '300012',
        'data': {'feeds': []}
      },
      {'success': true},
      _response({'feeds': 'invalid', 'categories': 'invalid'}),
      _response({}),
    ]) {
      final bridge = _DiscoveryBridge((path, query) => response);
      final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
      await expectLater(site.getRecommendRooms(), throwsA(isA<CoreError>()));
      await expectLater(site.getCategores(), throwsA(isA<CoreError>()));
    }
  });

  test('initial cursor zero stops and invalid room cards are skipped',
      () async {
    final bridge = _DiscoveryBridge((path, query) => _response({
          'feeds': [
            {'roomId': '570493541297105186'},
            _feed(roomId: '123', cursorScore: 'unused'),
            _feed(roomId: '570493541297105187', cursorScore: 'x', host: ''),
            _feed(roomId: '570493541297105188', cursorScore: '0'),
          ],
        }));
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
    final result = await site.getRecommendRooms();
    expect(result.items.map((item) => item.roomId), ['570493541297105188']);
    expect(result.hasMore, isFalse);
    expect((await site.getRecommendRooms(page: 2)).items, isEmpty);
    expect(bridge.requests, hasLength(1));
  });

  test('keeps cursor state separate for each category', () async {
    final bridge = _DiscoveryBridge((path, query) => _response({
          'feeds': [
            _feed(
              roomId: query['cursorScore'] == '0'
                  ? '570493541297105186'
                  : '570493541297105187',
              cursorScore: '${query['category']}-next',
            ),
          ],
        }));
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
    final category =
        LiveSubCategory(id: '0', name: '全部', parentId: 'xiaohongshu');
    await site.getRecommendRooms();
    await site.getCategoryRooms(category);
    await site.getRecommendRooms(page: 2);
    await site.getCategoryRooms(category, page: 2);
    expect(bridge.requests.map((request) => request.query['cursorScore']),
        ['0', '0', '0-next', '0-next']);
  });

  test('ignores duplicate in-flight pages without consuming the next page',
      () async {
    final pendingResponse = Completer<dynamic>();
    final bridge = _DiscoveryBridge((path, query) {
      if (query['cursorScore'] == 'first') return pendingResponse.future;
      return _response({
        'feeds': [_feed(roomId: '570493541297105186', cursorScore: 'first')],
      });
    });
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
    await site.getRecommendRooms();
    final pending = site.getRecommendRooms(page: 2);
    expect((await site.getRecommendRooms(page: 2)).items, isEmpty);
    expect(bridge.requests, hasLength(2));
    pendingResponse.complete(_response({
      'feeds': [_feed(roomId: '570493541297105187', cursorScore: 'second')],
    }));
    expect((await pending).hasMore, isTrue);
    await site.getRecommendRooms(page: 3);
    expect(bridge.requests.last.query['cursorScore'], 'second');
  });

  test('can retry a failed page without losing its cursor', () async {
    var failed = false;
    final bridge = _DiscoveryBridge((path, query) {
      if (query['cursorScore'] == 'first' && !failed) {
        failed = true;
        throw StateError('temporary request failure');
      }
      return _response({
        'feeds': [_feed(roomId: '570493541297105186', cursorScore: 'first')],
      });
    });
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
    await site.getRecommendRooms();
    await expectLater(site.getRecommendRooms(page: 2), throwsStateError);
    await site.getRecommendRooms(page: 2);
    expect(bridge.requests.map((request) => request.query['cursorScore']),
        ['0', 'first', 'first']);
  });

  test('maps flat official categories beneath one Xiaohongshu root', () async {
    final bridge = _DiscoveryBridge((path, query) => _response({
          'categories': [
            {'id': 0, 'desc': '全部'},
            {'id': 12, 'desc': '游戏'},
          ],
        }));
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;

    final categories = await site.getCategores();

    expect(bridge.requests, hasLength(1));
    expect(
        bridge.requests.single.path, XiaohongshuDiscoveryClient.categoryPath);
    expect(bridge.requests.single.query, isEmpty);
    expect(categories, hasLength(1));
    expect(categories.single.id, 'xiaohongshu');
    expect(categories.single.name, '小红书直播');
    expect(
      categories.single.children
          .map((category) => (category.id, category.name)),
      [('0', '全部'), ('12', '游戏')],
    );
  });

  test('requests recommend category 0 and maps official feed fields', () async {
    final bridge = _DiscoveryBridge((path, query) => _response({
          'feeds': [
            _feed(roomId: '570493541297105186', cursorScore: 'next-1'),
          ],
        }));
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;

    final page = await site.getRecommendRooms();

    expect(bridge.requests, hasLength(1));
    final request = bridge.requests.single;
    expect(request.path, XiaohongshuDiscoveryClient.squareFeedPath);
    expect(request.query, {
      'cursorScore': '0',
      'source': 13,
      'category': '0',
      'topRoomIds': '',
      'preSource': '',
      'extraInfo': '',
      'size': 27,
      'extra_info': jsonEncode({
        'image_formats': ['jpg', 'webp', 'avif'],
      }),
    });
    expect(page.hasMore, isTrue);
    expect(page.items, hasLength(1));
    expect(page.items.single.roomId, '570493541297105186');
    expect(page.items.single.title, 'Live title');
    expect(page.items.single.cover, 'https://example.test/cover.jpg');
    expect(page.items.single.userName, '主播');
    expect(page.items.single.online, 321);
  });

  test('uses category ID and cursor score for the next page, de-duplicating',
      () async {
    final bridge = _DiscoveryBridge((path, query) {
      if (query['cursorScore'] == '0') {
        return _response({
          'feeds': [
            _feed(roomId: '570493541297105186', cursorScore: 'cursor-1'),
          ],
        });
      }
      return _response({
        'feeds': [
          _feed(roomId: '570493541297105186', cursorScore: 'cursor-2'),
          _feed(roomId: '570493541297105187', cursorScore: 'cursor-3'),
        ],
      });
    });
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
    final category = LiveSubCategory(
      id: '12',
      name: '游戏',
      parentId: 'xiaohongshu',
    );

    final first = await site.getCategoryRooms(category);
    final second = await site.getCategoryRooms(category, page: 2);

    expect(bridge.requests, hasLength(2));
    expect(bridge.requests[0].query['category'], '12');
    expect(bridge.requests[0].query['cursorScore'], '0');
    expect(bridge.requests[1].query['category'], '12');
    expect(bridge.requests[1].query['cursorScore'], 'cursor-1');
    expect(first.hasMore, isTrue);
    expect(first.items.map((item) => item.roomId), ['570493541297105186']);
    expect(second.hasMore, isTrue);
    expect(second.items.map((item) => item.roomId), ['570493541297105187']);
  });

  test('stops on empty feeds, missing cursor, and stalled cursor', () async {
    final feeds = <dynamic>[
      {'feeds': []},
      {
        'feeds': [
          _feed(roomId: '570493541297105186', cursorScore: ''),
        ],
      },
      {
        'feeds': [
          _feed(roomId: '570493541297105186', cursorScore: 'repeat'),
        ],
      },
    ];
    final bridge = _DiscoveryBridge((path, query) =>
        _response(feeds.length > 1 ? feeds.removeAt(0) : feeds.single));
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
    final category = LiveSubCategory(
      id: '12',
      name: '游戏',
      parentId: 'xiaohongshu',
    );

    final empty = await site.getCategoryRooms(category);
    expect(empty.hasMore, isFalse);
    expect((await site.getCategoryRooms(category, page: 2)).items, isEmpty);
    expect(bridge.requests, hasLength(1));

    final missingCursor = await site.getCategoryRooms(category);
    expect(missingCursor.hasMore, isFalse);
    expect((await site.getCategoryRooms(category, page: 2)).items, isEmpty);
    expect(bridge.requests, hasLength(2));

    final first = await site.getCategoryRooms(category);
    expect(first.hasMore, isTrue);
    final stalled = await site.getCategoryRooms(category, page: 2);
    expect(stalled.hasMore, isFalse);
    expect(bridge.requests, hasLength(4));
  });

  test('skips invalid rooms and rejects late responses after a refresh',
      () async {
    final oldPage = Completer<dynamic>();
    var requestNumber = 0;
    final bridge = _DiscoveryBridge((path, query) {
      requestNumber++;
      if (requestNumber == 1) return oldPage.future;
      return _response({
        'feeds': [
          _feed(roomId: 'bad-id', cursorScore: 'bad'),
          _feed(roomId: '570493541297105188', cursorScore: 'fresh'),
        ],
      });
    });
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
    final category = LiveSubCategory(
      id: '12',
      name: '游戏',
      parentId: 'xiaohongshu',
    );

    final pending = site.getCategoryRooms(category);
    final refreshed = await site.getCategoryRooms(category);
    oldPage.complete(_response({
      'feeds': [
        _feed(roomId: '570493541297105189', cursorScore: 'old'),
      ],
    }));

    expect(refreshed.items.map((item) => item.roomId), ['570493541297105188']);
    expect((await pending).items, isEmpty);
    expect(bridge.requests, hasLength(2));
  });

  test('resetPagination invalidates an in-flight response', () async {
    final pendingResponse = Completer<dynamic>();
    final bridge = _DiscoveryBridge((path, query) => pendingResponse.future);
    final site = XiaohongshuSite()..discoveryRequestBridge = bridge;
    final category = LiveSubCategory(
      id: '12',
      name: '游戏',
      parentId: 'xiaohongshu',
    );

    final pending = site.getCategoryRooms(category);
    site.discovery.resetPagination();
    pendingResponse.complete(_response({
      'feeds': [
        _feed(roomId: '570493541297105190', cursorScore: 'old'),
      ],
    }));

    expect((await pending).items, isEmpty);
    expect((await site.getCategoryRooms(category, page: 2)).items, isEmpty);
    expect(bridge.requests, hasLength(1));
  });

  test('changing discovery bridges invalidates previous pagination', () async {
    final oldResponse = Completer<dynamic>();
    final oldBridge = _DiscoveryBridge((path, query) => oldResponse.future);
    final newBridge = _DiscoveryBridge((path, query) => _response({
          'feeds': [_feed(roomId: '570493541297105190', cursorScore: 'new')],
        }));
    final site = XiaohongshuSite()..discoveryRequestBridge = oldBridge;
    final pending = site.getRecommendRooms();
    site.discoveryRequestBridge = newBridge;
    oldResponse.complete(_response({
      'feeds': [_feed(roomId: '570493541297105189', cursorScore: 'old')],
    }));
    expect((await pending).items, isEmpty);
    expect((await site.getRecommendRooms(page: 2)).items, isEmpty);
    expect((await site.getRecommendRooms()).items.single.roomId,
        '570493541297105190');
    expect(newBridge.requests.single.query['cursorScore'], '0');
  });

  test('search remains unavailable and directory is empty without a bridge',
      () async {
    final site = XiaohongshuSite();

    expect(site.discovery.isAvailable, isFalse);
    expect(await site.getCategores(), isEmpty);
    expect((await site.getRecommendRooms()).items, isEmpty);
    final rooms = await site.searchRooms('测试');
    expect(rooms.items, isEmpty);
    expect(rooms.metadata.origin, SearchOrigin.fallback);
    expect(rooms.metadata.continuation, SearchContinuation.unknown);
  });
}
