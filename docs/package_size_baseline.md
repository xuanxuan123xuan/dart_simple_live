# 包体基线与 libmpv 升级评估

记录时间：本次提交（HEAD 55cbbc21 之上）
分支：dev

## 1. 当前依赖与工具链（实测）

| 项 | 值 |
| --- | --- |
| Flutter | 3.41.9（channel user-branch） |
| Dart SDK | 3.11.5 |
| media_kit | 1.2.6（pubspec 约束 `^1.2.2`，锁文件解析为 1.2.6） |
| media_kit_video | 1.3.0（本地私有 fork：`third_party/media_kit_video`） |
| media_kit_libs_video | 1.0.7 |
| media_kit_libs_android_video | 1.3.8 |
| media_kit_libs_windows_video | 1.0.11 |
| media_kit_libs_macos_video / ios_video | 1.1.4 |
| media_kit_libs_linux | 1.2.1 |
| Android NDK | 28.2.13676358 |
| AGP / Gradle | 见 `simple_live_app/android` （本轮未改动） |

`media_kit_video` 是本地 fork，升级 libmpv 时它的 API 兼容性必须单独验证，
不能简单跟随 pub 上的 `media_kit_video` 版本。

## 2. 与上游 v1.13.1 的差异

上游 v1.13.1 的 `pubspec.yaml`：

- `media_kit: 1.2.6`
- `media_kit_video: 2.0.1`（注意：不是 1.x）
- `media_kit_libs_video: 1.0.7`
- 另有 `media_kit_libs_windows_video` 走本地 fork

也就是说：上游的“播放器升级”主要落在 `media_kit_video` 1.3.0 → 2.0.1
这个**大版本**上（2.0 有 breaking change），libmpv 本体版本随
`media_kit_libs_video` 走，而该项上游与本仓库相同（都是 1.0.7）。

上游 Android `build.gradle.kts` 中与包体相关的开关只有

```kotlin
isMinifyEnabled = true
isShrinkResources = true
```

本仓库**这两项早已开启**，因此上游的“全设备安装包大小优化”并没有
体现在这两个开关上，需要按版本 diff 逐条核对后才能复刻。

## 3. 本机无法采集的基线（待有构建环境的机器补齐）

本机 Flutter doctor 实测结果：

- Android toolchain：`Unable to locate Android SDK`
- Visual Studio（Windows 桌面）：doctor 检查崩溃，且未安装 MSVC
- Chrome：缺失（不影响移动/桌面产物）

结论：**本轮无法在本机产出任何 release 产物**，因此
Android APK/AAB（按 ABI）、iOS IPA、Windows/macOS/Linux 包体、
启动耗时、首次打开直播耗时、各协议播放成功率这些数字**暂缺**。

这些必须在装有对应 SDK 的机器上补齐，命令示例：

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

每个产物记录：文件大小、构建 commit、Flutter/Dart 版本。

## 4. 本轮已完成的低风险瘦身

删除两个确认无引用的资源（全仓库 `git grep` 验证，仅注释提及）：

| 文件 | 大小 | 结论 |
| --- | --- | --- |
| `simple_live_app/assets/images/egame.png` | 12 KB | 无任何代码引用 |
| `simple_live_app/assets/lotties/loadding.json` | 82 KB | 代码只用 `empty.json` / `error.json` |

收益很小（约 94 KB），属于清理死资源而非实质瘦身，但无风险。

保留（有引用，勿删）：

- `assets/logo_circle.png`、`assets/logo_400.png`：被
  `tool/generate_primary_icons.mjs` 引用（图标生成脚本），
  `logo_400.png` 还是 Windows MSIX 的 `logo_path`。

## 5. 后续步骤（需要构建环境）

1. 在具备 Android SDK / MSVC / macOS 的机器上采集第 3 节的基线数字。
2. 无风险项：按 ABI 拆分产物、检查重复 native 库、核对未使用资源与调试符号。
3. `media_kit_video` 1.3.0 → 2.0.1 的独立提交：先在本地 fork 上验证
   API 兼容，再分平台验证播放（Android 硬解/后台/横竖屏、Windows 音频与
   硬解、macOS/iOS 输出、Linux 启动与音频）。
4. 任一平台回归即回滚该提交，不与其他改动混提。

## 6. 已知与本次工作无关的既有问题

- `simple_live_core/test/douyin_partition_test.dart` 的
  “8 个一级分区都有图” 用例失败：`douyinPartitionImages` 中存在
  `'1'..'7'` 这些二级分区键，与断言的字面量集合不符。源文件与测试
  在本轮均未改动。
- `simple_live_app` 的 `dart analyze lib` 报
  `widgets/glass/glass_controls.dart:17` 未定义 `AppGlassController`，
  属既有问题。
