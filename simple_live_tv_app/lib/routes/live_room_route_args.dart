import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_channel.dart';

class LiveRoomRouteArgs {
  const LiveRoomRouteArgs({
    required this.site,
    required this.roomId,
    this.douyinSecUserId,
    this.xiaohongshuHostId,
    this.channels = const <LiveRoomChannel>[],
  });

  final Site site;
  final String roomId;
  final String? douyinSecUserId;
  final String? xiaohongshuHostId;
  final List<LiveRoomChannel> channels;
}
