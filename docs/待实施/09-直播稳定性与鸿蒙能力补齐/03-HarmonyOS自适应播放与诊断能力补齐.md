# HarmonyOS 自适应播放与诊断能力补齐

> 状态：部分实施
> 适用平台：HarmonyOS
> 前置依赖：[02-HarmonyOS直播起播与恢复稳定性](02-HarmonyOS直播起播与恢复稳定性.md)
> 不包含：多开同屏、照搬 mpv 参数

## 1. 结论

HarmonyOS 使用 AVPlayer/video_player，不能直接复用 media_kit/mpv 的缓存属性、音频欠载日志和动态追帧能力。应先建立稳定、统一的 OHOS 播放状态适配层，再依次补自动降清晰度、网络诊断和支持度明确的健康遥测。低延迟必须在起播稳定后单独开放，不能继续用全流强制 1 秒缓冲换取表面一致。

## 2. 当前差距

### 2.1 自动降清晰度未启用

`simple_live_app/lib/modules/live_room/live_room_controller.dart` 的 `_setupAutoQualityAdjust()` 在 OHOS 直接返回。非 OHOS 会监听 buffering 边沿并在窗口内多次缓冲后降一档画质。

### 2.2 自动网络诊断链路未启用

`PlayerController.onInit()` 在 OHOS 完成少量初始化后提前返回，不调用非 OHOS 的 `initStream()`，因此缓冲边沿统计、自动诊断提示和部分错误订阅没有等价接入。

### 2.3 低延迟追帧不可用

mpv 路径可以读取缓存并动态调整播放速度。OHOS 当前没有接入等价的缓存深度、吞吐和安全追帧控制，`MpvLiveLatencyChaseService` 在 OHOS 明确关闭。

### 2.4 健康遥测不完整

OHOS 当前可以取得 initialized、playing、buffering、position 和部分 size/error 状态，但没有与 mpv 等价的：

- demuxer 缓存时长。
- 音频欠载事件。
- 可靠吞吐采样。
- 结构化自动重连成功回调。
- 动态播放速度与缓存趋势。

不支持的字段必须标记 `unsupported`，不能用 0 伪装为健康。

### 2.5 高级设置没有等价实现

硬件解码开关、mpv 性能档位、输出驱动、`mpv.conf` 和高级 mpv options 在 OHOS 隐藏是合理的，因为 AVPlayer 不识别这些字段。真正缺失的是 AVPlayer 能支持的等价产品设置和能力说明。

## 3. 目标与非目标

### 3.1 目标

- OHOS 产生统一、可测试的播放状态事件。
- 自动降清晰度在 OHOS 可用，且不会引发高频详情请求。
- 网络诊断只使用真实当前流端点和可验证指标。
- 健康面板明确区分支持、暂不可用和数据不足。
- 提供 AVPlayer 可实现的稳定/低延迟策略档位。
- 所有自动控制都有 warmup、single-flight、cooldown 和停止条件。

### 3.2 非目标

- 不模拟不存在的 mpv 属性。
- 不把 TCP 连接失败称为“丢包率”。
- 不在没有缓存深度时启用动态倍速追帧。
- 不让健康评分直接重启播放器。
- 不复制 `mpv.conf`、`--vo`、音频滤镜等设置到 OHOS。
- 不包含多开同屏。

## 4. OHOS 播放状态适配层

### 4.1 统一事件模型

新增 `OhosPlaybackSignalAdapter`，将 `VideoPlayerValue` 和原生事件映射为：

```text
initialized
firstFrame
playing
bufferingStarted
bufferingEnded
positionAdvanced
nativeError
mediaHttpError
sourceAssigned
sourceReopened
disposed
```

每个事件携带：

```text
roomGeneration
playerGeneration
occurredAt
sourceFingerprint
supportedMetrics
```

`sourceFingerprint` 只能是脱敏哈希，不能包含完整 URL 或查询参数。

### 4.2 生命周期边界

