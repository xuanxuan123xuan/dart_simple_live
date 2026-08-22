import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/app_icon_service.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class AppstyleSettingPage extends GetView<AppSettingsController> {
  const AppstyleSettingPage({Key? key}) : super(key: key);

  // Every platform now ships the Modern artwork in its primary icon slot, so
  // both options in the picker would render the same mark. The picker and the
  // switching code behind it are kept intact — flip this to true to expose it.
  static const bool _showAppIconPicker = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("外观设置"),
      ),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "显示主题",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => RadioGroup<int>(
                groupValue: controller.themeMode.value,
                onChanged: (e) => controller.setTheme(e ?? 0),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<int>(
                      title: Text(
                        "跟随系统",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 0,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                    RadioListTile<int>(
                      title: Text(
                        "浅色模式",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 1,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                    RadioListTile<int>(
                      title: Text(
                        "深色模式",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 2,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                  ],
                ),
              ),
            ),
          ),
          ..._buildAppIconSection(context),
          AppStyle.vGap12,
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              "主题颜色",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSwitch(
                    value: controller.isDynamic.value,
                    title: "动态取色",
                    onChanged: (e) {
                      controller.setIsDynamic(e);
                      Get.forceAppUpdate();
                    },
                  ),
                  if (!controller.isDynamic.value) AppStyle.divider,
                  if (!controller.isDynamic.value)
                    Padding(
                      padding: AppStyle.edgeInsetsA12,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Color>[
                          const Color(0xffEF5350),
                          const Color(0xff3498db),
                          const Color(0xffF06292),
                          const Color(0xff9575CD),
                          const Color(0xff26C6DA),
                          const Color(0xff26A69A),
                          const Color(0xffFFF176),
                          const Color(0xffFF9800),
                        ]
                            .map(
                              (e) => GestureDetector(
                                onTap: () {
                                  controller.setStyleColor(e.toARGB32());
                                  Get.forceAppUpdate();
                                },
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: e,
                                    borderRadius: AppStyle.radius4,
                                    border: Border.all(
                                      color: Colors.grey.withAlpha(50),
                                      width: 1,
                                    ),
                                  ),
                                  child: Obx(
                                    () => Center(
                                      child: Icon(
                                        Icons.check,
                                        color: controller.styleColor.value ==
                                                e.toARGB32()
                                            ? Colors.white
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The app icon picker. Hidden while [_showAppIconPicker] is false; the
  /// runtime switching path (AppSettingsController.setAppIconVariant ->
  /// AppIconService -> the platform channels) stays wired up either way.
  List<Widget> _buildAppIconSection(BuildContext context) {
    if (!_showAppIconPicker) {
      return const [];
    }
    return [
      AppStyle.vGap12,
      Padding(
        padding: AppStyle.edgeInsetsA12,
        child: Text("应用图标", style: Get.textTheme.titleSmall),
      ),
      SettingsCard(
        child: Obx(
          () => RadioGroup<String>(
            groupValue: controller.appIconVariant.value,
            onChanged: controller.appIconChanging.value
                ? (_) {}
                : (value) async {
                    if (value == null) return;
                    final error = await controller.setAppIconVariant(value);
                    if (error == null || !context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error)),
                    );
                  },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: AppIconVariant.classic.storageValue,
                  title: const Text("Classic"),
                  subtitle: Text(
                    AppIconService.isSupported
                        ? "蓝色播放图标"
                        : "蓝色播放图标（当前平台不支持运行时切换）",
                  ),
                  secondary: const _AppIconPreview(
                    asset: "assets/images/logo.png",
                  ),
                  contentPadding: AppStyle.edgeInsetsH12,
                ),
                AppStyle.divider,
                RadioListTile<String>(
                  value: AppIconVariant.modern.storageValue,
                  title: const Text("Modern"),
                  subtitle: Text(
                    AppIconService.isSupported
                        ? "弹幕、直播信号与花体字标"
                        : "弹幕、直播信号与花体字标（当前平台不支持运行时切换）",
                  ),
                  secondary: const _AppIconPreview(
                    asset: "assets/images/app_icon_simplelive.png",
                  ),
                  contentPadding: AppStyle.edgeInsetsH12,
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

class _AppIconPreview extends StatelessWidget {
  const _AppIconPreview({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        asset,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
      ),
    );
  }
}

// extension ColorExt on Color {
//   static int _floatToInt8(double x) {
//     return (x * 255.0).round() & 0xff;
//   }

//   int get v =>
//       _floatToInt8(a) << 24 |
//       _floatToInt8(r) << 16 |
//       _floatToInt8(g) << 8 |
//       _floatToInt8(b) << 0;
// }
