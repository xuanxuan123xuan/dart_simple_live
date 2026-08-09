# HarmonyOS 直播起播与恢复稳定性

> 状态：待实施
> 适用平台：HarmonyOS
> 覆盖问题：快手部分房间持续转圈、抖音首次进房黑屏后刷新恢复
> 不包含：快手账号治理、多开同屏

## 1. 结论

两个问题都发生在房间详情和播放地址成功返回之后，且刷新会完整重建播放器并恢复。优先修复 AVPlayer 媒体源设置竞态、错误吞掉和无请求头 FLV 的建链路径，再调整播放恢复；不能通过频繁刷新房间详情或改成 HLS 掩盖原生播放器问题。

## 2. 证据

### 2.1 快手持续转圈

日志样本中：

- `tingan666`：进入后持续 `buffering=true`。
- `xzx11234`：进入后持续 `buffering=true`。
- `hrj20011221`：同版本可以正常播放。

三个房间详情均在约 1.1～1.3 秒成功返回，播放源均为有效的 H.264 HTTP-FLV，主机为 `tx-origin.pull.yximgs.com`。失败发生在 URL 解析之后。

iOS 可以正常播放同一批房间，进一步指向 HarmonyOS AVPlayer 路径。

### 2.2 抖音首次黑屏

日志中房间详情约 438ms 成功，之后播放器仍处于缓冲状态，没有 Dart 媒体错误和有效播放进度。手动刷新会重新加载详情、递增播放器 revision 并重建 AVPlayer，第二次可以成功。

### 2.3 快手格式选择不是根因

快手 core 已明确优先 H.264。快手正常只有主要 FLV 线路时，让 FLV 排在 HLS 前符合当前产品选择。本轮不改为 HLS 优先。

## 3. 已核实的高风险实现

### 3.1 媒体源可能重复设置

`simple_live_app/third_party/video_player_ohos/ohos/src/main/ets/components/videoplayer/VideoPlayer.ets` 当前可能在两个位置设置网络媒体源：

1. `createAVPlayer()` 创建完成后主动设置。
2. AVPlayer 进入 `IDLE` 的状态回调再次设置。

两个异步路径竞争时可能触发 AVPlayer 状态错误，例如 `5400102 AVPLAYER_STATE_ERROR`。

### 3.2 原生错误被静默吞掉

部分 AVPlayer 错误被无条件忽略，Flutter 侧只看到持续缓冲，没有可恢复错误。这会导致：

- 首次进房永久黑屏/转圈。
- Flutter watchdog 无法区分网络慢、地址失效和原生状态机失败。
- 播放恢复误用“重新请求房间详情”代替“重建本地播放器”。

### 3.3 所有 URL 统一使用 `setMediaSource`

历史改动把无请求头 URL 也从直接 `avPlayer.url` 切换到 `setMediaSource(...)`，并设置 `preferredBufferDuration: 1`。旧注释曾指出 `setMediaSource` 可能导致直播失败，因此该变更需要拆分验证。

### 3.4 现有测试不是原生播放测试

当前测试主要检查源文件是否包含 1 秒策略，不能证明 AVPlayer 状态转换、HTTP-FLV 首帧和 Texture 输出真实可用。

## 4. 目标与非目标

### 4.1 目标

- 每个播放器 generation 只设置一次媒体源。
- 无请求头 HTTP-FLV 使用更稳定的直接 URL 路径。
- 需要请求头的媒体继续支持 `setMediaSource`。
- 原生错误完整传回 Flutter，不再静默缓冲。
- 同一 FLV 的本地重开不请求平台房间详情。
- 快手和抖音首次进入都能稳定出首帧。
- 日志不包含 URL、Cookie、Token 等敏感信息。

### 4.2 非目标

- 不改变快手 H.264/FLV 优先级。
- 不用自动切 HLS 规避 AVPlayer 缺陷。
- 不在本方案实现双账号和关注匿名刷新。
- 不在稳定性修复前开放更激进低延迟策略。
- 不包含多开同屏。

## 5. 原生媒体源状态机

### 5.1 单一入口

所有媒体源设置收口到 `assignMediaSourceIfNeeded(generation)`。需要记录：

```text
playerGeneration
sourceAssignmentState = idle | assigning | assigned | failed
sourceKind = directUrl | mediaSourceWithHeaders
```

规则：

- 同 generation 的 `assigning/assigned` 直接返回。
- 新 URL、请求头或 revision 创建新 generation。
- 旧 generation 的异步回调不得改变新播放器状态。
- `IDLE` 回调只负责触发单一入口，不能自行重复设置媒体源。
- 创建流程与状态回调同时到达时，只允许一个路径取得赋值权。

### 5.2 路径选择

| 条件 | 路径 |
| --- | --- |
| HTTP(S) 且请求头为空 | `avPlayer.url` 直接赋值 |
| 存在必要请求头 | `setMediaSource` |
| 本地/其他协议 | 保持平台已验证路径 |

请求头只包含默认空 Map 时应视为“无请求头”，不能因为 Flutter 传了空对象就进入 `setMediaSource`。

### 5.3 缓冲策略

先以不设置 `preferredBufferDuration: 1` 的稳定基线验证两类问题。确认起播稳定后再独立 A/B：

1. 默认 AVPlayer 策略。
2. 仅对已验证协议设置保守缓冲时长。
3. 失败立即回滚到默认策略。

低延迟档位属于 [03-HarmonyOS自适应播放与诊断能力补齐](03-HarmonyOS自适应播放与诊断能力补齐.md)，不能和本轮稳定性修复绑定上线。

