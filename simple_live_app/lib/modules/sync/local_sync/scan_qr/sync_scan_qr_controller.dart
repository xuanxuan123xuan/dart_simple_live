import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/signalr_service.dart';

class SyncScanQRControlelr extends BaseController {
  static const _ohosScanChannel = MethodChannel('simple_live/ohos_scan');
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? qrController;
  StreamSubscription<Barcode>? barcodeStreamSubscription;
  final ohosScanning = false.obs;
  final ohosError = ''.obs;
  bool pause = false;

  @override
  void onReady() {
    super.onReady();
    if (Utils.isOhos) {
      startOhosScan();
    }
  }

  Future<void> startOhosScan() async {
    if (ohosScanning.value) {
      return;
    }
    ohosScanning.value = true;
    ohosError.value = '';
    try {
      final code = await _ohosScanChannel.invokeMethod<String>('scanQrCode');
      if (code == null || code.trim().isEmpty) {
        ohosError.value = '未识别到二维码内容';
        return;
      }
      await _handleCode(code);
    } on PlatformException catch (e) {
      if (e.code == 'scan_cancelled') {
        Get.back();
        return;
      }
      ohosError.value = '扫码失败：${e.message ?? e.code}';
    } catch (e) {
      ohosError.value = '扫码失败：$e';
    } finally {
      ohosScanning.value = false;
    }
  }

  void onQRViewCreated(QRViewController controller) {
    qrController = controller;
    barcodeStreamSubscription =
        qrController!.scannedDataStream.listen((scanData) async {
      Log.d(scanData.toString());
      if (pause) {
        return;
      }
      pause = true;
      // 扫码成功后暂停摄像头
      await controller.pauseCamera();
      var code = scanData.code ?? "";
      // 处理扫码结果
      if (code.isEmpty) {
        pause = false;
        await controller.resumeCamera();
        return;
      }

      await _handleCode(code);
    });
  }

  Future<void> _handleCode(String code) async {
    // 如果是远程同步房间号
    if (code.trim().length == SignalRService.kRoomIdLength) {
      Get.offAndToNamed(
        RoutePath.kRemoteSyncRoom,
        arguments: code.trim().toUpperCase(),
      );
      return;
    }
    var addressList = code.split(";");
    if (addressList.length >= 2) {
      await showPickerAddress(addressList);
    } else {
      Get.back(result: code);
    }
  }

  Future<void> showPickerAddress(List<String> addressList) async {
    SmartDialog.showToast("扫描到多个地址，请选择一个连接");
    var address = await Utils.showBottomSheet(
      title: '请选择地址',
      child: ListView.builder(
        itemBuilder: (_, i) {
          return ListTile(
            title: Text(addressList[i]),
            onTap: () {
              Get.back(result: addressList[i]);
            },
          );
        },
        itemCount: addressList.length,
      ),
    );
    if (address != null && address.isNotEmpty) {
      Get.back(result: address);
    }
  }

  @override
  void onClose() {
    barcodeStreamSubscription?.cancel();

    super.onClose();
  }
}
