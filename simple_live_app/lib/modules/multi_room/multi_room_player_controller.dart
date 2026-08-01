import 'dart:async';
import 'dart:ui';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
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

  /// 本格独立音量（0-100），互不影响。
  final volume = 100.0.obs;

  /// 每格一条独立的弹幕长连接。
  late LiveDanmaku liveDanmaku = item.site.liveSite.getDanmaku();

  /// 弹幕渲染层的控制器，由 `DanmakuScreen` 在 build 时回传。
  DanmakuController? danmakuController;

  /// 聊天区竖向弹幕消息列表（独立于画面弹幕，不受弹幕开关控制）。
  final chatMessages = <LiveMessage>[].obs;
  static const int _maxChatMessages = 200;

  /// 重复弹幕去重（对齐正常直播间行为）。
  final List<String> _recentDanmuFingerprints = [];
  static const int _recentDanmuWindow = 10;

  List<LivePlayQuality> _qualities = const [];
  List<String> _playUrls = const [];
  Map<String, String>? _playHeaders;
  int _qualityIndex = -1;
  int _lineIndex = 0;
  bool _disposed = false;

  /// 当前格子的可选清晰度列表。
  List<LivePlayQuality> get qualities => _qualities;

  /// 当前清晰度索引。
  int get qualityIndex => _qualityIndex;

  /// 当前线路列表。
  List<String> get playUrls => _playUrls;

  /// 当前线路索引。
  int get lineIndex => _lineIndex;

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
      _recentDanmuFingerprints.clear();
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
    await player.setVolume(muted.value ? 0 : volume.value);
  }

  /// 切换本格清晰度（独立于其他格）。
  Future<void> changeQuality(int index) async {
    if (index < 0 || index >= _qualities.length || index == _qualityIndex) {
      return;
    }
    _qualityIndex = index;
    qualityInfo.value = _qualities[index].quality;
    final roomDetail = detail.value;
    if (roomDetail == null) return;
    try {
      await _loadPlayUrls(roomDetail);
      await _openCurrentUrl();
    } catch (e) {
      Log.e("多开切换清晰度失败：${item.site.id}/${item.roomId} $e",
          StackTrace.current);
      errorText.value = e.toString();
    }
  }

  /// 切换本格线路（独立于其他格）。
  Future<void> changeLine(int index) async {
    if (index < 0 || index >= _playUrls.length || index == _lineIndex) {
      return;
    }
    _lineIndex = index;
    lineInfo.value = "线路${_lineIndex + 1}";
    try {
      await _openCurrentUrl();
    } catch (e) {
      Log.e("多开切换线路失败：${item.site.id}/${item.roomId} $e",
          StackTrace.current);
      errorText.value = e.toString();
    }
  }

  /// 低内存降级：暂停本格弹幕连接（降级状态由调用方记录）。
  Future<void> degradeDanmaku() async {
    await _stopDanmaku();
    danmakuController?.clear();
  }

  /// 低内存恢复：重建本格弹幕连接。
  Future<void> restoreDanmaku() async {
    final roomDetail = detail.value;
    if (roomDetail == null || !liveStatus.value) {
      return;
    }
    _startDanmaku(roomDetail);
  }

  /// 低内存降级：切到最低清晰度（若当前不是最低）。
  Future<void> degradeQuality() async {
    if (_qualities.length <= 1 || _qualityIndex == _qualities.length - 1) {
      return;
    }
    await changeQuality(_qualities.length - 1);
  }

  /// 由 `DanmakuScreen` 创建后回传渲染控制器。
  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
  }

  void _startDanmaku(LiveRoomDetail roomDetail) {
    liveDanmaku.onMessage = _onDanmakuMessage;
    liveDanmaku.onClose = (msg) {
      Log.d("多开弹幕关闭：${item.site.id}/${item.roomId} $msg");
      _addSysMessage(msg);
    };
    liveDanmaku.onReady = () {
      Log.d("多开弹幕已连接：${item.site.id}/${item.roomId}");
    };
    unawaited(
      liveDanmaku.start(roomDetail.danmakuData).catchError((Object e) {
        // 弹幕连不上不影响看画面，只记日志。
        Log.e("多开弹幕启动失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
        _addSysMessage("弹幕连接失败");
      }),
    );
  }

  /// 追加一条系统消息到聊天区（对齐正常直播间 LiveSysMessage 样式）。
  void _addSysMessage(String msg) {
    if (_disposed || msg.isEmpty) return;
    chatMessages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    );
    while (chatMessages.length > _maxChatMessages) {
      chatMessages.removeAt(0);
    }
  }

  /// 用户/关键词/重复弹幕过滤（对齐正常直播间行为）。
  bool _shouldFilterDanmu(LiveMessage msg) {
    final settings = AppSettingsController.instance;
    if (settings.shouldShieldUser(msg.userName, siteId: item.site.id)) {
      Log.d("多开过滤被屏蔽用户: ${msg.userName}");
      return true;
    }
    if (settings.danmuShieldEnable.value &&
        settings.danmuKeywordShieldEnable.value) {
      for (final keyword in settings.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          final removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            Log.d("正则屏蔽词 $keyword 无法编译，已跳过");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("多开命中屏蔽词 $keyword");
          return true;
        }
      }
    }
    if (settings.danmuDedupeEnable.value) {
      final fingerprint = "${msg.userName}|${msg.message}";
      if (_recentDanmuFingerprints.contains(fingerprint)) {
        return true;
      }
      _recentDanmuFingerprints.add(fingerprint);
      if (_recentDanmuFingerprints.length > _recentDanmuWindow) {
        _recentDanmuFingerprints.removeAt(0);
      }
    }
    return false;
  }

  void _onDanmakuMessage(LiveMessage msg) {
    if (_disposed || msg.type != LiveMessageType.chat || !liveStatus.value) {
      return;
    }
    // 对齐正常直播间：屏蔽/去重过滤后仍记录到聊天区（不受弹幕开关控制）。
    if (_shouldFilterDanmu(msg)) {
      return;
    }
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
    await player.setVolume(muted.value ? 0 : volume.value);
  }

  /// 设置本格音量（0-100）并取消静音。
  Future<void> setVolume(double value) async {
    volume.value = value.clamp(0, 100).toDouble();
    if (muted.value && value > 0) {
      muted.value = false;
    }
    if (muted.value) {
      await player.setVolume(0);
    } else {
      await player.setVolume(volume.value);
    }
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
