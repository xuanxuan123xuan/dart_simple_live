import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';

class MultiRoomItem {
  final Site site;
  final String roomId;
  final String userName;
  final String face;

  const MultiRoomItem({
    required this.site,
    required this.roomId,
    required this.userName,
    required this.face,
  });

  factory MultiRoomItem.fromFollow(FollowUser item) {
    return MultiRoomItem(
      site: Sites.allSites[item.siteId]!,
      roomId: item.roomId,
      userName: item.userName,
      face: item.face,
    );
  }

  String get key => "${site.id}_$roomId";
}

class MultiRoomLaunchArgs {
  final List<MultiRoomItem> rooms;
  final bool returnToLiveRoom;

  const MultiRoomLaunchArgs({
    required this.rooms,
    this.returnToLiveRoom = false,
  });
}

class MultiRoomOpenSingleResult {
  final MultiRoomItem room;

  const MultiRoomOpenSingleResult(this.room);
}
