import 'package:simple_live_core/simple_live_core.dart';

/// Keeps share-link metadata scoped to the room that supplied it.
class LiveRoomDetailLoader {
  LiveRoomDetailLoader({
    required LiveSite site,
    required String roomId,
    String? douyinSecUserId,
  }) {
    final secUserId = douyinSecUserId?.trim();
    if (site is DouyinSite && secUserId != null && secUserId.isNotEmpty) {
      _douyinSite = site;
      _douyinRoomId = roomId;
      _douyinSecUserId = secUserId;
    }
  }

  DouyinSite? _douyinSite;
  String? _douyinRoomId;
  String? _douyinSecUserId;

  void clearDouyinShareContext() {
    _douyinSite = null;
    _douyinRoomId = null;
    _douyinSecUserId = null;
  }

  Future<LiveRoomDetail> load({
    required LiveSite site,
    required String roomId,
    KuaishouRequestSource? source,
  }) async {
    if (!identical(site, _douyinSite) || roomId != _douyinRoomId) {
      clearDouyinShareContext();
    }
    final secUserId = _douyinSecUserId;
    Future<LiveRoomDetail> fetch() => site is DouyinSite
        ? site.getRoomDetail(roomId: roomId, secUserId: secUserId)
        : site.getRoomDetail(roomId: roomId);

    final detail = await (source == null
        ? fetch()
        : KuaishouRequestTrace.run(source, fetch));
    if (detail.roomId != roomId &&
        identical(site, _douyinSite) &&
        roomId == _douyinRoomId) {
      clearDouyinShareContext();
    }
    return detail;
  }
}
