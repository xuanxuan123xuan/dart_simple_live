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
import 'package:simple_live_app/services/network_diagnose_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class MultiRoomPlayerController extends GetxController {
  final MultiRoomItem item;
  final void Function()? onPlayerOpened;

  MultiRoomPlayerController(
    this.item, {
    this.onPlayerOpened,
    double? initialVolume,
    bool? initialShowDanmaku,
    int? initialQualityIndex,
    int? initialLineIndex,
  }) {
    if (initialVolume != null) {
      volume.value = initialVolume.clamp(0, 100).toDouble();
    }
    if (initialShowDanmaku != null) {
      showDanmaku.value = initialShowDanmaku;
    }
    _restoreQualityIndex = initialQualityIndex;
    _restoreLineIndex = initialLineIndex;
  }

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

  /// 状态徽标：空=正常；"重试中…"=流错误重试；"弹幕重连…"=弹幕重连。
  final streamStatus = "".obs;

  // --- 流错误自动重试 ---
  int _streamErrorRetryCount = 0;
  DateTime? _lastStreamErrorTime;
  static const int _maxStreamRetry = 3;

  // --- 弹幕断线自动重连 ---
  int _danmakuReconnectCount = 0;
  Timer? _danmakuReconnectTimer;
  bool _danmakuManuallyStopped = false;
  static const int _maxDanmakuReconnect = 5;

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
  bool _playbackDesired = false;
  bool _danmakuActive = false;
  Future<void>? _danmakuStopFuture;
  Future<void> _operationChain = Future<void>.value();
  Future<void>? _loadFuture;

  /// 上次会话的画质/线路索引（布局恢复用，load 后应用）。
  int? _restoreQualityIndex;
  int? _restoreLineIndex;

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
    // 流错误自动重试（对齐单直播间行为）。
    player.stream.error.listen((event) {
      if (_disposed || !liveStatus.value) return;
      if (_isStreamError(event)) {
        unawaited(_handleStreamError(event));
      }
    });
    unawaited(load());
  }

  static bool _isStreamError(String error) {
    return error.contains('mbedtls_ssl_read') ||
        error.contains('Packet corrupt') ||
        error.contains('Packet corupt') ||
        error.contains('tls:') ||
        error.contains('Invalid NAL unit') ||
        error.contains('missing picture');
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operationChain.then((_) async {
      if (_disposed) return;
      await operation();
    });
    _operationChain = result.catchError((Object _) {});
    return result;
  }

  /// 流错误自动重试：最多 3 次，每次重开当前线路。
  Future<void> _handleStreamError(String error) {
    return _enqueue(() => _handleStreamErrorInternal(error));
  }

  Future<void> _handleStreamErrorInternal(String error) async {
    final now = DateTime.now();
    if (_lastStreamErrorTime != null &&
        now.difference(_lastStreamErrorTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastStreamErrorTime = now;
    if (_streamErrorRetryCount >= _maxStreamRetry) {
      Log.e("多开流错误重试次数已达上限：${item.site.id}/${item.roomId} $error",
          StackTrace.current);
      streamStatus.value = "";
      errorText.value = "播放中断，请手动刷新";
      return;
    }
    _streamErrorRetryCount += 1;
    streamStatus.value = "重试中($_streamErrorRetryCount/$_maxStreamRetry)…";
    Log.w("多开检测到流错误，自动重试：${item.site.id}/${item.roomId} $error", false);
    await Future.delayed(const Duration(seconds: 1));
    if (_disposed) return;
    try {
      await player.pause();
      await Future.delayed(const Duration(milliseconds: 200));
      await _openCurrentUrl();
      streamStatus.value = "";
    } catch (e) {
      Log.e("多开重启解码器失败：${item.site.id}/${item.roomId} $e",
          StackTrace.current);
      streamStatus.value = "";
    }
  }

  Future<void> load() {
    final activeLoad = _loadFuture;
    if (activeLoad != null) return activeLoad;
    final result = _enqueue(_loadInternal);
    _loadFuture = result;
    void clearActiveLoad() {
      if (identical(_loadFuture, result)) _loadFuture = null;
    }

    unawaited(result.then<void>(
      (_) => clearActiveLoad(),
      onError: (Object _, StackTrace __) => clearActiveLoad(),
    ));
    return result;
  }

  Future<void> _loadInternal() async {
    loading.value = true;
    errorText.value = "";
    liveStatus.value = false;
    _playbackDesired = false;
    try {
      await player.stop();
      if (_disposed) return;
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
      if (_disposed) return;
      await _loadPlayUrls(roomDetail);
      if (_disposed) return;
      await _openCurrentUrl();
      if (_disposed) return;
      unawaited(_startDanmaku(roomDetail));
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
    // 优先恢复上次会话的画质。
    final restore = _restoreQualityIndex;
    _restoreQualityIndex = null;
    if (restore != null && restore >= 0 && restore < _qualities.length) {
      _qualityIndex = restore;
      qualityInfo.value = _qualities[_qualityIndex].quality;
      return;
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
    // 优先恢复上次会话的线路；否则自动测速选最快的。
    final restore = _restoreLineIndex;
    _restoreLineIndex = null;
    if (restore != null && restore >= 0 && restore < _playUrls.length) {
      _lineIndex = restore;
    } else if (AppSettingsController.instance.autoSelectFastestLine.value &&
        _playUrls.length > 1) {
      _lineIndex = await NetworkDiagnoseService.findFastestLine(_playUrls);
    } else {
      _lineIndex = 0;
    }
    lineInfo.value = "线路${_lineIndex + 1}";
  }

  Future<void> _openCurrentUrl() async {
    if (_disposed || _playUrls.isEmpty) return;
    var url = _playUrls[_lineIndex];
    if (AppSettingsController.instance.playerForceHttps.value) {
      url = url.replaceAll("http://", "https://");
    }
    _playbackDesired = true;
    await player.open(Media(url, httpHeaders: _playHeaders));
    if (_disposed) return;
    await player.setVolume(muted.value ? 0 : volume.value);
    // iOS 上多个 libmpv Player 共享 audio session。任意一格重新 open
    // 都可能中断其他格，由页面级控制器统一恢复仍应播放的播放器。
    if (!_disposed) {
      onPlayerOpened?.call();
    }
  }

  /// iOS 上其他 Player.open() 可能抢占共享音频会话。这里依据业务意图恢复，
  /// 不读取可能尚未刷新的 player.state.playing。
  Future<void> ensurePlaying() {
    return _enqueue(() async {
      if (_disposed || !_playbackDesired || !liveStatus.value) return;
      await player.play();
    });
  }

  /// 切换本格清晰度（独立于其他格）。
  Future<void> changeQuality(int index) {
    return _enqueue(() async {
      if (index < 0 || index >= _qualities.length || index == _qualityIndex) {
        return;
      }
      _qualityIndex = index;
      qualityInfo.value = _qualities[index].quality;
      final roomDetail = detail.value;
      if (roomDetail == null) return;
      try {
        await _loadPlayUrls(roomDetail);
        if (_disposed) return;
        await _openCurrentUrl();
      } catch (e) {
        Log.e("多开切换清晰度失败：${item.site.id}/${item.roomId} $e",
            StackTrace.current);
        errorText.value = e.toString();
      }
    });
  }

  /// 切换本格线路（独立于其他格）。
  Future<void> changeLine(int index) {
    return _enqueue(() async {
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
    });
  }

  /// 低内存降级：暂停本格弹幕连接（降级状态由调用方记录）。
  Future<void> degradeDanmaku() async {
    await _stopDanmaku();
    danmakuController?.clear();
  }

  /// 低内存恢复：重建本格弹幕连接。
  Future<void> restoreDanmaku() async {
    final roomDetail = detail.value;
    if (_disposed || _danmakuActive || roomDetail == null || !liveStatus.value) {
      return;
    }
    await _startDanmaku(roomDetail);
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

  Future<void> _startDanmaku(LiveRoomDetail roomDetail) async {
    final pendingStop = _danmakuStopFuture;
    if (pendingStop != null) {
      await pendingStop;
    }
    if (_disposed || _danmakuActive) return;
    _danmakuActive = true;
    _danmakuManuallyStopped = false;
    liveDanmaku.onMessage = _onDanmakuMessage;
    liveDanmaku.onClose = (msg) {
      _danmakuActive = false;
      Log.d("多开弹幕关闭：${item.site.id}/${item.roomId} $msg");
      _addSysMessage(msg);
      _scheduleDanmakuReconnect();
    };
    liveDanmaku.onReady = () {
      Log.d("多开弹幕已连接：${item.site.id}/${item.roomId}");
      _danmakuReconnectCount = 0;
      _danmakuReconnectTimer?.cancel();
      streamStatus.value = "";
    };
    try {
      await liveDanmaku.start(roomDetail.danmakuData);
    } catch (e) {
      _danmakuActive = false;
      if (!_disposed && !_danmakuManuallyStopped) {
        // 弹幕连不上不影响看画面，只记日志。
        Log.e("多开弹幕启动失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
        _addSysMessage("弹幕连接失败");
      }
    }
  }

  /// 弹幕意外断开后指数退避自动重连（3s/6s/12s…最多 5 次）。
  void _scheduleDanmakuReconnect() {
    if (_disposed || _danmakuManuallyStopped || !liveStatus.value) {
      return;
    }
    if (_danmakuReconnectCount >= _maxDanmakuReconnect) {
      streamStatus.value = "";
      return;
    }
    _danmakuReconnectCount += 1;
    streamStatus.value = "弹幕重连($_danmakuReconnectCount/$_maxDanmakuReconnect)…";
    final delay = Duration(seconds: 3 * (1 << (_danmakuReconnectCount - 1)));
    _danmakuReconnectTimer?.cancel();
    _danmakuReconnectTimer = Timer(delay, () {
      if (_disposed || _danmakuManuallyStopped || !liveStatus.value) {
        return;
      }
      final roomDetail = detail.value;
      if (roomDetail != null) {
        unawaited(_startDanmaku(roomDetail));
      }
    });
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

  Future<void> _stopDanmaku() {
    final activeStop = _danmakuStopFuture;
    if (activeStop != null) return activeStop;
    late final Future<void> trackedStop;
    trackedStop = _stopDanmakuInternal().whenComplete(() {
      if (identical(_danmakuStopFuture, trackedStop)) {
        _danmakuStopFuture = null;
      }
    });
    _danmakuStopFuture = trackedStop;
    return trackedStop;
  }

  Future<void> _stopDanmakuInternal() async {
    _danmakuManuallyStopped = true;
    _danmakuActive = false;
    _danmakuReconnectTimer?.cancel();
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
    _playbackDesired = false;
    _danmakuActive = false;
    // 必须断开弹幕长连接，否则移除格子后连接和心跳会泄漏。
    liveDanmaku.onMessage = null;
    liveDanmaku.onClose = null;
    liveDanmaku.onReady = null;
    _danmakuReconnectTimer?.cancel();
    unawaited(liveDanmaku.stop());
    danmakuController = null;
    // 等当前串行的 open/load 收尾后再释放 Player，避免异步回调操作已释放实例。
    unawaited(_operationChain.whenComplete(() async {
      await player.stop();
      await player.dispose();
    }));
    super.onClose();
  }
}
