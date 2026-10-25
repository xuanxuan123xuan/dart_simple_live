import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  late DouyinSite site;
  late Interceptor interceptor;
  late List<RequestOptions> requests;
  late List<Map<String, dynamic>> catalog;
  late Map<String, dynamic> roomTags;
  var failCatalog = false;
  Completer<void>? catalogGate;

  setUp(() {
    requests = [];
    failCatalog = false;
    catalogGate = null;
    roomTags = {
      'partition': {'id_str': '1010026', 'type': 1, 'title': '绝地求生'},
      'parent_partition': {'id_str': '1', 'type': 1, 'title': '射击'},
    };
    catalog = [
      _node('103', 4, '游戏', [
        _node('1', 1, '射击', [_node('1010026', 1, '绝地求生')]),
      ]),
      _node('101', 4, '聊天'),
    ];
    site = DouyinSite(abogusSigner: (url, _) => url);
    interceptor = InterceptorsWrapper(onRequest: (options, handler) async {
      requests.add(options);
      if (options.uri.path.contains('/partition/detail/room/')) {
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'status_code': 0,
            'data': {'data': []}
          },
        ));
      } else if (options.uri.path.contains('/web/enter/')) {
        handler.resolve(Response(requestOptions: options, data: {
          'status_code': 0,
          'data': {
            'data': [
              {
                'id_str': '123',
                'status': 4,
                'title': '测试房间',
                'owner': {'id_str': '456', 'nickname': '主播'},
                ...roomTags,
              }
            ]
          }
        }));
      } else {
        await catalogGate?.future;
        if (failCatalog) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ));
        } else {
          handler.resolve(Response<String>(
            requestOptions: options,
            data:
                '<script>\\"categoryData\\":${jsonEncode(catalog).replaceAll('"', r'\"')}</script>',
          ));
        }
      }
    });
    HttpClient.instance.dio.interceptors.add(interceptor);
  });
  tearDown(() => HttpClient.instance.dio.interceptors.remove(interceptor));

  test('room detail pairs the ID and type for child and parent', () async {
    final detail = await site.getRoomDetail(roomId: 'room');
    expect(detail.categoryId, '1010026,1');
    expect(detail.categoryParentId, '1,1');
  });

  test('current game_data tag resolves through the real category directory',
      () async {
    roomTags = {
      'game_data': {
        'game_tag_info': {
          'is_game': 1,
          'game_tag_id': 1010026,
          'game_tag_name': '绝地求生',
        },
      },
    };
    final detail = await site.getRoomDetail(roomId: 'game-room');
    expect(detail.categoryId, '1010026');
    expect(detail.categoryName, '绝地求生');
    final resolved = await site.resolveRoomCategory(detail);
    expect(resolved?.id, '1010026,1');
    expect(resolved?.parentId, '1,1');
  });

  test('non-game placeholder does not become a fake category', () async {
    roomTags = {
      'game_data': {
        'game_tag_info': {
          'is_game': 2,
          'game_tag_id': 0,
          'game_tag_name': '',
        }
      }
    };
    final detail = await site.getRoomDetail(roomId: 'chat-room');
    expect(detail.categoryId, isNull);
    expect(await site.resolveRoomCategory(detail), isNull);
    expect(requests, hasLength(1));
  });

  test('typed category needs no catalog request', () async {
    final category =
        await site.resolveRoomCategory(_room('1010026,1', parent: '1,1'));
    expect(category?.id, '1010026,1');
    expect(category?.parentId, '1,1');
    expect(requests, isEmpty);
  });

  test('raw ID resolves recursively without external image requests', () async {
    final category = await site.resolveRoomCategory(_room('1010026'));
    expect(category?.id, '1010026,1');
    expect(category?.parentId, '1,1');
    expect(category?.name, '绝地求生');
    expect(requests, hasLength(1));
    expect(requests.single.uri.host, 'live.douyin.com');
  });

  test('parent-only tag can resolve but unknown child does not fall back',
      () async {
    expect((await site.resolveRoomCategory(_room(null, parent: '101')))?.id,
        '101,4');
    expect(
        await site.resolveRoomCategory(_room('999', parent: '101,4')), isNull);
    expect(await site.resolveRoomCategory(_room(null)), isNull);
    expect(requests, hasLength(1));
  });

  test('duplicate raw IDs with different types are unavailable', () async {
    catalog.add(_node('1010026', 4, '另一个分区'));
    expect(await site.resolveRoomCategory(_room('1010026')), isNull);
  });

  test('explicit parent disambiguates a repeated child ID', () async {
    catalog.add(_node('102', 4, '其他', [_node('1010026', 1, '重复')]));
    final category =
        await site.resolveRoomCategory(_room('1010026', parent: '1,1'));
    expect(category?.parentId, '1,1');
  });

  test('concurrent lookups share one request and reuse successful cache',
      () async {
    catalogGate = Completer<void>();
    final first = site.resolveRoomCategory(_room('1010026'));
    final second = site.resolveRoomCategory(_room('101'));
    await Future<void>.delayed(Duration.zero);
    catalogGate!.complete();
    expect((await first)?.id, '1010026,1');
    expect((await second)?.id, '101,4');
    await site.resolveRoomCategory(_room('1010026'));
    expect(requests, hasLength(1));
  });

  test('failed lookup is a CoreError and does not poison the cache', () async {
    failCatalog = true;
    await expectLater(
        site.resolveRoomCategory(_room('1010026')), throwsA(isA<CoreError>()));
    failCatalog = false;
    expect((await site.resolveRoomCategory(_room('1010026')))?.id, '1010026,1');
    expect(requests, hasLength(2));
  });

  test('empty catalog is rejected and can be retried', () async {
    catalog.clear();
    await expectLater(
        site.resolveRoomCategory(_room('101')), throwsA(isA<CoreError>()));
    catalog.add(_node('101', 4, '聊天'));
    expect((await site.resolveRoomCategory(_room('101')))?.id, '101,4');
  });

  test('category request uses injected signer and exact paging parameters',
      () async {
    var signCount = 0;
    site = DouyinSite(abogusSigner: (url, _) {
      signCount++;
      return url;
    });
    await site.getCategoryRooms(
        LiveSubCategory(id: '1010026,1', name: '绝地求生', parentId: '1,1'),
        page: 3);
    expect(signCount, 1);
    expect(requests.single.uri.queryParameters,
        containsPair('partition', '1010026'));
    expect(requests.single.uri.queryParameters,
        containsPair('partition_type', '1'));
    expect(requests.single.uri.queryParameters, containsPair('offset', '30'));
  });

  for (final id in ['101', '101,', ',1', '101,x', '101,1,4', '0,1']) {
    test('invalid category $id fails before network access', () async {
      await expectLater(
          site.getCategoryRooms(
              LiveSubCategory(id: id, name: '分区', parentId: id)),
          throwsA(isA<CoreError>()));
      expect(requests, isEmpty);
    });
  }
}

Map<String, dynamic> _node(String id, int type, String name,
        [List<Map<String, dynamic>> children = const []]) =>
    {
      'partition': {'id_str': id, 'type': type, 'title': name},
      'sub_partition': children,
    };

LiveRoomDetail _room(String? id, {String? parent}) => LiveRoomDetail(
      roomId: 'room',
      title: '房间',
      cover: '',
      userName: '主播',
      userAvatar: '',
      online: 0,
      status: true,
      url: '',
      categoryId: id,
      categoryName: '分区',
      categoryParentId: parent,
      categoryParentName: '父分区',
    );
