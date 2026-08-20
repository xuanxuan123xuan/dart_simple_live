# Twitch（老鼠台）平台接入构思大纲（待实施）

> 状态：构思阶段，未排期、未实施。
>
> 本文只用于确认接入边界与技术路线。在播放方案、OAuth 方案和网络代理方案确定前，不进入正式开发。

## 1. 目标

将 Twitch 作为第六个直播平台接入 Simple Live，尽量复用现有 `LiveSite`、聚合搜索、关注页、播放器和弹幕模型。

期望最终覆盖：

- 推荐直播与游戏分类；
- 房间搜索和主播搜索；
- 房间详情、直播状态和当前观看人数；
- 本地关注，以及可选的 Twitch 官方关注同步；
- 直播播放与清晰度切换；
- 聊天消息和 Twitch 官方表情；
- 主 App 与 TV 端的平台入口。

## 2. 一句话结论

Twitch 的列表、搜索、分类、直播状态和观看人数都有正式 API，接入现有数据模型难度不高；主要风险在原生播放地址、OAuth 凭据管理、国内网络可达性和聊天鉴权。

建议先完成“可浏览、可搜索、可关注”，再单独决定播放采用官方嵌入播放器还是非公开原生播放链路。

## 3. 暂不纳入首版

- 订阅、Bits、打赏和商业化功能；
- 发送聊天消息、管理频道或执行封禁操作；
- Clips、VOD 和回放列表；
- 7TV、BetterTTV、FrankerFaceZ 等第三方表情；
- 多 Twitch 账号切换；
- 自动跨平台主播去重。

## 4. 现有接口映射

| Simple Live 能力 | Twitch 数据来源 | 初步结论 |
|---|---|---|
| `getRecommendRooms` | 热门直播 `Get Streams` | 可直接实现 |
| `getCategores` | 热门游戏 `Get Top Games` | 可直接实现 |
| `getCategoryRooms` | 按 `game_id` 查询直播 | 可直接实现 |
| `searchRooms` | `Search Channels`，优先在线频道 | 可直接实现 |
| `searchAnchors` | `Search Channels` / `Get Users` | 可直接实现 |
| `getRoomDetail` | `Get Users` + `Get Streams` + 频道信息 | 可组合实现 |
| `getLiveStatusState` | `Get Streams` 是否返回目标频道 | 可直接实现 |
| `getPlayQualites` | 播放清单中的 variant | 取决于播放路线 |
| `getPlayUrls` | 官方嵌入播放器或原生 HLS | 核心决策点 |
| `getDanmaku` | EventSub WebSocket / IRC | 需要用户 OAuth |

### 4.1 数据字段建议

- `siteId`：`twitch`；
- `roomId`：使用稳定的 `broadcaster_user_id`，不要只保存可能改名的登录名；
- `LiveRoomItem.title`：直播标题；
- `LiveRoomItem.cover`：替换 Twitch 缩略图模板中的宽高占位符；
- `LiveRoomItem.userName`：优先显示 `user_name`；
- `LiveRoomItem.online`：直接使用 `viewer_count`；
- `LiveRoomDetail.data`：保存登录名、游戏 ID、语言等 Twitch 专属字段；
- 分页：把 Twitch cursor 包装进现有搜索/分类元数据，避免伪造页码。

## 5. 认证方案

Twitch Helix API 请求需要 `Client-Id` 和 OAuth Access Token。移动端不能把共享 `client_secret` 直接打包进应用。

候选方案：

### 方案 A：用户 OAuth 登录

- 应用注册一个 Twitch Client ID；
- 用户通过系统浏览器或设备授权流程登录；
- 客户端保存用户 Access Token，并按需要申请最小权限；
- 公共列表、官方关注和聊天统一使用用户 Token。

优点：不需要在安装包内保存 Client Secret，后续可支持官方关注和聊天。

缺点：首次使用 Twitch 必须登录，公共浏览门槛较高。

### 方案 B：轻量 Token 服务

