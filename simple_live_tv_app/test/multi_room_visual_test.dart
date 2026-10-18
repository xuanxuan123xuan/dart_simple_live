import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/multi_room_ui_fixture.dart';

bool _screenshotFontLoaded = false;

Future<void> _loadScreenshotFont(WidgetTester tester) async {
  if (_screenshotFontLoaded ||
      Platform.environment['UPDATE_MULTI_ROOM_SCREENSHOTS'] != '1') {
    return;
  }

  await tester.runAsync(() async {
    final font = File(r'C:\Windows\Fonts\msyh.ttc');
    if (await font.exists()) {
      final loader = FontLoader('Microsoft YaHei')
        ..addFont(
          font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    final icons = File(
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    );
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')
            ..addFont(icons.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  _screenshotFontLoaded = true;
}

Future<void> _writeScreenshot(
  WidgetTester tester,
  MultiRoomUiFixture fixture,
  String name,
) async {
  final outputDirectory = Directory(
    '${Directory.current.path}${Platform.pathSeparator}'
    '.dart_tool${Platform.pathSeparator}multi-room-ui',
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(fixture.captureKey),
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
  const sizes = [Size(1280, 720), Size(1920, 1080)];

  for (final count in [2, 3, 4]) {
    for (final layout in ['grid', 'mainSub']) {
      for (final size in sizes) {
        testWidgets(
          '$count-room $layout keeps fixture video geometry at '
          '${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
            await _loadScreenshotFont(tester);
            final fixture = MultiRoomUiFixture(count: count);
            addTearDown(() => fixture.dispose(tester));
            fixture.settings.setMultiRoomLayout(layout);
            await fixture.pump(tester, size: size);
            fixture.rooms
                .focusNodeFor(fixture.rooms.rooms.first)
                .requestFocus();
            await tester.pump();

            final videoFinders = [
              for (var index = 0; index < count; index++)
                find.byKey(
                  ValueKey<String>(
                    'multi-room-video-${fixture.rooms.rooms[index].key}',
                  ),
                ),
            ];
            final visibleRects = [
              for (final finder in videoFinders) tester.getRect(finder),
            ];
            final visibleElements = [
              for (final finder in videoFinders) tester.element(finder),
            ];
            if (count == 2) {
              final left = visibleRects[0];
              final right = visibleRects[1];
              // Two rooms occupy one centered row, never two cells of a 2x2 grid.
              expect(left.center.dy, closeTo(size.height / 2, 1));
              expect(right.center.dy, closeTo(size.height / 2, 1));
              expect(left.right, lessThan(right.left));
              expect(left.width / left.height, closeTo(16 / 9, .01));
              expect(right.width / right.height, closeTo(16 / 9, .01));
              expect(left.width / right.width,
                  closeTo(layout == 'mainSub' ? 2 : 1, .01));
              expect(find.text('双屏同播  2 路'), findsOneWidget);
            }

            // The fixture has no native player surface. These captures show
            // the rendered TV layout and its text placeholder only.
            if (exportScreenshots) {
              final name = '${count}room-$layout-'
                  '${size.width.toInt()}x${size.height.toInt()}';
              await _writeScreenshot(
                tester,
                fixture,
                '$name-visible-fixture-placeholder.png',
              );
            }

            await tester.pump(const Duration(seconds: 5));
            await tester.pump(const Duration(milliseconds: 220));

            for (var index = 0; index < videoFinders.length; index++) {
              expect(tester.getRect(videoFinders[index]), visibleRects[index]);
              expect(
                identical(
                  tester.element(videoFinders[index]),
                  visibleElements[index],
                ),
                isTrue,
                reason: 'Hiding controls must retain video element $index.',
              );
            }

            if (exportScreenshots) {
              final name = '${count}room-$layout-'
                  '${size.width.toInt()}x${size.height.toInt()}';
              await _writeScreenshot(
                tester,
                fixture,
                '$name-hidden-fixture-placeholder.png',
              );
            }
          },
        );
      }
    }
  }

  testWidgets('four-room grid tiles remain inside a 1280x480 TV viewport',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    await fixture.pump(tester, size: const Size(1280, 480));
    const viewport = Rect.fromLTWH(0, 0, 1280, 480);

    final tileRects = [
      for (var index = 0; index < fixture.rooms.rooms.length; index++)
        tester.getRect(
          find.byKey(
            ValueKey<String>(
              'multi-room-tile-${fixture.rooms.rooms[index].key}',
            ),
          ),
        ),
    ];
    expect(tileRects, hasLength(4));
    for (final rect in tileRects) {
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(rect.left, greaterThanOrEqualTo(viewport.left));
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.right, lessThanOrEqualTo(viewport.right));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
    }
  });
}
