# HarmonyOS 系统体验与播放器设置补齐

> 状态：待实施
> 适用平台：HarmonyOS
> 范围：屏幕常亮、自动小窗设置、能力化播放器设置与已有功能回归
> 不包含：多开同屏

## 1. 结论

HarmonyOS 的后台播放、手动小窗、截图、分享、通知、同步和网页登录已经有专用实现，不应重复开发。当前真正需要补的是播放时屏幕常亮、已经存在但 UI 隐藏的自动小窗选项，以及让设置页只展示 AVPlayer 实际支持的能力。

## 2. 当前能力矩阵

| 功能 | 当前状态 | 本方案动作 |
| --- | --- | --- |
| 后台继续播放 | 已有 OHOS 原生服务 | 回归验证 |
| 手动进入小窗 | 已有 `OhosPipService` | 回归验证 |
| 退后台自动小窗 | 原生与 Dart 逻辑已有，设置项仅 Android 可见 | 补 UI 与能力检测 |
| 小窗隐藏弹幕 | 逻辑已有，设置项仅 Android 可见 | 补 UI 与回归 |
| 截图保存图库 | 已有原生截图/保存路径 | 回归验证失败提示 |
| 文本/文件分享 | 已有 `OhosDocumentService` | 不改 |
| 配置导入导出 | 已有 OHOS 文档插件 | 不改 |
| WebDAV/远程/局域网同步 | 已有 | 不改 |
| 二维码扫描 | 已有 OHOS 扫码通道 | 不改 |
| 哔哩哔哩/抖音/快手网页登录 | 已有 OHOS WebView/Cookie 通道 | 只补快手状态展示 |
| 开播通知与点击进房 | 已有 OHOS 通知桥 | 回归验证 |
| 关注服务卡片 | OHOS 独有 | 不改 |
| 播放时屏幕常亮 | 未接入 | 新增原生能力 |
| mpv 高级设置 | AVPlayer 不支持 | 不照搬，改为能力化设置 |

## 3. 目标与非目标

### 3.1 目标

- 播放页前台可见时保持屏幕常亮。
- 离开播放、暂停到策略要求关闭、进入后台或销毁后可靠释放常亮。
- HarmonyOS 设置页可以配置自动小窗和小窗隐藏弹幕。
- 设备不支持 PiP 时隐藏或禁用相关设置，并给出准确原因。
- 设置页不出现无效的 mpv/硬解字段。
- 已有 OHOS 原生能力完成统一回归矩阵。

### 3.2 非目标

- 不实现多开同屏。
- 不为 AVPlayer 模拟 `mpv.conf`、`--vo` 或音频滤镜。
- 不改变系统全局休眠时间。
- 不保证系统省电策略下无限后台存活。
- 不在本方案重写通知、同步和文件系统插件。

## 4. 播放时屏幕常亮

### 4.1 当前问题

`player_controller.dart` 当前在 OHOS 跳过 `PlaybackDisplayCoordinator` 的 keep-awake lease，仓库也没有对应原生窗口常亮桥。长时间观看时设备可能按系统超时熄屏。

### 4.2 原生桥

新增窄接口，例如：

```text
simple_live/ohos_display
  setKeepScreenOn(enabled: bool)
  getKeepScreenOn() -> bool   // 可选，用于诊断
```

ArkTS 侧使用当前 HarmonyOS SDK/API 12 可用的窗口常亮能力。具体 API 名称必须在本机构建 SDK 中核实，不能仅凭文档版本照抄。

### 4.3 Lease 语义

Flutter 不直接在多个页面反复调用原生开关，而是复用 `PlaybackDisplayCoordinator` 的 lease 思路：

- 首个活跃播放 lease 开启常亮。
- 最后一个 lease 释放时关闭常亮。
- 同一房间重复 set 不产生重复原生调用。
- 应用进入后台且没有 PiP/允许后台视频场景时释放。
- 回前台恢复播放后重新申请。
- 异常退出、播放器 dispose 和路由替换都必须 finally 释放。

虽然 OHOS 不支持多开，本地仍使用 lease 可以避免全屏、PiP、页面生命周期之间互相覆盖。

### 4.4 策略

| 场景 | 常亮 |
| --- | --- |
| 前台正在播放 | 开 |
| 前台缓冲/短暂重连 | 保持 |
| 用户暂停 | 建议关闭 |
| PiP 活跃 | 由系统 PiP 策略决定，默认不强制主窗口常亮 |
| 后台仅音频 | 关 |
| 房间关闭/应用销毁 | 关 |

## 5. 自动小窗设置

### 5.1 当前问题

`prepareAutoPipOnLeave()` 和 `OhosPipService.prepareAuto()` 已支持 HarmonyOS，但设置页中“进入小窗隐藏弹幕”和“退出时自动小窗”使用 `visible: Platform.isAndroid`，导致 OHOS 用户无法正常开启。

### 5.2 设置展示

移动端设置条件改为能力驱动：

```text
pipAvailable
pipAutoOnLeaveSupported
pipCanHideDanmaku
```

