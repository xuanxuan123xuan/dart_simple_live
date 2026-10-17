import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_detail_loader.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';

void main() {
  test('failed entry keeps its anchor identifier for refresh', () async {
    final site = _RecordingDouyinSite()..failure = CoreError('temporary');
    final loader = LiveRoomDetailLoader(
      site: site,
      roomId: 'old-room',
      douyinSecUserId: ' share-anchor ',
    );

    await expectLater(
      loader.load(site: site, roomId: 'old-room'),
      throwsA(isA<CoreError>()),
    );
    site.failure = null;
    await loader.load(site: site, roomId: 'old-room');

    expect(site.calls, [
      ('old-room', 'share-anchor'),
      ('old-room', 'share-anchor'),
    ]);
  });

  test('switching rooms discards the old anchor even when returning', () async {
    final site = _RecordingDouyinSite();
    final loader = LiveRoomDetailLoader(
      site: site,
      roomId: 'old-room',
      douyinSecUserId: 'share-anchor',
    );

    await loader.load(site: site, roomId: 'new-room');
    await loader.load(site: site, roomId: 'old-room');

    expect(site.calls, [('new-room', null), ('old-room', null)]);
  });

  test('switching sites cannot reuse an anchor for an identical room ID',
      () async {
    final site = _RecordingDouyinSite();
    final otherSite = _OtherSite();
    final loader = LiveRoomDetailLoader(
      site: site,
      roomId: 'same-room',
      douyinSecUserId: 'share-anchor',
    );

    await loader.load(site: otherSite, roomId: 'same-room');
    await loader.load(site: site, roomId: 'same-room');

    expect(otherSite.calls, ['same-room']);
    expect(site.calls, [('same-room', null)]);
  });

  test('resolving a stable room ID discards the share identifier', () async {
    final site = _RecordingDouyinSite()..resolvedRoomId = 'stable-room';
    final loader = LiveRoomDetailLoader(
      site: site,
      roomId: 'old-room',
      douyinSecUserId: 'share-anchor',
    );

    final detail = await loader.load(site: site, roomId: 'old-room');
    await loader.load(site: site, roomId: detail.roomId);
    await loader.load(site: site, roomId: 'old-room');

    expect(site.calls, [
      ('old-room', 'share-anchor'),
      ('stable-room', null),
      ('old-room', null),
    ]);
  });

  test('clearing entry context takes effect before the next room load',
      () async {
    final site = _RecordingDouyinSite();
    final loader = LiveRoomDetailLoader(
      site: site,
      roomId: 'room',
      douyinSecUserId: 'share-anchor',
    );

    loader.clearDouyinShareContext();
    await loader.load(site: site, roomId: 'room');

    expect(site.calls, [('room', null)]);
  });

  test('an empty share identifier preserves ordinary room loading', () async {
    final site = _RecordingDouyinSite();
    final loader = LiveRoomDetailLoader(
      site: site,
      roomId: 'room',
      douyinSecUserId: '  ',
    );

    await loader.load(site: site, roomId: 'room');

    expect(site.calls, [('room', null)]);
  });

  test('Xiaohongshu host follows the resolved room and clears on room switch',
      () async {
    final site = _RecordingXiaohongshuSite()..resolvedRoomId = 'B';
    final loader = LiveRoomDetailLoader(
      site: site,
      roomId: 'A',
      xiaohongshuHostId: '5eafa4cc0000000001005613',
    );

    await loader.load(site: site, roomId: 'A');
    await loader.load(site: site, roomId: 'B');
    await loader.load(site: site, roomId: 'other');

    expect(site.calls, [
      ('A', '5eafa4cc0000000001005613'),
      ('B', '5eafa4cc0000000001005613'),
      ('other', null),
    ]);
  });

  test('Xiaohongshu delayed detail cannot restore cleared host context',
      () async {
    final pending = Completer<LiveRoomDetail>();
    final site = _RecordingXiaohongshuSite()..pendingDetail = pending;
    final loader = LiveRoomDetailLoader(
      site: site,
      roomId: 'A',
      xiaohongshuHostId: '5eafa4cc0000000001005613',
    );

    final oldLoad = loader.load(site: site, roomId: 'A');
    loader.clearXiaohongshuShareContext();
    site.pendingDetail = null;
    pending.complete(site.detailFor('A'));
    await oldLoad;
    await loader.load(site: site, roomId: 'A');

    expect(site.calls, [
      ('A', '5eafa4cc0000000001005613'),
      ('A', null),
    ]);
  });

  testWidgets('share anchor reaches the HTTP request through navigation',
      (tester) async {
    const roomId = '7696440023213673256';
    const webRid = '3010151431';
    const secUserId = 'MS4w.share-anchor_1';
    final previousSite = Sites.allSites[Constant.kDouyin]!;
    final site = Site(
      id: Constant.kDouyin,
      name: '抖音直播',
      logo: '',
      liveSite: DouyinSite(abogusSigner: (url, _) => url),
    );
    Sites.allSites[Constant.kDouyin] = site;
    final requests = <RequestOptions>[];
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      final reflow = options.uri.path.contains('/reflow/info/');
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'status_code': 0,
          'data': reflow
              ? {
                  'room': {
                    'status': 4,
                    'owner': {'web_rid': webRid},
                  },
                }
              : {
                  'data': [],
                  'user': {
                    'id_str': 'anchor-id',
                    'nickname': '主播',
                    'live_status': 0,
                  },
                },
        },
      ));
    });
    HttpClient.instance.dio.interceptors.add(interceptor);
    addTearDown(() {
      HttpClient.instance.dio.interceptors.remove(interceptor);
      Sites.allSites[Constant.kDouyin] = previousSite;
      Get.reset();
    });
    final target = (await LiveRoomLinkParser().parse(
      'https://webcast.amemv.com/douyin/webcast/reflow/$roomId'
      '?sec_user_id=MS4w%2Eshare-anchor_1',
    ))!;
    late Future<LiveRoomDetail> detailRequest;
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const SizedBox()),
        GetPage(
          name: RoutePath.kLiveRoomDetail,
          binding: BindingsBuilder(() {
            final args = Get.arguments as Map<String, dynamic>;
            final routeSite = args['site'] as Site;
            final routeRoomId = Get.parameters['roomId']!;
            detailRequest = LiveRoomDetailLoader(
              site: routeSite.liveSite,
              roomId: routeRoomId,
              douyinSecUserId: args['douyinSecUserId'] as String?,
            ).load(site: routeSite.liveSite, roomId: routeRoomId);
          }),
          page: () => const SizedBox(),
        ),
      ],
    ));
    unawaited(AppNavigator.toLiveRoomDetail(
      site: target.site,
      roomId: target.roomId,
      douyinSecUserId: target.douyinSecUserId,
    ));
    await tester.pumpAndSettle();

    final detail = await detailRequest;
    expect(detail.roomId, webRid);
    expect(requests, hasLength(2));
    expect(requests.first.uri.queryParameters['room_id'], roomId);
    expect(requests.first.uri.queryParameters['sec_user_id'], secUserId);
    expect(requests.last.uri.queryParameters['web_rid'], webRid);
    Get.back();
    await tester.pumpAndSettle();
  });

  testWidgets('navigation omits share metadata for other platforms',
      (tester) async {
    addTearDown(Get.reset);
    Map<String, dynamic>? captured;
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const SizedBox()),
        GetPage(
          name: RoutePath.kLiveRoomDetail,
          binding: BindingsBuilder(() {
            captured = Get.arguments as Map<String, dynamic>;
          }),
          page: () => const SizedBox(),
        ),
      ],
    ));
    unawaited(AppNavigator.toLiveRoomDetail(
      site: Sites.allSites[Constant.kHuya]!,
      roomId: 'navigation-room',
      douyinSecUserId: 'share-anchor',
    ));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.containsKey('douyinSecUserId'), isFalse);
    Get.back();
    await tester.pumpAndSettle();
  });
}

