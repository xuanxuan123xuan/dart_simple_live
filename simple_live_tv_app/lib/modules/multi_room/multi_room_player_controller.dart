import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/services/mpv_options_service.dart';

class MultiRoomPlayerController extends GetxController {
  final MultiRoomItem item;

  MultiRoomPlayerController(this.item);

  late final Player player = Player(
    configuration: PlayerConfiguration(
      title: item.userName,
      logLevel: MPVLogLevel.error,
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

  List<LivePlayQuality> _qualities = const [];
  List<String> _playUrls = const [];
  Map<String, String>? _playHeaders;
  int _qualityIndex = -1;
  int _lineIndex = 0;
  int _mediaErrorRetryCount = 0;
  bool _disposed = false;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription? _logSubscription;

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
    _initPlayerStreams();
    unawaited(MpvOptionsService.applyToPlayer(player));
    unawaited(load());
  }

  void _initPlayerStreams() {
    _errorSubscription = player.stream.error.listen((event) {
      Log.d("多屏同播播放器错误：${item.site.id}/${item.roomId} $event");
      if (event.contains('no sound.')) {
        return;
      }

      // Fix TV多开灰屏: 检测流错误并自动重试
      if (_isStreamError(event)) {
        unawaited(_handleStreamError(event));
        return;
      }

      unawaited(_handleMediaError(event));
    });
    _completedSubscription = player.stream.completed.listen((event) {
      if (event) {
        unawaited(_handleMediaEnd());
      }
    });
    _logSubscription = player.stream.log.listen((event) {
      Log.d("多屏同播播放器日志：${item.site.id}/${item.roomId} ${event.text}");
    });
  }

  // Fix TV多开灰屏: 判断是否为流错误
  bool _isStreamError(String error) {
    return error.contains('mbedtls_ssl_read') ||
        error.contains('Packet corrupt') ||
        error.contains('Packet corupt') ||
        error.contains('tls:') ||
        error.contains('Invalid NAL unit') ||
        error.contains('missing picture');
  }

  // Fix TV多开灰屏: 处理流错误，自动重试解码器
  Future<void> _handleStreamError(String error) async {
    if (_disposed || _playUrls.isEmpty) {
      return;
    }

    Log.w(
      "多屏同播检测到流错误，尝试恢复：${item.site.id}/${item.roomId} $error",
    );

    // 短暂暂停再恢复，触发重新连接
    try {
      await player.pause();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_disposed) {
        await player.play();
      }
    } catch (e, stackTrace) {
      Log.e(
        "多屏同播恢复流失败：${item.site.id}/${item.roomId} $e",
        stackTrace,
      );
      // 恢复失败，走线路切换逻辑
      await _handleMediaError(error);
    }
  }

  /// 读取多屏同播格子房间详情。
  ///
  /// 快手请求通过 [KuaishouRequestTrace] 标记为多开来源，保留高优先级但
  /// 仍遵守协调器最小间隔，与手机/桌面端多开行为保持一致；其他平台不标记来源。
  Future<LiveRoomDetail> _fetchRoomDetail() {
    if (item.site.id != Constant.kKuaishou) {
      return item.site.liveSite.getRoomDetail(roomId: item.roomId);
    }
    return KuaishouRequestTrace.run(
      KuaishouRequestSource.multiRoom,
      () => item.site.liveSite.getRoomDetail(roomId: item.roomId),
    );
  }

