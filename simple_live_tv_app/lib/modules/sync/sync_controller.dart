import 'dart:async';
import 'dart:convert';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/event_bus.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/bulk_data_import_service.dart';
import 'package:simple_live_tv_app/services/douyu_account_service.dart';
import 'package:simple_live_tv_app/services/douyin_account_service.dart';
import 'package:simple_live_tv_app/services/kuaishou_account_service.dart';
import 'package:simple_live_tv_app/services/signalr_service.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';
import 'package:simple_live_tv_app/widgets/sync_progress_dialog.dart';

class SyncController extends BaseController {
  final SignalRService signalR = SignalRService();
  StreamSubscription? _stateSubscription;
  StreamSubscription? _roomDestroyedSubscription;
  StreamSubscription? _roomUserUpdatedSubscription;
  StreamSubscription? _onFavoriteSubscription;
  StreamSubscription? _onHistorySubscription;
  StreamSubscription? _onShieldWordSubscription;
  StreamSubscription? _onBiliAccountSubscription;
  StreamSubscription? _onDouyinAccountSubscription;
  StreamSubscription? _onKuaishouAccountSubscription;
  StreamSubscription? _onDouyuAccountSubscription;
  StreamSubscription? _onXiaohongshuAccountSubscription;
  final currentRoomId = "--".obs;
  final RxList<RoomUser> roomUsers = <RoomUser>[].obs;
  Timer? _timer;
  final countDown = 600.obs;
  final connectionError = "".obs;
  final latestResult = "".obs;
  final isConnecting = false.obs;

  final Rx<SignalRConnectionState> state =
      Rx<SignalRConnectionState>(SignalRConnectionState.connecting);

  @override
  void onInit() {
    unawaited(connect());
    super.onInit();
  }

  void _finishSyncImport({
    required String successMessage,
    String? eventName,
  }) {
    if (eventName != null) {
      EventBus.instance.emit(eventName, 0);
    }
    SyncProgressDialog.dismiss();
    latestResult.value = successMessage;
    SmartDialog.showToast(successMessage);
  }

  void _reportSyncFailure(
    String label,
    Object error, {
    bool sensitive = false,
  }) {
    final detail = sensitive ? "请检查账号凭据后重试" : _formatSyncError(error);
    latestResult.value = "$label：$detail";
    SyncProgressDialog.dismiss();
    SmartDialog.showToast(latestResult.value);
    Log.w("TV远程同步失败：${sensitive ? error.runtimeType : error}");
  }

  Future<void> connect() async {
    if (isConnecting.value) {
      return;
    }
    isConnecting.value = true;
    connectionError.value = "";
    currentRoomId.value = "--";
    roomUsers.clear();
    _timer?.cancel();
    countDown.value = 600;
    await _cancelSubscriptions();
    listenSignalR();
    state.value = SignalRConnectionState.connecting;
    try {
      await signalR.connect();
      if (signalR.state == SignalRConnectionState.connected) {
        await createRoom();
      }
    } catch (e) {
      connectionError.value = "连接同步服务失败：${_formatSyncError(e)}";
      state.value = SignalRConnectionState.disconnected;
      _timer?.cancel();
      countDown.value = 600;
    } finally {
      isConnecting.value = false;
    }
  }

  void retryConnection() => unawaited(connect());

  Future<void> createRoom() async {
    try {
      final resp = await signalR.createRoom();
      if (resp.isSuccess && (resp.data?.trim().isNotEmpty ?? false)) {
        currentRoomId.value = resp.data!.trim();
        _startTimer();
      } else {
        await _handleConnectionFailure(
          resp.message.isEmpty ? "服务未返回房间号" : resp.message,
          label: "创建同步房间失败",
        );
      }
    } catch (e) {
      await _handleConnectionFailure(e, label: "创建同步房间失败");
    }
  }

  Future<void> _handleConnectionFailure(
    Object error, {
    required String label,
  }) async {
    _timer?.cancel();
    countDown.value = 600;
    currentRoomId.value = "--";
    roomUsers.clear();
    connectionError.value = "$label：${_formatSyncError(error)}";
    state.value = SignalRConnectionState.disconnected;
    await signalR.disconnect();
  }

  String _formatSyncError(Object e) {
    final text =
        e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (text.isEmpty) {
      return "未知错误";
    }
    return text;
  }

