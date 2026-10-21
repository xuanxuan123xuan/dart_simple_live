import 'dart:ui' show PointerDeviceKind;

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/multi_room_ui_fixture.dart';

Key _key(String value) => ValueKey<String>(value);

Finder _topOverlay() => find.byKey(_key('multi-room-top-overlay'));
Finder _bottomOverlay() => find.byKey(_key('multi-room-bottom-overlay'));
Finder _pauseButton() => find.byKey(_key('multi-room-pause'));
Finder _danmakuButton() => find.byKey(_key('multi-room-danmaku'));
Finder _video(MultiRoomUiFixture fixture, int index) => find.byKey(
      _key('multi-room-video-${fixture.rooms.rooms[index].key}'),
    );
Finder _tile(MultiRoomUiFixture fixture, int index) => find.byKey(
      _key('multi-room-tile-${fixture.rooms.rooms[index].key}'),
    );
Finder _danmakuLayer(MultiRoomUiFixture fixture, int index) => find.descendant(
      of: _tile(fixture, index),
      matching: find.byType(DanmakuScreen, skipOffstage: false),
    );

void _expectOverlayState(WidgetTester tester, {required bool visible}) {
  for (final overlay in [_topOverlay(), _bottomOverlay()]) {
    expect(overlay, findsOneWidget);
    final opacity = tester.widget<AnimatedOpacity>(overlay);
    final pointerBoundary = opacity.child as IgnorePointer;
    final focusBoundary = pointerBoundary.child as ExcludeFocus;
    final semanticsBoundary = focusBoundary.child as ExcludeSemantics;
    expect(pointerBoundary.ignoring, !visible);
    expect(focusBoundary.excluding, !visible);
    expect(semanticsBoundary.excluding, !visible);
    expect(opacity.opacity, visible ? 1 : 0);
  }
}

void _expectRoomSelected(
  WidgetTester tester,
  MultiRoomUiFixture fixture,
  int index,
) {
  final semantics = tester
      .widgetList<Semantics>(
        find.descendant(
            of: _tile(fixture, index), matching: find.byType(Semantics)),
      )
      .singleWhere((widget) => widget.properties.selected != null);
  expect(semantics.properties.selected, isTrue);
}

void _expectOptionState(
  WidgetTester tester,
  String option,
  bool selected,
) {
  final semantics = tester.widget<Semantics>(
    find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.label == option &&
        widget.properties.checked != null),
  );
  expect(semantics.properties.selected, selected);
  expect(semantics.properties.checked, selected);
  expect(semantics.properties.inMutuallyExclusiveGroup, isTrue);
}

Future<void> _pumpUntilHidden(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 220));
}

