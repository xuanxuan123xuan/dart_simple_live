# libmpv 集成包（HarmonyOS / OpenHarmony）

预编译好的 libmpv 与对接说明，**拿来即用，无需自行编译**。本目录自包含，整份拷走即可。

## 0. 目录内容

| 路径 | 说明 |
|---|---|
| `libs/arm64-v8a/libmpv.so` | 预编译产物，已 strip |
| `include/mpv/client.h` | 公共头，与上面的产物同一次构建产出 |
| `CMakeLists.sample.txt` | 可直接抄的 CMake 接法 |

**产物指纹**（换库后请核对）：

```
sha256  a07d3ccb92ae58b4f6e121681098da6253270d845bc19f31f555e2283b549b58
size    16,999,984 bytes
SONAME  libmpv.so
```

---

## 1. 产物规格

| 项 | 值 |
|---|---|
| 架构 | `arm64-v8a`（aarch64-linux-ohos），**只有这一个 ABI** |
| SONAME | `libmpv.so`（**不是** `libmpv.so.2`） |
| 体积 | 16.21 MiB，gzip -9 后约 7.10 MiB |
| 导出面 | 54 个 `mpv_*`，其余符号全部隐藏 |
| 渲染 | `vo=gpu` / `gpu-next` + **Vulkan**（无 GL/EGL 通路） |
| 硬解 | OHCodec（`h264_oh` / `hevc_oh`），支持 ConsumerSurface 零拷贝直通 |
| 运行时依赖 | SONAME + 11 个 `DT_NEEDED`，全部为系统库，由动态加载器解析 |
| 主要组件版本 | mpv 0.41.0（OHOS fork）、FFmpeg n8.0、libplacebo v7.360.1、mbedtls 3.6.4、dav1d 1.5.1、shaderc v2025.4 |

---

## 2. 放进你的工程

以一个名为 `player` 的模块为例：

```
player/
├── oh-package.json5
├── build-profile.json5                     # externalNativeOptions 指向下面的 CMakeLists
└── src/main/cpp/
    ├── CMakeLists.txt                      # 抄本目录的 CMakeLists.sample.txt
    ├── mpv_napi.cpp                        # 你自己的 NAPI 桥
    ├── include/mpv/                        # ← 本包的 include/mpv/
    ├── third_party/libmpv/libmpv.so        # ← 本包的 libs/arm64-v8a/libmpv.so
    └── types/libmpv_napi/                  # NAPI 的 .d.ts 声明包
        ├── index.d.ts
        └── oh-package.json5
```

模块的 `oh-package.json5` 里把 NAPI 声明包自指为依赖，ArkTS 侧才能 `import ... from 'libmpv_napi.so'`：

```json5
{
  "dependencies": {
    "libmpv_napi.so": "file:./src/main/cpp/types/libmpv_napi"
  }
}
```

---

## 3. CMake 接法

直接抄 `CMakeLists.sample.txt`。三条铁律，每条都是实际踩过的坑：

**① 文件名必须与 SONAME 一致，不要用 patchelf 改名。**
`-l:<file>` 记进 `DT_NEEDED` 的是该文件的 SONAME，名字与 SONAME 不符时运行时会按 SONAME
去 `$ORIGIN` 找不到同名文件。而 patchelf 改 SONAME 会因塞不进原 `.dynstr` 而新建高地址 LOAD 段
并搬走 `.dynsym`/`.dynstr`，`.gnu.hash` 却留在原处，musl 查符号越界 → **dlopen 期 SIGSEGV**。

**② `$ORIGIN` rpath + `--disable-new-dtags` + `-z lazy`。**
前两者让运行时在 NAPI 库同目录找到 `libmpv.so`；`-z lazy` 是因为鸿蒙应用 namespace
对跨库符号用立即绑定时会在加载期误报 mpv API 缺失，延迟解析可绕开。

**③ 不要强链 `libnative_image.so` / 编解码类系统库。**
它们由 `libmpv.so` 自身的 `DT_NEEDED` 拉取。NAPI 侧再强链一遍，会在应用 namespace 里 reloc 失败，
表现为**看起来毫不相关的 `mpv_create not found`**。NAPI 只需要 `libace_napi.z.so`
和（若要调整 surface 尺寸）`libnative_window.so`。

另外两处易漏：

- `LINK_DEPENDS` 要显式声明 `libmpv.so`——手工 `-l:` 指定的库 CMake 推不出依赖关系，
  不声明时**换了 `.so` 也不会触发重链**，POST_BUILD 拷贝随之不执行，包里残留旧库
  （典型症状是「明明换了库却没生效」）。
