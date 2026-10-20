# 直播录制实现与验收记录

普通客户端在直播间右上角的“更多”菜单提供“录制直播”开关，普通模式和全屏共用入口。开启时选择仅视频、视频＋弹幕数据或自动合成弹幕，记住上次选择。红点和时长不随播放控件隐藏。已保存的内容从“我的 → 录制文件”访问。

桌面首次录制选择保存目录，手机使用应用文档目录。录制列表支持播放、合成、重试、取消、分享、另存、删除及打包导出弹幕素材。原始 MKV 与弹幕资源保留在每段独立目录中；`export-work` 中的分块图片和编码中间文件在导出结束或失败时清理。

## 媒体与时间轴

- `RecordingService` 串行管理唯一采集会话和导出队列；房间协调器绑定播放器、绘制记录与房间生命周期。
- `MpvRecordingSource` 设置当前播放器的 `stream-record`，不重新获取或连接直播地址。更换播放源前等待本段停止。
- mpv 不录制开始前已缓存的包，并会重排写出文件的时间戳。通过播放器中带媒体 PTS 的多个独立帧指纹，与最终本地文件的解码帧匹配，确定文件时间到观看媒体时间的映射。至少三个唯一帧的偏移需要在 35 ms 内一致，不使用点击后的墙钟秒数推算。
- 本地时间轴验证播放器显式启用视频解码；原生 media_kit 在未挂载 VideoController 时默认禁用视频。MKV 创建后首个簇刷新前可能长度为零，所以启动时确认创建，停录后用 FFprobe 检查轨道和时长。
- 去除首个可解码视频帧之前的内容，并限制导出结束时间，避免将尚未观看的缓存尾部烧入弹幕。静态、过短或无法匹配的内容保留材料并提示无法确认映射，不输出声称同步的弹幕成片。
- 无弹幕成片优先流复制到 MP4；编码不兼容或封装失败保留 MKV。弹幕成片为 H.264/AAC MP4，保留源视频分辨率。

## 弹幕与生命周期

本地 canvas_danmaku 的捕获钩子默认关闭。启用后记录实际绘制的文字、描边、图片、混排及特殊弹幕的 PNG 资源、位置、变换、透明度和媒体时间。已有弹幕、清屏、图片加载更新和设置变化通过实际重绘进入时间轴。视频矩形映射同时处理 contain 黑边、cover 裁切、拉伸、全屏边距与窗口变化。聊天列表、播放器控件和独立醒目留言卡片不参与合成。

导出流式读取 JSONL，以两秒为一块生成最多 60 fps 的透明叠加层，复用有界图片缓存。块间连续音频在最后统一编码，避免每块 AAC 编码的累积延迟。失败、取消与后台暂停均保留原始材料。

离房、暂停、刷新、切流、重连前停止采集；移动端进入 hidden/paused 时先刷新待保存的绘制记录并停止采集，导出等待前台后重新执行。桌面失焦不停止。下次打开录制目录会将未正常结束的清单识别为可恢复的中断任务。异常退出前未完成时间映射的任务只能恢复原始视频和材料，不能直接生成已验证同步的成片。

不在清单、绘制资源或录制日志中写入 Cookie、鉴权请求头或直播地址。FFmpeg 导出输入只允许本地 file/pipe 协议。

## 依赖与本机验证

固定 `ffmpeg_kit_flutter_new: 4.6.7`。原有部分 media_kit 原生库禁用了 muxer，无法实际写出 stream-record；应用局部覆盖为带封装器的固定原生构建，下载时校验 SHA-256。Linux 使用系统 libmpv，启动时检查实际文件创建。iOS 最低版本调整为 14。第三方原生库说明随应用资源提供。

Windows 本机使用 Flutter 3.41.9。仓库声明 Flutter >=3.44.7，未降低仓库约束；本地测试通过独立依赖解析目录及独立的本次改动快照运行，避免混入其他任务的播放器改动。该结果不能替代要求版本 SDK 的正式构建验收。

已验证：

- canvas_danmaku 包 33 项测试通过。
- 录制、回放像素比较、坐标映射、菜单开关及相关播放策略共 54 项测试通过，包括移动端停录等待绘制落盘和清单写入失败释放采集资源。
- 录制相关代码和五个播放器接入文件分析无 error/warning，已有 12 条 info 级建议保留。
- Windows 原生测试入口 `simple_live_app/test_native/recording_smoke.dart`：本地 HTTP FLV/HLS H.264/AAC，以及 HLS HEVC/AAC，均完成实际录制、时间轴匹配、无损封装、分块弹幕合成及成片 FFprobe/完整解码检查，320×180 分辨率保持不变。
- 同一本次改动独立快照的普通应用入口 Windows Debug 构建通过。

在普通 Flutter 环境重现测试：

```powershell
cd simple_live_app
flutter pub get
flutter test --no-pub test/recording test/playback/player_controls_auto_hide_test.dart test/playback/player_volume_session_policy_test.dart test/playback/live_room_quality_policy_test.dart
$env:SIMPLE_LIVE_RECORDING_SMOKE_DIR = 'E:/recording-smoke'
flutter run -d windows -t test_native/recording_smoke.dart --no-pub
```

原生测试生成合成样片，输出目录下的 `result.json` 汇总每种输入的时间映射、输出编码、时长、尺寸和验证结果。

尚待验收：Windows 正式 SDK/Release、真实直播与 GPU 播放画面、至少 30 分钟录制、高密度图片弹幕、端到端视觉时差不超过 100 ms；Android、iOS、macOS、Linux 的构建和真机插件加载、录制、合成、播放、系统文件导出。当前 Windows 环境没有已配置的 Android SDK，也没有 Apple/Linux 构建宿主。代码接入和依赖声明不等同于这些平台的运行验收。
