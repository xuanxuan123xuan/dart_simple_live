import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';

void main() {
  const room = '570493541297105186';
  const host = '0123456789abcdef01234567';
  test('XHS room IDs and supported livestream links retain host metadata',
      () async {
    final parser = LiveRoomLinkParser();
    for (final url in [
      room,
      'https://www.xiaohongshu.com/livestream/$room?host_id=$host',
      'https://www.xiaohongshu.com/hina/livestream/$room/123'
    ]) {
      final target = await parser.parse(url, roomSiteId: Constant.kXiaohongshu);
      expect(target?.roomId, room);
      expect(target?.site.id, Constant.kXiaohongshu);
      if (url.contains('host_id')) expect(target?.xiaohongshuHostId, host);
    }
  });
  test('XHS short links resolve only to a trusted live room', () async {
    final parser = LiveRoomLinkParser(
        locationResolver: (_) async =>
            'https://www.xiaohongshu.com/livestream/$room');
    expect((await parser.parse('https://xhslink.com/a/abc'))?.roomId, room);
    for (final destination in [
      'https://evil.test/livestream/$room',
      'https://www.xiaohongshu.com/explore/$room',
      'https://user@www.xiaohongshu.com/livestream/$room',
      'https://www.xiaohongshu.com:8443/livestream/$room'
    ]) {
      expect(
          await LiveRoomLinkParser(locationResolver: (_) async => destination)
              .parse('https://xhslink.com/a/abc'),
          isNull);
    }
  });
  test('rejects ordinary notes, lookalike hosts and malformed XHS IDs',
      () async {
    final parser = LiveRoomLinkParser();
    for (final input in [
      'https://www.xiaohongshu.com/explore/$room',
      'https://www.xiaohongshu.com/user/profile/$host',
      'https://xiaohongshu.com.evil.test/livestream/$room',
      'https://www.xiaohongshu.com/livestream/abc',
      '123',
      '../12345678'
    ]) {
      expect(
          await parser.parse(input, roomSiteId: Constant.kXiaohongshu), isNull);
    }
  });
}
