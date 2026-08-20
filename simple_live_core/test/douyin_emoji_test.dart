import 'package:simple_live_core/src/danmaku/douyin_emoji_assets.dart';
import 'package:simple_live_core/src/danmaku/douyin_mobile_emoji_assets.dart';
import 'package:test/test.dart';

void main() {
  group('douyin emoji refresh', () {
    test('移动端表情目录完整并优先于网页静态表', () {
      expect(douyinMobileEmojiAssetCount, 455);
      expect(douyinMobileEmojiFileCount, 433);
      expect(douyinMobileEmojiAssets, hasLength(douyinMobileEmojiAssetCount));
      expect(
        douyinMobileEmojiAssets.values.toSet(),
        hasLength(douyinMobileEmojiFileCount),
      );
      expect(
        resolveDouyinEmoji('[微笑]'),
        'asset://assets/images/douyin_emoji/weixiao.png',
      );
      expect(
        douyinMobileEmojiAssets.entries.every(
          (entry) =>
              entry.key.startsWith('[') &&
              entry.key.endsWith(']') &&
              entry.value.startsWith(
                'asset://assets/images/douyin_emoji/',
              ),
        ),
        isTrue,
      );
    });

    test('动态映射覆盖优先，未覆盖项仍走移动端内置表', () async {
      await refreshDouyinEmoji(
        fetcher: () async => '{"status_code":0,"version":1,"emoji_list":['
            '{"display_name":"[新表情]","emoji_url":{"url_list":["https://cdn.test/emoji/new.png"]}},'
            '{"display_name":"[V5]","emoji_url":{"url_list":["https://cdn.test/emoji/v5.png"]}}'
            ']}',
      );
      expect(
        resolveDouyinEmoji('[新表情]'),
        'https://cdn.test/emoji/new.png',
      );
      expect(
        resolveDouyinEmoji('[微笑]'),
        douyinMobileEmojiAssets['[微笑]'],
      );
      // 动态表覆盖了 [V5]，应返回 CDN 图而非本地映射。
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
