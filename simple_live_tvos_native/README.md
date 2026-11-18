# Simple Live tvOS 原生客户端

SwiftUI 应用通过原生网络适配器连接各平台。HTTPS HLS 使用 AVPlayer，HTTP HLS、FLV 和 RTMP 使用 KSPlayer/FFmpeg。最低支持 tvOS 17。独立的 Flutter 客户端位于 `simple_live_tvos_app/`。

## 构建和测试

需要带 tvOS SDK 的 Xcode 与 XcodeGen。Xcode 26 如果提示缺少 Metal Toolchain，先执行 `xcodebuild -downloadComponent MetalToolchain`。如果没有 Apple TV 模拟器，先在 Xcode 的 Components 安装 tvOS 运行时。

在仓库根目录执行：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

tool/build_tvos_native.sh

tool/build_tvos_native.sh \
  -destination 'platform=tvOS Simulator,name=Apple TV' test

tool/build_tvos_native.sh \
  -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build
```

测试目标的设备名称以 `xcrun simctl list devices available` 列出的名称为准，也可使用 `id=<UDID>`。设置 `XCODEGEN` 可指定本地工具路径，设置 `TVOS_DERIVED_DATA` 可更改产物目录。

脚本按固定提交浅克隆 [KSPlayer 2.3.4](https://github.com/kingslay/KSPlayer/tree/2.3.4) 和 [FFmpegKit 6.1.3](https://github.com/kingslay/FFmpegKit/tree/6.1.3)，并修正 FFmpegKit 内 `libshaderc_combined` 的 tvOS 框架标识。两个版本的源码许可均见各自仓库的 GPL-3.0 文件。抖音签名脚本移植自本仓库的 `simple_live_core/lib/src/scripts/douyin_sign.dart`。播放器依赖和生成的 Xcode 工程均为本地构建文件。

`ProviderSmokeTests` 需要访问真实站点和媒体样例，常规测试跳过。使用 `build-for-testing` 生成 `.xctestrun` 后，在 `SimpleLiveTVOSTests.EnvironmentVariables` 下设置 `SIMPLELIVE_LIVE_SMOKE=1`，然后用 `xcodebuild -xctestrun <路径> -destination <模拟器> test-without-building` 运行。小红书实播测试还需要通过 `SIMPLELIVE_XIAOHONGSHU_SHARE_URL` 提供正在直播的公开分享链接。

## 当前范围

- B 站与斗鱼提供电视端扫码。二维码生成和等待确认已经过测试，完整登录后重启恢复需要在对应平台 App 扫码验收。
- 虎牙、抖音、快手提供游客入口。小红书已在 Apple TV 模拟器上通过公开分享链接进房和播放的测试。推荐、分类和弹幕接口仍需适配。
- Mac 登录辅助程序和其余四个平台的扫码仍待实现。各平台接口、直播流和弹幕需要分别验证。
- 模拟器用于应用和联网冒烟测试。未签名真机产物用于构建验证，Apple TV 安装和长期播放需要单独验收。
