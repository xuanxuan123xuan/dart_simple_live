import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';

void main() {
  test('parses direct livestream and dynpath links', () async {
    final parser = LiveRoomLinkParser();
    for (final input in [
      'https://www.xiaohongshu.com/livestream/570493541297105186',
      'https://www.xiaohongshu.com/livestream/abc/570493541297105186',
      'https://www.xiaohongshu.com/hina/livestream/570493541297105186/1720000000',
    ]) {
      final target = await parser.parse('$input，');
      expect(target?.site.id, Constant.kXiaohongshu);
      expect(target?.roomId, '570493541297105186');
    }
  });

  test('resolves a trusted short link to its numeric room', () async {
    final parser = LiveRoomLinkParser(
        locationResolver: (_) async =>
            'https://www.xiaohongshu.com/livestream/alias/570493541297105186');
    expect((await parser.parse('https://xhslink.com/a/abc'))?.roomId,
        '570493541297105186');
  });

  test('rejects invalid ids, credentials, ports and short redirect loops',
      () async {
    final parser = LiveRoomLinkParser(locationResolver: (url) async => url);
    for (final url in [
      'https://www.xiaohongshu.com/livestream/invalid',
      'https://www.xiaohongshu.com/foo/livestream/570493541297105186',
      'https://user@www.xiaohongshu.com/livestream/570493541297105186',
      'https://www.xiaohongshu.com:444/livestream/570493541297105186',
      'https://xhslink.com/a/loop',
    ]) {
      expect(await parser.parse(url), isNull);
    }
  });

  test('rejects ordinary pages and untrusted redirects', () async {
    final parser = LiveRoomLinkParser(
      locationResolver: (_) async =>
          'https://example.com/livestream/570493541297105186',
    );
    expect(
        await parser.parse('https://www.xiaohongshu.com/explore/123'), isNull);
    expect(await parser.parse('https://xhslink.com/a/abc'), isNull);
  });
}
