# What's Changed

> 每次版本更新的变更记录。发布 Release 时该文件内容会附带到简介的 "What's Changed" 部分。

## v1.13.0 (2026-08-03)

### 弹窗稳定性（iOS / LiveContainer）
- 修复所有弹窗"打开后自动关闭"：根因是 LiveContainer / iOS 26 触摸事件重复投递，第二次触摸命中遮罩触发关闭
- 统一防护：右侧弹窗（showRightDialog）、底部弹窗（showModalBottomSheetSafe）、居中弹窗（showDialogSafe）全部加 1s 遮罩防穿透窗口
- 全部 `Get.dialog` / `showModalBottomSheet` / `PopupMenuButton` 调用点统一迁移到自定义 route
- 可取消 Timer 根治跨测试 flaky

### 状态栏（iOS 26）
- iOS 状态栏改为 VC-based 方案：自定义 FlutterViewController 子类 + `prefersStatusBarHidden` 动态返回 + 原生 `simple_live/status_bar` channel 双保险
- LiveContainer 容器兼容：回退子类 cast 到基类，避免容器环境启动崩溃

### 工程与分发
- 分支更名：`feat/ohos-1.12.7` → `stable`（引用同步）
- workflow 中"鸿蒙"统一改"HarmonyOS"
- 新增 AltStore / LiveContainer IPA 源（稳定版 + dev 测试版），Release 附件直接输出 .ipa
- 修复 pbxproj ID 冲突导致 Xcode 项目损坏