## 6. 错误传播与状态日志

### 6.1 Flutter 错误模型

原生错误至少传递：

```text
nativeErrorCode
nativeState
sourceAssignmentState
sourceKind
prepared
firstFrameRendered
```

禁止传递完整 URL、查询参数、Cookie、Referer、Token、DID。

### 6.2 关键状态

记录以下离散事件：

- player created
- source assigning / assigned / failed
- initialized / prepared
- first frame
- playing / buffering
- native error
- disposed

Flutter 只有在收到 `firstFrame` 或可靠的 `playing && !buffering` 后，才能判定起播成功。

### 6.3 错误处理

- 状态机错误：重建本地播放器一次，使用当前地址。
- 媒体 HTTP 403/404/410：允许业务层刷新一次地址。
- 解码/格式错误：显示明确错误，可允许用户手动换线路。
- 超时无原生错误：本地重建一次；仍失败后停止自动恢复。

## 7. Flutter 播放恢复

### 7.1 恢复顺序

```text
首次起播超时/持续缓冲
  -> 使用当前 URL 重建 AVPlayer
  -> 仍失败且有明确地址失效证据
  -> 刷新一次房间详情/播放地址
  -> 仍失败则停止自动重试
```

快手只有一个主要 FLV 地址时，持续缓冲不代表地址过期。不能每 30 秒获取新详情。

### 7.2 请求边界

- 本地状态错误、首帧超时和普通缓冲不触发快手详情请求。
- 只有媒体层明确返回地址失效，或地址已使用较长时间，才允许刷新。
- 地址刷新 single-flight，至少 5 分钟冷却。
- 活跃播放会话期间停止秒级房间详情轮询。
- 所有平台请求仍受 [01-快手全平台请求与双账号治理](01-快手全平台请求与双账号治理.md) 的物理请求调度器约束。

### 7.3 抖音首次黑屏

抖音与快手共享同一 AVPlayer 初始化修复。抖音不应通过“首次失败后自动刷新详情”作为长期方案；初始化 race 修复后，保留一次同 URL 本地重建作为安全兜底。

## 8. 推荐改动范围

- `simple_live_app/third_party/video_player_ohos/ohos/src/main/ets/components/videoplayer/VideoPlayer.ets`
- `simple_live_app/third_party/video_player_ohos/lib/video_player_ohos.dart` 或对应通道层
- `simple_live_app/lib/modules/live_room/player/ohos_video_player.dart`
- `simple_live_app/lib/modules/live_room/player/player_controller.dart`
- `simple_live_app/lib/modules/live_room/live_room_controller.dart`

原生插件负责状态机和错误事实；Flutter widget 负责 generation 和生命周期；房间控制器负责有限恢复及平台请求边界。

## 9. 实施步骤

### P0：补观测

1. 记录脱敏状态转换。
2. 将此前吞掉的 AVPlayer 错误上报 Flutter。
3. 暂不改变恢复策略，用日志确认两个失败房间的真实错误。

### P1：消除竞态

1. 增加 generation 和单次赋值保护。
2. 合并创建流程与 IDLE 回调的媒体源入口。
3. 增加旧回调拒绝逻辑。

### P2：恢复直接 URL 路径

1. 空请求头 HTTP-FLV 改用 `avPlayer.url`。
2. 有请求头媒体保留 `setMediaSource`。
3. 默认关闭 1 秒强制缓冲策略并 A/B 验证。

### P3：收敛恢复

1. 首次失败只重建本地播放器。
2. 地址失效才刷新详情。
3. 加入单次重试、冷却和停止条件。

## 10. 测试

### 10.1 纯逻辑/静态测试

- 同 generation 只能执行一次 source assignment。
- 新 generation 拒绝旧回调。
- 空 headers 选择 direct URL。
- 非空 headers 选择 media source。
- 原生错误结构脱敏。
- 普通缓冲不触发详情刷新。
- 403/404/410 只允许一次地址刷新。

### 10.2 ArkTS/插件测试

- `IDLE` 与 create 回调并发时只设置一次媒体源。
- dispose 后迟到回调无效。
- source assignment 失败能到达 Dart。
- Texture/Surface 在重建、全屏和前后台切换后仍可输出画面。

### 10.3 真机矩阵

- 快手：两个失败房间和一个正常对照房间。
- 抖音：首次进入、返回重进、手动刷新。
- 协议：无 headers FLV、有 headers 流、HLS 对照。
- 生命周期：前后台、锁屏恢复、画中画、横竖屏、切清晰度。
- 网络：Wi-Fi、蜂窝、弱网和网络切换。

## 11. 验收标准

- 快手三个样本房间首次进入均能出首帧。
- 抖音首次进入不再依赖手动刷新。
- 日志中同 generation 没有重复设置媒体源。
- AVPlayer 错误在 Flutter 可见，不再表现为永久静默缓冲。
- 连续缓冲 10 分钟不产生周期性平台详情请求。
- 正常房间、后台播放、截图和画中画无回归。

## 12. 风险与回滚

- 直接 `url` 与 `setMediaSource` 在不同系统版本表现可能不同，应保留受控开关。
- 去掉 1 秒缓冲策略可能增加延迟，但稳定性优先；低延迟后续独立恢复。
- 错误上报可能触发现有 Flutter 自动恢复，需要同步加入单次重试边界。
- 若某类 header 流回归，只回滚该 source kind，不回滚 generation 防竞态。
