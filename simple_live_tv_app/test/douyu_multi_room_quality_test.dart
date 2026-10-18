import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_playback_intent.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_player_controller.dart';

class _Settings extends AppSettingsController {
  @override
  // No local-storage initialization is needed for controller tests.
  // ignore: must_call_super
  void onInit() {}
}

class _Streams implements PlayerStream {
  final errors = StreamController<String>.broadcast();
  final completions = StreamController<bool>.broadcast();

  @override
  Stream<String> get error => errors.stream;
  @override
  Stream<bool> get completed => completions.stream;
  @override
  Stream<PlayerLog> get log => const Stream<PlayerLog>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  @override
  final _Streams stream = _Streams();
  final opened = <String>[];
  final openPlayModes = <bool>[];
  int playCalls = 0;
  int pauseCalls = 0;
  final volumes = <double>[];
  Completer<void>? openGate;
  bool emitPreviousEventsOnOpen = false;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((playable as Media).uri);
    openPlayModes.add(play);
    await openGate?.future;
    if (emitPreviousEventsOnOpen) {
      stream.errors.add('late previous-source error');
      stream.completions.add(true);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {
    await stream.errors.close();
    await stream.completions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Site extends LiveSite {
  int calls = 0;
  bool failDanmaku = false;

  @override
  LiveDanmaku getDanmaku() {
    if (failDanmaku) throw StateError('signing failed');
    return LiveDanmaku();
  }

  Completer<LivePlayUrl>? gate;
  final requestedRates = <int>[];

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async =>
      LiveRoomDetail(
          roomId: roomId,
          title: 'test',
          cover: '',
          userName: '',
          userAvatar: '',
          online: 1,
          status: true,
          url: '');

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
          {required LiveRoomDetail detail}) async =>
      [LivePlayQuality(quality: '原画', data: 0)];

  LivePlayUrl urls(String name) => LivePlayUrl(
        urls: [
          'https://example.test/$calls/one',
          'https://example.test/$calls/two'
        ],
        actualQuality: LivePlayQuality(quality: name, data: null),
      );

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    calls++;
    requestedRates.add(quality.data as int);
    return gate == null ? urls('蓝光4M') : await gate!.future;
  }
}

class _Controller extends MultiRoomPlayerController {
  _Controller(super.item, this._testPlayer);
  final _Player _testPlayer;
  @override
  _Player get player => _testPlayer;
}

void main() {
  late _Site site;
  late _Player player;
  late _Controller controller;

  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_Settings());
    site = _Site();
    player = _Player();
    controller = _Controller(
      MultiRoomItem(
          site:
              Site(id: 'douyu', name: '斗鱼', logo: '', liveSite: site, index: 0),
          roomId: '1',
          userName: 'test',
          face: ''),
      player,
    );
  });

  tearDown(() async {
    await controller.closePlaybackSession();
    Get.reset();
  });

  test('multi-room keeps original request while showing fallback and recovery',
      () async {
    await controller.load();
    expect(controller.qualityInfo.value, '蓝光4M');
    expect(controller.requestedQualityInfo.value, '原画');
    expect(controller.qualityDisplayInfo, contains('实际 蓝光4M'));
    site.gate = Completer<LivePlayUrl>();
    final refresh = controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(controller.qualityInfo.value, '蓝光4M');
    site.gate!.complete(site.urls('原画'));
    await refresh;
    expect(controller.qualityInfo.value, '原画');
    expect(site.requestedRates, [0, 0]);
  });

  test('events queued by previous media during reopen cannot switch new lines',
      () async {
    await controller.load();
    player.emitPreviousEventsOnOpen = true;
    await controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(player.opened, hasLength(2));
    expect(controller.lineInfo.value, '线路 1/2');
    expect(controller.errorText.value, isEmpty);
  });

  test('an older load cannot replace the active actual quality or URLs',
      () async {
    site.gate = Completer<LivePlayUrl>();
    final pending = site.gate!;
    final oldLoad = controller.load();
    while (site.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    site.gate = null;
    await controller.load();
    pending.complete(site.urls('stale quality'));
    await oldLoad;
    expect(controller.qualityInfo.value, '蓝光4M');
    expect(player.opened, hasLength(1));
  });

  test('a pause during native open is not undone when open completes late',
      () async {
    player.openGate = Completer<void>();
    final loading = controller.load();
    while (player.opened.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }

    final pause = controller.setUserPaused(true);
    player.openGate!.complete();
    await Future.wait([loading, pause]);

    expect(player.openPlayModes, [false]);
    expect(player.playCalls, 0);
    expect(player.pauseCalls, greaterThan(0));
    expect(controller.userPaused.value, isTrue);
  });
  test('scheduled account reload immediately rejects old account result',
      () async {
    site.gate = Completer<LivePlayUrl>();
    final oldLoad = controller.load();
    while (site.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    controller.markLoadScheduled();
    site.gate!.complete(site.urls('old account'));
    await oldLoad;
    expect(player.opened, isEmpty);
    expect(controller.qualityInfo.value, isEmpty);
    site.gate = null;
    await controller.load();
    expect(player.opened, hasLength(1));
  });

  test('danmaku construction failure leaves playable video intact', () async {
    site.failDanmaku = true;
    await controller.setDanmakuActive(true);
    await controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(site.calls, 1);
    expect(player.playCalls, 1);
    expect(controller.liveStatus.value, isTrue);
    expect(controller.errorText.value, isEmpty);
  });

  test('resume after pause during open binds recovery to resumed media',
      () async {
    player.openGate = Completer<void>();
    final loading = controller.load();
    while (player.opened.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final pause = controller.setUserPaused(true);
    player.openGate!.complete();
    await Future.wait([loading, pause]);
    await controller.setUserPaused(false);
    expect(player.playCalls, 1);
    player.stream.completions.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(player.opened, hasLength(3));
  });

  test('background resume rebinds completion recovery', () async {
    await controller.load();
    controller.suspend(TvPlaybackSuspension.background);
    controller.resume(TvPlaybackSuspension.background);
    await Future<void>.delayed(Duration.zero);
    player.stream.completions.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(player.opened, hasLength(3));
  });

  test('memory release rejects URL response still in flight', () async {
    site.gate = Completer<LivePlayUrl>();
    final loading = controller.load();
    while (site.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.releaseForMemoryPressure();
    site.gate!.complete(site.urls('released'));
    await loading;
    expect(controller.isReleasedForMemory, isTrue);
    expect(player.opened, isEmpty);
    expect(player.playCalls, 0);
  });

  test('rapid audio selection and secondary volume keep one audible source',
      () async {
    final otherPlayer = _Player();
    final other = _Controller(
        MultiRoomItem(
          site: controller.item.site,
          roomId: '2',
          userName: 'other',
          face: '',
        ),
        otherPlayer);
    final parent = MultiRoomController([]);
    parent.sessions
        .addAll({controller.item.key: controller, other.item.key: other});
    parent.rooms.addAll([controller.item, other.item]);
    parent.mainRoomKey.value = controller.item.key;
    await Future.wait([
      parent.setAudioEnabled(controller.item.key, true),
      parent.setAudioEnabled(other.item.key, true),
      parent.changeRoomVolume(controller.item, 8),
    ]);
    expect(parent.audioRoomKeys, {controller.item.key});
    expect(controller.muted.value, isFalse);
    expect(other.muted.value, isTrue);
    expect(otherPlayer.volumes.last, 0);
    expect(player.volumes.last, 80);
    await other.closePlaybackSession();
  });
}
