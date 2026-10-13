# 聚映 HAP：播放器实现借鉴笔记

## 1. 播放链路

```text
ArkUI XComponent(SURFACE)
        ↓ surfaceId / NativeWindow
libmpv_napi.so
        ↓ libmpv client API
定制 libmpv + OHCodec + Vulkan
```

播放器使用 `XComponentType.SURFACE`，组件 ID 为 `livify_player_RenderFitSurface`，画面区域铺满、黑色背景，并使用 `RenderFit.RESIZE_FILL`。

## 2. 初始化参数

反汇编中可以确认的低延迟参数包括：

```text
demuxer-lavf-analyzeduration = 0.5
demuxer-lavf-probesize       = 1500000
demuxer-lavf-o               = fflags=+nobuffer
demuxer-max-back-bytes       = 100KiB
cache                        = no
cache-pause                  = no
video-sync                   = desync
framedrop                    = vo
target-colorspace-hint       = yes
```

默认 demux 缓冲上限为 8 MiB，且可在设置中调整。这里的目标是直播低延迟，不是点播拖动体验。

## 3. 鸿蒙硬解策略

播放器默认尝试 OHCodec 硬解：

```text
ohcodec 直出 Surface
   └─ 互操作失败 / 长时间无渲染
      → ohcodec-copy
         └─ 仍失败
            → hwdec=no（软件解码）
```

直出失败累计到阈值后切换到 `ohcodec-copy`；硬解模式长时间没有确认成功也会触发切换；copy 模式再次超时后锁定软件解码，避免循环抖动。

## 4. 首帧与黑屏处理

`FILE_LOADED` 不直接代表用户已经看到画面。它的处理顺序是：

1. mpv 报告文件已加载。
2. 页面继续保留封面。
3. 监听 `estimated-vf-fps` 等属性确认真正开始输出视频帧。
4. 收到渲染回调后才显示视频 Surface。
5. 如果回调迟迟不来，约 10 秒后走最终兜底。

这比“收到播放成功回调就立刻隐藏封面”稳定得多，能避免有声无画和黑屏闪现。

## 5. Surface 重建

Surface 创建、销毁和尺寸变化分别处理：

- 新 Surface 创建后重新设置 `wid`。
- 尺寸变化同时更新 NativeWindow 和 `ohos-surface-size`。
- 首次尺寸变化可能执行 `vo=null → gpu-next`，强制视频输出重新配置。
- 页面重载后新 Surface 未及时出现时，短暂复用旧 Surface。

折叠屏展开、横竖屏切换、画中画返回时，这套机制比单纯重建播放器更不容易闪退。

## 6. 建议在 Flutter 项目中抽象出的接口

不要让页面直接调用 mpv/NAPI，建议隔离成：

```dart
abstract interface class LivePlayer {
  Future<void> attachSurface(String surfaceId);
  Future<void> setSurfaceSize(int width, int height);
  Future<void> play(String url, {Map<String, String>? headers});
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setHardwareDecode(bool enabled);
  Future<void> release();
}
```

页面只订阅 `preparing / buffering / playing / error / rendering` 等状态，不直接处理 native handle。

