import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/models/db/history.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';
import 'package:simple_live_tv_app/widgets/tv_open_live_link_dialog.dart';
import 'package:simple_live_tv_app/widgets/tv_playback_dialog_theme.dart';
import 'package:simple_live_tv_app/widgets/tv_room_picker.dart';

import 'support/multi_room_ui_fixture.dart';

const _designSize = Size(1920, 1080);
const _screenshotSizes = [Size(1280, 720), Size(1920, 1080)];

bool _screenshotFontsLoaded = false;

class _DialogTestApp {
  _DialogTestApp(
    this.tester, {
    Iterable<FollowUser> follows = const <FollowUser>[],
    Iterable<History> histories = const <History>[],
  }) {
    Get.testMode = true;
    Get.put<AppSettingsController>(MultiRoomUiSettings());
    Get.put<FollowUserService>(_FakeFollowUserService(follows));
    Get.put<DBService>(_FakeDbService(histories));
  }

  final WidgetTester tester;
  final GlobalKey captureKey = GlobalKey();

  Future<void> pump({
    required Widget home,
    Size size = const Size(1920, 1080),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: _designSize,
        builder: (_, __) => RepaintBoundary(
          key: captureKey,
          child: GetMaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppStyle.lightTheme,
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await tester.pump();
  }
}

class _FakeFollowUserService extends FollowUserService {
  _FakeFollowUserService(Iterable<FollowUser> follows) {
    allList.assignAll(follows);
  }

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeDbService extends DBService {
  _FakeDbService(this.histories);

  final Iterable<History> histories;

  @override
  List<History> getHistores() => histories.toList(growable: false);
}

FollowUser _follow(String roomId, String userName, {int status = 0}) =>
    FollowUser(
      id: '${Constant.kDouyu}_$roomId',
      roomId: roomId,
      siteId: Constant.kDouyu,
      userName: userName,
      face: '',
      addTime: DateTime(2026, 1, 1),
    )..liveStatus.value = status;

History _history(String roomId, String userName) => History(
      id: '${Constant.kDouyu}_$roomId',
      roomId: roomId,
      siteId: Constant.kDouyu,
      userName: userName,
      face: '',
      updateTime: DateTime(2026, 1, 2),
    );

MultiRoomItem _room(String roomId, String userName) => MultiRoomItem(
      site: Sites.allSites[Constant.kDouyu]!,
      roomId: roomId,
      userName: userName,
      face: '',
    );

Widget _launcherHome({
  required VoidCallback openPicker,
  required VoidCallback openLink,
}) =>
    Scaffold(
      backgroundColor: const Color(0xff141e30),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: openPicker, child: const Text('选择直播间')),
            TextButton(onPressed: openLink, child: const Text('打开链接')),
          ],
        ),
      ),
    );

Finder _pickerTile(String userName) => find.ancestor(
      of: find.text(userName),
      matching: find.byType(TvDialogFocusableSurface),
    );

Checkbox _pickerCheckbox(WidgetTester tester, Finder tile) =>
    tester.widget<Checkbox>(
      find.descendant(of: tile, matching: find.byType(Checkbox)),
    );

void _expectDialogInsideViewport(WidgetTester tester, Size size) {
  final dialog = find.byType(Dialog);
  expect(dialog, findsOneWidget);
  final rect = tester.getRect(dialog);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(size.width));
  expect(rect.bottom, lessThanOrEqualTo(size.height));
}

Future<void> _loadScreenshotFonts(WidgetTester tester) async {
  if (_screenshotFontsLoaded ||
      Platform.environment['UPDATE_MULTI_ROOM_SCREENSHOTS'] != '1') {
    return;
  }

  await tester.runAsync(() async {
    final chineseFont = File(r'C:\Windows\Fonts\msyh.ttc');
    if (await chineseFont.exists()) {
      final loader = FontLoader('Microsoft YaHei')
        ..addFont(
          chineseFont.readAsBytes().then(ByteData.sublistView),
        );
      await loader.load();
    }

    final materialIcons = File(
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    );
    if (await materialIcons.exists()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
              materialIcons.readAsBytes().then(ByteData.sublistView),
            ))
          .load();
    }
  });
  _screenshotFontsLoaded = true;
}

