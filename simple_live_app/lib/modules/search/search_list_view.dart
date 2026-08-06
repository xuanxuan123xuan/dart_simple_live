import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/live_room_grid_layout.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SearchListView extends StatelessWidget {
  const SearchListView({required this.controller, Key? key}) : super(key: key);

  final SearchListController controller;

  @override
  Widget build(BuildContext context) {
    // Masonry 自适应高度，mainAxisExtent 仅 useFixedGrid 预留。
    final roomLayout = LiveRoomGridLayout.resolve(
      MediaQuery.sizeOf(context).width,
      detailsExtent: 0,
    );

    var userRowCount = MediaQuery.of(context).size.width ~/ 500;
    if (userRowCount < 1) userRowCount = 1;
    return KeepAliveWrapper(
      child: Obx(
        () => Column(
          children: [
            Expanded(
              child: controller.searchMode.value == 0
                  ? PageGridView(
                      pageController: controller,
                      padding: AppStyle.edgeInsetsA12,
                      firstRefresh: false,
                      mainAxisSpacing: LiveRoomGridLayout.defaultSpacing,
                      crossAxisSpacing: LiveRoomGridLayout.defaultSpacing,
                      crossAxisCount: roomLayout.crossAxisCount,
                      showPageLoadding: true,
                      itemBuilder: (_, i) {
                        var item = controller.list[i] as LiveRoomItem;
                        return LiveRoomCard(controller.site, item);
                      },
                    )
                  : PageGridView(
                      crossAxisSpacing: 12,
                      crossAxisCount: userRowCount,
                      pageController: controller,
                      firstRefresh: false,
                      itemBuilder: (_, i) {
                        var item = controller.list[i] as LiveAnchorItem;
                        return SearchAnchorTile(
                          site: controller.site,
                          item: item,
                          metadata: controller.searchMetadata,
                        );
                      },
                    ),
            ),
            if (controller.paginationUnavailable.value)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  "分页信息不可用，已停止自动加载",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SearchAnchorTile extends StatelessWidget {
  const SearchAnchorTile({
    required this.site,
    required this.item,
    this.metadata,
    Key? key,
  }) : super(key: key);

  final Site site;
  final LiveAnchorItem item;
  final LiveSearchMetadata? metadata;

  @override
  Widget build(BuildContext context) {
    final isDerived = metadata?.origin == SearchOrigin.derived;
    return ListTile(
      leading: NetImage(
        item.avatar,
        width: 48,
        height: 48,
        borderRadius: 24,
      ),
      title: Text(
        item.userName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: item.liveStatus ? Colors.green : Colors.grey,
              borderRadius: AppStyle.radius12,
            ),
          ),
          AppStyle.hGap4,
          Flexible(
            child: Text(
              isDerived
                  ? (item.liveStatus ? "直播中 · 派生结果" : "未开播 · 派生结果")
                  : (item.liveStatus ? "直播中" : "未开播"),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: item.liveStatus ? null : Colors.grey,
              ),
            ),
          ),
        ],
      ),
      onTap: () => AppNavigator.toLiveRoomDetail(
        site: site,
        roomId: item.roomId,
      ),
    );
  }
}
