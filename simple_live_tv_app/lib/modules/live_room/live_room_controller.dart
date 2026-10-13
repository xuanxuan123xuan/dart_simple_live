import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/desktop_startup_args.dart';
import 'package:simple_live_tv_app/app/event_bus.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/models/db/history.dart';
import 'package:simple_live_tv_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_tv_app/services/current_room_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

class LiveRoomController extends PlayerController with WidgetsBindingObserver {
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
  }) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
  }
  final FocusNode focusNode = FocusNode();
  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var specialFollowed = false.obs;
  var liveStatus = false.obs;
  Rx<LiveStatusState> roomLiveState = LiveStatusState.unknown.obs;
  var playbackLoadError = "".obs;
  var muted = false.obs;
  bool _autoSwitchingRoom = false;
  Completer<void>? _playerReopenCompleter;
  bool _mediaRecoveryInFlight = false;
  bool _playbackSessionReady = false;
  int _roomGeneration = 0;
  int _loadGeneration = 0;
  int _urlRequestGeneration = 0;
  int _playRequestGeneration = 0;
  int _recoveryOperationGeneration = 0;
  bool _recoveryExhausted = false;
  bool _disposed = false;
  String _lastShortcutKey = "";
  String _lastShortcutSource = "";
  DateTime? _lastShortcutHandledAt;

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 是否处于后台
  var isBackground = false;

  /// 自动退出倒计时，单位秒
  var countdown = 60.obs;

  Timer? autoExitTimer;
  DateTime? _autoExitDeadline;
  bool _autoExitCompleting = false;

  /// 设置的自动关闭时长，单位分钟
  var autoExitMinutes = 60.obs;

  /// 是否已请求延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  var datetime = "00:00".obs;

  void initTimer() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      var now = DateTime.now();
      datetime.value =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    });
  }

  /// 双击退出Flag
  bool doubleClickExit = false;

  /// 双击退出Timer
  Timer? doubleClickTimer;
  final Queue<String> _recentDanmuFingerprints = Queue<String>();
  final Map<String, int> _recentDanmuCounts = <String, int>{};
  int _recentDanmuEventsSincePrune = 0;
  RxList<LiveRepeatedDanmuSummary> liveEventFlows =
      <LiveRepeatedDanmuSummary>[].obs;
  LiveRepeatedDanmuAggregator _liveEventFlowAggregator =
      LiveRepeatedDanmuAggregator();
  Timer? _liveEventFlowTimer;

  @override
  void onInit() {
    CurrentRoomService.instance.setRoom(site, roomId);
    initTimer();
    _startLiveEventFlowTimer();
    initAutoExit();
    showDanmakuState.value = DesktopStartupArgs.isSecondaryDesktopInstance
        ? false
        : AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    specialFollowed.value = DBService.instance.followBox
            .get("${site.id}_$roomId")
            ?.isSpecialFollow ??
        false;

    unawaited(loadData());
    unawaited(syncDesktopFullscreenState());

    super.onInit();
  }

  void initAutoExit() {
    autoExitEnable.value = AppSettingsController.instance.autoExitEnable.value;
    autoExitMinutes.value =
        AppSettingsController.instance.roomAutoExitDuration.value;
    countdown.value = autoExitMinutes.value * 60;
    if (autoExitEnable.value) {
      setAutoExit();
    }
  }

  void setAutoExit() {
    if (!autoExitEnable.value) {
      autoExitTimer?.cancel();
      _autoExitDeadline = null;
      return;
    }
    autoExitTimer?.cancel();
    _autoExitCompleting = false;
    _autoExitDeadline =
        DateTime.now().add(Duration(minutes: autoExitMinutes.value));
    _refreshAutoExitCountdown();
    autoExitTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshAutoExitCountdown(),
    );
  }

  void _refreshAutoExitCountdown() {
    final deadline = _autoExitDeadline;
    if (!autoExitEnable.value || deadline == null) {
      return;
    }
    final remaining = deadline.difference(DateTime.now());
    countdown.value = remaining.isNegative ? 0 : remaining.inSeconds + 1;
    if (remaining <= Duration.zero) {
      unawaited(_completeAutoExit());
    }
  }

  Future<void> _completeAutoExit() async {
    if (_autoExitCompleting) {
      return;
    }
    _autoExitCompleting = true;
    autoExitTimer?.cancel();
    _autoExitDeadline = null;
    countdown.value = 0;
    try {
      Log.i(
          "定时关闭到点：platform=${Platform.operatingSystem} room=${site.id}/$roomId");
      await liveDanmaku.stop();
      await player.stop();
      await WakelockPlus.disable();
      if (Platform.isAndroid) {
        await SystemNavigator.pop();
      } else {
        if (Platform.isWindows) {
          await windowManager.setPreventClose(false);
        }
        await windowManager.close();
      }
    } catch (e, stackTrace) {
      Log.e("执行定时关闭失败: $e", stackTrace);
    }
  }

  void stopAutoExit() {
    autoExitEnable.value = false;
    autoExitTimer?.cancel();
    _autoExitDeadline = null;
    countdown.value = autoExitMinutes.value * 60;
  }

  Future<void> refreshRoom() async {
    //messages.clear();

    liveDanmaku.stop();
    _clearDanmuDedupeState();

    await loadData();
  }

  Future<void> syncDesktopFullscreenState() async {
    if (!Platform.isWindows) {
      fullScreenState.value = false;
      return;
    }
    try {
      fullScreenState.value = await windowManager.isFullScreen();
    } catch (e) {
      Log.logPrint(e);
    }
  }

  Future<void> toggleDesktopFullscreen() async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      final nextValue = !await windowManager.isFullScreen();
      await windowManager.setFullScreen(nextValue);
      fullScreenState.value = nextValue;
      SmartDialog.showToast(nextValue ? "已进入全屏" : "已退出全屏");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("切换全屏失败");
    }
  }

  void toggleDanmaku() {
    showDanmakuState.value = !showDanmakuState.value;
    AppSettingsController.instance.setDanmuEnable(showDanmakuState.value);
    SmartDialog.showToast(showDanmakuState.value ? "弹幕已开启" : "弹幕已关闭");
  }

  Future<void> toggleMute() async {
    muted.value = !muted.value;
    await player.setVolume(muted.value ? 0 : 100);
    SmartDialog.showToast(muted.value ? "已静音" : "已恢复声音");
  }

  bool handleDesktopShortcut(
    String key, {
    required String source,
  }) {
    final now = DateTime.now();
    if (_lastShortcutKey == key &&
        _lastShortcutSource != source &&
        _lastShortcutHandledAt != null &&
        now.difference(_lastShortcutHandledAt!) <
            const Duration(milliseconds: 160)) {
      _lastShortcutHandledAt = now;
      _lastShortcutSource = source;
      return true;
    }
    _lastShortcutKey = key;
    _lastShortcutSource = source;
    _lastShortcutHandledAt = now;
    switch (key) {
      case "keyF":
        unawaited(toggleDesktopFullscreen());
        return true;
      case "keyD":
        toggleDanmaku();
        return true;
      case "keyR":
        unawaited(refreshRoom());
        return true;
      case "keyM":
        unawaited(toggleMute());
        return true;
      default:
        return false;
    }
  }

  bool handleKeyboardShortcut(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyF) {
      return handleDesktopShortcut("keyF", source: "keyboard");
    }
    if (key == LogicalKeyboardKey.keyD) {
      return handleDesktopShortcut("keyD", source: "keyboard");
    }
    if (key == LogicalKeyboardKey.keyR) {
      return handleDesktopShortcut("keyR", source: "keyboard");
    }
    if (key == LogicalKeyboardKey.keyM) {
      return handleDesktopShortcut("keyM", source: "keyboard");
    }
    return false;
  }

  void showAutoExitSheet() {
    Utils.showRightDialog(
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              "定时关闭",
              style: AppStyle.titleStyleWhite,
            ),
          ),
          Obx(
            () => SwitchListTile(
              title: Text(
                "启用定时关闭",
                style: Get.textTheme.titleMedium,
              ),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;
                AppSettingsController.instance.setAutoExitEnable(e);
                if (e) {
                  setAutoExit();
                } else {
                  stopAutoExit();
                }
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration =
                    Duration(hours: value.hour, minutes: value.minute);
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance
                    .setRoomAutoExitDuration(autoExitMinutes.value);
                if (autoExitEnable.value) {
                  setAutoExit();
                } else {
                  countdown.value = autoExitMinutes.value * 60;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) {
    if (msg.type == LiveMessageType.chat) {
      // 关键词屏蔽检查
      for (var keyword in AppSettingsController.instance.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            // should avoid this during add keyword
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽消息内容：${msg.message}");
          return;
        }
      }

      if (_isDuplicateDanmu(msg)) {
        return;
      }

      _recordLiveEventFlow(msg);

      if (!liveStatus.value || isBackground) {
        return;
      }

      final renderEmoji = AppSettingsController.instance.danmuRenderEmoji.value;
      final parts = renderEmoji ? _buildDanmakuContentParts(msg.spans) : null;
      addDanmaku([
        DanmakuContentItem(
          msg.message,
          color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b),
          imageUrls: renderEmoji && parts == null ? msg.imageUrls : null,
          parts: parts,
        ),
      ]);
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      //superChats.add(msg.data);
    }
  }

  List<DanmakuContentPart>? _buildDanmakuContentParts(
    List<LiveMessageSpan>? spans,
  ) {
    final source = spans ?? const <LiveMessageSpan>[];
    if (source.isEmpty) {
      return null;
    }
    final parts = <DanmakuContentPart>[];
    for (final span in source) {
      if (span.isText) {
        final text = span.text ?? "";
        if (text.isNotEmpty) {
          parts.add(DanmakuContentPart.text(text));
        }
      } else if (span.isImage) {
        final imageUrl = (span.imageUrl ?? "").trim();
        if (imageUrl.isNotEmpty) {
          parts.add(
            DanmakuContentPart.image(
              imageUrl,
              fallbackText: span.fallbackText,
            ),
          );
        }
      }
    }
    return parts.isEmpty ? null : parts;
  }

  bool _isDuplicateDanmu(LiveMessage msg) {
    final settings = AppSettingsController.instance;
    if (!settings.danmuDedupeEnable.value) {
      return false;
    }
    final strictMode = settings.danmuDedupeStrictMode;
    final fingerprint = _buildDanmuFingerprint(
      msg,
      includeUserName: !strictMode,
    );
    if (fingerprint == null) {
      return false;
    }
    final windowSize = settings.effectiveDanmuDedupeWindow;
    final duplicate = _recentDanmuCounts.containsKey(fingerprint);
    _recentDanmuFingerprints.addLast(fingerprint);
    _recentDanmuCounts[fingerprint] =
        (_recentDanmuCounts[fingerprint] ?? 0) + 1;
    if (strictMode) {
      _recentDanmuEventsSincePrune = 0;
      _pruneRecentDanmuFingerprints(windowSize);
      return duplicate;
    }

    final step = settings.danmuDedupeStep.value.clamp(1, 20).toInt();
    _recentDanmuEventsSincePrune += 1;
    final shouldPrune = _recentDanmuEventsSincePrune >= step ||
        _recentDanmuFingerprints.length > windowSize + step - 1;
    if (shouldPrune) {
      _recentDanmuEventsSincePrune = 0;
    }
    if (shouldPrune) {
      _pruneRecentDanmuFingerprints(windowSize);
    }
    return duplicate;
  }

  void _pruneRecentDanmuFingerprints(int windowSize) {
    while (_recentDanmuFingerprints.length > windowSize) {
      final removed = _recentDanmuFingerprints.removeFirst();
      final count = (_recentDanmuCounts[removed] ?? 0) - 1;
      if (count <= 0) {
        _recentDanmuCounts.remove(removed);
      } else {
        _recentDanmuCounts[removed] = count;
      }
    }
  }

  String? _buildDanmuFingerprint(
    LiveMessage msg, {
    required bool includeUserName,
  }) {
    final parts = <String>[];
    final message = _normalizeDanmuFingerprintPart(msg.message);
    if (message.isNotEmpty) {
      parts.add("m:$message");
    }
    for (final span in msg.spans ?? const <LiveMessageSpan>[]) {
      final text = _normalizeDanmuFingerprintPart(span.text ?? "");
      final imageUrl = _normalizeDanmuFingerprintPart(span.imageUrl ?? "");
      if (text.isNotEmpty) {
        parts.add("t:$text");
      }
      if (imageUrl.isNotEmpty) {
        parts.add("i:$imageUrl");
      }
    }
    for (final imageUrl in msg.imageUrls ?? const <String>[]) {
      final value = _normalizeDanmuFingerprintPart(imageUrl);
      if (value.isNotEmpty) {
        parts.add("u:$value");
      }
    }
    if (parts.isEmpty) {
      return null;
    }
    if (!includeUserName) {
      return parts.join("\u0002");
    }
    final userName = _normalizeDanmuFingerprintPart(msg.userName);
    if (userName.isEmpty) {
      return null;
    }
    return "$userName\u0001${parts.join("\u0002")}";
  }

  String _normalizeDanmuFingerprintPart(String value) {
    return value.trim().replaceAll(RegExp(r"\s+"), " ");
  }

  void _clearDanmuDedupeState() {
    _recentDanmuFingerprints.clear();
    _recentDanmuCounts.clear();
    _recentDanmuEventsSincePrune = 0;
  }

  void _startLiveEventFlowTimer() {
    _liveEventFlowTimer?.cancel();
    _liveEventFlowTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _flushLiveEventFlow(),
    );
  }

  void _recordLiveEventFlow(LiveMessage msg) {
    if (msg.userName == "LiveSysMessage") {
      return;
    }
    final settings = AppSettingsController.instance;
    if (!settings.liveEventFlowEnable.value) {
      clearLiveEventFlow();
      return;
    }
    final text = _normalizeDanmuFingerprintPart(msg.message);
    if (text.isEmpty) {
      return;
    }
    _ensureLiveEventFlowAggregatorSettings();
    _liveEventFlowAggregator.add(text);
    _flushLiveEventFlow();
  }

  void _flushLiveEventFlow() {
    final settings = AppSettingsController.instance;
    if (!settings.liveEventFlowEnable.value) {
      clearLiveEventFlow();
      return;
    }
    _ensureLiveEventFlowAggregatorSettings();
    final summaries = _liveEventFlowAggregator.preview(
      displayTtl: Duration(
        seconds: settings.effectiveLiveEventFlowDisplaySeconds,
      ),
    );
    liveEventFlows.assignAll(summaries);
  }

  void _ensureLiveEventFlowAggregatorSettings() {
    final settings = AppSettingsController.instance;
    final countWindow = Duration(
      seconds: settings.effectiveLiveEventFlowWindowSeconds,
    );
    final minDisplayCount = settings.effectiveLiveEventFlowMinCount;
    if (_liveEventFlowAggregator.countWindow == countWindow &&
        _liveEventFlowAggregator.minDisplayCount == minDisplayCount) {
      return;
    }
    _liveEventFlowAggregator = LiveRepeatedDanmuAggregator(
      countWindow: countWindow,
      minDisplayCount: minDisplayCount,
    );
    liveEventFlows.clear();
  }

  void clearLiveEventFlow() {
    _liveEventFlowAggregator.clear();
    liveEventFlows.clear();
  }

  /// 接收 WebSocket 关闭消息
  void onWSClose(String msg) {
    Log.d("弹幕服务器连接状态：$msg");
    final shouldNotify = msg.contains("失败") || msg.contains("超过最大次数");
    if (shouldNotify && AppSettingsController.instance.danmuEnable.value) {
      SmartDialog.showToast("弹幕连接异常：$msg");
    }
  }

  /// WebSocket 已连接完成
  void onWSReady() {
    Log.d("弹幕服务器连接成功");
  }

  /// 读取房间详情。快手请求通过 [KuaishouRequestTrace] 标记为用户进房来源，
  /// 供 core 侧按来源汇总请求量；其他平台不带来源标记。
  /// resetRoom 换台后同样经 loadData 走 userEnter 来源（与手机/桌面端语义一致）。
  Future<LiveRoomDetail> _fetchRoomDetailWithSource({
    required Site requestSite,
    required String requestRoomId,
  }) {
    if (requestSite.id != Constant.kKuaishou) {
      return requestSite.liveSite.getRoomDetail(roomId: requestRoomId);
    }
    return KuaishouRequestTrace.run(
      KuaishouRequestSource.userEnter,
      () => requestSite.liveSite.getRoomDetail(roomId: requestRoomId),
    );
  }

  /// 加载直播间信息
  Future<void> loadData() async {
    if (_disposed) return;
    final requestSite = site;
    final requestRoomId = roomId;
    final roomGeneration = _roomGeneration;
    final loadGeneration = ++_loadGeneration;
    _urlRequestGeneration++;
    _playRequestGeneration++;
    _resetAutomaticRecovery();
    invalidatePlaybackGeneration();

    playbackLoadError.value = "";
    roomLiveState.value = LiveStatusState.unknown;
    liveStatus.value = false;
    detail.value = null;
    online.value = 0;
    qualites.clear();
    currentQuality = -1;
    currentQualityInfo.value = "";
    playUrls.clear();
    playHeaders = null;
    currentLineIndex = -1;
    currentLineInfo.value = "";
    _playbackSessionReady = false;
    try {
      pageLoadding.value = true;
      final loadedDetail = await _fetchRoomDetailWithSource(
        requestSite: requestSite,
        requestRoomId: requestRoomId,
      );
      if (!_isCurrentLoad(roomGeneration, loadGeneration)) return;

      detail.value = loadedDetail;
      final status = loadedDetail.resolvedLiveStatus;
      roomLiveState.value = status;
      liveStatus.value = status == LiveStatusState.live;

      addHistory();
      online.value = loadedDetail.online;
      if (status == LiveStatusState.live) {
        await _loadPlayQualities(
          requestSite: requestSite,
          requestRoomId: requestRoomId,
          requestDetail: loadedDetail,
          roomGeneration: roomGeneration,
          loadGeneration: loadGeneration,
        );
      } else if (status == LiveStatusState.unknown) {
        playbackLoadError.value = "暂时无法确认直播状态，请重试";
      }
      if (!_isCurrentLoad(roomGeneration, loadGeneration)) return;
      if (loadedDetail.isRecord) {
        SmartDialog.showToast("当前主播未开播，正在轮播录像");
      }

      initDanmau();
      liveDanmaku.start(loadedDetail.danmakuData);
    } catch (e) {
      if (!_isCurrentLoad(roomGeneration, loadGeneration)) return;
      roomLiveState.value = LiveStatusState.unknown;
      playbackLoadError.value = "加载直播间失败，请重试：$e";
    } finally {
      if (_isCurrentLoad(roomGeneration, loadGeneration)) {
        pageLoadding.value = false;
      }
    }
  }

  /// 初始化播放器
  Future<void> getPlayQualites() async {
    final requestSite = site;
    final requestRoomId = roomId;
    final requestDetail = detail.value;
    if (requestDetail == null) return;
    _resetAutomaticRecovery();
    invalidatePlaybackGeneration();
    await _loadPlayQualities(
      requestSite: requestSite,
      requestRoomId: requestRoomId,
      requestDetail: requestDetail,
      roomGeneration: _roomGeneration,
      loadGeneration: _loadGeneration,
    );
  }

  Future<void> _loadPlayQualities({
    required Site requestSite,
    required String requestRoomId,
    required LiveRoomDetail requestDetail,
    required int roomGeneration,
    required int loadGeneration,
  }) async {
    if (!_isCurrentLoad(roomGeneration, loadGeneration)) return;
    final requestGeneration = ++_urlRequestGeneration;
    _playRequestGeneration++;
    _playbackSessionReady = false;
    playbackLoadError.value = "";
    qualites.clear();
    currentQuality = -1;
    playUrls.clear();
    playHeaders = null;
    currentLineIndex = -1;
    currentLineInfo.value = "";
    try {
      final playQualites =
          await requestSite.liveSite.getPlayQualites(detail: requestDetail);
      if (!_isCurrentUrlRequest(
          roomGeneration, loadGeneration, requestGeneration)) {
        return;
      }

      if (playQualites.isEmpty) {
        playbackLoadError.value = "无法读取播放清晰度，请稍后重试";
        Log.e(
          "播放清晰度列表为空：${requestSite.id}/$requestRoomId",
          StackTrace.current,
        );
        return;
      }
      qualites.value = playQualites;
      var qualityLevel = AppSettingsController.instance.qualityLevel.value;
      if (qualityLevel == 2) {
        //最高
        currentQuality = 0;
      } else if (qualityLevel == 0) {
        //最低
        currentQuality = playQualites.length - 1;
      } else {
        //中间值
        int middle = (playQualites.length / 2).floor();
        currentQuality = middle;
      }

      await _loadPlayUrl(
        requestSite: requestSite,
        requestRoomId: requestRoomId,
        requestDetail: requestDetail,
        qualityIndex: currentQuality,
        roomGeneration: roomGeneration,
        loadGeneration: loadGeneration,
      );
    } catch (e, stackTrace) {
      if (!_isCurrentUrlRequest(
          roomGeneration, loadGeneration, requestGeneration)) {
        return;
      }
      Log.e("读取播放清晰度失败：${requestSite.id}/$requestRoomId error=$e", stackTrace);
      playbackLoadError.value = e.toString();
    }
  }

  Future<void> getPlayUrl() async {
    final requestSite = site;
    final requestRoomId = roomId;
    final requestDetail = detail.value;
    final qualityIndex = currentQuality;
    if (requestDetail == null ||
        qualityIndex < 0 ||
        qualityIndex >= qualites.length) {
      return;
    }
    _resetAutomaticRecovery();
    invalidatePlaybackGeneration();
    playbackLoadError.value = "";
    final roomGeneration = _roomGeneration;
    final loadGeneration = _loadGeneration;
    await _loadPlayUrl(
      requestSite: requestSite,
      requestRoomId: requestRoomId,
      requestDetail: requestDetail,
      qualityIndex: qualityIndex,
      roomGeneration: roomGeneration,
      loadGeneration: loadGeneration,
    );
  }

  Future<void> _loadPlayUrl({
    required Site requestSite,
    required String requestRoomId,
    required LiveRoomDetail requestDetail,
    required int qualityIndex,
    required int roomGeneration,
    required int loadGeneration,
  }) async {
    if (!_isCurrentLoad(roomGeneration, loadGeneration) ||
        qualityIndex < 0 ||
        qualityIndex >= qualites.length) {
      return;
    }
    final requestGeneration = ++_urlRequestGeneration;
    _playRequestGeneration++;
    _playbackSessionReady = false;
    final quality = qualites[qualityIndex];
    playUrls.clear();
    playHeaders = null;
    currentQualityInfo.value = quality.quality;
    currentLineInfo.value = "";
    currentLineIndex = -1;
    try {
      final playUrl = await requestSite.liveSite
          .getPlayUrls(detail: requestDetail, quality: quality);
      if (!_isCurrentUrlRequest(
        roomGeneration,
        loadGeneration,
        requestGeneration,
      )) {
        return;
      }
      if (playUrl.urls.isEmpty) {
        playbackLoadError.value = "无法读取播放地址，请稍后重试";
        return;
      }
      playUrls.value = playUrl.urls;
      playHeaders = playUrl.headers;
      currentLineIndex = 0;
      currentLineInfo.value = "线路${currentLineIndex + 1}";
      mediaErrorRetryCount = 0;
      _recoveryExhausted = false;
      await setPlayer();
    } catch (e, stackTrace) {
      if (!_isCurrentUrlRequest(
        roomGeneration,
        loadGeneration,
        requestGeneration,
      )) {
        return;
      }
      Log.e("读取播放地址失败：${requestSite.id}/$requestRoomId error=$e", stackTrace);
      playbackLoadError.value = e.toString();
    }
  }

  Future<bool> _reloadPlayUrls({bool silent = false}) async {
    final requestSite = site;
    final requestDetail = detail.value;
    final qualityIndex = currentQuality;
    if (requestDetail == null ||
        qualityIndex < 0 ||
        qualityIndex >= qualites.length) {
      return false;
    }
    final roomGeneration = _roomGeneration;
    final loadGeneration = _loadGeneration;
    if (!_isCurrentLoad(roomGeneration, loadGeneration)) return false;
    final requestGeneration = ++_urlRequestGeneration;
    final quality = qualites[qualityIndex];
    currentQualityInfo.value = quality.quality;
    final playUrl = await requestSite.liveSite
        .getPlayUrls(detail: requestDetail, quality: quality);
    if (!_isCurrentUrlRequest(
      roomGeneration,
      loadGeneration,
      requestGeneration,
    )) {
      return false;
    }
    if (playUrl.urls.isEmpty) {
      if (!silent) {
        SmartDialog.showToast("无法读取播放地址");
      }
      return false;
    }
    playUrls.value = playUrl.urls;
    playHeaders = playUrl.headers;
    if (currentLineIndex < 0) {
      currentLineIndex = 0;
    } else if (currentLineIndex >= playUrls.length) {
      currentLineIndex = playUrls.length - 1;
    }
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    return true;
  }

  @protected
  Future<void> stopCurrentPlayer() => player.stop();

  @protected
  Future<void> openPlayerMedia(Media media) => player.open(media);

  @protected
  Future<void> setPlayerVolume(double volume) => player.setVolume(volume);

  Future<void> changePlayLine(int index) async {
    if (index < 0 || index >= playUrls.length) return;
    _urlRequestGeneration++;
    _resetAutomaticRecovery();
    invalidatePlaybackGeneration();
    playbackLoadError.value = "";
    await _changePlayLine(index);
  }

  Future<void> _changePlayLine(int index) async {
    currentLineIndex = index;
    mediaErrorRetryCount = 0;
    await setPlayer();
  }

  Future<void> setPlayer({bool refreshUrls = false}) async {
    final expectedRoomGeneration = _roomGeneration;
    final expectedLoadGeneration = _loadGeneration;
    final requestGeneration = ++_playRequestGeneration;
    final requestSite = site;
    final requestRoomId = roomId;
    _playbackSessionReady = false;
    while (_playerReopenCompleter != null) {
      await _playerReopenCompleter!.future;
      if (!_isCurrentPlaybackRequest(
        expectedRoomGeneration,
        expectedLoadGeneration,
        requestGeneration,
      )) {
        return;
      }
    }
    final completer = Completer<void>();
    _playerReopenCompleter = completer;
    try {
      if (refreshUrls) {
        var reloaded = false;
        try {
          reloaded = await _reloadPlayUrls(silent: true);
        } catch (e, stackTrace) {
          Log.e("刷新播放地址失败，将重开旧地址：${requestSite.id}/$requestRoomId error=$e",
              stackTrace);
        }
        if (!_isCurrentPlaybackRequest(
          expectedRoomGeneration,
          expectedLoadGeneration,
          requestGeneration,
        )) {
          return;
        }
        if (!reloaded) {
          Log.w("刷新播放地址失败，回退为重新打开当前线路");
        }
      }
      if (!_isCurrentPlaybackRequest(
            expectedRoomGeneration,
            expectedLoadGeneration,
            requestGeneration,
          ) ||
          currentLineIndex < 0 ||
          currentLineIndex >= playUrls.length) {
        return;
      }
      final playUrl = playUrls[currentLineIndex];
      final requestHeaders = playHeaders;
      currentLineInfo.value = "线路${currentLineIndex + 1}";
      errorMsg.value = "";
      await initializePlayer();
      if (!_isCurrentPlaybackRequest(
        expectedRoomGeneration,
        expectedLoadGeneration,
        requestGeneration,
      )) {
        return;
      }
      // 此时新媒体即将打开，起播期间发生的真实错误也需要进入恢复流程。
      _playbackSessionReady = true;
      beginPlaybackGeneration();
      await openPlayerMedia(
        Media(
          playUrl,
          httpHeaders: requestHeaders,
        ),
      );
      if (!_isCurrentPlaybackRequest(
        expectedRoomGeneration,
        expectedLoadGeneration,
        requestGeneration,
      )) {
        return;
      }
      playbackLoadError.value = "";
      await setPlayerVolume(muted.value ? 0 : 100);

      Log.d("播放链接\r\n：$playUrl");
    } catch (e, stackTrace) {
      Log.e("重新打开播放器失败: $e", stackTrace);
      if (_isCurrentPlaybackRequest(
        expectedRoomGeneration,
        expectedLoadGeneration,
        requestGeneration,
      )) {
        _playbackSessionReady = true;
        playbackLoadError.value = "播放器打开失败，请重试：$e";
        // 等当前重开流程释放互斥标记，再按普通播放错误进入下一次恢复。
        Timer.run(() {
          if (_isCurrentPlaybackRequest(
            expectedRoomGeneration,
            expectedLoadGeneration,
            requestGeneration,
          )) {
            unawaited(mediaError(e.toString()));
          }
        });
      }
    } finally {
      if (identical(_playerReopenCompleter, completer)) {
        _playerReopenCompleter = null;
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  bool get _shouldRefreshUrlsOnPlaybackRetry =>
      site.id == Constant.kHuya || site.id == Constant.kDouyu;

  @override
  Future<void> mediaEnd() async {
    await _recoverPlayback(ended: true);
  }

  int mediaErrorRetryCount = 0;

  @override
  Future<void> mediaError(String error) async {
    await _recoverPlayback(ended: false, error: error);
  }

  Future<void> _recoverPlayback(
      {required bool ended, String error = ""}) async {
    if (_mediaRecoveryInFlight ||
        _recoveryExhausted ||
        !_playbackSessionReady ||
        _disposed) {
      return;
    }
    final recoveryGeneration = ++_recoveryOperationGeneration;
    final expectedRoomGeneration = _roomGeneration;
    final expectedLoadGeneration = _loadGeneration;
    final requestSite = site;
    final requestRoomId = roomId;
    _mediaRecoveryInFlight = true;
    try {
      if (mediaErrorRetryCount < 2) {
        Log.d("${ended ? '播放结束' : '播放失败'}，尝试第${mediaErrorRetryCount + 1}次刷新");
        if (mediaErrorRetryCount == 1) {
          await waitForPlaybackRetry();
        }
        if (!_isCurrentRecovery(
          expectedRoomGeneration,
          expectedLoadGeneration,
          recoveryGeneration,
        )) {
          return;
        }
        mediaErrorRetryCount += 1;
        await setPlayer(refreshUrls: _shouldRefreshUrlsOnPlaybackRetry);
        return;
      }

      if (!_isCurrentRecovery(
        expectedRoomGeneration,
        expectedLoadGeneration,
        recoveryGeneration,
      )) {
        return;
      }
      if (playUrls.length - 1 == currentLineIndex) {
        _recoveryExhausted = true;
        if (requestSite.id == Constant.kDouyu) {
          await _handleDouyuExhaustedPlayback(
            requestSite: requestSite,
            requestRoomId: requestRoomId,
            roomGeneration: expectedRoomGeneration,
            loadGeneration: expectedLoadGeneration,
            recoveryGeneration: recoveryGeneration,
          );
        } else if (ended) {
          roomLiveState.value = LiveStatusState.offline;
          liveStatus.value = false;
          await _tryAutoSwitchToNextLiveRoom(reason: "live_end");
        } else {
          errorMsg.value = "播放失败";
          SmartDialog.showToast("播放失败:$error");
          await _tryAutoSwitchToNextLiveRoom(reason: "playback_failure");
        }
      } else {
        await _changePlayLine(currentLineIndex + 1);
      }
    } finally {
      if (recoveryGeneration == _recoveryOperationGeneration) {
        _mediaRecoveryInFlight = false;
      }
    }
  }

  @override
  Future<void> reopenPlaybackForRenderFallback() async {
    if (playbackRecoveryBlocked) return;
    await setPlayer(refreshUrls: _shouldRefreshUrlsOnPlaybackRetry);
  }

  @override
  bool get playbackRecoveryBlocked =>
      !_playbackSessionReady || _recoveryExhausted || _disposed;

  @override
  bool get playbackRecoveryPending =>
      _playbackSessionReady && (mediaErrorRetryCount > 0 || _recoveryExhausted);

  @override
  void playbackStable() {
    if (!_playbackSessionReady ||
        roomLiveState.value == LiveStatusState.offline) {
      return;
    }
    mediaErrorRetryCount = 0;
    _recoveryExhausted = false;
    playbackLoadError.value = "";
    errorMsg.value = "";
    roomLiveState.value = LiveStatusState.live;
    liveStatus.value = true;
    Log.d("播放已连续稳定 30 秒，重置自动恢复次数");
  }

  Future<void> _handleDouyuExhaustedPlayback({
    required Site requestSite,
    required String requestRoomId,
    required int roomGeneration,
    required int loadGeneration,
    required int recoveryGeneration,
  }) async {
    LiveStatusState state;
    try {
      state = await requestSite.liveSite.getLiveStatusState(
        roomId: requestRoomId,
      );
      if (!_isCurrentRecovery(
          roomGeneration, loadGeneration, recoveryGeneration)) {
        return;
      }
      if (state == LiveStatusState.offline) {
        await waitForOfflineConfirmation();
        if (!_isCurrentRecovery(
            roomGeneration, loadGeneration, recoveryGeneration)) {
          return;
        }
        state = await requestSite.liveSite.getLiveStatusState(
          roomId: requestRoomId,
        );
        if (!_isCurrentRecovery(
            roomGeneration, loadGeneration, recoveryGeneration)) {
          return;
        }
      }
    } catch (e, stackTrace) {
      if (!_isCurrentRecovery(
          roomGeneration, loadGeneration, recoveryGeneration)) {
        return;
      }
      Log.e("查询斗鱼直播状态失败：$requestRoomId error=$e", stackTrace);
      state = LiveStatusState.unknown;
    }

    if (state == LiveStatusState.offline) {
      roomLiveState.value = LiveStatusState.offline;
      liveStatus.value = false;
      playbackLoadError.value = "";
      await _tryAutoSwitchToNextLiveRoom(reason: "live_end");
      return;
    }

    if (state == LiveStatusState.live) {
      roomLiveState.value = LiveStatusState.live;
      liveStatus.value = true;
      playbackLoadError.value = "直播流已中断，请重试或切换线路";
    } else {
      roomLiveState.value = LiveStatusState.unknown;
      playbackLoadError.value = "播放恢复失败，暂时无法确认直播状态";
    }
    await _tryAutoSwitchToNextLiveRoom(reason: "playback_failure");
  }

  @protected
  Future<void> waitForPlaybackRetry() =>
      Future<void>.delayed(const Duration(seconds: 1));

  @protected
  Future<void> waitForOfflineConfirmation() =>
      Future<void>.delayed(const Duration(seconds: 1));

  bool _isCurrentLoad(int roomGeneration, int loadGeneration) =>
      !_disposed &&
      roomGeneration == _roomGeneration &&
      loadGeneration == _loadGeneration;

  bool _isCurrentRecovery(
    int roomGeneration,
    int loadGeneration,
    int recoveryGeneration,
  ) =>
      _isCurrentLoad(roomGeneration, loadGeneration) &&
      recoveryGeneration == _recoveryOperationGeneration;

  bool _isCurrentUrlRequest(
    int roomGeneration,
    int loadGeneration,
    int requestGeneration,
  ) =>
      _isCurrentLoad(roomGeneration, loadGeneration) &&
      requestGeneration == _urlRequestGeneration;

  bool _isCurrentPlaybackRequest(
    int roomGeneration,
    int loadGeneration,
    int requestGeneration,
  ) =>
      _isCurrentLoad(roomGeneration, loadGeneration) &&
      requestGeneration == _playRequestGeneration;

  void _resetAutomaticRecovery() {
    _recoveryOperationGeneration++;
    _mediaRecoveryInFlight = false;
    _recoveryExhausted = false;
    mediaErrorRetryCount = 0;
  }

  @override
  String playbackStallSourceIdentity(String activeUri) {
    return "${site.id}|$roomId|$currentQuality|$currentLineIndex";
  }

  @override
  bool get playbackRecoveryInFlight =>
      !_playbackSessionReady || _mediaRecoveryInFlight;

  Future<void> _tryAutoSwitchToNextLiveRoom({required String reason}) async {
    final settings = AppSettingsController.instance;
    final enabled = reason == "live_end"
        ? settings.autoSwitchNextOnLiveEnd.value
        : settings.autoSwitchNextOnPlaybackFailure.value;
    if (!enabled || _autoSwitchingRoom) {
      return;
    }

    final liveChannels = FollowUserService.instance.livingList.toList();
    if (liveChannels.isEmpty) {
      return;
    }

    final currentId = "${site.id}_$roomId";
    final currentIndex =
        liveChannels.indexWhere((item) => item.id == currentId);
    final candidates =
        liveChannels.where((item) => item.id != currentId).toList();
    if (candidates.isEmpty) {
      return;
    }

    FollowUser target;
    if (currentIndex < 0 || currentIndex >= liveChannels.length - 1) {
      target = candidates.first;
    } else {
      target = liveChannels[currentIndex + 1];
      if (target.id == currentId) {
        target = candidates.first;
      }
    }

    _autoSwitchingRoom = true;
    try {
      SmartDialog.showToast(
        reason == "live_end" ? "当前直播已结束，已切换到下一个直播间" : "当前直播播放失败，已切换到下一个直播间",
      );
      await resetRoom(Sites.allSites[target.siteId]!, target.roomId);
    } finally {
      _autoSwitchingRoom = false;
    }
  }

  /// 添加历史记录
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var history = DBService.instance.getHistory(id);
    if (history != null) {
      history.updateTime = DateTime.now();
    }
    history ??= History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );

    DBService.instance.addOrUpdateHistory(history);
  }

  /// 关注用户
  void followUser() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
      ),
    );
    followed.value = true;
    specialFollowed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
    SmartDialog.showToast("已关注");
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    // if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
    //   return;
    // }

    var id = "${site.id}_$roomId";
    DBService.instance.deleteFollow(id);
    followed.value = false;
    specialFollowed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
    SmartDialog.showToast("已取消关注");
  }

  void toggleSpecialFollow(bool enabled) {
    if (detail.value == null) {
      return;
    }
    final id = "${site.id}_$roomId";
    var follow = DBService.instance.followBox.get(id);
    follow ??= FollowUser(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      addTime: DateTime.now(),
    );
    follow.isSpecialFollow = enabled;
    DBService.instance.addFollow(follow);
    followed.value = true;
    specialFollowed.value = enabled;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
    SmartDialog.showToast(enabled ? "已设为特别关注" : "已取消特别关注");
  }

  Future<void> resetRoom(Site site, String roomId) async {
    if (this.site == site && this.roomId == roomId) {
      return;
    }

    _roomGeneration += 1;
    final roomGeneration = _roomGeneration;
    _loadGeneration += 1;
    _urlRequestGeneration++;
    _playRequestGeneration++;
    _resetAutomaticRecovery();
    invalidatePlaybackGeneration();
    _playbackSessionReady = false;
    rxSite.value = site;
    rxRoomId.value = roomId;
    detail.value = null;
    roomLiveState.value = LiveStatusState.unknown;
    liveStatus.value = false;
    playbackLoadError.value = "";
    online.value = 0;
    pageLoadding.value = false;
    CurrentRoomService.instance.setRoom(site, roomId);
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    specialFollowed.value = DBService.instance.followBox
            .get("${site.id}_$roomId")
            ?.isSpecialFollow ??
        false;

    // 清除全部消息
    liveDanmaku.stop();
    _clearDanmuDedupeState();
    clearLiveEventFlow();

    danmakuController?.clear();

    // 重新设置LiveDanmaku
    liveDanmaku = site.liveSite.getDanmaku();

    // 停止播放
    await stopCurrentPlayer();

    // 刷新信息
    if (_disposed || roomGeneration != _roomGeneration) return;
    await loadData();
  }

  void nextChannel() {
    //读取正在直播的频道
    var liveChannels = FollowUserService.instance.livingList;
    if (liveChannels.isEmpty) {
      SmartDialog.showToast("没有正在直播的频道");
      return;
    }
    var index = liveChannels
        .indexWhere((element) => element.id == "${site.id}_$roomId");
    if (index == -1) {
      SmartDialog.showToast("当前直播间不在直播列表中");
      return;
    }
    index += 1;
    if (index >= liveChannels.length) {
      index = 0;
    }
    var nextChannel = liveChannels[index];

    unawaited(
        resetRoom(Sites.allSites[nextChannel.siteId]!, nextChannel.roomId));
  }

  void prevChannel() {
    //读取正在直播的频道
    var liveChannels = FollowUserService.instance.livingList;
    if (liveChannels.isEmpty) {
      SmartDialog.showToast("没有正在直播的频道");
      return;
    }
    var index = liveChannels
        .indexWhere((element) => element.id == "${site.id}_$roomId");
    if (index == -1) {
      SmartDialog.showToast("当前直播间不在直播列表中");
      return;
    }
    index -= 1;
    if (index < 0) {
      index = liveChannels.length - 1;
    }
    var nextChannel = liveChannels[index];

    unawaited(
        resetRoom(Sites.allSites[nextChannel.siteId]!, nextChannel.roomId));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      Log.d("进入后台");
      //进入后台，关闭弹幕
      danmakuController?.clear();
      isBackground = true;
    } else
    //返回前台
    if (state == AppLifecycleState.resumed) {
      Log.d("返回前台");
      _refreshAutoExitCountdown();
      isBackground = false;
    }
  }

  @override
  void onClose() {
    _disposed = true;
    _roomGeneration += 1;
    _loadGeneration += 1;
    _urlRequestGeneration++;
    _playRequestGeneration++;
    _resetAutomaticRecovery();
    invalidatePlaybackGeneration();
    _playbackSessionReady = false;
    autoExitTimer?.cancel();
    liveDanmaku.stop();
    _liveEventFlowTimer?.cancel();
    clearLiveEventFlow();

    danmakuController = null;
    super.onClose();
  }
}