Future<void> _writeDialogScreenshot(
  WidgetTester tester,
  _DialogTestApp app,
  String name,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(app.captureKey),
  );
  final outputDirectory = Directory(
    '${Directory.current.path}${Platform.pathSeparator}'
    '.dart_tool${Platform.pathSeparator}multi-room-ui',
  );

  await tester.runAsync(() async {
    await outputDirectory.create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not encode $name as PNG.');
      await File(
        '${outputDirectory.path}${Platform.pathSeparator}$name',
      ).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

void main() {
  final exportScreenshots =
      Platform.environment['UPDATE_MULTI_ROOM_SCREENSHOTS'] == '1';

  testWidgets('picker centers tab labels and uses an unframed playback icon',
      (tester) async {
    final app = _DialogTestApp(tester);
    addTearDown(app.dispose);
    await app.pump(
        home: _launcherHome(
      openPicker: () => showTvRoomPicker(maxRooms: 4),
      openLink: () {},
    ));
    await tester.tap(find.text('选择直播间'));
    await tester.pumpAndSettle();
    for (final section in ['关注', '历史', '搜索']) {
      final tab = find.byKey(Key('tv-room-picker-tab-$section'));
      expect(tester.getCenter(find.text(section)).dy,
          closeTo(tester.getCenter(tab).dy, .5));
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(tab).height, lessThanOrEqualTo(52));
    }
    expect(tester.getRect(find.byKey(const Key('tv-room-picker-tab-关注'))).right,
        lessThan(tester.getRect(find.byKey(const Key('tv-room-picker-tab-历史'))).left));
    expect(tester.getRect(find.byKey(const Key('tv-room-picker-tab-历史'))).right,
        lessThan(tester.getRect(find.byKey(const Key('tv-room-picker-tab-搜索'))).left));
    final header = tester.widget<TvPlaybackDialogHeader>(
      find.byType(TvPlaybackDialogHeader),
    );
    expect(header.icon, Icons.video_library_outlined);
    expect(header.framedIcon, isFalse);
  });

  testWidgets(
      'live rooms sort first and status updates preserve selection and focus',
      (tester) async {
    final offline = _follow('a', '离线甲', status: 1);
    final live = _follow('b', '直播乙', status: 2);
    final unknown = _follow('c', '未知丙');
    final liveSecond = _follow('d', '直播丁', status: 2);
    final app =
        _DialogTestApp(tester, follows: [offline, live, unknown, liveSecond]);
    addTearDown(app.dispose);
    await app.pump(
        home: _launcherHome(
      openPicker: () => showTvRoomPicker(maxRooms: 4),
      openLink: () {},
    ));
    await tester.tap(find.text('选择直播间'));
    await tester.pumpAndSettle();
    void expectOrder(List<String> names) {
      for (var index = 1; index < names.length; index++) {
        expect(tester.getTopLeft(_pickerTile(names[index - 1])).dy,
            lessThan(tester.getTopLeft(_pickerTile(names[index])).dy));
      }
    }

    expectOrder(['直播乙', '直播丁', '离线甲', '未知丙']);
    expect(find.text('直播中'), findsNWidgets(2));
    expect(find.text('未开播'), findsOneWidget);
    expect(find.text('状态未知'), findsOneWidget);
    await tester.tap(find.text('离线甲'));
    await tester.pumpAndSettle();
    final tile = _pickerTile('离线甲');
    final element = tester.element(tile);
    final focusNode = tester
        .widget<InkWell>(
          find.descendant(of: tile, matching: find.byType(InkWell)),
        )
        .focusNode!;
    focusNode.requestFocus();
    await tester.pump();
    unknown.liveStatus.value = 2;
    await tester.pumpAndSettle();
    expectOrder(['直播乙', '未知丙', '直播丁', '离线甲']);
    expect(find.text('直播中'), findsNWidgets(3));
    expect(identical(tester.element(tile), element), isTrue);
    expect(focusNode.hasPrimaryFocus, isTrue);
    expect(_pickerCheckbox(tester, tile).value, isTrue);
  });

  testWidgets('history reuses known status and leaves unchecked rooms unknown',
      (tester) async {
    final app = _DialogTestApp(
      tester,
      follows: [_follow('known', '已关注主播', status: 2)],
      histories: [_history('other', '未关注历史'), _history('known', '已知历史')],
    );
    addTearDown(app.dispose);
    await app.pump(
        home: _launcherHome(
      openPicker: () => showTvRoomPicker(maxRooms: 4),
      openLink: () {},
    ));
    await tester.tap(find.text('选择直播间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_pickerTile('已知历史')).dy,
        lessThan(tester.getTopLeft(_pickerTile('未关注历史')).dy));
    expect(find.text('直播中'), findsOneWidget);
    expect(find.text('状态未知'), findsOneWidget);
    expect(find.text('未开播'), findsNothing);
  });

  testWidgets('picker caps selection at two and returns selected rooms',
      (tester) async {
    final app = _DialogTestApp(tester, follows: [
      _follow('room-1', '第一位主播'),
      _follow('room-2', '第二位主播'),
      _follow('room-3', '第三位主播'),
    ]);
    addTearDown(app.dispose);
    Future<List<MultiRoomItem>?>? pickerResult;

    await app.pump(
      home: _launcherHome(
        openPicker: () => pickerResult = showTvRoomPicker(maxRooms: 2),
        openLink: () {},
      ),
    );
    await tester.tap(find.text('选择直播间'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第一位主播'));
    await tester.tap(find.text('第二位主播'));
    await tester.pumpAndSettle();

    final thirdTile = _pickerTile('第三位主播');
    expect(tester.widget<TvDialogFocusableSurface>(thirdTile).disabled, isTrue);
    await tester.tap(find.text('第三位主播'));
    await tester.pump();
    expect(_pickerCheckbox(tester, thirdTile).value, isFalse);

    await tester.tap(find.text('开始多屏播放'));
    await tester.pumpAndSettle();
    expect(pickerResult, isNotNull);
    final selected = await pickerResult!;
    expect(
      selected?.map((room) => room.roomId).toList(),
      ['room-1', 'room-2'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing rooms stay locked and are included in the result',
      (tester) async {
    final existing = _room('already-playing', '正在播放的主播');
    final app = _DialogTestApp(tester, follows: [
      _follow('already-playing', '正在播放的主播'),
      _follow('new-room', '新选择的主播'),
    ]);
    addTearDown(app.dispose);
    Future<List<MultiRoomItem>?>? pickerResult;

    await app.pump(
      home: _launcherHome(
        openPicker: () => pickerResult = showTvRoomPicker(
          maxRooms: 3,
          existingRooms: [existing],
        ),
        openLink: () {},
      ),
    );
    await tester.tap(find.text('选择直播间'));
    await tester.pumpAndSettle();

    final existingTile = _pickerTile('正在播放的主播');
    expect(_pickerCheckbox(tester, existingTile).value, isTrue);
    expect(
        tester.widget<TvDialogFocusableSurface>(existingTile).disabled, isTrue);
    await tester.tap(find.text('正在播放的主播'));
    await tester.pump();
    expect(_pickerCheckbox(tester, existingTile).value, isTrue);

    await tester.tap(find.text('新选择的主播'));
    await tester.tap(find.text('开始多屏播放'));
    await tester.pumpAndSettle();
    expect(pickerResult, isNotNull);
    final selected = await pickerResult!;
    expect(selected?.map((room) => room.roomId).toList(), [
      'already-playing',
      'new-room',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote OK toggles a focused picker row', (tester) async {
    final app = _DialogTestApp(tester, follows: [
      _follow('remote-room', '遥控器选择的主播'),
    ]);
    addTearDown(app.dispose);
    await app.pump(
      home: _launcherHome(
        openPicker: () => showTvRoomPicker(maxRooms: 2),
        openLink: () {},
      ),
    );
    await tester.tap(find.text('选择直播间'));
    await tester.pumpAndSettle();
    final tile = _pickerTile('遥控器选择的主播');
    final inkWell = tester.widget<InkWell>(
      find.descendant(of: tile, matching: find.byType(InkWell)),
    );
    inkWell.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(_pickerCheckbox(tester, tile).value, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(_pickerCheckbox(tester, tile).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history tab offers a room that can be selected', (tester) async {
    final app = _DialogTestApp(
      tester,
      histories: [_history('history-room', '历史主播')],
    );
    addTearDown(app.dispose);
    Future<List<MultiRoomItem>?>? pickerResult;

    await app.pump(
      home: _launcherHome(
        openPicker: () => pickerResult = showTvRoomPicker(maxRooms: 2),
        openLink: () {},
      ),
    );
    await tester.tap(find.text('选择直播间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();

    expect(find.text('历史主播'), findsOneWidget);
    await tester.tap(find.text('历史主播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始多屏播放'));
    await tester.pumpAndSettle();
    expect(pickerResult, isNotNull);
    final selected = await pickerResult!;
    expect(
      selected?.map((room) => room.roomId).toList(),
      ['history-room'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('link dialog defaults to Douyu and resolves a numeric room ID',
      (tester) async {
    final app = _DialogTestApp(tester);
    addTearDown(app.dispose);
    Future<LiveRoomLinkTarget?>? linkResult;

    await app.pump(
      home: _launcherHome(
        openPicker: () {},
        openLink: () => linkResult = Get.dialog<LiveRoomLinkTarget>(
          const TvOpenLiveLinkDialog(initialSiteId: Constant.kDouyu),
          barrierDismissible: false,
        ),
      ),
    );
    await tester.tap(find.text('打开链接'));
    await tester.pumpAndSettle();
    expect(find.text('斗鱼直播'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.text('打开直播'));
    await tester.pumpAndSettle();

    expect(linkResult, isNotNull);
    final target = await linkResult!;
    expect(target, isA<LiveRoomLinkTarget>());
    expect(target?.site.id, Constant.kDouyu);
    expect(target?.roomId, '12345678');
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid link input keeps the dialog open with an error',
      (tester) async {
    final app = _DialogTestApp(tester);
    addTearDown(app.dispose);
    Future<LiveRoomLinkTarget?>? linkResult;

    await app.pump(
      home: _launcherHome(
        openPicker: () {},
        openLink: () => linkResult = Get.dialog<LiveRoomLinkTarget>(
          const TvOpenLiveLinkDialog(initialSiteId: Constant.kDouyu),
          barrierDismissible: false,
        ),
      ),
    );
    await tester.tap(find.text('打开链接'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://invalid.example/not-a-live-room',
    );
    await tester.tap(find.text('打开直播'));
    await tester.pumpAndSettle();

    expect(find.text('无法识别该直播间。请检查链接或房间号。'), findsOneWidget);
    expect(find.byType(TvOpenLiveLinkDialog), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await linkResult, isNull);
  });

  for (final size in _screenshotSizes) {
    final width = size.width.toInt();
    final height = size.height.toInt();

    testWidgets('picker dialog fits ${width}x$height', (tester) async {
      await _loadScreenshotFonts(tester);
      final app = _DialogTestApp(tester, follows: [
        _follow('preview-1', '正在同播的主播', status: 2),
        _follow('preview-2', '游戏直播间', status: 2),
        _follow('preview-3', '音乐直播间', status: 1),
        _follow('preview-4', '户外直播间', status: 1),
        _follow('preview-5', '赛事直播间'),
      ]);
      addTearDown(app.dispose);
      await app.pump(
        size: size,
        home: _launcherHome(
          openPicker: () => showTvRoomPicker(
            maxRooms: 4,
            existingRooms: [_room('preview-1', '正在同播的主播')],
            selectedRooms: [_room('preview-2', '游戏直播间')],
          ),
          openLink: () {},
        ),
      );
      await tester.tap(find.text('选择直播间'));
      await tester.pumpAndSettle();

      _expectDialogInsideViewport(tester, size);
      expect(tester.takeException(), isNull);
      if (exportScreenshots) {
        await _writeDialogScreenshot(
          tester,
          app,
          'room-picker-${width}x$height.png',
        );
      }
    });

    testWidgets('open-link dialog fits ${width}x$height', (tester) async {
      await _loadScreenshotFonts(tester);
      final app = _DialogTestApp(tester);
      addTearDown(app.dispose);
      await app.pump(
        size: size,
        home: _launcherHome(
          openPicker: () {},
          openLink: () => Get.dialog<LiveRoomLinkTarget>(
            const TvOpenLiveLinkDialog(initialSiteId: Constant.kDouyu),
            barrierDismissible: false,
          ),
        ),
      );
      await tester.tap(find.text('打开链接'));
      await tester.pumpAndSettle();

      _expectDialogInsideViewport(tester, size);
      expect(tester.takeException(), isNull);
      if (exportScreenshots) {
        await _writeDialogScreenshot(
          tester,
          app,
          'open-live-link-${width}x$height.png',
        );
      }
    });
  }

  testWidgets('both dialogs remain within a short 1280x480 viewport',
      (tester) async {
    const size = Size(1280, 480);
    final app = _DialogTestApp(tester);
    addTearDown(app.dispose);
    Future<List<MultiRoomItem>?>? pickerResult;
    Future<LiveRoomLinkTarget?>? linkResult;

    await app.pump(
      size: size,
      home: _launcherHome(
        openPicker: () => pickerResult = showTvRoomPicker(maxRooms: 2),
        openLink: () => linkResult = Get.dialog<LiveRoomLinkTarget>(
          const TvOpenLiveLinkDialog(initialSiteId: Constant.kDouyu),
          barrierDismissible: false,
        ),
      ),
    );

    await tester.tap(find.text('选择直播间'));
    await tester.pumpAndSettle();
    _expectDialogInsideViewport(tester, size);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    _expectDialogInsideViewport(tester, size);
    expect(tester.takeException(), isNull);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(pickerResult, isNotNull);
    expect(await pickerResult!, isNull);

    await tester.tap(find.text('打开链接'));
    await tester.pumpAndSettle();
    _expectDialogInsideViewport(tester, size);
    expect(tester.takeException(), isNull);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(linkResult, isNotNull);
    expect(await linkResult!, isNull);
  });
}
