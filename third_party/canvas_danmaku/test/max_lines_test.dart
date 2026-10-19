import 'dart:math' as math;

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:canvas_danmaku/scroll_danmaku_painter.dart';
import 'package:canvas_danmaku/static_danmaku_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double trackHeight(DanmakuOption option) {
  final text = TextPainter(
    text: TextSpan(
      text: '弹幕',
      style:
          TextStyle(fontSize: option.fontSize, fontFamily: option.fontFamily),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return math.max(text.height, option.fontSize * option.emojiScale) *
      option.lineHeight.clamp(1, 3);
}

class Harness {
  final WidgetTester tester;
  late DanmakuController controller;
  Harness(this.tester);

  Future<void> mount(DanmakuOption option, {double height = 400}) async {
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 600,
          height: height,
          child: DanmakuScreen(
            option: option,
            createdController: (value) => controller = value,
          ),
        ),
      ),
    ));
  }

  Future<void> fill() async {
    for (var i = 0; i < 20; i++) {
      for (final type in [
        DanmakuItemType.scroll,
        DanmakuItemType.top,
        DanmakuItemType.bottom,
      ]) {
        controller.addDanmaku(DanmakuContentItem('弹幕 $i 😀', type: type));
      }
    }
    await tester.pump();
  }

  ScrollDanmakuPainter get scroll => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<ScrollDanmakuPainter>()
      .single;

  StaticDanmakuPainter get fixed => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<StaticDanmakuPainter>()
      .single;

  void expectCount(int count) {
    expect(scroll.scrollDanmakuItems, hasLength(count));
    expect(fixed.topDanmakuItems, hasLength(count));
    expect(fixed.buttomDanmakuItems, hasLength(count));
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('maxLines defaults to area mode and copyWith retains or replaces it',
      () {
    final option = DanmakuOption();
    expect(option.maxLines, 0);
    expect(option.copyWith(maxLines: 3).copyWith(opacity: .5).maxLines, 3);
    expect(option.copyWith(maxLines: 3).copyWith(maxLines: 0).maxLines, 0);
  });

  for (final lines in [1, 3, 6]) {
    testWidgets(
        '$lines lines ignore a small area and bound every ordinary type',
        (tester) async {
      final harness = Harness(tester);
      final option = DanmakuOption(maxLines: lines, area: .1);
      await harness.mount(option);
      await harness.fill();
      harness.expectCount(lines);
      expect(harness.fixed.topDanmakuItems.last.yPosition,
          closeTo((lines - 1) * trackHeight(option), .001));
      await harness.dispose();
    });
  }

  testWidgets('small viewport fits complete tracks and reserves subtitle space',
      (tester) async {
    final harness = Harness(tester);
    final option = DanmakuOption(maxLines: 6, area: .1);
    final height = trackHeight(option) * 2.9;
    await harness.mount(option, height: height);
    await harness.fill();
    harness.expectCount(1);
    harness.controller.updateOption(option.copyWith(safeArea: false));
    await tester.pump();
    await harness.fill();
    harness.expectCount(2);
    await harness.mount(option, height: trackHeight(option) * .9);
    await harness.fill();
    harness.expectCount(0);
    await harness.dispose();
  });

  testWidgets('font and emoji scale changes clear old tracks and refit',
      (tester) async {
    final harness = Harness(tester);
    final option = DanmakuOption(maxLines: 6, safeArea: false);
    await harness.mount(option, height: 150);
    await harness.fill();
    harness.expectCount(6);
    final enlarged = option.copyWith(fontSize: 30, emojiScale: 2);
    harness.controller.updateOption(enlarged);
    await tester.pump();
    harness.expectCount(0);
    await harness.fill();
    harness.expectCount(2);
    expect(harness.fixed.topDanmakuItems.last.yPosition, 60);
    await harness.dispose();
  });

  testWidgets('widget line reduction and geometry changes clear old tracks',
      (tester) async {
    final harness = Harness(tester);
    final option = DanmakuOption(maxLines: 6);
    await harness.mount(option);
    await harness.fill();
    harness.expectCount(6);
    final reduced = option.copyWith(maxLines: 1);
    await harness.mount(reduced);
    harness.expectCount(0);
    await harness.fill();
    harness.expectCount(1);
    await harness.mount(reduced, height: 300);
    harness.expectCount(0);
    await harness.dispose();
  });

  testWidgets('default mode retains area allocation and existing active items',
      (tester) async {
    final harness = Harness(tester);
    final option = DanmakuOption(area: .5);
    final height = trackHeight(option) * 10;
    await harness.mount(option, height: height);
    await harness.fill();
    harness.expectCount(5);
    harness.controller.updateOption(option.copyWith(fontSize: 18));
    await tester.pump();
    harness.expectCount(5);
    harness.controller.clear();
    await harness.mount(option.copyWith(area: 1), height: height);
    await harness.fill();
    harness.expectCount(9);
    await harness.dispose();
  });

  testWidgets('immediate refill after reducing lines keeps the clock running',
      (tester) async {
    final harness = Harness(tester);
    final option = DanmakuOption(maxLines: 3, duration: 1);
    await harness.mount(option);
    await harness.fill();
    harness.controller.updateOption(option.copyWith(maxLines: 1));
    await tester.pump();
    await harness.fill();
    harness.expectCount(1);
    final initialX = harness.scroll.scrollDanmakuItems.single.xPosition;

    // The engine uses a real Stopwatch, whereas pump advances fake timers.
    // Refill above occurs before the existing 100 ms cleanup task wakes up.
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 120),
        ));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
        harness.scroll.scrollDanmakuItems.single.xPosition, lessThan(initialX));
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 1000),
        ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.fixed.topDanmakuItems, isEmpty);
    expect(harness.fixed.buttomDanmakuItems, isEmpty);
    await harness.dispose();
  });

  testWidgets('switching from lines to area clears and uses the area again',
      (tester) async {
    final harness = Harness(tester);
    final option = DanmakuOption(maxLines: 1, area: .5);
    final height = trackHeight(option) * 10;
    await harness.mount(option, height: height);
    await harness.fill();
    harness.expectCount(1);
    harness.controller.updateOption(option.copyWith(maxLines: 0));
    await tester.pump();
    harness.expectCount(0);
    await harness.fill();
    harness.expectCount(5);
    await harness.dispose();
  });

  testWidgets('option update rejects additions using the previous track layout',
      (tester) async {
    final harness = Harness(tester);
    final option = DanmakuOption(maxLines: 6);
    await harness.mount(option);
    await harness.fill();
    harness.controller.updateOption(option.copyWith(maxLines: 1));
    // Do not pump: the new layout has not run yet.
    for (var i = 0; i < 6; i++) {
      harness.controller.addDanmaku(
        DanmakuContentItem('stale $i', type: DanmakuItemType.top),
      );
    }
    await tester.pump();
    harness.expectCount(0);
    await harness.fill();
    harness.expectCount(1);
    await harness.dispose();
  });

  testWidgets('one track accepts another scroll after the previous one enters',
      (tester) async {
    final harness = Harness(tester);
    await harness.mount(DanmakuOption(maxLines: 1, duration: 10));
    harness.controller.addDanmaku(DanmakuContentItem('a'));
    harness.controller.addDanmaku(DanmakuContentItem('a'));
    await tester.pump();
    expect(harness.scroll.scrollDanmakuItems, hasLength(1));
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 600),
        ));
    await tester.pump(const Duration(milliseconds: 600));
    harness.controller.addDanmaku(DanmakuContentItem('a'));
    await tester.pump();
    expect(harness.scroll.scrollDanmakuItems, hasLength(2));
    expect(harness.scroll.scrollDanmakuItems.map((item) => item.yPosition),
        everyElement(0));
    await harness.dispose();
  });
}