- 服务端安全保存 Client Secret；
- 服务端获取 App Access Token，并代理或向客户端提供受控能力；
- 用户不登录也能浏览公共列表；
- 官方关注与聊天仍另走用户 OAuth。

优点：公共浏览体验最好。

缺点：引入服务端成本、可用性和隐私责任。

### 当前倾向

首版优先方案 A，避免为一个平台立即增加后端。必须支持“免登录浏览”时再评估方案 B。

## 6. 播放路线决策

### 路线 A：官方嵌入播放器

- 在 WebView 中打开 Twitch 官方 Embed Player；
- 遵循 Twitch 对 `parent`、域名和播放器参数的要求；
- 登录、广告与部分交互交由 Twitch 页面处理。

优点：官方支持、协议稳定、维护成本较低。

缺点：与现有 `media_kit` 播放器的手势、画中画、音量、缓存和多开体验不统一；TV 遥控器体验需要额外验证。

### 路线 B：原生 HLS 播放

- 获取播放访问令牌和 HLS master playlist；
- 将 variant 映射成现有 `LivePlayQuality`；
- 继续使用 `media_kit` 播放。

优点：能完整复用现有播放器、画中画和清晰度体系。

缺点：Twitch 没有面向第三方客户端公开稳定的原生 HLS API；相关链路可能随时变更，并存在合规和长期维护风险。

### 决策门

正式开发前必须明确：

1. 是否接受 Twitch 房间使用独立的 WebView 播放页；
2. 如果必须原生播放，是否接受非公开接口带来的维护成本；
3. TV 端是否允许第一版只跳转官方页面，稍后再补原生播放。

## 7. 关注页设计

### 7.1 本地关注

沿用 Simple Live 当前关注数据，不要求用户在 Twitch 官方账号中关注主播。

- 关注项保存 `broadcaster_user_id`；
- 登录名和显示名作为可更新字段；
- 刷新时批量请求多个主播的直播状态；
- 未返回的主播明确判定为离线，请求失败则保持 `unknown`；
- 当前观看人数使用 `viewer_count`。

Twitch 支持一次请求传多个 `user_id`，因此不应照搬逐房间刷新模式。

### 7.2 官方关注同步

作为可选增强：用户授权后读取 Twitch 官方关注列表，再选择导入本地关注。首版不自动双向写入，避免误操作和额外权限。

## 8. 聚合搜索设计

- 在 App 和 TV 的站点注册表中新增 `twitch`；
- 聚合搜索与其他平台并发，单独处理 OAuth 缺失、网络不可达和限流错误；
- Twitch 搜索结果优先展示正在直播的频道；
- `viewer_count` 直接进入当前火焰图标数字；
- 没有 Token 时显示明确的“登录 Twitch”操作，不显示成普通加载失败；
- 尊重 Twitch 返回的限流响应头，不进行高频自动重试。

## 9. 聊天与表情

### 9.1 聊天

优先采用 Twitch 推荐的 EventSub WebSocket：

- 使用用户 OAuth Token 建立会话；
- 订阅频道聊天消息；
- 将文本、用户名、颜色、徽章和表情片段映射到 `LiveMessage`；
- 页面退出、换房和 Token 失效时正确取消订阅；
- IRC 仅作为兼容备选，不作为第一实现。

首版只读聊天，不申请发送和管理权限。

### 9.2 官方表情

Twitch 表情不适合做成本地固定名称映射，应按远程资源处理：

- 根据消息片段中的 emote ID 组合官方图片地址；
- 复用或新增内存/磁盘图片缓存；
- 保留文本区间，避免表情替换后截断后续消息；
- 支持普通、动画和不同像素密度；
- 加载失败时回退为原始表情文本。

## 10. 网络与代理

当前项目的代理设置主要服务于远程同步，尚不是平台 API、图片、播放和 WebSocket 共用的全局代理。

Twitch 接入前需要补一个统一网络出口方案，至少覆盖：

- Helix API；
- OAuth 页面和 Token 请求；
- 图片 CDN；
- EventSub WebSocket；
- Twitch Embed 或原生 HLS；
- App、桌面端与 TV 端。

