# 测试组织

在 `simple_live_app` 包目录执行检查，测试内的源码、配置和资源路径也以该目录为基准：

```bash
flutter test --no-pub
dart analyze lib test
```

默认测试命令会递归发现各目录下的 `*_test.dart`，CI 无需逐个列出文件。

| 目录 | 职责 |
| --- | --- |
| `accounts/` | 登录、Cookie、账号池、身份与 Web 会话 |
| `playback/` | 单房间播放、清晰度、恢复、延迟、后台播放 |
| `playback/multi_room/` | 多房间播放、配置、控制与手势 |
| `ui/` | 通用控件、玻璃效果、布局、绘制与交互 |
| `features/` | 搜索、关注、首页分页、链接解析与配置导入 |
| `platform/` | Android、iOS、Windows、OHOS 专属适配 |
| `infrastructure/` | 缓存、日志、更新、引导初始化与发布工作流 |
| `contracts/` | 纯源码文本、静态配置与资源约束 |

纯源码或静态配置检查归入 `contracts/`；混合行为测试按功能归类；平台专属测试归入 `platform/`。测试文件随组件职责组织，不按用例数量合并。复用辅助代码时放在所属功能目录，不使用 `*_test.dart` 后缀。

例如，只验证画质策略与缓冲计数：

```bash
flutter test --no-pub test/playback/live_room_quality_policy_test.dart test/playback/live_room_auto_quality_buffer_tracker_test.dart
```

Core 的真实平台联网验收独立于本包，运行方式见 [Core 测试说明](../../simple_live_core/README.md#测试)。离线测试不能替代真实平台、原生播放器或设备上的验收。
