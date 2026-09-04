import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_danmaku_status.dart';

void main() {
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
