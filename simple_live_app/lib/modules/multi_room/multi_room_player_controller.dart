import 'dart:async';
import 'dart:ui';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class MultiRoomPlayerController extends GetxController {
  final MultiRoomItem item;

  MultiRoomPlayerController(this.item);

  late final Player player = Player(
    configuration: PlayerConfiguration(
      title: item.userName,
      logLevel: AppSettingsController.instance.logEnable.value
          ? MPVLogLevel.info
          : MPVLogLevel.error,
    ),
  );
  late final VideoController videoController = VideoController(
    player,
    configuration: MpvOptionsService.videoControllerConfiguration(),
  );

  final detail = Rx<LiveRoomDetail?>(null);
  final loading = true.obs;
  final liveStatus = false.obs;
  final errorText = "".obs;
  final muted = true.obs;
  final qualityInfo = "".obs;
  final lineInfo = "".obs;

  /// 本格弹幕开关。多开只收不发，不提供发送入口。
  final showDanmaku = true.obs;

  /// 每格一条独立的弹幕长连接。
  late LiveDanmaku liveDanmaku = item.site.liveSite.getDanmaku();

  /// 弹幕渲染层的控制器，由 `DanmakuScreen` 在 build 时回传。
  DanmakuController? danmakuController;

  /// 聊天区竖向弹幕消息列表（独立于画面弹幕，不受弹幕开关控制）。
  final chatMessages = <LiveMessage>[].obs;
  static const int _maxChatMessages = 200;

  List<LivePlayQuality> _qualities = const [];
  List<String> _playUrls = const [];
  Map<String, String>? _playHeaders;
  int _qualityIndex = -1;
  int _lineIndex = 0;
  bool _disposed = false;

  String get title {
    final roomTitle = detail.value?.title.trim();
    if (roomTitle != null && roomTitle.isNotEmpty) {
      return roomTitle;
    }
    return item.userName;
  }

  @override
  void onInit() {
    super.onInit();
    unawaited(MpvOptionsService.applyToPlayer(player));
    unawaited(load());
  }

  Future<void> load() async {
    loading.value = true;
    errorText.value = "";
    liveStatus.value = false;
    try {
      await player.stop();
      // 重新加载前断开旧连接，避免刷新后同一格挂着两条长连接。
      await _stopDanmaku();
      chatMessages.clear();
      final roomDetail =
          await item.site.liveSite.getRoomDetail(roomId: item.roomId);
      if (_disposed) {
        return;
      }
      detail.value = roomDetail;
      liveStatus.value = roomDetail.status || roomDetail.isRecord;
      if (!liveStatus.value) {
        return;
      }
      await _loadQualities(roomDetail);
      await _loadPlayUrls(roomDetail);
      await _openCurrentUrl();
      _startDanmaku(roomDetail);
    } catch (e) {
      Log.e(
        "多开直播间加载失败：${item.site.id}/${item.roomId} $e",
        StackTrace.current,
      );
      errorText.value = e.toString();
    } finally {
      if (!_disposed) {
        loading.value = false;
      }
    }
  }

  Future<void> _loadQualities(LiveRoomDetail roomDetail) async {
    _qualities = await item.site.liveSite.getPlayQualites(detail: roomDetail);
    if (_qualities.isEmpty) {
      throw Exception("无法读取播放清晰度");
    }
    final qualityLevel = AppSettingsController.instance.qualityLevel.value;
    if (qualityLevel == 2) {
      _qualityIndex = 0;
    } else if (qualityLevel == 0) {
      _qualityIndex = _qualities.length - 1;
    } else {
      _qualityIndex = (_qualities.length / 2).floor();
    }
    qualityInfo.value = _qualities[_qualityIndex].quality;
  }

  Future<void> _loadPlayUrls(LiveRoomDetail roomDetail) async {
    final playUrl = await item.site.liveSite.getPlayUrls(
      detail: roomDetail,
      quality: _qualities[_qualityIndex],
    );
    if (playUrl.urls.isEmpty) {
      throw Exception("无法读取播放地址");
    }
    _playUrls = playUrl.urls;
    _playHeaders = playUrl.headers;
    _lineIndex = 0;
    lineInfo.value = "线路${_lineIndex + 1}";
  }

  Future<void> _openCurrentUrl() async {
    var url = _playUrls[_lineIndex];
    if (AppSettingsController.instance.playerForceHttps.value) {
      url = url.replaceAll("http://", "https://");
    }
    await player.open(Media(url, httpHeaders: _playHeaders));
    await player.setVolume(
        muted.value ? 0 : AppSettingsController.instance.playerVolume.value);
  }

  /// 由 `DanmakuScreen` 创建后回传渲染控制器。
  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
  }

  void _startDanmaku(LiveRoomDetail roomDetail) {
    liveDanmaku.onMessage = _onDanmakuMessage;
    liveDanmaku.onClose = (msg) {
      Log.d("多开弹幕关闭：${item.site.id}/${item.roomId} $msg");
    };
    liveDanmaku.onReady = () {
      Log.d("多开弹幕已连接：${item.site.id}/${item.roomId}");
    };
    unawaited(
      liveDanmaku.start(roomDetail.danmakuData).catchError((Object e) {
        // 弹幕连不上不影响看画面，只记日志。
        Log.e("多开弹幕启动失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
      }),
    );
  }

  void _onDanmakuMessage(LiveMessage msg) {
    if (_disposed || msg.type != LiveMessageType.chat || !liveStatus.value) {
      return;
    }
    // 聊天区消息始终记录（不受弹幕开关控制）。
    chatMessages.add(msg);
    while (chatMessages.length > _maxChatMessages) {
      chatMessages.removeAt(0);
    }
    // 画面弹幕由开关控制。
    if (!showDanmaku.value) return;
    final settings = AppSettingsController.instance;
    danmakuController?.addDanmaku(
      DanmakuContentItem(
        msg.message,
        color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b),
        imageUrls: settings.danmuRenderEmoji.value ? msg.imageUrls : null,
      ),
    );
  }

  Future<void> _stopDanmaku() async {
    liveDanmaku.onMessage = null;
    liveDanmaku.onClose = null;
    liveDanmaku.onReady = null;
    try {
      await liveDanmaku.stop();
    } catch (e) {
      Log.d("多开弹幕停止异常：${item.site.id}/${item.roomId} $e");
    }
    danmakuController?.clear();
    // stop() 后的实例不可复用，重新取一个干净的。
    liveDanmaku = item.site.liveSite.getDanmaku();
  }

  void toggleDanmaku() {
    showDanmaku.value = !showDanmaku.value;
    if (!showDanmaku.value) {
      danmakuController?.clear();
    }
  }

  Future<void> refreshRoom() async {
    await load();
    SmartDialog.showToast("已刷新 ${item.userName}");
  }

  Future<void> toggleMute() async {
    muted.value = !muted.value;
    await player.setVolume(
      muted.value ? 0 : AppSettingsController.instance.playerVolume.value,
    );
  }

  @override
  void onClose() {
    _disposed = true;
    // 必须断开弹幕长连接，否则移除格子后连接和心跳会泄漏。
    liveDanmaku.onMessage = null;
    liveDanmaku.onClose = null;
    liveDanmaku.onReady = null;
    unawaited(liveDanmaku.stop());
    danmakuController = null;
    unawaited(player.stop());
    unawaited(player.dispose());
    super.onClose();
  }
}
