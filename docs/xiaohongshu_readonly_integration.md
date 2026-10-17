# 小红书直播只读接入与验收记录

本次新增小红书作为第六个平台。保留现有 `LiveSite` 接口，房间解析和视频播放匿名优先，Cookie 可选。实现不调用发送评论、点赞、礼物或平台关注接口。本地关注、历史记录和多开继续使用现有数据库与播放器。

## 当前行为

- 支持 `/livestream/<roomId>`、`/livestream/<alias>/<roomId>`、历史 `/hina/livestream/<roomId>/<timestamp>`，以及经过受限域名重定向的 `xhslink.com`。
- 读取直播页 SSR，处理 JavaScript `undefined`，解析 `roomTitle`、`roomCover`、主播和人数。
- `pullConfig` 支持当前 JSON 字符串格式及 `h264/h265` 数组、`master_url`、质量名称和宽高；优先 H.264，保留 HLS、FLV 与备用 CDN。播放请求带页面 Referer、User-Agent 和可选 Cookie。
- 评论使用 H5 互动接口的 `endTimestamp` 游标和服务端间隔；只映射 chat/online，有限重试，停止与重启隔离旧响应，停止时释放签名会话。
- WebView 只承担签名和 JSON 请求，使用网页自己的 `window.sign` / `window.f`。桥接仅允许已确认的五个 H5 GET 读取路径，禁止写方法和任意路径；406 只重建一次会话。
- Android/iOS/macOS 使用 InAppWebView；OHOS 使用 webview_flutter。Windows/Linux 已增加隐藏桌面签名会话，缺少 WebView2 或 WebKitGTK 运行库时提示具体原因，仍支持有效直播页的 SSR 与播放。跨场次身份恢复和更新后的平台验证见[主播身份与跨场次解析](xiaohongshu_anchor_resolution.md)。
- 多个房间共享同源签名页面，请求串行执行。关闭房间取消它的排队/在途请求；最后一个房间关闭时卸载页面。视频在原生播放器播放，签名页面禁用媒体播放。
- 没有取得可验证的直播目录协议。`XiaohongshuDiscoveryClient` 返回明确的不可用结果，搜索 metadata 是 fallback/unknown。推荐、分类和搜索界面显示“当前只能通过直播链接进入”，不从普通笔记伪造直播卡片。
- 账号页支持粘贴、配置状态与清除 Cookie；Cookie 放入独立的备份 accounts 字段，并从 settings 导出排除。日志对 Cookie、签名和小红书原始响应脱敏。
- 配置变更仅清理本账号注入的小红书 Cookie，不清空其他站点的浏览器 Cookie。
- 房间状态失败保留 unknown；结束后停止评论轮询并保留有效标题、封面和主播元数据。

## 2026-10-12 验证

### 静态与自动化

- 新增核心、账号、WebView、解析文件 `dart analyze`：无问题。
- 应用相关改动分析：无 error/warning；直播间控制器有 10 条原有 prefer_const_constructors 信息，未改动相关代码。
- 小红书核心解析、轮询、响应日志，以及 HTTP 脱敏/取消回归：30 项通过。
- Flutter 应用定向回归：80 项通过，覆盖链接、站点排序迁移、Cookie 与备份恢复、签名桥、排队取消、多房间共享、六站点选择器、搜索聚合、关注状态和配置包。
- 网页请求 JS 由 Node 执行实际脚本，mock 网页签名/fetch/bridge：签名成功、签名缺失、HTTP 406 三种情况通过。
- 核心扩大回归（排除原有联网直播 smoke 文件）：316 项通过、5 项快手测试失败。这五项也在本次改动前的 `dee552b5` 核心源码中复现，未纳入本次修复。
- 普通 `dart test` 包含多个平台真实直播与 30 秒弹幕 smoke，运行中出现既有失败，未作为全绿结果宣称。
- 没有构建或安装新的 APK/HAP；离线测试不等于设备验收。

### 新鲜匿名接口探测

使用 `simple_live_core/tool/probe_xiaohongshu.dart`，没有 Cookie、没有签名，探测不输出凭据或媒体 URL：

- 房间 `570493541297105186`：live；标题/主播/封面存在，人数解析为 10000，比例 0.5625，原画与 4 条线路。
- HLS：HTTP 200，正文以 `#EXTM3U` 开头。
- FLV：HTTP 200，读取并立即取消流，前三字节为 `FLV`。
- 未签名互动接口：HTTP 406，证明该请求需要签名会话。
- 已结束样本 `570321613446566013`：offline，标题/主播/封面仍能解析。
- `test/fixtures/xiaohongshu/live_ssr.json` 是本次匿名直播页实际响应中抽取的公开房间字段，不是目录或评论接口的实播验收。

可从核心包运行：

```powershell
dart run tool/probe_xiaohongshu.dart <当前房间号>
```

房间随时可能结束，重新运行时以当次结果为准。

## 仍待验收或受限的项目

- Android/iOS/macOS/OHOS 的真实 WebView 签名、Cookie 注入、实时评论与人数刷新。
- 2026-10-17 已取得 Windows 原生播放器实际视频画面，详见跨场次解析记录；其他设备、清晰度切换、竖屏表现与直播结束流程仍待验收。HTTP 媒体探测不能代替这些验收。
- 当前分享短链的真实跳转；自动化已验证受限跳转、非法目标和循环拒绝。
- 推荐、分类、搜索真实目录响应。取得稳定的接口路径、分页参数和 fixture 后才开放目录。
- Cookie 外发同步：自动审批拒绝了本地 HTTP、SignalR/WebDAV 发送端修改，理由是具体接收目标及中继信任范围未明确。现有改动只有本地存储、离线备份/恢复及 `/sync/account/xiaohongshu` 接收路由，没有新增专用发送端。已有本地全量同步与 WebDAV 打包也显式排除小红书 Cookie，避免通过通用备份路径间接外发；本地备份文件仍保留恢复能力。补发送端前需要明确允许的目标地址/设备和中继范围。

所有变更只提交到本地，不推送、不创建 PR。原有脏文件、生成文件和其他任务内容保留。
