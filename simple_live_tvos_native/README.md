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

## TV-16 账号导入接口

同步代码在主线程调用 `NativeCoreClient`。单笔账号导入使用 `saveAccount(_:for:)`，远程、局域网或 WebDAV 的批量导入可将 `core.prepareSyncAccounts` 直接传给 `SyncImporter`。

```swift
@MainActor
func saveAccount(_ credential: AccountCredential, for slot: AccountSlot) async throws

@MainActor
func prepareSyncAccounts(_ accounts: [SyncAccount]) async throws -> (@MainActor () throws -> Void)
```

`SyncAccount(slot:cookie:kww:expiresAt:)` 的槽位取值为 `bilibili`、`douyu`、`douyin`、`kuaishou`（主账号）、`kuaishou.secondary`（备用账号）和 `xiaohongshu`。`kww` 和 `expiresAt` 供快手使用。同步层负责解析 Dart 的传输包和筛选所选账号。准备阶段验证全部传入的凭据，返回的闭包将它们作为一个 Keychain 更新提交。省略的槽位保留原值，空 Cookie 会报错。账号在准备后被用户修改或退出时，闭包会报告冲突。

在 Apple TV 模拟器运行以下命令。测试使用专用 Keychain 命名空间和模拟凭据，覆盖旧值迁移、准备与提交、失败保留、主备切换及重启恢复。

```bash
tool/build_tvos_native.sh -destination 'id=<Apple TV 模拟器 UDID>' \
  CODE_SIGN_IDENTITY=- -only-testing:SimpleLiveTVOSTests/AccountSessionTests \
  -only-testing:SimpleLiveTVOSTests/ProviderAccountTests \
  -only-testing:SimpleLiveTVOSTests/AccountImportTests test
```

账号设置页的导航目标为 `AccountSettingsView()`，沿用应用的 `NativeCoreClient` 环境对象。可用遥控器进入抖音账号，录入 `ttwid=tv16-fixture`，确认显示「已配置」。终止应用后重新打开，应恢复该状态。清除 Cookie 并确认退出后，再次打开应显示「未配置」。B 站和斗鱼的联机二维码测试可按上文启用 `SIMPLELIVE_LIVE_SMOKE=1`，并只运行 `ProviderSmokeTests` 的 `testBilibiliQRChallenge` 和 `testDouyuQRChallenge`。

## 当前范围

- B 站与斗鱼提供电视端扫码。二维码生成和等待确认已经过测试，完整登录后重启恢复需要在对应平台 App 扫码验收。
- 虎牙、抖音、快手支持游客观看。斗鱼、抖音、快手、小红书可配置 Cookie，快手有主账号和备用账号。小红书可通过公开分享链接进房，也可连接 Dart 手机端浏览热门和类目。
- Mac 登录辅助程序和其余四个平台的扫码仍待实现。各平台接口、直播流和弹幕需要分别验证。
- 模拟器用于应用和联网冒烟测试。未签名真机产物用于构建验证，Apple TV 安装和长期播放需要单独验收。

小红书列表需要两台设备在同一局域网。先在 iPhone 或安卓手机的 Simple Live 打开「局域网数据同步」→「小红书直播发现」，再到 Apple TV 的「热门直播」→「小红书」→「手机连接」填写地址和连接码。手机页面需保持打开以刷新和翻页。Apple TV 直接播放直播，手机只提供房间列表。