- POST_BUILD 把 `libmpv.so` 拷进 NAPI 产物目录，运行时才找得到。

---

## 4. NAPI 桥

ArkTS 不能直接调 C，必须自己写一层 NAPI。要点：

- **事件循环**：`mpv_set_wakeup_callback` 唤醒 + 独立线程轮询 `mpv_wait_event`，
  再经 `napi_threadsafe_function` 投递回 ArkTS。不要在 mpv 回调线程里直接碰 napi。
- **属性写入一律异步**（`mpv_set_property_async`）。同步写会阻塞调用线程，
  实测在 UI 线程上连写 4 次耗时 417ms，直接被 XCollie 抓到。
- **日志分档**：`mpv_request_log_messages` 是**全局单一阈值**，`msg-level` 只管终端输出。
  debug 构建用 `debug`，release 降到 `warn`（低于 warn 会让 §6.3 的 interop 看门狗收不到日志）。
  要给单个模块放行 trace，得用 `msg-level=all=debug,<模块>=trace` +
  `mpv_request_log_messages("terminal-default")`。

一个完整播放器实际用到的 API 就下面 19 个，够用：

```
mpv_client_api_version  mpv_create              mpv_initialize          mpv_terminate_destroy
mpv_set_option_string   mpv_set_property_string mpv_set_property_async  mpv_get_property
mpv_get_property_string mpv_observe_property    mpv_unobserve_property  mpv_command
mpv_command_string      mpv_wait_event          mpv_set_wakeup_callback mpv_request_log_messages
mpv_event_name          mpv_error_string        mpv_free
```

---

## 5. 接 XComponent

- XComponent 用 **SURFACE** 类型，拿到的 `surfaceId` 字符串直接作为 mpv 的 `wid` 选项写入。
- 解码侧的 surface 由 libmpv 内部自建（`OH_ConsumerSurface_Create`）。
  **不要**把 XComponent 的 window 交给解码器——那会和 VO 抢同一个 BufferQueue，
  正确形态是解码与 VO 各占一块 surface，解码帧经 NativeImage → `OH_NativeBuffer`
  → Vulkan 外部内存导入 → 回到 XComponent。

**尺寸变化不要重建 XComponent**（会黑闪）。涉及两个属性：

| 属性 | 说明 |
|---|---|
| `wid` | XComponent 的 `surfaceId` 字符串 |
| `ohos-surface-size` | `<宽>x<高>`，须与 surface 的 buffer 几何尺寸一致 |

完整序列：先用 `OH_NativeWindow_CreateNativeWindowFromSurfaceId` + `SET_BUFFER_GEOMETRY`
改 buffer 的几何尺寸——mpv 画在这个 surface 上，buffer 尺寸不改的话组件变大后画面会停在
原尺寸，右侧/下方留黑；再走一次 `vo=null` → 写 `ohos-surface-size` / `wid` / `hwdec`
→ 写回 `vo` 触发热重配。**重配时 `hwdec` 必须沿用本轮已定案的形态**，
否则 10bit 流会被换回 `-copy` 形态，花屏复现。

---

## 6. mpv 选项

取值来自直播场景的实机调优。点播 / 本地文件场景请自行放宽低延迟相关项。

### 6.1 初始化前（`mpv_set_option_string`，须在 `mpv_initialize` 之前）

| 选项 | 取值 | 说明 |
|---|---|---|
| `vo` | `gpu-next` | HDR 直通只在 gpu-next 实现；`gpu` 亦可用，但会失去 §6.4 的 PQ 直通 |
| `gpu-context` | `ohosvk` | **必设**。跳过 displayvk（要 `VK_KHR_display`，鸿蒙 ICD 没有）。auto 会先探 displayvk 再切 vo，Mali 第二次 `vkCreateDevice` 必挂 |
| `gpu-api` | `vulkan` | **必设**。本产物无 GL 通路，不显式指定会先吃一次 `EGL_BAD_MATCH` 才回落 |
| `hwdec` | `ohcodec` | 见 §6.3。产物内已有 SPS bootstrap，起播即挂硬解是可行的 |
| `hwdec-software-fallback` | `3` | 给 OHCodec 若干次失败额度，超出回落软解。旧别名 `vd-lavc-software-fallback` 已废弃，别重复设 |
| `force-window` | `yes` | 未出画时也保持窗口，避免 VO 反复建销 |
| `keep-open` | `yes` | 流断开时不自动销毁播放核 |
| `idle` | `yes` | 无文件时保持核心存活，供下一次 `loadfile` 复用 |
| `input-default-bindings` / `input-vo-keyboard` | `no` | 应用自己处理输入 |
| `msg-level` | `ffmpeg=debug,vd=v,hwdec=v` | 收 ohdec 的 bootstrap 诊断。mpv 把 FFmpeg 的 `AV_LOG_INFO` 降级成 `MSGL_V`、`AV_LOG_VERBOSE` 降成 `MSGL_DEBUG`，所以要 debug 级才收得到 |

