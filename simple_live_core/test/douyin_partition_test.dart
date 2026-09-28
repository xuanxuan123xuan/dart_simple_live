import 'package:simple_live_core/src/douyin_partition_images.dart';
import 'package:test/test.dart';

void main() {
  group('douyinPartitionImages', () {
    /// 8 个一级分区（id_str 101~108）加游戏分区（103）下的 7 个二级分区
    /// （id_str 1~7）。二级分区图与一级分区图放在同一张表里，key 不重叠。
    const topLevelIds = {'101', '102', '103', '104', '105', '106', '107', '108'};
    const gameSubPartitionIds = {'1', '2', '3', '4', '5', '6', '7'};

    test('包含 8 个一级分区与游戏下 7 个二级分区', () {
      expect(
        douyinPartitionImages.keys.toSet(),
        topLevelIds.union(gameSubPartitionIds),
      );
    });

    test('每个 key 对应的都是合法 http(s) URL', () {
      douyinPartitionImages.forEach((id, url) {
        expect(isHttpImageUrl(url), isTrue, reason: '$id -> $url');
      });
    });

    test('二级分区图与一级分区图不共用 key', () {
      expect(
        topLevelIds.intersection(gameSubPartitionIds),
        isEmpty,
        reason: '二级 key 不能和一级 key 撞车，否则 103 的游戏图会被覆盖',
      );
    });
  });

  group('isHttpImageUrl', () {
    test('非 URL 字符串返回 false（分区 id 等）', () {
      expect(isHttpImageUrl('101'), isFalse);
      expect(isHttpImageUrl('103'), isFalse);
      expect(isHttpImageUrl('聊天'), isFalse);
      expect(isHttpImageUrl(''), isFalse);
    });

    test('真实 http(s) URL 返回 true', () {
      expect(isHttpImageUrl('https://i0.hdslb.com/bfs/live/a.png'), isTrue);
      expect(isHttpImageUrl('http://x.com/a.png'), isTrue);
    });

    test('非 http(s) 协议返回 false', () {
      expect(isHttpImageUrl('asset://assets/images/a.png'), isFalse);
      expect(isHttpImageUrl('file:///a.png'), isFalse);
      expect(isHttpImageUrl('data:image/png;base64,xxx'), isFalse);
    });
  });
}
