import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/models/db/history.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_tv_app/services/current_room_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';

class _TestSettings extends AppSettingsController {
  @override
  // Tests use the default values without opening local storage.
  // ignore: must_call_super
  void onInit() {}
}

class _EmptyFollowBox implements Box<FollowUser> {
  @override
  FollowUser? get(dynamic key, {FollowUser? defaultValue}) => defaultValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDB extends DBService {
  _TestDB() {
    followBox = _EmptyFollowBox();
  }

  @override
  bool getFollowExist(String id) => false;

  @override
  History? getHistory(String id) => null;

  @override
  Future<void> addOrUpdateHistory(History history) async {}
}

class _TestFollowService extends FollowUserService {
  @override
  // No database or timers are needed for channel selection.
  // ignore: must_call_super
  void onInit() {}
}

class _ScriptedSite extends LiveSite {
  _ScriptedSite({this.urlCount = 2});

  final int urlCount;
  int detailCalls = 0;
  int qualityCalls = 0;
  int urlCalls = 0;
  int statusCalls = 0;
  final Queue<Future<LiveStatusState> Function()> statusResults = Queue();
  Future<LiveRoomDetail> Function(String roomId, int call)? detailResponse;
  Future<List<LivePlayQuality>> Function(LiveRoomDetail detail, int call)?
      qualityResponse;
  Future<LivePlayUrl> Function(LiveRoomDetail detail, int call)? urlResponse;

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) {
    final call = ++detailCalls;
    return detailResponse?.call(roomId, call) ??
        Future.value(_detail(roomId, title: 'detail-$call'));
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) {
    final call = ++qualityCalls;
    return qualityResponse?.call(detail, call) ??
        Future.value([LivePlayQuality(quality: 'HD', data: 1)]);
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) {
    final call = ++urlCalls;
    return urlResponse?.call(detail, call) ??
        Future.value(_urls(detail.title, call, urlCount));
  }

  @override
  Future<LiveStatusState> getLiveStatusState({required String roomId}) {
    statusCalls++;
    return statusResults.isEmpty
        ? Future.value(LiveStatusState.live)
        : statusResults.removeFirst()();
  }
}

LiveRoomDetail _detail(
  String roomId, {
  required String title,
  LiveStatusState status = LiveStatusState.live,
}) =>
    LiveRoomDetail(
      roomId: roomId,
      title: title,
      cover: '',
      userName: 'anchor',
      userAvatar: '',
      online: 1,
      status: status == LiveStatusState.live,
      liveStatusState: status,
      url: '',
    );

LivePlayUrl _urls(String title, int call, int count) => LivePlayUrl(
      urls: [
        for (var line = 1; line <= count; line++)
          'https://test/$title/$call/$line'
      ],
    );

Site _site(String id, LiveSite liveSite) => Site(
      id: id,
      name: id,
      logo: '',
      liveSite: liveSite,
      index: 0,
    );

class _TestRoomController extends LiveRoomController {
  _TestRoomController({required super.pSite, required super.pRoomId});

  final List<String> opened = [];
  int openFailuresRemaining = 0;
  int retryWaits = 0;
  int confirmationWaits = 0;
  bool interceptRoomSwitch = false;
  String? switchedTo;

  @override
  Future<void> resetRoom(Site site, String roomId) async {
    if (interceptRoomSwitch) {
      switchedTo = '${site.id}_$roomId';
      return;
    }
    await super.resetRoom(site, roomId);
  }

  @override
  Future<void> initializePlayer() async {}

  @override
  Future<void> openPlayerMedia(Media media) async {
    if (openFailuresRemaining > 0) {
      openFailuresRemaining--;
      throw StateError('open failed');
    }
    opened.add(media.uri.toString());
  }

  @override
  Future<void> setPlayerVolume(double volume) async {}

  @override
  Future<void> stopCurrentPlayer() async {}

  @override
  Future<void> disposePlayer() async {}

  @override
  Future<void> resetSystem() async {}

