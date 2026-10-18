import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/bulk_data_import_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_app/services/signalr_service.dart';
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';
import 'package:simple_live_app/widgets/sync_progress_dialog.dart';
import 'package:simple_live_core/simple_live_core.dart';

class RemoteSyncRoomController extends BaseController {
  final String roomId;
  final SignalRService signalR = SignalRService();
  RemoteSyncRoomController(this.roomId) {
    if (roomId.isNotEmpty) {
      currentRoomId.value = roomId;
    }
  }
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
  var currentRoomId = "--".obs;
  RxList<RoomUser> roomUsers = <RoomUser>[].obs;
  bool get hasValidRoomId =>
      currentRoomId.value.trim().length == SignalRService.kRoomIdLength;

  bool get canSendNewAccountCredentials => supportsNewAccountTargets(
        roomUsers,
        selfConnectionId: signalR.hubConnection.connectionId,
      );

  static bool supportsNewAccountTargets(
    Iterable<RoomUser> users, {
    String? selfConnectionId,
  }) {
    final selfId = selfConnectionId?.trim() ?? "";
    final receivers = users.where((user) {
      if (user.isSelf || (selfId.isNotEmpty && user.connectionId == selfId)) {
        return false;
      }
      return true;
    }).toList();
    return receivers.isNotEmpty &&
        receivers.every(
          (user) =>
              const {"tv", "windows"}
                  .contains(user.platform.trim().toLowerCase()) &&
              user.app.trim() == "Simple Live TV" &&
              _isVersionAtLeast(user.version, "1.8.0"),
        );
  }

  static bool _isVersionAtLeast(String version, String minimum) {
    List<int>? parse(String value) {
      final numbers = <int>[];
      for (final part in value.trim().split(".").take(3)) {
        final match = RegExp(r"^\d+").firstMatch(part);
        if (match == null) {
          return null;
        }
        numbers.add(int.parse(match.group(0)!));
      }
      if (numbers.length < 2) {
        return null;
      }
      while (numbers.length < 3) {
        numbers.add(0);
      }
      return numbers;
    }

    final current = parse(version);
    final required = parse(minimum);
    if (current == null || required == null) {
      return false;
    }
    for (var index = 0; index < current.length; index++) {
      if (current[index] != required[index]) {
        return current[index] > required[index];
      }
    }
    return true;
  }

  Timer? _timer;

