import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/modules/settings/danmaku_display_settings.dart';
import 'package:simple_live_tv_app/widgets/settings_item_widget.dart';

/// Shared TV settings for choosing the danmaku display area or line count.
class TvDanmakuDisplaySettings extends StatelessWidget {
  const TvDanmakuDisplaySettings({
    required this.modeFocusNode,
    required this.valueFocusNode,
    super.key,
  });

  final AppFocusNode modeFocusNode;
  final AppFocusNode valueFocusNode;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Obx(
          () => SettingsItemWidget(
            foucsNode: modeFocusNode,
            autofocus: modeFocusNode.isFoucsed.value,
            title: '显示方式',
            items: DanmakuDisplaySettings.modeItems,
            value: settings.danmuDisplayMode.value,
            onChanged: (value) {
              settings.setDanmuDisplayMode(value as String);
            },
          ),
        ),
        AppStyle.vGap24,
        Obx(() {
          final mode = DanmakuDisplaySettings.normalizeMode(
            settings.danmuDisplayMode.value,
          );
          final lineMode = mode == DanmakuDisplaySettings.linesMode;
          return SettingsItemWidget(
            foucsNode: valueFocusNode,
            autofocus: valueFocusNode.isFoucsed.value,
            title: lineMode ? '最多行数' : '显示区域',
            items: lineMode
                ? DanmakuDisplaySettings.maxLinesItems
                : DanmakuDisplaySettings.areaItems,
            value: lineMode
                ? settings.danmuMaxLines.value
                : settings.danmuArea.value,
            onChanged: (value) {
              if (lineMode) {
                settings.setDanmuMaxLines(value as int);
              } else {
                settings.setDanmuArea(value as double);
              }
            },
          );
        }),
      ],
    );
  }
}
