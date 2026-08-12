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
    expect(layout.size.width, layout.paragraph.longestLine.ceilToDouble());
    expect(
      layout.paragraph.getBoxesForRange(
        leadingText.length + 1 + trailingText.length - 1,
        leadingText.length + 1 + trailingText.length,
      ),
      isNotEmpty,
      reason: '表情后的最后一个字符必须保留在单行 Paragraph 中',
    );
  });

  test('fallback token width is reserved and responds to style changes', () {
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
    final fallbackPainter = TextPainter(
      text: const TextSpan(text: token, style: TextStyle(fontSize: 16)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final box = normal.paragraph.getBoxesForPlaceholders().single;
    expect(box.right - box.left, greaterThanOrEqualTo(fallbackPainter.width));
    expect(larger.size.width, greaterThan(normal.size.width));
    expect(larger.size.height, greaterThan(normal.size.height));
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