Future<void> _tapRoom(
    WidgetTester tester, MultiRoomUiFixture fixture, int index) async {
  await tester.tap(_tile(fixture, index));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('idle controls become unreachable while video elements stay put',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);
    fixture.rooms.focusNodeFor(fixture.rooms.rooms.first).requestFocus();
    await tester.pump();

    _expectOverlayState(tester, visible: true);
    final pauseRect = tester.getRect(_pauseButton());
    final videoRects = <Rect>[
      for (var index = 0; index < fixture.rooms.rooms.length; index++)
        tester.getRect(_video(fixture, index)),
    ];
    final videoElements = <Element>[
      for (var index = 0; index < fixture.rooms.rooms.length; index++)
        tester.element(_video(fixture, index)),
    ];

    await _pumpUntilHidden(tester);
    _expectOverlayState(tester, visible: false);
    await tester.tapAt(pauseRect.center);
    expect(fixture.session(0).pauseActions, 0);

    for (var index = 0; index < fixture.rooms.rooms.length; index++) {
      expect(tester.getRect(_video(fixture, index)), videoRects[index]);
      expect(
        identical(tester.element(_video(fixture, index)), videoElements[index]),
        isTrue,
        reason: 'Idle overlay changes must not replace video element $index.',
      );
    }
  });

  testWidgets(
      'danmaku canvas fills each room and stays live when controls hide',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 2);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);

    final layer = _danmakuLayer(fixture, 1);
    expect(layer, findsOneWidget);
    expect(tester.getRect(layer), tester.getRect(_video(fixture, 1)));
    final layerElement = tester.element(layer);
    final danmakuController = fixture.session(1).danmakuController;
    expect(danmakuController, isNotNull);
    danmakuController!.addDanmaku(DanmakuContentItem('多屏弹幕测试消息'));
    await tester.pump(const Duration(milliseconds: 100));

    await _pumpUntilHidden(tester);
    _expectOverlayState(tester, visible: false);
    expect(fixture.session(1).showDanmakuState.value, isTrue);
    expect(
        tester
            .widget<Offstage>(
              find.ancestor(of: layer, matching: find.byType(Offstage)).first,
            )
            .offstage,
        isFalse);
    expect(identical(tester.element(layer), layerElement), isTrue);
    expect(identical(fixture.session(1).danmakuController, danmakuController),
        isTrue);
    danmakuController.clear();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets(
      'danmaku toggle belongs to the selected room and follows focus order',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);
    fixture.rooms.focusNodeFor(fixture.rooms.rooms.first).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Focus>(
              find
                  .descendant(of: _pauseButton(), matching: find.byType(Focus))
                  .first,
            )
            .focusNode!
            .hasPrimaryFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_danmakuButton(), findsOneWidget);
    expect(find.text('关弹幕'), findsOneWidget);
    final danmakuFocus = tester.widget<Focus>(
      find.descendant(of: _danmakuButton(), matching: find.byType(Focus)).first,
    );
    expect(danmakuFocus.focusNode!.hasPrimaryFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(fixture.session(0).danmakuChanges, [false]);
    expect(fixture.session(0).showDanmakuState.value, isFalse);
    for (var index = 1; index < fixture.rooms.rooms.length; index++) {
      expect(fixture.session(index).danmakuChanges, isEmpty);
      expect(fixture.session(index).showDanmakuState.value, isTrue);
    }
    expect(find.text('开弹幕'), findsOneWidget);
  });

  testWidgets('main room, focus, audio and expansion preserve room preferences',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);
    final rooms = fixture.rooms.rooms;

    fixture.rooms.setMainRoom(rooms[2]);
    fixture.rooms.focusedRoomKey.value = rooms[1].key;
    await fixture.rooms.toggleAudio(rooms[2]);
    await tester.pumpAndSettle();
    for (var index = 0; index < rooms.length; index++) {
      expect(fixture.session(index).showDanmakuState.value, isTrue);
      expect(fixture.session(index).danmakuChanges, isEmpty);
    }

    await fixture.rooms.toggleRoomDanmaku(rooms[1]);
    expect(fixture.rooms.isRoomDanmakuEnabled(rooms[1].key), isFalse);
    await fixture.rooms.toggleExpanded(rooms[2]);
    expect(fixture.session(0).showDanmakuState.value, isFalse);
    expect(fixture.session(1).showDanmakuState.value, isFalse);
    expect(fixture.session(2).showDanmakuState.value, isTrue);
    expect(fixture.session(3).showDanmakuState.value, isFalse);

    await fixture.rooms.handleBack();
    for (var index = 0; index < rooms.length; index++) {
      expect(
        fixture.session(index).showDanmakuState.value,
        index != 1,
        reason: 'Returning from expanded view restores room $index preference.',
      );
    }
    expect(fixture.rooms.isRoomDanmakuEnabled(rooms[1].key), isFalse);
  });

  testWidgets('a room can enable danmaku while the global default is off',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 2, globalDanmakuEnabled: false);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);

    expect(fixture.session(0).showDanmakuState.value, isFalse);
    expect(fixture.session(1).showDanmakuState.value, isFalse);
    expect(find.text('开弹幕'), findsOneWidget);
    await tester.tap(_danmakuButton());
    await tester.pumpAndSettle();

    expect(fixture.settings.danmuEnable.value, isFalse);
    expect(fixture.session(0).showDanmakuState.value, isTrue);
    expect(fixture.session(1).showDanmakuState.value, isFalse);
    expect(fixture.rooms.isRoomDanmakuEnabled(fixture.rooms.rooms.first.key),
        isTrue);
    expect(find.text('关弹幕'), findsOneWidget);
  });

  testWidgets('first OK wakes the pause control, and a long press acts once',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 2);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);
    fixture.rooms.focusNodeFor(fixture.rooms.rooms.first).requestFocus();
    await tester.pump();

    await _pumpUntilHidden(tester);
    _expectOverlayState(tester, visible: false);
    expect(fixture.session(0).pauseActions, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    _expectOverlayState(tester, visible: true);
    expect(fixture.session(0).pauseActions, 0);
    final pauseFocus = tester.widget<Focus>(
      find.descendant(of: _pauseButton(), matching: find.byType(Focus)).first,
    );
    expect(pauseFocus.focusNode!.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fixture.session(0).pauseActions, 1);
    expect(fixture.session(0).userPaused.value, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fixture.session(0).pauseActions, 2);
    expect(fixture.session(0).userPaused.value, isFalse);
  });

  for (final count in [2, 4]) {
    testWidgets(
        '$count-room arrows select rooms without changing main or audio',
        (tester) async {
      final fixture = MultiRoomUiFixture(count: count);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      final rooms = fixture.rooms.rooms;
      final initialMainKey = fixture.rooms.mainRoomKey.value;
      final initialAudioRoomKeys = fixture.rooms.audioRoomKeys.toSet();
      fixture.rooms.focusNodeFor(rooms.first).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(fixture.rooms.focusedRoomKey.value, rooms[1].key);
      expect(fixture.rooms.mainRoomKey.value, initialMainKey);
      expect(fixture.rooms.audioRoomKeys, initialAudioRoomKeys);

      if (count == 4) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(fixture.rooms.focusedRoomKey.value, rooms[3].key);
        expect(fixture.rooms.mainRoomKey.value, initialMainKey);
        expect(fixture.rooms.audioRoomKeys, initialAudioRoomKeys);
      }
    });
  }

  testWidgets('Back hides the overlay before arrows resume room navigation',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);
    fixture.rooms.focusNodeFor(fixture.rooms.rooms.first).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 220));
    _expectOverlayState(tester, visible: false);
    expect(_tile(fixture, 1), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(fixture.rooms.focusedRoomKey.value, fixture.rooms.rooms[1].key);
    expect(_tile(fixture, 1), findsOneWidget);
  });

  testWidgets(
      'actual mouse movement wakes controls and stationary hover times out',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getRect(_video(fixture, 0)).center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4999));
    _expectOverlayState(tester, visible: true);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 220));
    _expectOverlayState(tester, visible: false);

    await mouse.moveTo(tester.getRect(_video(fixture, 2)).center);
    await tester.pump();
    _expectOverlayState(tester, visible: true);

    // No further pointer movement occurs during this full idle interval.
    await tester.pump(const Duration(milliseconds: 4999));
    _expectOverlayState(tester, visible: true);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 220));
    _expectOverlayState(tester, visible: false);
    await mouse.removePointer();
  });

  testWidgets('touch selection focuses a room and exposes shared controls',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);

    await _tapRoom(tester, fixture, 2);

    expect(fixture.rooms.focusedRoomKey.value, fixture.rooms.rooms[2].key);
    _expectRoomSelected(tester, fixture, 2);
    _expectOverlayState(tester, visible: true);
    final pauseFocus = tester.widget<Focus>(
      find.descendant(of: _pauseButton(), matching: find.byType(Focus)).first,
    );
    expect(pauseFocus.focusNode!.hasPrimaryFocus, isTrue);
  });

  testWidgets('quality and line controls become available after initial load',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 2);
    addTearDown(() => fixture.dispose(tester));
    final target = fixture.session(0);
    target.capabilitiesAvailable = false;
    target.loading.value = true;
    await fixture.pump(tester, settle: false);
    await tester.tap(find.byKey(_key('multi-room-quality')));
    await tester.pump();
    expect(find.text('流畅'), findsNothing);

    target.capabilitiesAvailable = true;
    target.loading.value = false;
    await tester.pump();
    await tester.tap(find.byKey(_key('multi-room-quality')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('流畅'));
    await tester.pumpAndSettle();
    expect(target.qualityChanges, 1);
    await tester.tap(find.byKey(_key('multi-room-line')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('线路 2'));
    await tester.pumpAndSettle();
    expect(target.lineChanges, 1);
  });

  for (final targetIndex in [1, 2, 3]) {
    testWidgets(
        'quality and line dialogs hold the overlay and target room ${targetIndex + 1}',
        (tester) async {
      final fixture = MultiRoomUiFixture(count: 4);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      await _tapRoom(tester, fixture, targetIndex);
      final target = fixture.session(targetIndex);

      await tester.tap(find.byKey(_key('multi-room-quality')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      _expectOverlayState(tester, visible: true);
      expect(find.text('流畅'), findsOneWidget);
      _expectOptionState(tester, '原画', true);
      _expectOptionState(tester, '流畅', false);
      await tester.tap(find.text('流畅'));
      await tester.pumpAndSettle();

      expect(target.qualityChanges, 1);
      expect(target.selectedQuality, 1);
      for (var index = 0; index < fixture.rooms.rooms.length; index++) {
        if (index == targetIndex) continue;
        expect(fixture.session(index).qualityChanges, 0);
        expect(fixture.session(index).selectedQuality, 0);
      }

      await tester.tap(find.byKey(_key('multi-room-line')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      _expectOverlayState(tester, visible: true);
      expect(find.text('线路 2'), findsOneWidget);
      _expectOptionState(tester, '线路 1', true);
      _expectOptionState(tester, '线路 2', false);
      await tester.tap(find.text('线路 2'));
      await tester.pumpAndSettle();

      expect(target.lineChanges, 1);
      expect(target.selectedLine, 1);
      for (var index = 0; index < fixture.rooms.rooms.length; index++) {
        if (index == targetIndex) continue;
        expect(fixture.session(index).lineChanges, 0);
        expect(fixture.session(index).selectedLine, 0);
      }

      // Dialog transitions already consume a few frames of the new interval.
      await tester.pump(const Duration(seconds: 4));
      _expectOverlayState(tester, visible: true);
      await tester.pump(const Duration(milliseconds: 1220));
      _expectOverlayState(tester, visible: false);
    });
  }

  testWidgets('slider sends absolute volume and releases holds after dismissal',
      (tester) async {
    final fixture = MultiRoomUiFixture();
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);
    await _tapRoom(tester, fixture, 3);
    await tester.tap(find.byKey(_key('multi-room-sound')));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(72);
    slider.onChanged!(15);
    slider.onChanged!(85);
    slider.onChanged!(37);
    await tester.pumpAndSettle();
    expect(fixture.session(3).volume.value, 37);
    expect(fixture.session(0).muted.value, isTrue);
    await tester.pump(const Duration(seconds: 8));
    _expectOverlayState(tester, visible: true);
    // Dismiss midway through a drag: dispose must release its extra hold.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    await _pumpUntilHidden(tester);
    _expectOverlayState(tester, visible: false);
  });

  testWidgets('menu key works on controls and nested settings keep focus',
      (tester) async {
    final fixture = MultiRoomUiFixture();
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);
    fixture.rooms.focusNodeFor(fixture.rooms.rooms.first).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
        fixture.rooms.focusNodeFor(fixture.rooms.rooms.first).hasPrimaryFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(find.text('多屏操作'), findsOneWidget);
    await tester.tap(find.text('多屏设置'));
    await tester.pumpAndSettle();
    expect(find.text('多屏设置'), findsOneWidget);
    expect(find.text('进入多开默认全部有声'), findsOneWidget);
    await tester.tap(find.text('进入多开默认全部有声'));
    await tester.pumpAndSettle();
    expect(fixture.settings.multiRoomAllAudioOnEntry.value, isFalse);
    expect(fixture.rooms.audioRoomKeys, hasLength(fixture.rooms.rooms.length));
    expect(
      fixture.rooms.sessions.values.every((session) => !session.muted.value),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 8));
    _expectOverlayState(tester, visible: true);
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('多屏设置'), findsNothing);
    await _pumpUntilHidden(tester);
    _expectOverlayState(tester, visible: false);
  });

  for (final count in [2, 3, 4]) {
    testWidgets('$count-room sound controls use exclusive parent audio routing',
        (tester) async {
      final fixture = MultiRoomUiFixture(count: count);
      addTearDown(() => fixture.dispose(tester));
      await fixture.pump(tester);
      final selectedIndex = count - 1;
      await _tapRoom(tester, fixture, selectedIndex);
      final selected = fixture.session(selectedIndex);
      final firstRoom = fixture.session(0);
      selected.volume.value = 50;
      _expectRoomSelected(tester, fixture, selectedIndex);

      await tester.tap(find.byKey(_key('multi-room-sound')));
      await tester.pumpAndSettle();
      expect(find.text('声音 · 直播间 $count'), findsOneWidget);
      expect(find.text('恢复声音'), findsOneWidget);
      expect(find.text('音量加'), findsOneWidget);
      await tester.tap(find.text('恢复声音'));
      await tester.pumpAndSettle();

      expect(selected.muted.value, isFalse);
      expect(firstRoom.muted.value, isTrue);
      expect(fixture.rooms.audioRoomKeys,
          {fixture.rooms.rooms[selectedIndex].key});

      await tester.tap(find.text('音量加'));
      await tester.pumpAndSettle();
      expect(selected.volume.value, 58);
      for (var index = 0; index < count; index++) {
        if (index == selectedIndex) continue;
        expect(fixture.session(index).muted.value, isTrue);
      }
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('mix audio preserves another room when restoring sound',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    fixture.settings.setMultiRoomMixAudio(true);
    await fixture.pump(tester);

    await _tapRoom(tester, fixture, 1);
    await tester.tap(find.byKey(_key('multi-room-sound')));
    await tester.pumpAndSettle();
    expect(find.text('声音 · 直播间 2'), findsOneWidget);
    await tester.tap(find.text('恢复声音'));
    await tester.pumpAndSettle();
    expect(fixture.session(0).muted.value, isFalse);
    expect(fixture.session(1).muted.value, isFalse);
    expect(
        fixture.rooms.audioRoomKeys,
        containsAll([
          fixture.rooms.rooms[0].key,
          fixture.rooms.rooms[1].key,
        ]));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    await _tapRoom(tester, fixture, 2);
    await tester.tap(find.byKey(_key('multi-room-sound')));
    await tester.pumpAndSettle();
    expect(find.text('声音 · 直播间 3'), findsOneWidget);
    await tester.tap(find.text('恢复声音'));
    await tester.pumpAndSettle();
    expect(fixture.session(1).muted.value, isFalse);
    expect(fixture.session(2).muted.value, isFalse);
    expect(
        fixture.rooms.audioRoomKeys,
        containsAll([
          fixture.rooms.rooms[0].key,
          fixture.rooms.rooms[1].key,
          fixture.rooms.rooms[2].key,
        ]));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
  });

  testWidgets('all-audio mode enables rooms and respects manual mute',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4, allAudioOnEntry: true);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester);
    await tester.pump();

    expect(
      fixture.rooms.sessions.values.every((session) => !session.muted.value),
      isTrue,
    );
    expect(fixture.rooms.audioRoomKeys, hasLength(4));

    final manuallyMuted = fixture.rooms.rooms[1];
    await fixture.rooms.setAudioEnabled(manuallyMuted.key, false);
    expect(fixture.session(1).muted.value, isTrue);
    expect(fixture.rooms.audioRoomKeys, isNot(contains(manuallyMuted.key)));

    await fixture.rooms.refreshAll();
    expect(fixture.session(1).muted.value, isTrue);
    expect(fixture.rooms.audioRoomKeys, isNot(contains(manuallyMuted.key)));

    await fixture.rooms.toggleAllAudio();
    expect(fixture.rooms.audioRoomKeys, isEmpty);
    expect(
      fixture.rooms.sessions.values.every((session) => session.muted.value),
      isTrue,
    );
    await fixture.rooms.toggleAllAudio();
    expect(fixture.rooms.audioRoomKeys, hasLength(4));
    expect(
      fixture.rooms.sessions.values.every((session) => !session.muted.value),
      isTrue,
    );

    fixture.rooms.setAllAudioOnEntry(false);
    await tester.pump();
    expect(fixture.rooms.audioRoomKeys, {fixture.rooms.rooms.first.key});
    expect(fixture.session(0).muted.value, isFalse);
    for (var index = 1; index < fixture.rooms.rooms.length; index++) {
      expect(fixture.session(index).muted.value, isTrue);
    }
  });
}
