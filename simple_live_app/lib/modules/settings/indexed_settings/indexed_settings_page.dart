import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/settings/indexed_settings/indexed_settings_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

class IndexedSettingsPage extends GetView<IndexedSettingsController> {
  const IndexedSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("主页设置"),
      ),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "主页排序 (长按拖动排序，重启后生效)",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: controller.updateHomeSort,
                children: controller.homeSort.map(
                  (key) {
                    var e = Constant.allHomePages[key]!;
                    return ListTile(
                      key: ValueKey(e.title),
                      title: Text(e.title),
                      visualDensity: VisualDensity.compact,
                      leading: Icon(e.iconData),
                      trailing: const Icon(Icons.drag_handle),
                    );
                  },
                ).toList(),
              ),
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("平台显示与排序", style: Get.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  "显示和排序立即生效；长按平台行或拖动手柄排序",
                  style: Get.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SettingsCard(
            child: Obx(
              () => ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: controller.updateSiteSort,
                children: controller.siteSort.asMap().entries.map(
                  (entry) {
                    final index = entry.key;
                    final key = entry.value;
                    var e = Sites.allSites[key]!;
                    final visible = controller.isSiteVisible(e.id);
                    final isLastVisible =
                        visible && controller.visibleSiteCount <= 1;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(e.id),
                      index: index,
                      child: ListTile(
                        visualDensity: VisualDensity.compact,
                        title: Text(e.name),
                        subtitle:
                            isLastVisible ? const Text("至少保留一个平台显示") : null,
                        leading: Image.asset(
                          e.logo,
                          width: 24,
                          height: 24,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              key: ValueKey("platform-visibility-${e.id}"),
                              value: visible,
                              onChanged: isLastVisible
                                  ? null
                                  : (value) => controller.setSiteVisible(
                                        e.id,
                                        value,
                                      ),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
