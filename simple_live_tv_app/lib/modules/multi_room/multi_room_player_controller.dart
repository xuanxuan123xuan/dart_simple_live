import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_danmaku_burst_scheduler.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_danmaku_content.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_playback_intent.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/services/live_play_quality_presentation.dart';
import 'package:simple_live_tv_app/services/mpv_options_service.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/douyin_account_service.dart';
import 'package:simple_live_tv_app/services/douyu_account_service.dart';
import 'package:simple_live_tv_app/services/kuaishou_account_service.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';

class MultiRoomPlayerController extends GetxController {
  MultiRoomPlayerController(
    this.item, {
    void Function(MultiRoomPlayerController controller)? onBufferFault,
    void Function(MultiRoomPlayerController controller)? onAccountChange,
  })  : _onBufferFault = onBufferFault,
        _onAccountChange = onAccountChange;

  final MultiRoomItem item;
  final void Function(MultiRoomPlayerController controller)? _onBufferFault;
  final void Function(MultiRoomPlayerController controller)? _onAccountChange;

  Player? _player;
  VideoController? _videoController;
  Player get player => _player ??= _createPlayer();
  VideoController? get videoController => _videoController;
  final playbackIntent = TvPlaybackIntent();

  Player _createPlayer() => Player(
        configuration: PlayerConfiguration(
          title: item.userName,
          logLevel: MPVLogLevel.error,
        ),
      );

  final detail = Rx<LiveRoomDetail?>(null);
  final loading = true.obs;
  final liveStatus = false.obs;
  final liveState = LiveStatusState.unknown.obs;
  final errorText = ''.obs;
  final muted = true.obs;
  final volume = 72.0.obs;
  final userPaused = false.obs;
  final qualityInfo = ''.obs;
  final requestedQualityInfo = ''.obs;
  final lineInfo = ''.obs;
  final showDanmakuState = false.obs;
  final renderRevision = 0.obs;
  final _qualityMismatchTracker = LivePlayQualityMismatchTracker();
  final _bufferTracker = LiveRoomAutoQualityBufferTracker();

  List<LivePlayQuality> _qualities = const [];
  List<String> _playUrls = const [];
  Map<String, String>? _playHeaders;
  int _qualityIndex = -1;
  int? _targetQualityIndex;
  int _lineIndex = 0;
  int _mediaErrorRetryCount = 0;
  int _loadGeneration = 0;
  int _playbackGeneration = 0;
  int? _recoveringPlaybackGeneration;
  bool _disposed = false;
  bool _prepared = false;
  bool _loadingInFlight = false;
  bool _loadScheduled = false;
  bool _releasedForMemory = false;
  bool _danmakuActive = false;
  bool _accountReloadPending = false;
  int _accountChangeGeneration = 0;
  int _danmakuGeneration = 0;
  Future<void>? _closeFuture;
  Future<void>? _memoryReleaseFuture;
  Future<void> _nativeQueue = Future<void>.value();
  Future<void> _danmakuQueue = Future<void>.value();
  final List<Worker> _accountWorkers = <Worker>[];
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<PlayerLog>? _logSubscription;
  LiveDanmaku? _danmaku;
  DanmakuController? _danmakuController;
  TvDanmakuBurstScheduler? _danmakuBurstScheduler;

  /// Each room keeps its own burst scheduler so a dense room cannot starve the
  /// other tiles' canvases.
  TvDanmakuBurstScheduler get _danmakuScheduler =>
      _danmakuBurstScheduler ??= TvDanmakuBurstScheduler(
        onBatch: _addDanmakuBatch,
        realtime: !AppSettingsController.instance.tvPerformanceSmooth,
      );

  String get title {
    final roomTitle = detail.value?.title.trim();
    return roomTitle == null || roomTitle.isEmpty ? item.userName : roomTitle;
  }

