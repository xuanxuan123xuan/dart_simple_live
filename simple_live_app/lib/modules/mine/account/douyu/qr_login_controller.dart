import 'dart:async';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

enum DouyuQRStatus { loading, unscanned, scanned, expired, failed }

typedef DouyuQrTimerFactory = Timer Function(
  Duration interval,
  void Function() onTick,
);

class DouyuQRLoginController extends GetxController {
  DouyuQRLoginController({
    DouyuPassport? passport,
    Future<bool> Function(DouyuPassport)? applyQrCredentials,
    DouyuQrTimerFactory? timerFactory,
    void Function(String message)? showToast,
  })  : _passport = passport ?? DouyuPassport(),
        _applyQrCredentials = applyQrCredentials ??
            ((value) => DouyuAccountService.instance.applyQrCredentials(value)),
        _timerFactory = timerFactory ?? _createTimer,
        _showToast = showToast ?? SmartDialog.showToast;

  static Timer _createTimer(
    Duration interval,
    void Function() onTick,
  ) =>
      Timer.periodic(interval, (_) => onTick());

  final DouyuPassport _passport;
  final Future<bool> Function(DouyuPassport) _applyQrCredentials;
  final DouyuQrTimerFactory _timerFactory;
  final void Function(String message) _showToast;
  Timer? timer;
  final qrcodeUrl = ''.obs;
  final qrStatus = DouyuQRStatus.loading.obs;
  bool _polling = false;
  int _pollingGeneration = 0;
  int _generation = 0;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    loadQrCode();
  }

  Future<void> loadQrCode() async {
    if (_closed) return;
    final generation = ++_generation;
    timer?.cancel();
    timer = null;
    _polling = false;
    _passport.close();
    qrStatus.value = DouyuQRStatus.loading;
    try {
      final url = await _passport.generateQrCode();
      if (!_isCurrent(generation)) return;
      qrcodeUrl.value = url;
      qrStatus.value = DouyuQRStatus.unscanned;
      timer = _timerFactory(const Duration(seconds: 3), () {
        unawaited(pollQrStatus(generation: generation));
      });
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) return;
      Log.e('斗鱼二维码生成失败: $error', stackTrace);
      qrStatus.value = DouyuQRStatus.failed;
      _showToast(error.toString());
    }
  }

  Future<void> pollQrStatus({int? generation}) async {
    final currentGeneration = generation ?? _generation;
    if (!_isCurrent(currentGeneration) ||
        _polling ||
        (qrStatus.value != DouyuQRStatus.unscanned &&
            qrStatus.value != DouyuQRStatus.scanned) ||
        qrStatus.value == DouyuQRStatus.expired ||
        qrStatus.value == DouyuQRStatus.failed) {
      return;
    }
    _polling = true;
    _pollingGeneration = currentGeneration;
    try {
      switch (await _passport.poll()) {
        case DouyuQrStatus.waiting:
          break;
        case DouyuQrStatus.scanned:
          if (!_isCurrent(currentGeneration)) return;
          qrStatus.value = DouyuQRStatus.scanned;
          break;
        case DouyuQrStatus.expired:
          if (!_isCurrent(currentGeneration)) return;
          timer?.cancel();
          timer = null;
          qrStatus.value = DouyuQRStatus.expired;
          break;
        case DouyuQrStatus.authorized:
          if (!_isCurrent(currentGeneration)) return;
          timer?.cancel();
          timer = null;
          final applied = await _applyQrCredentials(_passport);
          if (!_isCurrent(currentGeneration)) return;
          if (!applied) throw StateError('斗鱼登录凭据未通过认证校验');
          _showToast('斗鱼账号登录成功');
          Get.back();
          break;
      }
    } catch (error, stackTrace) {
      if (!_isCurrent(currentGeneration)) return;
      Log.e('斗鱼扫码登录失败: $error', stackTrace);
      timer?.cancel();
      timer = null;
      qrStatus.value = DouyuQRStatus.failed;
      _showToast(error.toString());
    } finally {
      if (_pollingGeneration == currentGeneration) _polling = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _generation++;
    timer?.cancel();
    timer = null;
    _passport.close();
    super.onClose();
  }

  bool _isCurrent(int generation) => !_closed && generation == _generation;
}