  void _startTimer() {
    countDown.value = 600;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      countDown.value--;
      if (countDown <= 0) {
        timer.cancel();
        Get.back();
      }
    });
  }

  void listenSignalR() {
    _stateSubscription = signalR.stateStream.listen((event) {
      state.value = event;
      if (event == SignalRConnectionState.disconnected && !isConnecting.value) {
        _timer?.cancel();
        countDown.value = 600;
        connectionError.value = "连接已断开，可以重试";
      }
    });
    _roomDestroyedSubscription = signalR.onRoomDestroyedStream.listen((roomId) {
      _timer?.cancel();
      countDown.value = 600;
      currentRoomId.value = "--";
      roomUsers.clear();
      connectionError.value = "同步房间已关闭，请重新连接";
      state.value = SignalRConnectionState.disconnected;
    });
    _roomUserUpdatedSubscription = signalR.onRoomUserUpdatedStream.listen(
      (roomUsers) {
        this.roomUsers.assignAll(roomUsers);
      },
    );
    _onFavoriteSubscription =
        signalR.onFavoriteStream.listen(onReceiveFavorite);
    _onHistorySubscription = signalR.onHistoryStream.listen(onReceiveHistory);
    _onShieldWordSubscription =
        signalR.onShieldWordStream.listen(onReceiveShieldWord);
    _onBiliAccountSubscription =
        signalR.onBiliAccountStream.listen(onReceiveBiliAccount);
    _onDouyinAccountSubscription =
        signalR.onDouyinAccountStream.listen(onReceiveDouyinAccount);
    _onKuaishouAccountSubscription =
        signalR.onKuaishouAccountStream.listen(onReceiveKuaishouAccount);
    _onDouyuAccountSubscription =
        signalR.onDouyuAccountStream.listen(onReceiveDouyuAccount);
    _onXiaohongshuAccountSubscription =
        signalR.onXiaohongshuAccountStream.listen(onReceiveXiaohongshuAccount);
  }

  Future<void> _cancelSubscriptions() async {
    await _stateSubscription?.cancel();
    await _roomDestroyedSubscription?.cancel();
    await _roomUserUpdatedSubscription?.cancel();
    await _onFavoriteSubscription?.cancel();
    await _onHistorySubscription?.cancel();
    await _onShieldWordSubscription?.cancel();
    await _onBiliAccountSubscription?.cancel();
    await _onDouyinAccountSubscription?.cancel();
    await _onKuaishouAccountSubscription?.cancel();
    await _onDouyuAccountSubscription?.cancel();
    await _onXiaohongshuAccountSubscription?.cancel();
    _stateSubscription = null;
    _roomDestroyedSubscription = null;
    _roomUserUpdatedSubscription = null;
    _onFavoriteSubscription = null;
    _onHistorySubscription = null;
    _onShieldWordSubscription = null;
    _onBiliAccountSubscription = null;
    _onDouyinAccountSubscription = null;
    _onKuaishouAccountSubscription = null;
    _onDouyuAccountSubscription = null;
    _onXiaohongshuAccountSubscription = null;
  }

  SyncProgress _stageProgress(String stage, RoomSyncPayload payload) {
    final total =
        payload.itemTotal > 0 ? payload.itemTotal : payload.chunkTotal;
    final current =
        payload.itemTotal > 0 ? payload.itemEnd : payload.chunkIndex;
    return SyncProgress(
      stage: stage,
      current: current,
      total: total,
      message: payload.chunkTotal > 1
          ? "接收第 ${payload.chunkIndex}/${payload.chunkTotal} 段"
          : stage,
    );
  }

  SyncProgressCallback _wrapPayloadProgress(RoomSyncPayload payload) {
    return (progress) {
      if (payload.itemTotal <= 0) {
        SyncProgressDialog.update(progress);
        return;
      }
      final current = (payload.itemStart + progress.current)
          .clamp(0, payload.itemTotal)
          .toInt();
      SyncProgressDialog.update(
        SyncProgress(
          stage: progress.stage,
          current: current,
          total: payload.itemTotal,
          message: "${progress.stage} $current/${payload.itemTotal}",
        ),
      );
    };
  }

  void onReceiveFavorite(RoomSyncPayload payload) async {
    try {
      SyncProgressDialog.show(_stageProgress("接收关注", payload));
      final stopwatch = Stopwatch()..start();
      final jsonBody = json.decode(payload.content);
      if (jsonBody is! List) {
        throw const FormatException("关注列表格式不是数组");
      }

      final result = await BulkDataImportService.importFollowUsers(
        jsonBody,
        overwrite: payload.overlay,
        onProgress: _wrapPayloadProgress(payload),
      );

      stopwatch.stop();
      Log.i(
        "房间同步关注完成：${result.logSummary} bytes=${payload.content.length} elapsed=${stopwatch.elapsedMilliseconds}ms",
      );

      if (payload.isLastChunk) {
        _finishSyncImport(
          successMessage: "已同步关注列表：${result.logSummary}",
          eventName: Constant.kUpdateFollow,
        );
      }
    } catch (e) {
      _reportSyncFailure("接收关注失败", e);
    }
  }

  void onReceiveHistory(RoomSyncPayload payload) async {
    try {
      SyncProgressDialog.show(_stageProgress("接收历史", payload));
      final stopwatch = Stopwatch()..start();
      final jsonBody = json.decode(payload.content);
      if (jsonBody is! List) {
        throw const FormatException("历史记录格式不是数组");
      }

      final result = await BulkDataImportService.importHistories(
        jsonBody,
        overwrite: payload.overlay,
        onProgress: _wrapPayloadProgress(payload),
      );

      stopwatch.stop();
      Log.i(
        "房间同步历史完成：${result.logSummary} bytes=${payload.content.length} elapsed=${stopwatch.elapsedMilliseconds}ms",
      );

      if (payload.isLastChunk) {
        _finishSyncImport(
          successMessage: "已同步观看记录：${result.logSummary}",
          eventName: Constant.kUpdateHistory,
        );
      }
    } catch (e) {
      _reportSyncFailure("接收历史失败", e);
    }
  }

  void onReceiveShieldWord(RoomSyncPayload payload) async {
    try {
      SyncProgressDialog.show(_stageProgress("接收屏蔽词", payload));
      final stopwatch = Stopwatch()..start();
      final jsonBody = json.decode(payload.content);
      if (jsonBody is! List) {
        throw const FormatException("屏蔽词格式不是数组");
      }

      final result = await BulkDataImportService.importShieldValues(
        jsonBody,
        overwrite: payload.overlay,
        onProgress: _wrapPayloadProgress(payload),
      );

      stopwatch.stop();
      Log.i(
        "房间同步屏蔽词完成：${result.logSummary} bytes=${payload.content.length} elapsed=${stopwatch.elapsedMilliseconds}ms",
      );

      if (payload.isLastChunk) {
        _finishSyncImport(
          successMessage: "已同步屏蔽词：${result.logSummary}",
        );
      }
    } catch (e) {
      _reportSyncFailure("接收屏蔽词失败", e);
    }
  }

  void onReceiveBiliAccount(RoomSyncPayload payload) async {
    try {
      final jsonBody = json.decode(payload.content);
      if (jsonBody is! Map) {
        throw const FormatException("账号数据格式不是对象");
      }
      final cookie = jsonBody['cookie']?.toString() ?? "";
      if (cookie.isEmpty) {
        throw const FormatException("账号 Cookie 为空");
      }
      BiliBiliAccountService.instance.setCookie(cookie);
      BiliBiliAccountService.instance.loadUserInfo();
      latestResult.value = '已同步哔哩哔哩账号';
      SmartDialog.showToast(latestResult.value);
    } catch (e) {
      _reportSyncFailure("接收哔哩哔哩账号失败", e, sensitive: true);
    }
  }

  void onReceiveDouyinAccount(RoomSyncPayload payload) async {
    try {
      final jsonBody = json.decode(payload.content);
      if (jsonBody is! Map) {
        throw const FormatException("账号数据格式不是对象");
      }
      final cookie = jsonBody['cookie']?.toString() ?? "";
      if (cookie.isEmpty) {
        throw const FormatException("账号 Cookie 为空");
      }
      DouyinAccountService.instance.setCookie(cookie);
      latestResult.value = '已同步抖音账号';
      SmartDialog.showToast(latestResult.value);
    } catch (e) {
      _reportSyncFailure("接收抖音账号失败", e, sensitive: true);
    }
  }

  void onReceiveKuaishouAccount(RoomSyncPayload payload) async {
    try {
      final jsonBody = json.decode(payload.content);
      if (jsonBody is! Map) {
        throw const FormatException("账号数据格式不是对象");
      }
      KuaishouAccountService.instance.importBackupMap(jsonBody);
      latestResult.value = '已同步快手账号';
      SmartDialog.showToast(latestResult.value);
    } catch (e) {
      _reportSyncFailure("接收快手账号失败", e, sensitive: true);
    }
  }

  void onReceiveDouyuAccount(RoomSyncPayload payload) async {
    try {
      final raw = json.decode(payload.content);
      final cookie = SyncAccountType.readCredentialCookie(
        raw,
        accountType: SyncAccountType.douyu,
      );
      if (cookie == null ||
          !await DouyuAccountService.instance.setCookie(cookie)) {
        throw const FormatException("斗鱼账号凭据无效");
      }
      latestResult.value = '已同步斗鱼账号';
      SmartDialog.showToast(latestResult.value);
    } catch (e) {
      _reportSyncFailure("接收斗鱼账号失败", e, sensitive: true);
    }
  }

  void onReceiveXiaohongshuAccount(RoomSyncPayload payload) async {
    try {
      final raw = json.decode(payload.content);
      final cookie = SyncAccountType.readCredentialCookie(
        raw,
        accountType: SyncAccountType.xiaohongshu,
      );
      if (cookie == null ||
          !await XiaohongshuAccountService.instance.setCookie(cookie)) {
        throw const FormatException("小红书账号凭据无效");
      }
      latestResult.value = '已同步小红书账号';
      SmartDialog.showToast(latestResult.value);
    } catch (e) {
      _reportSyncFailure("接收小红书账号失败", e, sensitive: true);
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    unawaited(_cancelSubscriptions());
    signalR.dispose();
    super.onClose();
  }
}
