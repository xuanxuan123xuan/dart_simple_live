import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/hot_live/hot_live_controller.dart';
import 'package:simple_live_tv_app/modules/search/search_controller_base.dart';

class SearchRoomController extends TvSearchController<LiveRoomItemExt> {
  SearchRoomController(super.keyword);

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
  Future<TvSearchPageResult<LiveRoomItemExt>> getSearchData(
    Site site,
    int page,
    CoreCancellation cancellation,
  ) async {
    final result = await site.liveSite.searchRooms(
      keyword,
      page: page,
      cancellation: cancellation,
    );
    return TvSearchPageResult(
      items: result.items
          .map(
            (item) => LiveRoomItemExt(
              roomId: item.roomId,
              title: item.title,
              cover: item.cover,
              userName: item.userName,
              online: item.online,
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