网络失败必须和“主播离线”“Token 失效”“接口限流”分开显示。

## 11. 代码结构草案

```text
simple_live_core/
  lib/src/twitch_site.dart
  lib/src/danmaku/twitch_danmaku.dart
  lib/src/common/twitch_api_client.dart
  lib/src/common/twitch_auth.dart

simple_live_app/
  lib/services/twitch_account_service.dart
  lib/modules/account/twitch_*.dart
  assets/images/twitch.png

simple_live_tv_app/
  Twitch 站点注册、账号授权入口和播放适配
```

建议把 Token 存储、刷新和权限检查放在 App 层；core 只接收可替换的认证提供者，避免 core 直接依赖 Hive、GetX 或平台安全存储。

## 12. 分阶段实施

### P0：可行性验证

- 注册测试应用并完成 OAuth；
- 验证目标网络环境下 API、图片、WebSocket 和 Embed 可达；
- 验证 App/Android TV 的官方嵌入播放器；
- 做一次原生播放路线的技术与合规评估；
- 确定最终播放路线。

### P1：公共数据与聚合搜索

- `TwitchSite` 基础实现；
- 推荐、分类、搜索、房间详情和观看人数；
- 主 App 注册第六个平台；
- 聚合搜索错误态和 OAuth 引导；
- 单元测试使用 fake transport，不依赖真实 Twitch 网络。

### P2：本地关注

- 关注项保存稳定用户 ID；
- 批量刷新在线状态；
- `live/offline/unknown` 三态；
- Token 失效与网络错误隔离。

### P3：播放

- 按已选路线实现 Embed 或原生播放；
- 验证清晰度、音量、横竖屏、画中画和多开；
- 验证广告、登录和地区限制场景。

### P4：聊天与官方表情

- EventSub WebSocket；
- 聊天消息模型映射；
- 官方表情远程渲染与缓存；
- 断线重连、Token 过期和换房取消。

### P5：TV 与体验收尾

- TV 站点注册与排序；
- 遥控器焦点、授权和播放器适配；
- 全平台回归与文档补齐。

## 13. 测试重点

- OAuth 缺失、过期、撤销和权限不足；
- 搜索 cursor 分页与切关键词取消；
- 多主播状态批量查询和部分失败；
- 限流响应与退避；
- 直播刚开播、刚下播和接口返回空列表；
- 缩略图模板替换；
- WebSocket 断开、重连和换房；
- 表情区间解析、连续表情与长弹幕不截断；
- 代理启用、直连失败和代理不可用；
- App、Windows、Android TV 和 HarmonyOS 的能力差异。

## 14. 首版验收口径

在选定的目标网络环境中：

1. 首页能看到 Twitch 推荐直播和当前观看人数；
2. 分类能按游戏浏览直播；
3. 聚合搜索能返回 Twitch 房间和主播；
4. 本地关注能批量刷新在线、离线和未知状态；
5. 点击直播间能通过选定播放路线稳定观看；
6. 页面退出后不残留请求、播放器或 WebSocket；
7. Token、Cookie 和授权信息不出现在普通日志中。

聊天和表情是否列入首版验收，等播放路线确定后再决定。

## 15. 待决策项

1. 首版是否允许强制 Twitch 登录；
2. 是否接受官方 WebView 播放；
3. 是否承担非公开原生播放链路的维护成本；
4. 是否在本轮同时建设全局代理；
5. 首版是否覆盖 TV；
6. 是否导入 Twitch 官方关注；
7. 聊天和官方表情是否与播放同时上线；
8. 未来是否接入 7TV/BTTV/FFZ。

## 16. 官方参考

- Twitch Authentication：<https://dev.twitch.tv/docs/authentication/>
- Twitch API：<https://dev.twitch.tv/docs/api/>
- Twitch API Reference：<https://dev.twitch.tv/docs/api/reference/>
- Twitch Chat & Chatbots：<https://dev.twitch.tv/docs/chat/>
- Twitch Video & Clips Embed：<https://dev.twitch.tv/docs/embed/video-and-clips/>
