import 'package:simple_live_core/src/douyin_partition_images.dart';
import 'package:test/test.dart';

void main() {
  group('douyinPartitionImages', () {
    test('8 个一级分区都有图且为合法 http(s) URL', () {
      expect(douyinPartitionImages.keys.toSet(), {'101', '102', '103', '104', '105', '106', '107', '108'});
      douyinPartitionImages.forEach((id, url) {
        expect(isHttpImageUrl(url), isTrue, reason: '$id -> $url');
      });
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
