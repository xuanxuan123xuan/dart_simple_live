import 'package:simple_live_core/simple_live_core.dart';

/// 首次进入或从未开播恢复时连接；持续直播的轮询不重复连接。
bool shouldStartDouyinDanmaku(
  LiveStatusState? previous,
  LiveStatusState current,
) =>
    current == LiveStatusState.live && previous != LiveStatusState.live;

/// 进入直播间时，弹幕连接前的状态提示序列。
///
/// 快手弹幕依赖登录 Cookie：未配置（或当前无可用会话）时根本无法建立
/// 连接，不应一直停在"正在连接弹幕服务器"，而是直接提示未登录。
/// 未满足连接条件时不显示连接中的提示。
List<String> liveRoomDanmakuConnectMessages({
  required bool isKuaishou,
  required bool hasKuaishouCookie,
  bool canConnect = true,
}) {
  if (!canConnect) {
    return const [];
  }
  if (isKuaishou && !hasKuaishouCookie) {
    return const [
      "快手未登录（无 Cookie），弹幕不可用",
      "可在「我的 → 账号管理」登录快手账号后重试",
    ];
  }
  return const ["正在连接弹幕服务器"];
}
