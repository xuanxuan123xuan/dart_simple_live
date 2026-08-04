<p align="center">
    <img width="128" src="/assets/logo.png" alt="Simple Live logo">
</p>
<h2 align="center">Simple Live — 稳定版</h2>

<p align="center">
简简单单的看直播 · <code>v1.13.0</code> · 分支 <code>stable</code>
</p>

![浅色模式](/assets/screenshot_light.jpg)

![深色模式](/assets/screenshot_dark.jpg)

> **Release 资产**：本仓库提供阶段性 `Release` 安装包与压缩包，见 [GitHub Releases](https://github.com/xuanxuan123xuan/dart_simple_live/releases) 页面。

## 📦 IPA 源（AltStore / LiveContainer）

本分支为**稳定版**，推荐添加稳定版源：

| 版本 | 源 URL |
|---|---|
| **稳定版（推荐）** | `https://raw.githubusercontent.com/xuanxuan123xuan/dart_simple_live/stable/ipa-source/apps-stable.json` |
| dev 测试版 | `https://raw.githubusercontent.com/xuanxuan123xuan/dart_simple_live/dev/ipa-source/apps.json` |

用法：**LiveContainer（或 AltStore/SideStore）→ 源 → 添加源**，粘贴 URL 即可。构建发布后源内点更新拿到最新 IPA。

> 稳定版源对应 `ios-stable` 标签；dev 测试版源对应 `ios-dev` 标签。

---

## 这个分支是什么

本仓库 fork 自 [June6699/dart_simple_live](https://github.com/June6699/dart_simple_live)。`stable` 是**长期维护的稳定分支**，重点维护三部分：

1. **鸿蒙 NEXT 适配**：完整的 OHOS 端口，包含 ArkTS 原生插件层（播放器、截图、扫码、Cookie、文件管理、PIP、网络信息）、服务卡片（关注主播开播状态）、后台开播检查（WorkScheduler + 用户开关）、以及 QuickJS FFI 签名桥接（抖音）。
2. **多开同屏**：在同一窗口内播放 2～4 个直播间，支持均分/主次布局、聚焦、聊天区、独立暂停与音频控制，以及自动画质调节。
3. **移动播放稳定性**：统一管理常亮锁和全屏系统栏，改善 iOS 状态栏隐藏、前后台恢复、播放器刷新及资源释放。

> 开发中的新功能在 [dev 分支](https://github.com/xuanxuan123xuan/dart_simple_live/tree/dev)（Flutter 3.41 升级线），验证稳定后合入本分支。

鸿蒙端口的代价是 **Flutter 版本钉死在 3.22 线**（`pubspec.yaml` 有 7 处依赖与 3.22 对齐），与 dev 分支的 Flutter 3.41 互斥，无法直接合并。

---

## 功能亮点

### 多开同屏

可以从关注页批量选择直播间，也可以在单直播间全屏状态下通过“添加直播间”直接转入多开。

- **2～4 路同屏**：iOS / Android 移动端最多 4 路；当前要求屏幕短边 ≥ 600 逻辑像素，因此主要面向 iPad、安卓平板及大屏/折叠设备。
- **灵活布局**：支持均分与主次布局反复切换，可直接“设为主画面”，也可双击聚焦单路；退出聚焦后恢复原布局。
- **完整单路衔接**：聚焦后可“转到单直播间”，释放其他多开播放器，并继续使用截图、小窗、定时关闭等完整功能。
- **独立播放控制**：每路可暂停、继续、刷新、静音和调节音量，同时提供全部暂停、全部静音及串行一键刷新。
- **声音策略**：设置中可选择仅允许一路声音或多路混音；单路声音模式会自动避免多个直播间同时出声。
- **聊天与弹幕**：每格独立接收弹幕；双开、三开可显示聊天区并拖动边界调整宽度。
- **自动画质**：综合各路带宽、缓冲次数、进程内存、分辨率、帧率和设备 CPU 性能逐级调节，稳定后按用户目标逐步恢复。
- **资源保护**：高内存占用时临时降低非主画面负载，内存回落后恢复；所有播放器刷新操作通过共享队列串行执行。
- **全屏体验**：多开期间保持屏幕常亮，iOS / Android 的状态栏和前后台恢复由统一协调器管理。
- **画面等比缩放不裁切**，比例不符时留黑边；弹幕行数按格子高度自适应，格子过矮时自动隐藏。
- **桌面端**（Windows / macOS）仍可优先使用多个独立系统窗口，失败或其他平台则退回单窗口同屏。
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
| Android | ✅ | 分架构 APK |
| iOS | ✅ | 未签名 IPA 或 AltStore 侧载 |
| Windows | ✅ | zip |
| macOS | ✅ | dmg / zip |
| Linux | ✅ | zip / deb |
| Android TV | ✅ | 拆分 APK（按 ABI） |
| TV-windows | ✅ | TV 的 UI 在 Windows 上运行，支持多开 |
| HarmonyOS NEXT | ✅ | 本分支 `stable`，见下方构建 |

---

## 环境

| 构建目标 | Flutter 版本 | 说明 |
|---|---|---|
| **本分支所有目标** | **3.22.x** | `stable`，pubspec 钉死 |
| 鸿蒙 HAP | 3.22 线 OHOS fork | `tool/build_ohos_hap.ps1` 自带 |

本分支的 `pubspec.yaml` 有 7 处依赖按 Flutter 3.22 钉死（`intl`、`archive`、`lottie`、`package_info_plus`、`window_manager`、`shelf`、`dynamic_color`），换用更新的 Flutter 会在 `flutter_localizations` 的 `intl` 传递依赖上解析失败，需连同这些依赖一起升级。

注意：`simple_live_app/.fvmrc` 里写的 `3.38.3` 与本目录 pubspec 并不匹配，所有构建流程均不读取它。

### 版本号维护

应用版本以 `simple_live_app/pubspec.yaml` 的 `version` 为唯一来源。当前版本为 `1.13.0+11300`，构建号规则为：

```text
major × 10000 + minor × 100 + patch
```

修改版本后在 `simple_live_app` 目录执行：

```bash
# 直接设置版本并同步所有派生文件；1.13 会自动规范为 1.13.0
dart run tool/app_version.dart set 1.13
```

---

## 免责声明

本项目仅用于学习交流，遵守各平台协议，**不提供任何形式的账号、付费、写操作或官方活动参与功能**，仅做直播观看与弹幕（只收不发）。
