import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_core/simple_live_core.dart';

class MpvOptionsService {
  static const Map<String, String> profileLabels = {
    "performance": "流畅",
    "balanced": "均衡",
    "quality": "画质",
  };

  static const Map<String, String> liveLatencyModeLabels = {
    "off": "关闭",
    "auto": "自动（推荐）",
    "aggressive": "激进",
  };

  static const Map<String, String> _defaultLiveLatencyOptions = {
    "cache": "yes",
    "cache-on-disk": "yes",
    "cache-secs": "10",
    "demuxer-readahead-secs": "1",
    "cache-pause": "yes",
    "audio-buffer": "0.2",
  };

  /// Options applied on every platform before profile/user options.
  ///
  /// `audio-client-name` is what libmpv passes to
  /// `IAudioSessionControl::SetDisplayName`, so it decides how the app is
  /// labelled in the Windows volume mixer. Without it the entry falls back to
  /// libmpv's own default and users can't find the app by name.
  static const Map<String, String> _baseOptions = {
    "audio-client-name": "SimpleLive",
  };

  /// Option keys whose accepted values depend on the platform's libmpv build.
  static const Set<String> platformScopedKeys = {"ao", "vo", "hwdec"};

  /// `ao`/`vo`/`hwdec` values that exist only in some platforms' libmpv builds,
  /// mapped to the platforms that actually provide them.
  ///
  /// Options reach libmpv verbatim, and a config can arrive from another device
  /// (imported profile, or values copied from a guide written for another
  /// platform). A foreign `vo`/`hwdec` only degrades to software decoding, but a
  /// foreign `ao` makes libmpv fail audio init outright and play with no sound:
  /// `ao=audiotrack` (Android) on Windows yields
  /// "Failed to initialize audio driver 'audiotrack'" and then "Audio: no audio".
  ///
  /// Values absent from this table are always kept. The table lists only what is
  /// known to be platform-exclusive, so cross-platform and debugging values
  /// (`auto`, `auto-safe`, `no`, `null`, `openal`, `sdl`, `gpu`, …) pass through.
  static const Map<String, Set<String>> platformExclusiveValues = {
    // --- ao ---
    "audiotrack": {"android"},
    "opensles": {"android"},
    "wasapi": {"windows"},
    "coreaudio": {"macos", "ios"},
    "coreaudio_exclusive": {"macos"},
    "pulse": {"linux"},
    "pipewire": {"linux"},
    "alsa": {"linux"},
    "oss": {"linux"},
    // --- vo ---
    "mediacodec_embed": {"android"},
    "x11": {"linux"},
    "wayland": {"linux"},
    // --- hwdec ---
    "mediacodec": {"android"},
    "mediacodec-copy": {"android"},
    "mediacodec-dec": {"android"},
    "d3d11va": {"windows"},
    "d3d11va-copy": {"windows"},
    "dxva2": {"windows"},
    "dxva2-copy": {"windows"},
    "videotoolbox": {"macos", "ios"},
    "videotoolbox-copy": {"macos", "ios"},
    "vaapi": {"linux"},
    "vaapi-copy": {"linux"},
    "vdpau": {"linux"},
    "vdpau-copy": {"linux"},
  };

  static const Map<String, Map<String, String>> desktopProfiles = {
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
    "balanced": <String, String>{},
    "balancedDesktop": {
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
      "vo": "gpu-next",
      "scale": "ewa_lanczossharp",
      "cscale": "ewa_lanczossoft",
      "dscale": "mitchell",
      "correct-downscaling": "yes",
      "sigmoid-upscaling": "yes",
      "deband": "yes",
    },
  };

  static Map<String, String> effectiveOptions() {
    return effectiveOptionsWithSource().options;
  }

