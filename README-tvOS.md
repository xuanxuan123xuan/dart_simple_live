# Simple Live tvOS 客户端

`simple_live_tvos_native/` 是使用 SwiftUI、AVPlayer 和 KSPlayer/FFmpeg 的原生
Apple TV 客户端。构建命令和当前平台验证范围见 [原生客户端说明](simple_live_tvos_native/README.md)。

`simple_live_tvos_app/` 是一个独立的 Apple TV 观看客户端，复用本仓库
`simple_live_core` 中的直播平台适配器。它定位为仅供观看的第三方客户端：
可以接收直播聊天消息，但不支持发送弹幕、聊天输入、购买或其他交互操作。

## 当前功能范围

- 提供六个直播平台入口：哔哩哔哩、虎牙、斗鱼、抖音、快手和小红书。
- 通过 tvOS AVPlayer 插件播放 HLS，支持清晰度选择、线路故障切换、
  请求头配置，以及直接播放 HLS 链接。
- 提供适合电视使用的推荐、搜索、房间号输入、分页、收藏、历史记录、
  设置和方向键焦点导航。
- 支持纯文本弹幕叠加显示，可开关弹幕并查看连接状态。图片表情、GIF、
  礼物和结构化付费消息的展示仍待实现；发送弹幕不在产品范围内。
- 通过 tvOS Keychain 方法通道恢复会话 Cookie。哔哩哔哩、斗鱼、抖音、
  快手和小红书仍支持手动输入 Cookie。首个计划支持原生网页登录的平台是小红书。

各平台的实际播放能力仍有差异：哔哩哔哩和快手在直播源返回 HLS 时可以使用；
小红书可能需要网页会话；虎牙通常返回 FLV；斗鱼和抖音可能需要 JS 签名，
或返回尚不支持的协议。能进入平台或获取房间详情，并不代表该直播流可以在 tvOS 上播放。

与平台无关的 Swift 状态和协议包位于 `simple_live_tvos_core/`。
其 SwiftPM 测试可以通过 xtool 在 Windows 和 Linux 上运行。该包不负责构建
tvOS 应用，也不能替代 macOS/Xcode 环境下的验证。

## Flutter 客户端的已知限制

1. Flutter 客户端目前仅支持 HLS。
2. `dart_quickjs_stub` 仍是测试替代实现，斗鱼和抖音依赖 JS 签名的相关逻辑
   尚不能视为已完成迁移。
3. Flutter 的 Keychain 和网页会话方法通道需要生成的 tvOS 宿主支持。在 Windows
   环境中缺少这些插件时，会回退到内存实现。
4. 当前代码尚未通过 Xcode、tvOS 模拟器、Apple TV 真机、签名 IPA 或
   生产环境直播流长时间播放的验证。目前的验收标准是 Windows 静态检查和 Dart 测试。

## 依赖与目录结构

应用依赖仓库中的以下现有路径：

```text
simple_live_tvos_app/
  lib/tvos_playback.dart       # HLS 后端接口与 AVPlayer 适配器
  lib/tvos_session.dart        # Keychain/WebView 方法通道约定
  lib/site_registry.dart       # 平台能力与 Cookie 路由
  lib/live_page.dart           # 房间播放、故障切换与文本弹幕
  test/playback_sources_test.dart
simple_live_core/
third_party/dart_quickjs_stub/
```

## AngelLive 参考

AngelLive 为 tvOS 原生层接口划分、播放恢复和后续 FLV 支持提供架构参考。
复制其代码或资源时，必须保留原仓库的 GPL-3.0 许可声明和署名，并检查与
本仓库 GPL-3.0 许可证的兼容性。

## 验证

在 Windows 上运行以下命令：

```powershell
Push-Location simple_live_tvos_app
flutter pub get
flutter analyze
flutter test
Pop-Location
dart format --output=none --set-exit-if-changed simple_live_tvos_app/lib simple_live_tvos_app/test
```

这些检查不能证明 tvOS 原生代码可以编译或能够在真机上播放。
具备 macOS/Xcode 和 Apple TV 环境后，必须单独记录相应验证结果。