  int get qualityIndex => _qualityIndex;
  int get targetQualityIndex => _targetQualityIndex ?? _qualityIndex;
  int get lineIndex => _lineIndex;
  int get lineCount => _playUrls.length;
  List<LivePlayQuality> get qualities => List.unmodifiable(_qualities);
  bool get isReleasedForMemory => _releasedForMemory;
  bool get canReduceQuality =>
      !_disposed &&
      !_loadingInFlight &&
      !_releasedForMemory &&
      playbackIntent.shouldPlay &&
      liveState.value == LiveStatusState.live &&
      _qualityIndex >= 0 &&
      _qualityIndex < _qualities.length - 1;
  bool get canRestoreQuality =>
      !_disposed &&
      !_loadingInFlight &&
      !_releasedForMemory &&
      playbackIntent.shouldPlay &&
      liveState.value == LiveStatusState.live &&
      _targetQualityIndex != null &&
      _qualityIndex > _targetQualityIndex! &&
      _qualityIndex > 0;

  String get qualityDisplayInfo {
    final requested = requestedQualityInfo.value;
    final actual = qualityInfo.value;
    if (requested.isEmpty || actual.isEmpty || requested == actual) {
      return actual;
    }
    return '请求 $requested / 实际 $actual';
  }

  void prepare() {
    if (_prepared || _disposed) return;
    final activePlayer = player;
    _videoController = VideoController(
      activePlayer,
      configuration: MpvOptionsService.videoControllerConfiguration(),
    );
    renderRevision.value++;
    _prepared = true;
    unawaited(MpvOptionsService.applyToPlayer(activePlayer));
    _initPlayerStreams();
    _watchAccountChanges();
  }

  void _watchAccountChanges() {
    if (item.site.id == Constant.kDouyu &&
        Get.isRegistered<DouyuAccountService>()) {
      final account = Get.find<DouyuAccountService>();
      var userRevision = account.userCookieRevision;
      _accountWorkers.add(ever(account.cookieRevision, (_) {
        final nextRevision = account.userCookieRevision;
        if (nextRevision == userRevision) return;
        userRevision = nextRevision;
        _scheduleAccountReload();
      }));
    }
    if (item.site.id == Constant.kXiaohongshu &&
        Get.isRegistered<XiaohongshuAccountService>()) {
      final account = Get.find<XiaohongshuAccountService>();
      _accountWorkers.add(ever(account.cookieRevision, (_) {
        _scheduleAccountReload();
      }));
    }
    if (item.site.id == Constant.kKuaishou &&
        Get.isRegistered<KuaishouAccountService>()) {
      final account = Get.find<KuaishouAccountService>();
      _accountWorkers.add(ever(account.revision, (_) {
        _scheduleAccountReload();
      }));
    }
    if (item.site.id == Constant.kDouyin &&
        Get.isRegistered<DouyinAccountService>()) {
      final account = Get.find<DouyinAccountService>();
      _accountWorkers.add(ever(account.hasCookie, (_) {
        _scheduleAccountReload();
      }));
    }
    if (item.site.id == Constant.kBiliBili &&
        Get.isRegistered<BiliBiliAccountService>()) {
      final account = Get.find<BiliBiliAccountService>();
      _accountWorkers.add(ever(account.logined, (_) {
        _scheduleAccountReload();
      }));
    }
  }

  void _scheduleAccountReload() {
    if (_disposed) return;
    markLoadScheduled();
    if (_accountReloadPending) return;
    _accountReloadPending = true;
    final generation = ++_accountChangeGeneration;
    scheduleMicrotask(() {
      _accountReloadPending = false;
      if (_disposed || generation != _accountChangeGeneration) return;
      if (_onAccountChange case final callback?) {
        callback(this);
      } else {
        unawaited(load());
      }
    });
  }

  void markLoadScheduled() {
    _loadScheduled = true;
    ++_loadGeneration;
    ++_playbackGeneration;
    _bumpDanmakuGeneration();
    _loadingInFlight = false;
    _bufferTracker.reset();
  }

  void _initPlayerStreams() {
    _logSubscription ??= player.stream.log.listen((event) {
      Log.d('多屏播放器日志：${item.site.id}/${item.roomId} ${event.text}');
    });
    try {
      _bufferingSubscription ??= player.stream.buffering.listen(_onBuffering);
    } catch (error) {
      Log.d('当前播放器不提供 buffering stream：$error');
    }
  }

