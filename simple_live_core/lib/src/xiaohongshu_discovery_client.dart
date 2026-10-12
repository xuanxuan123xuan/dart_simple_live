import 'model/live_anchor_item.dart';
import 'model/live_category.dart';
import 'model/live_category_result.dart';
import 'model/live_room_item.dart';
import 'model/live_search_result.dart';

/// Directory responses must be captured and validated before they are enabled.
/// Ordinary note/user search results are deliberately never used as live cards.
class XiaohongshuDiscoveryClient {
  static const unavailableReason = '当前只能通过直播链接进入';
  bool get isAvailable => false;
  static const unavailableMetadata = LiveSearchMetadata(
    continuation: SearchContinuation.unknown,
    origin: SearchOrigin.fallback,
  );

  Future<List<LiveCategory>> getCategories() async => [];
  Future<LiveCategoryResult> getRooms() async =>
      LiveCategoryResult(hasMore: false, items: <LiveRoomItem>[]);
  Future<LiveSearchRoomResult> searchRooms() async => LiveSearchRoomResult(
        items: <LiveRoomItem>[],
        metadata: unavailableMetadata,
      );
  Future<LiveSearchAnchorResult> searchAnchors() async =>
      LiveSearchAnchorResult(
        items: <LiveAnchorItem>[],
        metadata: unavailableMetadata,
      );
}
