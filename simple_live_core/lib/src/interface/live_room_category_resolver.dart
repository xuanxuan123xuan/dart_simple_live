import '../model/live_category.dart';
import '../model/live_room_detail.dart';

/// Optional capability for sites whose room tags need provider-specific lookup.
abstract interface class LiveRoomCategoryResolver {
  /// Returns a category accepted by the site's category-room endpoint.
  /// Missing or ambiguous tags return null; lookup failures throw CoreError.
  Future<LiveSubCategory?> resolveRoomCategory(LiveRoomDetail detail);
}