  /// Platform token used to match [platformExclusiveValues].
  ///
  /// OHOS is not special-cased: it never reaches libmpv (playback uses
  /// video_player there), and reporting it as Android keeps Android values,
  /// which is the harmless direction.
  static String currentPlatform() {
    if (Platform.isWindows) return "windows";
    if (Platform.isMacOS) return "macos";
    if (Platform.isIOS) return "ios";
    if (Platform.isLinux) return "linux";
    if (Platform.isAndroid) return "android";
    return "unknown";
  }

  static bool isValueSupportedOn(String value, String platform) {
    final platforms = platformExclusiveValues[value.trim().toLowerCase()];
    // Unlisted values are cross-platform or unknown to us: keep them.
    return platforms == null || platforms.contains(platform);
  }

  /// Drops `ao`/`vo`/`hwdec` values that the platform's libmpv cannot provide.
  ///
  /// Returns the surviving options plus the dropped ones, so callers can show
  /// what was ignored instead of leaving the user with silent breakage.
  static MpvPlatformFilterResult filterForPlatform(
    Map<String, String> options,
    String platform,
  ) {
    final kept = Map<String, String>.from(options);
    final ignored = <String, String>{};
    for (final key in platformScopedKeys) {
      final value = kept[key];
      if (value == null || isValueSupportedOn(value, platform)) {
        continue;
      }
      kept.remove(key);
      ignored[key] = value;
    }
    return MpvPlatformFilterResult(kept, ignored);
  }

  static MpvEffectiveOptions effectiveOptionsWithSource() {
    final settings = AppSettingsController.instance;
    final profile = settings.mpvProfile.value;
    final profileOptions = _profileOptionsForPlatform(profile);
    final options = <String, String>{
      ..._baseOptions,
      ...profileOptions,
    };
    final source = <String, String>{
      for (final key in _baseOptions.keys) key: "base",
      for (final key in profileOptions.keys) key: "profile:$profile",
    };
    if (settings.customPlayerOutput.value) {
      final vo = settings.videoOutputDriver.value.trim();
      final hwdec = settings.videoHardwareDecoder.value.trim();
      final ao = settings.audioOutputDriver.value.trim();
      if (vo.isNotEmpty) {
        options["vo"] = vo;
        source["vo"] = "custom";
      }
      if (hwdec.isNotEmpty) {
        options["hwdec"] = hwdec;
        source["hwdec"] = "custom";
      }
      if (ao.isNotEmpty) {
        options["ao"] = ao;
        source["ao"] = "custom";
      }
    }
    final advancedOptions = parseOptions(settings.mpvAdvancedOptions.value);
    options.addAll(advancedOptions);
    for (final key in advancedOptions.keys) {
      source[key] = "advanced";
    }
    final confOptions = parseConfFile(settings.importedMpvConfPath.value);
    options.addAll(confOptions);
    for (final key in confOptions.keys) {
      source[key] = "conf";
    }
    // Applied last so it covers every source, including options imported from
    // another platform's config.
    final filtered = filterForPlatform(options, currentPlatform());
    for (final entry in filtered.ignored.entries) {
      Log.d(
        "mpv option ignored (${currentPlatform()} 不支持): "
        "${entry.key}=${entry.value} source=${source[entry.key]}",
      );
    }
    return MpvEffectiveOptions(
      filtered.options,
      source,
      ignored: filtered.ignored,
    );
  }

  static VideoControllerConfiguration videoControllerConfiguration() {
    final settings = AppSettingsController.instance;
    if (settings.playerCompatMode.value && Platform.isAndroid) {
      return const VideoControllerConfiguration(
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
      );
    }
    final effectiveOptions = effectiveOptionsWithSource();
    final options = effectiveOptions.options;
    if (!Platform.isAndroid) {
      // 不传 vo：media_kit 各平台使用默认 video output。
      // （桌面 profile 里的 gpu/gpu-next 是给 vo=gpu 场景设计的，
      //  iOS 的 libmpv 不接受，传入会导致 VideoController 初始化失败黑屏。）
      return VideoControllerConfiguration(
        hwdec: _desktopVideoControllerHwdec(effectiveOptions),
        enableHardwareAcceleration: settings.hardwareDecode.value,
      );
    }
    return VideoControllerConfiguration(
      vo: options["vo"],
      hwdec: options["hwdec"],
      enableHardwareAcceleration: settings.hardwareDecode.value,
      // Fix Issue #57: 安卓全屏后画面卡死 - 延迟attach避免surface race condition
      androidAttachSurfaceAfterVideoParameters: true,
    );
  }

