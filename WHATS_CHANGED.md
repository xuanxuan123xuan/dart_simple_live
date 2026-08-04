# What's Changed

> 每次版本更新的变更记录。发布 Release 时该文件内容会附带到简介的 "What's Changed" 部分。

## v1.13.0 (2026-08-03)

### 弹窗稳定性（iOS / LiveContainer）
- 修复所有弹窗"打开后自动关闭"：根因是 LiveContainer / iOS 26 触摸事件重复投递，第二次触摸命中遮罩触发关闭
- 统一防护：右侧弹窗（showRightDialog）、底部弹窗（showBottomSheet / showModalBottomSheetSafe）、居中弹窗（showDialogSafe）、下拉菜单（PopupMenuButton → showRightDialog）全部加 1s 遮罩防穿透窗口
- 可取消 Timer 根治跨测试 flaky

### 状态栏（iOS 26）
- 排查并定位：Flutter 3.22 引擎未适配 iOS 26 scene-based 状态栏管理，`SystemChrome` 隐藏失效
- 原生强制隐藏通道（simple_live/status_bar）+ 周期重检（最长 3s）+ 周期重试（5 次）对抗系统恢复
- LiveContainer 下系统状态栏被容器接管，增加顶部黑条视觉兜底

### Flutter 升级（dev 分支）
- 全平台 Flutter 3.22 → 3.41.x：intl 0.19.0 → 0.20.2、onPopInvoked → onPopInvokedWithResult
- 鸿蒙可同步升级（[flutter_flutter_ohos](https://github.com/xuanxuan123xuan/flutter_flutter_ohos) 镜像 oh-3.41.9-release 分支）
- workflow 版本校验、VS/Xcode 注释同步更新

### 构建与发布
- AltStore / LiveContainer 双 IPA 源（稳定版 + dev 测试版），README 展示
- Release 结构优化：SHA-256 校验值进简介（不再作为 asset）、Android 主 app 不再发布 universal APK 与 AAB、简介精简
- iOS workflow 发布固定 tag `ios-dev` / `ios-stable` 供源使用
