import 'dart:ui' as ui;

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:canvas_danmaku/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matcher/matcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('long mixed content stays on one complete line', () {
    const leadingText = '这是一条明显宽于手机视口的长弹幕';
    const trailingText = '表情后面的最后一个字';
    final content = DanmakuContentItem(
      'unused',
      parts: const [
        DanmakuContentPart.text(leadingText),
        DanmakuContentPart.image(
          'https://cdn.test/emoji.png',
          fallbackText: '[尊嘟假嘟]',
        ),
        DanmakuContentPart.text(trailingText),
      ],
    );

    final layout = Utils.prepareContent(content, 24, 4, 1.25, null, true);
    final lines = layout.paragraph.computeLineMetrics();

    expect(layout.size.width, greaterThan(320));
    expect(lines, hasLength(1));
    expect(
      layout.size.width,
      greaterThanOrEqualTo(layout.paragraph.longestLine.ceilToDouble()),
    );
    expect(
      layout.paragraph.getBoxesForRange(
        leadingText.length + 1 + trailingText.length - 1,
        leadingText.length + 1 + trailingText.length,
      ),
      isNotEmpty,
      reason: '表情后的最后一个字符必须保留在单行 Paragraph 中',
    );
  });

  test(
    'emoji placeholder stays compact regardless of fallback token length',
    () {
      const token = '[憨笑哪吒]';
      final content = DanmakuContentItem(
        token,
        parts: const [
          DanmakuContentPart.image(
            'https://cdn.test/emoji.png',
            fallbackText: token,
          ),
        ],
      );

      final normal = Utils.prepareContent(content, 16, 4, 1.0, null, false);
      final larger = Utils.prepareContent(content, 28, 4, 1.5, null, false);
      final box = normal.paragraph.getBoxesForPlaceholders().single;
      expect(box.right - box.left, 16);
      expect(larger.size.width, greaterThan(normal.size.width));
      expect(larger.size.height, greaterThan(normal.size.height));
    },
  );

  test('consecutive emoji placeholders do not reserve token-sized gaps', () {
    final content = DanmakuContentItem(
      '[憨笑哪吒][尊嘟假嘟]尾字',
      parts: const [
        DanmakuContentPart.image(
          'https://cdn.test/emoji-1.png',
          fallbackText: '[憨笑哪吒]',
        ),
        DanmakuContentPart.image(
          'https://cdn.test/emoji-2.png',
          fallbackText: '[尊嘟假嘟]',
        ),
        DanmakuContentPart.text('尾字'),
      ],
    );

    final layout = Utils.prepareContent(content, 20, 4, 1.25, null, false);
    final boxes = layout.paragraph.getBoxesForPlaceholders();

    expect(boxes, hasLength(2));
    expect(boxes[0].right - boxes[0].left, 25);
    expect(boxes[1].right - boxes[1].left, 25);
    expect(boxes[1].left, boxes[0].right);
    expect(
      layout.paragraph.getBoxesForRange(3, 4),
      isNotEmpty,
      reason: '连续表情后的最后一个字必须保留',
    );
  });

  test('Douyin long emoji names use the same compact placeholder', () {
    final content = DanmakuContentItem(
      '[鲸鱼点赞][尴尬流汗]尾字',
      parts: const [
        DanmakuContentPart.image(
          'asset://assets/images/douyin_emoji/jingyudianzan.png',
          fallbackText: '[鲸鱼点赞]',
        ),
        DanmakuContentPart.image(
          'asset://assets/images/douyin_emoji/gangaliuhan.png',
          fallbackText: '[尴尬流汗]',
        ),
        DanmakuContentPart.text('尾字'),
      ],
    );

    final layout = Utils.prepareContent(content, 20, 4, 1.25, null, false);
    final boxes = layout.paragraph.getBoxesForPlaceholders();

    expect(boxes, hasLength(2));
    expect(boxes[0].right - boxes[0].left, 25);
    expect(boxes[1].right - boxes[1].left, 25);
    expect(boxes[1].left, boxes[0].right);
    expect(layout.paragraph.getBoxesForRange(3, 4), isNotEmpty);
  });

  test('missing image paints the literal fallback token', () async {
    final content = DanmakuContentItem(
      '[猪猪]',
      color: Colors.white,
      parts: const [
        DanmakuContentPart.image(
          'https://cdn.test/missing.png',
          fallbackText: '[猪猪]',
        ),
      ],
    );
    final layout = Utils.prepareContent(content, 24, 4, 1.25, null, false);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    Utils.drawEmojiImages(
      canvas,
      layout.paragraph,
      content,
      Offset.zero,
      const {},
      24,
      4,
      1.25,
      null,
    );

    final image = await recorder.endRecording().toImage(
          layout.size.width.ceil(),
          layout.size.height.ceil(),
        );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);
    var hasVisiblePixel = false;
    for (var i = 3; i < bytes!.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) != 0) {
        hasVisiblePixel = true;
        break;
      }
    }
    expect(hasVisiblePixel, isTrue);
  });
}