  static Future<void> applyToPlayer(Player player) async {
    // iOS 使用 libmpv vo，所有 mpv profile/scaler 选项都是为 gpu vo
    // 设计的，强行设置会破坏 libmpv 的颜色渲染管线（偏绿/偏紫）。
    if (Platform.isIOS) {
      return;
    }
    if (player.platform is! NativePlayer) {
      return;
    }
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
  }

  /// Returns the live-stream buffering profile for a protocol.
  ///
  /// FLV/RTMP can safely use a smaller client-side queue. HLS/fMP4 needs a
  /// larger conservative queue because the stream itself is segmented.
  static Map<String, String> liveLatencyOptions(
    String mode,
    LiveStreamProtocol protocol,
  ) {
    if (mode == "off") {
      return Map<String, String>.unmodifiable(_defaultLiveLatencyOptions);
    }

    final isLowLatencyProtocol = protocol == LiveStreamProtocol.flv ||
        protocol == LiveStreamProtocol.rtmp;
    if (mode == "aggressive" && isLowLatencyProtocol) {
      return const {
        "cache": "yes",
        "cache-on-disk": "no",
        "cache-secs": "0.5",
        "demuxer-readahead-secs": "0.5",
        "cache-pause": "no",
        "audio-buffer": "0",
      };
    }

    if (mode == "aggressive") {
      return const {
        "cache": "yes",
        "cache-on-disk": "no",
        "cache-secs": "0.5",
        "demuxer-readahead-secs": "0.5",
        "cache-pause": "no",
        "audio-buffer": "0.05",
      };
    }

    if (isLowLatencyProtocol) {
      return const {
        "cache": "yes",
        "cache-on-disk": "no",
        "cache-secs": "0.5",
        "demuxer-readahead-secs": "0.5",
        "cache-pause": "no",
        "audio-buffer": "0.05",
      };
    }

    return const {
      "cache": "yes",
      "cache-on-disk": "no",
      "cache-secs": "1",
      "demuxer-readahead-secs": "1",
      "cache-pause": "no",
      "audio-buffer": "0.1",
    };
  }

  /// Applies the protocol-aware buffering profile immediately before opening
  /// a URL. Advanced options and imported mpv.conf keep higher precedence.
  static Future<void> applyLiveLatencyOptions(
    Player player,
    LiveStreamProtocol protocol,
  ) async {
    if (Platform.isIOS || player.platform is! NativePlayer) {
      return;
    }
    final settings = AppSettingsController.instance;
    final options = Map<String, String>.from(
      liveLatencyOptions(settings.mpvLiveLatencyMode.value, protocol),
    );
    final advanced = parseOptions(settings.mpvAdvancedOptions.value);
    final conf = parseConfFile(settings.importedMpvConfPath.value);
    for (final key in options.keys.toList()) {
      if (advanced.containsKey(key)) {
        options[key] = advanced[key]!;
      }
      if (conf.containsKey(key)) {
        options[key] = conf[key]!;
      }
    }
    for (final entry in options.entries) {
      try {
        await (player.platform as dynamic).setProperty(entry.key, entry.value);
      } catch (e) {
        Log.d("live latency option skipped: ${entry.key}=${entry.value} $e");
      }
    }
    Log.d(
      "live latency profile=${settings.mpvLiveLatencyMode.value} "
      "protocol=${protocol.label} options=${options.length}",
    );
  }

