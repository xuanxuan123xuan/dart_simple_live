import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
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
  bool emitPreviousEventsOnOpen = false;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((playable as Media).uri);
    if (emitPreviousEventsOnOpen) {
      stream.errors.add('late previous-source error');
      stream.completions.add(true);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double volume) async {}
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
    controller.onClose();
    await Future<void>.delayed(Duration.zero);
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
    expect(controller.lineInfo.value, '线路1');
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
}
