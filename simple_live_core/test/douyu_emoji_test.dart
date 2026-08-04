import 'package:simple_live_core/src/danmaku/common_emoji_assets.dart';
import 'package:simple_live_core/src/danmaku/douyu_emoji_assets.dart';
import 'package:test/test.dart';

void main() {
  group('buildDouyuEmojiSpans', () {
    test('斗鱼原版表情命中（[吃瓜]）', () {
      final spans = buildDouyuEmojiSpans('看戏[吃瓜]');
      expect(spans, hasLength(2));
      expect(spans[0].isText, isTrue);
      expect(spans[0].text, '看戏');
      expect(spans[1].isImage, isTrue);
      expect(spans[1].imageUrl, douyuEmojiAssets['[吃瓜]']);
    });

    test('未命中原版时回退通用 Twemoji（[哈哈]）', () {
      final spans = buildDouyuEmojiSpans('就[哈哈]');
      expect(spans, hasLength(2));
      expect(spans[1].isImage, isTrue);
      expect(spans[1].imageUrl, commonEmojiAssets['[哈哈]']);
    });

    test('未命中任何映射的方括号文本保持原样', () {
      final spans = buildDouyuEmojiSpans('普通[文本]');
      expect(spans.where((s) => s.isImage), isEmpty);
      expect(spans.map((s) => s.text).join(), '普通[文本]');
    });
  });
}
