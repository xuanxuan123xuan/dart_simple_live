/// 进入直播间时，弹幕连接前的状态提示序列。
///
/// 快手弹幕依赖登录 Cookie：未配置（或当前无可用会话）时根本无法建立
/// 连接，不应一直停在"正在连接弹幕服务器"，而是直接提示未登录。
/// 非快手平台始终返回"正在连接弹幕服务器"。
List<String> liveRoomDanmakuConnectMessages({
  required bool isKuaishou,
  required bool hasKuaishouCookie,
}) {
  if (isKuaishou && !hasKuaishouCookie) {
    return const [
      "快手未登录（无 Cookie），弹幕不可用",
      "可在「我的 → 账号管理」登录快手账号后重试",
    ];
  }
  return const ["正在连接弹幕服务器"];
}
