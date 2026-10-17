import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  group('buildMultiRoomDanmakuContentParts', () {
    test('preserves the exact text and emoji order from message spans', () {
      final parts = buildMultiRoomDanmakuContentParts(const [
        LiveMessageSpan.text('前[未知]'),
        LiveMessageSpan.image(
          'asset://assets/images/douyin_emoji/weixiao.png',
          fallbackText: '[微笑]',
        ),
        LiveMessageSpan.text('后'),
      ]);

      expect(parts, hasLength(3));
      expect(parts![0].text, '前[未知]');
      expect(parts[0].isImage, isFalse);
      expect(
        parts[1].imageUrl,
        'asset://assets/images/douyin_emoji/weixiao.png',
      );
      expect(parts[1].fallbackText, '[微笑]');
      expect(parts[2].text, '后');
    });

    test('falls back to the legacy image URL path without rich spans', () {
      expect(buildMultiRoomDanmakuContentParts(null), isNull);
      expect(buildMultiRoomDanmakuContentParts(const []), isNull);
    });
  });
}