class _RecordingDouyinSite extends DouyinSite {
  final calls = <(String, String?)>[];
  CoreError? failure;
  String? resolvedRoomId;

  @override
  Future<LiveRoomDetail> getRoomDetail({
    required String roomId,
    String? secUserId,
  }) async {
    calls.add((roomId, secUserId));
    if (failure != null) throw failure!;
    return _detail(resolvedRoomId ?? roomId);
  }
}

class _OtherSite extends Fake implements LiveSite {
  final calls = <String>[];

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    calls.add(roomId);
    return _detail(roomId);
  }
}

class _RecordingXiaohongshuSite extends XiaohongshuSite {
  final calls = <(String, String?)>[];
  String? resolvedRoomId;
  Completer<LiveRoomDetail>? pendingDetail;

  LiveRoomDetail detailFor(String roomId) => LiveRoomDetail(
        roomId: resolvedRoomId ?? roomId,
        title: 'title',
        cover: '',
        userName: 'anchor',
        userAvatar: '',
        online: 0,
        status: true,
        liveStatusState: LiveStatusState.live,
        url: 'https://www.xiaohongshu.com/livestream/$roomId',
        data: XiaohongshuRoomSnapshot(
          roomId: resolvedRoomId ?? roomId,
          title: 'title',
          cover: '',
          userName: 'anchor',
          userAvatar: '',
          online: 0,
          live: true,
          liveStatus: 'success',
          roomStatus: 1,
          streams: const [],
          url: 'https://www.xiaohongshu.com/livestream/$roomId',
          hostId: '5eafa4cc0000000001005613',
        ),
      );

  @override
  Future<LiveRoomDetail> getRoomDetail({
    required String roomId,
    String? hostId,
  }) {
    calls.add((roomId, hostId));
    return pendingDetail?.future ?? Future.value(detailFor(roomId));
  }
}

LiveRoomDetail _detail(String roomId) => LiveRoomDetail(
      roomId: roomId,
      title: 'title',
      cover: '',
      userName: 'anchor',
      userAvatar: '',
      online: 0,
      status: false,
      url: 'https://example.com/$roomId',
    );
