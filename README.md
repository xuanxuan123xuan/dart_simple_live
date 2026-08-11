<p align="center">
    <img width="128" src="/assets/logo.png" alt="Simple Live logo">
</p>
<h2 align="center">Simple Live — dev 开发版</h2>

<p align="center">
简简单单的看直播 · <code>v1.13.2</code> · 分支 <code>dev</code>
</p>

![浅色模式](/assets/screenshot_light.jpg)

![深色模式](/assets/screenshot_dark.jpg)

> **Release 资产**：本仓库提供阶段性 `Release` 安装包与压缩包，见 [GitHub Releases](https://github.com/xuanxuan123xuan/dart_simple_live/releases) 页面。

## ❤️ 支持项目

Simple Live 会一直坚持**免费、开源、不向用户收费**。目前项目主要由我——一名暂时没有收入的大学生——利用课余时间维护；适配不同平台、跟进直播接口变化、测试和发布新版本，都需要持续投入时间与精力。

如果这个项目确实帮到了你，并且你在经济上有余力，欢迎通过下方二维码自愿赞助。每一份支持都会成为我继续维护和完善项目的动力。**赞助完全自愿，不赞助也不会影响任何功能或问题反馈。**

<p align="center">
  <img width="340" src="/assets/readme/sponsor-wechat.png" alt="微信赞助码">
  &nbsp;&nbsp;
  <img width="340" src="/assets/readme/sponsor-alipay.jpg" alt="支付宝赞助码">
</p>

<p align="center"><sub>微信 / 支付宝任选其一，请量力而行，感谢支持。</sub></p>

## 💬 反馈与交流

遇到播放问题、功能异常，或者有改进建议，欢迎加入 **SL 反馈催更群**。反馈时如果能附上平台、直播间链接、设备系统和复现步骤，会更方便定位问题。

- QQ 群号：`1059378368`

<p align="center">
  <img width="420" src="/assets/readme/feedback-qq-group.jpg" alt="SL 反馈催更群二维码">
</p>

---

## ⚠️ 开发版说明

本分支是 **dev 开发版**，用于验证新功能与修复，**可能存在不稳定或未完成的功能**，适合尝鲜测试，日常使用请用 [stable 稳定版](https://github.com/xuanxuan123xuan/dart_simple_live/tree/stable)。`stable` 已完成 Flutter 3.41 验证并同步升级。

## 📦 IPA 源（AltStore / LiveContainer）

本分支为 dev 测试版，推荐添加 dev 测试版源：

| 版本 | 源 URL |
|---|---|
| **dev 测试版（本分支）** | `https://raw.githubusercontent.com/xuanxuan123xuan/dart_simple_live/ipa-source/apps.json` |
| 稳定版 | `https://raw.githubusercontent.com/xuanxuan123xuan/dart_simple_live/ipa-stable/apps.json` |

用法：**LiveContainer（或 AltStore/SideStore）→ 源 → 添加源**，粘贴 URL 即可。构建发布后源内点更新拿到最新 IPA。

> dev 测试版源对应 `ios-dev` 标签；稳定版源对应 `ios-stable` 标签。

---

## 这个分支是什么

本仓库 fork 自 [June6699/dart_simple_live](https://github.com/June6699/dart_simple_live)。`dev` 是**开发分支**，用于先行验证新功能与修复，稳定后合入 [stable 分支](https://github.com/xuanxuan123xuan/dart_simple_live/tree/stable)。Flutter 3.41 升级已经过 dev 验证并同步到 stable。

**本分支与 stable 的差异**：

| 项 | stable | dev（本分支） |
|---|---|---|
| Flutter | **3.41.x** | **3.41.x** |
| Dart | **3.11.x** | **3.11.x** |
| intl | **0.20.2** | **0.20.2** |
| 版本号 | 1.13.x | **1.13.2** |
| 定位 | 稳定版 | 测试版（新功能验证） |

**dev 分支正在验证的内容**：
- **iOS 26 状态栏隐藏**：3.41 引擎的 scene-based 状态栏管理（签名版 SystemChrome 生效；LiveContainer 容器环境受限）
- **弹窗防穿透**：所有弹窗（右侧/底部/居中/菜单）加遮罩防穿透窗口，修复"打开即关闭"
- **直播延迟优化**：协议感知缓存档位、mpv 追帧、自动选线、线路记忆迁移和播放遥测已接入，正在进行长时与弱网验收
- **快手请求治理**：进程级优先队列、同房请求合并、短缓存、Cookie 会话隔离、403/429/安全验证页熔断、关注与多开限速已接入
- **网络波动诊断修复**：换房会话重置、缓冲边沿计数、起播 warmup、真实播放端点探测和 TCP 连接失败语义已接入
- **依赖解锁**：volume_controller / screen_brightness 可升级到新版（3.41 才有 Scene Lifecycle API）
- **跨平台聚合搜索**：主 App 已支持五平台并发分区展示；聚合页取第一页，单站页保留完整分页，并已完成取消、错误语义、分页来源和抖音派生主播数据治理

上述快手与网络诊断改动已通过 Flutter 3.41 定向分析、App 相关 35 项测试和 Core 相关 77 项测试；真实快手风控阈值、弱网与长时播放仍需真机验收。

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

## 更新计划（Roadmap）

> 保持"简简单单看直播"的初心，只做克制、不打扰的功能。以下为已确认的待做计划，按优先级排序：

| 功能 | 说明 | 状态 | 设计文档 |
|---|---|---|---|
| 直播延迟优化 | 协议感知缓存、mpv 追帧、自动选线、线路记忆和播放遥测 | 已实施，待长时/弱网验收 | [直播延迟优化设计](docs/直播延迟优化设计.md) |
| 快手请求与冷启动治理 | 请求协调、会话复用、限流熔断、稳定播放停轮询、弹幕重试收敛 | 已实施，待真实风控环境验收 | [冷启动设计](docs/快手直播间冷启动加载失败设计.md) / [频率限制设计](docs/快手直播请求频率限制设计.md) |
| 网络波动自动诊断修复 | 换房会话隔离、缓冲边沿计数、真实播放端点分层诊断 | 已实施，待弱网真机验收 | [网络波动修复设计](docs/直播间网络波动自动检测修复设计.md) |
| 弹幕热词统计 | 进房实时统计弹幕高频词，看节奏/吃瓜；点击热词可一键加屏蔽词 | 待做 | [弹幕热词统计设计](docs/弹幕热词统计设计.md) |
| 观看统计 | 本地静默统计观看时长/平台分布/常看主播（hive 存储，不打扰使用） | 待做 | [观看统计设计](docs/观看统计设计.md) |
| 音量记忆保持 | 切房间/切平台后音量应保持，不依赖系统音量；`resetRoom` 原地换房未重新施加音量（鸿蒙最可能暴露） | 待做（可随鸿蒙播放器改动搭车） | [音量统一设计](docs/音量统一设计.md)（A 部分） |
| 跨平台响度归一化 | 各平台基准响度不同，希望在 App 内听感一致；受播放器后端能力限制 | 暂缓（前提待实测，与延迟优化冲突） | [音量统一设计](docs/音量统一设计.md)（B 部分） |
| 跨平台聚合搜索 | 一个搜索框同时搜五大平台，结果按平台分区聚合展示；单站页提供完整分页 | 已实施（路线 A）；TV 已同步 core 竞态治理，测试受 native asset 工具链阻塞 | [跨平台聚合搜索设计](docs/跨平台聚合搜索设计.md) |
| 竖屏直播弹幕 | 竖屏直播左下角弹幕列表：从下往上、≤半屏、背景透明、长文本自动换行、上滑可回看历史、底部避让控制栏；弹幕模式跟随视频方向（横屏看竖屏流也用） | 待做（大更新，不急） | [竖屏弹幕与全屏方向设计](docs/竖屏弹幕与全屏方向设计.md)（A 部分） |
| 全屏方向跟随视频方向 | 竖屏直播全屏保持竖屏（`fullScreenForceLandscape` 默认关闭） | 待做 | [竖屏弹幕与全屏方向设计](docs/竖屏弹幕与全屏方向设计.md)（B 部分） |

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
| HarmonyOS NEXT | ✅ | 随全平台升级（runner 需换 oh-3.41.9-release） |

---

## 环境

| 构建目标 | Flutter 版本 | 说明 |
|---|---|---|
| **本分支所有目标** | **3.41.x** | dev / stable 共用工具链 |
| 鸿蒙 HAP | oh-3.41.9-release（[GitHub 镜像](https://github.com/xuanxuan123xuan/flutter_flutter_ohos)） | runner 预装 |

### 鸿蒙 HAP 构建

**前置条件**：Flutter OHOS（oh-3.41.9-release）、HarmonyOS SDK（API 12+）、JDK 17。

```bash
# 1. 克隆 Flutter OHOS 到本地
git clone --depth 1 --branch oh-3.41.9-release https://github.com/xuanxuan123xuan/flutter_flutter_ohos.git flutter_ohos

# 2. 设置环境变量（路径按实际修改）
export FLUTTER_OHOS_ROOT="$(pwd)/flutter_ohos"
export HOS_SDK_HOME="$HOME/HarmonyOS/Sdk"    # 或 DevEco 安装路径
export JAVA_HOME="/path/to/jdk-17"

# 3. 检出项目源码
git clone -b dev https://github.com/xuanxuan123xuan/dart_simple_live.git
cd dart_simple_live

# 4. 构建 HAP（签名版）
$FLUTTER_OHOS_ROOT/bin/flutter.bat pub get -C simple_live_app
$FLUTTER_OHOS_ROOT/bin/flutter.bat build hap --release \
  --dart-define=OHOS_SIGNING=true \
  --release-sks "$HOME/.ohos/release_signing.p12" \
  --release-key-password "YOUR_KEY_PASSWORD"
```

产物路径：`simple_live_app/build/hap/hap/simple_live_app-release-signed.hap`

详细签名配置参见 `build_ohos_hap.yml` workflow（`secrets.OHOS_SIGNING_DIR`）。

本分支已随升级适配：`intl` 0.20.2、`onPopInvokedWithResult`、workflow 版本校验更新；遗留的 deprecated（`RadioListTile.groupValue`、`Color.value`、`withOpacity` 等）已全部清理。

### 版本号维护

应用版本以 `simple_live_app/pubspec.yaml` 的 `version` 为唯一来源。当前版本为 `1.13.2+11302`，构建号规则为：

```text
major × 10000 + minor × 100 + patch
```

修改版本后在 `simple_live_app` 目录执行：

```bash
# 直接设置版本并同步所有派生文件
dart run tool/app_version.dart set 1.14
```

---

## 免责声明

本项目仅用于学习交流，遵守各平台协议，**不提供任何形式的账号、付费、写操作或官方活动参与功能**，仅做直播观看与弹幕（只收不发）。
