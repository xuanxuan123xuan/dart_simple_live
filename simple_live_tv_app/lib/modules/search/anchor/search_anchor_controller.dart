import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/search/search_controller_base.dart';

class SearchAnchorController extends TvSearchController<LiveAnchorItemExt> {
  SearchAnchorController(super.keyword);

  @override
  void onInit() {
    scrollController.addListener(scrollListener);
    refreshData();
    super.onInit();
  }

  void scrollListener() {
    if (scrollController.position.pixels >=
        (scrollController.position.maxScrollExtent - 100.w)) {
      loadData();
    }
  }

  @override
  Future<TvSearchPageResult<LiveAnchorItemExt>> getSearchData(
    Site site,
    int page,
    CoreCancellation cancellation,
  ) async {
    final result = await site.liveSite.searchAnchors(
      keyword,
      page: page,
      cancellation: cancellation,
    );
    return TvSearchPageResult(
      items: result.items
          .map(
            (item) => LiveAnchorItemExt(
              roomId: item.roomId,
              avatar: item.avatar,
              liveStatus: item.liveStatus,
              userName: item.userName,
            ),
          )
          .toList(),
      metadata: result.metadata,
    );
  }

  @override
  void onClose() {
    scrollController.removeListener(scrollListener);
    super.onClose();
  }
}

class LiveAnchorItemExt extends LiveAnchorItem {
  LiveAnchorItemExt({
    required super.roomId,
    required super.avatar,
    required super.liveStatus,
    required super.userName,
  });

  AppFocusNode focusNode = AppFocusNode();
}
