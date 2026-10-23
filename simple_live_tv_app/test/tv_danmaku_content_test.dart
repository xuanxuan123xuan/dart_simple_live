import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_danmaku_content.dart';

LiveMessage _message({
  String text = '',
  List<LiveMessageSpan>? spans,
  List<String>? imageUrls,
  LiveMessageColor? color,
}) {
  return LiveMessage(
    type: LiveMessageType.chat,
    userName: '观众',
    message: text,
    color: color ?? LiveMessageColor(255, 128, 0),
    spans: spans,
    imageUrls: imageUrls,
  );
}

void main() {
  test('keeps text, image and text in the original order', () {
    final content = buildTvDanmakuContent(
      _message(
        text: '送你礼物',
        spans: const [
          LiveMessageSpan.text('送你'),
          LiveMessageSpan.image('https://cdn.example/a.png',
              fallbackText: '[a]'),
          LiveMessageSpan.text('礼物'),
        ],
      ),
      renderEmoji: true,
    );

    expect(content.text, '送你礼物');
    expect(content.color, const Color.fromARGB(255, 255, 128, 0));
    final parts = content.parts!;
    expect(parts, hasLength(3));
    expect(parts[0].isText, isTrue);
    expect(parts[0].text, '送你');
    expect(parts[1].isImage, isTrue);
    expect(parts[1].imageUrl, 'https://cdn.example/a.png');
    expect(parts[1].fallbackText, '[a]');
    expect(parts[2].isText, isTrue);
    expect(parts[2].text, '礼物');
    expect(content.imageUrls, isNull);
  });

  test('keeps repeated emoji instead of collapsing duplicates', () {
    final content = buildTvDanmakuContent(
      _message(
        text: '哈哈哈',
        spans: const [
          LiveMessageSpan.image('https://cdn.example/haha.png'),
          LiveMessageSpan.image('https://cdn.example/haha.png'),
        ],
      ),
      renderEmoji: true,
    );

    expect(
      content.parts!.map((part) => part.imageUrl),
      ['https://cdn.example/haha.png', 'https://cdn.example/haha.png'],
    );
  });

  test('falls back to imageUrls when no span data is present', () {
    final content = buildTvDanmakuContent(
      _message(
        text: '表情弹幕',
        imageUrls: const [
          'https://cdn.example/one.png',
          'https://cdn.example/two.png',
        ],
      ),
      renderEmoji: true,
    );

    expect(content.parts, isNull);
    expect(content.imageUrls, [
      'https://cdn.example/one.png',
      'https://cdn.example/two.png',
    ]);
  });

  test('empty spans fall back to imageUrls as well', () {
    final content = buildTvDanmakuContent(
      _message(
        text: '表情弹幕',
        spans: const [],
        imageUrls: const ['https://cdn.example/one.png'],
      ),
      renderEmoji: true,
    );

    expect(content.parts, isNull);
    expect(content.imageUrls, ['https://cdn.example/one.png']);
  });

  test('disabled emoji rendering sends no image data at all', () {
    final content = buildTvDanmakuContent(
      _message(
        text: '表情弹幕',
        spans: const [
          LiveMessageSpan.text('表情'),
          LiveMessageSpan.image('https://cdn.example/one.png',
              fallbackText: '[表情]'),
        ],
        imageUrls: const ['https://cdn.example/one.png'],
      ),
      renderEmoji: false,
    );

    expect(content.text, '表情弹幕');
    expect(content.parts, isNull);
    expect(content.imageUrls, isNull);
  });

  test('missing image url keeps the fallback text', () {
    final content = buildTvDanmakuContent(
      _message(
        text: '送你[表情]',
        spans: const [
          LiveMessageSpan.text('送你'),
          LiveMessageSpan.image('   ', fallbackText: '[表情]'),
        ],
      ),
      renderEmoji: true,
    );

    final parts = content.parts!;
    expect(parts, hasLength(2));
    expect(parts[0].text, '送你');
    expect(parts[1].isText, isTrue);
    expect(parts[1].text, '[表情]');
  });

  test('spans without drawable content fall back to imageUrls', () {
    expect(buildTvDanmakuContentParts(const []), isNull);
    expect(
      buildTvDanmakuContentParts(const [LiveMessageSpan.text('')]),
      isNull,
    );
    expect(
      buildTvDanmakuContentParts(const [LiveMessageSpan.image('')]),
      isNull,
    );
  });
}