### 6.2 低延迟（初始化后写属性，一律走 `mpv_set_property_async`）

直播推荐值，各项含义同 mpv 上游文档：

| 属性 | 取值 |
|---|---|
| `cache` / `cache-pause` | `no` / `no`（宁可丢帧也别卡住） |
| `demuxer-lavf-o` | `fflags=+nobuffer` |
| `demuxer-max-back-bytes` | `100KiB` |
| `demuxer-max-bytes` | 视场景，如 `8MiB` |
| `demuxer-lavf-analyzeduration` / `demuxer-lavf-probesize` | `1.5` / `1500000` |
| `video-sync` | `desync` |
| `framedrop` | `vo` |
| `http-header-fields` | 多数直播源要 `Referer` / `User-Agent`，逗号分隔 |

### 6.3 硬解形态与保险链

本产物支持两种 OHCodec 形态：

| 形态 | 含义 | 何时用 |
|---|---|---|
| `ohcodec` | ConsumerSurface → Vulkan **零拷贝直通** | 默认。8bit / 10bit 均可 |
| `ohcodec-copy` | 解码输出经 CPU 全画面回拷 | 直通失败时的回落 |

建议的保险链：

1. 起播即写 `hwdec=ohcodec`，随后以 `hwdec-current` 的观察值确认是否真的挂上；
2. 确认超时或 `hwdec-current=no` → 降级 `ohcodec-copy`，**只允许一次**；
3. 再失败 → 锁 `hwdec=no` 至本轮播放结束，避免在软硬之间反复横跳。

额外需要一个**看门狗**覆盖「解码正常但 VO 导入每帧失败」的失败面：此时 `hwdec-current`
恒为 `ohcodec`，上面两条保险都不触发，表现为有声黑屏且无路可退。判据是每失败帧恰好一条的
error 级日志（`OHCodec Surface interop failed` / `Timed out waiting for rendered OHCodec Surface buffer`），
累计若干条即降级。

**切档 / 切源时记得清空「本轮已回落」的记忆**，否则一次回落会让后续所有场次都跑在回拷形态上。

### 6.4 HDR

| 选项 | 取值 | 说明 |
|---|---|---|
| `target-colorspace-hint` | `yes` | 让 mpv 把 PQ/BT.2020 原样交给显示管线。**仅 `vo=gpu-next` 消费此选项**，在 `vo=gpu` 上是 no-op |
| `hdr-compute-peak` | `no` | 动态峰值检测对 HDR 源每帧多跑一个 compute pass，实测丢帧 21/s → 14/s。直通生效时本就不走 tone-mapping，保留它是给回落场景兜底 |

配好这两项后，HDR 源的整条 tone-mapping 会被绕开，实机 1080p60 与 2K HDR 均可跑满 60fps；
日志里应能看到 `NativeWindow output switched to BT.2020 PQ`。
若这行没出现而帧率停在 40~45，多半是 `vo` 仍为 `gpu`——该 VO 不消费 `target-colorspace-hint`。

### 6.5 建议观察的属性

`mpv_observe_property` 注册，用于状态机与诊断：

| 属性 | 用途 |
|---|---|
| `pause` / `core-idle` / `paused-for-cache` / `eof-reached` | 播放状态机 |
| `cache-buffering-state` | 缓冲进度 |
| `hwdec-current` | **判断此刻是硬解还是软解的唯一可信来源**（用户偏好和回落标志都不能代替它） |
| `video-codec` / `video-format` | 诊断 |
| `estimated-vf-fps` | 稳态帧率；收敛后不再更新（属性只在变化时通知） |
| `frame-drop-count` / `decoder-frame-drop-count` | 分别是 VO 层丢帧与解码跟不上，两个口径要分开读 |
| `vo-delayed-frame-count` | VO 延迟帧 |
| `container-fps` / `estimated-display-fps` | 源帧率与显示刷新率 |

---

## 7. 能播什么、不能做什么

FFmpeg 是 `--disable-everything` + 显式白名单构建的，**集成前请先确认你的场景在白名单内**：

