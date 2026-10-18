import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_playback_intent.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_page.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_player_controller.dart';

class MultiRoomUiSettings extends AppSettingsController {
  @override
  // Keep the fixture independent of local storage and account sessions.
  // ignore: must_call_super
  void onInit() {}

  @override
  void setMultiRoomLayout(String value) => multiRoomLayout.value = value;

  @override
  void setMultiRoomMixAudio(bool value) => multiRoomMixAudio.value = value;

  @override
  void setMultiRoomMaxRooms(int value) => multiRoomMaxRooms.value = value;
}

class MultiRoomUiSession extends MultiRoomPlayerController {
  MultiRoomUiSession(super.item) {
    loading.value = false;
    liveStatus.value = true;
    liveState.value = LiveStatusState.live;
    requestedQualityInfo.value = '原画';
    qualityInfo.value = '蓝光4M';
    lineInfo.value = '线路 1/2';
  }

  int pauseActions = 0;
  int loads = 0;
  int qualityChanges = 0;
  int lineChanges = 0;
  int selectedQuality = 0;
  int selectedLine = 0;
  bool closed = false;
  bool capabilitiesAvailable = true;

  @override
  List<LivePlayQuality> get qualities => capabilitiesAvailable
      ? [
          LivePlayQuality(quality: '原画', data: 0),
          LivePlayQuality(quality: '流畅', data: 1),
        ]
      : const [];

  @override
  int get qualityIndex => selectedQuality;
  @override
  int get lineIndex => selectedLine;
  @override
  int get lineCount => capabilitiesAvailable ? 2 : 0;

  @override
  Future<void> togglePause() async {
    pauseActions++;
    await setUserPaused(!userPaused.value);
  }

  @override
  Future<void> setUserPaused(bool paused) async {
    userPaused.value = paused;
    playbackIntent.userPaused = paused;
  }

  @override
  Future<void> setMuted(bool value) async => muted.value = value;

  @override
  Future<void> setVolume(double value) async {
    volume.value = value.clamp(0, 100).toDouble();
    muted.value = volume.value == 0;
  }

  @override
  Future<void> selectQuality(int index, {bool automatic = false}) async {
    qualityChanges++;
    selectedQuality = index;
    requestedQualityInfo.value = qualities[index].quality;
    qualityInfo.value = qualities[index].quality;
  }

  @override
  Future<void> selectLine(int index) async {
    lineChanges++;
    selectedLine = index;
    lineInfo.value = '线路 ${index + 1}/2';
  }

  @override
  Future<void> load() async => loads++;

  @override
  Future<void> setDanmakuActive(bool active) async =>
      showDanmakuState.value = active;

  @override
  void suspend(TvPlaybackSuspension reason) => playbackIntent.suspend(reason);

  @override
  void resume(TvPlaybackSuspension reason) => playbackIntent.resume(reason);

  @override
  Future<void> closePlaybackSession() async => closed = true;
}

class MultiRoomUiRooms extends MultiRoomController {
  MultiRoomUiRooms(List<MultiRoomItem> items) : super(items) {
    rooms.assignAll(items);
    mainRoomKey.value = items.first.key;
    focusedRoomKey.value = items.first.key;
    for (final item in items) {
      sessions[item.key] = MultiRoomUiSession(item);
    }
    sessions[items.first.key]!.muted.value = false;
    audioRoomKeys.add(items.first.key);
    allMuted.value = false;
  }

  @override
  // UI actions use real parent dispatch, without native player setup.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> closePlaybackSession() async {
    for (final node in focusNodes.values) {
      node.dispose();
    }
    focusNodes.clear();
    for (final session in sessions.values) {
      await session.closePlaybackSession();
    }
  }
}

class MultiRoomUiFixture {
  MultiRoomUiFixture({int count = 4}) {
    Get.testMode = true;
    settings = Get.put<AppSettingsController>(MultiRoomUiSettings())
        as MultiRoomUiSettings;
    final site = Site(
        id: 'douyu', name: '斗鱼', logo: '', index: 0, liveSite: DouyuSite());
    rooms = Get.put<MultiRoomController>(MultiRoomUiRooms([
      for (var index = 0; index < count; index++)
        MultiRoomItem(
            site: site,
            roomId: '$index',
            userName: '直播间 ${index + 1}',
            face: ''),
    ])) as MultiRoomUiRooms;
  }

  late final MultiRoomUiSettings settings;
  late final MultiRoomUiRooms rooms;
  final captureKey = GlobalKey();

  MultiRoomUiSession session(int index) =>
      rooms.playerFor(rooms.rooms[index]) as MultiRoomUiSession;

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(1280, 720), bool settle = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(1920, 1080),
      builder: (_, child) => GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        theme: AppStyle.lightTheme,
        home: child,
      ),
      child: RepaintBoundary(key: captureKey, child: const MultiRoomPage()),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    Get.reset();
    await tester.pump();
  }
}
