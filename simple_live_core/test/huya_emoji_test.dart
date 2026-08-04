import 'package:simple_live_core/src/danmaku/common_emoji_assets.dart';
import 'package:simple_live_core/src/danmaku/huya_emoji_assets.dart';
import 'package:test/test.dart';

void main() {
  group('buildHuyaEmojiSpans', () {
    test('虎牙原版表情命中（[大笑]）', () {
      final spans = buildHuyaEmojiSpans('哈哈[大笑]');
      expect(spans, hasLength(2));
      expect(spans[0].isText, isTrue);
      expect(spans[0].text, '哈哈');
      expect(spans[1].isImage, isTrue);
      expect(spans[1].imageUrl, huyaEmojiAssets['[大笑]']);
    });

    test('未命中原版时回退通用 Twemoji（[哈哈]）', () {
      final spans = buildHuyaEmojiSpans('就[哈哈]');
      expect(spans, hasLength(2));
      expect(spans[1].isImage, isTrue);
      expect(spans[1].imageUrl, commonEmojiAssets['[哈哈]']);
      // 回退 URL 与虎牙原版不同（证明走的是通用表）
      expect(spans[1].imageUrl, isNot(huyaEmojiAssets['[大笑]']));
    });

    test('未命中任何映射的方括号文本保持原样', () {
      final spans = buildHuyaEmojiSpans('普通[文本]');
      expect(spans.where((s) => s.isImage), isEmpty);
      expect(spans.map((s) => s.text).join(), '普通[文本]');
    });
  });
}
