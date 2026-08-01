# simple_live_app

Simple Live 的 Flutter 客户端，支持 Android、iOS、Windows、macOS、Linux，以及本分支维护的 HarmonyOS NEXT 端口。

当前应用版本：`1.13.0+11300`。本分支使用 Flutter 3.22.x，依赖版本已经按该工具链固定。

## 目录

- `lib/modules/live_room`：单直播间、全屏、小窗和播放控制。
- `lib/modules/multi_room`：2～4 路多开、布局、聊天区、暂停/音频控制和自适应画质。
- `lib/services`：常亮锁、系统栏、内存监控及其他应用级服务。
- `ohos`：HarmonyOS NEXT 工程与 ArkTS 原生插件。
- `tool`：版本同步及鸿蒙构建脚本。

## 开发检查

```bash
dart analyze lib test
flutter test
dart run tool/app_version.dart check
```

## 版本号

只修改 `pubspec.yaml` 中的 `version`，然后执行：

```bash
dart run tool/app_version.dart sync
```

该命令会同步 Flutter 生成常量与鸿蒙版本配置。构建号必须满足 `major × 10000 + minor × 100 + patch`。

更多平台功能、构建方式和使用说明见仓库根目录 [README](../README.md)。
