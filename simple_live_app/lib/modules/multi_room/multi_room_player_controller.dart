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
import 'package:simple_live_app/modules/multi_room/multi_room_adaptive_quality.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/player_mutation_queue.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:simple_live_app/services/network_diagnose_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class MultiRoomRefreshResult {
  const MultiRoomRefreshResult({
    required this.roomKey,
    required this.success,
    this.error,
  });

  final String roomKey;
  final bool success;
  final String? error;
}

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
    bool initialPaused = false,
    PlayerMutationQueue? mutationQueue,
  })  : _mutationQueue = mutationQueue ?? PlayerMutationQueue(),
        _ownsMutationQueue = mutationQueue == null {
    if (initialVolume != null) {
      volume.value = initialVolume.clamp(0, 100).toDouble();
    }
    if (initialShowDanmaku != null) {
      showDanmaku.value = initialShowDanmaku;
    }
    _restoreQualityIndex = initialQualityIndex;
    _restoreLineIndex = initialLineIndex;
    paused.value = initialPaused;
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
  final paused = false.obs;
  final qualityLocked = false.obs;
  final qualityInfo = "".obs;
  final lineInfo = "".obs;

  /// 本格弹幕开关。多开只收不发，不提供发送入口。
  final showDanmaku = true.obs;

  /// 本格独立音量（0-100），互不影响。
  final volume = 100.0.obs;

  /// 本格操作按钮（右下角）是否显示：点格子呼出，5 秒不操作自动隐藏。
  final showTileControls = true.obs;
  Timer? _tileControlsTimer;

  /// 点击本格画面：呼出/收起本格按钮，并重置 5 秒自动隐藏计时。
  void toggleTileControls() {
    showTileControls.value = !showTileControls.value;
    _tileControlsTimer?.cancel();
    _tileControlsTimer = null;
    if (showTileControls.value) {
      _tileControlsTimer = Timer(const Duration(seconds: 5), () {
        if (!_disposed) {
          showTileControls.value = false;
        }
      });
    }
  }

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
  bool _playerDisposed = false;
  bool _routeTransitionClosed = false;
  Future<void>? _routeTransitionFuture;
  bool _playbackDesired = false;
  bool _danmakuActive = false;
  Future<void>? _danmakuStopFuture;
  Future<void> _operationChain = Future<void>.value();
  Future<void>? _loadFuture;
  final PlayerMutationQueue _mutationQueue;
  final bool _ownsMutationQueue;
  StreamSubscription<bool>? _bufferingSubscription;
  bool _isBuffering = false;
  int _bufferingCount = 0;
  Duration _bufferingDuration = Duration.zero;
  DateTime? _bufferingSince;
  DateTime? _lastOpenedAt;
  int? _userQualityIndex;
  int? _memoryPressureQualityIndex;

  /// 上次会话的画质/线路索引（布局恢复用，load 后应用）。
  int? _restoreQualityIndex;
  int? _restoreLineIndex;

  /// 当前格子的可选清晰度列表。
  List<LivePlayQuality> get qualities => _qualities;

  /// 当前清晰度索引。
  int get qualityIndex => _qualityIndex;

  int? get userQualityIndex => _userQualityIndex;

  bool get isMemoryQualityDegraded => _memoryPressureQualityIndex != null;

  bool get playbackDesired => _playbackDesired && !paused.value;

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
      if (_disposed || paused.value || !liveStatus.value) return;
      if (_isStreamError(event)) {
        unawaited(_handleStreamError(event));
      }
    });
    _bufferingSubscription =
        player.stream.buffering.listen(_onBufferingChanged);
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
    final result = _mutationQueue.run<void>(() async {
      if (_disposed || _routeTransitionClosed) return;
      await operation();
    });
    _operationChain = result.catchError((Object _) {});
    return result;
  }

  void _onBufferingChanged(bool value) {
    if (_disposed || paused.value) return;
    final now = DateTime.now();
    if (value && !_isBuffering) {
      _isBuffering = true;
      _bufferingCount += 1;
      _bufferingSince = now;
    } else if (!value && _isBuffering) {
      _finishBuffering(now);
    }
  }

  void _finishBuffering(DateTime now) {
    final since = _bufferingSince;
    if (since != null) {
      _bufferingDuration += now.difference(since);
    }
    _bufferingSince = null;
    _isBuffering = false;
  }

  MultiRoomPlaybackTelemetry telemetrySnapshot({
    DateTime? sampledAt,
    double? bandwidthBytesPerSecond,
    int? width,
    int? height,
    double? framesPerSecond,
    bool isPrimary = false,
    bool isFocused = false,
    bool isChatTarget = false,
  }) {
    final now = sampledAt ?? DateTime.now();
    final ongoing = _isBuffering && _bufferingSince != null
        ? now.difference(_bufferingSince!)
        : Duration.zero;
    return MultiRoomPlaybackTelemetry(
      roomKey: item.key,
      sampledAt: now,
      paused: paused.value,
      isBuffering: _isBuffering,
      bufferingCount: _bufferingCount,
      bufferingDuration: _bufferingDuration + ongoing,
      qualityIndex: _qualityIndex,
      qualityCount: _qualities.length,
      userTargetQualityIndex: _userQualityIndex,
      // Keep this null when the backend cannot expose libmpv's raw-input-rate;
      // unknown bandwidth must not be interpreted as zero.
      bandwidthBytesPerSecond: bandwidthBytesPerSecond,
      width: width,
      height: height,
      framesPerSecond: framesPerSecond,
      lastOpenedAt: _lastOpenedAt,
      isQualityLocked: qualityLocked.value,
      isPrimary: isPrimary,
      isFocused: isFocused,
      isChatTarget: isChatTarget,
    );
  }

  /// Samples properties exposed only by NativePlayer/libmpv. Web and other
  /// backends safely fall back to the regular snapshot with unknown values.
  Future<MultiRoomPlaybackTelemetry> sampleTelemetry({
    DateTime? sampledAt,
    bool isPrimary = false,
    bool isFocused = false,
    bool isChatTarget = false,
  }) async {
    final now = sampledAt ?? DateTime.now();
    final fallback = telemetrySnapshot(
      sampledAt: now,
      isPrimary: isPrimary,
      isFocused: isFocused,
      isChatTarget: isChatTarget,
    );
    if (_disposed || _playerDisposed) return fallback;
    final platform = player.platform;
    if (platform is! NativePlayer) return fallback;

    final raw = <String, String?>{};
    for (final property in const [
      mpvCacheSpeedProperty,
      mpvVideoWidthProperty,
      mpvVideoHeightProperty,
      mpvEstimatedFpsProperty,
    ]) {
      raw[property] = await _readNativeProperty(platform, property);
    }
    final native = parseMpvTelemetryProperties(raw);
    return telemetrySnapshot(
      sampledAt: now,
      bandwidthBytesPerSecond: native.bandwidthBytesPerSecond,
      width: native.width,
      height: native.height,
      framesPerSecond: native.framesPerSecond,
      isPrimary: isPrimary,
      isFocused: isFocused,
      isChatTarget: isChatTarget,
    );
  }

  Future<String?> _readNativeProperty(
    NativePlayer nativePlayer,
    String property,
  ) async {
    try {
      // NativePlayer's web stub intentionally omits getProperty. The runtime
      // type check above plus a dynamic call keeps web compilation safe.
      final dynamic native = nativePlayer;
      final dynamic value = await native.getProperty(property);
      return value is String ? value : value?.toString();
    } catch (_) {
      return null;
    }
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
    if (_disposed || paused.value) return;
    try {
      await player.pause();
      await Future.delayed(const Duration(milliseconds: 200));
      await _openCurrentUrl();
      streamStatus.value = "";
    } catch (e) {
      Log.e("多开重启解码器失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
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
    if (_qualityIndex >= 0) {
      _restoreQualityIndex = _qualityIndex;
    }
    if (_lineIndex >= 0) {
      _restoreLineIndex = _lineIndex;
    }
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
      _userQualityIndex ??= _qualityIndex;
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
    _userQualityIndex ??= _qualityIndex;
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
    if (_disposed || _routeTransitionClosed || _playUrls.isEmpty) return;
    var url = _playUrls[_lineIndex];
    if (AppSettingsController.instance.playerForceHttps.value) {
      url = url.replaceAll("http://", "https://");
    }
    _playbackDesired = true;
    _lastOpenedAt = DateTime.now();
    await player.open(
      Media(url, httpHeaders: _playHeaders),
      play: !paused.value,
    );
    if (_disposed) return;
    await player.setVolume(muted.value ? 0 : volume.value);
    if (paused.value) {
      await player.pause();
    }
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
      if (_disposed || paused.value || !_playbackDesired || !liveStatus.value) {
        return;
      }
      await player.play();
    });
  }

  /// Applies the user's explicit playback intent. Reopens and lifecycle
  /// recovery never override this state.
  Future<void> setPaused(bool value) {
    if (paused.value == value) return Future<void>.value();
    paused.value = value;
    if (value && _isBuffering) {
      _finishBuffering(DateTime.now());
    }
    return _enqueue(() async {
      if (value) {
        await player.pause();
      } else if (_playbackDesired && liveStatus.value) {
        await player.play();
      }
    });
  }

  Future<void> togglePaused() => setPaused(!paused.value);

  /// 切换本格清晰度（独立于其他格）。
  Future<void> changeQuality(
    int index, {
    bool userInitiated = true,
  }) {
    if (index < 0 || index >= _qualities.length) {
      return Future<void>.value();
    }
    if (userInitiated) {
      _userQualityIndex = index;
      qualityLocked.value = true;
      if (_memoryPressureQualityIndex != null) {
        // Remember the newest user target, but retain the emergency override.
        _memoryPressureQualityIndex = index;
        return Future<void>.value();
      }
    }
    return _enqueue(() async {
      if (index == _qualityIndex) {
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
        Log.e(
            "多开切换清晰度失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
        errorText.value = e.toString();
      }
    });
  }

  Future<void> changeQualityAutomatically(int index) {
    if (qualityLocked.value || _memoryPressureQualityIndex != null) {
      return Future<void>.value();
    }
    return changeQuality(index, userInitiated: false);
  }

  void useAutomaticQuality() {
    qualityLocked.value = false;
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
        Log.e("多开切换线路失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
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
    if (_disposed ||
        _danmakuActive ||
        roomDetail == null ||
        !liveStatus.value) {
      return;
    }
    await _startDanmaku(roomDetail);
  }

  /// 低内存降级：切到最低清晰度（若当前不是最低）。
  Future<void> degradeQuality() async {
    if (_qualities.length <= 1 || _qualityIndex == _qualities.length - 1) {
      return;
    }
    _memoryPressureQualityIndex ??= _userQualityIndex ?? _qualityIndex;
    await changeQuality(
      _qualities.length - 1,
      userInitiated: false,
    );
  }

  /// Restores the most recent user target after a temporary memory override.
  Future<void> restoreQualityAfterMemoryPressure() async {
    final target = _memoryPressureQualityIndex;
    _memoryPressureQualityIndex = null;
    if (target == null || target < 0 || target >= _qualities.length) return;
    await changeQuality(target, userInitiated: false);
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

  Future<MultiRoomRefreshResult> refreshRoom({bool showToast = true}) async {
    await load();
    final error = errorText.value.trim();
    final result = MultiRoomRefreshResult(
      roomKey: item.key,
      success: error.isEmpty,
      error: error.isEmpty ? null : error,
    );
    if (showToast) {
      SmartDialog.showToast(
        result.success ? "已刷新 ${item.userName}" : "刷新失败 ${item.userName}",
      );
    }
    return result;
  }

  Future<void> toggleMute() async {
    await setMuted(!muted.value);
  }

  Future<void> setMuted(bool value) async {
    if (muted.value == value) return;
    muted.value = value;
    await player.setVolume(muted.value ? 0 : volume.value);
  }

  /// 设置本格音量（0-100）。静音归属只由 [setMuted] 控制。
  Future<void> setVolume(double value) async {
    volume.value = value.clamp(0, 100).toDouble();
    if (muted.value) {
      await player.setVolume(0);
    } else {
      await player.setVolume(volume.value);
    }
  }

  /// Stops native resources before the focused room opens as a single room.
  /// Normal controller disposal remains safe after this method completes.
  Future<void> closeForRouteTransition() async {
    final activeTransition = _routeTransitionFuture;
    if (activeTransition != null) return activeTransition;
    if (_disposed || _playerDisposed) return;
    late final Future<void> transition;
    transition = _mutationQueue.run<void>(() async {
      if (_playerDisposed) return;
      _routeTransitionClosed = true;
      _playbackDesired = false;
      if (_isBuffering) _finishBuffering(DateTime.now());
      try {
        await _stopDanmaku();
        await player.stop();
        await player.dispose();
        _playerDisposed = true;
      } catch (_) {
        _routeTransitionClosed = false;
        rethrow;
      }
    });
    _routeTransitionFuture = transition;
    _operationChain = transition.catchError((Object _) {});
    await transition;
  }

  @override
  void onClose() {
    _disposed = true;
    _playbackDesired = false;
    if (_isBuffering) _finishBuffering(DateTime.now());
    unawaited(_bufferingSubscription?.cancel());
    _bufferingSubscription = null;
    _danmakuActive = false;
    // 必须断开弹幕长连接，否则移除格子后连接和心跳会泄漏。
    liveDanmaku.onMessage = null;
    liveDanmaku.onClose = null;
    liveDanmaku.onReady = null;
    _danmakuReconnectTimer?.cancel();
    _tileControlsTimer?.cancel();
    unawaited(liveDanmaku.stop());
    danmakuController = null;
    // 等当前串行的 open/load 收尾后再释放 Player，避免异步回调操作已释放实例。
    unawaited(_operationChain.whenComplete(() async {
      if (!_playerDisposed) {
        await player.stop();
        await player.dispose();
        _playerDisposed = true;
      }
      if (_ownsMutationQueue) {
        await _mutationQueue.close();
      }
    }));
    super.onClose();
  }
}
