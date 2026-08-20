import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';

class OtherSettingsController extends BaseController {
  final videoOutputDrivers = {
    "gpu": "gpu",
    "gpu-next": "gpu-next",
    "xv": "xv (X11 only)",
    "x11": "x11 (X11 only)",
    "vdpau": "vdpau (X11 only)",
    "direct3d": "direct3d (Windows only)",
    "sdl": "sdl",
    "dmabuf-wayland": "dmabuf-wayland",
    "vaapi": "vaapi",
    "null": "null",
    "libmpv": "libmpv",
    "mediacodec_embed": "mediacodec_embed (Android only)",
  };

  final audioOutputDrivers = {
    "null": "null (No audio output)",
    "pulse": "pulse (Linux, uses PulseAudio)",
    "pipewire": "pipewire (Linux, via Pulse compatibility or native)",
    "alsa": "alsa (Linux only)",
    "oss": "oss (Linux only)",
    "jack": "jack (Linux/macOS, low-latency)",
    "directsound": "directsound (Windows only)",
    "wasapi": "wasapi (Windows only)",
    "winmm": "winmm (Windows only, legacy API)",
    "audiounit": "audiounit (iOS only)",
    "coreaudio": "coreaudio (macOS only)",
    "opensles": "opensles (Android only)",
    "audiotrack": "audiotrack (Android only)",
    "aaudio": "aaudio (Android only)",
    "pcm": "pcm (Cross-platform)",
    "sdl": "sdl (Cross-platform, via SDL library)",
    "openal": "openal (Cross-platform, OpenAL backend)",
    "libao": "libao (Cross-platform, uses libao)",
    "auto": "auto (Not available)",
  };

  final hardwareDecoder = {
    "no": "no",
    "auto": "auto",
    "auto-safe": "auto-safe",
    "yes": "yes",
    "auto-copy": "auto-copy",
    "d3d11va": "d3d11va",
    "d3d11va-copy": "d3d11va-copy",
    "videotoolbox": "videotoolbox",
    "videotoolbox-copy": "videotoolbox-copy",
    "vaapi": "vaapi",
    "vaapi-copy": "vaapi-copy",
    "nvdec": "nvdec",
    "nvdec-copy": "nvdec-copy",
    "drm": "drm",
    "drm-copy": "drm-copy",
    "vulkan": "vulkan",
    "vulkan-copy": "vulkan-copy",
    "dxva2": "dxva2",
    "dxva2-copy": "dxva2-copy",
    "vdpau": "vdpau",
    "vdpau-copy": "vdpau-copy",
    "mediacodec": "mediacodec",
    "mediacodec-copy": "mediacodec-copy",
    "cuda": "cuda",
    "cuda-copy": "cuda-copy",
    "crystalhd": "crystalhd",
    "rkmpp": "rkmpp",
  };

  Future<void> editMpvAdvancedOptions() async {
    final textController = TextEditingController(
      text: AppSettingsController.instance.mpvAdvancedOptions.value,
    );
    final value = await Utils.showDialogSafe<String>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: const Text("高级 mpv options"),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: textController,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "每行一个，例如 scale=spline36",
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text("取消")),
          TextButton(
            onPressed: () => Get.back(result: textController.text),
            child: const Text("确定"),
          ),
        ],
      ),
    );
    textController.dispose();
    if (value == null) return;
    AppSettingsController.instance.setMpvAdvancedOptions(value);
    SmartDialog.showToast("已保存，重开直播间后生效");
    update();
  }

  Future<void> importMpvConf() async {
    final path = await MpvOptionsService.importMpvConf();
    if (path == null) return;
    AppSettingsController.instance.setImportedMpvConfPath(path);
    SmartDialog.showToast("已导入 mpv.conf，重开直播间后生效");
    update();
  }

  void clearImportedMpvConf() {
    AppSettingsController.instance.setImportedMpvConfPath("");
    SmartDialog.showToast("已清除导入配置");
    update();
  }
}
