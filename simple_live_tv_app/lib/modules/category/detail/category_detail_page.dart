import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/modules/category/detail/category_detail_controller.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';
import 'package:simple_live_tv_app/widgets/card/live_room_card.dart';
import 'package:simple_live_tv_app/widgets/net_image.dart';
import 'package:simple_live_tv_app/widgets/status/app_empty_widget.dart';
import 'package:simple_live_tv_app/widgets/status/app_error_widget.dart';
import 'package:simple_live_tv_app/widgets/highlight_widget.dart';

class CategoryDetailPage extends GetView<CategoryDetailController> {
  const CategoryDetailPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      controller.navigationRevision.value;
      return PopScope(
        canPop: !controller.canHandleBackInternally,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) controller.handleBack();
        },
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && _isBackKey(event.logicalKey)) {
              controller.handleBack();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: _buildScaffold(),
        ),
      );
    });
  }

  Widget _buildScaffold() {
    return AppScaffold(
      child: Column(
        children: [
          AppStyle.vGap32,
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: controller.backFocusNode,
                iconData: Icons.arrow_back,
                text: "返回",
                autofocus: true,
                onTap: controller.handleBack,
              ),
              AppStyle.hGap32,
              Obx(() {
                controller.navigationRevision.value;
                return Text(
                  controller.pageTitle,
                  style: AppStyle.titleStyleWhite.copyWith(
                    fontSize: 36.w,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }),
              AppStyle.hGap24,
              const Spacer(),
              Obx(
                () => Visibility(
                  visible: controller.loadding.value,
                  child: SizedBox(
                    width: 48.w,
                    height: 48.w,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 4.w,
                    ),
                  ),
                ),
              ),
              AppStyle.hGap48,
            ],
          ),
          AppStyle.vGap24,
          Expanded(
            child: Obx(() {
              controller.navigationRevision.value;
              if (controller.isCategorySelection) {
                return _buildChildCategories();
              }
              if (controller.pageError.value) {
                return AppErrorWidget(
                  errorMsg: controller.errorMsg.value,
                  onRefresh: controller.refreshData,
                );
              }
              if (controller.pageEmpty.value && !controller.loadding.value) {
                return AppEmptyWidget(
                  text: "暂无主播，请稍后再试",
                  onRefresh: controller.refreshData,
                );
              }
              return MasonryGridView.count(
                key: ValueKey('rooms-${controller.currentSubCategory.id}'),
                padding: AppStyle.edgeInsetsA48,
                itemCount: controller.list.length,
                crossAxisCount: 5,
                crossAxisSpacing: 48.w,
                mainAxisSpacing: 40.w,
                controller: controller.scrollController,
                itemBuilder: (_, index) {
                  final item = controller.list[index];
                  return LiveRoomCard(
                    cover: item.cover,
                    anchor: item.userName,
                    title: item.title,
                    focusNode: item.focusNode,
                    roomId: item.roomId,
                    online: item.online,
                    onTap: () {
                      AppNavigator.toLiveRoomDetail(
                        site: controller.site,
                        roomId: item.roomId,
                      );
                    },
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildChildCategories() {
    final children = controller.currentChildren;
    return GridView.builder(
      key: ValueKey('categories-${controller.currentSubCategory.id}'),
      padding: AppStyle.edgeInsetsA48,
      controller: controller.scrollController,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        crossAxisSpacing: 36.w,
        mainAxisSpacing: 36.w,
        childAspectRatio: 1.2,
      ),
      itemCount: children.length + 1,
      itemBuilder: (_, index) {
        if (index == 0) {
          return _buildCategoryTile(
            name: '全部',
            pic: controller.currentSubCategory.pic,
            focusNode: controller.currentLevel.allFocusNode,
            onTap: controller.openAllRooms,
          );
        }

        final child = children[index - 1];
        return _buildCategoryTile(
          name: child.name,
          pic: child.pic,
          focusNode: child.focusNode,
          onTap: () => controller.openSubCategory(child),
        );
      },
    );
  }

  Widget _buildCategoryTile({
    required String name,
    required String? pic,
    required AppFocusNode focusNode,
    required VoidCallback onTap,
  }) {
    final image = (pic ?? '').trim();
    return HighlightWidget(
      focusNode: focusNode,
      onTap: onTap,
      onFocusChange: (focused) {
        if (focused) controller.rememberFocus(focusNode);
      },
      color: Colors.white10,
      borderRadius: AppStyle.radius16,
      child: Obx(() => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              image.isNotEmpty
                  ? NetImage(
                      image,
                      width: 64.w,
                      height: 64.w,
                      borderRadius: 16.w,
                      cacheWidth: 100,
                    )
                  : Icon(
                      name == '全部' ? Icons.grid_view_rounded : Icons.dashboard,
                      size: 64.w,
                      color: focusNode.isFoucsed.value
                          ? Colors.black
                          : Colors.white,
                    ),
              AppStyle.vGap12,
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: focusNode.isFoucsed.value
                    ? AppStyle.textStyleBlack
                    : AppStyle.textStyleWhite,
              ),
            ],
          )),
    );
  }

  bool _isBackKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.backspace ||
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.browserBack;
}
