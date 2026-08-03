import 'package:simple_live_core/src/danmaku/common_emoji_assets.dart';
import 'package:test/test.dart';

void main() {
  group('buildCommonEmojiSpans', () {
    test('命中映射转图片 span，文字保留', () {
      final spans = buildCommonEmojiSpans('你好[大笑]呀');
      expect(spans, hasLength(3));
      expect(spans[0].isText, isTrue);
      expect(spans[0].text, '你好');
      expect(spans[1].isImage, isTrue);
      expect(spans[1].imageUrl, commonEmojiAssets['[大笑]']);
      expect(spans[2].isText, isTrue);
      expect(spans[2].text, '呀');
    });

    test('未命中映射的方括号文本保持原样', () {
      final spans = buildCommonEmojiSpans('普通[文本]测试');
      expect(spans.where((s) => s.isImage), isEmpty);
      expect(spans.map((s) => s.text).join(), '普通[文本]测试');
    });

    test('混合多个表情与未知 token', () {
      final spans = buildCommonEmojiSpans('[666][不存在的]哈');
      expect(spans, hasLength(3));
      expect(spans[0].isImage, isTrue);
      expect(spans[0].imageUrl, commonEmojiAssets['[666]']);
      expect(spans[1].isText, isTrue);
      expect(spans[1].text, '[不存在的]');
      expect(spans[2].isText, isTrue);
      expect(spans[2].text, '哈');
    });

    test('纯文本无表情返回单个 text span', () {
      final spans = buildCommonEmojiSpans('就是普通弹幕');
      expect(spans, hasLength(1));
      expect(spans.single.isText, isTrue);
      expect(spans.single.text, '就是普通弹幕');
    });
  });
}
