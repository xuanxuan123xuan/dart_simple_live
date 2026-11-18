import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/modules/account/douyu/qr_login_controller.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

class DouyuQRLoginPage extends StatefulWidget {
  const DouyuQRLoginPage({super.key});

  @override
  State<DouyuQRLoginPage> createState() => _DouyuQRLoginPageState();
}

class _DouyuQRLoginPageState extends State<DouyuQRLoginPage> {
  final _backFocusNode = AppFocusNode();
  final _retryFocusNode = AppFocusNode();

  DouyuQRLoginController get controller => Get.find<DouyuQRLoginController>();

  @override
  void dispose() {
    _backFocusNode.dispose();
    _retryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(
        children: [
          AppStyle.vGap32,
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: _backFocusNode,
                iconData: Icons.arrow_back,
                text: '返回',
                autofocus: true,
                onTap: () => Get.back(),
              ),
              AppStyle.hGap32,
              Text(
                '登录斗鱼',
                style: AppStyle.titleStyleWhite.copyWith(
                  fontSize: 36.w,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          AppStyle.vGap48,
          Expanded(
            child: Center(
              child: Obx(() {
                final status = controller.qrStatus.value;
                if (status == DouyuQRStatus.loading) {
                  return SizedBox(
                    width: 64.w,
                    height: 64.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 8.w,
                      color: Colors.white,
                    ),
                  );
                }
                if (status == DouyuQRStatus.failed ||
                    status == DouyuQRStatus.expired) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status == DouyuQRStatus.expired ? '二维码已失效' : '二维码加载失败',
                        style: AppStyle.textStyleWhite,
                      ),
                      HighlightButton(
                        focusNode: _retryFocusNode,
                        iconData: Icons.refresh,
                        text: '刷新二维码',
                        autofocus: true,
                        onTap: controller.loadQrCode,
                      ),
                    ],
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      data: controller.qrcodeUrl.value,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                      size: 360.w,
                      padding: AppStyle.edgeInsetsA12,
                    ),
                    AppStyle.vGap16,
                    Text(
                      status == DouyuQRStatus.scanned
                          ? '已扫描，请在斗鱼手机客户端确认登录'
                          : '请使用斗鱼手机客户端扫描二维码登录',
                      style: AppStyle.textStyleWhite,
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