- 切房、切线、切清晰度和播放器重建都递增 generation。
- 旧 generation 事件不得写入新房间。
- 前后台和 PiP 期间明确标记排除窗口，避免把系统暂停当网络波动。
- 首帧前 warmup 期间的正常 buffering 不计入自动降画质。

## 5. 自动降清晰度

### 5.1 触发策略

复用现有 `LiveRoomAutoQualityBufferTracker` 的纯策略，但接入 OHOS buffering 边沿：

- 起播 warmup 默认 8 秒。
- 30 秒窗口内出现多次独立 buffering 才降档。
- 每次只降一个画质等级。
- 降档后至少 30 秒冷却。
- 已在最低画质、用户锁定画质或处于播放器恢复时不触发。

具体阈值应通过真机样本校准，首版保持保守。

### 5.2 请求边界

- 已有同一详情内的其他清晰度 URL 时直接切换，不刷新房间详情。
- 只有目标清晰度 URL 缺失/明确过期时才允许请求一次详情。
- 所有请求受 [01-快手全平台请求与双账号治理](01-快手全平台请求与双账号治理.md) 约束。
- 自动降档和播放器本地重建不能同时执行。

### 5.3 自动恢复画质

首版只自动降档，不自动升档。待稳定播放时长、网络类型和带宽指标可靠后，再考虑逐级恢复，避免画质来回振荡。

## 6. 自动网络诊断

### 6.1 触发

- warmup 结束后，短窗口内至少两次独立 buffering。
- 同一房间诊断 single-flight。
- 诊断冷却至少 2 分钟。
- 播放器状态错误优先显示播放器错误，不误报网络。

### 6.2 数据源

- 当前实际播放 URL 的 host 和端口。
- HarmonyOS 当前网络类型：Wi-Fi、蜂窝、以太网或其他。
- DNS 解析结果、TCP 可达性和握手耗时。
- 播放器 buffering 持续时间与 position 是否推进。

不得固定探测多个公共 DNS 后汇总成“丢包率”。更完整的网络设计继续引用 [../04-App游戏式网络质量检测接入设计.md](../04-App游戏式网络质量检测接入设计.md)。

### 6.3 提示口径

| 证据 | 提示 |
| --- | --- |
| 当前流端点不可达 | 当前线路连接失败 |
| 端点可达但播放器无首帧且有原生错误 | 播放器初始化失败 |
| 多次 buffering 且 position 间歇推进 | 网络或 CDN 供给波动 |
| 数据不足/指标不支持 | 暂无法判断，不展示百分比分数 |

## 7. 健康遥测

### 7.1 支持矩阵

| 指标 | OHOS 首版 |
| --- | --- |
| initialized/playing/buffering | 支持 |
| 首帧耗时 | 原生事件补齐后支持 |
| position 推进 | 支持 |
| 原生错误码 | 原生上报后支持 |
| 媒体 HTTP 错误 | 平台能暴露时支持 |
| 缓存深度 | unsupported |
| 吞吐量 | 无可靠来源时 unsupported |
| 音频欠载 | unsupported |
| 自动重连成功 | 需要显式结构化回调 |

详细健康模型继续使用 [../02-直播链路健康度设计.md](../02-直播链路健康度设计.md)，本方案只补 OHOS 采集适配和能力声明。

### 7.2 评分边界

- `unsupported` 不等于 0。
- 有效故障域不足时显示“数据不足”。
- 健康度只观测，不直接切线、降画质或重启播放器。
- 自动控制逻辑消费独立、明确的事件，不读取 UI 分数。

## 8. 低延迟能力

### 8.1 已实施的稳定策略

当前不向业务层新增档位或公开 API，原生播放器按设备 SDK 分流：

| 设备 API | AVPlayer 策略 |
| --- | --- |
| 12–17 | `preferredBufferDuration: 20` |
| 18+ | `preferredBufferDuration: 20`、`preferredBufferDurationForPlaying: 5`、`thresholdForAutoQuickPlay: 60` |

