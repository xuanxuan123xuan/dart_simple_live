import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_danmaku_status.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('抖音离线进入不连接，开播后连接且持续直播不重复连接', () {
    expect(shouldStartDouyinDanmaku(null, LiveStatusState.offline), isFalse);
    expect(shouldStartDouyinDanmaku(null, LiveStatusState.unknown), isFalse);
    expect(shouldStartDouyinDanmaku(null, LiveStatusState.live), isTrue);
    expect(
      shouldStartDouyinDanmaku(
        LiveStatusState.offline,
        LiveStatusState.live,
      ),
      isTrue,
    );
    expect(
      shouldStartDouyinDanmaku(
        LiveStatusState.live,
        LiveStatusState.live,
      ),
      isFalse,
    );
  });
}