| 类别 | 已启用 |
|---|---|
| 视频解码 | `h264` `hevc`（软解）、`h264_oh` `hevc_oh`（OHCodec 硬解）、`libdav1d`(AV1)、`vp9` `vp8`、`mjpeg` `png` |
| 音频解码 | `aac` 系、`mp3` 系、`opus` `flac` `vorbis` `ac3` `eac3`、`pcm` 常见变体 |
| 封装 | `flv` `live_flv` `hls` `mpegts` `mov` `matroska` `ogg` `aac` `mp3` `flac` `wav` |
| 协议 | `file` `http` `https` `tcp` `tls` `udp`、`rtmp/rtmps/rtmpt/rtmpts/rtmpe`、`hls` `crypto` `data` `pipe` `fd` |

**明确不支持**（都是有意砍掉的，不是 bug）：

- **录制 / 转码 / 截图编码**：encoder 与 muxer 数量为 0，`png`/`mjpeg` encoder 已移除，
  所以 mpv 的 `screenshot` 命令不可用。
- **RTSP / RTP / SDP**：demuxer 已移除。
- **自定义 `--vf` / `--af` 滤镜链**：filter 只保留了 mpv 内部做格式协商的最小集
  （`scale` `format` `aformat` `aresample` `null` `anull` `setpts` `asetpts` `volume` `atempo` `pan` `fps`）。
  用到集外滤镜会**静默不生效或起播失败**。
- **Lua 脚本**、**ICC profile**、**Dolby Vision**、**OpenGL 渲染**、**命令行播放器**。

需要白名单之外的能力，请向本产物的维护方提出，由其重新构建，不建议自行替换产物。

---

## 8. 打包相关

- `abiFilters` 只需 `arm64-v8a`；本产物没有其它架构。
- `module.json5` 的 `compressNativeLibs` 设 `true` 时下载体积按 gzip 量级走
  （16.21 → 约 7.10 MiB），代价是首次加载要解压，装机占用不变。
- 联网播放记得申请 `ohos.permission.INTERNET`；后台播放另需长时任务与相应权限。

---

## 9. 排错

先按日志关键词对号入座：

| 日志关键词 / 症状 | 指向 |
|---|---|
| `Load native module failed` / `mpv_create not found` | §3 三条铁律，尤其②③ |
| `excluding due to too low API version` / vo 线程 SIGSEGV `@0` | Mali-G610 报 Vulkan 1.1。本产物已把 libplacebo 下限降到 1.1，并为 `vkWaitSemaphores`/`vkResetQueryPool` 回落 KHR/EXT 入口 |
| 换了 `.so` 但行为没变 | §3 的 `LINK_DEPENDS`，包里多半是旧库 |
| `missing parameter sets`、有声黑屏且无任何解码错误 | 参数集未就绪；产物内已实现 SPS bootstrap 与 6 秒看门狗，超时会自动回落软解。若持续黑屏请提供日志 |
| `buffer's memory is nullptr` | 在 SURFACE 模式下读了 CPU 内存——该模式的 `OH_AVBuffer` 没有可映射内存 |
| `SURFACE format without graphic pixel format; assuming NV12` | 格式误判，HDR 会花屏 |
| `IDENTITY` / `sampler is null` | 颜色走错分支或 descriptor 写了空句柄（只会采到 Y 分量） |
| `OHCodec Surface interop failed` / `Timed out waiting for rendered OHCodec Surface buffer` | VO 侧 Vulkan 导入失败，需按 §6.3 的看门狗降级到 `ohcodec-copy` |
| 画面右下留黑、全屏不铺满 | §5 的 `SET_BUFFER_GEOMETRY` |

硬解与 HDR 通路正常时，日志里应当出现：

```
vo/gpu/ohcodec:   OHCodec is using ConsumerSurface Vulkan raw-YUV zero-copy
vd:               Decoder format: ... ohcodec[p010] bt.2020-ncl/bt.2020/pq/limited
vo/gpu/ohcodec:   OHCodec YCbCr model=4 ... dst=rgba64
vo/gpu-next/ohos: NativeWindow output switched to BT.2020 PQ
```

8bit 档对应 `format=24 high_depth=0 dst=rgb0`、`YCbCr model=2`（BT.709）。

---

## 10. 许可

`libmpv.so` 是 mpv 与其依赖的静态链接组合：mpv 以 `-Dgpl=false` 构建（LGPL 2.1+），
FFmpeg 以 `--enable-version3` 且未启用 `--enable-gpl` 构建（LGPL 3），
另有 mbedtls（Apache-2.0）、dav1d（BSD-2）、libass（ISC）、freetype（FTL / GPLv2 双许可）、
harfbuzz（MIT）、shaderc（Apache-2.0）等。

实务上：以**动态库**形式集成（本文方案即是）、随应用附上各依赖的许可声明、
保留终端用户替换 `libmpv.so` 的可能性。以上为工程说明而非法律意见，商用前请自行核实。