  Future<void> load() async {
    if (_disposed || _releasedForMemory) return;
    _loadScheduled = false;
    final generation = ++_loadGeneration;
    _bumpDanmakuGeneration();
    _playbackGeneration++;
    _loadingInFlight = true;
    _playUrls = const [];
    _playHeaders = null;
    _qualities = const [];
    _bufferTracker.reset();
    loading.value = true;
    liveStatus.value = false;
    liveState.value = LiveStatusState.unknown;
    errorText.value = '';
    try {
      await _cancelPlaybackEvents();
      if (!_isCurrentLoad(generation)) return;
      await _stopDanmaku();
      if (!_isCurrentLoad(generation)) return;
      if (!_releasedForMemory) {
        await _runNative(() => player.stop());
      }

      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final roomDetail = await _fetchRoomDetail().timeout(
            const Duration(seconds: 20),
          );
          if (!_isCurrentLoad(generation)) return;
          detail.value = roomDetail;
          liveState.value = roomDetail.resolvedLiveStatus;
          liveStatus.value = liveState.value == LiveStatusState.live;
          if (liveState.value == LiveStatusState.offline) {
            errorText.value = '未开播';
            return;
          }
          if (liveState.value == LiveStatusState.unknown) {
            lastError = StateError('暂时无法确认直播状态');
            if (attempt < 2) {
              await _retryDelay(attempt);
              if (!_isCurrentLoad(generation)) return;
              continue;
            }
            errorText.value = '暂时无法确认直播状态，请重试';
            return;
          }

          final qualities = await item.site.liveSite
              .getPlayQualites(
                detail: roomDetail,
              )
              .timeout(const Duration(seconds: 20));
          if (!_isCurrentLoad(generation)) return;
          if (qualities.isEmpty) throw StateError('无法读取播放清晰度');
          _qualities = qualities;
          _selectInitialQuality();
          final requestedQuality = _qualities[_qualityIndex];
          requestedQualityInfo.value = requestedQuality.quality;
          final playUrl = await item.site.liveSite
              .getPlayUrls(
                detail: roomDetail,
                quality: requestedQuality,
              )
              .timeout(const Duration(seconds: 20));
          if (!_isCurrentLoad(generation)) return;
          if (playUrl.urls.isEmpty) throw StateError('无法读取播放地址');
          final presentation = LivePlayQualityPresentation(
            requestedQuality: requestedQuality,
            actualQuality: playUrl.actualQuality,
          );
          qualityInfo.value = presentation.display;
          final notice = _qualityMismatchTracker.update(presentation);
          if (notice != null) SmartDialog.showToast(notice);
          _playUrls = playUrl.urls;
          _playHeaders = playUrl.headers;
          _lineIndex = 0;
          _mediaErrorRetryCount = 0;
          lineInfo.value = '线路 1/${_playUrls.length}';
          liveStatus.value = true;
          _releasedForMemory = false;
          await _openCurrentUrl(generation);
          if (_isCurrentLoad(generation) && _danmakuActive) {
            final danmakuGeneration = _bumpDanmakuGeneration();
            unawaited(_startDanmaku(roomDetail, danmakuGeneration));
          }
          return;
        } catch (error, stackTrace) {
          if (!_isCurrentLoad(generation)) return;
          lastError = error;
          Log.e(
            '多屏加载尝试 ${attempt + 1}/3 失败：${item.site.id}/${item.roomId} $error',
            stackTrace,
          );
          if (attempt < 2) {
            await _retryDelay(attempt);
            if (!_isCurrentLoad(generation)) return;
          }
        }
      }
      if (_isCurrentLoad(generation)) {
        liveState.value = LiveStatusState.unknown;
        liveStatus.value = false;
        errorText.value = '加载失败，请重试：$lastError';
      }
    } finally {
      if (_isCurrentLoad(generation)) {
        loading.value = false;
        _loadingInFlight = false;
      }
    }
  }

  void _selectInitialQuality() {
    if (_qualities.isEmpty) {
      _qualityIndex = -1;
      return;
    }
    if (_targetQualityIndex == null) {
      final qualityLevel = AppSettingsController.instance.qualityLevel.value;
      _targetQualityIndex = qualityLevel == 2
          ? 0
          : qualityLevel == 0
              ? _qualities.length - 1
              : (_qualities.length / 2).floor();
    }
    _targetQualityIndex = _targetQualityIndex!.clamp(0, _qualities.length - 1);
    _qualityIndex = _qualityIndex < 0
        ? _targetQualityIndex!
        : _qualityIndex.clamp(0, _qualities.length - 1);
  }

  Future<LiveRoomDetail> _fetchRoomDetail() {
    final liveSite = item.site.liveSite;
    if (liveSite is XiaohongshuSite) {
      return liveSite.getRoomDetail(
        roomId: item.roomId,
        hostId: item.xiaohongshuHostId,
      );
    }
    if (liveSite is DouyinSite) {
      return liveSite.getRoomDetail(
        roomId: item.roomId,
        secUserId: item.douyinSecUserId,
      );
    }
    if (liveSite is KuaishouSite) {
      return KuaishouRequestTrace.run(
        KuaishouRequestSource.multiRoom,
        () => liveSite.getRoomDetail(roomId: item.roomId),
      );
    }
    return liveSite.getRoomDetail(roomId: item.roomId);
  }

  Future<void> _openCurrentUrl(int generation) async {
    if (!_isCurrentLoad(generation) ||
        _playUrls.isEmpty ||
        _lineIndex < 0 ||
        _lineIndex >= _playUrls.length) {
      return;
    }
    final playbackGeneration = ++_playbackGeneration;
    final currentUrl = _playUrls[_lineIndex];
    await _cancelPlaybackEvents();
    if (!_isCurrentPlayback(generation, playbackGeneration)) return;
    errorText.value = '';
    _bufferTracker.beginWarmup(DateTime.now());
    try {
      await _runNative(() {
        if (!_isCurrentPlayback(generation, playbackGeneration)) {
          return Future<void>.value();
        }
        return player.open(
          Media(currentUrl, httpHeaders: _playHeaders),
          play: false,
        );
      });
    } catch (error, stackTrace) {
      if (!_isCurrentPlayback(generation, playbackGeneration)) return;
      Log.e('多屏打开播放地址失败：${item.site.id}/${item.roomId} $error', stackTrace);
      if (_loadingInFlight) rethrow;
      await _recoverMediaError(
          error.toString(), generation, playbackGeneration);
      return;
    }
    if (!_isCurrentPlayback(generation, playbackGeneration)) {
      await _pauseIfPlaybackIsNoLongerAllowed();
      return;
    }
    _bindPlaybackEvents(generation, playbackGeneration);
    await _runNative(() async {
      await player.setVolume(muted.value ? 0 : volume.value);
      if (!_isCurrentPlayback(generation, playbackGeneration) ||
          !playbackIntent.shouldPlay) {
        await player.pause();
        return;
      }
      await player.play();
      if (!_isCurrentPlayback(generation, playbackGeneration) ||
          !playbackIntent.shouldPlay) {
        await player.pause();
      }
    });
    if (!_isCurrentPlayback(generation, playbackGeneration)) return;
    Log.i(
      '多屏打开直播流：${item.site.id}/${item.roomId} '
      'line=${_lineIndex + 1}/${_playUrls.length} muted=${muted.value}',
    );
  }

  void _bindPlaybackEvents(int loadGeneration, int playbackGeneration) {
    _errorSubscription = player.stream.error.listen((event) {
      if (!_isCurrentPlayback(loadGeneration, playbackGeneration) ||
          event.contains('no sound.')) {
        return;
      }
      unawaited(_recoverMediaError(event, loadGeneration, playbackGeneration));
    });
    _completedSubscription = player.stream.completed.listen((event) {
      if (event && _isCurrentPlayback(loadGeneration, playbackGeneration)) {
        unawaited(_recoverMediaError(
          '播放流已结束',
          loadGeneration,
          playbackGeneration,
        ));
      }
    });
  }

  Future<void> _recoverMediaError(
    String error,
    int loadGeneration,
    int playbackGeneration,
  ) async {
    if (!_isCurrentPlayback(loadGeneration, playbackGeneration) ||
        _loadingInFlight ||
        !playbackIntent.shouldPlay) {
      return;
    }
    if (_recoveringPlaybackGeneration == playbackGeneration) return;
    _recoveringPlaybackGeneration = playbackGeneration;
    try {
      if (_mediaErrorRetryCount < 2) {
        _mediaErrorRetryCount++;
        await _retryDelay(_mediaErrorRetryCount - 1);
        if (_isCurrentPlayback(loadGeneration, playbackGeneration)) {
          await _openCurrentUrl(loadGeneration);
        }
        return;
      }
      if (_lineIndex < _playUrls.length - 1) {
        _lineIndex++;
        _mediaErrorRetryCount = 0;
        lineInfo.value = '线路 ${_lineIndex + 1}/${_playUrls.length}';
        await _openCurrentUrl(loadGeneration);
        return;
      }
      liveState.value = LiveStatusState.unknown;
      liveStatus.value = false;
      errorText.value = '播放恢复失败，请手动刷新：$error';
      Log.w('多屏播放重试耗尽：${item.site.id}/${item.roomId} $error');
    } finally {
      if (_recoveringPlaybackGeneration == playbackGeneration) {
        _recoveringPlaybackGeneration = null;
      }
    }
  }

  void _onBuffering(bool buffering) {
    if (_disposed || _releasedForMemory) {
      _bufferTracker.reset();
      return;
    }
    if (_loadingInFlight ||
        _loadScheduled ||
        liveState.value != LiveStatusState.live) {
      return;
    }
    if (!playbackIntent.shouldPlay) {
      _bufferTracker.reset();
      return;
    }
    final shouldReduce = _bufferTracker.update(
      buffering: buffering,
      now: DateTime.now(),
    );
    if (shouldReduce &&
        AppSettingsController.instance.autoQualityDegrade.value) {
      _onBufferFault?.call(this);
    }
  }

  Future<void> _cancelPlaybackEvents() async {
    final errorSubscription = _errorSubscription;
    final completedSubscription = _completedSubscription;
    _errorSubscription = null;
    _completedSubscription = null;
    await errorSubscription?.cancel();
    await completedSubscription?.cancel();
  }

  Future<void> refreshRoom() => load();

  Future<void> selectQuality(int index, {bool automatic = false}) async {
    if (index < 0 || index >= _qualities.length || index == _qualityIndex) {
      return;
    }
    _qualityIndex = index;
    if (!automatic) _targetQualityIndex = index;
    requestedQualityInfo.value = _qualities[index].quality;
    await load();
  }

  Future<void> selectLine(int index) async {
    if (index < 0 || index >= _playUrls.length || index == _lineIndex) return;
    _lineIndex = index;
    lineInfo.value = '线路 ${_lineIndex + 1}/${_playUrls.length}';
    _mediaErrorRetryCount = 0;
    final generation = _loadGeneration;
    await _openCurrentUrl(generation);
  }

  Future<void> setMuted(bool value) async {
    muted.value = value;
    if (!value) volume.value = volume.value <= 0 ? 72 : volume.value;
    if (!_disposed && !_releasedForMemory) {
      await _runNative(() => player.setVolume(value ? 0 : volume.value));
    }
  }

  Future<void> setVolume(double value) async {
    final normalized = value.clamp(0, 100).toDouble();
    volume.value = normalized;
    muted.value = normalized == 0;
    if (!_disposed && !_releasedForMemory) {
      await _runNative(() => player.setVolume(normalized));
    }
  }

  Future<void> toggleMute() => setMuted(!muted.value);

  Future<void> setUserPaused(bool paused) async {
    if (_disposed) return;
    userPaused.value = paused;
    playbackIntent.userPaused = paused;
    if (paused) {
      _bufferTracker.reset();
      _playbackGeneration++;
      await _runNative(() => player.pause());
      return;
    }
    if (!playbackIntent.shouldPlay || _releasedForMemory) return;
    if (_playUrls.isEmpty) {
      if (!_loadingInFlight && !_loadScheduled) await load();
      return;
    }
    await _openCurrentUrl(_loadGeneration);
  }

  Future<void> togglePause() => setUserPaused(!userPaused.value);

  void suspend(TvPlaybackSuspension reason) {
    if (_disposed) return;
    playbackIntent.suspend(reason);
    _bufferTracker.reset();
    _playbackGeneration++;
    if (!_releasedForMemory) {
      unawaited(_runNative(() => player.pause()));
    }
  }

  void resume(TvPlaybackSuspension reason) {
    if (_disposed) return;
    playbackIntent.resume(reason);
    if (!playbackIntent.shouldPlay || _releasedForMemory) return;
    _bufferTracker.beginWarmup(DateTime.now());
    if (_playUrls.isNotEmpty) {
      unawaited(_openCurrentUrl(_loadGeneration));
    } else if (!_loadingInFlight && !_loadScheduled) {
      unawaited(load());
    }
  }

  void initDanmakuController(DanmakuController controller) {
    _danmakuController = controller;
  }

  Future<void> setDanmakuActive(bool active) async {
    final nextActive = active && !_isWindowsXiaohongshu;
    if (_danmakuActive == nextActive && showDanmakuState.value == nextActive) {
      return;
    }
    _danmakuActive = nextActive;
    showDanmakuState.value = _danmakuActive;
    final generation = _bumpDanmakuGeneration();
    final currentDetail = detail.value;
    if (_danmakuActive && currentDetail != null) {
      await _startDanmaku(currentDetail, generation);
    } else {
      await _stopDanmaku();
    }
  }

  bool get _isWindowsXiaohongshu =>
      Platform.isWindows && item.site.id == Constant.kXiaohongshu;

  Future<void> _startDanmaku(
    LiveRoomDetail roomDetail,
    int generation,
  ) {
    return _enqueueDanmaku(() async {
      await _stopCurrentDanmaku();
      if (!_isCurrentDanmaku(generation)) return;
      _danmakuScheduler.realtime =
          !AppSettingsController.instance.tvPerformanceSmooth;
      _danmakuScheduler.beginGeneration(generation);
      try {
        final current = _danmaku ??= item.site.liveSite.getDanmaku();
        current.onMessage = (message) {
          if (!identical(_danmaku, current)) return;
          handleDanmakuMessage(message, generation: generation);
        };
        await current.start(roomDetail.danmakuData);
        if (!_isCurrentDanmaku(generation)) await _stopCurrentDanmaku();
      } catch (error, stackTrace) {
        Log.e('多屏弹幕启动失败：${item.site.id}/${item.roomId} $error', stackTrace);
        return;
      }
    });
  }

  /// Renders one chat message on this room's canvas.
  ///
  /// Exposed so multi-room tests can drive the callback path without opening a
  /// real danmaku socket.
  @visibleForTesting
  void handleDanmakuMessage(LiveMessage message, {int? generation}) {
    if (message.type != LiveMessageType.chat) return;
    final targetGeneration = generation ?? _danmakuGeneration;
    if (!_canReceiveDanmaku(targetGeneration)) return;
    final settings = AppSettingsController.instance;
    final scheduler = _danmakuScheduler;
    scheduler.realtime = !settings.tvPerformanceSmooth;
    // A new connection may start before its first message arrives.
    if (scheduler.generation != targetGeneration) {
      scheduler.beginGeneration(targetGeneration);
    }
    scheduler.add(
      buildTvDanmakuContent(
        message,
        renderEmoji: settings.danmuRenderEmoji.value,
      ),
      generation: targetGeneration,
    );
  }

  void _addDanmakuBatch(List<DanmakuContentItem> items) {
    if (items.isEmpty || !_canDrawDanmaku) return;
    _danmakuController?.addDanmakuBatch(items);
  }

  bool get _canDrawDanmaku =>
      !_disposed && !_releasedForMemory && showDanmakuState.value;

  bool _canReceiveDanmaku(int generation) =>
      _canDrawDanmaku && generation == _danmakuGeneration;

  /// Advances the danmaku generation and drops anything still queued for the
  /// previous connection so a stale burst never reaches the new canvas.
  int _bumpDanmakuGeneration() {
    _danmakuBurstScheduler?.clear();
    return ++_danmakuGeneration;
  }

  bool _isCurrentDanmaku(int generation) =>
      !_disposed &&
      !_releasedForMemory &&
      _danmakuActive &&
      showDanmakuState.value &&
      generation == _danmakuGeneration;

  Future<void> _stopCurrentDanmaku() async {
    _danmakuBurstScheduler?.clear();
    _danmakuController?.clear();
    final current = _danmaku;
    if (current != null) {
      try {
        await current.stop();
      } catch (error, stackTrace) {
        Log.e('多屏弹幕停止失败：${item.site.id}/${item.roomId} $error', stackTrace);
      }
    }
  }

  Future<void> _stopDanmaku() {
    return _enqueueDanmaku(_stopCurrentDanmaku);
  }

  Future<void> _enqueueDanmaku(Future<void> Function() action) {
    final next = _danmakuQueue.then((_) => action());
    _danmakuQueue = next.catchError((Object error, StackTrace stackTrace) {
      Log.e('多屏弹幕任务失败：${item.site.id}/${item.roomId} $error', stackTrace);
    });
    return next;
  }

  Future<void> releaseForMemoryPressure() =>
      _memoryReleaseFuture ??= _releaseForMemoryPressure();

  Future<void> _releaseForMemoryPressure() async {
    if (_disposed || _releasedForMemory) return;
    playbackIntent.suspend(TvPlaybackSuspension.resources);
    _releasedForMemory = true;
    ++_loadGeneration;
    _bumpDanmakuGeneration();
    _loadingInFlight = false;
    _playbackGeneration++;
    await _stopDanmaku();
    await _cancelPlaybackEvents();
    await _bufferingSubscription?.cancel();
    _bufferingSubscription = null;
    await _logSubscription?.cancel();
    _logSubscription = null;
    final activePlayer = _player;
    if (activePlayer == null) return;
    await _runNative(() async {
      if (_disposed) return;
      await activePlayer.stop();
      await activePlayer.dispose();
      _player = null;
      _videoController = null;
      renderRevision.value++;
    }, allowReleased: true);
    if (_disposed) return;
    errorText.value = '资源紧张，按确定手动恢复';
  }

  Future<void> restoreAfterMemoryPressure() async {
    if (_disposed || !_releasedForMemory) return;
    await _memoryReleaseFuture;
    if (_disposed || !_releasedForMemory) return;
    _memoryReleaseFuture = null;
    _player = _createPlayer();
    _videoController = VideoController(
      _player!,
      configuration: MpvOptionsService.videoControllerConfiguration(),
    );
    _prepared = true;
    _releasedForMemory = false;
    renderRevision.value++;
    playbackIntent.resume(TvPlaybackSuspension.resources);
    unawaited(MpvOptionsService.applyToPlayer(player));
    _initPlayerStreams();
    await load();
  }

  bool _isCurrentLoad(int generation) =>
      !_disposed && !_releasedForMemory && generation == _loadGeneration;

  bool _isCurrentPlayback(int loadGeneration, int playbackGeneration) =>
      _isCurrentLoad(loadGeneration) &&
      playbackGeneration == _playbackGeneration;

  Future<void> _retryDelay(int attempt) =>
      Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));

  Future<void> closePlaybackSession() => _closeFuture ??= _close();

  Future<void> _close() async {
    _disposed = true;
    _bumpDanmakuGeneration();
    playbackIntent.close();
    _loadGeneration++;
    _playbackGeneration++;
    await _cancelPlaybackEvents();
    await _bufferingSubscription?.cancel();
    await _logSubscription?.cancel();
    _bufferingSubscription = null;
    _logSubscription = null;
    for (final worker in _accountWorkers) {
      worker.dispose();
    }
    _accountWorkers.clear();
    await _stopDanmaku();
    _danmakuBurstScheduler?.dispose();
    _danmakuBurstScheduler = null;
    await _nativeQueue;
    final activePlayer = _player;
    _videoController = null;
    if (activePlayer != null) {
      await _runNative(() => activePlayer.stop(), allowDisposed: true);
      await _runNative(() => activePlayer.dispose(), allowDisposed: true);
    }
    _player = null;
  }

  Future<void> _runNative(
    Future<void> Function() operation, {
    bool allowDisposed = false,
    bool allowReleased = false,
  }) {
    final next = _nativeQueue.then((_) async {
      if ((!allowDisposed && _disposed) ||
          (!allowDisposed && !allowReleased && _releasedForMemory)) {
        return;
      }
      await operation();
    });
    _nativeQueue = next.catchError((Object error, StackTrace stackTrace) {
      Log.e('多屏播放器原生操作失败：${item.site.id}/${item.roomId} $error', stackTrace);
    });
    return next;
  }

  Future<void> _pauseIfPlaybackIsNoLongerAllowed() async {
    if (!_disposed && !playbackIntent.shouldPlay && !_releasedForMemory) {
      await _runNative(() => player.pause());
    }
  }

  @override
  void onClose() {
    unawaited(closePlaybackSession());
    super.onClose();
  }
}