API 18 的系统智能追帧倍率固定为 1.2 倍，应用无法调成 1.05–1.1 倍。60 秒阈值用于让正常观看基本不触发追帧；它不是系统级关闭开关。策略设置失败时回退系统默认值，不阻断起播。

无请求头 URL 继续走 `player.url`，在 `initialized` 后应用策略再 `prepare()`；带请求头 URL 继续走 `setMediaSource` 并传入相同策略。两条路径均受 generation 防重和迟到回调保护。

### 8.2 禁止事项

- 不对所有 URL 强制 `preferredBufferDuration: 1`。
- 不在缺少缓存深度时通过频繁读 position 猜测缓存。
- 不在直播流上启用未经验证的动态倍速追帧。
- 不通过 API 20 的倍速接口为直播设置 1.05–1.1 倍。
- 不把 mpv 的档位名称直接映射成 AVPlayer 参数。

通用追帧算法参考 [../01-直播缓存追帧策略设计.md](../01-直播缓存追帧策略设计.md)，OHOS 只有在平台提供足够遥测后才接入相应阶段。

## 9. OHOS 播放器设置

不显示 mpv 专属设置。建议按能力动态展示：

- 播放缓冲策略：稳定/自动/低延迟实验档。
- 自动降清晰度开关。
- 网络波动提示开关。
- 播放诊断信息入口。

硬件解码由 AVPlayer 管理时，不提供无效开关；只有确认 HarmonyOS SDK 存在稳定且可控的解码策略 API 后再增加。

## 10. 推荐改动范围

- `simple_live_app/lib/modules/live_room/player/player_controller.dart`
- `simple_live_app/lib/modules/live_room/player/ohos_video_player.dart`
- `simple_live_app/lib/modules/live_room/live_room_controller.dart`
- `simple_live_app/lib/modules/live_room/live_room_auto_quality_buffer_tracker.dart`
- `simple_live_app/lib/services/live_link_health_collector.dart`
- `simple_live_app/lib/services/live_link_health_models.dart`
- `simple_live_app/lib/services/ohos_network_service.dart`
- `simple_live_app/lib/modules/settings/play_settings_page.dart`
- HarmonyOS video_player 原生事件通道

## 11. 实施顺序

1. 建立 OHOS 状态适配层和 generation 边界。
2. 接入首帧、原生错误和结构化本地重开事件。
3. 补自动降清晰度，首版只降不升。
4. 补真实端点网络诊断和保守提示。
5. 补健康度支持矩阵与数据不足展示。
6. 真机稳定后再开放 AVPlayer 低延迟档位。

## 12. 测试与验收

### 12.1 单元测试

- OHOS 状态事件映射和 generation 拒绝。
- warmup 内 buffering 不计数。
- 多次独立 buffering 才降档。
- 降档不刷新已有 URL 的房间详情。
- 诊断只探测当前实际 host/port。
- unsupported 指标不参与评分。
- 低延迟档位按协议和能力正确降级。

### 12.2 真机验收

- Wi-Fi/蜂窝弱网下自动降档只触发一次且不振荡。
- 切房、切线、切清晰度后旧事件不串房。
- 前后台、PiP 和系统暂停不误报网络波动。
- 诊断提示能区分原生初始化失败与端点不可达。
- 默认稳定档不引入 [02](02-HarmonyOS直播起播与恢复稳定性.md) 已修复问题。
- 连续观看 30 分钟没有额外平台详情请求。

## 13. 风险与回滚

- AVPlayer 暴露的状态粒度可能不足，缺失指标必须保持 unsupported。
- 自动降档可能被 CDN 短抖动误触发，首版需保守阈值和长冷却。
- 低延迟参数随 HarmonyOS API/系统版本变化，必须能力检测和远程/本地开关。
- 任一自动策略导致起播回归时，回滚控制策略，保留状态适配和诊断日志。
