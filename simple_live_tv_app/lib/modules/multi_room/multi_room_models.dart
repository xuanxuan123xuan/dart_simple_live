import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/models/db/history.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';

class MultiRoomItem {
  final Site site;
  final String roomId;
  final String userName;
  final String face;
  final String? douyinSecUserId;
  final String? xiaohongshuHostId;

  const MultiRoomItem({
    required this.site,
    required this.roomId,
    required this.userName,
    required this.face,
    this.douyinSecUserId,
    this.xiaohongshuHostId,
  });

  factory MultiRoomItem.fromFollow(FollowUser item) {
    return MultiRoomItem(
      site: Sites.allSites[item.siteId]!,
      roomId: item.roomId,
      userName: item.userName,
      face: item.face,
    );
  }

  factory MultiRoomItem.fromHistory(History item) {
    return MultiRoomItem(
      site: Sites.allSites[item.siteId]!,
      roomId: item.roomId,
      userName: item.userName,
      face: item.face,
    );
  }

  factory MultiRoomItem.fromLink(LiveRoomLinkTarget target) {
    return MultiRoomItem(
      site: target.site,
      roomId: target.roomId,
      userName: target.roomId,
      face: '',
      douyinSecUserId: target.douyinSecUserId,
      xiaohongshuHostId: target.xiaohongshuHostId,
    );
  }

  factory MultiRoomItem.fromSearchResult({
    required Site site,
    required LiveRoomItem item,
  }) {
    return MultiRoomItem(
      site: site,
      roomId: item.roomId,
      userName: item.userName,
      face: item.cover,
    );
  }

  String get key => "${site.id}_$roomId";
}
