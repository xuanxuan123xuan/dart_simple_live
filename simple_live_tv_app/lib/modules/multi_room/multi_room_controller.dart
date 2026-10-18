import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_focus_policy.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_playback_intent.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class MultiRoomController extends GetxController with WidgetsBindingObserver {
  static const int maxRooms = 4;
  static const Duration _qualityCooldown = Duration(seconds: 30);
  static const Duration _qualityStableWindow = Duration(seconds: 90);
  static const Duration _qualityRestoreInterval = Duration(seconds: 120);

  final List<MultiRoomItem> initialRooms;

  MultiRoomController(this.initialRooms);

  final rooms = <MultiRoomItem>[].obs;
  final sessions = <String, MultiRoomPlayerController>{};
  final focusNodes = <String, FocusNode>{};
  final mainRoomKey = ''.obs;
  final focusedRoomKey = ''.obs;
  final expandedRoomKey = RxnString();
  final audioRoomKeys = <String>{}.obs;
  final allPaused = false.obs;
  final allMuted = true.obs;
  final allowRoutePop = false.obs;

  Future<void> _loadQueue = Future<void>.value();
  Future<void> _audioQueue = Future<void>.value();
  final _queuedLoads = <MultiRoomPlayerController, Future<void>>{};
  Future<void>? _closeFuture;
  Timer? _qualityTimer;
  DateTime? _lastBufferFaultAt;
  DateTime? _lastQualityRestoreAt;
  DateTime? _firstMemoryWarningAt;
  final Set<String> _memoryReleasedRoomKeys = <String>{};
  int _danmakuSelectionGeneration = 0;
  bool _backgrounded = false;
  bool _closed = false;

  int get roomLimit {
    final settings = AppSettingsController.instance;
    return Platform.isAndroid
        ? settings.multiRoomMaxRooms.value.clamp(2, maxRooms).toInt()
        : maxRooms;
  }

  int get roomCount => rooms.length;
  int get remainingRoomCount => roomLimit - rooms.length;
  bool get areAllPaused =>
      sessions.isNotEmpty &&
      sessions.values.every((session) => session.userPaused.value);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    final requested = distinct(initialRooms);
    final limit = roomLimit;
    if (requested.length > limit) {
      SmartDialog.showToast('当前设备最多同时播放 $limit 路，已保留前 $limit 路');
    }
    rooms.assignAll(requested.take(limit));
    if (rooms.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_closed) Get.back<void>();
      });
      return;
    }
    mainRoomKey.value = rooms.first.key;
    for (final item in rooms) {
      _createSession(item);
    }
    _reconcileAudio(initial: true);
    unawaited(_syncDanmakuSelection());
    _qualityTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _restoreQualityWhenStable();
    });
    unawaited(WakelockPlus.enable());
  }

  List<MultiRoomItem> distinct(Iterable<MultiRoomItem> items) {
    final seen = <String>{};
    return items.where((item) => seen.add(item.key)).toList(growable: false);
  }

  FocusNode focusNodeFor(MultiRoomItem item) {
    return focusNodes.putIfAbsent(item.key, FocusNode.new);
  }

  MultiRoomPlayerController playerFor(MultiRoomItem item) {
    final session = sessions[item.key];
    if (session == null) {
      throw StateError('No multi-room playback session for ${item.key}');
    }
    return session;
  }

  void _createSession(MultiRoomItem item) {
    if (_closed || sessions.containsKey(item.key)) return;
    final session = MultiRoomPlayerController(
      item,
      onBufferFault: _onBufferFault,
      onAccountChange: _onAccountChange,
    );
    sessions[item.key] = session;
    session.prepare();
    if (_backgrounded) session.suspend(TvPlaybackSuspension.background);
    if (expandedRoomKey.value != null && expandedRoomKey.value != item.key) {
      session.suspend(TvPlaybackSuspension.focus);
    }
    session.markLoadScheduled();
    unawaited(_enqueueLoad(session));
  }

  void _onAccountChange(MultiRoomPlayerController session) {
    if (_closed || !identical(sessions[session.item.key], session)) return;
    session.markLoadScheduled();
    unawaited(_enqueueLoad(session));
  }

  Future<void> _enqueueLoad(MultiRoomPlayerController session) {
    final pending = _queuedLoads[session];
    if (pending != null) return pending;
    final next = _enqueue(() async {
      _queuedLoads.remove(session);
      if (identical(sessions[session.item.key], session)) await session.load();
    });
    _queuedLoads[session] = next;
    return next;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _loadQueue.then((_) async {
      if (!_closed) await action();
    });
    _loadQueue = next.catchError((Object error, StackTrace stackTrace) {
      Log.e('多屏任务队列执行失败：$error', stackTrace);
    });
    return _loadQueue;
  }

  bool addRooms(Iterable<MultiRoomItem> additions) {
    final candidates = distinct(additions)
        .where((item) => !rooms.any((room) => room.key == item.key))
        .toList(growable: false);
    if (candidates.isEmpty) {
      SmartDialog.showToast('所选直播间已在多屏列表中');
      return false;
    }
    final accepted =
        candidates.take(remainingRoomCount.clamp(0, maxRooms)).toList();
    if (accepted.isEmpty) {
      SmartDialog.showToast('最多同时播放 $roomLimit 路');
      return false;
    }
    rooms.addAll(accepted);
    for (final item in accepted) {
      _createSession(item);
    }
    if (accepted.length < candidates.length) {
      SmartDialog.showToast('最多同时播放 $roomLimit 路，已添加 ${accepted.length} 路');
    }
    return true;
  }

  Future<void> removeRoom(MultiRoomItem item) async {
    if (!rooms.any((room) => room.key == item.key)) return;
    final wasMain = mainRoomKey.value == item.key;
    final hadAudio = audioRoomKeys.contains(item.key);
    rooms.removeWhere((room) => room.key == item.key);
    audioRoomKeys.remove(item.key);
    focusNodes.remove(item.key)?.dispose();
    _memoryReleasedRoomKeys.remove(item.key);
    final session = sessions.remove(item.key);
    await session?.closePlaybackSession();

    if (rooms.isEmpty) {
      await exitPage();
      return;
    }
    if (wasMain || expandedRoomKey.value == item.key) {
      mainRoomKey.value = rooms.first.key;
      expandedRoomKey.value = null;
      _setFocusSuspension(null);
    }
    if (hadAudio &&
        audioRoomKeys.isEmpty &&
        !AppSettingsController.instance.multiRoomMixAudio.value) {
      await setAudioEnabled(mainRoomKey.value, true);
    }
    _reconcileAudio();
    await _syncDanmakuSelection();
  }

  void setMainRoom(MultiRoomItem item) {
    if (!rooms.any((room) => room.key == item.key)) return;
    mainRoomKey.value = item.key;
    _syncDanmakuSelection();
  }

  Future<void> toggleExpanded(MultiRoomItem item) async {
    if (expandedRoomKey.value == item.key) {
      expandedRoomKey.value = null;
      _setFocusSuspension(null);
      mainRoomKey.value = item.key;
      _syncDanmakuSelection();
      return;
    }
    expandedRoomKey.value = item.key;
    mainRoomKey.value = item.key;
    _setFocusSuspension(item.key);
    _syncDanmakuSelection();
  }

  void _setFocusSuspension(String? activeKey) {
    for (final entry in sessions.entries) {
      if (isRoomSuspendedByFocus(
        roomKey: entry.key,
        activeRoomKey: activeKey,
      )) {
        entry.value.suspend(TvPlaybackSuspension.focus);
      } else {
        entry.value.resume(TvPlaybackSuspension.focus);
      }
    }
  }

  bool get isExpanded => expandedRoomKey.value != null;

  Future<void> _enqueueAudio(Future<void> Function() action) {
    final next = _audioQueue.then((_) async {
      if (!_closed) await action();
    });
    _audioQueue = next.catchError((Object error, StackTrace stackTrace) {
      Log.e('多屏音频操作失败：$error', stackTrace);
    });
    return next;
  }

  Future<void> setAudioEnabled(String key, bool enabled) =>
      _enqueueAudio(() => _setAudioEnabled(key, enabled));

  Future<void> _setAudioEnabled(String key, bool enabled) async {
    final target = sessions[key];
    if (target == null) return;
    if (enabled && !AppSettingsController.instance.multiRoomMixAudio.value) {
      for (final entry in sessions.entries.toList()) {
        if (entry.key != key) await entry.value.setMuted(true);
      }
      audioRoomKeys.clear();
    }
    await target.setMuted(!enabled);
    if (!identical(sessions[key], target)) return;
    if (enabled) {
      audioRoomKeys.add(key);
    } else {
      audioRoomKeys.remove(key);
    }
    allMuted.value = audioRoomKeys.isEmpty;
  }

  Future<void> changeRoomVolume(MultiRoomItem item, double delta) =>
      _enqueueAudio(() async {
        final session = sessions[item.key];
        if (session == null) return;
        await _setRoomVolume(item.key, session.volume.value + delta);
      });

  Future<void> setRoomVolume(MultiRoomItem item, double value) {
    final requestedSession = sessions[item.key];
    return _enqueueAudio(() async {
      if (requestedSession == null ||
          !identical(sessions[item.key], requestedSession)) {
        return;
      }
      await _setRoomVolume(item.key, value);
    });
  }

  Future<void> _setRoomVolume(String key, double value) async {
    final session = sessions[key];
    if (session == null) return;
    final normalized = value.clamp(0, 100).toDouble();
    // Select the source before applying its new audible volume.
    await _setAudioEnabled(key, normalized > 0);
    if (identical(sessions[key], session)) await session.setVolume(normalized);
  }

  Future<void> toggleAudio(MultiRoomItem item) => _enqueueAudio(() async {
        final session = sessions[item.key];
        if (session != null) {
          await _setAudioEnabled(item.key, session.muted.value);
        }
      });

  Future<void> toggleAllAudio() => _enqueueAudio(() async {
        if (audioRoomKeys.isNotEmpty) {
          for (final session in sessions.values.toList()) {
            await session.setMuted(true);
          }
          audioRoomKeys.clear();
          allMuted.value = true;
        } else if (rooms.isNotEmpty) {
          await _setAudioEnabled(mainRoomKey.value, true);
        }
      });

  Future<void> toggleAllPause() async {
    final shouldPause =
        sessions.values.any((session) => !session.userPaused.value);
    allPaused.value = shouldPause;
    for (final session in sessions.values) {
      await session.setUserPaused(shouldPause);
    }
  }

  Future<void> refreshAll() async {
    final currentSessions = rooms
        .map((room) => sessions[room.key])
        .whereType<MultiRoomPlayerController>()
        .toList(growable: false);
    for (final session in currentSessions) {
      session.markLoadScheduled();
    }
    await Future.wait(currentSessions.map(_enqueueLoad));
  }

  void _reconcileAudio({bool initial = false}) {
    unawaited(_enqueueAudio(() async {
      if (initial && rooms.isNotEmpty) {
        await _setAudioEnabled(rooms.first.key, true);
      } else if (!AppSettingsController.instance.multiRoomMixAudio.value &&
          audioRoomKeys.length > 1) {
        final key = audioRoomKeys.contains(mainRoomKey.value)
            ? mainRoomKey.value
            : audioRoomKeys.first;
        await _setAudioEnabled(key, true);
      }
      allMuted.value = audioRoomKeys.isEmpty;
    }));
  }

  void setMixAudio(bool enabled) {
    unawaited(_enqueueAudio(() async {
      AppSettingsController.instance.setMultiRoomMixAudio(enabled);
      if (!enabled && audioRoomKeys.length > 1) {
        final key = audioRoomKeys.contains(mainRoomKey.value)
            ? mainRoomKey.value
            : audioRoomKeys.first;
        await _setAudioEnabled(key, true);
      }
    }));
  }

  Future<void> refreshRoom(MultiRoomItem item) {
    final session = sessions[item.key];
    if (session == null) return Future<void>.value();
    session.markLoadScheduled();
    return _enqueueLoad(session);
  }

  Future<void> selectRoomQuality(MultiRoomItem item, int index,
          {bool automatic = false}) =>
      _enqueue(() async {
        await sessions[item.key]?.selectQuality(index, automatic: automatic);
      });

  Future<void> selectRoomLine(MultiRoomItem item, int index) =>
      _enqueue(() async => sessions[item.key]?.selectLine(index));

  void _onBufferFault(MultiRoomPlayerController source) {
    final now = DateTime.now();
    final lastFault = _lastBufferFaultAt;
    if (lastFault != null && now.difference(lastFault) < _qualityCooldown) {
      return;
    }
    final candidates = rooms
        .map((item) => sessions[item.key])
        .whereType<MultiRoomPlayerController>()
        .where((session) => session.canReduceQuality)
        .toList();
    candidates.sort((left, right) {
      final leftIsMain = left.item.key == mainRoomKey.value ? 1 : 0;
      final rightIsMain = right.item.key == mainRoomKey.value ? 1 : 0;
      return leftIsMain.compareTo(rightIsMain);
    });
    if (candidates.isEmpty) return;
    _lastBufferFaultAt = now;
    _lastQualityRestoreAt = null;
    unawaited(selectRoomQuality(
      candidates.first.item,
      candidates.first.qualityIndex + 1,
      automatic: true,
    ));
  }

  void _restoreQualityWhenStable() {
    if (_closed || _backgrounded || rooms.isEmpty) return;
    if (!AppSettingsController.instance.autoQualityDegrade.value) return;
    final now = DateTime.now();
    final lastFault = _lastBufferFaultAt;
    if (lastFault == null || now.difference(lastFault) < _qualityStableWindow) {
      return;
    }
    final lastRestore = _lastQualityRestoreAt;
    if (lastRestore != null &&
        now.difference(lastRestore) < _qualityRestoreInterval) {
      return;
    }
    final candidates = rooms
        .map((room) => sessions[room.key])
        .whereType<MultiRoomPlayerController>()
        .where((session) => session.canRestoreQuality)
        .toList()
      ..sort((left, right) {
        final leftIsMain = left.item.key == mainRoomKey.value ? 1 : 0;
        final rightIsMain = right.item.key == mainRoomKey.value ? 1 : 0;
        return leftIsMain.compareTo(rightIsMain);
      });
    if (candidates.isEmpty) return;
    _lastQualityRestoreAt = now;
    unawaited(selectRoomQuality(
      candidates.first.item,
      candidates.first.qualityIndex - 1,
      automatic: true,
    ));
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    if (sessions.isEmpty) return;
    final now = DateTime.now();
    final first = _firstMemoryWarningAt;
    if (first != null && now.difference(first) <= const Duration(seconds: 30)) {
      MultiRoomPlayerController? secondary;
      for (final room in rooms) {
        if (room.key == mainRoomKey.value) continue;
        final session = sessions[room.key];
        if (session != null && !session.isReleasedForMemory) {
          secondary = session;
          break;
        }
      }
      if (secondary != null) {
        _memoryReleasedRoomKeys.add(secondary.item.key);
        unawaited(secondary.releaseForMemoryPressure());
        _firstMemoryWarningAt = null;
        return;
      }
    }
    _firstMemoryWarningAt = now;
    _onBufferFault(sessions[mainRoomKey.value] ?? sessions.values.first);
  }

  Future<void> recoverReleasedRoom(MultiRoomItem item) async {
    final key = item.key;
    if (!_memoryReleasedRoomKeys.contains(key)) return;
    final session = sessions[key];
    if (session == null) return;
    await _enqueue(session.restoreAfterMemoryPressure);
    if (!session.isReleasedForMemory) _memoryReleasedRoomKeys.remove(key);
  }

  Future<void> _syncDanmakuSelection() async {
    final generation = ++_danmakuSelectionGeneration;
    final activeKey = expandedRoomKey.value ?? mainRoomKey.value;
    for (final entry in sessions.entries.toList()) {
      if (_closed || generation != _danmakuSelectionGeneration) return;
      await entry.value.setDanmakuActive(
        entry.key == activeKey &&
            AppSettingsController.instance.danmuEnable.value,
      );
    }
  }

  Future<void> handleBack() async {
    if (expandedRoomKey.value != null) {
      final key = expandedRoomKey.value!;
      expandedRoomKey.value = null;
      _setFocusSuspension(null);
      mainRoomKey.value = key;
      await _syncDanmakuSelection();
      return;
    }
    final now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      await exitPage();
      return;
    }
    _lastBackAt = now;
    SmartDialog.showToast('再按一次返回关闭多屏');
  }

  DateTime? _lastBackAt;

  Future<void> exitPage() async {
    if (allowRoutePop.value) return;
    await closePlaybackSession();
    allowRoutePop.value = true;
    await Future<void>.delayed(Duration.zero);
    Get.back<void>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _backgrounded = true;
      for (final session in sessions.values) {
        session.suspend(TvPlaybackSuspension.background);
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      for (final session in sessions.values) {
        session.resume(TvPlaybackSuspension.background);
      }
    }
  }

  Future<void> closePlaybackSession() => _closeFuture ??= _closeSessions();

  Future<void> _closeSessions() async {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _qualityTimer?.cancel();
    for (final node in focusNodes.values) {
      node.dispose();
    }
    focusNodes.clear();
    await Future.wait(
        sessions.values.map((session) => session.closePlaybackSession()));
    sessions.clear();
    _memoryReleasedRoomKeys.clear();
    _queuedLoads.clear();
    await WakelockPlus.disable();
  }

  @override
  void onClose() {
    unawaited(closePlaybackSession());
    super.onClose();
  }
}
