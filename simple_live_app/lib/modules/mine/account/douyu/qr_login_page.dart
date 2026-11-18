import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/mine/account/douyu/qr_login_controller.dart';

class DouyuQRLoginPage extends GetView<DouyuQRLoginController> {
  const DouyuQRLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('斗鱼账号登录')),
      body: Center(
        child: Obx(() {
          switch (controller.qrStatus.value) {
            case DouyuQRStatus.loading:
              return const CircularProgressIndicator();
            case DouyuQRStatus.failed:
            case DouyuQRStatus.expired:
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(controller.qrStatus.value == DouyuQRStatus.expired
                      ? '二维码已失效'
                      : '二维码加载失败'),
                  TextButton(
                    onPressed: controller.loadQrCode,
                    child: const Text('刷新二维码'),
                  ),
                ],
              );
            case DouyuQRStatus.unscanned:
            case DouyuQRStatus.scanned:
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: AppStyle.radius12,
                    child: QrImageView(
                      data: controller.qrcodeUrl.value,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                      size: 220,
                      padding: AppStyle.edgeInsetsA12,
                    ),
                  ),
                  AppStyle.vGap8,
                  Text(controller.qrStatus.value == DouyuQRStatus.scanned
                      ? '已扫描，请在斗鱼手机客户端确认登录'
                      : '请使用斗鱼手机客户端扫描二维码'),
                ],
              );
          }
        }),
      ),
    );
  }
}
