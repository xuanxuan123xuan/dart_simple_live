import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class HomeListController extends BasePageController<LiveRoomItem> {
  final Site site;
  bool _hasMore = false;

  HomeListController(this.site);

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    var result = await site.liveSite.getRecommendRooms(page: page);
    _hasMore = result.hasMore;
    return result.items;
  }

  @override
  bool hasMoreForPage({
    required List<LiveRoomItem> items,
    required int page,
    required int pageSize,
  }) {
    return _hasMore;
  }
}