  @override
  Future<void> waitForPlaybackRetry() async {
    retryWaits++;
  }

  @override
  Future<void> waitForOfflineConfirmation() async {
    confirmationWaits++;
  }

  bool observeProgress(DateTime now, Duration position) {
    return observePlaybackProgress(
      now: now,
      generation: playbackGeneration,
      source: '${site.id}|$roomId|$currentQuality|$currentLineIndex',
      position: position,
      playing: true,
      buffering: false,
      completed: false,
    );
  }
}

Future<void> _exhaustOneLine(_TestRoomController controller) async {
  await controller.mediaEnd();
  await controller.mediaEnd();
  await controller.mediaEnd();
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_TestSettings());
    Get.put<CurrentRoomService>(CurrentRoomService());
    Get.put<DBService>(_TestDB());
  });

  tearDown(Get.reset);

  test(
      'each line gets two fresh URL retries; exhaustion ignores duplicate events',
      () async {
    final liveSite = _ScriptedSite();
    liveSite.statusResults
      ..add(() async => LiveStatusState.offline)
      ..add(() async => LiveStatusState.offline);
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, liveSite),
      pRoomId: '1',
    );
    await controller.loadData();
    expect(controller.opened, hasLength(1));

    await _exhaustOneLine(controller);
    expect(controller.currentLineIndex, 1);
    expect(controller.mediaErrorRetryCount, 0);
    expect(liveSite.urlCalls, 3);
    expect(controller.retryWaits, 1);

    await _exhaustOneLine(controller);
    expect(liveSite.urlCalls, 5);
    expect(controller.retryWaits, 2);
    expect(liveSite.statusCalls, 2);
    expect(controller.confirmationWaits, 1);
    expect(controller.roomLiveState.value, LiveStatusState.offline);
    expect(controller.liveStatus.value, isFalse);
    expect(controller.playbackLoadError.value, isEmpty);

    final opensAtExhaustion = controller.opened.length;
    await controller.mediaEnd();
    await controller.mediaError('duplicate');
    expect(controller.opened.length, opensAtExhaustion);
    expect(liveSite.statusCalls, 2);

    await controller.changePlayLine(0);
    await controller.mediaEnd();
    expect(controller.mediaErrorRetryCount, 1);
    expect(liveSite.urlCalls, 6);
  });

  test(
      'offline requires two checks; live, unknown, and failed checks show retry',
      () async {
    for (final result in <List<Future<LiveStatusState> Function()>>[
      [
        () async => LiveStatusState.offline,
        () async => LiveStatusState.live,
      ],
      [() async => LiveStatusState.unknown],
      [() async => throw StateError('network')],
    ]) {
      final liveSite = _ScriptedSite(urlCount: 1);
      liveSite.statusResults.addAll(result);
      final controller = _TestRoomController(
        pSite: _site(Constant.kDouyu, liveSite),
        pRoomId: '1',
      );
      await controller.loadData();
      await _exhaustOneLine(controller);

      expect(controller.roomLiveState.value, isNot(LiveStatusState.offline));
      expect(controller.playbackLoadError.value, isNotEmpty);
      if (result.length == 2) {
        expect(controller.roomLiveState.value, LiveStatusState.live);
        expect(controller.playbackLoadError.value, '直播流已中断，请重试或切换线路');
        expect(controller.confirmationWaits, 1);
      } else {
        expect(controller.roomLiveState.value, LiveStatusState.unknown);
        expect(controller.playbackLoadError.value, '播放恢复失败，暂时无法确认直播状态');
      }
    }
  });

  test(
      'non-Douyu completion retains live-end behavior and offline overlay state',
      () async {
    final liveSite = _ScriptedSite(urlCount: 1);
    final controller = _TestRoomController(
      pSite: _site(Constant.kBiliBili, liveSite),
      pRoomId: '1',
    );
    await controller.loadData();
    await _exhaustOneLine(controller);
    expect(controller.roomLiveState.value, LiveStatusState.offline);
    expect(controller.liveStatus.value, isFalse);
    expect(liveSite.statusCalls, 0);
    expect(liveSite.urlCalls, 1);
  });

  test('refresh rejects old media events and old detail/quality responses',
      () async {
    final liveSite = _ScriptedSite(urlCount: 1);
    final oldQuality = Completer<List<LivePlayQuality>>();
    liveSite.qualityResponse = (detail, call) => call == 2
        ? oldQuality.future
        : Future.value([LivePlayQuality(quality: 'HD', data: 1)]);
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, liveSite),
      pRoomId: '1',
    );
    await controller.loadData();
    final oldLoad = controller.loadData();
    await Future<void>.delayed(Duration.zero);
    expect(liveSite.qualityCalls, 2);
    final freshLoad = controller.loadData();
    await controller.mediaEnd();
    await freshLoad;
    final freshUrl = controller.playUrls.single;
    oldQuality.complete([LivePlayQuality(quality: 'stale', data: 0)]);
    await oldLoad;
    expect(controller.detail.value!.title, 'detail-3');
    expect(controller.playUrls.single, freshUrl);
    expect(controller.currentQualityInfo.value, 'HD');
    expect(controller.mediaErrorRetryCount, 0);
    expect(liveSite.urlCalls, 2);
  });

  test('manual URL request supersedes an in-flight recovery CDN response',
      () async {
    final liveSite = _ScriptedSite(urlCount: 1);
    final staleCdn = Completer<LivePlayUrl>();
    liveSite.urlResponse = (detail, call) => call == 2
        ? staleCdn.future
        : Future.value(_urls(detail.title, call, 1));
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, liveSite),
      pRoomId: '1',
    );
    await controller.loadData();
    final recovery = controller.mediaEnd();
    await Future<void>.delayed(Duration.zero);
    expect(liveSite.urlCalls, 2);

    final manual = controller.getPlayUrl();
    await Future<void>.delayed(Duration.zero);
    expect(liveSite.urlCalls, 3);
    staleCdn.complete(_urls('stale', 2, 1));
    await recovery;
    await manual;
    expect(controller.playUrls.single, contains('/3/1'));
    expect(controller.opened.last, contains('/3/1'));
    expect(controller.mediaErrorRetryCount, 0);
  });

  test('failed and unknown detail loads show retry and never mark offline',
      () async {
    final liveSite = _ScriptedSite(urlCount: 1);
    liveSite.detailResponse = (roomId, call) => call == 1
        ? Future.value(
            _detail(roomId, title: 'unknown', status: LiveStatusState.unknown))
        : Future.error(StateError('detail failed'));
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, liveSite),
      pRoomId: '1',
    );
    await controller.loadData();
    expect(controller.roomLiveState.value, LiveStatusState.unknown);
    expect(controller.playbackLoadError.value, isNotEmpty);
    expect(liveSite.urlCalls, 0);
    await controller.loadData();
    expect(controller.roomLiveState.value, LiveStatusState.unknown);
    expect(controller.playbackLoadError.value, contains('加载直播间失败'));
    await controller.mediaEnd();
    expect(liveSite.statusCalls, 0);
  });

  test('30 seconds of real progress rearms a direct recovery round', () async {
    final liveSite = _ScriptedSite(urlCount: 1);
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, liveSite),
      pRoomId: '1',
    );
    await controller.loadData();
    await _exhaustOneLine(controller);
    expect(controller.playbackLoadError.value, isNotEmpty);
    final statusCallsAtExhaustion = liveSite.statusCalls;

    final start = DateTime(2026, 1, 1);
    expect(controller.observeProgress(start, Duration.zero), isFalse);
    expect(
      controller.observeProgress(
        start.add(const Duration(seconds: 20)),
        Duration.zero,
      ),
      isFalse,
    );
    expect(controller.mediaErrorRetryCount, 2);
    controller.observeProgress(
      start.add(const Duration(seconds: 21)),
      const Duration(seconds: 1),
    );
    controller.observeProgress(
      start.add(const Duration(seconds: 50)),
      const Duration(seconds: 30),
    );
    expect(controller.playbackLoadError.value, isNotEmpty);
    controller.observeProgress(
      start.add(const Duration(seconds: 51)),
      const Duration(seconds: 31),
    );
    expect(controller.playbackLoadError.value, isEmpty);
    expect(controller.mediaErrorRetryCount, 0);
    await controller.mediaEnd();
    expect(controller.mediaErrorRetryCount, 1);
    expect(liveSite.statusCalls, statusCallsAtExhaustion);
  });

  test('player.open exceptions still exhaust into status confirmation',
      () async {
    final liveSite = _ScriptedSite(urlCount: 1);
    final statusQueried = Completer<void>();
    liveSite.statusResults.add(() {
      statusQueried.complete();
      return Future.value(LiveStatusState.live);
    });
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, liveSite),
      pRoomId: '1',
    )..openFailuresRemaining = 3;
    await controller.loadData();
    await statusQueried.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    expect(liveSite.urlCalls, 3);
    expect(controller.roomLiveState.value, LiveStatusState.live);
    expect(controller.playbackLoadError.value, '直播流已中断，请重试或切换线路');
  });

  test('late live-status response cannot change refreshed room state',
      () async {
    final liveSite = _ScriptedSite(urlCount: 1);
    final oldStatus = Completer<LiveStatusState>();
    liveSite.statusResults.add(() => oldStatus.future);
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, liveSite),
      pRoomId: '1',
    );
    await controller.loadData();
    await controller.mediaEnd();
    await controller.mediaEnd();
    final exhausted = controller.mediaEnd();
    await Future<void>.delayed(Duration.zero);
    expect(liveSite.statusCalls, 1);

    await controller.refreshRoom();
    final refreshedDetail = controller.detail.value;
    oldStatus.complete(LiveStatusState.offline);
    await exhausted;
    expect(controller.detail.value, same(refreshedDetail));
    expect(controller.roomLiveState.value, LiveStatusState.live);
    expect(controller.playbackLoadError.value, isEmpty);
  });

  test('resetRoom rejects old detail and URL responses', () async {
    final oldSite = _ScriptedSite(urlCount: 1);
    final pendingDetail = Completer<LiveRoomDetail>();
    oldSite.detailResponse = (roomId, call) => pendingDetail.future;
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, oldSite),
      pRoomId: 'old',
    );
    final oldLoad = controller.loadData();
    final middleSite = _ScriptedSite(urlCount: 1);
    await controller.resetRoom(_site(Constant.kBiliBili, middleSite), 'middle');
    pendingDetail.complete(_detail('old', title: 'stale-detail'));
    await oldLoad;
    expect(controller.detail.value!.roomId, 'middle');

    final pendingUrl = Completer<LivePlayUrl>();
    middleSite.urlResponse = (detail, call) => pendingUrl.future;
    final pendingLoad = controller.loadData();
    await Future<void>.delayed(Duration.zero);
    final currentSite = _ScriptedSite(urlCount: 1);
    await controller.resetRoom(_site(Constant.kHuya, currentSite), 'current');
    pendingUrl.complete(_urls('stale-url', 9, 1));
    await pendingLoad;
    expect(controller.detail.value!.roomId, 'current');
    expect(controller.playUrls.single, isNot(contains('stale-url')));
  });

  test('resetRoom and onClose reject late live-status responses', () async {
    final oldSite = _ScriptedSite(urlCount: 1);
    final pendingStatus = Completer<LiveStatusState>();
    oldSite.statusResults.add(() => pendingStatus.future);
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, oldSite),
      pRoomId: 'old',
    );
    await controller.loadData();
    await controller.mediaEnd();
    await controller.mediaEnd();
    final exhausted = controller.mediaEnd();
    await Future<void>.delayed(Duration.zero);
    expect(oldSite.statusCalls, 1);
    await controller.resetRoom(
      _site(Constant.kBiliBili, _ScriptedSite(urlCount: 1)),
      'new',
    );
    pendingStatus.complete(LiveStatusState.offline);
    await exhausted;
    expect(controller.roomId, 'new');
    expect(controller.roomLiveState.value, LiveStatusState.live);

    final closingSite = _ScriptedSite(urlCount: 1);
    final closingStatus = Completer<LiveStatusState>();
    closingSite.statusResults.add(() => closingStatus.future);
    final closingController = _TestRoomController(
      pSite: _site(Constant.kDouyu, closingSite),
      pRoomId: 'closing',
    );
    await closingController.loadData();
    await closingController.mediaEnd();
    await closingController.mediaEnd();
    final closingExhausted = closingController.mediaEnd();
    await Future<void>.delayed(Duration.zero);
    closingController.onClose();
    closingStatus.complete(LiveStatusState.offline);
    await closingExhausted;
    expect(closingController.roomLiveState.value, LiveStatusState.live);
  });

  test('onClose rejects a pending room detail response', () async {
    final pendingDetail = Completer<LiveRoomDetail>();
    final liveSite = _ScriptedSite(urlCount: 1)
      ..detailResponse = (roomId, call) => pendingDetail.future;
    final controller = _TestRoomController(
      pSite: _site(Constant.kDouyu, liveSite),
      pRoomId: '1',
    );
    final load = controller.loadData();
    controller.onClose();
    pendingDetail.complete(_detail('1', title: 'late'));
    await load;
    expect(controller.detail.value, isNull);
    expect(controller.playUrls, isEmpty);
  });

  test('auto-switch follows playback-failure and confirmed-live-end settings',
      () async {
    final settings = AppSettingsController.instance;
    settings.autoSwitchNextOnLiveEnd.value = true;
    settings.autoSwitchNextOnPlaybackFailure.value = false;
    final follows = Get.put<FollowUserService>(_TestFollowService());
    follows.livingList.addAll([
      FollowUser(
        id: '${Constant.kDouyu}_1',
        siteId: Constant.kDouyu,
        roomId: '1',
        userName: 'current',
        face: '',
        addTime: DateTime(2026),
      ),
      FollowUser(
        id: '${Constant.kBiliBili}_2',
        siteId: Constant.kBiliBili,
        roomId: '2',
        userName: 'next',
        face: '',
        addTime: DateTime(2026),
      ),
    ]);
    final originalTarget = Sites.allSites[Constant.kBiliBili]!;
    Sites.allSites[Constant.kBiliBili] =
        _site(Constant.kBiliBili, _ScriptedSite(urlCount: 1));
    try {
      final liveSite = _ScriptedSite(urlCount: 1);
      final controller = _TestRoomController(
        pSite: _site(Constant.kDouyu, liveSite),
        pRoomId: '1',
      )..interceptRoomSwitch = true;
      await controller.loadData();
      await _exhaustOneLine(controller);
      expect(controller.switchedTo, isNull);

      settings.autoSwitchNextOnPlaybackFailure.value = true;
      await controller.changePlayLine(0);
      await _exhaustOneLine(controller);
      expect(controller.switchedTo, '${Constant.kBiliBili}_2');

      settings.autoSwitchNextOnPlaybackFailure.value = false;
      final offlineSite = _ScriptedSite(urlCount: 1);
      offlineSite.statusResults
        ..add(() async => LiveStatusState.offline)
        ..add(() async => LiveStatusState.offline);
      final offlineController = _TestRoomController(
        pSite: _site(Constant.kDouyu, offlineSite),
        pRoomId: '1',
      )..interceptRoomSwitch = true;
      await offlineController.loadData();
      await _exhaustOneLine(offlineController);
      expect(offlineController.switchedTo, '${Constant.kBiliBili}_2');
    } finally {
      Sites.allSites[Constant.kBiliBili] = originalTarget;
    }
  });
}
