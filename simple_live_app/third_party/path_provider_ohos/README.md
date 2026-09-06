

<p align="center">
  <h1 align="center"> <code>path_provider</code> </h1>
</p>

本项目基于 [path_provider@2.1.0](https://pub.dev/packages/path_provider/versions/2.1.0) 开发。

## 简介

`path_provider` 在 Flutter 中用于获取设备上常用的文件系统路径，例如临时目录、应用文档目录、缓存目录及外部存储相关路径。本实现通过联邦插件（federated plugin）接入 `path_provider`，在 OpenHarmony 上提供与官方插件一致的平台通道能力。

## 下载安装

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

```yaml
...

dependencies:
  path_provider:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/path_provider/path_provider
      # ref: provider-v2.1.1-ohos-1.0.1
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
```

执行命令

```bash
flutter pub get
```

**TAG 版本对应表**

| Flutter 框架版本 | TAG1 | TAG2 | 分支 |
| :--- | :--- | :--- | :--- |
| 3.41 | `provider-v2.1.5-ohos-1.0.0` | `provider-v2.1.5-ohos-1.0.1` | `br_path_provider-v2.1.5_ohos` |
| 3.35 | `provider-v2.1.5-ohos-1.0.0` | `provider-v2.1.5-ohos-1.0.1` | `br_path_provider-v2.1.5_ohos` |
| 3.27 | `provider-v2.1.5-ohos-1.0.0` | `provider-v2.1.5-ohos-1.0.1` | `br_path_provider-v2.1.5_ohos` |
| 3.22 | `provider-v2.1.4_ohos-1.0.0` | `provider-v2.1.4_ohos-1.0.1` | `br_path_provider-v2.1.4_ohos` |
| 3.7 | `provider-v2.1.1-ohos-1.0.0` | `provider-v2.1.1-ohos-1.0.1` | `master` |

## 约束与限制

### 兼容性

在以下版本中已测试通过
1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;


### 权限要求

部分权限属于系统级（`system-level`），而应用默认等级为 `normal`，只能使用 `normal` 级权限。因此，若在应用中申请了系统级权限，安装 HAP 包时可能会出现错误。

打开 `entry/src/main/module.json5`，添加：

```yaml
"requestPermissions": [
  {
   "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"
      ],
      "when":"inuse"
    }
  },
]
```

打开 `entry/src/main/resources/base/element/string.json`，添加：

```
...
{
  "string": [
    {
      "name": "network_reason",
      "value": "使用网络"
    },
  ]
}
```

## 使用示例

本仓库示例 [`example/lib/main.dart`](./example/lib/main.dart) 与下列写法在实现思路上保持一致：都依赖 `path_provider_platform_interface`，使用 `PathProviderPlatform.instance` 调用 `getTemporaryPath()`、`getApplicationDocumentsPath()` 等；界面侧在按钮 `onPressed` 里触发请求，并通过 `FutureBuilder` 展示路径或错误。本文代码片段为精简示例，完整可运行版本请以 `example/lib/main.dart` 为准。


```dart
import 'package:flutter/material.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Future<void> logPathsFromExample() async {
  final PathProviderPlatform provider = PathProviderPlatform.instance;

  final temp = await provider.getTemporaryPath();
  debugPrint('Temporary: $temp');

  final docs = await provider.getApplicationDocumentsPath();
  debugPrint('Documents: $docs');

  final support = await provider.getApplicationSupportPath();
  debugPrint('Support: $support');

  final cache = await provider.getApplicationCachePath();
  debugPrint('Cache: $cache');
}
```

## 使用说明

1. 在 `pubspec.yaml` 中依赖 `path_provider`（Git 源与 `ref` 按上节配置）；示例工程会通过传递依赖解析到 `path_provider_platform_interface`。
2. 路径查询可参考示例实现思路：通过 `PathProviderPlatform.instance` 调用 `getTemporaryPath()` 等方法，并在界面侧通过按钮触发、`FutureBuilder` 展示结果。本文代码片段为精简示例，完整可运行版本请以 `example/lib/main.dart` 为准。

## 接口说明

### API

以下列出与 `path_provider` 平台接口相关的路径能力在本 OHOS 实现中的支持情况。应用层仍以 `path_provider` 主包导出的函数为准。

| 名称                | 返回值                        |  说明               | 类型       | OHOS 支持 |
|---------------------|-------------------------------------------------------------------------------------------------------|------|-------|-------------------|
| getTemporaryPath()   |   Future<String?>             |         获取设备上未备份的临时目录路径，适合存放下载文件的缓存     | function | yes               |
| getApplicationSupportPath()   |    Future<String?>     |    获取应用程序支持文件目录路径的方法，应用程序可能放置应用程序支持文件的目录的路径，如果该目录不存在，则自动创建。         | function | yes               |
| getLibraryPath()   |    Future<String?>     |    获取应用程序 Library 目录路径（iOS/macOS 等平台使用）。OHOS 不支持，调用将抛出 `UnsupportedError`。示例应用仍提供对应按钮以便验证该行为。         | function | no               |
| getApplicationDocumentsPath() |     Future<String?>  |          获取应用程序文件路径的方法，应用程序可以在其中放置用户生成的数据，或者不能由应用程序重新创建的数据。       | function | yes               |
| getApplicationCachePath()   | Future<String?>       |          获取应用程序缓存路径的方法，应用程序可能放置特定于应用程序的缓存文件目录的路径，如果该目录不存在，则自动创建。      | function       | yes              |
| getExternalCachePaths()     | Future<List<String?>> | 获取应用程序的缓存数据可以存储在外部的目录路径，这些路径通常位于外部存储上，如单独的分区或SD卡。手机可能有多个可用的存储目录  | function       | yes               |
| getExternalStoragePath()    |   Future<String?>         |       获取应用程序顶级存储路径的方法，应用程序可以在其中访问顶级存储的目录路径。     |        function       | yes               |
| getExternalStoragePaths([StorageDirectory](#StorageDirectory) arg_directory)   | Future<List<String?>> |   获取应用程序顶级存储路径的方法，应用程序特定的数据可以存储在外部目录的路径，这些路径通常位于外部存储上，如单独的分区或SD卡。手机可能有多个可用的存储目录。 | function       | yes               |
| getDownloadsPath()   | Future<String?>       | 获取下载文件目录路径的方法；OHOS 上基于 `getExternalStoragePaths(StorageDirectory.downloads)` 实现，无可用路径时返回 null。 | function | yes               |

### 属性

#### StorageDirectory

| 名称              | 说明                                                | 类型                                        | OHOS 支持 |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  StorageDirectory.music  | 存储目录的音乐文件类型 |  enum | yes   |
|  StorageDirectory.podcasts  | 存储目录的音频文件类型 |  enum | yes   |
|  StorageDirectory.ringtones  | 存储目录的铃声文件类型 |  enum | yes   |
|  StorageDirectory.alarms  | 存储目录的闹钟铃声文件类型 |  enum | yes   |
|  StorageDirectory.notifications  | 存储目录的通知文件类型 |  enum | yes   |
|  StorageDirectory.pictures  | 存储目录的图片文件类型 |  enum | yes   |
|  StorageDirectory.movies  | 存储目录的电影文件类型 |  enum | yes   |
|  StorageDirectory.downloads  | 存储目录的下载文件类型 |  enum | yes   |
|  StorageDirectory.dcim  | 存储目录的照片和视频文件类型 |  enum | yes   |
|  StorageDirectory.documents  | 存储目录的普通文件类型 |  enum | yes   |

## 不支持的能力

- `StorageDirectory.root`：公开 API 的 `StorageDirectory` 枚举**不包含** `root`，**不支持** `StorageDirectory.root` 写法。获取根目录请使用 `getExternalStoragePaths(type: null)`。
- `getLibraryPath()`：OHOS 不提供与 iOS/macOS 等价的 Library 目录概念，本实现会抛出 `UnsupportedError('getLibraryPath is not supported on OHOS')`（行为与 Android 实现一致）。示例应用 [`example/lib/main.dart`](./example/lib/main.dart) 中仍保留 **Get Library Directory** 按钮，点击后可通过 `FutureBuilder` 查看上述错误信息。

## 与 Android 的差异

部分「外部存储」相关接口与 Android 行为不一致，受平台能力限制无法对齐：

- `getExternalStorageDirectory()`：Android 返回外部存储上的应用专属目录，OHOS 返回应用沙箱内的 `files` 目录（内部存储）。
- `getExternalCacheDirectories()`：Android 可返回多个外部缓存目录，OHOS 仅返回单个应用 `cache` 目录。
- `getExternalStorageDirectories(type)`：Android 返回多个系统级外部媒体/存储目录，OHOS 在 `files` 目录下按类型创建子目录并返回单一路径。
## 遗留问题

## 目录结构

```
|---- path_provider_ohos
|     |---- example                    # 示例应用
|           |---- lib                  # 示例 Dart 代码
|           |---- ohos                 # 示例应用原生代码
|     |---- lib                        # Dart 核心实现
|           |---- path_provider_ohos.dart   # 插件主入口
|           |---- messages.g.dart           # 平台通道消息定义
|     |---- ohos                       # OpenHarmony 原生代码目录
|           |---- src/main/ets/components/plugin/PathProviderOhosPlugin.ets  # 插件入口
|     |---- test                       # 单元测试
|     |---- CHANGELOG.md               # 版本变更记录
|     |---- LICENSE                    # BSD-3-Clause
|     |---- pubspec.yaml               # 包配置文件
|     |---- README.md      # 中文文档
|     |---- README.en.md   # 英文文档
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues) ，当然，也非常欢迎发 [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls) 共建。

## 开源协议

本项目基于 [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/path_provider/path_provider_ohos/LICENSE) ，请自由地享受和参与开源。

> 模板版本: v0.0.1