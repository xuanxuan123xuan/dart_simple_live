import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';

/// Keeps a room's canvas and controller alive while applying shared preferences.
class TvDanmakuView extends StatelessWidget {
  const TvDanmakuView({
    required this.createdController,
    this.screenKey,
    super.key,
  });

  final ValueChanged<DanmakuController> createdController;
  final Key? screenKey;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Obx(
      () => DanmakuScreen(
        key: screenKey,
        createdController: createdController,
        option: DanmakuOption(
          fontSize: settings.danmuSize.value.w,
          fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
          area: settings.danmuArea.value,
          maxLines: settings.effectiveDanmuMaxLines,
          lineHeight: 1.25,
          emojiScale: 1.4,
          duration: settings.danmuSpeed.value.toInt(),
          opacity: settings.danmuOpacity.value,
        ),
      ),
    );
  }
}