  Future<void> load() async {
    loading.value = true;
    errorText.value = "";
    liveStatus.value = false;
    try {
      await player.stop();
      Log.i("多屏同播开始加载房间：${item.site.id}/${item.roomId}");
      final roomDetail = await _fetchRoomDetail();
      if (_disposed) {
        return;
      }
      Log.i(
        "多屏同播房间详情：${item.site.id}/${item.roomId} "
        "status=${roomDetail.status} record=${roomDetail.isRecord} "
        "title=${roomDetail.title}",
      );
      detail.value = roomDetail;
      liveStatus.value = roomDetail.status || roomDetail.isRecord;
      if (!liveStatus.value) {
        errorText.value = "未开播";
        return;
      }
      await _loadQualities(roomDetail);
      await _loadPlayUrls(roomDetail);
      loading.value = false;
      await _openCurrentUrl();
    } catch (e) {
      Log.e(
        "多屏同播加载失败：${item.site.id}/${item.roomId} $e",
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
    final qualityLevel = Platform.isAndroid
        ? 0
        : AppSettingsController.instance.qualityLevel.value;
    if (qualityLevel == 2) {
      _qualityIndex = 0;
    } else if (qualityLevel == 0) {
      _qualityIndex = _qualities.length - 1;
    } else {
      _qualityIndex = (_qualities.length / 2).floor();
    }
    qualityInfo.value = _qualities[_qualityIndex].quality;
    Log.i(
      "多屏同播清晰度：${item.site.id}/${item.roomId} "
      "selected=${qualityInfo.value} index=$_qualityIndex total=${_qualities.length}",
    );
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
    _mediaErrorRetryCount = 0;
    lineInfo.value = "线路${_lineIndex + 1}";
    Log.i(
      "多屏同播播放地址：${item.site.id}/${item.roomId} "
      "quality=${qualityInfo.value} urls=${_playUrls.length} "
      "headers=${_playHeaders?.keys.join(',') ?? ''}",
    );
  }

  Future<void> _openCurrentUrl() async {
    if (_playUrls.isEmpty || _lineIndex < 0 || _lineIndex >= _playUrls.length) {
      throw Exception("播放线路为空");
    }
    errorText.value = "";
    Log.i(
      "多屏同播打开播放器：${item.site.id}/${item.roomId} "
      "line=${_lineIndex + 1}/${_playUrls.length} muted=${muted.value}",
    );
    unawaited(
      player
          .open(Media(_playUrls[_lineIndex], httpHeaders: _playHeaders))
          .catchError((Object e, StackTrace stackTrace) {
        Log.e(
          "多屏同播打开播放链接失败：${item.site.id}/${item.roomId} $e",
          stackTrace,
        );
        if (!_disposed) {
          unawaited(_handleMediaError(e.toString()));
        }
      }),
    );
    await player.setVolume(muted.value ? 0 : 100);
    Log.d(
      "多屏同播播放链接：${item.site.id}/${item.roomId} "
      "线路${_lineIndex + 1}/${_playUrls.length} ${_playUrls[_lineIndex]}",
    );
  }

  Future<void> _handleMediaEnd() async {
    if (_disposed || _playUrls.isEmpty) {
      return;
    }
    if (_lineIndex < _playUrls.length - 1) {
      Log.w(
        "多屏同播播放结束，切换线路：${item.site.id}/${item.roomId} "
        "from=${_lineIndex + 1}",
      );
      _lineIndex += 1;
      _mediaErrorRetryCount = 0;
      lineInfo.value = "线路${_lineIndex + 1}";
      await _openCurrentUrl();
      return;
    }
    errorText.value = "播放已结束";
    Log.w("多屏同播播放结束：${item.site.id}/${item.roomId}");
  }

  Future<void> _handleMediaError(String error) async {
    if (_disposed || _playUrls.isEmpty) {
      return;
    }
    if (_mediaErrorRetryCount < 2) {
      _mediaErrorRetryCount += 1;
      Log.w(
        "多屏同播播放错误，重试当前线路：${item.site.id}/${item.roomId} "
        "line=${_lineIndex + 1} retry=$_mediaErrorRetryCount error=$error",
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_disposed) {
        await _openCurrentUrl();
      }
      return;
    }
    if (_lineIndex < _playUrls.length - 1) {
      Log.w(
        "多屏同播播放错误，切换线路：${item.site.id}/${item.roomId} "
        "from=${_lineIndex + 1} error=$error",
      );
      _lineIndex += 1;
      _mediaErrorRetryCount = 0;
      lineInfo.value = "线路${_lineIndex + 1}";
      await _openCurrentUrl();
      return;
    }
    errorText.value = "播放失败：$error";
    Log.e(
      "多屏同播播放失败：${item.site.id}/${item.roomId} $error",
      StackTrace.current,
    );
  }

  Future<void> refreshRoom() async {
    await load();
  }

  Future<void> toggleMute() async {
    muted.value = !muted.value;
    await player.setVolume(muted.value ? 0 : 100);
  }

  @override
  void onClose() {
    _disposed = true;
    unawaited(_errorSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    unawaited(_logSubscription?.cancel());
    unawaited(player.stop());
    unawaited(player.dispose());
    super.onClose();
  }
}
