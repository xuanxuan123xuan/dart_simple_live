# 小红书直播列表验证记录

2026-10-25 核对官网 `https://www.xiaohongshu.com/livelist?channel_id=0&channel_type=web_live_list`。

## 协议来源

- 官网 `index.a9f61821.js` 的 liveList store 使用 `category` 选择频道，初始 `cursorScore` 为字符串 `0`，`source` 为 13，`size` 为 27；下一页取最后一条 `feeds` 的 `cursorScore`。
- 官网 `vendor-dynamic.6e584070.js` 中两个 GET 封装分别访问 `/api/sns/red/live/web/feed/category` 和 `/api/sns/red/live/web/feed/v1/squarefeed`。
- PC 网页客户端负责完整的签名、设备头和请求序列化。列表桥接调用这两个官网封装，不使用直播间的 H5 签名函数。
- 官网 `LiveRoom.bb2c4fda.js` 的直播卡片读取 `live.tRoomInfo` 和 `live.tLiveHostInfo`，封面位于 `tRoomInfo.coverInfo`，房间号使用 `roomIdStr`，标题读取 `tRoomInfo.name`，人气读取 `tRoomInfo.displayCount`，主播名读取 `tLiveHostInfo.nickname`。分区渲染将 `categories[].id` 和 `categories[].desc` 转为 ID 和显示名称。

## 实测边界

本次全新隔离 Edge 匿名会话进入直播列表时被重定向至 `/website-login/error`，返回 `error_code=300012`，提示“IP存在风险，请切换可靠网络环境后重试”。无签名接口请求返回 HTTP 406。未使用用户浏览器配置或提取登录凭据。

因此本目录没有声称来自成功实测的列表 JSON 样本。目录解析测试中的响应是按官网脚本消费字段构造的模拟数据；JavaScript 契约、分页和会话测试不能代替真实服务验收。

待网络条件允许时，应分别以匿名会话和用户主动提供的可选 Cookie 验证：推荐首屏、第二页、分区列表、分区房间、刷新、卡片进房、空列表及失败重试。取得成功响应后，再添加脱敏样本并核对字段。设备端还需验证 Android/iOS/macOS/Linux WebView 和 Android TV 遥控导航。
