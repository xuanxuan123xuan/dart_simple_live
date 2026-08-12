import 'package:fixnum/fixnum.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/danmaku/proto/douyin.pb.dart';
import 'package:test/test.dart';

void main() {
  test('Douyin online update uses current viewers instead of cumulative users',
      () {
    final messages = <LiveMessage>[];
    final danmaku = DouyinDanmaku()..onMessage = messages.add;
    final payload = RoomUserSeqMessage()
      ..total = Int64(321)
      ..totalUser = Int64(9876);

    danmaku.unPackWebcastRoomUserSeqMessage(payload.writeToBuffer());

    expect(messages, hasLength(1));
    expect(messages.single.type, LiveMessageType.online);
    expect(messages.single.data, 321);
  });
}
