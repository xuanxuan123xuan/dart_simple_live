import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _Settings extends AppSettingsController {
  @override
  // No local-storage initialization is needed for controller tests.
  // ignore: must_call_super
  void onInit() {}
}

class _Streams implements PlayerStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  @override
  final _Streams stream = _Streams();
  @override
  PlatformPlayer? platform;
  final opened = <String>[];
  int stops = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((playable as Media).uri);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LivePlayQuality _quality(String name, int rate) =>
    LivePlayQuality(quality: name, data: rate);

class _Site extends LiveSite {
  List<LivePlayQuality> qualities = [
    _quality('原画', 0),
    _quality('蓝光4M', 4),
    _quality('流畅', 2),
  ];
  Completer<List<LivePlayQuality>>? qualityGate;
  Completer<void>? qualityRequested;
  Completer<LivePlayUrl>? urlGate;
  final requestedRates = <int>[];
  int urlCalls = 0;

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
        url: '',
      );

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    final gate = qualityGate;
    if (gate != null) {
      qualityGate = null;
      qualityRequested?.complete();
      return gate.future;
    }
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    urlCalls++;
    final rate = quality.data as int;
    requestedRates.add(rate);
    final gate = urlGate;
    if (gate != null) {
      urlGate = null;
      return gate.future;
    }
    return LivePlayUrl(
      urls: ['https://example.test/$urlCalls/$rate'],
      actualQuality: _quality(rate == 0 ? '蓝光4M' : quality.quality, rate),
    );
  }
}

class _Controller extends MultiRoomPlayerController {
  _Controller(super.item, this._testPlayer)
      : super(
          configuration: const MultiRoomPlayerConfiguration(
            enableDanmaku: false,
            enableLiveHealthSampling: false,
            enableAutomaticRecovery: false,
          ),
        );

  final _Player _testPlayer;

  @override
  _Player get player => _testPlayer;
}

void main() {
  late _Settings settings;
  late _Site site;
  late _Player player;
  late _Controller controller;

  setUp(() {
    Get.testMode = true;
    settings = _Settings();
    settings.qualityLevel.value = 2;
    Get.put<AppSettingsController>(settings);
    site = _Site();
    player = _Player();
    controller = _Controller(
      MultiRoomItem(
        site: Site(
          id: 'douyu',
          name: '斗鱼',
          logo: '',
          liveSite: site,
        ),
        roomId: '1',
        userName: 'test',
        face: '',
      ),
      player,
    );
  });

  tearDown(() async {
    await controller.playerMutationsIdle;
    controller.onClose();
    await Future<void>.delayed(Duration.zero);
    Get.reset();
  });

  test('multi-room keeps requested original and displays actual 4M', () async {
    await controller.load();

    expect(site.requestedRates, [0]);
    expect(controller.requestedQualityInfo, '原画');
    expect(controller.qualityInfo.value, '蓝光4M');
    expect(controller.qualityComparisonInfo, '请求：原画 · 实际：蓝光4M');
    expect(player.opened, ['https://example.test/1/0']);
  });

  test('same-quality click during refresh reopens the new URL', () async {
    await controller.load();
    final oldUrl = player.opened.single;
    final gate = Completer<List<LivePlayQuality>>();
    site.qualityGate = gate;
    site.qualityRequested = Completer<void>();

    final refresh = controller.load();
    await site.qualityRequested!.future;
    final selection = controller.changeQuality(0);
    gate.complete(site.qualities);
    await Future.wait([refresh, selection]);

    expect(player.stops, greaterThanOrEqualTo(2));
    expect(player.opened, [oldUrl, 'https://example.test/2/0']);
    expect(controller.playUrls, ['https://example.test/2/0']);
    expect(controller.qualityComparisonInfo, '请求：原画 · 实际：蓝光4M');
  });

  test('queued selection falls back when refreshed list is shorter', () async {
    await controller.load();
    final gate = Completer<List<LivePlayQuality>>();
    site.qualityGate = gate;
    site.qualityRequested = Completer<void>();

    final refresh = controller.load();
    await site.qualityRequested!.future;
    final selection = controller.changeQuality(2);
    gate.complete([
      _quality('原画', 0),
      _quality('蓝光4M', 4),
    ]);
    await Future.wait([refresh, selection]);

    expect(controller.qualityIndex, 1);
    expect(controller.userQualityIndex, 1);
    expect(site.requestedRates, [0, 4]);
    expect(player.opened.last, 'https://example.test/2/4');
  });
}
