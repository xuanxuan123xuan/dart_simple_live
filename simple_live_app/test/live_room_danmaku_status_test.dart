import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_app/modules/live_room/live_room_danmaku_status.dart';

void main() {
  test('抖音离线进入不连接，开播后连接且持续直播不重复连接', () {
    expect(shouldStartDouyinDanmaku(null, LiveStatusState.offline), isFalse);
    expect(shouldStartDouyinDanmaku(null, LiveStatusState.unknown), isFalse);
    expect(shouldStartDouyinDanmaku(null, LiveStatusState.live), isTrue);
    expect(
        shouldStartDouyinDanmaku(LiveStatusState.offline, LiveStatusState.live),
        isTrue);
    expect(shouldStartDouyinDanmaku(LiveStatusState.live, LiveStatusState.live),
        isFalse);
    expect(
        liveRoomDanmakuConnectMessages(
            isKuaishou: false, hasKuaishouCookie: true, canConnect: false),
        isEmpty);
  });
  group('liveRoomDanmakuConnectMessages', () {
    test('快手未登录（无 Cookie）时不显示"正在连接弹幕服务器"', () {
      final messages = liveRoomDanmakuConnectMessages(
        isKuaishou: true,
        hasKuaishouCookie: false,
      );
      expect(messages, [
        "快手未登录（无 Cookie），弹幕不可用",
        "可在「我的 → 账号管理」登录快手账号后重试",
      ]);
      expect(messages, isNot(contains('正在连接弹幕服务器')));
    });

    test('快手已配置 Cookie 时显示"正在连接弹幕服务器"', () {
      expect(
        liveRoomDanmakuConnectMessages(
          isKuaishou: true,
          hasKuaishouCookie: true,
        ),
        ['正在连接弹幕服务器'],
      );
    });

    test('非快手平台始终显示"正在连接弹幕服务器"', () {
      expect(
        liveRoomDanmakuConnectMessages(
          isKuaishou: false,
          hasKuaishouCookie: false,
        ),
        ['正在连接弹幕服务器'],
      );
    });
  });
}
