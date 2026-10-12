import 'package:test/test.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('parses live SSR room and keeps H264 HLS/FLV variants', () {
    const url = 'https://live-source-play.xhscdn.com/live/room.m3u8';
    final html = '''<script>window.__INITIAL_STATE__=${'''{'''}
      "liveStream": {"roomData": {
        "liveStatus": "success",
        "roomInfo": {
          "status": 2,
          "title": "情绪价值",
          "cover": "https://img.example/cover.jpg",
          "displayViewerCount": "1.2万",
          "pullConfig": {"quality": "HD", "codec": "h264", "hlsUrl": "$url",
            "flvUrl": "https://live-source-play.xhscdn.com/live/room.flv"}
        },
        "hostInfo": {"nickname": "主播", "avatar": "https://img.example/avatar.jpg"}
      }}
    }${'}'};</script>''';

    final snapshot = XiaohongshuSite.parseRoomSnapshot(
      html,
      roomId: '570493541297105186',
    );
    expect(snapshot.live, isTrue);
    expect(snapshot.online, 12000);
    expect(snapshot.userName, '主播');
    expect(snapshot.streams, hasLength(1));
    expect(snapshot.streams.single.url, url);
    expect(snapshot.streams.single.flvUrl, contains('.flv'));
  });

  test('maps explicit end and incomplete states', () {
    final offline = XiaohongshuSite.parseRoomSnapshotFromMap({
      'liveStream': {
        'roomData': {
          'liveStatus': 'end',
          'roomInfo': {'status': 0, 'title': '结束'},
        },
      },
    }, roomId: '570321613446566013');
    expect(offline.liveStatusState, LiveStatusState.offline);

    final unknown = XiaohongshuSite.parseRoomSnapshotFromMap({
      'liveStream': {
        'roomData': {
          'liveStatus': 'success',
          'roomInfo': {'status': 1},
        },
      },
    }, roomId: '570321613446566013');
    expect(unknown.liveStatusState, LiveStatusState.unknown);
  });

  test('polling uses cursor and deduplicates comments', () async {
    final cursors = <int>[];
    final messages = <LiveMessage>[];
    final danmaku = XiaohongshuDanmaku()..onMessage = messages.add;
    await danmaku.start(XiaohongshuDanmakuArgs(
      roomId: '570493541297105186',
      fetchPage: (cursor) async {
        cursors.add(cursor);
        return XiaohongshuInteractionPage(
          comments: [
            XiaohongshuComment(
              id: 'c1',
              userName: '用户',
              message: '你好',
            ),
          ],
          endTimestamp: 10,
          nextRequestInterval: const Duration(hours: 1),
          viewerCount: 9,
          praiseCount: 0,
        );
      },
    ));
    expect(cursors, [0]);
    expect(messages.where((item) => item.type == LiveMessageType.chat),
        hasLength(1));
    await danmaku.stop();
  });
}