  static Map<String, String> _profileOptionsForPlatform(String profile) {
    if (profile == "balanced") {
      return Platform.isWindows
          ? desktopProfiles["balanced"]!
          : desktopProfiles["balancedDesktop"]!;
    }
    return desktopProfiles[profile] ?? desktopProfiles["balanced"]!;
  }

  static String? _desktopVideoControllerHwdec(MpvEffectiveOptions options) {
    final source = options.source["hwdec"];
    if (Platform.isWindows && source == "profile:balanced") {
      return null;
    }
    return options.options["hwdec"];
  }

  static String diagnosticsSummary() {
    final effectiveOptions = effectiveOptionsWithSource();
    final options = effectiveOptions.options;
    String value(String key) {
      final optionValue = options[key];
      final source = effectiveOptions.source[key];
      if (optionValue == null || optionValue.isEmpty) {
        return "default";
      }
      return source == null ? optionValue : "$optionValue($source)";
    }

    final ignored = effectiveOptions.ignored.entries
        .map((e) => "${e.key}=${e.value}")
        .join(" ");
    return "profile=${AppSettingsController.instance.mpvProfile.value}, "
        "hardwareDecode=${AppSettingsController.instance.hardwareDecode.value}, "
        "liveLatency=${AppSettingsController.instance.mpvLiveLatencyMode.value}, "
        "vo=${value("vo")}, hwdec=${value("hwdec")}, ao=${value("ao")}, "
        "mpvOptions=${options.length}"
        "${ignored.isEmpty ? "" : ", ignored[$ignored]"}";
  }

  static Map<String, String> parseOptions(String raw) {
    final result = <String, String>{};
    for (final rawLine in raw.split(RegExp(r"\r?\n"))) {
      final line = _stripComment(rawLine).trim();
      if (line.isEmpty) {
        continue;
      }
      final entry = _parseLine(line);
      if (entry != null) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static Map<String, String> parseConfFile(String path) {
    if (path.trim().isEmpty) {
      return const {};
    }
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return const {};
      }
      return parseOptions(file.readAsStringSync());
    } catch (e) {
      Log.d("read mpv.conf failed: $e");
      return const {};
    }
  }

  static Future<String?> importMpvConf() async {
    final picked = await FilePicker.platform.pickFiles(
      allowedExtensions: ["conf"],
      type: FileType.custom,
    );
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      return null;
    }
    final supportDir = await getApplicationSupportDirectory();
    final targetDir = Directory(p.join(supportDir.path, "mpv"));
    await targetDir.create(recursive: true);
    final targetPath = p.join(targetDir.path, "mpv.conf");
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  static MapEntry<String, String>? _parseLine(String line) {
    final normalized =
        line.startsWith("--") ? line.substring(2).trimLeft() : line;
    final equalIndex = normalized.indexOf("=");
    if (equalIndex > 0) {
      return MapEntry(
        normalized.substring(0, equalIndex).trim(),
        normalized.substring(equalIndex + 1).trim(),
      );
    }
    final match = RegExp(r"^([^\s]+)\s+(.+)$").firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return MapEntry(match.group(1)!.trim(), match.group(2)!.trim());
  }

  static String _stripComment(String line) {
    final index = line.indexOf("#");
    if (index < 0) {
      return line;
    }
    return line.substring(0, index);
  }
}

class MpvEffectiveOptions {
  final Map<String, String> options;
  final Map<String, String> source;

  /// `ao`/`vo`/`hwdec` values dropped because this platform's libmpv lacks them.
  /// Keys still resolve in [source], so callers can report where each came from.
  final Map<String, String> ignored;

  const MpvEffectiveOptions(
    this.options,
    this.source, {
    this.ignored = const {},
  });
}

class MpvPlatformFilterResult {
  final Map<String, String> options;
  final Map<String, String> ignored;

  const MpvPlatformFilterResult(this.options, this.ignored);
}