  Future<Resp> _sendJsonChunks<T>({
    required List<T> items,
    required bool overlay,
    required String label,
    required String action,
    required Object? Function(T item) toJson,
  }) async {
    final policy = BulkDataImportService.policyForCount(items.length);
    final chunkSize = policy.scale == BulkDataScale.normal
        ? items.length
        : policy.dbBatchSize;
    final chunkTotal =
        items.isEmpty ? 1 : ((items.length - 1) ~/ chunkSize) + 1;
    Log.i("房间发送$label：count=${items.length} scale=${policy.label}");
    if (items.isEmpty) {
      SyncProgressDialog.update(SyncProgress(
        stage: "发送$label",
        current: 0,
        total: 0,
        message: "发送空列表",
      ));
      return signalR.sendContent(
        roomName: currentRoomId.value,
        action: action,
        overlay: overlay,
        content: json.encode(const []),
        extraPayload: const {
          "chunkIndex": 1,
          "chunkTotal": 1,
          "itemStart": 0,
          "itemEnd": 0,
          "itemTotal": 0,
        },
      );
    }
    Resp? lastResp;
    for (var start = 0; start < items.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, items.length).toInt();
      final chunkIndex = (start ~/ chunkSize) + 1;
      final chunk = items.sublist(start, end);
      final content = json.encode(chunk.map(toJson).toList());
      SyncProgressDialog.update(SyncProgress(
        stage: "发送$label",
        current: end,
        total: items.length,
        message: "发送第 $chunkIndex/$chunkTotal 段，$end/${items.length}",
      ));
      lastResp = await signalR.sendContent(
        roomName: currentRoomId.value,
        action: action,
        overlay: overlay && start == 0,
        content: content,
        extraPayload: {
          "chunkIndex": chunkIndex,
          "chunkTotal": chunkTotal,
          "itemStart": start,
          "itemEnd": end,
          "itemTotal": items.length,
        },
      );
      Log.i(
        "房间发送$label分段：${start + 1}-$end/${items.length} bytes=${content.length}",
      );
      if (!lastResp.isSuccess) {
        return lastResp;
      }
      await Future<void>.delayed(Duration.zero);
    }
    return lastResp ?? Resp(false, "没有可同步的数据", null);
  }

  var countDown = 600.obs;

  @override
  void onInit() {
    connect();
    super.onInit();
  }

  void connect() async {
    try {
      listenSignalR();
      // 总超时兜底：鸿蒙（或部分网络）上 IOWebSocketChannel.connect 的
      // ready 可能长期不完成，避免页面无限停在"连接中"。
      await signalR.connect().timeout(const Duration(seconds: 20));
      if (signalR.state == SignalRConnectionState.connected) {
        if (roomId.isEmpty) {
          createRoom();
        } else {
          joinRoom(roomId);
        }
      }
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("连接同步服务失败：${_formatSyncError(e)}");
      Get.back();
    }
  }

  void createRoom() async {
    try {
      var resp = await signalR.createRoom();
      if (resp.isSuccess && (resp.data?.trim().isNotEmpty ?? false)) {
        currentRoomId.value = resp.data!.trim();
        _startTimer();
      } else {
        SmartDialog.showToast(
          resp.message.isEmpty
              ? "创建房间失败：服务未返回房间号"
              : "创建房间失败：${_formatSyncError(resp.message)}",
        );
        Get.back();
      }
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("创建房间失败：${_formatSyncError(e)}");
      Get.back();
    }
  }

  void _startTimer() {
    // 倒计时5分钟，自动关闭页面
    countDown.value = 600;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      countDown--;
      if (countDown <= 0) {
        timer.cancel();
        Get.back();
      }
    });
  }

  void joinRoom(String roomId) async {
    try {
      var resp = await signalR.joinRoom(roomId);
      if (!resp.isSuccess) {
        SmartDialog.showToast(resp.message);
        Get.back();
      }
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("加入房间失败：${_formatSyncError(e)}");
      Get.back();
    }
  }

  String _formatSyncError(Object e) {
    final text =
        e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (text.isEmpty) {
      return "未知错误";
    }
    return text;
  }

  void listenSignalR() {
    _roomDestroyedSubscription = signalR.onRoomDestroyedStream.listen((roomId) {
      SmartDialog.showToast("房间已被销毁");
      Get.back();
    });
    _roomUserUpdatedSubscription = signalR.onRoomUserUpdatedStream.listen(
      (roomUsers) {
        this.roomUsers.assignAll(roomUsers);
      },
    );
    _onFavoriteSubscription = signalR.onFavoriteStream.listen((data) {
      onReceiveFavorite(data);
    });
    _onHistorySubscription = signalR.onHistoryStream.listen((data) {
      onReceiveHistory(data);
    });
    _onShieldWordSubscription = signalR.onShieldWordStream.listen((data) {
      onReceiveShieldWord(data);
    });
    _onBiliAccountSubscription = signalR.onBiliAccountStream.listen((data) {
      onReceiveBiliAccount(data);
    });
    _onDouyinAccountSubscription = signalR.onDouyinAccountStream.listen((data) {
      onReceiveDouyinAccount(data);
    });
    _onKuaishouAccountSubscription =
        signalR.onKuaishouAccountStream.listen((data) {
      onReceiveKuaishouAccount(data);
    });
    _onDouyuAccountSubscription = signalR.onDouyuAccountStream.listen((data) {
      onReceiveDouyuAccount(data);
    });
    _onXiaohongshuAccountSubscription =
        signalR.onXiaohongshuAccountStream.listen((data) {
      onReceiveXiaohongshuAccount(data);
    });
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
      SyncProgressDialog.update(SyncProgress(
        stage: progress.stage,
        current: current,
        total: payload.itemTotal,
        message: "${progress.stage} $current/${payload.itemTotal}",
      ));
    };
  }

  void onReceiveFavorite(RoomSyncPayload payload) async {
    try {
      SyncProgressDialog.show(_stageProgress("接收关注", payload));
      final stopwatch = Stopwatch()..start();
      var jsonBody = json.decode(payload.content);
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
        EventBus.instance.emit(Constant.kUpdateFollow, 0);
        SmartDialog.showToast(
          "已同步关注列表（${payload.itemTotal > 0 ? payload.itemTotal : result.imported} 条）",
        );
        SyncProgressDialog.dismiss();
      }
    } catch (e) {
      SyncProgressDialog.dismiss();
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  void onReceiveHistory(RoomSyncPayload payload) async {
    try {
      SyncProgressDialog.show(_stageProgress("接收历史", payload));
      final stopwatch = Stopwatch()..start();
      var jsonBody = json.decode(payload.content);
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
        SmartDialog.showToast(
          "已同步历史记录（${payload.itemTotal > 0 ? payload.itemTotal : result.imported} 条）",
        );
        EventBus.instance.emit(Constant.kUpdateHistory, 0);
        SyncProgressDialog.dismiss();
      }
    } catch (e) {
      SyncProgressDialog.dismiss();
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  void onReceiveShieldWord(RoomSyncPayload payload) async {
    try {
      SyncProgressDialog.show(_stageProgress("接收屏蔽词", payload));
      final stopwatch = Stopwatch()..start();
      var jsonBody = json.decode(payload.content);
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
        SmartDialog.showToast(
          "已同步屏蔽词（${payload.itemTotal > 0 ? payload.itemTotal : result.imported} 条）",
        );
        SyncProgressDialog.dismiss();
      }
    } catch (e) {
      SyncProgressDialog.dismiss();
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  void onReceiveBiliAccount(RoomSyncPayload payload) async {
    try {
      var jsonBody = json.decode(payload.content);
      if (jsonBody is! Map) {
        throw const FormatException("账号数据格式不是对象");
      }
      var cookie = jsonBody['cookie']?.toString() ?? "";
      if (cookie.isEmpty) {
        throw const FormatException("账号 Cookie 为空");
      }
      BiliBiliAccountService.instance.setCookie(cookie);
      BiliBiliAccountService.instance.loadUserInfo();
      SmartDialog.showToast('已同步哔哩哔哩账号');
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  void onReceiveDouyinAccount(RoomSyncPayload payload) async {
    try {
      var jsonBody = json.decode(payload.content);
      if (jsonBody is! Map) {
        throw const FormatException("账号数据格式不是对象");
      }
      var cookie = jsonBody['cookie']?.toString() ?? "";
      if (cookie.isEmpty) {
        throw const FormatException("账号 Cookie 为空");
      }
      DouyinAccountService.instance.setCookie(cookie);
      SmartDialog.showToast('已同步抖音账号');
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  void onReceiveKuaishouAccount(RoomSyncPayload payload) async {
    try {
      var jsonBody = json.decode(payload.content);
      if (jsonBody is! Map) {
        throw const FormatException("账号数据格式不是对象");
      }
      KuaishouAccountService.instance.importBackupMap(jsonBody);
      SmartDialog.showToast('已同步快手账号');
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
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
      SmartDialog.showToast('已同步斗鱼账号');
    } catch (e) {
      SmartDialog.showToast("同步斗鱼账号失败，请重试");
      Log.w("房间斗鱼账号导入失败：${e.runtimeType}");
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
      SmartDialog.showToast('已同步小红书账号');
    } catch (e) {
      SmartDialog.showToast("同步小红书账号失败，请重试");
      Log.w("房间小红书账号导入失败：${e.runtimeType}");
    }
  }

  Future<bool> showOverlayDialog() async {
    var overlay = await Utils.showAlertDialog(
      "是否覆盖远端数据？",
      title: "数据覆盖",
      confirm: "覆盖",
      cancel: "不覆盖",
    );
    return overlay;
  }

  void syncFollow() async {
    try {
      if (roomUsers.length <= 1) {
        SmartDialog.showToast("无设备连接");
        return;
      }

      var overlay = await showOverlayDialog();
      SyncProgressDialog.show(const SyncProgress(stage: "准备发送关注"));
      var users = DBService.instance.getFollowList();
      var resp = await _sendJsonChunks(
        items: users,
        label: "关注",
        action: "SendFavorite",
        overlay: overlay,
        toJson: (item) => item.toJson(),
      );
      if (resp.isSuccess) {
        SmartDialog.showToast("已发送关注列表");
      } else {
        SmartDialog.showToast("发送失败:${resp.message}");
      }
    } catch (e) {
      SmartDialog.showToast("发送失败:$e");
      Log.logPrint(e);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void syncHistory() async {
    try {
      if (roomUsers.length <= 1) {
        SmartDialog.showToast("无设备连接");
        return;
      }
      var overlay = await showOverlayDialog();
      SyncProgressDialog.show(const SyncProgress(stage: "准备发送历史"));
      var histores = DBService.instance.getHistores();
      var resp = await _sendJsonChunks(
        items: histores,
        label: "历史",
        action: "SendHistory",
        overlay: overlay,
        toJson: (item) => item.toJson(),
      );
      if (resp.isSuccess) {
        SmartDialog.showToast("已发送历史记录");
      } else {
        SmartDialog.showToast("发送失败:${resp.message}");
      }
    } catch (e) {
      SmartDialog.showToast("发送失败:$e");
      Log.logPrint(e);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void syncBlockedWord() async {
    try {
      if (roomUsers.length <= 1) {
        SmartDialog.showToast("无设备连接");
        return;
      }
      var overlay = await showOverlayDialog();
      SyncProgressDialog.show(const SyncProgress(stage: "准备发送屏蔽词"));
      var shieldList = AppSettingsController.instance.allShieldValues.toList();
      var resp = await _sendJsonChunks(
        items: shieldList,
        label: "屏蔽词",
        action: "SendShieldWord",
        overlay: overlay,
        toJson: (item) => item,
      );
      if (resp.isSuccess) {
        SmartDialog.showToast("已发送屏蔽词");
      } else {
        SmartDialog.showToast("发送失败:${resp.message}");
      }
    } catch (e) {
      SmartDialog.showToast("发送失败:$e");
      Log.logPrint(e);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void syncBiliAccount() async {
    try {
      if (roomUsers.length <= 1) {
        SmartDialog.showToast("无设备连接");
        return;
      }
      if (!BiliBiliAccountService.instance.logined.value) {
        SmartDialog.showToast("未登录哔哩哔哩");
        return;
      }
      SyncProgressDialog.show(const SyncProgress(stage: "发送哔哩哔哩账号"));

      var resp = await signalR.sendContent(
        roomName: currentRoomId.value,
        action: "SendBiliAccount",
        overlay: true,
        content: json.encode({
          "cookie": BiliBiliAccountService.instance.cookie,
        }),
      );
      if (resp.isSuccess) {
        SmartDialog.showToast("已发送哔哩哔哩账号");
      } else {
        SmartDialog.showToast("发送失败:${resp.message}");
      }
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void syncDouyinAccount() async {
    try {
      if (roomUsers.length <= 1) {
        SmartDialog.showToast("无设备连接");
        return;
      }
      if (!DouyinAccountService.instance.hasCookie.value) {
        SmartDialog.showToast("未配置抖音 Cookie");
        return;
      }
      SyncProgressDialog.show(const SyncProgress(stage: "发送抖音账号"));

      var resp = await signalR.sendContent(
        roomName: currentRoomId.value,
        action: "SendDouyinAccount",
        overlay: true,
        content: json.encode({
          "accountType": "douyin",
          "cookie": DouyinAccountService.instance.cookie,
        }),
      );
      if (resp.isSuccess) {
        SmartDialog.showToast("已发送抖音账号");
      } else {
        SmartDialog.showToast("发送失败:${resp.message}");
      }
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void syncKuaishouAccount() async {
    try {
      if (roomUsers.length <= 1) {
        SmartDialog.showToast("无设备连接");
        return;
      }
      final hasKuaishouCookie =
          KuaishouAccountService.instance.primary.isConfigured ||
              KuaishouAccountService.instance.secondary.isConfigured;
      if (!hasKuaishouCookie) {
        SmartDialog.showToast("未配置快手 Cookie");
        return;
      }
      SyncProgressDialog.show(const SyncProgress(stage: "发送快手账号"));

      var resp = await signalR.sendContent(
        roomName: currentRoomId.value,
        action: "SendKuaishouAccount",
        overlay: true,
        content: json.encode({
          ...KuaishouAccountService.instance.exportBackupMap(),
          "accountType": "kuaishou",
        }),
      );
      if (resp.isSuccess) {
        SmartDialog.showToast("已发送快手账号");
      } else {
        SmartDialog.showToast("发送失败:${resp.message}");
      }
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void syncDouyuAccount() async {
    if (!canSendNewAccountCredentials) {
      SmartDialog.showToast("需所有已连接设备均为 Simple Live TV 1.8.0 或更新版本");
      return;
    }
    final account = DouyuAccountService.instance;
    if (!account.hasCookie.value) {
      SmartDialog.showToast("未配置斗鱼 Cookie");
      return;
    }
    await _sendNewAccountCredentials(
      accountType: SyncAccountType.douyu,
      cookie: account.cookie,
      action: "SendDouyuAccount",
      label: "斗鱼",
    );
  }

  void syncXiaohongshuAccount() async {
    if (!canSendNewAccountCredentials) {
      SmartDialog.showToast("需所有已连接设备均为 Simple Live TV 1.8.0 或更新版本");
      return;
    }
    final account = XiaohongshuAccountService.instance;
    if (!account.hasCookie.value) {
      SmartDialog.showToast("未配置小红书 Cookie");
      return;
    }
    await _sendNewAccountCredentials(
      accountType: SyncAccountType.xiaohongshu,
      cookie: account.cookie,
      action: "SendXiaohongshuAccount",
      label: "小红书",
    );
  }

  Future<void> _sendNewAccountCredentials({
    required String accountType,
    required String cookie,
    required String action,
    required String label,
  }) async {
    try {
      if (roomUsers.length <= 1) {
        SmartDialog.showToast("无设备连接");
        return;
      }
      SyncProgressDialog.show(SyncProgress(stage: "发送$label账号"));
      final response = await signalR.sendContent(
        roomName: currentRoomId.value,
        action: action,
        overlay: true,
        content: json.encode(
          SyncAccountType.credentialsEnvelope(
            accountType: accountType,
            cookie: cookie,
          ),
        ),
      );
      if (response.isSuccess) {
        SmartDialog.showToast("已发送$label账号");
      } else {
        SmartDialog.showToast("发送失败：${response.message}");
      }
    } catch (e) {
      SmartDialog.showToast("同步$label账号失败：${exceptionToString(e)}");
      Log.w("房间$label账号发送失败：${e.runtimeType}");
    } finally {
      SyncProgressDialog.dismiss();
    }
  }

  void showQRInfo() {
    if (!hasValidRoomId) {
      SmartDialog.showToast("房间号还未创建完成");
      return;
    }
    Utils.showBottomSheet(
      title: "房间信息",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: currentRoomId.value,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
            padding: AppStyle.edgeInsetsA12,
            size: 200,
          ),
          AppStyle.vGap24,
          Text(
            currentRoomId.value,
            textAlign: TextAlign.center,
            style: Get.textTheme.titleLarge,
          ),
          const Text(
            "请使用其他Simple Live客户端扫描上方二维码\n建立连接后可选择需要同步的数据",
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  void onClose() {
    _timer?.cancel();
    _roomDestroyedSubscription?.cancel();
    _roomUserUpdatedSubscription?.cancel();
    _onFavoriteSubscription?.cancel();
    _onHistorySubscription?.cancel();
    _onShieldWordSubscription?.cancel();
    _onBiliAccountSubscription?.cancel();
    _onDouyinAccountSubscription?.cancel();
    _onKuaishouAccountSubscription?.cancel();
    _onDouyuAccountSubscription?.cancel();
    _onXiaohongshuAccountSubscription?.cancel();
    signalR.dispose();
    super.onClose();
  }
}
