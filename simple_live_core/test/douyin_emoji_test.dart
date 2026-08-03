import 'package:simple_live_core/src/danmaku/douyin_emoji_assets.dart';
import 'package:test/test.dart';

void main() {
  group('douyin emoji refresh', () {
    test('静态表兜底：未刷新时命中内置映射', () {
      expect(
        resolveDouyinEmoji('[V5]'),
        douyinEmojiAssets['[V5]'],
      );
    });

    test('动态映射覆盖优先，未覆盖项仍走静态表', () async {
      await refreshDouyinEmoji(
        fetcher: () async =>
            '{"status_code":0,"version":1,"emoji_list":['
            '{"display_name":"[新表情]","emoji_url":{"url_list":["https://cdn.test/emoji/new.png"]}},'
            '{"display_name":"[V5]","emoji_url":{"url_list":["https://cdn.test/emoji/v5.png"]}}'
            ']}',
      );
      expect(
        resolveDouyinEmoji('[新表情]'),
        'https://cdn.test/emoji/new.png',
      );
      // 动态表覆盖了 [V5]，应返回 CDN 图而非本地 asset。
      expect(
        resolveDouyinEmoji('[V5]'),
        'https://cdn.test/emoji/v5.png',
      );
    });

    test('刷新失败静默降级，内置表仍可用', () async {
      await refreshDouyinEmoji(
        fetcher: () async => throw Exception('network down'),
      );
      expect(resolveDouyinEmoji('[V5]'), isNotNull);
    });
  });
}
