import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:simple_live_app/widgets/settings/settings_menu.dart';

class FollowSettingsPage extends GetView<AppSettingsController> {
  const FollowSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("关注设置"),
      ),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          SettingsCard(
            child: Column(
              children: [
                Obx(
                  () => SettingsSwitch(
                    value: controller.autoUpdateFollowEnable.value,
                    title: "自动更新关注直播状态",
                    onChanged: (e) {
                      controller.setAutoUpdateFollowEnable(e);
                      FollowService.instance.initTimer();
                    },
                  ),
                ),
                if (Utils.isOhos) ...[
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      value: controller.ohosBackgroundFollowCheck.value,
                      title: "后台检查特别关注开播",
                      subtitle:
                          "应用退到后台或关闭后仍检查开播并推送通知。系统最小间隔约 2 小时，会增加耗电；仅支持虎牙 / 斗鱼 / 哔哩哔哩",
                      onChanged: controller.setOhosBackgroundFollowCheck,
                    ),
                  ),
                ],
                Obx(
                  () => Visibility(
                    visible: controller.autoUpdateFollowEnable.value,
                    child: AppStyle.divider,
                  ),
                ),
                Obx(
                  () => Visibility(
                    visible: controller.autoUpdateFollowEnable.value,
                    child: SettingsAction(
                      title: "自动更新间隔",
                      value:
                          "${controller.autoUpdateFollowDuration.value ~/ 60}小时${controller.autoUpdateFollowDuration.value % 60}分钟",
                      onTap: () {
                        setTimer(context);
                      },
                    ),
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu<int>(
                    title: "更新线程数",
                    value: controller.effectiveUpdateFollowThreadCount,
                    valueMap: const {
                      0: "自动",
                      1: "1",
                      2: "2",
                      3: "3",
                      4: "4",
                      5: "5",
                      6: "6",
                      7: "7",
                      8: "8",
                    },
                    onChanged: (value) {
                      controller.setUpdateFollowThreadCount(value);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu<int>(
                    title: "关注每页数量",
                    value: controller.followPageSize.value,
                    valueMap: const {
                      50: "50",
                      100: "100",
                      150: "150",
                      200: "200",
                      300: "300",
                      400: "400",
                    },
                    onChanged: (value) {
                      controller.setFollowPageSize(value);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void setTimer(BuildContext context) async {
    var value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: controller.autoUpdateFollowDuration.value ~/ 60,
        minute: controller.autoUpdateFollowDuration.value % 60,
      ),
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (_, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        );
      },
    );
    if (value == null || (value.hour == 0 && value.minute == 0)) {
      return;
    }
    var duration = Duration(hours: value.hour, minutes: value.minute);
    controller.setAutoUpdateFollowDuration(duration.inMinutes);
    FollowService.instance.initTimer();
  }
}
