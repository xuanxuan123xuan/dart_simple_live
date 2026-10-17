# simple_live_core

项目核心库，实现获取各个网站的信息及弹幕。

## 测试

在 `simple_live_core` 包目录运行日常离线回归：

```bash
dart test
```

真实平台的联网冒烟测试位于 `test_live/`，不会被默认命令发现。需要在线验收时显式运行：

```bash
dart test test_live/providers_smoke_test.dart
```

联网测试依赖平台接口、网络环境、当时的直播与弹幕状态；每个平台会等待 30 秒接收弹幕，后续用例依赖前面的房间和清晰度结果。它们不作为日常离线回归的通过标准，也不能替代设备播放验收。

`test/douyin_danmaku_online_test.dart` 验证在线人数消息解析，不访问线上服务，保留在默认离线回归中。
