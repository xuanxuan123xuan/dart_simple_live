import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/modules/category/detail/category_detail_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/live_room_grid_layout.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_app/widgets/shadow_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

class CategoryDetailPage extends GetView<CategoryDetailController> {
  final String? controllerTag;

  const CategoryDetailPage({this.controllerTag, Key? key}) : super(key: key);

  @override
  String? get tag => controllerTag;

  @override
  Widget build(BuildContext context) {
    if (controller.subCategory.hasChildren) {
      return _buildChildCategories(context);
    }
    // Masonry 自适应高度，mainAxisExtent 仅 useFixedGrid 预留。
    final layout = LiveRoomGridLayout.resolve(
      MediaQuery.sizeOf(context).width,
      detailsExtent: 0,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(controller.subCategory.name),
      ),
      body: KeepAliveWrapper(
        child: PageGridView(
          pageController: controller,
          padding: AppStyle.edgeInsetsA12,
          firstRefresh: true,
          mainAxisSpacing: LiveRoomGridLayout.defaultSpacing,
          crossAxisSpacing: LiveRoomGridLayout.defaultSpacing,
          crossAxisCount: layout.crossAxisCount,
          itemBuilder: (_, i) {
            var item = controller.list[i];
            return LiveRoomCard(
              controller.site,
              item,
              onTap: controller.onRoomSelected == null
                  ? null
                  : () {
                      final onRoomSelected = controller.onRoomSelected!;
                      Get.back();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        onRoomSelected(controller.site, item.roomId);
                      });
                    },
            );
          },
        ),
      ),
    );
  }

  Widget _buildChildCategories(BuildContext context) {
    final children = controller.subCategory.children;
    // 上级分类插入的自身副本会与本页重复，这里过滤掉。
    final subCategories =
        children.where((item) => item.id != controller.subCategory.id).toList();
    final crossAxisCount =
        (MediaQuery.sizeOf(context).width ~/ 96).clamp(1, 12).toInt();
    return Scaffold(
      appBar: AppBar(
        title: Text(controller.subCategory.name),
      ),
      body: GridView.builder(
        padding: AppStyle.edgeInsetsA12,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.15,
        ),
        itemCount: subCategories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildChildTile(
              context,
              name: "全部",
              pic: controller.subCategory.pic,
              icon: Icons.grid_view_rounded,
              onTap: () {
                AppNavigator.toCategoryDetail(
                  site: controller.site,
                  category: LiveSubCategory(
                    id: controller.subCategory.id,
                    name: controller.subCategory.name,
                    parentId: controller.subCategory.parentId,
                    pic: controller.subCategory.pic,
                  ),
                  onRoomSelected: controller.onRoomSelected,
                  excludedRoomId: controller.excludedRoomId,
                );
              },
            );
          }
          final child = subCategories[index - 1];
          return _buildChildTile(
            context,
            name: child.name,
            pic: child.pic,
            icon: _categoryIcon(child.name),
            onTap: () {
              AppNavigator.toCategoryDetail(
                site: controller.site,
                category: child,
                onRoomSelected: controller.onRoomSelected,
                excludedRoomId: controller.excludedRoomId,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildChildTile(
    BuildContext context, {
    required String name,
    required String? pic,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final image = (pic ?? "").trim();
    return ShadowCard(
      backgroundColor: Colors.transparent,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          image.isNotEmpty
              ? NetImage(
                  image,
                  width: 40,
                  height: 40,
                  borderRadius: 8,
                )
              : _buildFallbackIcon(context, icon),
          AppStyle.vGap4,
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackIcon(BuildContext context, IconData icon) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(40)),
        color: color.withAlpha(18),
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }

  /// 抖音子分区无官方图片，按名称给出语义图标兜底。
  IconData _categoryIcon(String name) {
    if (controller.site.id != Constant.kDouyin) {
      return Icons.dashboard_customize_rounded;
    }
    if (name.contains("射击") || name.contains("枪")) {
      return Icons.my_location_rounded;
    }
    if (name.contains("MOBA") || name.contains("对战")) {
      return Icons.sports_martial_arts_rounded;
    }
    if (name.contains("游戏") || name.contains("电竞")) {
      return Icons.sports_esports_rounded;
    }
    if (name.contains("音乐") || name.contains("唱")) {
      return Icons.music_note_rounded;
    }
    if (name.contains("舞")) {
      return Icons.auto_awesome_rounded;
    }
    if (name.contains("聊天") || name.contains("交友")) {
      return Icons.forum_rounded;
    }
    return Icons.grid_view_rounded;
  }
}
