import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_core/simple_live_core.dart';

class CategoryDetailController extends BasePageController<LiveRoomItem> {
  final Site site;
  final LiveSubCategory subCategory;
  final RoomSelectionCallback? onRoomSelected;
  final String? excludedRoomId;
  bool _hasMore = false;
  CategoryDetailController({
    required this.site,
    required this.subCategory,
    this.onRoomSelected,
    this.excludedRoomId,
  });

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    var result = await site.liveSite.getCategoryRooms(subCategory, page: page);
    _hasMore = result.hasMore;
    return result.items
        .where((item) => item.roomId != excludedRoomId)
        .toList();
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
