<p align="center">
    <img width="128" src="/assets/logo.png" alt="Simple Live logo">
</p>
<h2 align="center">Simple Live — 鸿蒙 / 多开分支</h2>

<p align="center">
简简单单的看直播 · <code>feat/ohos-1.12.7</code>
</p>

![浅色模式](/assets/screenshot_light.jpg)

![深色模式](/assets/screenshot_dark.jpg)

> **Release 资产**：本仓库提供阶段性 `Release` 安装包与压缩包，见 [GitHub Releases](https://github.com/xuanxuan123xuan/dart_simple_live/releases) 页面。

---

## 这个分支是什么

本仓库 fork 自 [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)，`feat/ohos-1.12.7` 是一个长期维护的独立分支，主要做两件事：

1. **鸿蒙 NEXT 适配**：完整的 OHOS 端口，包含 ArkTS 原生插件层（播放器、截图、扫码、Cookie、文件管理、PIP、网络信息）、服务卡片（关注主播开播状态）、后台开播检查（WorkScheduler + 用户开关）、以及 QuickJS FFI 签名桥接（抖音）。
2. **多开同屏**：在同一窗口内并排播放多个直播间，每格独立弹幕，画面等比缩放不裁切，布局自适应。

鸿蒙端口的代价是 **Flutter 版本钉死在 3.22 线**（`pubspec.yaml` 有 7 处依赖与 3.22 对齐），与主线的 Flutter 3.41 互斥，无法直接合并。

---

## 功能亮点

### 多开同屏

从关注页进入：点多开按钮进多选态，选 2 个以上正在直播的关注即可。

- **平板支持**：按屏幕短边 ≥ 600 逻辑像素判定，iPad、安卓平板均可多开，手机不支持。
- **桌面端**（Windows / macOS）会优先拉起多个独立系统窗口；失败或其他平台则退回单窗口同屏。
- **排布自适应**：横屏放两个会排成上下两行（画面比左右并排大约 1.18 倍）；三个排成 2×2 空一格。
- **画面等比缩放不裁切**，比例不符时留黑边。
- **每格独立弹幕**，只收不发。弹幕行数按格子高度自适应，格子过矮时自动隐藏。
- 鸿蒙暂不支持多开：该平台不初始化 media_kit，播放走 `video_player_ohos`。

### 鸿蒙 NEXT

| 能力 | 实现方式 |
|---|---|
| 直播播放 | `video_player_ohos` / AVPlayer，非 media_kit |
| 弹幕 | 平台无关，复用 `simple_live_core` WebSocket |
| 截图 | 原生 `ohos_media` 通道，用户取消正确处理为"取消保存"而非报错 |
| 扫码 | 原生 `ohos_scan` 通道（`@kit.ScanKit`） |
| 抖音搜索 | QuickJS FFI 桥接，`.so` 预编译 |
| 服务卡片 | `FollowFormAbility` + `OhosWidgetPlugin`，关注主播开播状态一目了然 |
| 后台开播提醒 | `FollowCheckExtension`（WorkScheduler），用户可在设置中开关 |
| Cookie 管理 | 原生 `ohos_web_cookie` 通道 |
| PIP 画中画 | 原生 `ohos_pip` 通道 |
| 文件管理 | 原生 `ohos_documents` 通道 |

### 通用功能

- 虎牙、斗鱼、哔哩哔哩、抖音、快手五大平台直播
- 弹幕（只收不发）
- 关注管理、标签分组、分页浏览
- 播放画质 / 线路选择
- 远程同步（Cloudflare Workers 临时房间 + 自建地址）
- 配置导入导出（设置、关注、标签、历史、弹幕屏蔽词）
- 桌面端小窗 / 画中画
- 实时字幕（桌面端，需本地 Whisper 模型）

---

## APP 支持平台

| 平台 | 状态 | 说明 |
|---|---|---|
| Android | ✅ | 主线 APK |
| iOS | ✅ | 未签名 IPA 或 AltStore 侧载 |
| Windows | ✅ | 主线 zip |
| macOS | ✅ | 主线 dmg / zip |
| Linux | ✅ | zip / deb |
| Android TV | ✅ | 拆分 APK（按 ABI） |
| TV-windows | ✅ | TV 的 UI 在 Windows 上运行，支持多开 |
| HarmonyOS NEXT | ✅ | 本分支 `feat/ohos-1.12.7`，见下方构建 |

---

## 用户群

扫码加入 SimpleLive 用户群，交流使用问题和反馈建议。

<p align="center">
  <img width="360" src="/assets/user_group_wechat.jpg" alt="SimpleLive 用户群二维码">
</p>

---

## 环境

| 构建目标 | Flutter 版本 | 说明 |
|---|---|---|
| Windows / Android / Android TV | 3.41.9 | 主线 |
| Linux | 3.38.10 | 主线 WSL |
| **本分支所有目标** | **3.22.x** | `feat/ohos-1.12.7`，pubspec 钉死 |
| 鸿蒙 HAP | 3.22 线 OHOS fork | `tool/build_ohos_hap.ps1` 自带 |

本分支的 `pubspec.yaml` 有 7 处依赖按 Flutter 3.22 钉死（`intl`、`archive`、`lottie`、`package_info_plus`、`window_manager`、`shelf`、`dynamic_color`），换用更新的 Flutter 会在 `flutter_localizations` 的 `intl` 传递依赖上解析失败，需连同这些依赖一起升级。

注意：`simple_live_app/.fvmrc` 里写的 `3.38.3` 与本目录 pubspec 并不匹配，所有构建流程均不读取它。

---

## 构建

GitHub Actions 提供这些构建流程，均为手动触发（`workflow_dispatch`）：

| workflow | 产物 | runner | 说明 |
|---|---|---|---|
| `build_ios_ipa_ohos_branch.yml` | iOS `ipa` | `macos-14` | 本分支专用；钉 Flutter `3.22.3` + Xcode `15.4` |
| `build_ohos_hap.yml` | 鸿蒙 `hap`（已签名） | 自建 Windows | 需自建 runner，官方工具约 2.4 GB 且需账号登录 |
| `publish_app_release_*.yml` | 各平台正式包 | GitHub 托管 | 主线用，本分支不适用 |

### iOS IPA

- 钉 Flutter `3.22.3` + Xcode `15.4`（Flutter 3.22 早于 Xcode 16，用 16.x 会在链接期报错）。
- runner 用 `macos-14`（该镜像 2026-11-02 后不可用，届时需连同 Flutter 版本一起升级）。
- 默认产**未签名 IPA**，需 AltStore / Sideloadly 侧载。
- 配好 `IOS_CERT_P12_BASE64`、`IOS_CERT_PASSWORD`、`IOS_PROVISIONING_PROFILE_BASE64`、`IOS_TEAM_ID` 四个 secrets 后可勾选签名构建，产出 ad-hoc 签名包。

### 鸿蒙 HAP

- 必须用自建 runner：官方命令行工具约 2.4 GB 且需账号登录，GitHub 托管 runner 无法安装。
- 需配置仓库变量：`FLUTTER_OHOS_ROOT`、`HOS_SDK_HOME`、`JAVA_HOME`。
- 需配置签名 secrets：`OHOS_KEYSTORE_P12_BASE64`、`OHOS_PROFILE_CERT_PEM_BASE64`、`OHOS_APP_CERT_CHAIN_PEM_BASE64`、`OHOS_PROFILE_JSON_BASE64`、`OHOS_KEYSTORE_PASSWORD`、`OHOS_KEY_PASSWORD`。
- 本地构建见 `simple_live_app/tool/build_ohos_hap.ps1`。

### Release 资产

当前提供这些正式资产（主线）：

- Android `apk`
- Android TV 拆分 `apk`（`arm64-v8a` / `armeabi-v7a` / `x86_64`）
- Windows `zip`
- Linux `zip` / `deb`

鸿蒙 `hap` 与 iOS `ipa` 不随 Release 发布，需自行用对应 workflow 构建。

---

## 远程同步服务

当前远程同步使用自建 Cloudflare Workers 临时房间服务：

- 服务状态页：`https://simple-live-sync.3439394104.workers.dev`
- App 内 WebSocket 地址：`wss://simple-live-sync.3439394104.workers.dev/sync`

普通用户不需要自己配置服务器；创建房间、扫码或输入房间号即可同步。浏览器直接打开 `/sync` 显示 `websocket upgrade required` 是正常的。

已知限制：房间 600 秒后自动过期；创建者退出后房间销毁；单房间最多 8 个连接；单条消息最大 1 MB；不保存任何用户数据。这不是账号云同步，不会跨天、跨设备持续自动同步。

可配置项见 App 内 `其他设置 -> 同步服务地址` 和 `同步代理地址`。如果所在网络无法访问 `workers.dev`，可改用局域网同步、WebDAV，或填写自建地址。

---

## 配置导入

新版配置包导出设置、关注、标签、历史、弹幕屏蔽词和屏蔽词预设；Cookie、WebDAV 密码等敏感内容默认不写入。

- 支持导入新版 `simple_live_profile.json`。
- 支持导入旧版 `simple_live_config.json`（通常只含设置和弹幕屏蔽词）。
- 兼容旧 WebDAV/同步备份里的关注、标签、历史数组格式。

---

## 抖音搜索 Cookie

抖音播放可使用内置 `ttwid` 兜底，但房间名 / 主播名搜索经常要求登录态。搜索不可用时，在 `账号管理 -> 抖音 -> Cookie登录` 粘贴桌面浏览器登录后的完整 Cookie。

电脑端获取：打开 `www.douyin.com` → `F12` → `Network` → 刷新 → 点任意 `douyin.com` 请求 → `Request Headers` → 复制完整 `cookie`。应用也兼容直接粘贴 `Cookie: xxx` 或整段请求头，会自动提取。

抖音账号页会尝试从 `sid_guard` 解析 Cookie 剩余有效期；只配置 `ttwid` 时无法判断。Cookie 仍可能因退出登录、改密或平台风控提前失效。

TV 端不内置浏览器，请从主 App 同步完整 Cookie。

---

## 参考及引用

[AllLive](https://github.com/xiaoyaocz/AllLive) `本项目的 C# 版`

[xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live) `上游 fork 来源`

[dart_tars_protocol](https://github.com/xiaoyaocz/dart_tars_protocol.git)

[wbt5/real-url](https://github.com/wbt5/real-url)

[lovelyyoshino/Bilibili-Live-API](https://github.com/lovelyyoshino/Bilibili-Live-API/blob/master/API.WebSocket.md)

[IsoaSFlus/danmaku](https://github.com/IsoaSFlus/danmaku)

[BacooTang/huya-danmu](https://github.com/BacooTang/huya-danmu)

[TarsCloud/Tars](https://github.com/TarsCloud/Tars)

[YunzhiYike/douyin-live](https://github.com/YunzhiYike/douyin-live)

[5ime/Tiktok_Signature](https://github.com/5ime/Tiktok_Signature)

[EmojiAll 抖音平台表情](https://www.emojiall.com/zh-hans/platform-douyin) `感谢提供抖音平台表情参考，项目内仅作为本地静态表情资源使用`

---

## 声明

本项目的功能基于互联网上公开资料整理与开发，无任何破解、逆向工程等行为。

本项目仅用于学习交流编程技术，严禁用于商业目的。如有任何商业行为，均与本项目无关。

如果本项目存在侵犯您合法权益的情况，请及时联系开发者，开发者会及时处理相关内容。

## 绝对禁止更新的一些功能

> [!WARNING]
>
> 不碰账号，不碰钱，不碰写操作，不碰官方活动。

- 官方账号登录、注册、找回密码、实名、绑定手机、未成年人模式。
- 官方账号维度的关注、取关、拉黑、消息已读、历史同步、收藏同步。
- 任何充值相关功能：钱包、余额、B币、银瓜子、金瓜子、虎牙币、电池、礼物背包、订单、退款、兑换码、优惠券。
- 任何付费互动：送礼物、上头条、上舰、续费大航海、开贵族、点亮粉丝牌、付费表情、充电、打赏。
- 任何"发出去"的直播互动：发送弹幕、评论、点赞、分享任务、投票、PK 助力、上麦申请、连麦申请。
- 任何社交功能：点赞、私信、群聊、应援团消息、用户聊天、主播私信。
- 任何治理功能：举报、申诉、房管、禁言、踢人、拉黑官方账号关系。
- 任何官方活动：抽奖、福袋、红包、竞猜、宝箱、签到、任务中心、经验成长、勋章升级、直播间成就。
- 任何主播后台：开播、改标题、改分区、公告、商品橱窗、收益、数据后台、粉丝管理。
- 任何电商闭环：直播间购物、商品跳转下单、会员购、店铺、带货组件。
- 离线缓存、录播下载、源流下载、批量导出。
- 完整首页推荐流、热榜、官方消息中心、Push 通知中心。
- 动态发布、评论发布、社区互动、投稿。
- 官方账号体系下的"我的"页面复刻，比如钱包、勋章、等级、任务、资产全量展示。
- 过于完整的录播 / 回放 / 追更体系，尤其是能替代用户回到官方 App 的那种。

---

## Star History

![star-history-202676](./images/README/star-history-202676.png)