而不是直接判断 `Platform.isAndroid`。HarmonyOS 原生插件初始化后返回能力；设备不支持时可以隐藏设置或禁用并显示“设备不支持小窗”。

### 5.3 行为

- 手动小窗继续保留播放器按钮。
- 开启自动小窗后，按 Home/系统手势退后台进入 PiP；应用内返回仍回主页。
- 进入 PiP 时按设置隐藏弹幕和控制栏。
- 退出 PiP 后恢复进入前弹幕状态。
- 切房、关闭播放器和禁用设置时取消 pending auto-PiP。
- 自动小窗失败不能阻止应用正常退后台。

## 6. 能力化播放器设置

### 6.1 不应在 OHOS 展示

- mpv 性能档位。
- 高级 mpv options。
- 导入 `mpv.conf`。
- 视频输出驱动 `--vo`。
- AVPlayer 没有对应 API 的硬件解码开关。

隐藏这些项不是功能缺陷，而是正确的平台边界。

### 6.2 应展示的等价设置

在 [03-HarmonyOS自适应播放与诊断能力补齐](03-HarmonyOS自适应播放与诊断能力补齐.md) 落地后，OHOS 可以展示：

- 播放缓冲策略：稳定/自动/低延迟实验。
- 自动降清晰度。
- 网络波动提示。
- 播放诊断信息。
- 后台继续播放。
- 自动小窗与小窗弹幕行为。
- 画面尺寸、HTTPS、音量/亮度手势等现有通用设置。

设置项必须由 capability model 决定是否出现，避免 UI 打开了底层尚未实现的功能。

## 7. 快手账号信息的 OHOS 展示

快手账号、双 Cookie 和到期时间完整设计位于 [01-快手全平台请求与双账号治理](01-快手全平台请求与双账号治理.md)。本方案只规定 OHOS 设置页展示行为：

- `fetchCookieSync()` 未提供到期属性时显示“到期时间未知”。
- 显示登录时间和上次验证成功时间。
- 请求频繁显示暂停截止时间，不能显示成 Cookie 到期。
- Cookie 明确失效显示“需要重新登录”，不能等次日自动恢复。

## 8. 已有能力回归

本轮触及生命周期和设置页，必须回归已经可用的 OHOS 功能：

- 后台播放开启/关闭及回前台恢复。
- 手动 PiP、自动 PiP、PiP 退出。
- 全屏与横竖屏切换。
- 截图成功、用户取消保存、原生截图失败。
- 分享直播间链接和配置包。
- WebDAV、远程同步、局域网同步与扫码。
- 三个平台网页登录和 Cookie 保存。
- 开播通知点击后冷/热启动进入目标房间。
- 关注服务卡片快照和后台检查。

关注后台检查当前仅支持虎牙、斗鱼、哔哩哔哩；该平台范围不是本方案扩展目标。

## 9. 推荐改动范围

- `simple_live_app/lib/services/playback_display_coordinator.dart`
- 新增 `simple_live_app/lib/services/ohos_display_service.dart`
- 新增/扩展 HarmonyOS display 原生插件
- `simple_live_app/lib/modules/live_room/player/player_controller.dart`
- `simple_live_app/lib/services/ohos_pip_service.dart`
- `simple_live_app/lib/modules/settings/play_settings_page.dart`
- `simple_live_app/lib/app/controller/app_settings_controller.dart`
- `simple_live_app/lib/modules/mine/account/account_controller.dart`

## 10. 实施顺序

1. 增加 OHOS display 插件和幂等常亮接口。
2. 将 OHOS 接入 PlaybackDisplayCoordinator lease。
3. 覆盖前后台、PiP、暂停和 dispose 生命周期。
4. 把 PiP 设置条件从平台判断改为能力判断。
5. 显示 OHOS 自动小窗和隐藏弹幕设置。
6. [03](03-HarmonyOS自适应播放与诊断能力补齐.md) 完成后接入 AVPlayer 等价设置。
7. 执行已有 OHOS 功能回归矩阵。

## 11. 测试与验收

### 11.1 单元/通道测试

- keep-awake 首次 lease 开、最后 lease 关。
- 重复 set 幂等。
- dispose/异常路径释放。
- PiP capability 决定设置项可见性。
- auto-PiP 开关正确持久化。
- PiP 进入/退出恢复弹幕状态。
- 到期未知、Cookie 失效和请求频繁文案互不混淆。

### 11.2 真机验收

- 连续前台播放超过系统熄屏时间，屏幕不熄灭。
- 暂停/退出房间后系统可正常熄屏。
- 退后台自动进入 PiP，返回后画面和弹幕状态正确。
- 关闭自动 PiP 后退后台不进入小窗。
- 后台播放、通知、截图、分享、同步和网页登录无回归。

## 12. 风险与回滚

- 常亮未释放会增加耗电，必须有 finally 和应用生命周期兜底。
- 系统/设备不支持自动 PiP 时应安全退化为普通后台行为。
- capability 探测失败默认关闭功能，不能假定支持。
- UI 接线可以独立回滚，不应回滚已经稳定的 PiP 原生实现。
