# 鸿蒙（HarmonyOS NEXT）已知问题清单

> 由 4 路只读子代理审计（player/isOhos 分支、平台误判、布局 SafeArea、原生插件）产出。
> 状态列：✅ 已修 / 🔧 待修 / ℹ️ 信息项。修改后更新此表。

## 🔴 高风险

| # | 位置 | 问题 | 状态 |
|---|------|------|------|
| H1 | `third_party/video_player_ohos/ohos/src/main/ets/components/videoplayer/VideoPlayer.ets:161` | `globalVideoList` 从未 `setObject` 初始化，COMPLETED/previousVideo/nextVideo 路径 `getObject(...).length` 抛 TypeError（视频播完/切集必崩） | 🔧 |
| H2 | `third_party/video_player_ohos/ohos/src/main/ets/components/videoplayer/VideoPlayerApiImpl.ets:260` | create 的 Pigeon handler 无 `.catch()`，创建失败（URL 解析/setMediaSource 抛错）时 reply 永不调用，Dart 侧永久挂起 | 🔧 |
| H3 | `app/utils.dart:540` `checkStorgePermission` | 鸿蒙上 `Platform.isAndroid` 可能为 true → 走 Android 存储权限流程（permission_handler/device_info 无实现）→ 返回 false，配置包导入导出/屏蔽预设被"没有存储权限"拦截（应先 `if (!Platform.isAndroid \|\| Utils.isOhos) return true;`） | 🔧 |
| H4 | `live_room/player/player_controller.dart:693/2156` | 全屏过渡（`ohosFullscreenTransition` true，约 1.5s）中退出直播间，`exitFull` 直接 return → `fullScreenState` 停留 true、方向锁定横屏、系统栏残留，无自愈 | 🔧 |
| H5 | `simple_live_core/lib/src/scripts/douyin_sign.dart:10651+` | 签名调用无 try/catch（QuickJS .so 缺失/符号不匹配时抖音/斗鱼全链路挂）；`getSignature` while 重试无次数上限 | 🔧 |
| H6 | `live_room/player/player_controller.dart:1091` `_captureOhosScreenshot` | 原生窗口截图失败后回退 Flutter `toImage`，抓不到 AVPlayer 原生纹理 → 保存黑屏图 | 🔧 |

## 🟡 中风险

| # | 位置 | 问题 | 状态 |
|---|------|------|------|
| M1 | `live_room_page.dart:821` `_buildOhosBottomBar` | 鸿蒙全屏底栏 7 按钮 + 3 段文本 ≈512px，窄屏/横屏全屏横向溢出（鸿蒙独有） | 🔧 |
| M2 | `live_room/player/player_controller.dart:1853` | 鸿蒙播放中 wakelock 为 no-op（`_setKeepScreenAwake` 对 ohos 直接 return），长时间观看屏幕自动熄屏 | 🔧 |
| M3 | `live_room/player/ohos_video_player.dart:140` `_initialize` | 初始化失败/超时后 controller 不 dispose、不 detach，原生 AVPlayer 悬挂占用资源 | 🔧 |
| M4 | `VideoPlayer.ets:609` `getIUri` | 每次打开新 fd 不关旧的，本地视频切换累积 fd 泄漏 | 🔧 |
| M5 | `VideoPlayer.ets:190` ERROR 分支 | reset 触发 IDLE 自动重载，对不可恢复 IO 错误形成失败→reset→重载死循环 | 🔧 |
| M6 | `VideoPlayer.ets:170` RELEASED 回调 | 对已释放 avPlayer 二次 release，且未置 null | 🔧 |
| M7 | `VideoPlayerApiImpl.ets:100-140` | create 中资源提取无 try-finally，fetchMetadata/fetchFrameByTime 抛错时 extractor/generator 不 release | 🔧 |
| M8 | `VideoPlayerApiImpl.ets:40/113/135` | PixelMap 从不 release，asset/fd 每创建一次泄漏位图 | 🔧 |
| M9 | `OhosPipManager.ets:114` | `pipStarting` 无超时兜底，STARTED 事件丢失时 PiP 状态卡死 | 🔧 |
| M10 | `live_room_controller.dart:3803` | 前台恢复仅 `play()` 不检测断流，流已死时画面卡死无提示 | 🔧 |
| M11 | `player_controller.dart:765` `_waitForOhosViewport` | 1.5s 超时后无降级，方向未就绪仍完成全屏（竖屏黑边/横屏错位） | ℹ️ |
| M12 | `main.dart:131` | 启动 edgeToEdge fire-and-forget，与 exitFull 的 manual+overlays 语义不一致（flutter_ohos 对 edgeToEdge 支持不完整） | ℹ️ |
| M13 | `OhosMediaPlugin.ets:63` | `window.getLastWindow` 用应用级 Context（应为 UIAbilityContext），截图可能失败 | 🔧 |
| M14 | `OhosBackgroundPlaybackPlugin.ets:70` | `startBackgroundRunning` 失败时 session 已 activate 未回收 | 🔧 |
| M15 | `player_controls.dart:40` `_fullScreenControlPadding` | 鸿蒙全屏控件无安全边距修正（圆角/折叠屏贴近边缘） | ℹ️ |

## 🟢 低风险 / 信息项

| 位置 | 问题 | 状态 |
|------|------|------|
| `platform_utils.dart:28` + `indexed_controller.dart:88` | 鸿蒙不恢复上次直播间（与 Android/iOS 行为不一致，设计取舍） | ℹ️ |
| `live_subtitle_service.dart:48` | 字幕特性全局关闭（鸿蒙无独立字幕路径） | ℹ️ |
| `background_playback_service.dart:38` | detach 后 channel handler 未清空（当前安全） | ℹ️ |
| `OhosNotificationPlugin.ets:100` | BUNDLE_NAME/ABILITY_NAME 硬编码 `com.simplelive.app` | ℹ️ |
| `VideoPlayer.ets:420` | 直播流 duration=0 时 initProgress 除零（NaN 写入 progressVal） | ℹ️ |
| `VideoPlayer.ets:585` | CACHED_DURATION 事件不带值，Dart 侧落到 unknown | ℹ️ |
| `Messages.ets:258` | PlaybackSpeedMessage 类型断言错误（实为 Number） | ℹ️ |
| `OhosWidgetPlugin.ets:106` | notifyFormsChange 传空 formId 数组 | ℹ️ |
| `ohos_pip_service.dart:85` | dispose 后再次 initialize 对已关闭 StreamController add 抛 StateError | ℹ️ |

## 已修复项（最近轮次）

- ✅ 全屏方向切换画面变形（方向就绪后再切布局 → 按用户选择改为立即全屏 + 黑边过渡）
- ✅ 鸿蒙退出全屏状态栏不恢复（edgeToEdge → manual + overlays）
- ✅ 对话框 BOTTOM OVERFLOWED / 输入框键盘弹出上移（showDialogSafe 默认 isScrollControlled + 去掉 viewInsets 上移）
- ✅ 底部弹窗标题与状态栏重叠（_RightSideSheetRoute SafeArea top: true）
- ✅ QuickJS jsSetMemoryLimit 符号缺失（compat 不传 memoryLimit）
- ✅ 直播间有声音没画面（回滚 Texture 直出）
