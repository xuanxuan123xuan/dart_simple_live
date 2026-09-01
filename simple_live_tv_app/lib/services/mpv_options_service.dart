import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/log.dart';

class MpvEffectiveOptions {
  const MpvEffectiveOptions(this.options, this.source);

  final Map<String, String> options;
  final Map<String, String> source;
}

class MpvOptionsService {
  static const Map<String, String> profileLabels = {
    "performance": "流畅",
    "balanced": "均衡",
    "quality": "高画质",
  };

  static const Map<String, String> videoOutputDrivers = {
    "gpu": "gpu（推荐）",
    "gpu-next": "gpu-next",
    "mediacodec_embed": "mediacodec_embed（兼容）",
    "libmpv": "libmpv",
  };

  static const Map<String, String> hardwareDecoders = {
    "auto-safe": "auto-safe（推荐）",
    "auto": "auto",
    "mediacodec": "mediacodec",
    "mediacodec-copy": "mediacodec-copy",
    "no": "no（软件解码）",
  };

  static const Map<String, String> audioOutputDrivers = {
    "audiotrack": "audiotrack（推荐）",
    "aaudio": "aaudio",
    "opensles": "opensles",
    "auto": "auto",
  };

  static const Map<String, Map<String, String>> profiles = {
    "performance": {
      "profile": "fast",
      "hwdec": "auto-safe",
      "vo": "gpu",
      "scale": "bilinear",
      "cscale": "bilinear",
      "dscale": "bilinear",
      "correct-downscaling": "no",
      "sigmoid-upscaling": "no",
      "deband": "no",
    },
    "balanced": {
      "profile": "gpu-hq",
      "hwdec": "auto-safe",
      "vo": "gpu",
      "scale": "spline36",
      "cscale": "spline36",
      "dscale": "mitchell",
      "deband": "no",
    },
    "quality": {
      "profile": "gpu-hq",
      "hwdec": "auto-safe",
      "vo": "gpu",
      "scale": "spline36",
      "cscale": "spline36",
      "dscale": "mitchell",
      "correct-downscaling": "yes",
      "sigmoid-upscaling": "yes",
      "deband": "yes",
    },
  };

  static MpvEffectiveOptions mergeOptions({
    required String profile,
    required bool customOutput,
    required String videoOutput,
    required String hardwareDecoder,
    required String audioOutput,
    required String advancedOptions,
    required bool hardwareDecodeEnabled,
    bool compatMode = false,
    bool isAndroid = false,
  }) {
    final profileOptions = profiles[profile] ?? profiles["balanced"]!;
    final options = Map<String, String>.from(profileOptions);
    final source = <String, String>{
      for (final key in profileOptions.keys) key: "profile:$profile",
    };
    if (customOutput) {
      final custom = <String, String>{
        "vo": videoOutput.trim(),
        "hwdec": hardwareDecoder.trim(),
        "ao": audioOutput.trim(),
      }..removeWhere((_, value) => value.isEmpty);
      options.addAll(custom);
      for (final key in custom.keys) {
        source[key] = "custom";
      }
    }
    final advanced = parseOptions(advancedOptions);
    options.addAll(advanced);
    for (final key in advanced.keys) {
      source[key] = "advanced";
    }
    if (!hardwareDecodeEnabled) {
      options["hwdec"] = "no";
      source["hwdec"] = "hardware-switch";
    }
    if (compatMode && isAndroid) {
      options["vo"] = "mediacodec_embed";
      options["hwdec"] = "mediacodec";
      source["vo"] = "compat-mode";
      source["hwdec"] = "compat-mode";
    }
    return MpvEffectiveOptions(options, source);
  }

  static MpvEffectiveOptions effectiveOptionsWithSource() {
    final settings = AppSettingsController.instance;
    return mergeOptions(
      profile: settings.mpvProfile.value,
      customOutput: settings.customPlayerOutput.value,
      videoOutput: settings.videoOutputDriver.value,
      hardwareDecoder: settings.videoHardwareDecoder.value,
      audioOutput: settings.audioOutputDriver.value,
      advancedOptions: settings.mpvAdvancedOptions.value,
      hardwareDecodeEnabled: settings.hardwareDecode.value,
      compatMode: settings.playerCompatMode.value,
      isAndroid: Platform.isAndroid,
    );
  }

  static Map<String, String> effectiveOptions() {
    return effectiveOptionsWithSource().options;
  }

  static VideoControllerConfiguration videoControllerConfiguration() {
    final settings = AppSettingsController.instance;
    final options = effectiveOptions();
    if (!Platform.isAndroid) {
      return VideoControllerConfiguration(
        hwdec: options["hwdec"],
        enableHardwareAcceleration: settings.hardwareDecode.value,
      );
    }
    return VideoControllerConfiguration(
      vo: options["vo"],
      hwdec: options["hwdec"],
      enableHardwareAcceleration:
          settings.hardwareDecode.value || settings.playerCompatMode.value,
    );
  }

  static Future<void> applyToPlayer(Player player) async {
    if (player.platform is! NativePlayer) return;
    final options = Map<String, String>.from(effectiveOptions())
      ..remove("vo")
      ..remove("hwdec");
    for (final entry in options.entries) {
      try {
        await (player.platform as dynamic).setProperty(entry.key, entry.value);
      } catch (e) {
        Log.d("mpv option skipped: ${entry.key}=${entry.value} $e");
      }
    }
    Log.i("播放器配置：${diagnosticsSummary()}");
  }

  static Map<String, String> parseOptions(String raw) {
    final result = <String, String>{};
    for (final rawLine in raw.split(RegExp(r"\r?\n"))) {
      final withoutComment = rawLine.split('#').first.trim();
      if (withoutComment.isEmpty) continue;
      final normalized = withoutComment.startsWith('--')
          ? withoutComment.substring(2).trimLeft()
          : withoutComment;
      final equalIndex = normalized.indexOf('=');
      if (equalIndex <= 0) continue;
      final key = normalized.substring(0, equalIndex).trim();
      final value = normalized.substring(equalIndex + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  static String diagnosticsSummary() {
    final effective = effectiveOptionsWithSource();
    final keys = effective.options.keys.toList()..sort();
    final applied = keys
        .map(
          (key) =>
              "$key=${effective.options[key]}(${effective.source[key] ?? 'default'})",
        )
        .join(", ");

    return "profile=${AppSettingsController.instance.mpvProfile.value}, "
        "hardwareDecode=${AppSettingsController.instance.hardwareDecode.value}, "
        "compat=${AppSettingsController.instance.playerCompatMode.value}, "
        "options=[$applied]";
  }
}
