import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_layout_metrics.dart';

void main() {
  group('TvMultiRoomLayoutMetrics', () {
    test('two-room grid uses the available width and preserves 16:9', () {
      final metrics = TvMultiRoomLayoutMetrics.twoRoom(
        viewport: const Size(1920, 1080),
        gap: 0,
        mainSub: false,
      );

      expect(metrics.tileSize, const Size(960, 540));
      expect(metrics.contentSize, const Size(1920, 540));
    });

    test('main-sub layout uses the available width without crop', () {
      final metrics = TvMultiRoomLayoutMetrics.twoRoom(
        viewport: const Size(1920, 1080),
        gap: 0,
        mainSub: true,
      );

      expect(metrics.tileSize, const Size(640, 360));
      expect(metrics.contentSize, const Size(1920, 720));
    });

    test('four-room grid keeps the 16:9 tile ratio with a gap', () {
      final metrics = TvMultiRoomLayoutMetrics.grid(
        viewport: const Size(1920, 1080),
        gap: 16,
      );

      expect(metrics.tileSize.width / metrics.tileSize.height,
          closeTo(16 / 9, 0.001));
      expect(metrics.contentSize.width, lessThanOrEqualTo(1920));
      expect(metrics.contentSize.height, lessThanOrEqualTo(1080));
    });
  });
}
