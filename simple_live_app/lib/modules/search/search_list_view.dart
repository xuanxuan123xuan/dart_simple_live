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
  const SearchListView({
    required this.controller,
    required this.topClearance,
    Key? key,
  }) : super(key: key);

  final SearchListController controller;
  final double topClearance;

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
        () {
          final headerSlivers = <Widget>[
            SliverToBoxAdapter(child: SizedBox(height: topClearance)),
            if (controller.site.id == "douyin" &&
                controller.searchMode.value == 1 &&
                !controller.pageEmpty.value)
              const SliverToBoxAdapter(child: DouyinAnchorSearchNotice()),
          ];
          return Column(
            children: [
              Expanded(
                child: controller.searchMode.value == 0
                    ? PageGridView(
                        pageController: controller,
                        padding: AppStyle.edgeInsetsA12,
                        headerSlivers: headerSlivers,
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
                        headerSlivers: headerSlivers,
                        firstRefresh: false,
                        emptyWidget: controller.site.id == "douyin"
                            ? const DouyinAnchorSearchEmpty()
                            : null,
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
          );
        },
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
                  ? (item.liveStatus ? "直播中 · 来自直播间搜索" : "未开播 · 来自直播间搜索")
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

class DouyinAnchorSearchNotice extends StatelessWidget {
  const DouyinAnchorSearchNotice({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: Colors.grey,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "仅匹配正在直播的抖音主播，未开播不会显示。",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class DouyinAnchorSearchEmpty extends StatelessWidget {
  const DouyinAnchorSearchEmpty({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.grey),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "没有匹配到正在直播的抖音主播。",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
