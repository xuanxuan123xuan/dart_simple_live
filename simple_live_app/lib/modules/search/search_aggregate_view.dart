import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/search/search_aggregate_error_presentation.dart';
import 'package:simple_live_app/modules/search/search_aggregate_models.dart';
import 'package:simple_live_app/modules/search/search_list_view.dart';
import 'package:simple_live_app/modules/search/search_site_page.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/live_room_grid_layout.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SearchAggregateView extends StatelessWidget {
  const SearchAggregateView({
    required this.result,
    Key? key,
  }) : super(key: key);

  final SearchAggregateResult result;

  @override
  Widget build(BuildContext context) {
    if (result.query == null) {
      return const _AggregateMessage(
        icon: Icons.search,
        message: "输入关键词开始搜索",
        hint: "支持粘贴直播链接并直接进入直播间",
      );
    }

    return ListView.builder(
      padding: AppStyle.pagePadding(bottom: 24),
      itemCount: result.sites.length,
      itemBuilder: (context, index) {
        final state = result.sites[index];
        return _SiteSection(
          state: state,
          query: result.query!,
        );
      },
    );
  }
}

class _SiteSection extends StatelessWidget {
  const _SiteSection({
    required this.state,
    required this.query,
  });

  final SearchAggregateSiteState state;
  final SearchAggregateQuery query;

  bool get isDouyinAuthFailure =>
      SearchAggregateErrorPresentation.offersDouyinCookieConfig(
        state.site.id,
        state.error,
      );

  void openSite() {
    Get.toNamed(
      RoutePath.kSearchSite,
      arguments: SearchSiteRouteArgs(
        site: state.site,
        keyword: query.keyword,
        searchMode: query.searchMode,
        scopeId:
            "aggregate-${state.site.id}-${DateTime.now().microsecondsSinceEpoch}",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomLayout = LiveRoomGridLayout.resolve(
      MediaQuery.sizeOf(context).width,
      detailsExtent: 64,
    );
    final anchorColumns =
        (MediaQuery.sizeOf(context).width ~/ 500).clamp(1, 4).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
          child: Row(
            children: [
              Image.asset(state.site.logo, width: 22, height: 22),
              AppStyle.hGap8,
              Expanded(
                child: Text(
                  state.site.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (!state.isLoading)
                TextButton.icon(
                  onPressed: openSite,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text("查看更多"),
                ),
            ],
          ),
        ),
        if (state.isLoading)
          const _SectionStatus(
            icon: Icons.hourglass_empty,
            message: "正在加载",
          )
        else if (state.site.id == "douyin" &&
            query.searchMode == 1 &&
            state.isEmpty)
          const DouyinAnchorSearchEmpty()
        else ...[
          if (state.site.id == "douyin" && query.searchMode == 1)
            const DouyinAnchorSearchNotice(),
          if (state.isEmpty)
            const _SectionStatus(
              icon: Icons.remove_circle_outline,
              message: "暂无结果",
            )
          else if (state.hasError)
            _SectionStatus(
              icon: Icons.error_outline,
              message: SearchAggregateErrorPresentation.message(state.error),
              actionLabel: isDouyinAuthFailure ? "去配置" : null,
              onAction: isDouyinAuthFailure
                  ? AppNavigator.toDouyinCookieConfig
                  : null,
            )
          else if (query.searchMode == 0)
            MasonryGridView.count(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: math.min(
                state.items.length,
                roomLayout.crossAxisCount,
              ),
              crossAxisCount: roomLayout.crossAxisCount,
              crossAxisSpacing: LiveRoomGridLayout.defaultSpacing,
              mainAxisSpacing: LiveRoomGridLayout.defaultSpacing,
              itemBuilder: (_, index) => LiveRoomCard(
                state.site,
                state.items[index] as LiveRoomItem,
              ),
            )
          else
            GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: math.min(state.items.length, anchorColumns),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: anchorColumns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 4,
                mainAxisExtent: 80,
              ),
              itemBuilder: (_, index) => SearchAnchorTile(
                site: state.site,
                item: state.items[index] as LiveAnchorItem,
                metadata: state.metadata,
              ),
            ),
        ],
        const Divider(height: 1),
      ],
    );
  }
}

class _SectionStatus extends StatelessWidget {
  const _SectionStatus({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          AppStyle.hGap8,
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _AggregateMessage extends StatelessWidget {
  const _AggregateMessage({
    required this.icon,
    required this.message,
    this.hint,
  });

  final IconData icon;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppStyle.edgeInsetsA24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            AppStyle.vGap12,
            Text(message, textAlign: TextAlign.center),
            if (hint != null) ...[
              AppStyle.vGap12,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link, size: 18, color: Colors.grey),
                  AppStyle.hGap4,
                  Flexible(
                    child: Text(
                      hint!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
